#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=fixture.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/fixture.sh"
create_fixture

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
mkdir -p "$test_home/bin-extras"
write_fake_tool "$test_home/bin-extras/node"
set +e
health_failure_output=$(PATH="$test_home/bin-extras:$PATH" run_manager install "$health_artifact" 2>&1)
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

test_home=$test_root/health-home
mkdir -p "$test_home/bin-extras"
for command_name in helm rg stylua; do
  printf '#!/usr/bin/env bash\nexit 91\n' >"$test_home/bin-extras/$command_name"
  chmod 0755 "$test_home/bin-extras/$command_name"
done
export PATH="$test_home/bin-extras:$PATH"
run_manager install "$artifact_one" >/dev/null
VIRTUAL_ENV="$test_home/bin-extras" run_manager health >/dev/null

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

printf 'dotfiles_release: health passed\n'
