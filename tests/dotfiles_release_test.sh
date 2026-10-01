#!/usr/bin/env bash

set -euo pipefail

repo_dir=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
test_root=$(mktemp -d)
os_release=$test_root/os-release

cleanup() {
  find "$test_root" -depth -delete
}
trap cleanup EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_link() {
  local path=$1 target=$2
  [[ -L $path ]] || fail "$path is not a symlink"
  [[ $(readlink -- "$path") == "$target" ]] ||
    fail "$path does not point to $target"
}

printf 'ID=debian\nVERSION_ID=13\n' >"$os_release"

write_fake_tool() {
  local path=$1
  mkdir -p "$(dirname -- "$path")"
  cat >"$path" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
self=$(readlink -f -- "$0")
if [[ ${1:-} == hold ]]; then
  printf 'before=%s\n' "$self" >"$2"
  sleep 2
  printf 'after=%s\n' "$self" >>"$2"
  exit 0
fi
printf '%s fixture 1.0\n' "$(basename -- "$0")"
EOF
  chmod 0755 "$path"
}

write_fake_python() {
  local path=$1
  mkdir -p "$(dirname -- "$path")"
  cat >"$path" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ " $* " == *' -m venv '* ]]; then
  destination=${!#}
  mkdir -p "$destination/bin"
  printf 'home = fixture\n' >"$destination/pyvenv.cfg"
  cp "$0" "$destination/bin/python"
  for command_name in ansible ansible-config ansible-lint ansible-playbook yamllint; do
    printf '#!/usr/bin/env bash\nprintf "%%s fixture 1.0\\n" "$(basename -- "$0")"\n' \
      >"$destination/bin/$command_name"
    chmod 0755 "$destination/bin/$command_name"
  done
fi
exit 0
EOF
  chmod 0755 "$path"
}

make_artifact() {
  local commit=$1 marker=$2 destination=$3
  local id=dotfiles-${commit:0:12}
  local stage=$test_root/stage-$marker release=$test_root/stage-$marker/$id
  local command_name plugin plugin_dir

  mkdir -p "$release/bin" "$release/config/nvim2/tests" \
    "$release/dotfiles/bash" "$release/dotfiles/git" \
    "$release/dotfiles/tmux" "$release/dotfiles/vim" \
    "$release/dotfiles/oh-my-posh" \
    "$release/dotfiles/k9s/.config/k9s/skins" \
    "$release/share/nvim2/mason/bin" "$release/share/nvim2/mason/packages/ansible-lint" \
    "$release/share/nvim2/mason/packages/yamllint" \
    "$release/python-wheelhouse" "$release/share/tmux/plugins" \
    "$release/tools/bin" "$release/tools/nvim/bin" "$release/tools/tmux/bin"

  cp "$repo_dir/scripts/dotfiles-release" "$release/dotfiles-release"
  chmod 0755 "$release/dotfiles-release"
  ln -s ../dotfiles-release "$release/bin/dotfiles-release"
  for command_name in nvim tmux; do write_fake_tool "$release/tools/$command_name/bin/$command_name"; done
  write_fake_python "$release/tools/python-3.12.12/bin/python3"
  for command_name in node npm npx corepack rg zoxide k9s kubectx kubens \
    oh-my-posh task fzf terraform; do
    write_fake_tool "$release/tools/bin/$command_name"
    ln -s "../tools/bin/$command_name" "$release/bin/$command_name"
  done
  ln -s ../tools/python-3.12.12/bin/python3 "$release/bin/python"
  ln -s ../tools/python-3.12.12/bin/python3 "$release/bin/python3"
  # The generated launchers intentionally expand these expressions at runtime.
  # shellcheck disable=SC2016
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    'self=$(readlink -f -- "$0")' \
    'release=${self%/bin/nvim}' \
    'export NVIM_APPNAME=${NVIM_APPNAME:-nvim2}' \
    'exec "$release/tools/nvim/bin/nvim" "$@"' >"$release/bin/nvim"
  # shellcheck disable=SC2016
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    'self=$(readlink -f -- "$0")' \
    'release=${self%/bin/tmux}' \
    'config="$release/dotfiles/tmux/.tmux.conf"' \
    'export TMUX_OFFLINE_RELEASE_ROOT="$release"' \
    'export TMUX_OFFLINE_CONFIG="$config"' \
    'exec "$release/tools/tmux/bin/tmux" "$@"' >"$release/bin/tmux"
  chmod 0755 "$release/bin/nvim" "$release/bin/tmux"
  for plugin in tmux-sensible tmux-resurrect tmux-continuum; do
    plugin_dir=$release/share/tmux/plugins/$plugin
    mkdir -p "$plugin_dir"
    printf 'fixture %s\n' "$plugin" >"$plugin_dir/${plugin#tmux-}.tmux"
    git -C "$plugin_dir" init -q
    git -C "$plugin_dir" remote add origin "https://github.com/tmux-plugins/$plugin.git"
    git -C "$plugin_dir" add .
    GIT_AUTHOR_NAME=fixture GIT_AUTHOR_EMAIL=fixture@example.invalid \
      GIT_COMMITTER_NAME=fixture GIT_COMMITTER_EMAIL=fixture@example.invalid \
      GIT_AUTHOR_DATE='2026-01-01T00:00:00Z' GIT_COMMITTER_DATE='2026-01-01T00:00:00Z' \
      git -C "$plugin_dir" commit -q -m fixture
  done
  ln -s ../packages/ansible-lint/venv/bin/ansible-lint \
    "$release/share/nvim2/mason/bin/ansible-lint"
  ln -s ../packages/yamllint/venv/bin/yamllint \
    "$release/share/nvim2/mason/bin/yamllint"
  printf '#!/usr/bin/env bash\nexit 0\n' >"$release/config/nvim2/tests/check.sh"
  chmod 0755 "$release/config/nvim2/tests/check.sh"
  printf 'fixture %s\n' "$marker" >"$release/config/nvim2/init.lua"
  mkdir -p "$release/config/nvim2/tests/bad%new.dir"
  printf 'fixture percent path\n' >"$release/config/nvim2/tests/bad%new.dir/example"
  printf 'fixture punctuation path\n' \
    >"$release/config/nvim2/tests/reference_screenshot()---respects-\`opts.directory\`"
  mkdir -p "$release/config/nvim2/tests/Lua 5.4 zh-cn utf8"
  printf 'fixture spaced target\n' >"$release/config/nvim2/tests/Lua 5.4 zh-cn utf8/target file"
  ln -s 'target file' "$release/config/nvim2/tests/Lua 5.4 zh-cn utf8/link with space"
  for file in .bashrc .bash_profile .bash_aliases; do printf '%s\n' "$marker" >"$release/dotfiles/bash/$file"; done
  printf '%s\n' "$marker" >"$release/dotfiles/git/.gitconfig"
  printf '%s\n' "$marker" >"$release/dotfiles/tmux/.tmux.conf"
  printf '%s\n' "$marker" >"$release/dotfiles/vim/.vimrc"
  printf '%s\n' "$marker" >"$release/dotfiles/oh-my-posh/.oh-my-posh.omp.json"
  for file in config.yaml aliases.yaml plugins.yaml; do
    printf '%s\n' "$marker" >"$release/dotfiles/k9s/.config/k9s/$file"
  done
  printf '%s\n' "$marker" >"$release/dotfiles/k9s/.config/k9s/skins/skin.yaml"
  mkdir -p "$release/python-locks"
  printf 'fixture lock\n' >"$release/python-locks/ansible-lint.lock"
  printf 'fixture lock\n' >"$release/python-locks/yamllint.lock"
  printf 'fixture wheel\n' >"$release/python-wheelhouse/fixture.whl"
  printf '%s\n' \
    'FORMAT_VERSION=1' \
    "RELEASE_ID=$id" \
    'PLATFORM_ID=debian-13-x86_64' \
    "SOURCE_COMMIT=$commit" \
    'SOURCE_TREE=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb' \
    'BUILDER_IMAGE=fixture@sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc' \
    'NVIM_VERSION=v1.0' \
    'NODE_VERSION=1.0' \
    'NPM_VERSION=1.0' \
    'NODE_UPSTREAM_NPM_VERSION=1.0' \
    'PYTHON_VERSION=3.12.12' \
    'PYTHON_BUILD=20260127' \
    'TMUX_VERSION=1.0' \
    'RG_VERSION=1.0' \
    'FZF_VERSION=1.0' \
    'ZOXIDE_VERSION=1.0' \
    'K9S_VERSION=1.0' \
    'KUBECTX_VERSION=1.0' \
    'OMP_VERSION=1.0' \
    'TASK_VERSION=1.0' \
    'TERRAFORM_VERSION=1.0' \
    'OFFLINE_TOOLS=nvim,nodejs,python,rg,tmux,oh-my-posh,k9s,zoxide,kubectx,kubens,task,fzf,terraform' \
    'PAYLOAD_PATHS=bin,config,dotfiles,python-locks,python-wheelhouse,share,tools' \
    >"$release/release.env"
  printf 'marker=%s\n' "$marker" >"$release/build-manifest.txt"
  (
    cd "$release"
    find . -type f ! -name SHA256SUMS -print0 | sort -z |
      xargs -0 sha256sum >../SHA256SUMS
    mv ../SHA256SUMS SHA256SUMS
  )
  tar -C "$stage" -czf "$destination" "$id"
}

run_manager() {
  HOME=$test_home DOTFILES_OS_RELEASE_FILE=$os_release DOTFILES_RELEASE_TEST_MODE=1 \
    bash "$repo_dir/scripts/dotfiles-release" "$@"
}

commit_one=1111111111111111111111111111111111111111
commit_two=2222222222222222222222222222222222222222
commit_three=3333333333333333333333333333333333333333
id_one=dotfiles-${commit_one:0:12}
id_two=dotfiles-${commit_two:0:12}
id_three=dotfiles-${commit_three:0:12}
artifact_one=$test_root/one.tar.gz
artifact_two=$test_root/two.tar.gz
artifact_three=$test_root/three.tar.gz
make_artifact "$commit_one" one "$artifact_one"
make_artifact "$commit_two" two "$artifact_two"
make_artifact "$commit_three" three "$artifact_three"

test_home="$test_root/nonstandard home"
mkdir -p "$test_home/.config/k9s" "$test_home/bin"
printf 'original bashrc\n' >"$test_home/.bashrc"
printf 'private contexts\n' >"$test_home/kube-backup-contexts.txt"
printf 'private prefixes\n' >"$test_home/kube-log-prefixes.txt"

legacy_source="$test_root/legacy bstow source"
mkdir -p "$legacy_source/.config/nvim2" "$test_home/.config/nvim2" \
  "$test_home/.local/state/bstow" "$test_home/.local/state/dotfiles/setup-tools"
printf 'legacy nvim config\n' >"$legacy_source/.config/nvim2/init.lua"
ln -s "$legacy_source/.config/nvim2/init.lua" "$test_home/.config/nvim2/init.lua"
printf '%s\0%s\0' "$legacy_source" '.config/nvim2/init.lua' \
  >"$test_home/.local/state/bstow/nvim2.links"

write_fake_tool "$test_home/bin/rg-0.9"
ln -s rg-0.9 "$test_home/bin/rg"
legacy_rg_content=$(tar --sort=name --mtime=@0 --owner=0 --group=0 --numeric-owner \
  -C "$test_home/bin" -cf - -- rg-0.9 | sha256sum | awk '{print $1}')
printf 'complete\t%s\t%s\n' \
  aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa \
  "$legacy_rg_content" >"$test_home/.local/state/dotfiles/setup-tools/rg-0.9.state"

legacy_data="$test_root/legacy nvim data"
mkdir -p "$legacy_data" "$test_home/.local/share" "$test_home/.local/state/nvim2"
printf 'legacy visits\n' >"$legacy_data/mini-visits-index"
printf 'legacy telescope\n' >"$legacy_data/telescope_history.sqlite3"
printf 'legacy telescope prompts\n' >"$legacy_data/telescope_history"
printf 'newer visits\n' >"$test_home/.local/state/nvim2/mini-visits-index"
ln -s "$legacy_data" "$test_home/.local/share/nvim2"
printf 'CURRENT_DATA=%q\n' "$legacy_data" \
  >"$test_home/.local/state/nvim2-release-rollback.env"
chmod 0600 "$test_home/.local/state/nvim2-release-rollback.env"
mkdir -p "$test_home/.tmux/plugins"
cp -a "$test_root/stage-one/$id_one/share/tmux/plugins/." "$test_home/.tmux/plugins/"

foreign_home="$test_root/foreign home"
mkdir -p "$foreign_home/bin"
ln -s /usr/bin/true "$foreign_home/bin/rg"
test_home=$foreign_home
set +e
foreign_output=$(run_manager install "$artifact_one" 2>&1)
foreign_status=$?
set -e
[[ $foreign_status -ne 0 && $foreign_output == *'foreign managed path exists'* ]] ||
  fail 'foreign managed link was accepted'
assert_link "$foreign_home/bin/rg" /usr/bin/true
test_home="$test_root/nonstandard home"

run_manager verify debian-13-x86_64 "$artifact_one"
assert_link "$test_home/dotfiles-releases/current" "$id_one"
assert_link "$test_home/bin/rg" '../dotfiles-releases/current/bin/rg'
assert_link "$test_home/.config/k9s/config.yaml" \
  "$test_home/dotfiles-releases/current/dotfiles/k9s/.config/k9s/config.yaml"
[[ $(<"$test_home/kube-backup-contexts.txt") == 'private contexts' ]] || fail 'private contexts changed'
[[ $(<"$test_home/kube-log-prefixes.txt") == 'private prefixes' ]] || fail 'private prefixes changed'
[[ ! -e $test_home/bin/python && ! -e $test_home/bin/python3 ]] || fail 'global Python links were created'
[[ -x $test_home/dotfiles-releases/$id_one/share/nvim2/mason/packages/ansible-lint/venv/bin/ansible-lint ]] ||
  fail 'ansible-lint offline venv was not created'
[[ -x $test_home/dotfiles-releases/$id_one/share/nvim2/mason/packages/yamllint/venv/bin/yamllint ]] ||
  fail 'yamllint offline venv was not created'
[[ $(<"$test_home/.local/state/nvim2/mini-visits-index") == 'newer visits' ]] ||
  fail 'state migration replaced newer Mini Visits state'
[[ $(<"$test_home/.local/state/nvim2/telescope_history.sqlite3") == 'legacy telescope' ]] ||
  fail 'Telescope state was not migrated'
[[ $(<"$test_home/.local/state/nvim2/telescope_history") == 'legacy telescope prompts' ]] ||
  fail 'Telescope prompt history was not migrated'
[[ $(<"$legacy_data/mini-visits-index") == 'legacy visits' ]] ||
  fail 'state migration removed its source'
run_manager health
run_manager list | grep -F "$id_one" | grep -F current >/dev/null

first_digest=$(sha256sum "$test_home/dotfiles-releases/$id_one/installed.sha256")
run_manager install "$artifact_one"
[[ $(sha256sum "$test_home/dotfiles-releases/$id_one/installed.sha256") == "$first_digest" ]] ||
  fail 'idempotent install changed the release'

process_record=$test_root/process-record
run_manager install "$artifact_two"
run_manager health "$id_one"
HOME=$test_home "$test_home/dotfiles-releases/$id_one/bin/nvim" hold "$process_record" &
old_process=$!
while [[ ! -s $process_record ]]; do sleep 0.05; done
run_manager rollback
wait "$old_process"
grep -F "$id_one/tools/nvim/bin/nvim" "$process_record" >/dev/null ||
  fail 'running process did not stay on its physical release'
assert_link "$test_home/dotfiles-releases/current" "$id_one"
assert_link "$test_home/dotfiles-releases/previous" "$id_two"

set +e
DOTFILES_RELEASE_TEST_FAIL_PHASE=after-publish run_manager install "$artifact_three" >/dev/null 2>&1
failure_status=$?
set -e
[[ $failure_status -eq 72 ]] || fail 'after-publish failure hook returned the wrong status'
[[ -f $test_home/dotfiles-releases/.state/pending.env ]] || fail 'interrupted install has no journal'
run_manager install "$artifact_two"
[[ ! -e $test_home/dotfiles-releases/$id_three ]] || fail 'recovery retained an unselected release'
assert_link "$test_home/dotfiles-releases/current" "$id_two"

set +e
DOTFILES_RELEASE_TEST_FAIL_PHASE=after-switch run_manager install "$artifact_three" >/dev/null 2>&1
failure_status=$?
set -e
[[ $failure_status -eq 73 ]] || fail 'after-switch failure hook returned the wrong status'
run_manager install "$artifact_one"
[[ ! -e $test_home/dotfiles-releases/$id_three ]] || fail 'switch recovery retained a failed release'
assert_link "$test_home/dotfiles-releases/current" "$id_one"

collision=$test_root/collision.tar.gz
make_artifact "$commit_one" collision "$collision"
set +e
collision_output=$(run_manager install "$collision" 2>&1)
collision_status=$?
set -e
[[ $collision_status -ne 0 && $collision_output == *'release ID collision'* ]] ||
  fail 'same-ID different-content collision was accepted'

tampered=$test_home/dotfiles-releases/$id_one/config/nvim2/init.lua
original_mode=$(stat -c %a "$tampered")
printf 'tampered\n' >>"$tampered"
set +e
run_manager health >/dev/null 2>&1
tamper_status=$?
set -e
[[ $tamper_status -ne 0 ]] || fail 'health accepted a modified release'
printf 'fixture one\n' >"$tampered"

chmod 0600 "$tampered"
set +e
run_manager health >/dev/null 2>&1
mode_status=$?
set -e
[[ $mode_status -ne 0 ]] || fail 'health accepted a modified release mode'
chmod "$original_mode" "$tampered"

release_link="$test_home/dotfiles-releases/$id_one/config/nvim2/tests/Lua 5.4 zh-cn utf8/link with space"
unlink "$release_link"
ln -s example "$release_link"
set +e
run_manager health >/dev/null 2>&1
link_status=$?
set -e
[[ $link_status -ne 0 ]] || fail 'health accepted a modified release symlink'
unlink "$release_link"
ln -s 'target file' "$release_link"

exec {lock_fd}>"$test_home/dotfiles-releases/.state/lock"
flock -x "$lock_fd"
set +e
lock_output=$(run_manager install "$artifact_one" 2>&1)
lock_status=$?
set -e
[[ $lock_status -ne 0 && $lock_output == *'another release operation is running'* ]] ||
  fail 'concurrent install was accepted'
flock -u "$lock_fd"
exec {lock_fd}>&-

malicious_root=$test_root/malicious
mkdir -p "$malicious_root/dotfiles-aaaaaaaaaaaa"
# shellcheck disable=SC2016
printf 'RELEASE_ID=$(touch /tmp/dotfiles-release-eval-marker)\n' \
  >"$malicious_root/dotfiles-aaaaaaaaaaaa/release.env"
printf '' >"$malicious_root/dotfiles-aaaaaaaaaaaa/SHA256SUMS"
tar -C "$malicious_root" -czf "$test_root/malicious.tar.gz" dotfiles-aaaaaaaaaaaa
find /tmp -maxdepth 1 -name dotfiles-release-eval-marker -delete
set +e
run_manager install "$test_root/malicious.tar.gz" >/dev/null 2>&1
malicious_status=$?
set -e
[[ $malicious_status -ne 0 ]] || fail 'malicious metadata was accepted'
[[ ! -e /tmp/dotfiles-release-eval-marker ]] || fail 'release metadata was executed'

unsafe_link_root=$test_root/unsafe-link
mkdir -p "$unsafe_link_root/dotfiles-aaaaaaaaaaaa"
ln -s ../../outside "$unsafe_link_root/dotfiles-aaaaaaaaaaaa/escape"
tar -C "$unsafe_link_root" -czf "$test_root/unsafe-link.tar.gz" dotfiles-aaaaaaaaaaaa
set +e
unsafe_link_output=$(run_manager install "$test_root/unsafe-link.tar.gz" 2>&1)
unsafe_link_status=$?
set -e
[[ $unsafe_link_status -ne 0 && $unsafe_link_output == *'archive link escapes its root'* ]] ||
  fail 'escaping archive symlink was accepted'

corrupt_root=$test_root/corrupt
mkdir "$corrupt_root"
tar -xzf "$artifact_three" -C "$corrupt_root"
printf 'corrupt\n' >>"$corrupt_root/$id_three/config/nvim2/init.lua"
tar -C "$corrupt_root" -czf "$test_root/corrupt.tar.gz" "$id_three"
set +e
corrupt_output=$(run_manager install "$test_root/corrupt.tar.gz" 2>&1)
corrupt_status=$?
set -e
[[ $corrupt_status -ne 0 && $corrupt_output == *'checksum did NOT match'* ]] ||
  fail 'artifact with a corrupt payload was accepted'

run_manager install "$artifact_three"
run_manager uninstall "$id_two"
[[ ! -e $test_home/dotfiles-releases/$id_two ]] || fail 'uninstall retained an unselected release'
run_manager rollback
set +e
run_manager uninstall "$id_one" >/dev/null 2>&1
selected_status=$?
set -e
[[ $selected_status -ne 0 ]] || fail 'selected release was removed'
run_manager uninstall
[[ $(<"$test_home/.bashrc") == 'original bashrc' ]] || fail 'uninstall did not restore the original bashrc'
assert_link "$test_home/bin/rg" rg-0.9
[[ -x $test_home/bin/rg-0.9 ]] || fail 'uninstall did not restore the setup-tools payload'
[[ -d $test_home/.config/nvim2 && ! -L $test_home/.config/nvim2 ]] ||
  fail 'uninstall did not restore the bstow tree'
assert_link "$test_home/.config/nvim2/init.lua" "$legacy_source/.config/nvim2/init.lua"
assert_link "$test_home/.local/share/nvim2" "$legacy_data"
[[ -d $test_home/.tmux/plugins/tmux-sensible/.git &&
  ! -L $test_home/.tmux/plugins/tmux-sensible ]] ||
  fail 'uninstall did not restore the managed tmux plugin checkout'
[[ $(<"$test_home/kube-backup-contexts.txt") == 'private contexts' ]] || fail 'uninstall changed private contexts'

run_manager install "$artifact_three"
assert_link "$test_home/dotfiles-releases/current" "$id_three"
run_manager uninstall
assert_link "$test_home/bin/rg" rg-0.9
run_manager uninstall "$id_one"
run_manager uninstall "$id_three"
[[ ! -e $test_home/dotfiles-releases/$id_one && ! -e $test_home/dotfiles-releases/$id_three ]] ||
  fail 'inactive releases were retained'

printf 'Dotfiles release tests passed\n'
