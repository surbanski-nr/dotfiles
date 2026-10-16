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
[[ ! -L $test_home/.ssh/config && ! -L $test_home/.config/systemd/user/dotfiles-ssh-agent.service ]] ||
  fail 'installing a pre-SSH release created SSH links'
run_manager install "$artifact_two" >/dev/null
[[ -r $test_home/.ssh/config && -r $test_home/.config/systemd/user/dotfiles-ssh-agent.service ]] ||
  fail 'upgrading a pre-SSH release did not publish the SSH configuration'
run_manager rollback >/dev/null
assert_link "$test_home/dotfiles-releases/current" "$id_one"
run_manager health >/dev/null
[[ ! -e $test_home/.ssh/config && ! -e $test_home/.config/systemd/user/dotfiles-ssh-agent.service ]] ||
  fail 'pre-SSH rollback still resolves SSH configuration from the newer release'
run_manager rollback "$id_two" >/dev/null
[[ -r $test_home/.ssh/config && -r $test_home/.config/systemd/user/dotfiles-ssh-agent.service ]] ||
  fail 'selecting the SSH release again did not restore its configuration'
run_manager uninstall >/dev/null
[[ ! -L $test_home/.ssh/config && ! -L $test_home/.config/systemd/user/dotfiles-ssh-agent.service ]] ||
  fail 'uninstall retained optional SSH links'

test_home=$test_root/current-profile-validation-home
mkdir -p "$test_home"
for command_name in kind uv uvx; do
  candidate=$test_root/current-profile-missing-$command_name.tar.gz
  make_artifact "$commit_three" "current-profile-missing-$command_name" "$candidate" 3.0 true true true
  rm "$test_root/stage-current-profile-missing-$command_name/$id_three/bin/$command_name"
  repack_artifact "current-profile-missing-$command_name" "$id_three" "$candidate"
  if run_manager install "$candidate" >"$test_root/current-profile-missing-$command_name.log" 2>&1; then
    fail "release was installed without $command_name"
  fi
done
for field in KIND_VERSION UV_VERSION; do
  candidate=$test_root/current-profile-missing-$field.tar.gz
  make_artifact "$commit_three" "current-profile-missing-$field" "$candidate" 3.0 true true true
  sed -i "/^$field=/d" "$test_root/stage-current-profile-missing-$field/$id_three/release.env"
  repack_artifact "current-profile-missing-$field" "$id_three" "$candidate"
  if run_manager install "$candidate" >"$test_root/current-profile-missing-$field.log" 2>&1; then
    fail 'current profile was installed without its version metadata'
  fi
done
[[ ! -e $test_home/dotfiles-releases/current ]] || fail 'invalid current-profile release became active'

test_home=$test_root/current-profile-rollback-home
mkdir -p "$test_home"
run_manager install "$artifact_two" >/dev/null
run_manager install "$artifact_three" >/dev/null
for command_name in kind uv uvx actionlint shellcheck yamllint gh htop kubeconform kyverno trivy; do
  [[ -x $test_home/bin/$command_name ]] || fail "release did not publish $command_name"
done
run_manager health "$id_two" >/dev/null
run_manager rollback >/dev/null
for command_name in kind uv uvx actionlint shellcheck yamllint gh htop kubeconform kyverno trivy; do
  [[ ! -x $test_home/bin/$command_name ]] || fail "legacy rollback retained $command_name"
done
run_manager rollback "$id_three" >/dev/null
run_manager uninstall >/dev/null
for command_name in kind uv uvx actionlint shellcheck yamllint gh htop kubeconform kyverno trivy; do
  [[ ! -e $test_home/bin/$command_name && ! -L $test_home/bin/$command_name ]] ||
    fail "uninstall retained $command_name"
done

test_home=$test_root/current-profile-connected-home
mkdir -p "$test_home/bin" "$test_home/.local/state/dotfiles/setup-tools"
for command_name in kind uv uvx gh; do
  write_fake_tool "$test_home/bin/$command_name-0.9" 0.9
  ln -s "$command_name-0.9" "$test_home/bin/$command_name"
done
write_fake_tool "$test_home/bin/htop-0.9/bin/htop" 0.9
ln -s htop-0.9/bin/htop "$test_home/bin/htop"
for tool in kind uv gh htop; do
  destinations=("$tool-0.9")
  [[ $tool != uv ]] || destinations+=(uvx-0.9)
  content=$(tar --sort=name --mtime=@0 --owner=0 --group=0 --numeric-owner \
    -C "$test_home/bin" -cf - -- "${destinations[@]}" | sha256sum | awk '{print $1}')
  printf 'complete\t%s\t%s\n' \
    aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa "$content" \
    >"$test_home/.local/state/dotfiles/setup-tools/$tool-0.9.state"
done
run_manager install "$artifact_three" >/dev/null
run_manager uninstall >/dev/null
for command_name in kind uv uvx gh; do
  assert_link "$test_home/bin/$command_name" "$command_name-0.9"
done
assert_link "$test_home/bin/htop" htop-0.9/bin/htop
printf '\nmodified\n' >>"$test_home/bin/uvx-0.9"
if run_manager install "$artifact_three" >"$test_root/uv-modified-provider.log" 2>&1; then
  fail 'offline release adopted a uv pair with a modified uvx'
fi
assert_link "$test_home/bin/uv" uv-0.9
assert_link "$test_home/bin/uvx" uvx-0.9

test_home=$test_root/go-validation-home
mkdir -p "$test_home"
go_broken=$test_root/go-broken.tar.gz
make_artifact "$commit_three" go-missing-pin "$go_broken"
sed -i '/^GO_VERSION=/d' "$test_root/stage-go-missing-pin/$id_three/release.env"
repack_artifact go-missing-pin "$id_three" "$go_broken"
if run_manager install "$go_broken" >"$test_root/go-missing-pin.log" 2>&1; then
  fail 'Go profile was accepted without its version pin'
fi
for command_name in go gofmt; do
  make_artifact "$commit_three" "go-missing-$command_name" "$go_broken"
  rm "$test_root/stage-go-missing-$command_name/$id_three/tools/go/bin/$command_name"
  repack_artifact "go-missing-$command_name" "$id_three" "$go_broken"
  if run_manager install "$go_broken" >"$test_root/go-missing-$command_name.log" 2>&1; then
    fail "Go release was installed without $command_name"
  fi
done
make_artifact "$commit_three" go-wrong-version "$go_broken"
sed -i 's/^GO_VERSION=.*/GO_VERSION=9.9/' "$test_root/stage-go-wrong-version/$id_three/release.env"
repack_artifact go-wrong-version "$id_three" "$go_broken"
if run_manager install "$go_broken" >"$test_root/go-wrong-version.log" 2>&1; then
  fail 'Go release was installed with an unexpected executable version'
fi
[[ ! -e $test_home/dotfiles-releases/current ]] || fail 'failed Go release became active'

test_home=$test_root/go-old-profile-home
mkdir -p "$test_home"
old_go_artifact=$test_root/old-go-profile.tar.gz
make_artifact "$commit_one" old-go-profile "$old_go_artifact" 1.0 true false
run_manager install "$old_go_artifact" >/dev/null
run_manager install "$artifact_two" >/dev/null
[[ $("$test_home/bin/go" version) == *'fixture 2.0'* && -x $test_home/bin/gofmt ]] ||
  fail 'Go SDK commands did not follow the active release'
run_manager rollback >/dev/null
[[ ! -x $test_home/bin/go && ! -x $test_home/bin/gofmt ]] ||
  fail 'rollback to the pre-Go profile retained executable Go launchers'
[[ -x $test_home/bin/fd ]] || fail 'pre-Go rollback removed fd'

test_home=$test_root/go-connected-migration-home
mkdir -p "$test_home/bin/go-0.9/bin" "$test_home/.local/state/dotfiles/setup-tools"
for command_name in go gofmt; do
  write_fake_tool "$test_home/bin/go-0.9/bin/$command_name" 0.9
  ln -s "go-0.9/bin/$command_name" "$test_home/bin/$command_name"
done
go_content=$(tar --sort=name --mtime=@0 --owner=0 --group=0 --numeric-owner \
  -C "$test_home/bin" -cf - -- go-0.9 | sha256sum | awk '{print $1}')
printf 'complete\t%s\t%s\n' \
  aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa \
  "$go_content" >"$test_home/.local/state/dotfiles/setup-tools/go-0.9.state"
run_manager install "$artifact_two" >/dev/null
[[ $("$test_home/bin/go" version) == *'fixture 2.0'* ]] || fail 'offline release did not adopt the owned SDK'
run_manager uninstall >/dev/null
assert_link "$test_home/bin/go" go-0.9/bin/go
assert_link "$test_home/bin/gofmt" go-0.9/bin/gofmt
printf '\nmodified\n' >>"$test_home/bin/go-0.9/bin/gofmt"
if run_manager install "$artifact_two" >"$test_root/go-modified-provider.log" 2>&1; then
  fail 'offline release adopted a modified connected Go SDK'
fi
assert_link "$test_home/bin/go" go-0.9/bin/go

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

printf 'dotfiles_release: profiles passed\n'
