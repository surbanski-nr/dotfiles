#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=fixture.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/fixture.sh"
create_fixture

test_home="$test_root/nonstandard home"
mkdir -p "$test_home/.config/k9s" "$test_home/bin"
printf 'original bashrc\n' >"$test_home/.bashrc"
printf 'private contexts\n' >"$test_home/kube-backup-contexts.txt"
printf 'private prefixes\n' >"$test_home/kube-log-prefixes.txt"
mkdir -m 0700 "$test_home/bin-extras"
printf '#!/usr/bin/env bash\nexit 91\n' >"$test_home/bin-extras/helm"
chmod 0755 "$test_home/bin-extras/helm"
ln -s helm "$test_home/bin-extras/rg"
extras_digest=$(tar --sort=name --mtime=@0 --owner=0 --group=0 --numeric-owner \
  -C "$test_home" -cf - bin-extras | sha256sum)
export PATH="$test_home/bin-extras:$PATH"

legacy_source="$test_root/legacy bstow source"
legacy_data="$legacy_source/.local/share/nvim2"
mkdir -p "$legacy_source/.config/nvim2" "$legacy_data" "$test_home/.config/nvim2" \
  "$test_home/.local/state/bstow" "$test_home/.local/state/dotfiles/setup-tools"
printf 'legacy nvim config\n' >"$legacy_source/.config/nvim2/init.lua"
ln -s "$legacy_source/.config/nvim2/init.lua" "$test_home/.config/nvim2/init.lua"
printf '%s\0%s\0%s\0' "$legacy_source" '.config/nvim2/init.lua' \
  '.local/share/nvim2' \
  >"$test_home/.local/state/bstow/nvim2.links"

write_fake_tool "$test_home/bin/rg-0.9"
ln -s rg-0.9 "$test_home/bin/rg"
legacy_rg_content=$(tar --sort=name --mtime=@0 --owner=0 --group=0 --numeric-owner \
  -C "$test_home/bin" -cf - -- rg-0.9 | sha256sum | awk '{print $1}')
printf 'complete\t%s\t%s\n' \
  aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa \
  "$legacy_rg_content" >"$test_home/.local/state/dotfiles/setup-tools/rg-0.9.state"

mkdir -p "$test_home/.local/share" "$test_home/.local/state/nvim2"
printf 'legacy telescope\n' >"$legacy_data/telescope_history.sqlite3"
printf 'legacy telescope prompts\n' >"$legacy_data/telescope_history"
printf 'newer telescope\n' >"$test_home/.local/state/nvim2/telescope_history.sqlite3"
ln -s "$legacy_data" "$test_home/.local/share/nvim2"
mkdir -p "$test_home/.tmux/plugins"
cp -a "$test_root/stage-one/$id_one/share/tmux/plugins/." "$test_home/.tmux/plugins/"

test_home=$test_root/telescope-state-home
mkdir -p "$test_home/.local/share" "$test_home/.local/state/nvim2" "$test_home/.local/state/bstow"
ln -s "$legacy_data" "$test_home/.local/share/nvim2"
printf '%s\0%s\0' "$legacy_source" '.local/share/nvim2' \
  >"$test_home/.local/state/bstow/nvim2.links"
printf 'newer prompts\n' >"$test_home/.local/state/nvim2/telescope_history"
run_manager install "$artifact_one" >"$test_root/telescope-migration.log" 2>&1
[[ $(<"$test_home/.local/state/nvim2/telescope_history.sqlite3") == 'legacy telescope' ]] ||
  fail 'Telescope SQLite history was not migrated'
[[ $(<"$test_home/.local/state/nvim2/telescope_history") == 'newer prompts' ]] ||
  fail 'state migration replaced newer Telescope prompt history'
[[ $(<"$legacy_data/telescope_history") == 'legacy telescope prompts' ]] ||
  fail 'state migration removed the Telescope prompt source'
test_home="$test_root/nonstandard home"

run_manager verify debian-13-x86_64 "$artifact_one"
assert_link "$test_home/dotfiles-releases/current" "$id_one"
assert_link "$test_home/bin/rg" '../dotfiles-releases/current/bin/rg'
for client in kubectl helm; do
  assert_link "$test_home/bin/$client" "../dotfiles-releases/current/bin/$client"
  [[ $(env -u KUBECTL_VERSION -u HELM_VERSION "$test_home/bin/$client") == *'fixture 1.0'* ]] ||
    fail "$client did not select the default version"
  [[ $(env "${client^^}_VERSION=0.9" "$test_home/bin/$client") == *'fixture 0.9'* ]] ||
    fail "$client did not select the requested version"
  [[ $(env "${client^^}_VERSION=0.9" "$test_home/bin/$client" fixture-args \
    'argument with spaces' '*' '--flag=value') == *$'<argument with spaces>\n<*>\n<--flag=value>' ]] ||
    fail "$client changed its arguments"
  set +e
  env "${client^^}_VERSION=0.9" "$test_home/bin/$client" fixture-fail >/dev/null
  client_status=$?
  set -e
  [[ $client_status -eq 42 ]] || fail "$client did not preserve its exit status"
  for requested_version in 99.0 ../../bin/rg; do
    if env "${client^^}_VERSION=$requested_version" "$test_home/bin/$client" \
      >"$test_root/$client-error.log" 2>&1; then
      fail "$client accepted an unavailable or invalid version"
    fi
  done
done
KUBECTL_VERSION=99.0 HELM_VERSION=99.0 run_manager health >/dev/null
assert_link "$test_home/.config/k9s/config.yaml" \
  "$test_home/dotfiles-releases/current/dotfiles/k9s/.config/k9s/config.yaml"
assert_link "$test_home/.ssh/config" \
  "$test_home/dotfiles-releases/current/dotfiles/ssh/.ssh/config"
assert_link "$test_home/.config/systemd/user/dotfiles-ssh-agent.service" \
  "$test_home/dotfiles-releases/current/dotfiles/ssh/.config/systemd/user/dotfiles-ssh-agent.service"
[[ $(<"$test_home/kube-backup-contexts.txt") == 'private contexts' ]] || fail 'private contexts changed'
[[ $(<"$test_home/kube-log-prefixes.txt") == 'private prefixes' ]] || fail 'private prefixes changed'
[[ ! -e $test_home/bin/python && ! -e $test_home/bin/python3 ]] || fail 'global Python links were created'
[[ -x $test_home/dotfiles-releases/$id_one/share/nvim2/mason/packages/ansible-lint/venv/bin/ansible-lint ]] ||
  fail 'ansible-lint offline venv was not created'
[[ -x $test_home/dotfiles-releases/$id_one/share/nvim2/mason/packages/yamllint/venv/bin/yamllint ]] ||
  fail 'yamllint offline venv was not created'
[[ $(<"$test_home/.local/state/nvim2/telescope_history.sqlite3") == 'newer telescope' ]] ||
  fail 'state migration replaced newer Telescope state'
[[ $(<"$test_home/.local/state/nvim2/telescope_history") == 'legacy telescope prompts' ]] ||
  fail 'Telescope prompt history was not migrated'
[[ $(<"$legacy_data/telescope_history.sqlite3") == 'legacy telescope' ]] ||
  fail 'state migration removed its source'
run_manager health
set +e
FIXTURE_FAIL_PYTHON_IMPORT=1 run_manager health </dev/null >"$test_root/python-health.log" 2>&1
python_health_status=$?
set -e
[[ $python_health_status -eq 95 ]] ||
  fail 'health did not reject a broken Python package import'
run_manager list | grep -F "$id_one" | grep -F current >/dev/null

first_digest=$(sha256sum "$test_home/dotfiles-releases/$id_one/installed.sha256")
run_manager install "$artifact_one"
[[ $(sha256sum "$test_home/dotfiles-releases/$id_one/installed.sha256") == "$first_digest" ]] ||
  fail 'idempotent install changed the release'

process_record=$test_root/process-record
run_manager install "$artifact_two"
assert_link "$test_home/bin/fd" '../dotfiles-releases/current/bin/fd'
[[ $("$test_home/bin/fd" --version) == *'fixture 2.0'* ]] ||
  fail 'fd launcher did not select the active release'
[[ $("$test_home/bin/kubectl") == *'fixture 2.0'* &&
  $("$test_home/bin/helm") == *'fixture 2.0'* &&
  $(KUBECTL_VERSION=0.9 "$test_home/bin/kubectl") == *'fixture 0.9'* ]] ||
  fail 'client launchers did not follow the active release'
standalone_manager=$test_root/standalone-dotfiles-release
cp "$test_home/dotfiles-releases/$id_two/dotfiles-release" "$standalone_manager"
HOME=$test_home DOTFILES_OS_RELEASE_FILE=$os_release DOTFILES_RELEASE_TEST_MODE=1 \
  bash "$standalone_manager" health "$id_one"
process_gate=$test_root/process-continue
running_release=$test_home/dotfiles-releases/$id_two
expected_record=$(printf 'before=%s\nconfig-before=%s\n' \
  "$running_release/tools/nvim/bin/nvim" "$running_release/config")
HOME=$test_home NVIM_APPNAME=nvim2 timeout 30s \
  "$test_home/bin/nvim" hold "$process_record" "$process_gate" &
old_process=$!
for ((attempt = 0; attempt < 200; attempt++)); do
  if [[ -s $process_record && $(<"$process_record") == "$expected_record" ]]; then break; fi
  sleep 0.05
done
[[ -s $process_record && $(<"$process_record") == "$expected_record" ]] ||
  fail 'process did not start through the active B launcher with its configuration'
run_manager rollback
: >"$process_gate"
wait "$old_process"
old_process=
expected_record=$(printf 'before=%s\nconfig-before=%s\nafter=%s\nconfig-after=%s\n' \
  "$running_release/tools/nvim/bin/nvim" "$running_release/config" \
  "$running_release/tools/nvim/bin/nvim" "$running_release/config")
[[ $(<"$process_record") == "$expected_record" ]] ||
  fail 'running process changed its executable or configuration after rollback'
running_release=$test_home/dotfiles-releases/$id_one
HOME=$test_home NVIM_APPNAME=nvim2 \
  "$test_home/bin/nvim" hold "$test_root/new-process-record" "$process_gate"
expected_record=$(printf 'before=%s\nconfig-before=%s\nafter=%s\nconfig-after=%s\n' \
  "$running_release/tools/nvim/bin/nvim" "$running_release/config" \
  "$running_release/tools/nvim/bin/nvim" "$running_release/config")
[[ $(<"$test_root/new-process-record") == "$expected_record" ]] ||
  fail 'new process did not follow the rolled-back A launcher and configuration'
assert_link "$test_home/dotfiles-releases/current" "$id_one"
assert_link "$test_home/dotfiles-releases/previous" "$id_two"
[[ ! -e $test_home/bin/fd ]] || fail 'legacy rollback retained an executable from the newer release'
[[ ! -e $test_home/bin/go && ! -e $test_home/bin/gofmt ]] ||
  fail 'legacy rollback retained Go commands from the newer release'
[[ $("$test_home/bin/kubectl") == *'fixture 1.0'* &&
  $("$test_home/bin/helm") == *'fixture 1.0'* ]] ||
  fail 'client launchers did not follow rollback'

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


run_manager install "$artifact_three"
run_manager uninstall "$id_two"
[[ ! -e $test_home/dotfiles-releases/$id_two ]] || fail 'uninstall retained an unselected release'
run_manager rollback
set +e
run_manager uninstall "$id_one" >/dev/null 2>&1
selected_status=$?
set -e
[[ $selected_status -ne 0 ]] || fail 'selected release was removed'
ownership_file=$test_home/dotfiles-releases/.state/ownership.tsv
cp "$ownership_file" "$ownership_file.current"
awk -F '\t' 'BEGIN { OFS="\t" } { print $2, $3, $4, $5 }' \
  "$ownership_file" >"$ownership_file.legacy"
mv -T "$ownership_file.legacy" "$ownership_file"
set +e
legacy_orphan_output=$(run_manager uninstall 2>&1)
legacy_orphan_status=$?
set -e
[[ $legacy_orphan_status -ne 0 &&
  $legacy_orphan_output == *'ownership record has an invalid field count'* ]] ||
  fail 'obsolete four-column ownership state was accepted'
[[ -L $test_home/.bashrc &&
  -f $test_home/dotfiles-releases/.state/pending.env ]] ||
  fail 'obsolete ownership state changed managed data or discarded its journal'
mv -T "$ownership_file.current" "$ownership_file"
run_manager uninstall
[[ $(<"$test_home/.bashrc") == 'original bashrc' ]] || fail 'uninstall did not restore the original bashrc'
[[ ! -e $test_home/.ssh/config && ! -L $test_home/.ssh/config &&
  ! -e $test_home/.config/systemd/user/dotfiles-ssh-agent.service &&
  ! -L $test_home/.config/systemd/user/dotfiles-ssh-agent.service ]] ||
  fail 'baseline restore retained the SSH agent configuration'
[[ ! -e $test_home/bin/kubectl && ! -L $test_home/bin/kubectl &&
  ! -e $test_home/bin/helm && ! -L $test_home/bin/helm ]] ||
  fail 'baseline restore retained public offline client links'
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

[[ $(tar --sort=name --mtime=@0 --owner=0 --group=0 --numeric-owner \
  -C "$test_home" -cf - bin-extras | sha256sum) == "$extras_digest" ]] ||
  fail 'release lifecycle changed user extras, permissions or symlinks'

printf 'dotfiles_release: lifecycle passed\n'
