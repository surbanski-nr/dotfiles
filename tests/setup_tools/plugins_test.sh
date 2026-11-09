#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=fixture.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/fixture.sh"
create_fixture

plugins=(tmux-sensible tmux-resurrect tmux-continuum)
declare -A pinned_commits=() newer_commits=()
collision_commit=''
broken_commit=''
export GIT_CONFIG_GLOBAL=$test_root/gitconfig
git config --file "$GIT_CONFIG_GLOBAL" \
  "url.file://$test_root/origins/.insteadOf" https://example.invalid/tmux/
mkdir -p "$test_root/origins"
printf 'declare -gA TMUX_PLUGINS=()\n' >>"$test_repository/tools.env"
for plugin in "${plugins[@]}"; do
  seed=$test_root/seed-$plugin
  entry=${plugin#tmux-}.tmux
  git init -q -b main "$seed"
  git -C "$seed" config user.name fixture
  git -C "$seed" config user.email fixture@example.invalid
  printf '#!/usr/bin/env bash\nprintf "plugin fixture\\n"\n' >"$seed/$entry"
  printf 'ignored-note\n' >"$seed/.gitignore"
  chmod 0755 "$seed/$entry"
  git -C "$seed" add "$entry" .gitignore
  git -C "$seed" commit -qm initial
  pinned_commits[$plugin]=$(git -C "$seed" rev-parse HEAD)
  printf '# newer revision\n' >>"$seed/$entry"
  git -C "$seed" commit -qam newer
  newer_commits[$plugin]=$(git -C "$seed" rev-parse HEAD)
  if [[ $plugin == tmux-sensible ]]; then
    printf 'upstream file\n' >"$seed/ignored-note"
    git -C "$seed" add -f ignored-note
    git -C "$seed" commit -qm collision
    collision_commit=$(git -C "$seed" rev-parse HEAD)
    chmod 0644 "$seed/$entry"
    git -C "$seed" commit -qam broken
    broken_commit=$(git -C "$seed" rev-parse HEAD)
  fi
  git clone -q --bare "$seed" "$test_root/origins/$plugin.git"
  printf 'TMUX_PLUGINS[%q]=%q\n' "$plugin" \
    "https://example.invalid/tmux/$plugin.git|${pinned_commits[$plugin]}" \
    >>"$test_repository/tools.env"
done
printf 'TOOLS=(tmux tmux-sensible tmux-resurrect tmux-continuum)\n' \
  >>"$test_repository/tools.env"

assert_plugin() {
  local root=$1 name=$2 commit=$3
  [[ -d $root/$name/.git && -x $root/$name/${name#tmux-}.tmux ]] ||
    fail "incomplete plugin installation: $root/$name"
  [[ $(git -C "$root/$name" rev-parse HEAD) == "$commit" ]] ||
    fail "plugin is not at its selected commit: $name"
}

run_setup "$test_home" "$test_repository" "$archive_root" tmux-sensible
assert_plugin "$test_home/dotfiles-releases/online/share/tmux/plugins" tmux-sensible "${pinned_commits[tmux-sensible]}"
[[ ! -e $test_home/dotfiles-releases/online/bin/tmux &&
  ! -e $test_home/dotfiles-releases/online/share/tmux/plugins/tmux-resurrect ]] ||
  fail 'an individual plugin request installed other tools'
[[ -x $test_home/dotfiles-releases/online/bin/dotfiles-release &&
  ! -e $test_home/dotfiles-releases/online/state/setup-tools ]] ||
  fail 'an individual plugin request created binary ownership records'
[[ -z $(find "$test_home/dotfiles-releases/online/state" -name '*.state' -print -quit) ]] ||
  fail 'a Git plugin created binary ownership state'

run_setup "$test_home" "$test_repository" "$archive_root"
[[ -x $test_home/dotfiles-releases/online/bin/tmux ]] || fail 'default setup did not install the tmux binary'
for plugin in "${plugins[@]}"; do
  assert_plugin "$test_home/dotfiles-releases/online/share/tmux/plugins" "$plugin" "${pinned_commits[$plugin]}"
done
[[ ! -e $test_home/dotfiles-releases/online/share/tmux/plugins/tpm ]] || fail 'setup still installed TPM'

checkout=$test_home/dotfiles-releases/online/share/tmux/plugins/tmux-sensible
printf 'keep this note\n' >"$checkout/local-notes"
mkdir -p "$test_home/.tmux/resurrect"
printf 'saved session\n' >"$test_home/.tmux/resurrect/session"
git -C "$checkout" remote set-url origin https://example.invalid/tmux/tmux-sensible
printf 'TMUX_PLUGINS[tmux-sensible]=%q\n' \
  "https://example.invalid/tmux/tmux-sensible.git|${newer_commits[tmux-sensible]}" \
  >>"$test_repository/tools.env"
run_setup "$test_home" "$test_repository" "$archive_root" tmux-sensible
assert_plugin "$test_home/dotfiles-releases/online/share/tmux/plugins" tmux-sensible "${newer_commits[tmux-sensible]}"
[[ $(<"$checkout/local-notes") == 'keep this note' &&
$(<"$test_home/.tmux/resurrect/session") == 'saved session' ]] ||
  fail 'repinning a plugin changed user notes or session data'

printf 'keep this ignored note\n' >"$checkout/ignored-note"
printf 'TMUX_PLUGINS[tmux-sensible]=%q\n' \
  "https://example.invalid/tmux/tmux-sensible.git|$collision_commit" \
  >>"$test_repository/tools.env"
if run_setup "$test_home" "$test_repository" "$archive_root" tmux-sensible \
  >"$test_root/plugin-collision.log" 2>&1; then
  fail 'repinning overwrote an ignored user file'
fi
assert_plugin "$test_home/dotfiles-releases/online/share/tmux/plugins" tmux-sensible "${newer_commits[tmux-sensible]}"
[[ $(<"$checkout/ignored-note") == 'keep this ignored note' ]] ||
  fail 'repinning changed an ignored user file'
mv "$checkout/ignored-note" "$test_root/ignored-note-backup"
printf 'TMUX_PLUGINS[tmux-sensible]=%q\n' \
  "https://example.invalid/tmux/tmux-sensible.git|$broken_commit" \
  >>"$test_repository/tools.env"
if run_setup "$test_home" "$test_repository" "$archive_root" tmux-sensible \
  >"$test_root/broken-plugin.log" 2>&1; then
  fail 'setup selected a plugin without an executable entry point'
fi
assert_plugin "$test_home/dotfiles-releases/online/share/tmux/plugins" tmux-sensible "${newer_commits[tmux-sensible]}"
printf 'TMUX_PLUGINS[tmux-sensible]=%q\n' \
  "https://example.invalid/tmux/tmux-sensible.git|${newer_commits[tmux-sensible]}" \
  >>"$test_repository/tools.env"

git config --file "$GIT_CONFIG_GLOBAL" \
  "url.file://$test_root/missing/.insteadOf" https://example.invalid/tmux/
git config --file "$GIT_CONFIG_GLOBAL" --unset-all \
  "url.file://$test_root/origins/.insteadOf"
run_setup "$test_home" "$test_repository" "$archive_root" "${plugins[@]}"
printf 'TMUX_PLUGINS[tmux-sensible]=%q\n' \
  "https://example.invalid/tmux/tmux-sensible.git|$(printf '%040d' 3)" \
  >>"$test_repository/tools.env"
if run_setup "$test_home" "$test_repository" "$archive_root" tmux-sensible \
  >"$test_root/fetch-failure.log" 2>&1; then
  fail 'setup accepted an unavailable plugin commit'
fi
assert_plugin "$test_home/dotfiles-releases/online/share/tmux/plugins" tmux-sensible "${newer_commits[tmux-sensible]}"
[[ $(<"$checkout/local-notes") == 'keep this note' ]] ||
  fail 'a failed fetch changed user notes'

failed_home=$test_root/failed-home
if run_setup "$failed_home" "$test_repository" "$archive_root" tmux-resurrect \
  >"$test_root/clone-failure.log" 2>&1; then
  fail 'setup hid a plugin clone failure'
fi
[[ ! -e $failed_home/dotfiles-releases/online/share/tmux/plugins/tmux-resurrect &&
  -z $(find "$failed_home/dotfiles-releases/online/share/tmux/plugins" -mindepth 1 -print -quit) ]] ||
  fail 'a failed clone left a partial plugin checkout'
git config --file "$GIT_CONFIG_GLOBAL" --unset-all \
  "url.file://$test_root/missing/.insteadOf"
git config --file "$GIT_CONFIG_GLOBAL" \
  "url.file://$test_root/origins/.insteadOf" https://example.invalid/tmux/
printf 'TMUX_PLUGINS[tmux-sensible]=%q\n' \
  "https://example.invalid/tmux/tmux-sensible.git|${pinned_commits[tmux-sensible]}" \
  >>"$test_repository/tools.env"

dirty_home=$test_root/dirty-home
run_setup "$dirty_home" "$test_repository" "$archive_root" tmux-sensible
dirty_checkout=$dirty_home/dotfiles-releases/online/share/tmux/plugins/tmux-sensible
printf '# local edit\n' >>"$dirty_checkout/sensible.tmux"
dirty_hash=$(sha256sum "$dirty_checkout/sensible.tmux")
if run_setup "$dirty_home" "$test_repository" "$archive_root" tmux tmux-resurrect tmux-sensible \
  >"$test_root/dirty-plugin.log" 2>&1; then
  fail 'setup overwrote a modified plugin checkout'
fi
[[ $(sha256sum "$dirty_checkout/sensible.tmux") == "$dirty_hash" &&
  ! -e $dirty_home/dotfiles-releases/online/bin/tmux &&
  ! -e $dirty_home/dotfiles-releases/online/share/tmux/plugins/tmux-resurrect ]] ||
  fail 'plugin preflight changed the checkout or installed another requested tool'

foreign_home=$test_root/foreign-home
mkdir -p "$foreign_home/dotfiles-releases/online/share/tmux/plugins"
ln -s "$checkout" "$foreign_home/dotfiles-releases/online/share/tmux/plugins/tmux-sensible"
if run_setup "$foreign_home" "$test_repository" "$archive_root" tmux-sensible \
  >"$test_root/plugin-symlink.log" 2>&1; then
  fail 'setup accepted an offline or foreign plugin symlink'
fi
assert_link "$foreign_home/dotfiles-releases/online/share/tmux/plugins/tmux-sensible" "$checkout"

git -C "$dirty_checkout" checkout -- sensible.tmux
git -C "$dirty_checkout" remote set-url origin https://example.invalid/foreign.git
if run_setup "$dirty_home" "$test_repository" "$archive_root" tmux-sensible \
  >"$test_root/plugin-origin.log" 2>&1; then
  fail 'setup accepted a plugin with an unexpected origin'
fi
[[ $(git -C "$dirty_checkout" remote get-url origin) == https://example.invalid/foreign.git ]] ||
  fail 'setup rewrote a foreign origin'

custom_home=$test_root/custom-home
custom_root=$test_root/custom-release-root
DOTFILES_RELEASE_ROOT="$custom_root" \
  run_setup "$custom_home" "$test_repository" "$archive_root" tmux-continuum
assert_plugin "$custom_root/online/share/tmux/plugins" tmux-continuum "${pinned_commits[tmux-continuum]}"
[[ ! -e $custom_home/.tmux && ! -e $custom_home/dotfiles-releases ]] ||
  fail 'custom release setup also used the default root'

space_root=$test_root/'custom release root with spaces'
if DOTFILES_RELEASE_ROOT="$space_root" \
  run_setup "$test_root/space-root-home" "$test_repository" "$archive_root" tmux-continuum \
  >"$test_root/space-root.log" 2>&1; then
  fail 'setup accepted an unsupported upstream plugin directory with spaces'
fi
[[ ! -e $space_root/online/share/tmux/plugins/tmux-continuum &&
  $(<"$test_root/space-root.log") == *'without whitespace'* ]] ||
  fail 'unsupported plugin path was published or not explained'

unsupported_root=$test_root/invalid-root
printf 'private root contents\n' >"$unsupported_root"
if DOTFILES_RELEASE_ROOT="$unsupported_root" \
  run_setup "$test_root/unsupported-root-home" "$test_repository" "$archive_root" tmux-sensible \
  >"$test_root/unsupported-root.log" 2>&1; then
  fail 'setup accepted a release root that is a regular file'
fi
[[ $(<"$unsupported_root") == 'private root contents' &&
  $(<"$test_root/unsupported-root.log") == *'invalid release root'* ]] ||
  fail 'invalid root was changed or not explained'

offline_root=$test_root/release/share/tmux/plugins
HOME="$test_root/offline-home" bash -eu -o pipefail -s -- \
  "$test_repository" "$offline_root" "${plugins[@]}" <<'EOF'
repository=$1 root=$2
shift 2
source "$repository/scripts/setup-lib"
source "$repository/scripts/setup-catalog-lib"
source "$repository/scripts/setup-recipes-lib"
source "$repository/scripts/setup-tools-lib"
source "$repository/scripts/setup-tmux-lib"
source "$repository/tools.env"
TEMP_PATHS=()
trap cleanup_setup EXIT
install_tmux_plugins "$root" "$@"
EOF
for plugin in "${plugins[@]}"; do
  assert_plugin "$offline_root" "$plugin" "${pinned_commits[$plugin]}"
done
[[ ! -e $test_root/offline-home ]] || fail 'offline plugin installation changed HOME'

selected_release=$test_root/selected-release
selected_plugin=$selected_release/share/tmux/plugins/tmux-sensible/sensible.tmux
mkdir -p "$(dirname -- "$selected_plugin")"
cat >"$selected_plugin" <<'EOF'
#!/usr/bin/env bash
printf 'tmux-sensible\n' >>"$TEST_LOADED_PLUGINS"
EOF
chmod 0755 "$selected_plugin"
printf 'OFFLINE_RELEASE_TOOLS=tmux,tmux-sensible\n' >"$selected_release/release.env"
loaded_plugins=$test_root/loaded-plugins
TEST_LOADED_PLUGINS="$loaded_plugins" TMUX_OFFLINE_RELEASE_ROOT="$selected_release" \
  bash "$repo_dir/tmux/.tmux/load-plugins.sh"
[[ $(<"$loaded_plugins") == tmux-sensible ]] || fail 'loader ignored the release plugin selection'
space_release=$test_root/'selected release with spaces'
cp -a -- "$selected_release" "$space_release"
: >"$loaded_plugins"
if TEST_LOADED_PLUGINS="$loaded_plugins" TMUX_OFFLINE_RELEASE_ROOT="$space_release" \
  bash "$repo_dir/tmux/.tmux/load-plugins.sh" >"$test_root/space-plugin-loader.log" 2>&1; then
  fail 'loader accepted an unsupported upstream plugin directory with spaces'
fi
[[ ! -s $loaded_plugins && $(<"$test_root/space-plugin-loader.log") == *'without whitespace'* ]] ||
  fail 'unsupported plugin path was run or not explained'
printf 'OFFLINE_RELEASE_TOOLS=tmux\n' >"$selected_release/release.env"
: >"$loaded_plugins"
TEST_LOADED_PLUGINS="$loaded_plugins" TMUX_OFFLINE_RELEASE_ROOT="$selected_release" \
  bash "$repo_dir/tmux/.tmux/load-plugins.sh"
[[ ! -s $loaded_plugins ]] || fail 'loader ran a plugin omitted from the release selection'
printf 'OFFLINE_RELEASE_TOOLS=tmux,tmux-resurrect\n' >"$selected_release/release.env"
if TMUX_OFFLINE_RELEASE_ROOT="$selected_release" bash "$repo_dir/tmux/.tmux/load-plugins.sh" \
  >"$test_root/missing-selected-plugin.log" 2>&1; then
  fail 'loader accepted a missing selected plugin'
fi
[[ $(<"$test_root/missing-selected-plugin.log") == *'missing '*'/tmux-resurrect/resurrect.tmux'* ]] ||
  fail 'loader did not explain the missing selected plugin'

printf 'Setup tools plugin tests passed\n'
