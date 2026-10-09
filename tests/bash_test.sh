#!/usr/bin/env bash

set -euo pipefail

repo_dir=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
command_fixture=$repo_dir/tests/fixtures/bash/command
scenario_fixture=$repo_dir/tests/fixtures/bash/scenario
test_root=$(mktemp -d)
original_path=$PATH

cleanup() {
  local status=$?
  PATH=$original_path
  find "$test_root" -depth -delete
  exit "$status"
}
trap cleanup EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_contains() {
  local value=$1
  local expected=$2
  [[ $value == *"$expected"* ]] || fail "expected output to contain: $expected"
}

link_command() {
  ln -s "$command_fixture" "$test_root/bin/$1"
}

run_scenario() {
  local scenario=$1
  shift
  env TEST_REPO_DIR="$repo_dir" TEST_SCENARIO="$scenario" "$@" \
    "$scenario_fixture"
}

mkdir -p "$test_root/bin"
ln -s "$(command -v bash)" "$test_root/bin/bash"
ln -s "$(command -v grep)" "$test_root/bin/grep"
for command_name in git tmux fzf less mc; do
  link_command "$command_name"
done

set +e
check_output=$(
  env -i HOME="$test_root" PATH="$test_root/bin" \
    TEST_REPO_DIR="$repo_dir" TEST_SCENARIO=check-tools "$scenario_fixture" 2>&1
)
check_status=$?
set -e
[[ $check_status -eq 1 ]] || fail 'dotfiles-check accepted a missing required command'
assert_contains "$check_output" 'MISSING nvim'
assert_contains "$check_output" 'MISSING zoxide'

link_command nvim
for command_name in node python rg; do
  link_command "$command_name"
done
wrapper_output=$(
  run_scenario check-mc-wrapper \
    env HOME="$test_root" DOTFILES="$test_root/no-manifest" PATH="$test_root/bin"
)
assert_contains "$wrapper_output" 'mc: '
assert_contains "$wrapper_output" '(shell wrapper: alias)'

editor_output=$(
  TEST_COMMAND_MODE=editor run_scenario editor \
    env HOME="$test_root" PATH="$test_root/bin"
)
[[ $editor_output == 'app=nvim2 argc=1 first=file with space' ]] ||
  fail 'v did not preserve the Nvim2 profile or argument quoting'

set +e
missing_output=$(
  run_scenario missing-kubectl \
    env HOME="$test_root" PATH="$test_root/bin" 2>&1
)
missing_status=$?
set -e
[[ $missing_status -eq 127 ]] || fail 'missing kubectl did not return 127'
[[ $missing_output == 'dotfiles: kl requires kubectl' ]] ||
  fail 'missing dependency message was noisy or unclear'

link_command kubectl
filtered=$(
  TEST_COMMAND_MODE=filter run_scenario filter-pods \
    env HOME="$test_root" PATH="$test_root/bin"
)
assert_contains "$filtered" 'pod-a=-v'

set +e
TEST_COMMAND_MODE=failure run_scenario failed-pod-list \
  env HOME="$test_root" PATH="$test_root/bin" >/dev/null 2>&1
kpl_status=$?
set -e
[[ $kpl_status -eq 42 ]] || fail 'kpl hid kubectl get pods failure'

link_command bat
set +e
TEST_COMMAND_MODE=failure run_scenario failed-log-pipeline \
  env HOME="$test_root" PATH="$test_root/bin" >/dev/null 2>&1
kl_status=$?
set -e
[[ $kl_status -eq 42 ]] || fail 'kl hid the left side of its pipeline'

mkdir -p "$test_root/logs"
(
  cd "$test_root/logs"
  TEST_COMMAND_MODE=logs run_scenario write-pod-logs \
    env HOME="$test_root" PATH="$test_root/bin:$original_path"
  [[ $(<api-1.log) == 'logs for api-1' ]]
  [[ ! -e worker-1.log ]]
) || fail 'kpl did not write only successful matching pod logs'

reload_home=$test_root/reload-home
mkdir -p "$reload_home"
ln -s "$repo_dir/bash/.bash_aliases" "$reload_home/.bash_aliases"
reload_output=$(
  timeout 15 env HOME="$reload_home" PATH="$test_root/bin:$original_path" \
    TERM=xterm-256color TEST_REPO_DIR="$repo_dir" TEST_SCENARIO=reload \
    bash --noprofile --norc -i "$scenario_fixture" 2>&1
)
[[ $(grep -o '_dotfiles_history_sync' <<<"$reload_output" | wc -l) -eq 1 ]] ||
  fail 'history prompt hook was duplicated on reload'
[[ $(grep -o '__zoxide_hook' <<<"$reload_output" | wc -l) -le 1 ]] ||
  fail 'zoxide prompt hook was duplicated on reload'
[[ $reload_output != *'history -r'* ]] ||
  fail 'legacy full history reload remains in PROMPT_COMMAND'
[[ $reload_output != *'_dotfiles_sync_virtual_env_prompt'* ]] ||
  fail 'removed virtual environment prompt hook remains in PROMPT_COMMAND'
assert_contains "$reload_output" 'settings=100000:100000:3:on:on:on'
assert_contains "$reload_output" 'venv_disable_prompt=1'

link_command zoxide
broken_output=$(
  timeout 15 env HOME="$reload_home" PATH="$test_root/bin:$original_path" \
    TERM=xterm-256color TEST_REPO_DIR="$repo_dir" TEST_SCENARIO=broken-integration \
    bash --noprofile --norc -i "$scenario_fixture" 2>&1
)
assert_contains "$broken_output" 'dotfiles: zoxide initialization failed'
[[ $broken_output != *'command not found'* ]] ||
  fail 'broken integration emitted raw shell errors'

invalid_output=$(
  timeout 15 env HOME="$reload_home" PATH="$test_root/bin:$original_path" \
    TERM=xterm-256color TEST_REPO_DIR="$repo_dir" TEST_SCENARIO=invalid-integration \
    bash --noprofile --norc -i "$scenario_fixture" 2>&1
)
assert_contains "$invalid_output" 'dotfiles: zoxide returned invalid shell initialization'
assert_contains "$invalid_output" 'continued=yes'
[[ $invalid_output != *'syntax error'* ]] ||
  fail 'invalid integration emitted raw shell errors'

agent_home=$test_root/agent-home
agent_bin=$test_root/agent-bin
agent_log=$test_root/agent.log
mkdir -p "$agent_home/.ssh" "$agent_bin"
printf 'invalid key\n' >"$agent_home/.ssh/github"
chmod 600 "$agent_home/.ssh/github"
printf ':\n' >"$agent_home/.bashrc"
ln -s "$command_fixture" "$agent_bin/ssh-agent"
ln -s "$command_fixture" "$agent_bin/ssh-add"

profile_output=$(
  env -i HOME="$agent_home" PATH="$agent_bin:/usr/bin:/bin" \
    TEST_AGENT_LOG="$agent_log" TEST_COMMAND_MODE=agent \
    TEST_REPO_DIR="$repo_dir" TEST_SCENARIO=failed-agent-key \
    "$scenario_fixture" 2>&1
)
assert_contains "$profile_output" 'profile_status=0 sock=unset pid=unset'
[[ ! -e $agent_log ]] || fail 'login profile started an ssh-agent'

stale_output=$(
  env -i HOME="$agent_home" PATH=/usr/bin:/bin SSH_AUTH_SOCK=/missing/agent.sock \
    TEST_REPO_DIR="$repo_dir" TEST_SCENARIO=stale-agent-socket \
    "$scenario_fixture" 2>&1
)
assert_contains "$stale_output" 'dotfiles: SSH_AUTH_SOCK is not a socket: /missing/agent.sock'
assert_contains "$stale_output" 'stale_status=0 sock=unset'

link_command vi
link_command vim
editor_log=$test_root/editors.log
independent_output=$(
  TEST_COMMAND_MODE=independent TEST_EDITOR_LOG="$editor_log" \
    run_scenario independent-editors \
    env HOME="$reload_home" PATH="$test_root/bin:$original_path" TERM=xterm-256color \
    bash --noprofile --norc -i
)
assert_contains "$independent_output" 'cat=file vi=function vim=alias v=function'
assert_contains "$(<"$editor_log")" 'vi:first'
assert_contains "$(<"$editor_log")" 'vim:second'

git_home=$test_root/git-home
git_bin=$test_root/git-bin
git_editor_log=$test_root/git-editor.log
mkdir -p "$git_home" "$git_bin"
cp "$repo_dir/git/.gitconfig" "$git_home/.gitconfig"
cp "$repo_dir/tests/fixtures/bash/git-editor" "$git_bin/vi"
chmod 0755 "$git_bin/vi"
ln -s "$(PATH="$original_path" command -v git)" "$git_bin/git"
timeout 15s env -u GIT_EDITOR -u GIT_CONFIG_PARAMETERS -u GIT_CONFIG_COUNT \
  HOME="$git_home" PATH="$git_bin:/usr/bin:/bin" TERM=xterm-256color \
  GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="$git_home/.gitconfig" \
  TEST_GIT_EDITOR_LOG="$git_editor_log" TEST_REPO_DIR="$repo_dir" \
  TEST_SCENARIO=git-editor bash --noprofile --norc -i "$scenario_fixture"
[[ $(<"$git_editor_log") == 'editor=vi visual=vi' ]] ||
  fail 'Git commit or shell editor defaults did not use system vi'

checkout_with_spaces="$test_root/checkout with spaces"
mkdir -p "$checkout_with_spaces/scripts"
custom_output=$(
  run_scenario custom-dotfiles \
    env HOME="$reload_home" DOTFILES="$checkout_with_spaces" \
    PATH="$test_root/bin:$original_path" TERM=xterm-256color \
    bash --noprofile --norc -i
)
assert_contains "$custom_output" "dotfiles=$checkout_with_spaces pwd=$checkout_with_spaces"

transition_home="$test_root/transition home"
transition_connected="$test_root/connected checkout/dotfiles"
transition_a="$transition_home/dotfiles-releases/dotfiles-aaaaaaaaaaaa"
transition_b="$transition_home/dotfiles-releases/dotfiles-bbbbbbbbbbbb"
mkdir -p "$transition_home/.asdf/shims"
ln -s "$command_fixture" "$transition_home/.asdf/shims/terragrunt"
for root in "$transition_connected" "$transition_a/dotfiles" "$transition_b/dotfiles"; do
  mkdir -p "$root/bash" "$root/scripts"
  cp "$repo_dir/bash/.bashrc" "$root/bash/.bashrc"
done
printf 'RELEASE_ID=dotfiles-aaaaaaaaaaaa\n' >"$transition_a/release.env"
printf 'RELEASE_ID=dotfiles-bbbbbbbbbbbb\n' >"$transition_b/release.env"
printf '#!/usr/bin/env bash\nprintf "connected\\n"\n' \
  >"$transition_connected/scripts/snapshot-marker"
printf '#!/usr/bin/env bash\nprintf "release-a\\n"\n' \
  >"$transition_a/dotfiles/scripts/snapshot-marker"
printf '#!/usr/bin/env bash\nprintf "release-b\\n"\n' \
  >"$transition_b/dotfiles/scripts/snapshot-marker"
chmod 0755 "$transition_connected/scripts/snapshot-marker" \
  "$transition_a/dotfiles/scripts/snapshot-marker" \
  "$transition_b/dotfiles/scripts/snapshot-marker"
transition_output=$(
  run_scenario root-transition \
    env HOME="$transition_home" PATH="$test_root/bin:$original_path" \
    TERM=xterm-256color TEST_CONNECTED_ROOT="$transition_connected" \
    TEST_RELEASE_A="$transition_a" TEST_RELEASE_B="$transition_b" \
    bash --noprofile --norc -i
)
assert_contains "$transition_output" \
  "connected=$transition_connected:unset:connected"
assert_contains "$transition_output" \
  "release-a=$transition_a/dotfiles:$transition_a:release-a"
assert_contains "$transition_output" \
  "release-b=$transition_b/dotfiles:$transition_b:release-b"
assert_contains "$transition_output" \
  "rollback-a=$transition_a/dotfiles:$transition_a:release-a"
assert_contains "$transition_output" \
  "baseline=$transition_connected:unset:connected"
assert_contains "$transition_output" \
  "connected-asdf=$transition_home/.asdf/shims/terragrunt"
assert_contains "$transition_output" 'offline-asdf=absent'
assert_contains "$transition_output" \
  "baseline-asdf=$transition_home/.asdf/shims/terragrunt"

custom_root="$test_root/custom root"
second_custom_root="$test_root/second custom root"
mkdir -p "$custom_root/scripts" "$second_custom_root/scripts"
override_output=$(
  run_scenario root-override \
    env HOME="$transition_home" PATH="$test_root/bin:$original_path" \
    TERM=xterm-256color TEST_CONNECTED_ROOT="$transition_connected" \
    TEST_RELEASE_A="$transition_a" TEST_RELEASE_B="$transition_b" \
    TEST_CUSTOM_ROOT="$custom_root" TEST_SECOND_CUSTOM_ROOT="$second_custom_root" \
    bash --noprofile --norc -i
)
assert_contains "$override_output" "override-before=$custom_root:unset"
assert_contains "$override_output" "override-during=$second_custom_root:unset"
assert_contains "$override_output" "legacy-before-reset=$transition_a/dotfiles"
assert_contains "$override_output" "legacy-after-reset=$transition_connected"

launcher_environment_output=$(
  run_scenario launcher-environment \
    env HOME="$transition_home" PATH="$test_root/bin:$original_path" \
    TERM=xterm-256color \
    XDG_CONFIG_HOME="$transition_a/config" XDG_DATA_HOME="$transition_a/share" \
    _ZO_DATA_DIR="$test_root/user data/zoxide" \
    DOTFILES_LAUNCHER_XDG_CONFIG_HOME_SET=1 \
    DOTFILES_LAUNCHER_XDG_CONFIG_HOME="$test_root/user config" \
    DOTFILES_LAUNCHER_XDG_DATA_HOME_SET=1 \
    DOTFILES_LAUNCHER_XDG_DATA_HOME="$test_root/user data" \
    DOTFILES_LAUNCHER_ZO_DATA_DIR_SET=0 \
    bash --noprofile --norc -i
)
assert_contains "$launcher_environment_output" \
  "xdg-config=$test_root/user config xdg-data=$test_root/user data zoxide=unset markers="

launcher_unset_output=$(
  run_scenario launcher-environment \
    env -u XDG_CONFIG_HOME -u XDG_DATA_HOME -u _ZO_DATA_DIR \
    HOME="$transition_home" PATH="$test_root/bin:$original_path" \
    TERM=xterm-256color \
    DOTFILES_LAUNCHER_XDG_CONFIG_HOME_SET=0 \
    DOTFILES_LAUNCHER_XDG_DATA_HOME_SET=0 \
    DOTFILES_LAUNCHER_ZO_DATA_DIR_SET=0 \
    bash --noprofile --norc -i
)
assert_contains "$launcher_unset_output" \
  'xdg-config=unset xdg-data=unset zoxide=unset markers='

path_home=$test_root/path-home
mkdir -p "$path_home/.venv/bin" "$path_home/.asdf/shims" "$path_home/bin"
ln -s "$command_fixture" "$path_home/.venv/bin/python"
ln -s "$command_fixture" "$path_home/.asdf/shims/terraform"
ln -s "$command_fixture" "$path_home/bin/terraform"
path_output=$(
  run_scenario path-order \
    env HOME="$path_home" VIRTUAL_ENV="$path_home/.venv" \
    PATH="$path_home/bin:$original_path" TERM=xterm-256color \
    bash --noprofile --norc -i
)
assert_contains "$path_output" "python=$path_home/.venv/bin/python"
assert_contains "$path_output" "terraform=$path_home/.asdf/shims/terraform"
path_line=$(grep '^path=' <<<"$path_output")
[[ ${path_line#path=} == "$path_home/.venv/bin:"* ]] ||
  fail 'active virtual environment lost PATH precedence'

brew_home=$test_root/brew-home
brew_bin=$test_root/existing-homebrew/bin
brew_log=$test_root/brew.log
mkdir -p "$brew_home" "$brew_bin"
ln -s "$command_fixture" "$brew_bin/brew"
TEST_BREW_LOG="$brew_log" run_scenario reload \
  env HOME="$brew_home" PATH="$brew_bin:$test_root/bin:$original_path" \
  TERM=xterm-256color bash --noprofile --norc -i >/dev/null 2>&1
[[ ! -e $brew_log ]] || fail 'Bash startup invoked Homebrew'

fzf_output=$(
  TEST_COMMAND_MODE=fzf-init run_scenario fzf-init \
    env HOME="$reload_home" PATH="$test_root/bin:$original_path" TERM=xterm-256color \
    bash --noprofile --norc -i
)
assert_contains "$fzf_output" 'fzf-init=yes'

stale_vz_output=$(
  run_scenario stale-vz \
    env HOME="$reload_home" PATH="$test_root/bin:$original_path"
)
[[ $stale_vz_output == 'editors=v,vold vz=removed' ]] ||
  fail 'alias reload did not remove stale vz while preserving v and vold'

posh_log=$test_root/oh-my-posh.log
posh_state=$test_root/kubectl-prompt-disabled
ln -s "$command_fixture" "$test_root/bin/oh-my-posh"
ln -s "$repo_dir/oh-my-posh/.oh-my-posh.omp.json" \
  "$reload_home/.oh-my-posh.omp.json"
kube_init_output=$(
  TEST_COMMAND_MODE=kube-prompt TEST_POSH_LOG="$posh_log" \
    TEST_POSH_STATE="$posh_state" run_scenario kube-prompt-init \
    env HOME="$reload_home" PATH="$test_root/bin:$original_path" \
    TERM=xterm-256color bash --noprofile --norc -i
)
assert_contains "$kube_init_output" 'kube-default=disabled'
[[ $(grep -c '^init bash ' "$posh_log") -eq 1 ]] ||
  fail 'Oh My Posh was initialized more than once on Bash reload'
[[ $(grep -c '^toggle kubectl$' "$posh_log") -eq 1 ]] ||
  fail 'Kubernetes prompt default was not initialized exactly once'

kube_toggle_output=$(
  TEST_COMMAND_MODE=kube-prompt TEST_POSH_LOG="$posh_log" \
    TEST_POSH_STATE="$posh_state" run_scenario kube-prompt-toggle \
    env HOME="$reload_home" PATH="$test_root/bin:$original_path"
)
assert_contains "$kube_toggle_output" 'Kubernetes prompt enabled'
assert_contains "$kube_toggle_output" 'Kubernetes prompt disabled'
[[ $(grep -c '^get toggles$' "$posh_log") -eq 2 ]] ||
  fail 'kp did not inspect the native Oh My Posh toggle state'
[[ $(grep -c '^toggle kubectl$' "$posh_log") -eq 3 ]] ||
  fail 'kp did not toggle the Kubernetes segment twice'

printf 'Bash tests passed\n'
