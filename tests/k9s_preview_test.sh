#!/usr/bin/env bash

set -euo pipefail

repo_dir=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
task_executable=${VALIDATION_TOOLS_DIR:-$repo_dir/bin}/task
test_root=$(mktemp -d)
preview_pid=
cleanup() {
  if [[ -n $preview_pid ]]; then
    touch "$test_root/release"
    wait "$preview_pid" || true
  fi
  find "$test_root" -depth -delete
}
trap cleanup EXIT
fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

checkout=$test_root/'checkout with spaces'
mkdir -p "$checkout/scripts" "$checkout/tests" "$test_root/bin" "$test_root/state"
cp "$repo_dir/Taskfile.yml" "$checkout/Taskfile.yml"
cp "$repo_dir/scripts/k9s-preview" "$checkout/scripts/"
cp -R "$repo_dir/k9s" "$checkout/k9s"
cp "$repo_dir/tests/k9s-preview.yaml" "$checkout/tests/"
for program in docker kind kubectl k9s; do
  ln -s "$repo_dir/tests/fixtures/k9s-preview/command" "$test_root/bin/$program"
done
export PATH="$test_root/bin:$PATH" TEST_K9S_PREVIEW_STATE=$test_root/state
export HOME=$test_root/home XDG_DATA_HOME=$test_root/'data with spaces'
export XDG_CONFIG_HOME=$test_root/normal-config XDG_CACHE_HOME=$test_root/normal-cache XDG_STATE_HOME=$test_root/normal-state
export K9S_CONFIG_DIR=$test_root/normal-config/k9s K9S_LOGS_DIR=$test_root/normal-state/k9s
export KUBECONFIG=$test_root/normal-kubeconfig KUBECACHEDIR=$test_root/normal-cache/kube
unset DOCKER_HOST DOCKER_CONTEXT
printf 'normal kubeconfig\n' >"$KUBECONFIG"
normal_kubeconfig=$(sha256sum "$KUBECONFIG")
source_hashes=$(find "$checkout/k9s" -type f -exec sha256sum {} + | sort)
printf 'unrelated cluster\n' >"$TEST_K9S_PREVIEW_STATE/cluster-unrelated"
run_preview() {
  "$task_executable" --dir "$checkout" --silent k9s
}
run_clean() {
  "$task_executable" --dir "$checkout" --silent k9s:clean
}

TEST_K9S_DOCKER_STATUS=1 run_preview >"$test_root/docker-failed.log" 2>&1 && fail 'unavailable Docker was accepted'
[[ ! -e $TEST_K9S_PREVIEW_STATE/preview-root ]] || fail 'k9s opened with unavailable Docker'
DOCKER_HOST=tcp://remote.invalid:2375 run_preview >"$test_root/remote.log" 2>&1 && fail 'remote Docker was accepted'

run_preview >"$test_root/open.log" 2>&1
preview_root=$(<"$TEST_K9S_PREVIEW_STATE/preview-root")
cluster=dotfiles-k9s-${preview_root##*/}
[[ -f $TEST_K9S_PREVIEW_STATE/cluster-$cluster && -f $preview_root/kubeconfig ]] || fail 'preview cluster was not retained'
cmp "$checkout/tests/k9s-preview.yaml" "$TEST_K9S_PREVIEW_STATE/workloads-$cluster" || fail 'wrong preview workloads were deployed'
[[ -f $TEST_K9S_PREVIEW_STATE/job-$cluster ]] || fail 'no immediate preview job was created'
[[ $(find "$checkout/k9s" -type f -exec sha256sum {} + | sort) == "$source_hashes" ]] || fail 'k9s changed repository configuration'
[[ $(sha256sum "$KUBECONFIG") == "$normal_kubeconfig" ]] || fail 'normal kubeconfig changed'
[[ ! -e $XDG_CONFIG_HOME && ! -e $XDG_CACHE_HOME && ! -e $XDG_STATE_HOME ]] || fail 'normal profile directories were used'
[[ -f $preview_root/config/k9s/clusters/preview/context/config.yaml && -f $preview_root/config/k9s/hotkeys.yaml ]] ||
  fail 'generated k9s data did not remain in the private profile'

printf '\n# edited configuration\n' >>"$checkout/k9s/.config/k9s/config.yaml"
printf '\n# edited skin\n' >>"$checkout/k9s/.config/k9s/skins/surb.yaml"
run_preview >"$test_root/reopen.log" 2>&1
cmp "$checkout/k9s/.config/k9s/config.yaml" "$TEST_K9S_PREVIEW_STATE/seen-config.yaml" || fail 'configuration changes were not visible'
cmp "$checkout/k9s/.config/k9s/skins/surb.yaml" "$TEST_K9S_PREVIEW_STATE/seen-skin.yaml" || fail 'skin changes were not visible'

mv "$checkout/k9s/.config/k9s/aliases.yaml" "$test_root/source-aliases.yaml"
run_preview >"$test_root/removed-config.log" 2>&1
[[ ! -e $checkout/k9s/.config/k9s/aliases.yaml ]] || fail 'k9s recreated removed repository configuration through a dangling symlink'
[[ -f $preview_root/config/k9s/aliases.yaml && ! -L $preview_root/config/k9s/aliases.yaml ]] || fail 'default aliases escaped the private profile'
mv "$test_root/source-aliases.yaml" "$checkout/k9s/.config/k9s/aliases.yaml"

TEST_K9S_EXIT_STATUS=130 run_preview >"$test_root/interrupt.log" 2>&1 && fail 'k9s interruption was ignored'
[[ -d $preview_root && -f $TEST_K9S_PREVIEW_STATE/cluster-$cluster ]] || fail 'interruption automatically removed the preview'
TEST_K9S_READY=$test_root/ready TEST_K9S_RELEASE=$test_root/release run_preview >"$test_root/held.log" 2>&1 &
preview_pid=$!
deadline=$((SECONDS + 5))
until [[ -e $test_root/ready ]]; do
  ((SECONDS < deadline)) || fail 'preview did not open'
  sleep 0.1
done
run_clean >"$test_root/active-clean.log" 2>&1 && fail 'clean removed an active preview'
[[ -d $preview_root && -f $TEST_K9S_PREVIEW_STATE/cluster-$cluster ]] || fail 'active preview was changed'
touch "$test_root/release"
wait "$preview_pid"
preview_pid=

XDG_DATA_HOME=$test_root/unowned-data run_preview >"$test_root/unowned-open.log" 2>&1 && fail 'unowned cluster was reused'
XDG_DATA_HOME=$test_root/unowned-data run_clean >"$test_root/unowned-clean.log" 2>&1 && fail 'unowned cluster was deleted'
[[ -f $TEST_K9S_PREVIEW_STATE/cluster-$cluster ]] || fail 'ownership rejection changed the cluster'

owner=$(<"$preview_root/owner")
printf 'foreign ownership\n' >"$preview_root/owner"
run_clean >"$test_root/foreign-owner.log" 2>&1 && fail 'foreign ownership was accepted'
printf '%s\n' "$owner" >"$preview_root/owner"
mv "$preview_root/kubeconfig" "$preview_root/kubeconfig.saved"
ln -s "$KUBECONFIG" "$preview_root/kubeconfig"
run_preview >"$test_root/kubeconfig-symlink.log" 2>&1 && fail 'foreign kubeconfig symlink was followed'
run_clean >"$test_root/kubeconfig-symlink-clean.log" 2>&1 && fail 'foreign kubeconfig symlink was followed during clean'
[[ $(sha256sum "$KUBECONFIG") == "$normal_kubeconfig" ]] || fail 'normal kubeconfig symlink target changed'
unlink "$preview_root/kubeconfig"
mv "$preview_root/kubeconfig.saved" "$preview_root/kubeconfig"

TEST_K9S_DELETE_STATUS=1 run_clean >"$test_root/delete-failed.log" 2>&1 && fail 'failed cluster deletion was ignored'
[[ -d $preview_root && -f $TEST_K9S_PREVIEW_STATE/cluster-$cluster ]] || fail 'failed clean lost recovery state'
run_clean >"$test_root/clean.log" 2>&1
run_clean >"$test_root/clean-again.log" 2>&1
[[ ! -e $preview_root && ! -e $TEST_K9S_PREVIEW_STATE/cluster-$cluster ]] || fail 'clean left the owned preview behind'
[[ -f $TEST_K9S_PREVIEW_STATE/cluster-unrelated ]] || fail 'clean removed an unrelated cluster'
[[ -f $checkout/k9s/.config/k9s/config.yaml && -f $checkout/k9s/.config/k9s/skins/surb.yaml ]] || fail 'clean followed repository symlinks'

TEST_K9S_CREATE_STATUS=1 run_preview >"$test_root/create-failed.log" 2>&1 && fail 'partial cluster creation was ignored'
[[ -d $preview_root && -f $TEST_K9S_PREVIEW_STATE/cluster-$cluster ]] || fail 'partial cluster cannot be recovered'
run_clean >"$test_root/partial-clean.log" 2>&1
TEST_K9S_ROLLOUT_STATUS=1 run_preview >"$test_root/rollout-failed.log" 2>&1 && fail 'failed workload rollout was ignored'
[[ -d $preview_root ]] || fail 'failed rollout lost recovery state'
run_preview >"$test_root/rollout-retry.log" 2>&1
run_clean >"$test_root/final-clean.log" 2>&1
printf 'k9s_preview: tests passed\n'
