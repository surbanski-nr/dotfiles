#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=fixture.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/fixture.sh"
create_fixture

test_home=$test_root/ssh-legacy-home
mkdir -p "$test_home"
legacy_ssh_artifact=$test_root/pre-ssh.tar.gz
make_artifact "$commit_one" pre-ssh "$legacy_ssh_artifact" 1.0 false false
find "$test_root/stage-pre-ssh/$id_one/dotfiles/ssh" -depth -delete
repack_artifact pre-ssh "$id_one" "$legacy_ssh_artifact"
run_manager install "$legacy_ssh_artifact" >/dev/null
[[ ! -L $test_home/.ssh/config ]] || fail 'pre-SSH release created SSH links'
run_manager install "$artifact_two" >/dev/null
run_manager set "$id_one" >/dev/null
[[ ! -e $test_home/.ssh/config &&
  ! -e $test_home/.config/systemd/user/dotfiles-ssh-agent.service ]] ||
  fail 'older profile borrowed SSH configuration from the new release'
run_manager set "$id_two" >/dev/null
[[ -r $test_home/.ssh/config && -r $test_home/.config/systemd/user/dotfiles-ssh-agent.service ]] ||
  fail 'switching back did not restore SSH links'
run_manager uninstall >/dev/null
[[ ! -L $test_home/.ssh/config && ! -L $test_home/.config/systemd/user/dotfiles-ssh-agent.service ]] ||
  fail 'uninstall retained optional links'

test_home=$test_root/current-profile-home
mkdir -p "$test_home"
run_manager install "$artifact_two" >/dev/null
run_manager install "$artifact_three" >/dev/null
for command_name in kind uv uvx actionlint shellcheck yamllint gh htop kubeconform kyverno trivy; do
  [[ -x $test_home/bin/$command_name ]] || fail "profile did not publish $command_name"
done
run_manager set "$id_two" >/dev/null
for command_name in kind uv uvx actionlint shellcheck yamllint gh htop kubeconform kyverno trivy; do
  [[ ! -x $test_home/bin/$command_name ]] || fail "old profile borrowed $command_name"
done
run_manager set "$id_three" >/dev/null
run_manager uninstall >/dev/null
for command_name in kind uv uvx actionlint shellcheck yamllint gh htop kubeconform kyverno trivy; do
  [[ ! -L $test_home/bin/$command_name ]] || fail "uninstall retained $command_name"
done

for command_name in kind uv uvx fd go gofmt; do
  marker=missing-$command_name
  archive=$test_root/$marker.tar.gz
  make_artifact "$commit_three" "$marker" "$archive" 3.0 true true true
  unlink "$test_root/stage-$marker/$id_three/bin/$command_name"
  repack_artifact "$marker" "$id_three" "$archive"
  if run_manager verify "$archive" >/dev/null 2>&1; then
    fail "verification accepted a profile without $command_name"
  fi
done
for field in KIND_VERSION UV_VERSION FD_VERSION GO_VERSION; do
  marker=missing-$field
  archive=$test_root/$marker.tar.gz
  make_artifact "$commit_three" "$marker" "$archive" 3.0 true true true
  sed -i "/^$field=/d" "$test_root/stage-$marker/$id_three/release.env"
  repack_artifact "$marker" "$id_three" "$archive"
  if run_manager verify "$archive" >/dev/null 2>&1; then
    fail "verification accepted a profile without $field"
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

test_home=$test_root/pre-go-home
mkdir -p "$test_home"
old_go_artifact=$test_root/pre-go.tar.gz
make_artifact "$commit_one" pre-go "$old_go_artifact" 1.0 true false
run_manager install "$old_go_artifact" >/dev/null
run_manager install "$artifact_two" >/dev/null
run_manager set "$id_one" >/dev/null
[[ -x $test_home/bin/fd && ! -x $test_home/bin/go && ! -x $test_home/bin/gofmt ]] ||
  fail 'pre-Go selection did not keep only the supported tools'

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

printf 'dotfiles_release: profiles passed\n'
