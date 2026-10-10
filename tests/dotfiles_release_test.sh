#!/usr/bin/env bash

set -euo pipefail

repo_dir=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
test_root=$(mktemp -d)
os_release=$test_root/os-release

cleanup() {
  if [[ -n ${lock_holder_pid:-} ]]; then
    kill "$lock_holder_pid" 2>/dev/null || true
    wait "$lock_holder_pid" 2>/dev/null || true
  fi
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
  local version=${2:-1.0}
  mkdir -p "$(dirname -- "$path")"
  cat >"$path" <<EOF
#!/usr/bin/env bash
set -euo pipefail
 self=\$(readlink -f -- "\$0")
if [[ \${1:-} == hold ]]; then
  printf 'before=%s\n' "\$self" >"\$2"
  sleep 2
  printf 'after=%s\n' "\$self" >>"\$2"
  exit 0
fi
case \$(basename -- "\$0") in
  k9s) [[ \$* == 'version --short' ]] || exit 93 ;;
  oh-my-posh | terraform) [[ \$* == version ]] || exit 94 ;;
  tmux) [[ \$* == -V ]] || exit 95 ;;
esac
printf '%s fixture $version\n' "\$(basename -- "\$0")"
EOF
  if [[ ${path##*/} == nvim ]]; then
    cat >>"$path" <<'EOF'
release=${self%/tools/nvim/bin/nvim}
[[ ${DOTFILES_OFFLINE_RELEASE_ROOT:-} == "$release" ]] || exit 96
EOF
  fi
  if [[ ${path##*/} == kubectl-* || ${path##*/} == helm-* ]]; then
    cat >>"$path" <<'EOF'
if [[ ${1:-} == fixture-args ]]; then
  shift
  printf '<%s>\n' "$@"
elif [[ ${1:-} == fixture-fail ]]; then
  exit 42
fi
EOF
  fi
  chmod 0755 "$path"
}

write_fake_python() {
  local path=$1
  mkdir -p "$(dirname -- "$path")"
  cat >"$path" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ ${FIXTURE_FAIL_PYTHON_IMPORT:-} == 1 &&
  ${1:-} == -I && ${2:-} == - && ${!#} == ansible-lint ]]; then
  exit 95
fi
if [[ " $* " == *' -m venv '* ]]; then
  destination=${!#}
  mkdir -p "$destination/bin"
  printf 'home = fixture\n' >"$destination/pyvenv.cfg"
  cp "$0" "$destination/bin/python"
  for command_name in ansible ansible-config ansible-lint ansible-playbook yamllint; do
    printf '%s\n' \
      '#!/usr/bin/env bash' \
      'if [[ $(basename -- "$0") == ansible-lint && " $* " != *" --offline "* ]]; then exit 97; fi' \
      'printf "%s fixture 1.0\n" "$(basename -- "$0")"' \
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
  local release_version=${4:-1.0}
  local include_fd=${5:-true}
  local offline_profile=nvim,nodejs,python,rg,tmux,oh-my-posh,k9s,zoxide,kubectx,kubens,task,fzf,terraform,kubectl,helm
  local id=dotfiles-${commit:0:12}
  local stage=$test_root/stage-$marker release=$test_root/stage-$marker/$id
  local command_name plugin plugin_dir version

  mkdir -p "$release/bin" "$release/config/nvim2/tests" \
    "$release/dotfiles/bash" "$release/dotfiles/git" \
    "$release/dotfiles/tmux" "$release/dotfiles/vim" \
    "$release/dotfiles/oh-my-posh" \
    "$release/dotfiles/k9s/.config/k9s/skins" \
    "$release/share/nvim2/mason/bin" "$release/share/nvim2/mason/packages/ansible-lint" \
    "$release/share/nvim2/mason/packages/yamllint" \
    "$release/python-wheelhouse" "$release/share/tmux/plugins" \
    "$release/tools/bin" "$release/tools/nvim/bin" "$release/tools/tmux/bin"

  {
    printf '#!/usr/bin/env bash\n'
    cat "$repo_dir/tools-probes.env" "$repo_dir/scripts/dotfiles-release"
  } >"$release/dotfiles-release"
  chmod 0755 "$release/dotfiles-release"
  ln -s ../dotfiles-release "$release/bin/dotfiles-release"
  for command_name in nvim tmux; do
    write_fake_tool "$release/tools/$command_name/bin/$command_name" "$release_version"
  done
  write_fake_python "$release/tools/python-3.12.12/bin/python3"
  for command_name in node npm npx corepack rg zoxide k9s kubectx kubens \
    oh-my-posh task fzf terraform; do
    write_fake_tool "$release/tools/bin/$command_name" "$release_version"
    ln -s "../tools/bin/$command_name" "$release/bin/$command_name"
  done
  for command_name in kubectl helm; do
    for version in "$release_version" 0.9; do
      write_fake_tool "$release/tools/bin/$command_name-$version" "$version"
      ln -s "../tools/bin/$command_name-$version" "$release/bin/$command_name-$version"
    done
    ln -s "$command_name-$release_version" "$release/tools/bin/$command_name"
    install -m 0755 "$repo_dir/scripts/offline-kubernetes-client" "$release/bin/$command_name"
  done
  if [[ $include_fd == true ]]; then
    write_fake_tool "$release/tools/bin/fd" "$release_version"
    ln -s ../tools/bin/fd "$release/bin/fd"
    offline_profile+=,fd
  fi
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
    'if [[ -f $release/installed.sha256 ]]; then export DOTFILES_OFFLINE_RELEASE_ROOT="$release"; fi' \
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
  printf 'ansible-lint==26.1.1\n' >"$release/python-locks/ansible-lint.in"
  printf 'ansible-lint==26.1.1 --hash=sha256:fixture\n' \
    >"$release/python-locks/ansible-lint.lock"
  printf 'yamllint==1.38.0\n' >"$release/python-locks/yamllint.in"
  printf 'yamllint==1.38.0 --hash=sha256:fixture\n' >"$release/python-locks/yamllint.lock"
  printf 'ansible-lint\t26.1.1\nyamllint\t1.38.0\n' \
    >"$release/python-locks/inventory.tsv"
  printf 'fixture wheel\n' >"$release/python-wheelhouse/fixture.whl"
  printf '%s\n' \
    "RELEASE_ID=$id" \
    'PLATFORM_ID=debian-13-x86_64' \
    "SOURCE_COMMIT=$commit" \
    'SOURCE_TREE=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb' \
    'BUILDER_IMAGE=fixture@sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc' \
    "NVIM_VERSION=v$release_version" \
    "NODE_VERSION=$release_version" \
    "NPM_VERSION=$release_version" \
    "NODE_UPSTREAM_NPM_VERSION=$release_version" \
    'PYTHON_VERSION=3.12.12' \
    'PYTHON_BUILD=20260127' \
    "TMUX_VERSION=$release_version" \
    "RG_VERSION=$release_version" \
    "FZF_VERSION=$release_version" \
    "ZOXIDE_VERSION=$release_version" \
    "K9S_VERSION=$release_version" \
    "KUBECTX_VERSION=$release_version" \
    "OMP_VERSION=$release_version" \
    "TASK_VERSION=$release_version" \
    "TERRAFORM_VERSION=$release_version" \
    "KUBECTL_VERSIONS=$release_version,0.9" \
    "HELM_VERSIONS=$release_version,0.9" \
    "OFFLINE_TOOLS=$offline_profile" \
    'PAYLOAD_PATHS=bin,config,dotfiles,python-locks,python-wheelhouse,share,tools' \
    >"$release/release.env"
  if [[ $include_fd == true ]]; then
    printf 'FD_VERSION=%s\n' "$release_version" >>"$release/release.env"
  fi
  printf 'marker=%s\n' "$marker" >"$release/build-manifest.txt"
  (
    cd "$release"
    find . -type f ! -name SHA256SUMS -print0 | sort -z |
      xargs -0 sha256sum >../SHA256SUMS
    mv ../SHA256SUMS SHA256SUMS
  )
  tar -C "$stage" -czf "$destination" "$id"
}

repack_artifact() {
  local marker=$1 id=$2 destination=$3 release
  release=$test_root/stage-$marker/$id

  (
    cd "$release"
    find . -type f ! -name SHA256SUMS -print0 | sort -z |
      xargs -0 sha256sum >"$test_root/$marker-SHA256SUMS"
    mv "$test_root/$marker-SHA256SUMS" SHA256SUMS
  )
  tar -C "$test_root/stage-$marker" -czf "$destination" "$id"
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
make_artifact "$commit_one" one "$artifact_one" 1.0 false
make_artifact "$commit_two" two "$artifact_two" 2.0
make_artifact "$commit_three" three "$artifact_three"

test_home=$test_root/fd-validation-home
fd_broken=$test_root/fd-broken.tar.gz
make_artifact "$commit_three" fd-missing-pin "$fd_broken"
sed -i '/^FD_VERSION=/d' "$test_root/stage-fd-missing-pin/$id_three/release.env"
repack_artifact fd-missing-pin "$id_three" "$fd_broken"
if run_manager verify debian-13-x86_64 "$fd_broken" >"$test_root/fd-missing-pin.log" 2>&1; then
  fail 'fd profile was accepted without its version pin'
fi
make_artifact "$commit_three" fd-missing-executable "$fd_broken"
rm "$test_root/stage-fd-missing-executable/$id_three/tools/bin/fd"
repack_artifact fd-missing-executable "$id_three" "$fd_broken"
if run_manager install "$fd_broken" >"$test_root/fd-missing-executable.log" 2>&1; then
  fail 'fd release was installed without its executable'
fi
make_artifact "$commit_three" fd-wrong-version "$fd_broken"
sed -i 's/^FD_VERSION=.*/FD_VERSION=9.9/' "$test_root/stage-fd-wrong-version/$id_three/release.env"
repack_artifact fd-wrong-version "$id_three" "$fd_broken"
if run_manager install "$fd_broken" >"$test_root/fd-wrong-version.log" 2>&1; then
  fail 'fd release was installed with an unexpected executable version'
fi
[[ ! -e $test_home/dotfiles-releases/current ]] || fail 'failed fd release became active'

test_home=$test_root/fd-connected-migration-home
mkdir -p "$test_home/bin" "$test_home/.local/state/dotfiles/setup-tools"
write_fake_tool "$test_home/bin/fd-0.9" 0.9
ln -s fd-0.9 "$test_home/bin/fd"
fd_content=$(tar --sort=name --mtime=@0 --owner=0 --group=0 --numeric-owner \
  -C "$test_home/bin" -cf - -- fd-0.9 | sha256sum | awk '{print $1}')
printf 'complete\t%s\t%s\n' \
  aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa \
  "$fd_content" >"$test_home/.local/state/dotfiles/setup-tools/fd-0.9.state"
run_manager install "$artifact_two" >/dev/null
[[ $("$test_home/bin/fd" --version) == *'fixture 2.0'* ]] ||
  fail 'offline release did not adopt the owned connected fd launcher'
run_manager uninstall >/dev/null
assert_link "$test_home/bin/fd" fd-0.9
[[ $("$test_home/bin/fd" --version) == *'fixture 0.9'* ]] ||
  fail 'uninstall did not restore the connected fd payload'
printf '\nmodified\n' >>"$test_home/bin/fd-0.9"
if run_manager install "$artifact_two" >"$test_root/fd-modified-provider.log" 2>&1; then
  fail 'offline release adopted a modified connected fd payload'
fi
assert_link "$test_home/bin/fd" fd-0.9

reserved_root=$test_root/reserved-paths
mkdir -p "$reserved_root"

test_home=$reserved_root/lock-home
private_lock_target=$reserved_root/private-lock-target
mkdir -p "$test_home/dotfiles-releases/.state"
printf 'private lock target\n' >"$private_lock_target"
chmod 0640 "$private_lock_target"
private_lock_digest=$(sha256sum "$private_lock_target")
private_lock_mode=$(stat -c %a "$private_lock_target")
ln -s "$private_lock_target" "$test_home/dotfiles-releases/.state/lock"
set +e
reserved_output=$(run_manager list 2>&1)
reserved_status=$?
set -e
[[ $reserved_status -ne 0 && $reserved_output == *'invalid reserved state path'* ]] ||
  fail 'foreign lock symlink was accepted'
[[ $(sha256sum "$private_lock_target") == "$private_lock_digest" &&
  $(stat -c %a "$private_lock_target") == "$private_lock_mode" ]] ||
  fail 'foreign lock symlink target was modified'
assert_link "$test_home/dotfiles-releases/.state/lock" "$private_lock_target"

test_home=$reserved_root/broken-lock-home
mkdir -p "$test_home/dotfiles-releases/.state"
ln -s "$reserved_root/missing-lock-target" "$test_home/dotfiles-releases/.state/lock"
set +e
run_manager list >/dev/null 2>&1
reserved_status=$?
set -e
[[ $reserved_status -ne 0 ]] || fail 'broken lock symlink was accepted'
assert_link "$test_home/dotfiles-releases/.state/lock" "$reserved_root/missing-lock-target"

for selection in current previous; do
  test_home=$reserved_root/regular-$selection-home
  mkdir -p "$test_home/dotfiles-releases"
  printf 'private selection\n' >"$test_home/dotfiles-releases/$selection"
  selection_digest=$(sha256sum "$test_home/dotfiles-releases/$selection")
  set +e
  run_manager list >/dev/null 2>&1
  reserved_status=$?
  set -e
  [[ $reserved_status -ne 0 ]] || fail "regular $selection was accepted"
  [[ $(sha256sum "$test_home/dotfiles-releases/$selection") == "$selection_digest" ]] ||
    fail "regular $selection was modified"
  [[ ! -e $test_home/dotfiles-releases/.state ]] ||
    fail "regular $selection was rejected only after a state write"
done

test_home=$reserved_root/broken-selection-home
mkdir -p "$test_home/dotfiles-releases"
ln -s dotfiles-aaaaaaaaaaaa "$test_home/dotfiles-releases/current"
set +e
run_manager list >/dev/null 2>&1
reserved_status=$?
set -e
[[ $reserved_status -ne 0 ]] || fail 'broken current selection was accepted'
assert_link "$test_home/dotfiles-releases/current" dotfiles-aaaaaaaaaaaa
[[ ! -e $test_home/dotfiles-releases/.state ]] ||
  fail 'broken current selection was rejected only after a state write'

test_home=$reserved_root/release-root-home
outside_release_root=$reserved_root/outside-release-root
mkdir -p "$test_home" "$outside_release_root"
printf 'outside marker\n' >"$outside_release_root/marker"
outside_release_digest=$(sha256sum "$outside_release_root/marker")
ln -s "$outside_release_root" "$test_home/dotfiles-releases"
set +e
run_manager list >/dev/null 2>&1
reserved_status=$?
set -e
[[ $reserved_status -ne 0 ]] || fail 'symlink release root was accepted'
[[ $(sha256sum "$outside_release_root/marker") == "$outside_release_digest" ]] ||
  fail 'symlink release root target was modified'

test_home=$reserved_root/state-home
outside_state=$reserved_root/outside-state
mkdir -p "$test_home/dotfiles-releases" "$outside_state"
printf 'outside state marker\n' >"$outside_state/marker"
outside_state_digest=$(sha256sum "$outside_state/marker")
ln -s "$outside_state" "$test_home/dotfiles-releases/.state"
set +e
run_manager list >/dev/null 2>&1
reserved_status=$?
set -e
[[ $reserved_status -ne 0 ]] || fail 'symlink state directory was accepted'
[[ $(sha256sum "$outside_state/marker") == "$outside_state_digest" ]] ||
  fail 'symlink state target was modified'

test_home=$reserved_root/ownership-home
mkdir -p "$test_home/dotfiles-releases/.state/ownership.tsv"
set +e
run_manager list >/dev/null 2>&1
reserved_status=$?
set -e
[[ $reserved_status -ne 0 && -d $test_home/dotfiles-releases/.state/ownership.tsv ]] ||
  fail 'directory ownership record was accepted or replaced'

test_home=$reserved_root/parent-link-home
outside_bin=$reserved_root/outside-bin
mkdir -p "$test_home" "$outside_bin"
printf 'outside bin marker\n' >"$outside_bin/marker"
outside_bin_digest=$(sha256sum "$outside_bin/marker")
ln -s "$outside_bin" "$test_home/bin"
set +e
parent_output=$(run_manager install "$artifact_one" 2>&1)
parent_status=$?
set -e
[[ $parent_status -ne 0 && $parent_output == *'symlink parent'* ]] ||
  fail 'managed path with a symlink parent was accepted'
[[ $(sha256sum "$outside_bin/marker") == "$outside_bin_digest" ]] ||
  fail 'managed symlink parent target was modified'
[[ ! -e $test_home/dotfiles-releases/current &&
  ! -e $test_home/dotfiles-releases/.state/pending.env &&
  ! -e $test_home/dotfiles-releases/$id_one ]] ||
  fail 'parent-link conflict retained partial release state'

failure_bin=$test_root/failure-bin
mkdir -p "$failure_bin"

test_home=$test_root/ownership-write-failure-home
mkdir -p "$test_home"
printf 'ownership baseline\n' >"$test_home/.bashrc"
cat >"$failure_bin/mv" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
destination=${!#}
if [[ $destination == */.state/ownership.tsv ]]; then exit 91; fi
exec /usr/bin/mv "$@"
EOF
chmod 0755 "$failure_bin/mv"
set +e
ownership_failure_output=$(PATH="$failure_bin:/usr/bin:/bin" run_manager install "$artifact_one" 2>&1)
ownership_failure_status=$?
set -e
[[ $ownership_failure_status -ne 0 && $ownership_failure_output != *': installed '* ]] ||
  fail 'ownership write failure reported installation success'
[[ $(<"$test_home/.bashrc") == 'ownership baseline' &&
  ! -e $test_home/dotfiles-releases/current &&
  ! -e $test_home/dotfiles-releases/.state/pending.env &&
  ! -e $test_home/dotfiles-releases/$id_one ]] ||
  fail 'ownership write failure did not restore the first-install baseline'
rm "$failure_bin/mv"
run_manager install "$artifact_one" >/dev/null
run_manager uninstall >/dev/null

test_home=$test_root/pending-write-failure-home
mkdir -p "$test_home"
printf 'pending baseline\n' >"$test_home/.bashrc"
cat >"$failure_bin/mv" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
destination=${!#}
if [[ $destination == */.state/pending.env ]]; then exit 97; fi
exec /usr/bin/mv "$@"
EOF
chmod 0755 "$failure_bin/mv"
set +e
pending_failure_output=$(PATH="$failure_bin:/usr/bin:/bin" run_manager install "$artifact_one" 2>&1)
pending_failure_status=$?
set -e
[[ $pending_failure_status -ne 0 && $pending_failure_output != *': installed '* ]] ||
  fail 'pending write failure reported installation success'
[[ $(<"$test_home/.bashrc") == 'pending baseline' &&
  ! -e $test_home/dotfiles-releases/current &&
  ! -e $test_home/dotfiles-releases/.state/pending.env &&
  ! -e $test_home/dotfiles-releases/$id_one ]] ||
  fail 'pending write failure changed the first-install baseline'
rm "$failure_bin/mv"
run_manager install "$artifact_one" >/dev/null
run_manager uninstall >/dev/null

test_home=$test_root/link-failure-home
mkdir -p "$test_home"
printf 'link baseline\n' >"$test_home/.bashrc"
cat >"$failure_bin/ln" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
destination=${!#}
if [[ $destination == */.dotfiles-release-link.* ]]; then exit 92; fi
exec /usr/bin/ln "$@"
EOF
chmod 0755 "$failure_bin/ln"
set +e
link_failure_output=$(PATH="$failure_bin:/usr/bin:/bin" run_manager install "$artifact_one" 2>&1)
link_failure_status=$?
set -e
[[ $link_failure_status -ne 0 && $link_failure_output != *': installed '* ]] ||
  fail 'managed-link failure reported installation success'
[[ $(<"$test_home/.bashrc") == 'link baseline' &&
  ! -e $test_home/dotfiles-releases/current &&
  ! -e $test_home/dotfiles-releases/.state/pending.env &&
  ! -e $test_home/dotfiles-releases/$id_one ]] ||
  fail 'managed-link failure did not restore the first-install baseline'
rm "$failure_bin/ln"
run_manager install "$artifact_one" >/dev/null
run_manager uninstall >/dev/null

test_home=$test_root/selection-failure-home
mkdir -p "$test_home"
printf 'selection baseline\n' >"$test_home/.bashrc"
run_manager install "$artifact_one" >/dev/null
cat >"$failure_bin/mv" <<EOF
#!/usr/bin/env bash
set -euo pipefail
destination=\${!#}
if [[ \$destination == '$test_home/dotfiles-releases/current' ]]; then exit 93; fi
exec /usr/bin/mv "\$@"
EOF
chmod 0755 "$failure_bin/mv"
set +e
selection_failure_output=$(PATH="$failure_bin:/usr/bin:/bin" run_manager install "$artifact_two" 2>&1)
selection_failure_status=$?
set -e
[[ $selection_failure_status -ne 0 && $selection_failure_output != *': installed '* ]] ||
  fail 'current selection failure reported installation success'
assert_link "$test_home/dotfiles-releases/current" "$id_one"
[[ ! -e $test_home/dotfiles-releases/previous &&
  ! -e $test_home/dotfiles-releases/.state/pending.env &&
  ! -e $test_home/dotfiles-releases/$id_two ]] ||
  fail 'current selection failure did not restore the A selection pair'
rm "$failure_bin/mv"
run_manager install "$artifact_two" >/dev/null
assert_link "$test_home/dotfiles-releases/current" "$id_two"
run_manager uninstall >/dev/null

test_home=$test_root/previous-selection-failure-home
mkdir -p "$test_home"
printf 'previous selection baseline\n' >"$test_home/.bashrc"
run_manager install "$artifact_one" >/dev/null
cat >"$failure_bin/mv" <<EOF
#!/usr/bin/env bash
set -euo pipefail
destination=\${!#}
if [[ \$destination == '$test_home/dotfiles-releases/previous' ]]; then exit 98; fi
exec /usr/bin/mv "\$@"
EOF
chmod 0755 "$failure_bin/mv"
set +e
previous_failure_output=$(PATH="$failure_bin:/usr/bin:/bin" run_manager install "$artifact_two" 2>&1)
previous_failure_status=$?
set -e
[[ $previous_failure_status -ne 0 && $previous_failure_output != *': installed '* ]] ||
  fail 'previous selection failure reported installation success'
assert_link "$test_home/dotfiles-releases/current" "$id_one"
[[ ! -e $test_home/dotfiles-releases/previous &&
  ! -e $test_home/dotfiles-releases/.state/pending.env &&
  ! -e $test_home/dotfiles-releases/$id_two ]] ||
  fail 'previous selection failure did not restore the A selection pair'
rm "$failure_bin/mv"
run_manager install "$artifact_two" >/dev/null
run_manager uninstall >/dev/null

test_home=$test_root/recovery-failure-home
mkdir -p "$test_home"
printf 'recovery baseline\n' >"$test_home/.bashrc"
run_manager install "$artifact_one" >/dev/null
cat >"$failure_bin/mv" <<EOF
#!/usr/bin/env bash
set -euo pipefail
destination=\${!#}
if [[ \$destination == '$test_home/dotfiles-releases/current' ]]; then exit 95; fi
exec /usr/bin/mv "\$@"
EOF
cat >"$failure_bin/unlink" <<EOF
#!/usr/bin/env bash
set -euo pipefail
if [[ \${!#} == '$test_home/dotfiles-releases/previous' ]]; then exit 96; fi
exec /usr/bin/unlink "\$@"
EOF
chmod 0755 "$failure_bin/mv" "$failure_bin/unlink"
set +e
recovery_failure_output=$(PATH="$failure_bin:/usr/bin:/bin" run_manager install "$artifact_two" 2>&1)
recovery_failure_status=$?
set -e
[[ $recovery_failure_status -ne 0 &&
  $recovery_failure_output == *'automatic recovery also failed'* &&
  $recovery_failure_output != *': installed '* ]] ||
  fail 'activation plus recovery failure was not reported'
assert_link "$test_home/dotfiles-releases/current" "$id_one"
[[ -f $test_home/dotfiles-releases/.state/pending.env &&
  -d $test_home/dotfiles-releases/$id_two ]] ||
  fail 'failed automatic recovery discarded its journal or retained payload'
rm "$failure_bin/mv" "$failure_bin/unlink"
run_manager install "$artifact_two" >/dev/null
assert_link "$test_home/dotfiles-releases/current" "$id_two"
[[ ! -e $test_home/dotfiles-releases/.state/pending.env ]] ||
  fail 'retry did not clear the recovered activation journal'
run_manager uninstall >/dev/null

test_home=$test_root/kill-after-backup-home
mkdir -p "$test_home"
printf 'kill backup baseline\n' >"$test_home/.bashrc"
chmod 0640 "$test_home/.bashrc"
kill_backup_digest=$(sha256sum "$test_home/.bashrc")
kill_backup_mode=$(stat -c %a "$test_home/.bashrc")
cat >"$failure_bin/mv" <<EOF
#!/usr/bin/env bash
set -euo pipefail
source_path=\${@: -2:1}
destination=\${!#}
/usr/bin/mv "\$@"
if [[ \$source_path == '$test_home/.bashrc' &&
  \$destination == '$test_home/.dotfiles-release-backup-'* ]]; then
  kill -KILL "\$PPID"
fi
EOF
chmod 0755 "$failure_bin/mv"
set +e
PATH="$failure_bin:/usr/bin:/bin" run_manager install "$artifact_one" >/dev/null 2>&1
kill_backup_status=$?
set -e
[[ $kill_backup_status -ne 0 &&
  -f $test_home/dotfiles-releases/.state/pending.env ]] ||
  fail 'SIGKILL after backup move did not leave a recovery journal'
rm "$failure_bin/mv"
run_manager install "$artifact_one" >/dev/null
run_manager uninstall >/dev/null
[[ $(sha256sum "$test_home/.bashrc") == "$kill_backup_digest" &&
  $(stat -c %a "$test_home/.bashrc") == "$kill_backup_mode" ]] ||
  fail 'retry after backup SIGKILL did not restore baseline bytes and mode'
[[ -z $(find "$test_home" -name '.dotfiles-release-backup-*' -print -quit) ]] ||
  fail 'retry after backup SIGKILL left an orphaned backup'

test_home=$test_root/kill-after-link-home
mkdir -p "$test_home"
printf 'kill link baseline\n' >"$test_home/.bashrc"
kill_link_digest=$(sha256sum "$test_home/.bashrc")
cat >"$failure_bin/mv" <<EOF
#!/usr/bin/env bash
set -euo pipefail
source_path=\${@: -2:1}
destination=\${!#}
/usr/bin/mv "\$@"
if [[ \$source_path == '$test_home/.dotfiles-release-link.'* &&
  \$destination == '$test_home/.bashrc' ]]; then
  kill -KILL "\$PPID"
fi
EOF
chmod 0755 "$failure_bin/mv"
set +e
PATH="$failure_bin:/usr/bin:/bin" run_manager install "$artifact_one" >/dev/null 2>&1
kill_link_status=$?
set -e
[[ $kill_link_status -ne 0 && -L $test_home/.bashrc &&
  -f $test_home/dotfiles-releases/.state/pending.env ]] ||
  fail 'SIGKILL after managed-link rename did not preserve a recoverable state'
rm "$failure_bin/mv"
run_manager install "$artifact_one" >/dev/null
run_manager uninstall >/dev/null
[[ $(sha256sum "$test_home/.bashrc") == "$kill_link_digest" ]] ||
  fail 'retry after managed-link SIGKILL did not restore baseline bytes'

test_home=$test_root/kill-after-created-link-home
mkdir -p "$test_home"
cat >"$failure_bin/mv" <<EOF
#!/usr/bin/env bash
set -euo pipefail
source_path=\${@: -2:1}
destination=\${!#}
/usr/bin/mv "\$@"
if [[ \$source_path == '$test_home/bin/.dotfiles-release-link.'* &&
  \$destination == '$test_home/bin/dotfiles-release' ]]; then
  kill -KILL "\$PPID"
fi
EOF
chmod 0755 "$failure_bin/mv"
set +e
PATH="$failure_bin:/usr/bin:/bin" run_manager install "$artifact_one" >/dev/null 2>&1
kill_created_status=$?
set -e
[[ $kill_created_status -ne 0 && -L $test_home/bin/dotfiles-release &&
  -f $test_home/dotfiles-releases/.state/pending.env ]] ||
  fail 'SIGKILL after created-link rename did not preserve a recoverable state'
rm "$failure_bin/mv"
run_manager install "$artifact_one" >/dev/null
run_manager uninstall >/dev/null
[[ ! -e $test_home/bin/dotfiles-release &&
  ! -e $test_home/dotfiles-releases/.state/pending.env ]] ||
  fail 'retry after created-link SIGKILL did not restore absence'

test_home=$test_root/kill-provider-home
mkdir -p "$test_home/bin" "$test_home/.local/state/dotfiles/setup-tools"
printf 'provider baseline\n' >"$test_home/.bashrc"
write_fake_tool "$test_home/bin/rg-0.9"
ln -s rg-0.9 "$test_home/bin/rg"
provider_content=$(tar --sort=name --mtime=@0 --owner=0 --group=0 --numeric-owner \
  -C "$test_home/bin" -cf - -- rg-0.9 | sha256sum | awk '{print $1}')
printf 'complete\t%s\t%s\n' \
  aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa \
  "$provider_content" >"$test_home/.local/state/dotfiles/setup-tools/rg-0.9.state"
cat >"$failure_bin/mv" <<EOF
#!/usr/bin/env bash
set -euo pipefail
source_path=\${@: -2:1}
destination=\${!#}
/usr/bin/mv "\$@"
if [[ \$source_path == '$test_home/bin/rg' &&
  \$destination == '$test_home/bin/.dotfiles-release-backup-'* ]]; then
  kill -KILL "\$PPID"
fi
EOF
chmod 0755 "$failure_bin/mv"
set +e
PATH="$failure_bin:/usr/bin:/bin" run_manager install "$artifact_one" >/dev/null 2>&1
kill_provider_status=$?
set -e
[[ $kill_provider_status -ne 0 &&
  -f $test_home/dotfiles-releases/.state/pending.env ]] ||
  fail 'SIGKILL while migrating an owned provider link left no journal'
rm "$failure_bin/mv"
run_manager install "$artifact_one" >/dev/null
run_manager uninstall >/dev/null
assert_link "$test_home/bin/rg" rg-0.9
[[ -x $test_home/bin/rg-0.9 ]] ||
  fail 'retry after provider-link SIGKILL did not restore its payload'

test_home=$test_root/kill-selection-home
mkdir -p "$test_home"
printf 'kill selection baseline\n' >"$test_home/.bashrc"
run_manager install "$artifact_one" >/dev/null
cat >"$failure_bin/mv" <<EOF
#!/usr/bin/env bash
set -euo pipefail
destination=\${!#}
/usr/bin/mv "\$@"
if [[ \$destination == '$test_home/dotfiles-releases/current' ]]; then
  kill -KILL "\$PPID"
fi
EOF
chmod 0755 "$failure_bin/mv"
set +e
PATH="$failure_bin:/usr/bin:/bin" run_manager install "$artifact_two" >/dev/null 2>&1
kill_selection_status=$?
set -e
[[ $kill_selection_status -ne 0 &&
  -f $test_home/dotfiles-releases/.state/pending.env ]] ||
  fail 'SIGKILL after current rename did not preserve a recovery journal'
assert_link "$test_home/dotfiles-releases/current" "$id_two"
assert_link "$test_home/dotfiles-releases/previous" "$id_one"
rm "$failure_bin/mv"
run_manager install "$artifact_two" >/dev/null
assert_link "$test_home/dotfiles-releases/current" "$id_two"
assert_link "$test_home/dotfiles-releases/previous" "$id_one"
[[ ! -e $test_home/dotfiles-releases/.state/pending.env ]] ||
  fail 'retry after selection SIGKILL retained its journal'
run_manager uninstall >/dev/null

test_home=$test_root/kill-restore-home
mkdir -p "$test_home"
printf 'kill restore baseline\n' >"$test_home/.bashrc"
chmod 0640 "$test_home/.bashrc"
kill_restore_digest=$(sha256sum "$test_home/.bashrc")
kill_restore_mode=$(stat -c %a "$test_home/.bashrc")
run_manager install "$artifact_one" >/dev/null
restore_phase=$test_root/restore-recovery-phase
cat >"$failure_bin/mv" <<EOF
#!/usr/bin/env bash
set -euo pipefail
source_path=\${@: -2:1}
destination=\${!#}
/usr/bin/mv "\$@"
if [[ \$source_path == '$test_home/.dotfiles-release-backup-'* &&
  \$destination == '$test_home/.bashrc' ]]; then
  printf 'restored\n' >'$restore_phase'
  kill -KILL "\$PPID"
fi
if [[ \$destination == '$test_home/dotfiles-releases/.state/ownership.tsv' &&
  -f '$restore_phase' && \$(<'$restore_phase') == restored ]]; then
  printf 'recorded\n' >'$restore_phase'
  kill -KILL "\$PPID"
fi
EOF
chmod 0755 "$failure_bin/mv"
set +e
PATH="$failure_bin:/usr/bin:/bin" run_manager uninstall >/dev/null 2>&1
kill_restore_status=$?
set -e
[[ $kill_restore_status -ne 0 &&
  -f $test_home/dotfiles-releases/.state/pending.env ]] ||
  fail 'SIGKILL after backup restore did not preserve its journal'
set +e
PATH="$failure_bin:/usr/bin:/bin" run_manager uninstall >/dev/null 2>&1
kill_recovery_status=$?
set -e
[[ $kill_recovery_status -ne 0 &&
  $(<"$restore_phase") == recorded &&
  -f $test_home/dotfiles-releases/.state/pending.env ]] ||
  fail 'SIGKILL during repeated recovery did not preserve its journal'
rm "$failure_bin/mv"
restore_retry_output=$(run_manager uninstall)
[[ $restore_retry_output == *'recovery already restored the pre-release baseline'* ]] ||
  fail 'retry uninstall did not report recovered baseline success'
[[ $(sha256sum "$test_home/.bashrc") == "$kill_restore_digest" &&
  $(stat -c %a "$test_home/.bashrc") == "$kill_restore_mode" ]] ||
  fail 'retry after restore SIGKILL did not preserve baseline bytes and mode'
[[ ! -e $test_home/dotfiles-releases/.state/pending.env ]] ||
  fail 'retry after restore SIGKILL retained its journal'

test_home=$test_root/kill-created-restore-home
mkdir -p "$test_home"
printf 'created restore baseline\n' >"$test_home/.bashrc"
run_manager install "$artifact_one" >/dev/null
cat >"$failure_bin/unlink" <<EOF
#!/usr/bin/env bash
set -euo pipefail
path=\${!#}
/usr/bin/unlink "\$@"
if [[ \$path == '$test_home/.bash_profile' ]]; then
  kill -KILL "\$PPID"
fi
EOF
chmod 0755 "$failure_bin/unlink"
set +e
PATH="$failure_bin:/usr/bin:/bin" run_manager uninstall >/dev/null 2>&1
kill_created_restore_status=$?
set -e
[[ $kill_created_restore_status -ne 0 && ! -e $test_home/.bash_profile &&
  -f $test_home/dotfiles-releases/.state/pending.env ]] ||
  fail 'SIGKILL after removing a created path left no recoverable state'
rm "$failure_bin/unlink"
run_manager uninstall >/dev/null
[[ ! -e $test_home/.bash_profile &&
  ! -e $test_home/dotfiles-releases/.state/pending.env ]] ||
  fail 'retry after created-path restore SIGKILL did not converge'

test_home=$test_root/foreign-restore-home
mkdir -p "$test_home"
printf 'foreign restore baseline\n' >"$test_home/.bashrc"
run_manager install "$artifact_one" >/dev/null
unlink "$test_home/.bashrc"
printf 'foreign user edit\n' >"$test_home/.bashrc"
foreign_restore_digest=$(sha256sum "$test_home/.bashrc")
set +e
foreign_restore_output=$(run_manager uninstall 2>&1)
foreign_restore_status=$?
set -e
[[ $foreign_restore_status -ne 0 &&
  $foreign_restore_output == *'refusing to replace modified managed path'* ]] ||
  fail 'foreign edit during restore was not rejected'
[[ $(sha256sum "$test_home/.bashrc") == "$foreign_restore_digest" &&
  -f $test_home/dotfiles-releases/.state/pending.env &&
  -n $(find "$test_home" -maxdepth 1 -name '.dotfiles-release-backup-*' -print -quit) ]] ||
  fail 'restore conflict changed foreign data or discarded recovery state'
unlink "$test_home/.bashrc"
ln -s "$test_home/dotfiles-releases/current/dotfiles/bash/.bashrc" "$test_home/.bashrc"
run_manager uninstall >/dev/null
[[ $(<"$test_home/.bashrc") == 'foreign restore baseline' ]] ||
  fail 'retry after repairing restore conflict did not restore baseline'

health_commit=4444444444444444444444444444444444444444
health_id=dotfiles-${health_commit:0:12}
health_artifact=$test_root/health-failure.tar.gz
make_artifact "$health_commit" health-failure "$health_artifact"
printf '#!/usr/bin/env bash\nexit 94\n' >"$test_root/stage-health-failure/$health_id/tools/bin/node"
chmod 0755 "$test_root/stage-health-failure/$health_id/tools/bin/node"
(
  cd "$test_root/stage-health-failure/$health_id"
  find . -type f ! -name SHA256SUMS -print0 | sort -z |
    xargs -0 sha256sum >"$test_root/health-SHA256SUMS"
  mv "$test_root/health-SHA256SUMS" SHA256SUMS
)
tar -C "$test_root/stage-health-failure" -czf "$health_artifact" "$health_id"
test_home=$test_root/health-failure-home
mkdir -p "$test_home"
set +e
health_failure_output=$(run_manager install "$health_artifact" 2>&1)
health_failure_status=$?
set -e
[[ $health_failure_status -ne 0 && $health_failure_output != *': installed '* ]] ||
  fail 'required final health failure reported installation success'
[[ ! -e $test_home/dotfiles-releases/current &&
  ! -e $test_home/dotfiles-releases/.state/pending.env &&
  ! -e $test_home/dotfiles-releases/$health_id ]] ||
  fail 'required final health failure retained partial installation state'

inventory_commit=5555555555555555555555555555555555555555
inventory_id=dotfiles-${inventory_commit:0:12}
inventory_artifact=$test_root/inventory-mismatch.tar.gz
make_artifact "$inventory_commit" inventory "$inventory_artifact"
printf 'ansible-lint\t99.0.0\nyamllint\t1.38.0\n' \
  >"$test_root/stage-inventory/$inventory_id/python-locks/inventory.tsv"
(
  cd "$test_root/stage-inventory/$inventory_id"
  find . -type f ! -name SHA256SUMS -print0 | sort -z |
    xargs -0 sha256sum >"$test_root/inventory-SHA256SUMS"
  mv "$test_root/inventory-SHA256SUMS" SHA256SUMS
)
tar -C "$test_root/stage-inventory" -czf "$inventory_artifact" "$inventory_id"
test_home=$test_root/inventory-mismatch-home
mkdir -p "$test_home"
set +e
inventory_output=$(run_manager install "$inventory_artifact" 2>&1)
inventory_status=$?
set -e
[[ $inventory_status -ne 0 && $inventory_output == *'does not match Mason inventory'* ]] ||
  fail 'Python inventory/lock mismatch was accepted'
[[ ! -e $test_home/dotfiles-releases/current &&
  ! -e $test_home/dotfiles-releases/.state/pending.env &&
  ! -e $test_home/dotfiles-releases/$inventory_id ]] ||
  fail 'Python inventory mismatch retained partial installation state'

printf 'ansible-lint\t26.1.1\nansible-lint\t26.1.1\n' \
  >"$test_root/stage-inventory/$inventory_id/python-locks/inventory.tsv"
repack_artifact inventory "$inventory_id" "$inventory_artifact"
if run_manager install "$inventory_artifact" >"$test_root/duplicate-inventory.log" 2>&1; then
  fail 'duplicate Python inventory packages were accepted'
fi
[[ ! -e $test_home/dotfiles-releases/current &&
  ! -e $test_home/dotfiles-releases/.state/pending.env &&
  ! -e $test_home/dotfiles-releases/$inventory_id ]] ||
  fail 'duplicate Python inventory retained partial installation state'

foreign_plugin_home=$test_root/foreign-plugin-home
foreign_plugin=$foreign_plugin_home/.tmux/plugins/tmux-sensible
mkdir -p "$(dirname -- "$foreign_plugin")"
cp -a "$test_root/stage-one/$id_one/share/tmux/plugins/tmux-sensible" "$foreign_plugin"
git -C "$foreign_plugin" remote set-url origin https://example.invalid/foreign.git
test_home=$foreign_plugin_home
if run_manager install "$artifact_one" >"$test_root/foreign-plugin.log" 2>&1; then
  fail 'foreign tmux plugin checkout was adopted'
fi
[[ ! -L $foreign_plugin &&
  $(git -C "$foreign_plugin" remote get-url origin) == https://example.invalid/foreign.git &&
  ! -e $test_home/dotfiles-releases/current ]] ||
  fail 'foreign tmux plugin checkout changed after rejected install'

test_home="$test_root/nonstandard home"
mkdir -p "$test_home/.config/k9s" "$test_home/bin"
printf 'original bashrc\n' >"$test_home/.bashrc"
printf 'private contexts\n' >"$test_home/kube-backup-contexts.txt"
printf 'private prefixes\n' >"$test_home/kube-log-prefixes.txt"

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
[[ $(sed -n 's/^NODE_VERSION=//p' "$test_home/dotfiles-releases/$id_one/release.env") == 1.0 &&
  $(sed -n 's/^NODE_VERSION=//p' "$test_home/dotfiles-releases/$id_two/release.env") == 2.0 ]] ||
  fail 'A/B fixtures do not carry distinct release versions'
standalone_manager=$test_root/standalone-dotfiles-release
cp "$test_home/dotfiles-releases/$id_two/dotfiles-release" "$standalone_manager"
HOME=$test_home DOTFILES_OS_RELEASE_FILE=$os_release DOTFILES_RELEASE_TEST_MODE=1 \
  bash "$standalone_manager" health "$id_one"
HOME=$test_home "$test_home/dotfiles-releases/$id_one/bin/nvim" hold "$process_record" &
old_process=$!
while [[ ! -s $process_record ]]; do sleep 0.05; done
run_manager rollback
wait "$old_process"
grep -F "$id_one/tools/nvim/bin/nvim" "$process_record" >/dev/null ||
  fail 'running process did not stay on its physical release'
assert_link "$test_home/dotfiles-releases/current" "$id_one"
assert_link "$test_home/dotfiles-releases/previous" "$id_two"
[[ ! -e $test_home/bin/fd ]] || fail 'legacy rollback retained an executable from the newer release'
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

collision=$test_root/collision.tar.gz
make_artifact "$commit_one" collision "$collision"
set +e
collision_output=$(run_manager install "$collision" 2>&1)
collision_status=$?
set -e
[[ $collision_status -ne 0 && $collision_output == *'release ID collision'* ]] ||
  fail 'same-ID different-content collision was accepted'

metadata_commit=6666666666666666666666666666666666666666
metadata_id=dotfiles-${metadata_commit:0:12}
metadata_artifact=$test_root/metadata-unknown.tar.gz
make_artifact "$metadata_commit" metadata-unknown "$metadata_artifact"
printf 'FORMAT_VERSION=1\n' >>"$test_root/stage-metadata-unknown/$metadata_id/release.env"
repack_artifact metadata-unknown "$metadata_id" "$metadata_artifact"
set +e
metadata_output=$(run_manager install "$metadata_artifact" 2>&1)
metadata_status=$?
set -e
[[ $metadata_status -ne 0 &&
  $metadata_output == *'unknown release metadata key: FORMAT_VERSION'* ]] ||
  fail 'obsolete release metadata marker was accepted'
assert_link "$test_home/dotfiles-releases/current" "$id_one"
[[ ! -e $test_home/dotfiles-releases/$metadata_id ]] ||
  fail 'invalid metadata package was retained'

duplicate_commit=7777777777777777777777777777777777777777
duplicate_id=dotfiles-${duplicate_commit:0:12}
duplicate_artifact=$test_root/metadata-duplicate.tar.gz
make_artifact "$duplicate_commit" metadata-duplicate "$duplicate_artifact"
printf 'TASK_VERSION=1.0\n' >>"$test_root/stage-metadata-duplicate/$duplicate_id/release.env"
repack_artifact metadata-duplicate "$duplicate_id" "$duplicate_artifact"
set +e
duplicate_output=$(run_manager install "$duplicate_artifact" 2>&1)
duplicate_status=$?
set -e
[[ $duplicate_status -ne 0 &&
  $duplicate_output == *'duplicate release metadata key: TASK_VERSION'* ]] ||
  fail 'duplicate release metadata field was accepted'
assert_link "$test_home/dotfiles-releases/current" "$id_one"
[[ ! -e $test_home/dotfiles-releases/$duplicate_id ]] ||
  fail 'duplicate metadata package was retained'

missing_commit=8888888888888888888888888888888888888888
missing_id=dotfiles-${missing_commit:0:12}
missing_artifact=$test_root/metadata-missing.tar.gz
make_artifact "$missing_commit" metadata-missing "$missing_artifact"
sed -i '/^TASK_VERSION=/d' "$test_root/stage-metadata-missing/$missing_id/release.env"
repack_artifact metadata-missing "$missing_id" "$missing_artifact"
set +e
missing_metadata_output=$(run_manager install "$missing_artifact" 2>&1)
missing_metadata_status=$?
set -e
[[ $missing_metadata_status -ne 0 &&
  $missing_metadata_output == *'missing release metadata key: TASK_VERSION'* ]] ||
  fail 'missing release metadata field was accepted'
assert_link "$test_home/dotfiles-releases/current" "$id_one"
[[ ! -e $test_home/dotfiles-releases/$missing_id ]] ||
  fail 'missing metadata package was retained'

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

lock_ready=$test_root/lock-ready
(
  exec {lock_fd}<"$test_home/dotfiles-releases/.state/lock"
  flock -x "$lock_fd"
  : >"$lock_ready"
  sleep 60
) &
lock_holder_pid=$!
while [[ ! -e $lock_ready ]]; do sleep 0.01; done
set +e
lock_output=$(run_manager install "$artifact_one" 2>&1)
lock_status=$?
rollback_lock_output=$(run_manager rollback 2>&1)
rollback_lock_status=$?
list_lock_output=$(run_manager list 2>&1)
list_lock_status=$?
health_lock_output=$(run_manager health 2>&1)
health_lock_status=$?
set -e
[[ $lock_status -ne 0 && $lock_output == *'another release operation is running'* ]] ||
  fail 'concurrent install was accepted'
[[ $rollback_lock_status -ne 0 &&
  $rollback_lock_output == *'another release operation is running'* ]] ||
  fail 'second concurrent mutation was accepted'
[[ $list_lock_status -ne 0 &&
  $list_lock_output == *'another release operation is running'* ]] ||
  fail 'concurrent list was accepted'
[[ $health_lock_status -ne 0 &&
  $health_lock_output == *'another release operation is running'* ]] ||
  fail 'concurrent health was accepted'
kill -KILL "$lock_holder_pid"
wait "$lock_holder_pid" 2>/dev/null || true
lock_holder_pid=
run_manager install "$artifact_one" >/dev/null

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

printf 'Dotfiles release tests passed\n'
