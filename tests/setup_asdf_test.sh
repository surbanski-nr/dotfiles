#!/usr/bin/env bash

set -euo pipefail

repo_dir=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
test_root=$(mktemp -d)

cleanup() {
  find "$test_root" -depth -delete
}
trap cleanup EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

# shellcheck source=../versions.env
source "$repo_dir/versions.env"

write_asdf_fixture() {
  local path=$1 version=$2
  mkdir -p "$(dirname -- "$path")"
  cat >"$path" <<EOF
#!/usr/bin/env bash
set -euo pipefail
case \${1:-} in
  version) printf 'asdf version $version\n' ;;
  list)
    [[ -d \$ASDF_DATA_DIR/installs/\$2/\$3 ]] && printf '  %s\n' "\$3"
    ;;
  install)
    printf 'install\t%s\t%s\n' "\$2" "\$3" >>"\$TEST_ASDF_LOG"
    [[ \${TEST_ASDF_FAIL_VERSION:-} != "\$3" ]] || exit 65
    mkdir -p "\$ASDF_DATA_DIR/installs/\$2/\$3"
    ;;
  reshim) printf 'reshim\t%s\t%s\n' "\$2" "\$3" >>"\$TEST_ASDF_LOG" ;;
  set)
    printf 'set\t%s\t%s\n' "\$3" "\$4" >>"\$TEST_ASDF_LOG"
    ;;
  *) exit 66 ;;
esac
EOF
  chmod 0755 "$path"
}

record_asdf_fixture() {
  local home=$1 target=$2 state installs
  state=$home/.local/state/dotfiles/setup-asdf/asdf-target
  installs=$home/.local/state/dotfiles/setup-asdf/installations
  mkdir -p "$installs"
  printf '%s\n' "$target" >"$state"
  sha256sum "$home/bin/$target" | awk '{print $1}' >"$installs/$target.sha256"
  chmod 0600 "$state"
}

prepare_plugin() {
  local home=$1 repository=$2
  local plugin=$home/.asdf/plugins/terraform
  local plugin_commit
  mkdir -p "$plugin"
  git init -q "$plugin"
  git -C "$plugin" config user.name fixture
  git -C "$plugin" config user.email fixture@example.invalid
  printf 'fixture\n' >"$plugin/plugin"
  git -C "$plugin" add plugin
  git -C "$plugin" commit -qm fixture
  plugin_commit=$(git -C "$plugin" rev-parse HEAD)
  git -C "$plugin" remote add origin "$plugin"
  printf 'ASDF_TERRAFORM_PLUGIN_REPO=%s\nASDF_TERRAFORM_PLUGIN_COMMIT=%s\n' \
    "$plugin" "$plugin_commit" >>"$repository/versions.env"
}

test_repo="$test_root/repository"
test_home="$test_root/home"
mkdir -p "$test_repo/scripts" "$test_home/bin"
cp "$repo_dir/setup-asdf" "$test_repo/setup-asdf"
cp "$repo_dir/scripts/setup-lib" "$test_repo/scripts/setup-lib"
cp "$repo_dir/versions.env" "$test_repo/versions.env"

cat >"$test_home/bin/kubectl" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod 0755 "$test_home/bin/kubectl"
set +e
conflict_output=$(HOME="$test_home" "$test_repo/setup-asdf" kubectl 2>&1)
conflict_status=$?
set -e
[[ $conflict_status -ne 0 ]] || fail 'direct kubectl launcher conflict was accepted'
[[ $conflict_output == *'conflicts with the direct launcher'* ]] ||
  fail 'direct launcher conflict was not reported'
[[ ! -e $test_home/bin/asdf && ! -e $test_home/.asdf ]] ||
  fail 'provider conflict changed the asdf installation'

rm "$test_home/bin/kubectl"
mkdir -p "$test_home/.local/state/dotfiles/setup-asdf/lock"
set +e
lock_output=$(HOME="$test_home" "$test_repo/setup-asdf" kubectl 2>&1)
lock_status=$?
set -e
[[ $lock_status -ne 0 ]] || fail 'concurrent setup-asdf lock was ignored'
[[ $lock_output == *'another setup-asdf process is running'* ]] ||
  fail 'concurrent setup-asdf did not report the lock'
[[ ! -e $test_home/bin/asdf ]] || fail 'lock conflict installed asdf'

rmdir "$test_home/.local/state/dotfiles/setup-asdf/lock"
write_asdf_fixture "$test_home/bin/asdf-manual" manual
ln -s asdf-manual "$test_home/bin/asdf"
set +e
foreign_output=$(HOME="$test_home" "$test_repo/setup-asdf" terraform 2>&1)
foreign_status=$?
set -e
[[ $foreign_status -ne 0 && $foreign_output == *'has no ownership state'* ]] ||
  fail 'foreign asdf-manual link was accepted'
[[ $(readlink -- "$test_home/bin/asdf") == asdf-manual ]] ||
  fail 'foreign asdf link was changed'

reconcile_repo=$test_root/reconcile-repository
reconcile_home=$test_root/reconcile-home
reconcile_log=$test_root/reconcile.log
mkdir -p "$reconcile_repo/scripts" "$reconcile_home/bin"
cp "$repo_dir/setup-asdf" "$reconcile_repo/setup-asdf"
cp "$repo_dir/scripts/setup-lib" "$reconcile_repo/scripts/setup-lib"
cp "$repo_dir/versions.env" "$reconcile_repo/versions.env"
prepare_plugin "$reconcile_home" "$reconcile_repo"
write_asdf_fixture "$reconcile_home/bin/asdf-0.19.0" 0.19.0
write_asdf_fixture "$reconcile_home/bin/asdf-$ASDF_VERSION" "$ASDF_VERSION"
ln -s asdf-0.19.0 "$reconcile_home/bin/asdf"
record_asdf_fixture "$reconcile_home" asdf-0.19.0
sha256sum "$reconcile_home/bin/asdf-$ASDF_VERSION" | awk '{print $1}' \
  >"$reconcile_home/.local/state/dotfiles/setup-asdf/installations/asdf-$ASDF_VERSION.sha256"

HOME="$reconcile_home" TEST_ASDF_LOG="$reconcile_log" \
  "$reconcile_repo/setup-asdf" terraform
[[ $(readlink -- "$reconcile_home/bin/asdf") == "asdf-$ASDF_VERSION" ]] ||
  fail 'managed asdf was not upgraded to the selected version'
[[ -x $reconcile_home/bin/asdf-0.19.0 ]] || fail 'previous asdf binary was removed'
[[ $(<"$reconcile_home/.local/state/dotfiles/setup-asdf/asdf-target") == "asdf-$ASDF_VERSION" ]] ||
  fail 'selected asdf target was not recorded'
HOME="$reconcile_home" TEST_ASDF_LOG="$reconcile_log" \
  "$reconcile_repo/setup-asdf" terraform
[[ $(grep -c '^install' "$reconcile_log") -eq 2 ]] ||
  fail 'second setup-asdf run reinstalled a runtime'
[[ $(grep -c '^set' "$reconcile_log") -eq 2 ]] ||
  fail 'setup-asdf did not select the home default after each successful run'

failure_repo=$test_root/failure-repository
failure_home=$test_root/failure-home
failure_log=$test_root/failure.log
mkdir -p "$failure_repo/scripts" "$failure_home/bin"
cp "$repo_dir/setup-asdf" "$failure_repo/setup-asdf"
cp "$repo_dir/scripts/setup-lib" "$failure_repo/scripts/setup-lib"
cp "$repo_dir/versions.env" "$failure_repo/versions.env"
prepare_plugin "$failure_home" "$failure_repo"
write_asdf_fixture "$failure_home/bin/asdf-$ASDF_VERSION" "$ASDF_VERSION"
ln -s "asdf-$ASDF_VERSION" "$failure_home/bin/asdf"
record_asdf_fixture "$failure_home" "asdf-$ASDF_VERSION"
set +e
HOME="$failure_home" TEST_ASDF_LOG="$failure_log" \
  TEST_ASDF_FAIL_VERSION=1.15.9 \
  "$failure_repo/setup-asdf" terraform >/dev/null 2>&1
failure_status=$?
set -e
[[ $failure_status -ne 0 ]] || fail 'asdf runtime installation failure was hidden'
[[ ! -f $failure_log || $(grep -c '^set' "$failure_log") -eq 0 ]] ||
  fail 'runtime failure changed the home default'

printf 'Setup asdf tests passed\n'
