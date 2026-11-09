#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=fixture.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/fixture.sh"
create_fixture

test_home=$test_root/'online home with spaces'
online_source=$test_root/'editable checkout'
mkdir -p "$test_home/bin" "$test_home/.local/share/nvim2/mason"
printf 'private git configuration\n' >"$test_home/.gitconfig"
printf 'cached editor data\n' >"$test_home/.local/share/nvim2/mason/keep"
printf '#!/usr/bin/env bash\nprintf "user fd override\\n"\n' >"$test_home/bin/fd"
chmod 0755 "$test_home/bin/fd"
override_digest=$(sha256sum "$test_home/bin/fd")

if run_manager set online >"$test_root/missing-online.log" 2>&1; then
  fail 'an unprepared online installation was activated'
fi
[[ ! -e $test_home/.gitconfig.before-dotfiles-release ]] ||
  fail 'missing online installation changed HOME configuration'

# Prepare real installer output with local archives, independently of the
# archived-release fixture and its transaction helpers.
bash -euo pipefail -s -- "$repo_dir" "$test_home" "$online_source" <<'BASH'
repository=$1 target_home=$2 checkout=$3
source "$repository/tests/setup_tools/fixture.sh"
create_fixture
make_test_repo "$checkout"
cp "$test_repository/tools.env" "$checkout/tools.env"
printf 'TOOLS=(fd tmux nvim kubectl helm)\n' >>"$checkout/tools.env"
for package in bash git ssh vim tmux nvim2; do
  cp -a "$repository/$package" "$checkout/$package"
done
cp -a "$repository/scripts/." "$checkout/scripts/"
run_setup "$target_home" "$checkout" "$archive_root"
BASH

online=$test_home/dotfiles-releases/online
run_manager set online >/dev/null
assert_link "$test_home/dotfiles-releases/current" online
assert_link "$online/dotfiles" "$online_source"
assert_link "$test_home/.gitconfig" "$test_home/dotfiles-releases/current/dotfiles/git/.gitconfig"
[[ $(<"$test_home/.local/share/nvim2/mason/keep") == 'cached editor data' &&
  $(<"$test_home/.gitconfig.before-dotfiles-release") == 'private git configuration' ]] ||
  fail 'online activation lost editor data or the original configuration'
[[ $(sha256sum "$test_home/bin/fd") == "$override_digest" ]] ||
  fail 'online activation changed a user command override'
online_nvim=$("$online/bin/nvim" --version)
run_manager health >/dev/null

manager_target=$(readlink -- "$online/bin/dotfiles-release")
unlink -- "$online/bin/dotfiles-release"
if run_manager health >"$test_root/missing-online-manager.log" 2>&1; then
  fail 'online health accepted a missing public release manager'
fi
grep -F 'online manager command is missing or incorrect' "$test_root/missing-online-manager.log" >/dev/null ||
  fail 'online health did not identify the missing release manager'
if HOME="$test_home" DOTFILES="$online_source" bash --noprofile --norc -c \
  'source "$DOTFILES/bash/.bash_aliases"; dotfiles-check' >"$test_root/missing-check-manager.log" 2>&1; then
  fail 'dotfiles-check ignored the missing active release manager'
fi
grep -F 'active release manager is missing' "$test_root/missing-check-manager.log" >/dev/null ||
  fail 'dotfiles-check fell back to bootstrap checks for a damaged active installation'
ln -s -- "$manager_target" "$online/bin/dotfiles-release"
run_manager health >/dev/null

client_aliases=("$online/bin/kubectl-"*)
alias=${client_aliases[0]}
alias_target=$(readlink -- "$alias")
unlink -- "$alias"
if run_manager health >"$test_root/missing-client-alias.log" 2>&1; then
  fail 'online health accepted a missing retained client command'
fi
grep -F 'online command is missing' "$test_root/missing-client-alias.log" >/dev/null ||
  fail 'online health did not identify the missing client command'
ln -s -- "$alias_target" "$alias"
run_manager health >/dev/null

printf '# mutable online configuration\n' >>"$online_source/git/.gitconfig"
grep -F 'mutable online configuration' "$test_home/.gitconfig" >/dev/null ||
  fail 'online configuration no longer follows the editable checkout'

run_manager install "$artifact_one" >/dev/null
assert_link "$test_home/dotfiles-releases/current" "$id_one"
[[ $(<"$online/share/nvim2/mason/keep") == 'cached editor data' ]] ||
  fail 'offline activation changed the retained online editor data'
if grep -F 'mutable online configuration' "$test_home/.gitconfig" >/dev/null; then
  fail 'offline configuration followed the editable online checkout'
fi
run_manager health >/dev/null

# Online updates write only online, even while an immutable release is current.
offline_digest=$(sha256sum "$test_home/dotfiles-releases/$id_one/installed.sha256")
HOME="$test_home" "$online_source/setup-tools" fd >/dev/null
assert_link "$test_home/dotfiles-releases/current" "$id_one"
[[ $(sha256sum "$test_home/dotfiles-releases/$id_one/installed.sha256") == "$offline_digest" ]] ||
  fail 'online reconciliation wrote to the selected offline release'
run_manager health >/dev/null
run_manager health online >/dev/null

run_manager set online >/dev/null
assert_link "$test_home/dotfiles-releases/current" online
[[ $("$test_home/dotfiles-releases/current/bin/nvim" --version) == "$online_nvim" &&
  $(<"$test_home/.local/share/nvim2/mason/keep") == 'cached editor data' ]] ||
  fail 'returning online lost the retained runtime or editor data'
run_manager list >"$test_root/online-list.log"
grep -F $'online\tonline\tworking-tree' "$test_root/online-list.log" >/dev/null ||
  fail 'list omitted the mutable online installation'

exec {shared_lock_fd}<"$test_home/dotfiles-releases"
flock -n "$shared_lock_fd"
if HOME="$test_home" "$online_source/setup-tools" fd >"$test_root/locked-online.log" 2>&1; then
  fail 'setup-tools ignored the common release lock'
fi
grep -F 'another installation or release operation is running' "$test_root/locked-online.log" >/dev/null ||
  fail 'setup-tools did not report the common release lock'
if run_manager set "$id_one" >"$test_root/locked-offline.log" 2>&1; then
  fail 'offline activation ignored the common release lock'
fi
exec {shared_lock_fd}>&-

printf '# changed payload\n' >>"$(readlink -f -- "$online/bin/fd")"
run_manager set "$id_one" >/dev/null
if run_manager set online >"$test_root/modified-online.log" 2>&1; then
  fail 'a modified online payload was activated'
fi
assert_link "$test_home/dotfiles-releases/current" "$id_one"
grep -F 'online tool payload was modified' "$test_root/modified-online.log" >/dev/null ||
  fail 'online integrity rejection did not identify the modified payload'

run_manager uninstall online >/dev/null
[[ -d $online_source && -f $online_source/git/.gitconfig &&
  $(sha256sum "$test_home/bin/fd") == "$override_digest" ]] ||
  fail 'uninstall online removed its checkout or a user executable'
assert_link "$test_home/dotfiles-releases/current" "$id_one"
run_manager uninstall >/dev/null
[[ $(<"$test_home/.gitconfig") == 'private git configuration' &&
  $(<"$test_home/.local/share/nvim2/mason/keep") == 'cached editor data' ]] ||
  fail 'uninstall did not restore the original HOME configuration and editor data'

printf 'dotfiles_release: online passed\n'
