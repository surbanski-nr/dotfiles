#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=fixture.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/fixture.sh"
create_fixture

single_repository=$test_root/single-repository
single_home=$test_root/single-home
make_test_repo "$single_repository"
cp "$test_repository/tools.env" "$single_repository/tools.env"
printf 'TOOLS=(fd)\n' >>"$single_repository/tools.env"
run_setup "$single_home" "$single_repository" "$archive_root"
"$single_home/dotfiles-releases/online/bin/fd" --version | grep -F "$FD_VERSION" >/dev/null
[[ $(find "$single_home/dotfiles-releases/online/bin" -mindepth 1 -maxdepth 1 | wc -l) -eq 2 ]] ||
  fail 'single-tool default installation installed unselected tools'
[[ ! -e $single_home/.tmux ]] || fail 'single-tool default installation installed tmux plugins'

node_repository=$test_root/node-repository
node_home=$test_root/node-home
node_archives=$test_root/node-archives
node_work=$test_root/node-work
node_version=99.7.0
npm_version=1.2.3
node_tree=node-v$node_version-linux-x64
make_test_repo "$node_repository"
mkdir -p "$node_work/$node_tree/bin" "$node_work/package" "$node_archives"
write_fake "$node_work/$node_tree/bin/node" node "$node_version"
write_fake "$node_work/$node_tree/bin/npx" npx "$npm_version"
write_fake "$node_work/$node_tree/bin/corepack" corepack "$npm_version"
printf '0.9.0\n' >"$node_work/$node_tree/bin/npm-version"
cat >"$node_work/$node_tree/bin/npm" <<EOF
#!/usr/bin/env bash
set -euo pipefail
[[ \$(node --version) == 'node $node_version' ]] || exit 92
version_file=\$(dirname -- "\$(readlink -f -- "\$0")")/npm-version
case \$1 in
  --version)
    cat "\$version_file"
    ;;
  install)
    printf '%s\n' '$npm_version' >"\$version_file"
    ;;
  *)
    exit 93
    ;;
esac
EOF
chmod 0755 "$node_work/$node_tree/bin/npm"
printf 'npm fixture\n' >"$node_work/package/README"
tar -C "$node_work" -cJf "$node_archives/node.tar.xz" "$node_tree"
tar -C "$node_work" -czf "$node_archives/npm.tgz" package
append_release "$node_repository/tools.env" TOOL_RELEASES nodejs "$node_version" \
  https://example.invalid/node.tar.xz "$(sha256sum "$node_archives/node.tar.xz" | awk '{print $1}')"
append_release "$node_repository/tools.env" TOOL_RELEASES npm "$npm_version" \
  https://example.invalid/npm.tgz "$(sha256sum "$node_archives/npm.tgz" | awk '{print $1}')"
printf 'TOOLS=(nodejs)\n' >>"$node_repository/tools.env"
run_setup "$node_home" "$node_repository" "$node_archives" >/dev/null
node_bin=$node_home/dotfiles-releases/online/bin
[[ $("$node_bin/node" --version) == "node $node_version" &&
  $(PATH="$node_bin:/usr/bin:/bin" "$node_bin/npm" --version) == "$npm_version" ]] ||
  fail 'cold Node setup did not prepare its own SDK with the pinned npm'

selection_repository=$test_root/selection-repository
selection_home=$test_root/selection-home
make_test_repo "$selection_repository"
cp "$test_repository/tools.env" "$selection_repository/tools.env"
printf 'TOOLS=(fd k9s)\n' >>"$selection_repository/tools.env"
mkdir -p "$selection_home/bin"
write_fake "$selection_home/bin/k9s" k9s user-override
override_digest=$(sha256sum "$selection_home/bin/k9s")
run_setup "$selection_home" "$selection_repository" "$archive_root" >/dev/null
printf 'TOOLS=(fd)\n' >>"$selection_repository/tools.env"
run_setup "$selection_home" "$selection_repository" "$archive_root" fd >/dev/null
[[ -x $selection_home/dotfiles-releases/online/bin/k9s ]] ||
  fail 'a named setup request removed another tool'
run_setup "$selection_home" "$selection_repository" "$archive_root" >/dev/null
[[ ! -e $selection_home/dotfiles-releases/online/bin/k9s &&
  ! -L $selection_home/dotfiles-releases/online/bin/k9s &&
  -x $selection_home/dotfiles-releases/online/tools/bin/k9s-$K9S_VERSION &&
  $(sha256sum "$selection_home/bin/k9s") == "$override_digest" ]] ||
  fail 'deselecting a tool kept its command or changed retained data or a user override'

mkdir -p "$test_home"
printf 'private context bytes' >"$test_home/kube-backup-contexts.txt"
printf 'private prefix bytes' >"$test_home/kube-log-prefixes.txt"
cp "$test_home/kube-backup-contexts.txt" "$test_root/kube-context-before"
cp "$test_home/kube-log-prefixes.txt" "$test_root/kube-prefix-before"
test_xdg=$test_root/'xdg elsewhere'

before=$(find "$archive_root" -type f -print0 | sort -z | xargs -0 sha256sum)
# The downloader reads the growing log to check progress before starting.
# shellcheck disable=SC2094
TEST_EXPECTED_INSTALL_PROGRESS="setup-tools: installing k9s $K9S_VERSION" \
  TEST_INSTALL_PROGRESS_LOG="$test_root/install-progress.log" XDG_CONFIG_HOME="$test_xdg" \
  run_setup "$test_home" "$test_repository" "$archive_root" \
  k9s gh htop oh-my-posh uv nvim fd go kind tmux yq >"$test_root/install-progress.log"
after=$(find "$archive_root" -type f -print0 | sort -z | xargs -0 sha256sum)
[[ $before == "$after" ]] || fail 'setup-tools changed a download fixture'
cmp "$test_root/kube-context-before" "$test_home/kube-backup-contexts.txt" ||
  fail 'setup-tools changed kube-backup-contexts.txt'
cmp "$test_root/kube-prefix-before" "$test_home/kube-log-prefixes.txt" ||
  fail 'setup-tools changed kube-log-prefixes.txt'
[[ ! -e $test_xdg/kube-backup-contexts.txt &&
  ! -e $test_xdg/kube-log-prefixes.txt ]] ||
  fail 'setup-tools relocated private Kubernetes inputs into XDG_CONFIG_HOME'

load_test_versions "$test_repository"
assert_link "$test_home/dotfiles-releases/online/bin/k9s" "../tools/bin/k9s-$K9S_VERSION"
assert_link "$test_home/dotfiles-releases/online/bin/kind" "../tools/bin/kind-$KIND_VERSION"
assert_link "$test_home/dotfiles-releases/online/bin/gh" "../tools/bin/gh-$GH_VERSION"
assert_link "$test_home/dotfiles-releases/online/bin/htop" "../tools/htop-$HTOP_VERSION/bin/htop"
assert_link "$test_home/dotfiles-releases/online/bin/oh-my-posh" "../tools/bin/oh-my-posh-$OMP_VERSION"
assert_link "$test_home/dotfiles-releases/online/bin/uv" "../tools/bin/uv-$UV_VERSION"
assert_link "$test_home/dotfiles-releases/online/bin/uvx" "../tools/bin/uvx-$UV_VERSION"
assert_link "$test_home/dotfiles-releases/online/bin/nvim" "../tools/nvim-$NVIM_VERSION/bin/nvim"
assert_link "$test_home/dotfiles-releases/online/bin/fd" "../tools/bin/fd-$FD_VERSION"
assert_link "$test_home/dotfiles-releases/online/bin/go" "../tools/go-$GO_VERSION/bin/go"
assert_link "$test_home/dotfiles-releases/online/bin/gofmt" "../tools/go-$GO_VERSION/bin/gofmt"
assert_link "$test_home/dotfiles-releases/online/bin/tmux" "../tools/tmux-$TMUX_VERSION/bin/tmux"
"$test_home/dotfiles-releases/online/bin/yq" --version | grep -F "yq $YQ_VERSION" >/dev/null
"$test_home/dotfiles-releases/online/bin/go" version | grep -F "$GO_VERSION" >/dev/null
[[ -f $test_home/dotfiles-releases/online/tools/go-$GO_VERSION/src/fmt/print.go &&
  -f $test_home/dotfiles-releases/online/tools/go-$GO_VERSION/pkg/tool/linux_amd64/compile ]] ||
  fail 'Go SDK standard library or compiler tree was not retained'
"$test_home/dotfiles-releases/online/bin/fd" --version | grep -F "$FD_VERSION" >/dev/null
[[ -f $test_home/dotfiles-releases/online/tools/nvim-$NVIM_VERSION/share/nvim/runtime/syntax/test.vim ]] ||
  fail 'Neovim runtime tree was not retained'
"$test_home/dotfiles-releases/online/bin/k9s" version --short | grep -F "$K9S_VERSION" >/dev/null
"$test_home/dotfiles-releases/online/bin/kind" version | grep -F "$KIND_VERSION" >/dev/null
"$test_home/dotfiles-releases/online/bin/uvx" --version | grep -F "$UV_VERSION" >/dev/null
"$test_home/dotfiles-releases/online/bin/htop" --version | grep -F "$HTOP_VERSION" >/dev/null
"$test_home/dotfiles-releases/online/bin/tmux" -V | grep -F "$TMUX_VERSION" >/dev/null

default_repository=$test_root/default-repository
default_home=$test_root/default-home
make_test_repo "$default_repository"
cp "$test_repository/tools.env" "$default_repository/tools.env"
printf 'TOOLS=(fd k9s gh oh-my-posh python uv nvim go kind yq)\n' >>"$default_repository/tools.env"
TEST_UV_LOG="$test_root/default-python.log" XDG_CONFIG_HOME="$default_home/.config" \
  run_setup "$default_home" "$default_repository" "$archive_root"
for tool in fd k9s gh oh-my-posh uv uvx nvim go gofmt kind yq; do
  [[ -x $default_home/dotfiles-releases/online/bin/$tool ]] || fail "default online install omitted $tool"
done
[[ $(<"$default_home/.config/uv/.python-version") == "$PYTHON_VERSION" ]] ||
  fail 'default setup-tools did not select catalog Python through uv'

find "$archive_root" -depth -delete
XDG_CONFIG_HOME="$test_xdg" run_setup "$test_home" "$test_repository" "$archive_root" \
  k9s gh htop uv nvim go tmux yq
cmp "$test_root/kube-context-before" "$test_home/kube-backup-contexts.txt" ||
  fail 'setup-tools reconciliation changed kube-backup-contexts.txt'
cmp "$test_root/kube-prefix-before" "$test_home/kube-log-prefixes.txt" ||
  fail 'setup-tools reconciliation changed kube-log-prefixes.txt'

printf 'setup-tools tests: install passed\n'
