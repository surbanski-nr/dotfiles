#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=fixture.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/fixture.sh"
create_fixture

release=$test_root/stage-one/$id_one
printf 'Go UTF-8 fixture\n' >"$release/tools/Þfoo.go"
ln -s Þfoo.go "$release/tools/utf8-link"
ln -s lib/tmux-test/run_tests "$release/share/tmux/plugins/tmux-resurrect/run_tests"
mkdir -p "$release/share/tmux/plugins/tmux-resurrect/tests/helpers"
ln -s ../lib/tmux-test/tests/run_tests_in_isolation \
  "$release/share/tmux/plugins/tmux-resurrect/tests/run_tests_in_isolation"
ln -s ../../lib/tmux-test/tests/helpers/helpers.sh \
  "$release/share/tmux/plugins/tmux-resurrect/tests/helpers/helpers.sh"
repack_artifact one "$id_one" "$artifact_one"

download_dir=$test_root/download
mkdir -p "$download_dir"
tar -xOzf "$artifact_one" "$id_one/dotfiles-release" >"$download_dir/dotfiles-release"
cp "$artifact_one" "$download_dir/renamed-package.tar.gz"
test_home=$test_root/verification-home
mkdir -p "$test_home/bin"
printf 'private bashrc\n' >"$test_home/.bashrc"
ln -s /usr/bin/true "$test_home/bin/rg"
home_digest=$(tar --sort=name --mtime=@0 --owner=0 --group=0 --numeric-owner \
  -C "$test_home" -cf - . | sha256sum)
output=$(LC_ALL=C HOME=$test_home DOTFILES_OS_RELEASE_FILE=$test_root/missing-os-release \
  bash "$download_dir/dotfiles-release" verify "$download_dir/renamed-package.tar.gz")
[[ $output == *"$id_one (debian-13-x86_64)"* ]] ||
  fail 'standalone verification did not derive identity and platform from the renamed archive'
[[ $(tar --sort=name --mtime=@0 --owner=0 --group=0 --numeric-owner \
  -C "$test_home" -cf - . | sha256sum) == "$home_digest" ]] ||
  fail 'verify changed the target HOME'
[[ ! -e $test_home/dotfiles-releases ]] || fail 'verify installed the release'
LC_ALL=C run_manager install "$artifact_one" >/dev/null
LC_ALL=C run_manager uninstall "$id_one" >/dev/null

make_artifact "$commit_two" no-execution "$artifact_two"
release=$test_root/stage-no-execution/$id_two
printf '#!/usr/bin/env bash\nexit 99\n' >"$release/tools/bin/node"
repack_artifact no-execution "$id_two" "$artifact_two"
run_manager verify "$artifact_two" >/dev/null
if run_manager install "$artifact_two" >/dev/null 2>&1; then
  fail 'install accepted a failed runtime probe'
fi
[[ ! -e $test_home/dotfiles-releases/$id_two && ! -L $test_home/dotfiles-releases/current ]] ||
  fail 'failed runtime probe activated or retained the candidate'

for defect in missing-layout missing-executable missing-plugin missing-wheelhouse \
  dangling-plugin-runtime missing-private-nvim missing-private-tmux missing-nvim-runtime \
  incomplete-ssh checksum missing-checksum extra-file extra-root dangling-link duplicate-member installed-state \
  inventory-mismatch duplicate-inventory extra-lock control-character control-link; do
  marker=verify-$defect
  archive=$test_root/$marker.tar.gz
  make_artifact "$commit_three" "$marker" "$archive" 3.0 true true true
  release=$test_root/stage-$marker/$id_three
  case $defect in
    missing-layout) find "$release/config" -depth -delete ;;
    missing-executable) unlink "$release/bin/uvx" ;;
    missing-plugin) find "$release/share/tmux/plugins/tmux-sensible" -depth -delete ;;
    missing-wheelhouse) find "$release/python-wheelhouse" -depth -delete ;;
    missing-private-nvim) unlink "$release/tools/nvim/bin/nvim" ;;
    missing-private-tmux) unlink "$release/tools/tmux/bin/tmux" ;;
    missing-nvim-runtime) find "$release/tools/nvim/share/nvim/runtime" -depth -delete ;;
    incomplete-ssh) unlink "$release/dotfiles/ssh/.ssh/config" ;;
    dangling-link) ln -s missing "$release/tools/dangling" ;;
    dangling-plugin-runtime)
      unlink "$release/share/tmux/plugins/tmux-resurrect/resurrect.tmux"
      ln -s missing "$release/share/tmux/plugins/tmux-resurrect/resurrect.tmux"
      ;;
    installed-state) printf 'fake\n' >"$release/installed.sha256" ;;
    inventory-mismatch)
      printf 'ansible-lint\t99.0.0\nyamllint\t1.38.0\n' >"$release/python-locks/inventory.tsv"
      ;;
    duplicate-inventory)
      printf 'ansible-lint\t26.1.1\nansible-lint\t26.1.1\n' >"$release/python-locks/inventory.tsv"
      ;;
    extra-lock) cp "$release/python-locks/yamllint.lock" "$release/python-locks/extra.lock" ;;
    control-character) printf 'unsafe\n' >"$release/tools/"$'control\001' ;;
    control-link)
      printf 'unsafe\n' >"$release/tools/"$'control\001'
      ln -s $'control\001' "$release/tools/control-link"
      ;;
  esac
  repack_artifact "$marker" "$id_three" "$archive"
  case $defect in
    checksum) printf 'modified\n' >>"$release/config/nvim2/init.lua" ;;
    missing-checksum) sed -i '\|./config/nvim2/init.lua$|d' "$release/SHA256SUMS" ;;
    extra-file) printf 'unlisted\n' >"$release/unlisted" ;;
    extra-root)
      mkdir -p "$test_root/stage-$marker/another-root"
      tar -C "$test_root/stage-$marker" -czf "$archive" "$id_three" another-root
      ;;
    duplicate-member)
      tar -C "$test_root/stage-$marker" -czf "$archive" "$id_three" "$id_three/release.env"
      ;;
  esac
  if [[ $defect == checksum || $defect == missing-checksum || $defect == extra-file ]]; then
    tar -C "$test_root/stage-$marker" -czf "$archive" "$id_three"
  fi
  if run_manager verify "$archive" >"$test_root/$marker.log" 2>&1; then
    fail "verify accepted $defect"
  fi
done

for command in inspect rollback; do
  if run_manager "$command" >/dev/null 2>&1; then fail "obsolete command $command still exists"; fi
done
if run_manager verify debian-13-x86_64 "$artifact_one" >/dev/null 2>&1; then
  fail 'verify still accepts a required platform argument'
fi
if run_manager verify --skip-health "$artifact_one" >/dev/null 2>&1; then
  fail 'verify accepted a runtime bypass flag'
fi

printf 'dotfiles_release: verification passed\n'
