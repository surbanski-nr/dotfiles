#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=fixture.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/fixture.sh"
create_fixture

recovery_repo="$test_root/recovery-repository"
recovery_archives="$test_root/recovery-archives"
recovery_home="$test_root/recovery-home"
make_test_repo "$recovery_repo"
make_archives "$recovery_repo" "$recovery_archives"
mkdir -p "$test_root/fail-bin"
cat >"$test_root/fail-bin/mv" <<'EOF'
#!/usr/bin/env bash
set -eu
args="$*"
source_path=
for argument in "$@"; do
  case $argument in -- | -*) ;; *) source_path=$argument; break ;; esac
done
if [ -n "$source_path" ] && [ -f "$source_path" ] &&
  grep -q '^complete' "$source_path" && [ ! -e "$TEST_MV_MARKER" ]; then
  : >"$TEST_MV_MARKER"
  exit 73
fi
exec "$TEST_REAL_MV" "$@"
EOF
chmod 0755 "$test_root/fail-bin/mv"
real_mv=$(command -v mv)
set +e
PATH="$test_root/fail-bin:$PATH" TEST_REAL_MV="$real_mv" \
  TEST_MV_MARKER="$test_root/mv-failed" \
  run_setup "$recovery_home" "$recovery_repo" "$recovery_archives" k9s >/dev/null 2>&1
publish_status=$?
set -e
[[ $publish_status -eq 73 ]] || fail 'state publication fixture returned an unexpected status'
[[ -f $recovery_home/bin/k9s-$K9S_VERSION ]] || fail 'failed publication lost installed content'
[[ ! -L $recovery_home/bin/k9s ]] || fail 'failed publication changed the selection'
find "$recovery_archives" -depth -delete
run_setup "$recovery_home" "$recovery_repo" "$recovery_archives" k9s
assert_link "$recovery_home/bin/k9s" "k9s-$K9S_VERSION"

pair_repo="$test_root/pair-repository"
pair_archives="$test_root/pair-archives"
pair_home="$test_root/pair-home"
pair_work="$test_root/pair-work"
make_test_repo "$pair_repo"
make_archives "$pair_repo" "$pair_archives"
run_setup "$pair_home" "$pair_repo" "$pair_archives" uv
old_uv_target=$(readlink -- "$pair_home/bin/uv")
old_uvx_target=$(readlink -- "$pair_home/bin/uvx")
new_uv_version=99.1.0
write_fake "$pair_work/uv-x86_64-unknown-linux-gnu/uv" uv "$new_uv_version"
write_fake "$pair_work/uv-x86_64-unknown-linux-gnu/uvx" uvx "$new_uv_version"
mkdir -p "$pair_archives/uv/$new_uv_version"
tar -C "$pair_work" -czf \
  "$pair_archives/uv/$new_uv_version/uv-x86_64-unknown-linux-gnu.tar.gz" \
  uv-x86_64-unknown-linux-gnu
new_uv_digest=$(sha256sum \
  "$pair_archives/uv/$new_uv_version/uv-x86_64-unknown-linux-gnu.tar.gz" | awk '{print $1}')
append_release "$pair_repo/tools.env" TOOL_RELEASES uv "$new_uv_version" \
  "https://example.invalid/uv/$new_uv_version/uv-x86_64-unknown-linux-gnu.tar.gz" "$new_uv_digest"
mkdir -p "$test_root/activation-fail-bin"
cat >"$test_root/activation-fail-bin/mv" <<'EOF'
#!/usr/bin/env bash
set -eu
source_path=
for argument in "$@"; do
  case $argument in -- | -*) ;; *) source_path=$argument; break ;; esac
done
case $source_path in
  */.uvx.link.*)
    if [ ! -e "$TEST_MV_MARKER" ]; then
      : >"$TEST_MV_MARKER"
      exit 74
    fi
    ;;
esac
exec "$TEST_REAL_MV" "$@"
EOF
chmod 0755 "$test_root/activation-fail-bin/mv"
set +e
PATH="$test_root/activation-fail-bin:$PATH" TEST_REAL_MV="$real_mv" \
  TEST_MV_MARKER="$test_root/activation-mv-failed" \
  run_setup "$pair_home" "$pair_repo" "$pair_archives" uv >/dev/null 2>&1
activation_status=$?
set -e
[[ $activation_status -eq 74 ]] || fail 'activation fixture returned an unexpected status'
assert_link "$pair_home/bin/uv" "$old_uv_target"
assert_link "$pair_home/bin/uvx" "$old_uvx_target"

# A kill between the two payload moves leaves recorded but inactive content.
# Retry removes only that partial version and installs both executables again.
pair_state=$pair_home/.local/state/dotfiles/setup-tools/uv-$new_uv_version.state
sed -i 's/^complete/pending/' "$pair_state"
unlink "$pair_home/bin/uvx-$new_uv_version"
run_setup "$pair_home" "$pair_repo" "$pair_archives" uv >/dev/null
assert_link "$pair_home/bin/uv" "uv-$new_uv_version"
assert_link "$pair_home/bin/uvx" "uvx-$new_uv_version"
"$pair_home/bin/uvx" --version | grep -F "$new_uv_version" >/dev/null ||
  fail 'partial paired payload retry did not restore the second executable'

printf 'changed\n' >>"$recovery_home/bin/k9s-$K9S_VERSION"
set +e
modified_output=$(run_setup "$recovery_home" "$recovery_repo" "$recovery_archives" k9s 2>&1)
modified_status=$?
set -e
[[ $modified_status -ne 0 ]] || fail 'modified retained installation was accepted'
[[ $modified_output == *'managed installation was modified'* ]] ||
  fail 'modified retained installation did not report a conflict'

printf 'setup_tools: recovery passed\n'
