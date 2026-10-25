#!/usr/bin/env bash

set -euo pipefail

unset DOTFILES_IGNORE_USER_BIN

repo_dir=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
test_root=$(mktemp -d)
trap 'find "$test_root" -depth -delete' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

original=$test_root/original
release=$test_root/'relocated release with spaces'
test_home="$test_root/home with spaces"
mkdir -p "$original/bin" "$original/tools/go/bin" "$test_home/bin"
: >"$original/installed.sha256"
: >"$original/tools/go/bin/go"
chmod 0755 "$original/tools/go/bin/go"
for tool in nvim tmux; do
  mkdir -p "$original/tools/$tool/bin"
  install -m 0755 "$repo_dir/scripts/offline-$tool" "$original/bin/$tool"
  install -m 0755 "$repo_dir/tests/fixtures/scripts/launcher-tool" "$original/tools/$tool/bin/$tool"
done
mv -T -- "$original" "$release"
ln -s "$release" "$test_root/current"
release_bin=$test_root/current/bin

output=$(env -u NVIM_APPNAME HOME="$test_home" XDG_CONFIG_HOME=/user/config \
  XDG_DATA_HOME=/user/data GOROOT=/project/sdk GOTOOLCHAIN=auto \
  "$release_bin/nvim" -- 'literal ; value' '')
[[ $output == *"tool=$release/tools/nvim/bin/nvim"* && $output == *'app=nvim2'* &&
  $output == *"config=$release/config"* && $output == *"data=$release/share"* &&
  $output == *$'GOROOT=unset\nGOTOOLCHAIN=local'* &&
  $output == *$'<-->\n<literal ; value>\n<>' ]] ||
  fail "Nvim lost its release, isolated environment or literal arguments: $output"

output=$(HOME="$test_home" NVIM_APPNAME=personal XDG_CONFIG_HOME=/user/config \
  XDG_DATA_HOME=/user/data "$release_bin/nvim" file)
[[ $output == *'app=personal'* && $output == *$'config=/user/config\ndata=/user/data'* ]] ||
  fail 'Nvim changed the environment for a separate user profile'

output=$(HOME="$test_home" NVIM_APPNAME=nvim2 XDG_CONFIG_HOME=/user/config \
  XDG_DATA_HOME=/user/data GOROOT=/project/sdk GOTOOLCHAIN=auto \
  TERM=xterm-256color TEST_REPO_DIR="$repo_dir" TEST_SCENARIO=launcher-environment \
  "$release_bin/nvim" fixture-shell 2>"$test_root/shell.log")
[[ $output == *'xdg-config=/user/config xdg-data=/user/data'* &&
  $output == *'go-root=/project/sdk go-toolchain=auto'* ]] ||
  fail 'a shell started from Nvim did not recover the user environment'

printf '#!/usr/bin/env bash\nprintf "release\\n"\n' >"$release/bin/path-probe"
chmod 0755 "$release/bin/path-probe"
for provider in bin 'project venv/bin'; do
  mkdir -p "$test_home/$provider"
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" %q\n' "$provider" \
    >"$test_home/$provider/path-probe"
  chmod 0755 "$test_home/$provider/path-probe"
done
output=$(HOME="$test_home" PATH="$test_home/bin:$PATH" \
  "$release_bin/nvim" fixture-path)
[[ $output == *'selected=bin'* ]] || fail 'launcher demoted user bin'
output=$(HOME="$test_home" VIRTUAL_ENV="$test_home/project venv" \
  "$release_bin/nvim" fixture-path)
[[ $output == *'selected=project venv/bin'* ]] || fail 'launcher demoted the active venv'
output=$(HOME="$test_home" DOTFILES_IGNORE_USER_BIN=1 \
  PATH="$test_home/bin:$PATH" "$release_bin/nvim" fixture-path)
[[ $output == *'selected=release'* && $output != *"$test_home/bin"* ]] ||
  fail 'launcher retained ignored user bin'
output=$(HOME="$test_home" TEST_REPO_DIR="$repo_dir" TEST_SCENARIO=path-selection \
  "$release_bin/nvim" fixture-shell 2>"$test_root/shell.log")
[[ $output == *'selected=bin'* ]] || fail 'nested Bash lost user bin'

config=$release/dotfiles/tmux/.tmux.conf
output=$("$release_bin/tmux" new-session 'literal ; value' '')
[[ $output == *"tool=$release/tools/tmux/bin/tmux"* && $output == *"tmux-config=$config"* &&
  $output == *"$(printf '<-f>\n<%s>\n<new-session>\n<literal ; value>\n<>' "$config")" ]] ||
  fail "tmux lost its release configuration or literal arguments: $output"
output=$("$release_bin/tmux" -f '/user/config with spaces' new-session)
[[ $output == *$'<-f>\n</user/config with spaces>\n<new-session>' &&
  $output != *"<$config>"* ]] || fail 'tmux replaced an explicit configuration'

for tool in nvim tmux; do
  if FIXTURE_LAUNCHER_EXIT_CODE=42 "$release_bin/$tool" --version >/dev/null; then
    fail "$tool hid the child exit status"
  else
    [[ $? -eq 42 ]] || fail "$tool changed the child exit status"
  fi
done

mkdir -p "$release/tools/bin" "$release/share/helm/plugins"
for tool in helm kubectl; do
  install -m 0755 "$repo_dir/scripts/offline-kubernetes-client" "$release/bin/$tool"
  for version in 1.2.3 2.3.4; do
    install -m 0755 "$repo_dir/tests/fixtures/scripts/launcher-tool" "$release/tools/bin/$tool-$version"
  done
  ln -s "$tool-1.2.3" "$release/tools/bin/$tool"
  for selection in '' 1.2.3 v1.2.3 2.3.4 v2.3.4; do
    output=$(env "${tool^^}_VERSION=$selection" "$release_bin/$tool" -- 'literal ; value' '')
    [[ $output == *"tool=$release/tools/bin/$tool-${selection#v}"* ||
      ( -z $selection && $output == *"tool=$release/tools/bin/$tool-1.2.3"* ) ]] ||
      fail "$tool selected the wrong version: $selection"
    [[ $output == *$'<-->\n<literal ; value>\n<>' ]] || fail "$tool changed literal arguments"
  done
  for selection in vv1.2.3 ../1.2.3 '1.2.3;echo' 9.8.7; do
    if env "${tool^^}_VERSION=$selection" "$release_bin/$tool" >"$test_root/client-error.log" 2>&1; then
      fail "$tool accepted invalid or unbundled version $selection"
    else
      status=$?
      [[ ( $selection == 9.8.7 && $status -eq 127 ) || ( $selection != 9.8.7 && $status -eq 2 ) ]] ||
        fail "$tool returned the wrong selector failure status"
    fi
  done
  if FIXTURE_LAUNCHER_EXIT_CODE=42 "$release_bin/$tool" --version >/dev/null; then
    fail "$tool hid the child exit status"
  else
    [[ $? -eq 42 ]] || fail "$tool changed the child exit status"
  fi
done
for selection in unset empty override; do
  case $selection in
    unset) output=$(env -u HELM_PLUGINS "$release_bin/helm") ;;
    empty) output=$(HELM_PLUGINS='' "$release_bin/helm") ;;
    override) output=$(HELM_PLUGINS="$test_root/user plugins" "$release_bin/helm") ;;
  esac
  expected=$release/share/helm/plugins
  [[ $selection != override ]] || expected=$test_root/'user plugins'
  [[ $output == *"helm-plugins=$expected"* ]] || fail 'Helm lost its bundled or explicit plugin directory'
done
export HELM_PLUGINS="$test_root/user plugins"
"$release_bin/helm" >/dev/null
[[ $HELM_PLUGINS == "$test_root/user plugins" ]] || fail 'Helm launcher changed its parent environment'
unset HELM_PLUGINS
legacy=$test_root/'legacy release'
mkdir -p "$legacy/bin" "$legacy/tools/bin"
cp "$release/bin/helm" "$legacy/bin/helm"
cp "$release/tools/bin/helm-1.2.3" "$legacy/tools/bin/helm"
unlink "$test_root/current"
ln -s "$legacy" "$test_root/current"
output=$(env -u HELM_PLUGINS "$release_bin/helm")
[[ $output == *"tool=$legacy/tools/bin/helm"* && $output == *'helm-plugins=unset'* ]] ||
  fail 'legacy Helm borrowed the plugin from another release'
output=$(HELM_PLUGINS='' "$release_bin/helm")
[[ $output == *$'helm-plugins=\n'* ]] || fail 'legacy Helm changed empty plugin discovery'

printf 'Offline Nvim and tmux launcher tests passed\n'
