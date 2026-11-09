#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=fixture.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/fixture.sh"
create_fixture

test_home=$test_root/current-tools-home
release_bin=$test_home/dotfiles-releases/current/bin
mkdir -p "$test_home"
run_manager install "$artifact_two" >/dev/null
run_manager install "$artifact_three" >/dev/null
for command_name in kind uv uvx actionlint shellcheck yamllint gh htop kubeconform kyverno trivy; do
  [[ -x $release_bin/$command_name ]] || fail "selection did not expose $command_name"
done
[[ ! -e $test_home/bin ]] || fail 'release created a user bin directory'
run_manager set "$id_two" >/dev/null
for command_name in kind uv uvx actionlint shellcheck yamllint gh htop kubeconform kyverno trivy; do
  [[ ! -e $release_bin/$command_name && ! -L $release_bin/$command_name ]] ||
    fail "old selection borrowed or left a dangling link for $command_name"
done
run_manager set "$id_three" >/dev/null
run_manager uninstall >/dev/null
for command_name in kind uv uvx actionlint shellcheck yamllint gh htop kubeconform kyverno trivy; do
  [[ ! -L $release_bin/$command_name ]] || fail "uninstall retained $command_name"
done

for command_name in kind uv uvx fd go gofmt; do
  marker=missing-$command_name
  archive=$test_root/$marker.tar.gz
  make_artifact "$commit_three" "$marker" "$archive" 3.0 true true true
  unlink "$test_root/stage-$marker/$id_three/bin/$command_name"
  repack_artifact "$marker" "$id_three" "$archive"
  if run_manager verify "$archive" >/dev/null 2>&1; then
    fail "verification accepted a selection without $command_name"
  fi
done
for field in KIND_VERSION UV_VERSION FD_VERSION GO_VERSION; do
  marker=missing-$field
  archive=$test_root/$marker.tar.gz
  make_artifact "$commit_three" "$marker" "$archive" 3.0 true true true
  sed -i "/^$field=/d" "$test_root/stage-$marker/$id_three/release.env"
  repack_artifact "$marker" "$id_three" "$archive"
  if run_manager verify "$archive" >/dev/null 2>&1; then
    fail "verification accepted a selection without $field"
  fi
done

for field in FD_VERSION GO_VERSION; do
  marker=wrong-$field
  archive=$test_root/$marker.tar.gz
  make_artifact "$commit_three" "$marker" "$archive" 3.0 true true true
  sed -i "s/^$field=.*/$field=9.9/" "$test_root/stage-$marker/$id_three/release.env"
  repack_artifact "$marker" "$id_three" "$archive"
  run_manager verify "$archive" >/dev/null
  if run_manager install "$archive" >/dev/null 2>&1; then
    fail "installation accepted an unexpected $field runtime"
  fi
done

test_home=$test_root/without-go-home
release_bin=$test_home/dotfiles-releases/current/bin
mkdir -p "$test_home"
without_go_artifact=$test_root/without-go.tar.gz
make_artifact "$commit_one" without-go "$without_go_artifact" 1.0 true false
run_manager install "$without_go_artifact" >/dev/null
run_manager install "$artifact_two" >/dev/null
run_manager set "$id_one" >/dev/null
[[ -x $release_bin/fd && ! -x $release_bin/go && ! -x $release_bin/gofmt ]] ||
  fail 'selection without Go did not keep only the selected tools'

test_home=$test_root/provider-backup-home
mkdir -p "$test_home/bin"
for command_name in kind uv uvx gh go gofmt fd; do
  write_fake_tool "$test_home/bin/$command_name-0.9" 0.9
  ln -s "$command_name-0.9" "$test_home/bin/$command_name"
done
write_fake_tool "$test_home/bin/htop-0.9/bin/htop" 0.9
ln -s htop-0.9/bin/htop "$test_home/bin/htop"
run_manager install "$artifact_three" >/dev/null
run_manager uninstall >/dev/null
for command_name in kind uv uvx gh go gofmt fd; do
  assert_link "$test_home/bin/$command_name" "$command_name-0.9"
  [[ -x $test_home/bin/$command_name-0.9 ]] || fail 'saved provider payload was removed'
done
assert_link "$test_home/bin/htop" htop-0.9/bin/htop

printf 'dotfiles_release: tool_lists passed\n'
