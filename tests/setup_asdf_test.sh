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

# shellcheck source=../tools.env
source "$repo_dir/tools.env"
# shellcheck source=../scripts/setup-lib
source "$repo_dir/scripts/setup-lib"
ASDF_VERSION=9.9.0

append_release() {
  local file=$1 tool=$2 version=$3 url=$4 digest=$5 value

  value=$'\n'"$version|$url|$digest"$'\n'
  printf 'TOOL_RELEASES[%q]=%q\n' "$tool" "$value" >>"$file"
}

test_catalog=$test_root/tools.env
cp "$repo_dir/tools.env" "$test_catalog"
append_release "$test_catalog" asdf "$ASDF_VERSION" \
  https://example.invalid/asdf.tar.gz "$(printf '%064d' 0)"
printf 'TOOL_RELEASES[terraform]=%q\n' \
  $'\n9.2.0|https://example.invalid/terraform-9.2.0.zip|0000000000000000000000000000000000000000000000000000000000000000\n9.1.0|https://example.invalid/terraform-9.1.0.zip|1111111111111111111111111111111111111111111111111111111111111111\n' \
  >>"$test_catalog"
append_release "$test_catalog" nodejs 89.1.0 \
  https://example.invalid/node-v89.1.0-linux-x64.tar.xz "$(printf '%064d' 0)"
append_release "$test_catalog" terragrunt 9.3.0 \
  https://example.invalid/terragrunt_linux_amd64 "$(printf '%064d' 0)"
cat >>"$test_catalog" <<'EOF'
ASDF_PLUGINS=(
  [terraform]='https://example.invalid/terraform.git|0000000000000000000000000000000000000000'
  [nodejs]='https://example.invalid/nodejs.git|0000000000000000000000000000000000000000'
  [terragrunt]='https://example.invalid/terragrunt.git|0000000000000000000000000000000000000000'
)
EOF
# shellcheck disable=SC1090
source "$test_catalog"

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
  local home=$1 target=$2 installs
  installs=$home/.local/state/dotfiles/setup-asdf/installations
  mkdir -p "$installs"
  sha256sum "$home/bin/$target" | awk '{print $1}' >"$installs/$target.sha256"
  chmod 0600 "$installs/$target.sha256"
}

prepare_plugin() {
  local home=$1 repository=$2 name=${3:-terraform}
  local plugin=$home/.asdf/plugins/$name
  local plugin_commit
  mkdir -p "$plugin"
  git init -q "$plugin"
  git -C "$plugin" config user.name fixture
  git -C "$plugin" config user.email fixture@example.invalid
  printf 'fixture\n' >"$plugin/plugin"
  git -C "$plugin" add plugin
  git -C "$plugin" commit -qm fixture
  plugin_commit=$(git -C "$plugin" rev-parse HEAD)
  git -C "$plugin" remote add origin "https://example.invalid/$name.git"
  printf 'ASDF_PLUGINS[%q]=%q\n' "$name" \
    "https://example.invalid/$name.git|$plugin_commit" >>"$repository/tools.env"
}

test_repo="$test_root/repository"
test_home="$test_root/home"
mkdir -p "$test_repo/scripts" "$test_home/bin"
cp "$repo_dir/setup-asdf" "$test_repo/setup-asdf"
cp "$repo_dir/scripts/setup-lib" "$test_repo/scripts/setup-lib"
cp "$test_catalog" "$test_repo/tools.env"
cp "$repo_dir/system.env" "$test_repo/system.env"

for tool in kubectl helm python; do
  printf '#!/usr/bin/env bash\nexit 0\n' >"$test_home/bin/$tool"
  chmod 0755 "$test_home/bin/$tool"
  set +e
  unsupported_output=$(HOME="$test_home" "$test_repo/setup-asdf" "$tool" 2>&1)
  unsupported_status=$?
  set -e
  [[ $unsupported_status -ne 0 && $unsupported_output == *"unknown project tool: $tool"* ]] ||
    fail "setup-asdf still accepts $tool"
  [[ ! -e $test_home/bin/asdf && ! -e $test_home/.asdf &&
    ! -e $test_home/.local/state/dotfiles/setup-asdf ]] ||
    fail 'unsupported tool request changed the asdf installation'
done

cat >"$test_home/bin/terraform" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod 0755 "$test_home/bin/terraform"
set +e
conflict_output=$(HOME="$test_home" "$test_repo/setup-asdf" terraform 2>&1)
conflict_status=$?
set -e
[[ $conflict_status -ne 0 ]] || fail 'direct terraform launcher conflict was accepted'
[[ $conflict_output == *'conflicts with the direct launcher'* ]] ||
  fail 'direct launcher conflict was not reported'
[[ ! -e $test_home/bin/asdf && ! -e $test_home/.asdf ]] ||
  fail 'provider conflict changed the asdf installation'

rm "$test_home/bin/terraform"
mkdir -p "$test_home/.local/state/dotfiles"
exec {test_lock_fd}>"$test_home/.local/state/dotfiles/setup.lock"
flock -n "$test_lock_fd"
set +e
lock_output=$(HOME="$test_home" "$test_repo/setup-asdf" terraform 2>&1)
lock_status=$?
set -e
[[ $lock_status -ne 0 ]] || fail 'concurrent setup-asdf lock was ignored'
[[ $lock_output == *'another online installer is running'* ]] ||
  fail 'concurrent setup-asdf did not report the lock'
[[ ! -e $test_home/bin/asdf ]] || fail 'lock conflict installed asdf'

exec {test_lock_fd}>&-
write_asdf_fixture "$test_home/bin/asdf-manual" manual
ln -s asdf-manual "$test_home/bin/asdf"
set +e
foreign_output=$(HOME="$test_home" "$test_repo/setup-asdf" terraform 2>&1)
foreign_status=$?
set -e
[[ $foreign_status -ne 0 && $foreign_output == *'refusing foreign asdf link'* ]] ||
  fail 'foreign asdf-manual link was accepted'
[[ $(readlink -- "$test_home/bin/asdf") == asdf-manual ]] ||
  fail 'foreign asdf link was changed'

install_repo=$test_root/install-repository
install_home=$test_root/install-home
install_log=$test_root/install.log
archive_root=$test_root/archive
asdf_archive=$test_root/asdf.tar.gz
mkdir -p "$install_repo/scripts" "$install_home/bin" "$archive_root"
cp "$repo_dir/setup-asdf" "$install_repo/setup-asdf"
cp "$repo_dir/scripts/setup-lib" "$install_repo/scripts/setup-lib"
cp "$test_catalog" "$install_repo/tools.env"
cp "$repo_dir/system.env" "$install_repo/system.env"
prepare_plugin "$install_home" "$install_repo"
write_asdf_fixture "$archive_root/asdf" "$ASDF_VERSION"
tar -C "$archive_root" -czf "$asdf_archive" asdf
archive_digest=$(sha256sum "$asdf_archive" | awk '{print $1}')
append_release "$install_repo/tools.env" asdf "$ASDF_VERSION" \
  https://example.invalid/asdf.tar.gz "$archive_digest"
cat >"$install_home/bin/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
destination=
while (($#)); do
  case $1 in
    --output) destination=$2; shift 2 ;;
    *) shift ;;
  esac
done
[[ -n $destination ]]
cp "$TEST_ASDF_ARCHIVE" "$destination"
EOF
chmod 0755 "$install_home/bin/curl"

# Even an exact pinned binary is foreign without its installation record.
unmanaged_home=$test_root/unmanaged-home
mkdir -p "$unmanaged_home/bin"
cp -a "$install_home/.asdf" "$unmanaged_home/.asdf"
cp "$archive_root/asdf" "$unmanaged_home/bin/asdf-$ASDF_VERSION"
ln -s "asdf-$ASDF_VERSION" "$unmanaged_home/bin/asdf"
cp "$install_home/bin/curl" "$unmanaged_home/bin/curl"
unmanaged_digest=$(sha256sum "$unmanaged_home/bin/asdf-$ASDF_VERSION")
for selection in linked unlinked; do
  if [[ $selection == unlinked ]]; then unlink "$unmanaged_home/bin/asdf"; fi
  set +e
  unmanaged_output=$(HOME="$unmanaged_home" PATH="$unmanaged_home/bin:/usr/bin:/bin" \
    TEST_ASDF_ARCHIVE="$asdf_archive" TEST_ASDF_LOG="$test_root/unmanaged.log" \
    "$install_repo/setup-asdf" terraform 2>&1)
  unmanaged_status=$?
  set -e
  [[ $unmanaged_status -ne 0 && $unmanaged_output == *'refusing unmanaged asdf installation'* ]] ||
    fail "$selection unrecorded asdf installation was accepted"
  [[ $(sha256sum "$unmanaged_home/bin/asdf-$ASDF_VERSION") == "$unmanaged_digest" ]] ||
    fail 'unrecorded asdf binary was changed'
  if [[ $selection == linked ]]; then
    [[ $(readlink -- "$unmanaged_home/bin/asdf") == "asdf-$ASDF_VERSION" ]] ||
      fail 'unrecorded asdf command link was changed'
  else
    [[ ! -e $unmanaged_home/bin/asdf && ! -L $unmanaged_home/bin/asdf ]] ||
      fail 'unrecorded asdf binary was selected'
  fi
  [[ ! -e $unmanaged_home/.local/state/dotfiles/setup-asdf/installations &&
    ! -e $test_root/unmanaged.log ]] || fail 'unrecorded asdf rejection changed installation state'
done

HOME="$install_home" PATH="$install_home/bin:/usr/bin:/bin" \
  TEST_ASDF_ARCHIVE="$asdf_archive" TEST_ASDF_LOG="$install_log" \
  "$install_repo/setup-asdf" terraform
[[ $(readlink -- "$install_home/bin/asdf") == "asdf-$ASDF_VERSION" ]] ||
  fail 'fresh asdf installation was not selected'
[[ $(sha256sum "$install_home/bin/asdf-$ASDF_VERSION" | awk '{print $1}') == \
  $(<"$install_home/.local/state/dotfiles/setup-asdf/installations/asdf-$ASDF_VERSION.sha256") ]] ||
  fail 'fresh asdf installation digest was not recorded'
install_state_digest=$(sha256sum \
  "$install_home/bin/asdf-$ASDF_VERSION" \
  "$install_home/.local/state/dotfiles/setup-asdf/installations/asdf-$ASDF_VERSION.sha256")
HOME="$install_home" PATH="$install_home/bin:/usr/bin:/bin" \
  TEST_ASDF_ARCHIVE="$test_root/absent-archive" TEST_ASDF_LOG="$install_log" \
  "$install_repo/setup-asdf" terraform
[[ $(sha256sum \
  "$install_home/bin/asdf-$ASDF_VERSION" \
  "$install_home/.local/state/dotfiles/setup-asdf/installations/asdf-$ASDF_VERSION.sha256") == \
  "$install_state_digest" ]] || fail 'fresh asdf installation retry changed ownership state'

reconcile_repo=$test_root/reconcile-repository
reconcile_home=$test_root/reconcile-home
reconcile_log=$test_root/reconcile.log
mkdir -p "$reconcile_repo/scripts" "$reconcile_home/bin"
cp "$repo_dir/setup-asdf" "$reconcile_repo/setup-asdf"
cp "$repo_dir/scripts/setup-lib" "$reconcile_repo/scripts/setup-lib"
cp "$test_catalog" "$reconcile_repo/tools.env"
cp "$repo_dir/system.env" "$reconcile_repo/system.env"
prepare_plugin "$reconcile_home" "$reconcile_repo"
write_asdf_fixture "$reconcile_home/bin/asdf-0.0.1" 0.0.1
write_asdf_fixture "$reconcile_home/bin/asdf-$ASDF_VERSION" "$ASDF_VERSION"
ln -s asdf-0.0.1 "$reconcile_home/bin/asdf"
record_asdf_fixture "$reconcile_home" asdf-0.0.1
sha256sum "$reconcile_home/bin/asdf-$ASDF_VERSION" | awk '{print $1}' \
  >"$reconcile_home/.local/state/dotfiles/setup-asdf/installations/asdf-$ASDF_VERSION.sha256"

HOME="$reconcile_home" TEST_ASDF_LOG="$reconcile_log" \
  "$reconcile_repo/setup-asdf" terraform
[[ $(readlink -- "$reconcile_home/bin/asdf") == "asdf-$ASDF_VERSION" ]] ||
  fail 'managed asdf was not upgraded to the selected version'
[[ -x $reconcile_home/bin/asdf-0.0.1 ]] || fail 'previous asdf binary was removed'
HOME="$reconcile_home" TEST_ASDF_LOG="$reconcile_log" \
  "$reconcile_repo/setup-asdf" terraform
[[ $(grep -c '^install' "$reconcile_log") -eq 2 ]] ||
  fail 'second setup-asdf run reinstalled a runtime'
[[ $(grep -c '^set' "$reconcile_log") -eq 2 ]] ||
  fail 'setup-asdf did not select the home default after each successful run'

# A verified retained binary may be selected manually. Obsolete selection
# records are ignored and neither override the link nor get rewritten.
unlink "$reconcile_home/bin/asdf"
ln -s asdf-0.0.1 "$reconcile_home/bin/asdf"
obsolete_state=$reconcile_home/.local/state/dotfiles/setup-asdf
printf 'obsolete selection\n' >"$obsolete_state/asdf-target"
printf 'obsolete journal\n' >"$obsolete_state/pending-selection"
obsolete_digest=$(sha256sum "$obsolete_state/asdf-target" "$obsolete_state/pending-selection")
HOME="$reconcile_home" TEST_ASDF_LOG="$reconcile_log" \
  "$reconcile_repo/setup-asdf" terraform >/dev/null
[[ $(readlink -- "$reconcile_home/bin/asdf") == "asdf-$ASDF_VERSION" ]] ||
  fail 'a manual managed selection did not reconcile to the catalog pin'
[[ $(sha256sum "$obsolete_state/asdf-target" "$obsolete_state/pending-selection") == "$obsolete_digest" ]] ||
  fail 'obsolete selection records were rewritten'

# A missing command link can be recreated from a verified retained binary.
unlink "$reconcile_home/bin/asdf"
HOME="$reconcile_home" TEST_ASDF_LOG="$reconcile_log" \
  "$reconcile_repo/setup-asdf" terraform >/dev/null
[[ $(readlink -- "$reconcile_home/bin/asdf") == "asdf-$ASDF_VERSION" ]] ||
  fail 'missing managed asdf command link was not restored'

printf '# local edit\n' >>"$reconcile_home/bin/asdf-$ASDF_VERSION"
modified_digest=$(sha256sum "$reconcile_home/bin/asdf-$ASDF_VERSION")
if HOME="$reconcile_home" TEST_ASDF_LOG="$reconcile_log" \
  "$reconcile_repo/setup-asdf" terraform >"$test_root/modified-asdf.log" 2>&1; then
  fail 'a modified managed asdf binary was accepted'
fi
grep -F 'managed asdf installation was modified' "$test_root/modified-asdf.log" >/dev/null ||
  fail 'modified managed asdf binary was not diagnosed'
[[ $(sha256sum "$reconcile_home/bin/asdf-$ASDF_VERSION") == "$modified_digest" ]] ||
  fail 'modified managed asdf binary was overwritten'

order_repo=$test_root/order-repository
order_home=$test_root/order-home
order_log=$test_root/order.log
mkdir -p "$order_repo/scripts" "$order_home/bin"
cp "$repo_dir/setup-asdf" "$order_repo/setup-asdf"
cp "$repo_dir/scripts/setup-lib" "$order_repo/scripts/setup-lib"
cp "$test_catalog" "$order_repo/tools.env"
cp "$repo_dir/system.env" "$order_repo/system.env"
prepare_plugin "$order_home" "$order_repo"
write_asdf_fixture "$order_home/bin/asdf-$ASDF_VERSION" "$ASDF_VERSION"
ln -s "asdf-$ASDF_VERSION" "$order_home/bin/asdf"
record_asdf_fixture "$order_home" "asdf-$ASDF_VERSION"
printf 'TOOL_RELEASES[terraform]=%q\n' \
  $'\n9.1.0|https://example.invalid/terraform-9.1.0.zip|0000000000000000000000000000000000000000000000000000000000000000\n9.2.0|https://example.invalid/terraform-9.2.0.zip|1111111111111111111111111111111111111111111111111111111111111111\n' \
  >>"$order_repo/tools.env"
HOME="$order_home" TEST_ASDF_LOG="$order_log" "$order_repo/setup-asdf" terraform
[[ $(grep '^install' "$order_log") == $'install\tterraform\t9.1.0\ninstall\tterraform\t9.2.0' &&
  $(tail -n 1 "$order_log") == $'set\tterraform\t9.1.0' ]] ||
  fail 'record order did not control installation order and home default'

default_repo=$test_root/default-repository
default_home=$test_root/default-home
default_log=$test_root/default.log
mkdir -p "$default_repo/scripts" "$default_home/bin"
cp "$repo_dir/setup-asdf" "$default_repo/setup-asdf"
cp "$repo_dir/scripts/setup-lib" "$default_repo/scripts/setup-lib"
cp "$test_catalog" "$default_repo/tools.env"
cp "$repo_dir/system.env" "$default_repo/system.env"
for tool in "${!ASDF_PLUGINS[@]}"; do
  prepare_plugin "$default_home" "$default_repo" "$tool"
done
write_asdf_fixture "$default_home/bin/asdf-$ASDF_VERSION" "$ASDF_VERSION"
ln -s "asdf-$ASDF_VERSION" "$default_home/bin/asdf"
record_asdf_fixture "$default_home" "asdf-$ASDF_VERSION"
for tool in kubectl helm; do
  printf '#!/usr/bin/env bash\nexit 0\n' >"$default_home/bin/$tool"
  chmod 0755 "$default_home/bin/$tool"
done
HOME="$default_home" TEST_ASDF_LOG="$default_log" "$default_repo/setup-asdf"
for installation in terraform/9.2.0 terraform/9.1.0 nodejs/89.1.0 terragrunt/9.3.0; do
  [[ -d $default_home/.asdf/installs/$installation ]] ||
    fail "default setup-asdf did not install $installation"
done
for expected in \
  $'set\tterraform\t9.2.0' \
  $'set\tnodejs\t89.1.0' \
  $'set\tterragrunt\t9.3.0'; do
  grep -Fx "$expected" "$default_log" >/dev/null ||
    fail "default setup-asdf omitted: $expected"
done

[[ ! -e $default_home/.asdf/installs/kubectl && ! -e $default_home/.asdf/installs/helm &&
  ! -e $default_home/.asdf/installs/python ]] ||
  fail 'default setup-asdf installed a directly managed runtime or client'

printf 'unset "ASDF_PLUGINS[terragrunt]"\n' >>"$default_repo/tools.env"
subset_log=$test_root/subset.log
HOME="$default_home" TEST_ASDF_LOG="$subset_log" "$default_repo/setup-asdf"
[[ $(grep -c '^set' "$subset_log") -eq 2 ]] ||
  fail 'default setup-asdf ignored a removed plugin mapping'
if grep -q $'\tterragrunt\t' "$subset_log"; then
  fail 'default setup-asdf installed a tool without a plugin mapping'
fi
if HOME="$default_home" TEST_ASDF_LOG="$subset_log" "$default_repo/setup-asdf" terragrunt \
  >"$test_root/removed-plugin.log" 2>&1; then
  fail 'setup-asdf accepted a removed plugin mapping'
fi

failure_repo=$test_root/failure-repository
failure_home=$test_root/failure-home
failure_log=$test_root/failure.log
mkdir -p "$failure_repo/scripts" "$failure_home/bin"
cp "$repo_dir/setup-asdf" "$failure_repo/setup-asdf"
cp "$repo_dir/scripts/setup-lib" "$failure_repo/scripts/setup-lib"
cp "$test_catalog" "$failure_repo/tools.env"
cp "$repo_dir/system.env" "$failure_repo/system.env"
prepare_plugin "$failure_home" "$failure_repo"
write_asdf_fixture "$failure_home/bin/asdf-$ASDF_VERSION" "$ASDF_VERSION"
ln -s "asdf-$ASDF_VERSION" "$failure_home/bin/asdf"
record_asdf_fixture "$failure_home" "asdf-$ASDF_VERSION"
set +e
HOME="$failure_home" TEST_ASDF_LOG="$failure_log" \
  TEST_ASDF_FAIL_VERSION=9.1.0 \
  "$failure_repo/setup-asdf" terraform >/dev/null 2>&1
failure_status=$?
set -e
[[ $failure_status -ne 0 ]] || fail 'asdf runtime installation failure was hidden'
[[ ! -f $failure_log || $(grep -c '^set' "$failure_log") -eq 0 ]] ||
  fail 'runtime failure changed the home default'

HOME="$failure_home" TEST_ASDF_LOG="$failure_log" \
  "$failure_repo/setup-asdf" terraform >/dev/null
[[ $(grep -c '^install' "$failure_log") -eq 3 &&
  $(tail -n 1 "$failure_log") == $'set\tterraform\t9.2.0' ]] ||
  fail 'runtime retry did not reuse success and finish the failed version'

# Interrupt each publication boundary, then retry with downloads disabled once
# the verified binary is present. Selection needs only the atomic command link.
recovery_bin=$test_root/recovery-bin
mkdir -p "$recovery_bin"
cat >"$recovery_bin/mv" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
destination=${!#}
case "$TEST_ASDF_FAIL_POINT:$destination" in
  binary:*/bin/asdf-* | digest:*/installations/asdf-*.sha256 | selection:*/bin/asdf)
    if [[ ! -e $TEST_ASDF_FAIL_MARKER ]]; then
      : >"$TEST_ASDF_FAIL_MARKER"
      exit 74
    fi
    ;;
  after-binary:*/bin/asdf-* | after-selection:*/bin/asdf)
    /usr/bin/mv "$@"
    kill -KILL "$PPID"
    exit 0
    ;;
esac
exec /usr/bin/mv "$@"
EOF
chmod 0755 "$recovery_bin/mv"
for point in digest binary after-binary selection after-selection; do
  recovery_home=$test_root/recovery-$point
  recovery_repo=$test_root/recovery-repository-$point
  recovery_log=$test_root/recovery-$point.log
  mkdir -p "$recovery_home/bin" "$recovery_repo/scripts"
  cp "$repo_dir/setup-asdf" "$recovery_repo/setup-asdf"
  cp "$repo_dir/scripts/setup-lib" "$recovery_repo/scripts/setup-lib"
  cp "$install_repo/tools.env" "$recovery_repo/tools.env"
  cp "$repo_dir/system.env" "$recovery_repo/system.env"
  prepare_plugin "$recovery_home" "$recovery_repo"
  cp "$install_home/bin/curl" "$recovery_home/bin/curl"
  write_asdf_fixture "$recovery_home/bin/asdf-0.0.1" 0.0.1
  record_asdf_fixture "$recovery_home" asdf-0.0.1
  ln -s asdf-0.0.1 "$recovery_home/bin/asdf"
  set +e
  HOME="$recovery_home" PATH="$recovery_bin:$recovery_home/bin:/usr/bin:/bin" \
    TEST_ASDF_ARCHIVE="$asdf_archive" TEST_ASDF_LOG="$recovery_log" \
    TEST_ASDF_FAIL_POINT="$point" TEST_ASDF_FAIL_MARKER="$test_root/failed-$point" \
    "$recovery_repo/setup-asdf" terraform >"$test_root/failure-$point.log" 2>&1
  publication_status=$?
  set -e
  if [[ $point == after-* ]]; then expected_status=137; else expected_status=74; fi
  [[ $publication_status -eq $expected_status ]] || fail "$point publication failure was hidden"
  if [[ $point == after-selection ]]; then expected_target=asdf-$ASDF_VERSION
  else expected_target=asdf-0.0.1
  fi
  [[ $(readlink -- "$recovery_home/bin/asdf") == "$expected_target" ]] ||
    fail "$point interruption changed selection unexpectedly"
  if [[ $point == after-binary || $point == selection || $point == after-selection ]]; then
    recovery_archive=$test_root/absent-archive
  else recovery_archive=$asdf_archive
  fi
  HOME="$recovery_home" PATH="$recovery_home/bin:/usr/bin:/bin" \
    TEST_ASDF_ARCHIVE="$recovery_archive" TEST_ASDF_LOG="$recovery_log" \
    "$recovery_repo/setup-asdf" terraform >/dev/null
  [[ $(readlink -- "$recovery_home/bin/asdf") == "asdf-$ASDF_VERSION" ]] ||
    fail "$point retry did not select the verified binary"
  [[ $(sha256sum "$recovery_home/bin/asdf-$ASDF_VERSION" | awk '{print $1}') == \
    $(<"$recovery_home/.local/state/dotfiles/setup-asdf/installations/asdf-$ASDF_VERSION.sha256") ]] ||
    fail "$point retry lost verified binary ownership"
  [[ -x $recovery_home/bin/asdf-0.0.1 ]] || fail "$point retry removed the old binary"
  [[ ! -e $recovery_home/.local/state/dotfiles/setup-asdf/asdf-target &&
    ! -e $recovery_home/.local/state/dotfiles/setup-asdf/pending-selection ]] ||
    fail "$point retry recreated redundant selection records"
done

# Retry must not interpret a foreign command link as interrupted publication.
unlink "$recovery_home/bin/asdf"
ln -s asdf-manual "$recovery_home/bin/asdf"
if HOME="$recovery_home" TEST_ASDF_LOG="$recovery_log" \
  "$recovery_repo/setup-asdf" terraform >"$test_root/foreign-retry.log" 2>&1; then
  fail 'retry replaced an unrelated asdf link'
fi
[[ $(readlink -- "$recovery_home/bin/asdf") == asdf-manual ]] ||
  fail 'retry modified an unrelated asdf link'

printf 'Setup asdf tests passed\n'
