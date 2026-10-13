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

mkdir -p "$test_root/no-sudo" "$test_root/wrong-arch"
ln -s "$(command -v dirname)" "$test_root/no-sudo/dirname"
ln -s "$(command -v uname)" "$test_root/no-sudo/uname"
set +e
missing_sudo_output=$(PATH="$test_root/no-sudo" /bin/bash "$repo_dir/setup-system" 2>&1)
missing_sudo_status=$?
set -e
[[ $missing_sudo_status -ne 0 ]] || fail 'setup-system accepted a missing sudo command'
[[ $missing_sudo_output == *'required command is missing: sudo'* ]] ||
  fail 'setup-system did not report missing sudo'

ln -s "$(command -v dirname)" "$test_root/wrong-arch/dirname"
cat >"$test_root/wrong-arch/uname" <<'EOF'
#!/bin/sh
case $1 in
  -s) printf 'Linux\n' ;;
  -m) printf 'aarch64\n' ;;
  *) exit 1 ;;
esac
EOF
chmod 0755 "$test_root/wrong-arch/uname"
set +e
wrong_arch_output=$(PATH="$test_root/wrong-arch" /bin/bash "$repo_dir/setup-system" 2>&1)
wrong_arch_status=$?
set -e
[[ $wrong_arch_status -ne 0 ]] || fail 'setup-system accepted an unsupported architecture'
[[ $wrong_arch_output == *'only Linux x86-64 is supported'* ]] ||
  fail 'setup-system did not report the unsupported architecture'

fixture_bin=$test_root/fixture-bin
package_log=$test_root/packages.log
debian_release=$test_root/debian-os-release
amazon_release=$test_root/amazon-os-release
mkdir -p "$fixture_bin"
for command_name in awk bash cat chmod cmp dirname env find grep id install ln mktemp readlink sed timeout uname; do
  ln -s "$(command -v "$command_name")" "$fixture_bin/$command_name"
done
export TEST_DOCKER_COMMAND="$repo_dir/tests/fixtures/setup-system/docker-command"
export TEST_FIXTURE_BIN="$fixture_bin"
printf 'ID=debian\nVERSION_ID=13\n' >"$debian_release"
printf 'ID=amzn\nVERSION_ID=2023\n' >"$amazon_release"
cat >"$fixture_bin/sudo" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[[ ${1:-} == -- ]] && shift
exec "$@"
EOF
cat >"$fixture_bin/apt-get" <<'EOF'
#!/usr/bin/env bash
[[ ${TEST_PACKAGE_FAIL:-} != "apt-get:${1:-}" ]] || exit 71
printf 'apt-get' >>"$TEST_PACKAGE_LOG"
printf '\t%s' "$@" >>"$TEST_PACKAGE_LOG"
printf '\n' >>"$TEST_PACKAGE_LOG"
if [[ ${1:-} == install && " $* " == *' docker-ce '* ]]; then
  ln -s "$TEST_DOCKER_COMMAND" "$TEST_FIXTURE_BIN/docker"
fi
EOF
cat >"$fixture_bin/dnf" <<'EOF'
#!/usr/bin/env bash
[[ ${TEST_PACKAGE_FAIL:-} != "dnf:${1:-}" ]] || exit 72
printf 'dnf' >>"$TEST_PACKAGE_LOG"
printf '\t%s' "$@" >>"$TEST_PACKAGE_LOG"
printf '\n' >>"$TEST_PACKAGE_LOG"
if [[ ${1:-} == install && " $* " == *' docker '* ]]; then
  ln -s "$TEST_DOCKER_COMMAND" "$TEST_FIXTURE_BIN/docker"
fi
EOF
chmod 0755 "$fixture_bin/sudo" "$fixture_bin/apt-get" "$fixture_bin/dnf"
for command_name in curl dpkg-query gpg groupadd rpm systemctl usermod; do
  ln -s "$repo_dir/tests/fixtures/setup-system/docker-command" "$fixture_bin/$command_name"
done
export TEST_DOCKER_LOG="$test_root/docker.log"
export SETUP_SYSTEM_ETC_DIR="$test_root/etc"

if PATH="$fixture_bin" TEST_PACKAGE_LOG="$package_log" \
  "$repo_dir/setup-system" --runtime >"$test_root/retired-flag.log" 2>&1; then
  fail 'setup-system accepted the retired --runtime flag'
fi
if PATH="$fixture_bin" TEST_PACKAGE_LOG="$package_log" \
  "$repo_dir/setup-system" --offline-release extra >"$test_root/extra-argument.log" 2>&1; then
  fail 'setup-system accepted an argument after --offline-release'
fi
[[ ! -e $package_log ]] || fail 'invalid arguments reached the package manager'

# shellcheck source=../system.env
source "$repo_dir/system.env"
for command_name in "${SYSTEM_RUNTIME_COMMANDS[@]}" "${SYSTEM_SETUP_COMMANDS[@]}"; do
  [[ -e $fixture_bin/$command_name ]] || ln -s /bin/true "$fixture_bin/$command_name"
done

for _ in 1 2; do
  PATH="$fixture_bin" TEST_PACKAGE_LOG="$package_log" \
    SETUP_SYSTEM_OS_RELEASE_FILE="$debian_release" \
    "$repo_dir/setup-system" --offline-release >/dev/null
done
[[ $(grep -c $'^apt-get\tupdate$' "$package_log") -eq 2 ]] ||
  fail 'offline-release setup did not repeat the package index refresh'
[[ $(grep -c 'libevent-core-2.1-7t64' "$package_log") -eq 2 ]] ||
  fail 'offline-release setup omitted libevent runtime'
[[ $(grep -c 'libncursesw6' "$package_log") -eq 2 ]] ||
  fail 'offline-release setup omitted htop ncurses runtime'
[[ $(grep -c 'diffutils' "$package_log") -eq 2 ]] ||
  fail 'offline-release setup omitted cmp runtime'
if grep $'^apt-get\tinstall' "$package_log" | grep -Eq $'\t(python3|tmux|build-essential)(\t|$)'; then
  fail 'offline-release setup included a connected-only package'
fi
[[ ! -e $TEST_DOCKER_LOG && ! -e $SETUP_SYSTEM_ETC_DIR ]] ||
  fail 'offline-release setup configured Docker'

: >"$package_log"
for _ in 1 2; do
  PATH="$fixture_bin" TEST_PACKAGE_LOG="$package_log" \
    SETUP_SYSTEM_OS_RELEASE_FILE="$debian_release" \
    "$repo_dir/setup-system" >/dev/null
done
[[ $(grep -c $'^apt-get\tupdate$' "$package_log") -eq 3 ]] ||
  fail 'connected setup did not refresh OS indexes twice and Docker only on the first run'
grep $'^apt-get\tinstall' "$package_log" | grep -F $'\tbuild-essential\t' >/dev/null ||
  fail 'connected setup omitted build prerequisites'
grep $'^apt-get\tinstall' "$package_log" | grep -F $'\tpython3\t' >/dev/null ||
  fail 'connected setup omitted its Python provider'
if grep $'^apt-get\tinstall' "$package_log" | grep -Eq $'\t(htop|tmux)(\t|$)'; then
  fail 'connected setup retained htop or tmux as an OS package'
fi
[[ $(grep -c $'\tdocker-ce\t' "$package_log") -eq 1 ]] ||
  fail 'connected Debian setup did not install Docker CE exactly once'
grep -F $'\tdocker-compose-plugin' "$package_log" >/dev/null ||
  fail 'connected Debian setup omitted Docker Compose'
[[ $(grep -c $'^usermod\t--append\t--groups\tdocker\t--\t'"$(id -un)"'$' "$TEST_DOCKER_LOG") -eq 1 ]] ||
  fail 'connected setup did not append Docker membership for the invoking user'
[[ $(grep -c $'^systemctl\tenable\t--now\tcontainerd.service\tdocker.service$' "$TEST_DOCKER_LOG") -eq 1 ]] ||
  fail 'connected setup did not enable and start the container services'
[[ $(grep -c $'^docker\t--host\tunix:///var/run/docker.sock\tinfo$' "$TEST_DOCKER_LOG") -eq 1 ]] ||
  fail 'connected setup did not verify the local Docker daemon'
docker_source=$SETUP_SYSTEM_ETC_DIR/apt/sources.list.d/docker.sources
docker_key=$SETUP_SYSTEM_ETC_DIR/apt/keyrings/docker.asc
grep -Fx 'URIs: https://download.docker.com/linux/debian' "$docker_source" >/dev/null ||
  fail 'Debian setup selected the wrong Docker repository'
grep -Fx 'Suites: trixie' "$docker_source" >/dev/null ||
  fail 'Debian setup selected the wrong Docker suite'
grep -Fx "Signed-By: $docker_key" "$docker_source" >/dev/null ||
  fail 'Docker repository did not scope its signing key'
[[ $(stat -c %a "$docker_key") == 644 && $(stat -c %a "$docker_source") == 644 ]] ||
  fail 'Docker repository files are not readable by apt'

for ubuntu_version in 24.04 26.04; do
  unlink "$fixture_bin/docker"
  ubuntu_release=$test_root/ubuntu-$ubuntu_version-os-release
  printf 'ID=ubuntu\nVERSION_ID=%s\n' "$ubuntu_version" >"$ubuntu_release"
  case $ubuntu_version in
    24.04) ubuntu_suite=noble ;;
    26.04) ubuntu_suite=resolute ;;
  esac
  PATH="$fixture_bin" TEST_PACKAGE_LOG="$package_log" \
    SETUP_SYSTEM_OS_RELEASE_FILE="$ubuntu_release" \
    SETUP_SYSTEM_ETC_DIR="$test_root/ubuntu-$ubuntu_version-etc" \
    "$repo_dir/setup-system" >/dev/null
  ubuntu_source=$test_root/ubuntu-$ubuntu_version-etc/apt/sources.list.d/docker.sources
  grep -Fx 'URIs: https://download.docker.com/linux/ubuntu' "$ubuntu_source" >/dev/null ||
    fail "Ubuntu $ubuntu_version setup selected the wrong Docker repository"
  grep -Fx "Suites: $ubuntu_suite" "$ubuntu_source" >/dev/null ||
    fail "Ubuntu $ubuntu_version setup selected the wrong Docker suite"
done

: >"$package_log"
unlink "$fixture_bin/docker"
for _ in 1 2; do
  PATH="$fixture_bin" TEST_PACKAGE_LOG="$package_log" TEST_RPM_MINIMAL=1 \
    SETUP_SYSTEM_OS_RELEASE_FILE="$amazon_release" \
    SETUP_SYSTEM_ETC_DIR="$test_root/amazon-etc" \
    "$repo_dir/setup-system" >/dev/null
done
[[ $(grep -c $'^dnf\tswap\t-y\tgnupg2-minimal\tgnupg2$' "$package_log") -eq 2 ]] ||
  fail 'Amazon connected setup did not preserve the GnuPG swap'
if grep $'^dnf\tinstall' "$package_log" | grep -Eq $'\t(cargo|clang-devel)(\t|$)'; then
  fail 'Amazon connected setup inherited builder-only packages'
fi
grep $'^dnf\tinstall' "$package_log" | grep -F $'\t--allowerasing\t' >/dev/null ||
  fail 'Amazon setup omitted --allowerasing'
[[ $(grep -c $'^dnf\tinstall\t-y\tdocker$' "$package_log") -eq 1 ]] ||
  fail 'Amazon setup did not install the distribution Docker package exactly once'
[[ ! -e $test_root/amazon-etc ]] || fail 'Amazon setup added an unsupported Docker CE repository'

: >"$package_log"
PATH="$fixture_bin" TEST_PACKAGE_LOG="$package_log" TEST_RPM_MINIMAL=0 \
  SETUP_SYSTEM_OS_RELEASE_FILE="$amazon_release" \
  "$repo_dir/setup-system" >/dev/null
grep -Fx $'dnf\tinstall\t-y\tgnupg2' "$package_log" >/dev/null ||
  fail 'Amazon connected setup did not install full GnuPG when minimal was absent'

# shellcheck source=../scripts/setup-lib
source "$repo_dir/scripts/setup-lib"
# shellcheck source=../system.env
source "$repo_dir/system.env"
system_package_list amzn:2023 build
printf '%s\n' "${SETUP_SYSTEM_PACKAGES[@]}" | grep -Fx cargo >/dev/null ||
  fail 'Amazon build omitted cargo'
printf '%s\n' "${SETUP_SYSTEM_PACKAGES[@]}" | grep -Fx clang-devel >/dev/null ||
  fail 'Amazon build omitted clang-devel'
system_package_list amzn:2023 setup
if printf '%s\n' "${SETUP_SYSTEM_PACKAGES[@]}" | grep -Eq '^(cargo|clang-devel)$'; then
  fail 'Amazon connected role contains a builder-only package'
fi
[[ $(printf '%s\n' "${SETUP_SYSTEM_PACKAGES[@]}" | sort -u | wc -l) -eq ${#SETUP_SYSTEM_PACKAGES[@]} ]] ||
  fail 'Amazon connected package list contains duplicates'

config_repo=$test_root/config-repo
mkdir -p "$config_repo/scripts"
cp "$repo_dir/setup-system" "$config_repo/setup-system"
cp "$repo_dir/scripts/setup-lib" "$config_repo/scripts/setup-lib"
cp "$repo_dir/system.env" "$config_repo/system.env"
printf 'SYSTEM_RUNTIME_PACKAGES+=(fixture-package)\n' >>"$config_repo/system.env"
PATH="$fixture_bin" TEST_PACKAGE_LOG="$package_log" \
  SETUP_SYSTEM_OS_RELEASE_FILE="$debian_release" \
  "$config_repo/setup-system" --offline-release >/dev/null
grep $'^apt-get\tinstall' "$package_log" | grep -F $'\tfixture-package' >/dev/null ||
  fail 'setup-system ignored the configured package list'

printf 'SYSTEM_RUNTIME_COMMANDS+=(dotfiles-fixture-missing-command)\n' >>"$config_repo/system.env"
set +e
verification_output=$(PATH="$fixture_bin" TEST_PACKAGE_LOG="$package_log" \
  SETUP_SYSTEM_OS_RELEASE_FILE="$debian_release" \
  "$config_repo/setup-system" --offline-release 2>&1)
verification_status=$?
set -e
[[ $verification_status -ne 0 && $verification_output == \
  *'setup-system: package installation did not provide dotfiles-fixture-missing-command'* ]] ||
  fail 'setup-system ignored a configured installation check'

set +e
PATH="$fixture_bin" TEST_PACKAGE_LOG="$package_log" \
  TEST_PACKAGE_FAIL=apt-get:update SETUP_SYSTEM_OS_RELEASE_FILE="$debian_release" \
  "$repo_dir/setup-system" --offline-release >/dev/null 2>&1
apt_failure=$?
PATH="$fixture_bin" TEST_PACKAGE_LOG="$package_log" TEST_RPM_MINIMAL=0 \
  TEST_PACKAGE_FAIL=dnf:install SETUP_SYSTEM_OS_RELEASE_FILE="$amazon_release" \
  "$repo_dir/setup-system" --offline-release >/dev/null 2>&1
dnf_failure=$?
set -e
[[ $apt_failure -eq 71 ]] || fail 'apt failure was hidden'
[[ $dnf_failure -eq 72 ]] || fail 'dnf failure was hidden'

unlink "$fixture_bin/docker"
for provider in docker.io containerd docker-ce; do
  : >"$package_log"
  : >"$TEST_DOCKER_LOG"
  conflict_output=$(PATH="$fixture_bin" TEST_PACKAGE_LOG="$package_log" \
    TEST_DOCKER_CONFLICT="$provider" SETUP_SYSTEM_OS_RELEASE_FILE="$debian_release" \
    "$repo_dir/setup-system" 2>&1)
  [[ $conflict_output == *"skipping Docker setup (package $provider already present)"* &&
    $conflict_output == *'host setup packages ready'* ]] ||
    fail 'existing runtime blocked the rest of setup'
  grep -F $'\tbuild-essential\t' "$package_log" >/dev/null || fail 'skip omitted ordinary setup packages'
  if grep -Eq '^(curl|gpg|groupadd|usermod|systemctl|docker)' "$TEST_DOCKER_LOG"; then
    fail 'skip modified or probed the existing Docker installation'
  fi
  if grep -F $'\tdocker-ce\t' "$package_log" >/dev/null; then
    fail 'skip installed a new Docker provider'
  fi
done

existing_output=$(PATH="$fixture_bin" TEST_PACKAGE_LOG="$package_log" \
  TEST_DOCKER_CONFLICT=docker-ce SETUP_SYSTEM_OS_RELEASE_FILE="$amazon_release" \
  "$repo_dir/setup-system" 2>&1)
[[ $existing_output == *'skipping Docker setup (package docker-ce already present)'* &&
  $existing_output == *'host setup packages ready'* ]] || fail 'Amazon setup blocked an existing Docker provider'

ln -s "$TEST_DOCKER_COMMAND" "$fixture_bin/docker"
: >"$TEST_DOCKER_LOG"
existing_output=$(PATH="$fixture_bin" TEST_PACKAGE_LOG="$package_log" \
  SETUP_SYSTEM_OS_RELEASE_FILE="$debian_release" "$repo_dir/setup-system" 2>&1)
[[ $existing_output == *'skipping Docker setup (command '* &&
  $existing_output == *'host setup packages ready'* ]] || fail 'unpackaged Docker blocked setup'
if grep -Eq '^(curl|gpg|groupadd|usermod|systemctl|docker)' "$TEST_DOCKER_LOG"; then
  fail 'skip modified or probed the unpackaged Docker installation'
fi

cp "$docker_key" "$test_root/original-key"
cp "$docker_source" "$test_root/original-source"
for failed_command in curl gpg systemctl docker; do
  [[ ! -L $fixture_bin/docker ]] || unlink "$fixture_bin/docker"
  : >"$TEST_DOCKER_LOG"
  set +e
  failure_output=$(PATH="$fixture_bin" TEST_PACKAGE_LOG="$package_log" \
    TEST_DOCKER_FAIL="$failed_command" SETUP_SYSTEM_OS_RELEASE_FILE="$debian_release" \
    "$repo_dir/setup-system" 2>&1)
  failure_status=$?
  set -e
  case $failed_command in
    curl) expected_status=75 ;;
    gpg) expected_status=76 ;;
    systemctl) expected_status=73 ;;
    docker) expected_status=74 ;;
  esac
  [[ $failure_status -eq $expected_status && $failure_output != *'host setup packages ready'* ]] ||
    fail "Docker $failed_command failure was hidden"
  cmp -s "$test_root/original-key" "$docker_key" || fail 'Docker failure corrupted the signing key'
  cmp -s "$test_root/original-source" "$docker_source" || fail 'Docker failure changed the repository'
done

printf '# foreign Docker repository\n' >"$docker_source"
unlink "$fixture_bin/docker"
set +e
foreign_output=$(PATH="$fixture_bin" TEST_PACKAGE_LOG="$package_log" \
  SETUP_SYSTEM_OS_RELEASE_FILE="$debian_release" "$repo_dir/setup-system" 2>&1)
foreign_status=$?
set -e
[[ $foreign_status -ne 0 && $foreign_output == *'existing Docker repository differs'* ]] ||
  fail 'connected setup accepted an unrelated repository configuration'
[[ $(<"$docker_source") == '# foreign Docker repository' ]] ||
  fail 'connected setup overwrote a foreign repository'

for role in runtime build; do
  system_package_list debian:13 "$role"
  if printf '%s\n' "${SETUP_SYSTEM_PACKAGES[@]}" | grep -Eq '^(docker.*|containerd.*|systemd)$'; then
    fail "Docker host packages leaked into the $role profile"
  fi
done

printf 'Setup system tests passed\n'
