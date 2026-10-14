#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=fixture.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/fixture.sh"
create_fixture

mkdir -p "$test_home"
printf 'private context bytes' >"$test_home/kube-backup-contexts.txt"
printf 'private prefix bytes' >"$test_home/kube-log-prefixes.txt"
cp "$test_home/kube-backup-contexts.txt" "$test_root/kube-context-before"
cp "$test_home/kube-log-prefixes.txt" "$test_root/kube-prefix-before"
test_xdg=$test_root/'xdg elsewhere'

before=$(find "$archive_root" -type f -print0 | sort -z | xargs -0 sha256sum)
XDG_CONFIG_HOME="$test_xdg" run_setup "$test_home" "$test_repository" "$archive_root" \
  k9s gh htop oh-my-posh uv nvim fd go kind tmux
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
assert_link "$test_home/bin/k9s" "k9s-$K9S_VERSION"
assert_link "$test_home/bin/kind" "kind-$KIND_VERSION"
assert_link "$test_home/bin/gh" "gh-$GH_VERSION"
assert_link "$test_home/bin/htop" "htop-$HTOP_VERSION/bin/htop"
assert_link "$test_home/bin/oh-my-posh" "oh-my-posh-$OMP_VERSION"
assert_link "$test_home/bin/uv" "uv-$UV_VERSION"
assert_link "$test_home/bin/uvx" "uvx-$UV_VERSION"
assert_link "$test_home/bin/nvim" "nvim-$NVIM_VERSION/bin/nvim"
assert_link "$test_home/bin/fd" "fd-$FD_VERSION"
assert_link "$test_home/bin/go" "go-$GO_VERSION/bin/go"
assert_link "$test_home/bin/gofmt" "go-$GO_VERSION/bin/gofmt"
assert_link "$test_home/bin/tmux" "tmux-$TMUX_VERSION/bin/tmux"
"$test_home/bin/go" version | grep -F "$GO_VERSION" >/dev/null
[[ -f $test_home/bin/go-$GO_VERSION/src/fmt/print.go &&
  -f $test_home/bin/go-$GO_VERSION/pkg/tool/linux_amd64/compile ]] ||
  fail 'Go SDK standard library or compiler tree was not retained'
"$test_home/bin/fd" --version | grep -F "$FD_VERSION" >/dev/null
[[ -f $test_home/bin/nvim-$NVIM_VERSION/share/nvim/runtime/syntax/test.vim ]] ||
  fail 'Neovim runtime tree was not retained'
"$test_home/bin/k9s" version --short | grep -F "$K9S_VERSION" >/dev/null
"$test_home/bin/kind" version | grep -F "$KIND_VERSION" >/dev/null
"$test_home/bin/uvx" --version | grep -F "$UV_VERSION" >/dev/null
"$test_home/bin/htop" --version | grep -F "$HTOP_VERSION" >/dev/null
"$test_home/bin/tmux" -V | grep -F "$TMUX_VERSION" >/dev/null

default_repository=$test_root/default-repository
default_home=$test_root/default-home
make_test_repo "$default_repository"
cp "$test_repository/tools.env" "$default_repository/tools.env"
printf 'TOOLS=(fd k9s gh oh-my-posh python uv nvim go kind)\n' >>"$default_repository/tools.env"
TEST_UV_LOG="$test_root/default-python.log" XDG_CONFIG_HOME="$default_home/.config" \
  run_setup "$default_home" "$default_repository" "$archive_root"
for tool in fd k9s gh oh-my-posh uv uvx nvim go gofmt kind; do
  [[ -x $default_home/bin/$tool ]] || fail "default online install omitted $tool"
done
[[ $(<"$default_home/.config/uv/.python-version") == "$PYTHON_VERSION" ]] ||
  fail 'default setup-tools did not select catalog Python through uv'

find "$archive_root" -depth -delete
XDG_CONFIG_HOME="$test_xdg" run_setup "$test_home" "$test_repository" "$archive_root" \
  k9s gh htop uv nvim go tmux
cmp "$test_root/kube-context-before" "$test_home/kube-backup-contexts.txt" ||
  fail 'setup-tools reconciliation changed kube-backup-contexts.txt'
cmp "$test_root/kube-prefix-before" "$test_home/kube-log-prefixes.txt" ||
  fail 'setup-tools reconciliation changed kube-log-prefixes.txt'

printf 'setup_tools: install passed\n'
