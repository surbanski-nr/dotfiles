#!/usr/bin/env bash

set -euo pipefail

repo_dir=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
test_root=$(mktemp -d)
online_setup_script=$repo_dir/setup-system
release_manager=$test_root/download/dotfiles-release

cleanup() {
  find "$test_root" -depth -delete
}
trap cleanup EXIT

bash "$repo_dir/scripts/build-standalone-script" "$repo_dir" "$release_manager"
(cd "$test_root/download" && sha256sum --check --strict dotfiles-release.sha256 >/dev/null)

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

mkdir -p "$test_root/no-sudo" "$test_root/wrong-arch"
ln -s "$(command -v dirname)" "$test_root/no-sudo/dirname"
ln -s "$(command -v uname)" "$test_root/no-sudo/uname"
set +e
missing_sudo_output=$(PATH="$test_root/no-sudo" /bin/bash "$online_setup_script" 2>&1)
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
wrong_arch_output=$(PATH="$test_root/wrong-arch" /bin/bash "$online_setup_script" 2>&1)
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
for command_name in awk bash cat chmod cmp dirname env find grep id install ln mkdir mktemp mv readlink sed timeout uname; do
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
if [[ ${TEST_PACKAGE_NETWORK_FAIL:-} == "apt-get:${1:-}" ]]; then
  printf 'Temporary failure resolving fixture-repository.invalid\n' >&2
  exit 100
fi
if [[ ${TEST_PACKAGE_EMPTY_CACHE:-0} == 1 ]]; then
  if [[ ${1:-} == update ]]; then
    printf 'Temporary failure resolving fixture-repository.invalid\n' >&2
  else
    printf 'E: Unable to locate package jq\n' >&2
  fi
  exit 100
fi
if [[ ${TEST_PACKAGE_TIMEOUT:-} == "apt-get:${1:-}" ]]; then
  exit 124
fi
if [[ ${TEST_PACKAGE_BAD_SIGNATURE:-0} == 1 ]]; then
  printf 'Temporary failure resolving other-repository.invalid\nNO_PUBKEY fixture\n' >&2
  exit 100
fi
if [[ ${1:-} == install && " $* " == *' docker-ce '* ]]; then
  ln -s "$TEST_DOCKER_COMMAND" "$TEST_FIXTURE_BIN/docker"
fi
if [[ ${1:-} == install && " $* " == *' gnupg '* && " $* " == *' systemd '* ]]; then
  for prerequisite in curl gpg systemctl; do
    [[ -e $TEST_FIXTURE_BIN/$prerequisite ]] || ln -s "$TEST_DOCKER_COMMAND" "$TEST_FIXTURE_BIN/$prerequisite"
  done
fi
EOF
cat >"$fixture_bin/dnf" <<'EOF'
#!/usr/bin/env bash
[[ ${TEST_PACKAGE_FAIL:-} != "dnf:${1:-}" ]] || exit 72
printf 'dnf' >>"$TEST_PACKAGE_LOG"
printf '\t%s' "$@" >>"$TEST_PACKAGE_LOG"
printf '\n' >>"$TEST_PACKAGE_LOG"
if [[ ${TEST_PACKAGE_NETWORK_FAIL:-} == "dnf:${1:-}" ]]; then
  printf 'Curl error (6): Could not resolve host: fixture-repository.invalid\n' >&2
  exit 1
fi
if [[ ${TEST_PACKAGE_TIMEOUT:-} == "dnf:${1:-}" ]]; then
  exit 124
fi
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
  "$online_setup_script" extra >"$test_root/extra-online-argument.log" 2>&1; then
  fail 'connected setup accepted an unexpected argument'
fi
if PATH="$fixture_bin" TEST_PACKAGE_LOG="$package_log" \
  /bin/bash "$release_manager" setup extra >"$test_root/extra-argument.log" 2>&1; then
  fail 'release setup accepted an unexpected argument'
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
    /bin/bash "$release_manager" setup >/dev/null
done
[[ $(grep -c $'^apt-get\tupdate\t--error-on=any$' "$package_log") -eq 3 ]] ||
  fail 'release setup did not repeat OS index refreshes and refresh Docker only once'
[[ $(grep -c 'libevent-core-2.1-7t64' "$package_log") -eq 2 ]] ||
  fail 'release setup omitted libevent runtime'
[[ $(grep -c 'libncursesw6' "$package_log") -eq 2 ]] ||
  fail 'release setup omitted htop ncurses runtime'
[[ $(grep -c 'diffutils' "$package_log") -eq 2 ]] ||
  fail 'release setup omitted cmp runtime'
[[ $(grep -c $'\tjq\t' "$package_log") -eq 2 ]] || fail 'release setup omitted jq'
mv "$fixture_bin/jq" "$fixture_bin/jq.saved"
if PATH="$fixture_bin" TEST_PACKAGE_LOG="$package_log" \
  SETUP_SYSTEM_OS_RELEASE_FILE="$debian_release" /bin/bash "$release_manager" setup \
  >"$test_root/jq-missing.log" 2>&1; then
  fail 'offline runtime accepted a missing jq command'
fi
grep -F 'package installation did not provide jq' "$test_root/jq-missing.log" >/dev/null || fail 'missing jq was not reported'
mv "$fixture_bin/jq.saved" "$fixture_bin/jq"
if grep $'^apt-get\tinstall' "$package_log" | grep -Eq $'\t(python3|tmux|build-essential)(\t|$)'; then
  fail 'release setup included a connected-only package'
fi
[[ $(grep -c $'\tdocker-ce\t' "$package_log") -eq 1 ]] ||
  fail 'release setup did not install Docker CE exactly once'
grep -F $'\tdocker-compose-plugin' "$package_log" >/dev/null ||
  fail 'release setup omitted Docker Compose'

: >"$package_log"
for _ in 1 2; do
  PATH="$fixture_bin" TEST_PACKAGE_LOG="$package_log" \
    SETUP_SYSTEM_OS_RELEASE_FILE="$debian_release" \
    "$online_setup_script" >/dev/null
done
[[ $(grep -c $'^apt-get\tupdate\t--error-on=any$' "$package_log") -eq 2 ]] ||
  fail 'connected setup did not refresh OS indexes twice'
grep $'^apt-get\tinstall' "$package_log" | grep -F $'\tbuild-essential\t' >/dev/null ||
  fail 'connected setup omitted build prerequisites'
grep $'^apt-get\tinstall' "$package_log" | grep -F $'\tpython3\t' >/dev/null ||
  fail 'connected setup omitted its Python provider'
for package in bsdutils procps; do
  grep $'^apt-get\tinstall' "$package_log" | grep -F $'\t'"$package"$'\t' >/dev/null ||
    fail "connected setup omitted the validation prerequisite $package"
done
if grep $'^apt-get\tinstall' "$package_log" | grep -Eq $'\t(htop|tmux)(\t|$)'; then
  fail 'connected setup retained htop or tmux as an OS package'
fi
if grep -F $'\tdocker-ce\t' "$package_log" >/dev/null; then
  fail 'connected Debian setup replaced an existing Docker installation'
fi
[[ $(grep -c $'^usermod\t--append\t--groups\tdocker\t--\t'"$(id -un)"'$' "$TEST_DOCKER_LOG") -eq 1 ]] ||
  fail 'host setup did not append Docker membership for the invoking user'
[[ $(grep -c $'^systemctl\tenable\t--now\tcontainerd.service\tdocker.service$' "$TEST_DOCKER_LOG") -eq 1 ]] ||
  fail 'host setup did not enable and start the container services'
[[ $(grep -c $'^docker\t--host\tunix:///var/run/docker.sock\tinfo$' "$TEST_DOCKER_LOG") -eq 1 ]] ||
  fail 'host setup did not verify the local Docker daemon'
for missing_command in pkill ps script; do
  mv "$fixture_bin/$missing_command" "$fixture_bin/$missing_command.saved"
  if missing_output=$(PATH="$fixture_bin" TEST_PACKAGE_LOG="$package_log" \
    SETUP_SYSTEM_OS_RELEASE_FILE="$debian_release" "$online_setup_script" 2>&1); then
    fail "connected setup accepted a missing validation prerequisite $missing_command"
  fi
  [[ $missing_output == *"package installation did not provide $missing_command"* ]] ||
    fail "connected setup did not report missing $missing_command"
  warning_output=$(PATH="$fixture_bin" TEST_PACKAGE_LOG="$package_log" \
    TEST_PACKAGE_NETWORK_FAIL=apt-get:install SETUP_SYSTEM_OS_RELEASE_FILE="$debian_release" \
    "$online_setup_script" 2>&1) || fail 'missing validation prerequisite after network failure stopped setup'
  [[ $warning_output == *"warning: package installation did not provide $missing_command"* &&
    $warning_output == *'completed with '* && $warning_output != *'host setup packages ready'* ]] ||
    fail "setup hid missing $missing_command after a network failure"
  PATH="$fixture_bin" TEST_PACKAGE_LOG="$package_log" \
    SETUP_SYSTEM_OS_RELEASE_FILE="$debian_release" /bin/bash "$release_manager" setup >/dev/null
  mv "$fixture_bin/$missing_command.saved" "$fixture_bin/$missing_command"
done
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
  : >"$package_log"
  PATH="$fixture_bin" TEST_PACKAGE_LOG="$package_log" \
    SETUP_SYSTEM_OS_RELEASE_FILE="$ubuntu_release" \
    SETUP_SYSTEM_ETC_DIR="$test_root/ubuntu-$ubuntu_version-etc" \
    /bin/bash "$release_manager" setup >/dev/null
  grep -F $'\tjq\t' "$package_log" >/dev/null || fail "Ubuntu $ubuntu_version runtime omitted jq"
  PATH="$fixture_bin" TEST_PACKAGE_LOG="$package_log" \
    SETUP_SYSTEM_OS_RELEASE_FILE="$ubuntu_release" \
    SETUP_SYSTEM_ETC_DIR="$test_root/ubuntu-$ubuntu_version-etc" \
    "$online_setup_script" >/dev/null
  ubuntu_source=$test_root/ubuntu-$ubuntu_version-etc/apt/sources.list.d/docker.sources
  grep -Fx 'URIs: https://download.docker.com/linux/ubuntu' "$ubuntu_source" >/dev/null ||
    fail "Ubuntu $ubuntu_version setup selected the wrong Docker repository"
  grep -Fx "Suites: $ubuntu_suite" "$ubuntu_source" >/dev/null ||
    fail "Ubuntu $ubuntu_version setup selected the wrong Docker suite"
done

: >"$package_log"
unlink "$fixture_bin/docker"
PATH="$fixture_bin" TEST_PACKAGE_LOG="$package_log" \
  SETUP_SYSTEM_OS_RELEASE_FILE="$amazon_release" /bin/bash "$release_manager" setup >/dev/null
grep -F $'\tjq\t' "$package_log" >/dev/null || fail 'Amazon runtime omitted jq'
[[ $(grep -c $'^dnf\tinstall\t-y\tdocker$' "$package_log") -eq 1 ]] ||
  fail 'Amazon release setup did not install the distribution Docker package'
: >"$package_log"
for _ in 1 2; do
  PATH="$fixture_bin" TEST_PACKAGE_LOG="$package_log" TEST_RPM_MINIMAL=1 \
    SETUP_SYSTEM_OS_RELEASE_FILE="$amazon_release" \
    SETUP_SYSTEM_ETC_DIR="$test_root/amazon-etc" \
    "$online_setup_script" >/dev/null
done
[[ $(grep -c $'^dnf\tswap\t-y\tgnupg2-minimal\tgnupg2$' "$package_log") -eq 2 ]] ||
  fail 'Amazon connected setup did not preserve the GnuPG swap'
if grep $'^dnf\tinstall' "$package_log" | grep -Eq $'\t(cargo|clang-devel)(\t|$)'; then
  fail 'Amazon connected setup inherited builder-only packages'
fi
grep $'^dnf\tinstall' "$package_log" | grep -F $'\t--allowerasing\t' >/dev/null ||
  fail 'Amazon setup omitted --allowerasing'
grep $'^dnf\tinstall' "$package_log" | grep -F $'\tprocps-ng\t' >/dev/null ||
  fail 'Amazon connected setup omitted its process tools'
if grep -Fx $'dnf\tinstall\t-y\tdocker' "$package_log" >/dev/null; then
  fail 'Amazon setup replaced its existing Docker installation'
fi
[[ ! -e $test_root/amazon-etc ]] || fail 'Amazon setup added an unsupported Docker CE repository'

: >"$package_log"
PATH="$fixture_bin" TEST_PACKAGE_LOG="$package_log" TEST_RPM_MINIMAL=0 \
  SETUP_SYSTEM_OS_RELEASE_FILE="$amazon_release" \
  "$online_setup_script" >/dev/null
grep -Fx $'dnf\tinstall\t-y\tgnupg2' "$package_log" >/dev/null ||
  fail 'Amazon connected setup did not install full GnuPG when minimal was absent'

# shellcheck source=../scripts/setup-system-lib
source "$repo_dir/scripts/setup-system-lib"
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
cp "$repo_dir/scripts/setup-system-lib" "$config_repo/scripts/setup-system-lib"
cp "$repo_dir/scripts/dotfiles-release" "$config_repo/scripts/dotfiles-release"
cp "$repo_dir/tools.env" "$config_repo/tools.env"
cp "$repo_dir/system.env" "$config_repo/system.env"
printf 'SYSTEM_RUNTIME_PACKAGES+=(fixture-package)\n' >>"$config_repo/system.env"
bash "$repo_dir/scripts/build-standalone-script" "$config_repo" "$test_root/config-manager"
PATH="$fixture_bin" TEST_PACKAGE_LOG="$package_log" \
  SETUP_SYSTEM_OS_RELEASE_FILE="$debian_release" \
  /bin/bash "$test_root/config-manager" setup >/dev/null
grep $'^apt-get\tinstall' "$package_log" | grep -F $'\tfixture-package' >/dev/null ||
  fail 'release setup ignored the configured package list'

printf 'SYSTEM_RUNTIME_COMMANDS+=(dotfiles-fixture-missing-command)\n' >>"$config_repo/system.env"
bash "$repo_dir/scripts/build-standalone-script" "$config_repo" "$test_root/config-manager"
set +e
verification_output=$(PATH="$fixture_bin" TEST_PACKAGE_LOG="$package_log" \
  SETUP_SYSTEM_OS_RELEASE_FILE="$debian_release" \
  /bin/bash "$test_root/config-manager" setup 2>&1)
verification_status=$?
set -e
[[ $verification_status -ne 0 && $verification_output == \
  *'package installation did not provide dotfiles-fixture-missing-command'* ]] ||
  fail 'release setup ignored a configured installation check'

set +e
PATH="$fixture_bin" TEST_PACKAGE_LOG="$package_log" \
  TEST_PACKAGE_FAIL=apt-get:update SETUP_SYSTEM_OS_RELEASE_FILE="$debian_release" \
  /bin/bash "$release_manager" setup >/dev/null 2>&1
apt_failure=$?
PATH="$fixture_bin" TEST_PACKAGE_LOG="$package_log" TEST_RPM_MINIMAL=0 \
  TEST_PACKAGE_FAIL=dnf:install SETUP_SYSTEM_OS_RELEASE_FILE="$amazon_release" \
  /bin/bash "$release_manager" setup >/dev/null 2>&1
dnf_failure=$?
set -e
[[ $apt_failure -eq 71 ]] || fail 'apt failure was hidden'
[[ $dnf_failure -eq 72 ]] || fail 'dnf failure was hidden'

for failed_operation in apt-get:update apt-get:install dnf:install; do
  : >"$package_log"
  case $failed_operation in
    apt-get:*) target_release=$debian_release ;;
    dnf:*) target_release=$amazon_release ;;
  esac
  warning_output=$(PATH="$fixture_bin" TEST_PACKAGE_LOG="$package_log" \
    TEST_PACKAGE_NETWORK_FAIL="$failed_operation" SETUP_SYSTEM_OS_RELEASE_FILE="$target_release" \
    /bin/bash "$release_manager" setup 2>&1) || fail 'network failure stopped setup'
  [[ $warning_output == *'dotfiles-release setup: warning: OS package installation failed'* &&
    $warning_output == *'completed with '* && $warning_output != *'prerequisites ready'* &&
    $warning_output == *'skipping Docker setup'* ]] || fail 'network failure was hidden or prevented continuation'
  if [[ $failed_operation == apt-get:update ]]; then
    grep -F $'apt-get\tinstall\t' "$package_log" >/dev/null ||
      fail 'an unavailable package index prevented trying cached package installation'
  fi
done
warning_output=$(PATH="$fixture_bin" TEST_PACKAGE_LOG="$package_log" \
  TEST_PACKAGE_EMPTY_CACHE=1 SETUP_SYSTEM_OS_RELEASE_FILE="$debian_release" \
  /bin/bash "$release_manager" setup 2>&1) || fail 'unavailable repository with an empty package cache stopped setup'
[[ $warning_output == *'warning: OS package installation failed'* &&
  $warning_output == *'Unable to locate package jq'* && $warning_output == *'completed with '* &&
  $warning_output == *'skipping Docker setup'* ]] || fail 'an empty package cache after network failure was hidden'
warning_output=$(PATH="$fixture_bin" TEST_PACKAGE_LOG="$package_log" \
  TEST_PACKAGE_TIMEOUT=apt-get:install SETUP_SYSTEM_OS_RELEASE_FILE="$debian_release" \
  /bin/bash "$release_manager" setup 2>&1) || fail 'package installation timeout stopped setup'
[[ $warning_output == *'warning: OS package installation failed (exit 124)'* &&
  $warning_output == *'completed with '* && $warning_output != *'prerequisites ready'* ]] ||
  fail 'package installation timeout was hidden'

mv "$fixture_bin/jq" "$fixture_bin/jq.saved"
warning_output=$(PATH="$fixture_bin" TEST_PACKAGE_LOG="$package_log" \
  TEST_PACKAGE_NETWORK_FAIL=apt-get:install SETUP_SYSTEM_OS_RELEASE_FILE="$debian_release" \
  /bin/bash "$release_manager" setup 2>&1) || fail 'missing prerequisite after network failure stopped setup'
[[ $warning_output == *'warning: package installation did not provide jq'* &&
  $warning_output == *'host preparation may be incomplete'* ]] || fail 'network failure hid a missing prerequisite'
mv "$fixture_bin/jq.saved" "$fixture_bin/jq"
set +e
signature_output=$(PATH="$fixture_bin" TEST_PACKAGE_LOG="$package_log" \
  TEST_PACKAGE_BAD_SIGNATURE=1 SETUP_SYSTEM_OS_RELEASE_FILE="$debian_release" \
  /bin/bash "$release_manager" setup 2>&1)
signature_status=$?
set -e
[[ $signature_status -eq 100 && $signature_output != *'completed with '* &&
  $signature_output != *'skipping Docker setup'* ]] || fail 'a network warning hid an invalid repository signature'

unlink "$fixture_bin/docker"
for provider in docker.io containerd docker-ce; do
  : >"$package_log"
  : >"$TEST_DOCKER_LOG"
  conflict_output=$(PATH="$fixture_bin" TEST_PACKAGE_LOG="$package_log" \
    TEST_DOCKER_CONFLICT="$provider" SETUP_SYSTEM_OS_RELEASE_FILE="$debian_release" \
    "$online_setup_script" 2>&1)
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
  "$online_setup_script" 2>&1)
[[ $existing_output == *'skipping Docker setup (package docker-ce already present)'* &&
  $existing_output == *'host setup packages ready'* ]] || fail 'Amazon setup blocked an existing Docker provider'

ln -s "$TEST_DOCKER_COMMAND" "$fixture_bin/docker"
: >"$TEST_DOCKER_LOG"
existing_output=$(PATH="$fixture_bin" TEST_PACKAGE_LOG="$package_log" \
  SETUP_SYSTEM_OS_RELEASE_FILE="$debian_release" "$online_setup_script" 2>&1)
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
    "$online_setup_script" 2>&1)
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

for missing_command in curl gpg systemctl; do
  [[ ! -L $fixture_bin/docker ]] || unlink "$fixture_bin/docker"
  mv "$fixture_bin/$missing_command" "$fixture_bin/$missing_command.saved"
  : >"$package_log"
  PATH="$fixture_bin" TEST_PACKAGE_LOG="$package_log" \
    SETUP_SYSTEM_OS_RELEASE_FILE="$debian_release" /bin/bash "$release_manager" setup >/dev/null
  grep -Fx $'apt-get\tinstall\t-y\tcurl\tgnupg\tsystemd' "$package_log" >/dev/null ||
    fail "minimal host missing $missing_command did not get Docker prerequisites"
  [[ -L $fixture_bin/docker ]] || fail 'minimal host did not get Docker'
  unlink "$fixture_bin/$missing_command"
  mv "$fixture_bin/$missing_command.saved" "$fixture_bin/$missing_command"
done

for failed_command in curl systemctl docker; do
  [[ ! -L $fixture_bin/docker ]] || unlink "$fixture_bin/docker"
  : >"$TEST_DOCKER_LOG"
  warning_output=$(PATH="$fixture_bin" TEST_PACKAGE_LOG="$package_log" \
    TEST_DOCKER_TIMEOUT="$failed_command" SETUP_SYSTEM_OS_RELEASE_FILE="$debian_release" \
    /bin/bash "$release_manager" setup 2>&1) || fail "Docker $failed_command timeout stopped setup"
  [[ $warning_output == *'warning: Docker '* && $warning_output == *'exit 124'* &&
    $warning_output == *'completed with '* && $warning_output != *'prerequisites ready'* ]] ||
    fail "Docker $failed_command timeout was hidden"
  if [[ $failed_command == curl ]] && grep -q '^systemctl' "$TEST_DOCKER_LOG"; then
    fail 'Docker services were touched after signing key download timed out'
  fi
done
[[ ! -L $fixture_bin/docker ]] || unlink "$fixture_bin/docker"
: >"$package_log"
warning_output=$(PATH="$fixture_bin" TEST_PACKAGE_LOG="$package_log" \
  TEST_DOCKER_NETWORK_FAIL=1 SETUP_SYSTEM_OS_RELEASE_FILE="$debian_release" \
  SETUP_SYSTEM_ETC_DIR="$test_root/unreachable-docker-etc" \
  /bin/bash "$release_manager" setup 2>&1) || fail 'unreachable Docker repository stopped setup'
[[ $warning_output == *'warning: Docker signing key download failed (exit 6)'* &&
  $warning_output == *'completed with '* && ! -e $test_root/unreachable-docker-etc ]] ||
  fail 'failed key download published an incomplete or unsafe Docker repository'
if grep -F $'\tdocker-ce\t' "$package_log" >/dev/null; then
  fail 'Docker was installed without a verified signing key'
fi

for target_release in "$debian_release" "$amazon_release"; do
  : >"$TEST_DOCKER_LOG"
  case $target_release in
    "$debian_release") failed_operation=apt-get:install ;;
    *) failed_operation=dnf:install ;;
  esac
  warning_output=$(PATH="$fixture_bin" TEST_PACKAGE_LOG="$package_log" \
    TEST_PACKAGE_NETWORK_FAIL="$failed_operation" SETUP_SYSTEM_OS_RELEASE_FILE="$target_release" \
    /bin/bash "$release_manager" setup 2>&1) || fail 'Docker package network failure stopped setup'
  [[ $warning_output == *'warning: Docker package installation failed'* &&
    $warning_output == *'completed with '* && $warning_output != *'prerequisites ready'* ]] ||
    fail 'Docker package network failure was hidden'
  if grep -Eq '^(groupadd|usermod|systemctl|docker)' "$TEST_DOCKER_LOG"; then
    fail 'failed Docker package installation changed user groups or services'
  fi
done

printf '# foreign Docker repository\n' >"$docker_source"
[[ ! -L $fixture_bin/docker ]] || unlink "$fixture_bin/docker"
set +e
foreign_output=$(PATH="$fixture_bin" TEST_PACKAGE_LOG="$package_log" \
  SETUP_SYSTEM_OS_RELEASE_FILE="$debian_release" "$online_setup_script" 2>&1)
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

setup_home=$test_root/setup-home
mkdir -p "$setup_home/bin" "$setup_home/dotfiles-releases"
printf 'private shell configuration\n' >"$setup_home/.bashrc"
ln -s existing-release "$setup_home/dotfiles-releases/current"
home_before=$(tar --sort=name --mtime=@0 --owner=0 --group=0 --numeric-owner \
  -C "$setup_home" -cf - . | sha256sum)
for manager in "$repo_dir/scripts/dotfiles-release" "$release_manager"; do
  PATH="$fixture_bin" TEST_PACKAGE_LOG="$package_log" \
    HOME="$setup_home" SETUP_SYSTEM_OS_RELEASE_FILE="$debian_release" \
    SETUP_SYSTEM_ETC_DIR="$test_root/unchanged-home-etc" \
    /bin/bash "$manager" setup >/dev/null
done
[[ $(tar --sort=name --mtime=@0 --owner=0 --group=0 --numeric-owner \
  -C "$setup_home" -cf - . | sha256sum) == "$home_before" ]] ||
  fail 'host setup changed HOME, installed a release or changed current'

printf 'Setup system tests passed\n'
