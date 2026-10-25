#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=fixture.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/fixture.sh"
create_fixture

test_home="$test_root/nonstandard home"
mkdir -p "$test_home/.config/k9s" "$test_home/bin"
release_bin=$test_home/dotfiles-releases/current/bin
printf 'original bashrc\n' >"$test_home/.bashrc"
chmod 0640 "$test_home/.bashrc"
printf 'private contexts\n' >"$test_home/kube-backup-contexts.txt"
printf 'private prefixes\n' >"$test_home/kube-log-prefixes.txt"
printf '#!/usr/bin/env bash\nexit 91\n' >"$test_home/bin/helm"
chmod 0755 "$test_home/bin/helm"
export TEST_DOCKER_LOG="$test_root/unexpected-system-commands.log"
for command_name in sudo apt-get dnf curl docker; do
  ln -s "$repo_dir/tests/fixtures/setup-system/docker-command" "$test_home/bin/$command_name"
done
export PATH="$test_home/bin:$PATH"

legacy_source="$test_root/legacy configuration"
legacy_data="$legacy_source/.local/share/nvim2"
mkdir -p "$legacy_source/.config/nvim2" "$legacy_data" "$test_home/.config/nvim2" \
  "$test_home/.local/share" "$test_home/.local/state/nvim2" "$test_home/.tmux/plugins"
printf 'legacy nvim config\n' >"$legacy_source/.config/nvim2/init.lua"
ln -s "$legacy_source/.config/nvim2/init.lua" "$test_home/.config/nvim2/init.lua"
ln -s "$legacy_data" "$test_home/.local/share/nvim2"
printf 'legacy telescope\n' >"$legacy_data/telescope_history.sqlite3"
printf 'legacy prompts\n' >"$legacy_data/telescope_history"
printf 'newer telescope\n' >"$test_home/.local/state/nvim2/telescope_history.sqlite3"
write_fake_tool "$test_home/bin/rg-0.9" 0.9
ln -s rg-0.9 "$test_home/bin/rg"
printf 'saved private provider\n' >"$test_home/bin/rg.before-dotfiles-release"
ln -s ../dotfiles-releases/current/bin/rg "$test_home/bin/legacy-link"
ln -s ../dotfiles-releases/current/bin/retired-tool "$test_home/bin/retired-tool"
user_bin_digest=$(tar --sort=name --mtime=@0 --owner=0 --group=0 --numeric-owner \
  -C "$test_home" -cf - bin | sha256sum)
cp -a "$test_root/stage-one/$id_one/share/tmux/plugins/." "$test_home/.tmux/plugins/"

run_manager verify "$artifact_one" >/dev/null
run_manager install "$artifact_one" >/dev/null
run_manager health >/dev/null
assert_link "$test_home/dotfiles-releases/current" "$id_one"
assert_link "$test_home/bin/rg" rg-0.9
[[ $(PATH="$test_home/bin:$release_bin:/usr/bin:/bin" command -v rg) == "$test_home/bin/rg" ]] ||
  fail 'user executable did not override the release'
[[ $(<"$test_home/.bashrc.before-dotfiles-release") == 'original bashrc' &&
  $(stat -c %a "$test_home/.bashrc.before-dotfiles-release") == 640 ]] ||
  fail 'install did not preserve baseline bytes and mode'
[[ $(<"$test_home/.local/state/nvim2/telescope_history.sqlite3") == 'newer telescope' &&
  $(<"$test_home/.local/state/nvim2/telescope_history") == 'legacy prompts' &&
  $(<"$legacy_data/telescope_history") == 'legacy prompts' ]] ||
  fail 'legacy state migration did not preserve old and new user data'
[[ ! -e $release_bin/python && ! -L $release_bin/python &&
  ! -e $release_bin/python3 && ! -L $release_bin/python3 &&
  -x $test_home/dotfiles-releases/current/tools/python/bin/python3 ]] ||
  fail 'private Python was published globally'
[[ -x $test_home/dotfiles-releases/$id_one/share/nvim2/mason/packages/ansible-lint/venv/bin/ansible-lint &&
  -x $test_home/dotfiles-releases/$id_one/share/nvim2/mason/packages/yamllint/venv/bin/yamllint ]] ||
  fail 'locked Python environments were not prepared'
[[ ! -e $test_home/dotfiles-releases/.state &&
  ! -e $test_home/dotfiles-releases/previous &&
  ! -e $test_home/dotfiles-releases/$id_one/.complete ]] ||
  fail 'install created obsolete release state'
assert_link "$test_home/.ssh/config" \
  "$test_home/dotfiles-releases/current/dotfiles/ssh/.ssh/config"
assert_link "$test_home/.config/systemd/user/dotfiles-ssh-agent.service" \
  "$test_home/dotfiles-releases/current/dotfiles/ssh/.config/systemd/user/dotfiles-ssh-agent.service"

for client in kubectl helm; do
  [[ $(env -u KUBECTL_VERSION -u HELM_VERSION "$release_bin/$client") == *'fixture 1.0'* &&
    $(env "${client^^}_VERSION=0.9" "$release_bin/$client") == *'fixture 0.9'* ]] ||
    fail "$client did not select the default and requested versions"
  [[ $(env "${client^^}_VERSION=0.9" "$release_bin/$client" fixture-args \
    'argument with spaces' '*' '--flag=value') == *$'<argument with spaces>\n<*>\n<--flag=value>' ]] ||
    fail "$client changed its arguments"
  status=0
  env "${client^^}_VERSION=0.9" "$release_bin/$client" fixture-fail >/dev/null || status=$?
  [[ $status == 42 ]] || fail "$client changed the exit status"
  for requested_version in 99.0 ../../bin/rg; do
    if env "${client^^}_VERSION=$requested_version" "$release_bin/$client" >/dev/null 2>&1; then
      fail "$client accepted an unavailable or invalid version"
    fi
  done
done

first_digest=$(sha256sum "$test_home/dotfiles-releases/$id_one/installed.sha256")
KUBECTL_VERSION=99.0 HELM_VERSION=99.0 run_manager install "$artifact_one" >/dev/null
[[ $(sha256sum "$test_home/dotfiles-releases/$id_one/installed.sha256") == "$first_digest" ]] ||
  fail 'reinstall rebuilt the immutable release'
run_manager install "$artifact_two" >/dev/null
assert_link "$test_home/dotfiles-releases/current" "$id_two"

standalone_manager=$test_root/downloaded-dotfiles-release
cp "$test_home/dotfiles-releases/$id_two/dotfiles-release" "$standalone_manager"
HOME=$test_home DOTFILES_OS_RELEASE_FILE=$os_release bash "$standalone_manager" list \
  >"$test_root/list.log"
[[ $(awk -F '\t' 'NR > 1 { count++ } END { print count }' "$test_root/list.log") == 2 ]] ||
  fail 'standalone manager did not list both installed releases'

process_record=$test_root/process-record
process_gate=$test_root/process-continue
running_release=$test_home/dotfiles-releases/$id_two
HOME=$test_home NVIM_APPNAME=nvim2 timeout 30s \
  "$release_bin/nvim" hold "$process_record" "$process_gate" &
old_process=$!
for ((attempt = 0; attempt < 200; attempt++)); do
  [[ ! -s $process_record ]] || break
  sleep 0.02
done
[[ -s $process_record ]] || fail 'process did not start from the active release'
run_manager set "$id_one" >/dev/null
: >"$process_gate"
wait "$old_process"
old_process=
expected_record=$(printf 'before=%s\nconfig-before=%s\nafter=%s\nconfig-after=%s\n' \
  "$running_release/tools/nvim/bin/nvim" "$running_release/config" \
  "$running_release/tools/nvim/bin/nvim" "$running_release/config")
[[ $(<"$process_record") == "$expected_record" ]] ||
  fail 'running process changed its physical executable or configuration after set'
HOME=$test_home NVIM_APPNAME=nvim2 \
  "$release_bin/nvim" hold "$test_root/new-process-record" "$process_gate"
[[ $(<"$test_root/new-process-record") == *"$id_one/tools/nvim/bin/nvim"* ]] ||
  fail 'new process did not use the selected release'
for command_name in fd go gofmt; do
  [[ ! -e $release_bin/$command_name && ! -L $release_bin/$command_name &&
    ! -L $test_home/bin/$command_name ]] || fail "removed tool left a public link: $command_name"
  if PATH="$release_bin" command -v "$command_name" >/dev/null; then
    fail "switching to an older profile borrowed $command_name"
  fi
done

run_manager uninstall "$id_two" >/dev/null
[[ ! -e $test_home/dotfiles-releases/$id_two ]] || fail 'uninstall retained an inactive release'
assert_link "$test_home/dotfiles-releases/current" "$id_one"
run_manager install "$artifact_three" >/dev/null
run_manager set "$id_one" >/dev/null
run_manager uninstall >/dev/null
[[ ! -e $test_home/dotfiles-releases/$id_one &&
  ! -L $test_home/dotfiles-releases/current &&
  -d $test_home/dotfiles-releases/$id_three ]] ||
  fail 'uninstall did not remove only the active release and selection'
[[ $(<"$test_home/.bashrc") == 'original bashrc' && $(stat -c %a "$test_home/.bashrc") == 640 ]] ||
  fail 'uninstall did not restore baseline bytes and mode'
assert_link "$test_home/bin/rg" rg-0.9
assert_link "$test_home/.config/nvim2/init.lua" "$legacy_source/.config/nvim2/init.lua"
assert_link "$test_home/.local/share/nvim2" "$legacy_data"
[[ -d $test_home/.tmux/plugins/tmux-sensible/.git && ! -L $test_home/.tmux/plugins/tmux-sensible &&
  ! -L $test_home/.ssh/config && ! -L $test_home/bin/kubectl ]] ||
  fail 'uninstall did not restore prior trees and remove release links'
[[ $(<"$test_home/kube-backup-contexts.txt") == 'private contexts' &&
  $(<"$test_home/kube-log-prefixes.txt") == 'private prefixes' ]] ||
  fail 'release operations modified private Kubernetes inputs'

run_manager set "$id_three" >/dev/null
assert_link "$test_home/dotfiles-releases/current" "$id_three"
run_manager uninstall "$id_three" >/dev/null
assert_link "$test_home/bin/rg" rg-0.9
[[ $(tar --sort=name --mtime=@0 --owner=0 --group=0 --numeric-owner \
  -C "$test_home" -cf - bin | sha256sum) == "$user_bin_digest" ]] ||
  fail 'release lifecycle changed user bin, its modes, backups or links'
[[ ! -e $TEST_DOCKER_LOG ]] || fail 'release operations ran host setup or attempted network downloads'

printf 'dotfiles_release: lifecycle passed\n'
