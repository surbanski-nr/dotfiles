#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=fixture.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/fixture.sh"
create_fixture

make_mason_artifact() {
  local marker=$1 selection=$2
  local destination=$test_root/$marker.tar.gz
  local release=$test_root/stage-$marker/$id_three
  local mason=$release/share/nvim2/mason mason_package

  if [[ $selection == empty || $selection == binary || $selection == binary-underscore ]]; then
    make_selected_artifact "$commit_three" "$marker" "$destination" nvim rg
  else
    make_selected_artifact "$commit_three" "$marker" "$destination" nvim rg python
  fi
  find "$mason/bin" "$mason/packages" "$release/python-locks" \
    "$release/python-wheelhouse" -mindepth 1 -depth -delete
  : >"$mason/inventory.tsv"
  : >"$release/python-locks/inventory.tsv"
  printf 'rg\n' >"$mason/requirements.txt"
  case $selection in
    binary | binary-underscore)
      mason_package=stylua
      [[ $selection != binary-underscore ]] || mason_package=eslint_d
      mkdir -p "$mason/packages/$mason_package"
      printf '{}\n' >"$mason/packages/$mason_package/mason-receipt.json"
      write_fake_tool "$mason/packages/$mason_package/$mason_package" v2.3.1
      ln -s "../packages/$mason_package/$mason_package" "$mason/bin/$mason_package"
      printf '%s\tv2.3.1\t-\t%s\n' "$mason_package" "$mason_package" >"$mason/inventory.tsv"
      ;;
    python | python-alias)
      mason_package=yamllint
      [[ $selection != python-alias ]] || mason_package=different-mason-name
      mkdir -p "$mason/packages/$mason_package"
      printf '{}\n' >"$mason/packages/$mason_package/mason-receipt.json"
      ln -s "../packages/$mason_package/venv/bin/yamllint" "$mason/bin/yamllint"
      printf '%s\t1.38.0\tyamllint\tyamllint\n' "$mason_package" >"$mason/inventory.tsv"
      printf 'yamllint\t1.38.0\n' >"$release/python-locks/inventory.tsv"
      printf 'yamllint==1.38.0\n' >"$release/python-locks/yamllint.in"
      printf 'yamllint==1.38.0 --hash=sha256:fixture\n' >"$release/python-locks/yamllint.lock"
      printf 'fixture wheel\n' >"$release/python-wheelhouse/fixture.whl"
      printf 'python\n' >>"$mason/requirements.txt"
      ;;
  esac
  repack_artifact "$marker" "$id_three" "$destination"
}

for selection in empty binary binary-underscore python python-alias; do
  marker=mason-$selection
  archive=$test_root/$marker.tar.gz
  make_mason_artifact "$marker" "$selection"
  run_manager verify "$archive" >/dev/null
  test_home=$test_root/home-$selection
  mkdir -p "$test_home"
  run_manager install "$archive" >/dev/null
  run_manager health >/dev/null
  [[ ! -e $test_home/dotfiles-releases/current/share/nvim2/mason/packages/ansible-lint ]] ||
    fail 'subset installed undeclared Ansible'
  run_manager uninstall >/dev/null
done

for damage in inventory receipt launcher extra-package python-inventory requirement; do
  marker=mason-broken-$damage
  archive=$test_root/$marker.tar.gz
  make_mason_artifact "$marker" binary
  release=$test_root/stage-$marker/$id_three
  mason=$release/share/nvim2/mason
  case $damage in
    inventory)
      rm "$mason/inventory.tsv"
      ;;
    receipt)
      rm "$mason/packages/stylua/mason-receipt.json"
      ;;
    launcher)
      unlink "$mason/bin/stylua"
      ;;
    extra-package)
      mkdir "$mason/packages/unselected"
      ;;
    python-inventory)
      printf 'yamllint\t1.38.0\n' >"$release/python-locks/inventory.tsv"
      ;;
    requirement)
      printf 'terraform\n' >>"$mason/requirements.txt"
      ;;
  esac
  repack_artifact "$marker" "$id_three" "$archive"
  if run_manager verify "$archive" >"$test_root/$damage.log" 2>&1; then
    fail "verification accepted damaged Mason payload: $damage"
  fi
done

make_mason_artifact mason-manifest empty
(
  # shellcheck source=../../scripts/build-dotfiles-release
  source "$repo_dir/scripts/build-dotfiles-release"
  # shellcheck source=../../scripts/setup-catalog-lib
  source "$repo_dir/scripts/setup-catalog-lib"
  # shellcheck source=../../scripts/setup-tools-lib
  source "$repo_dir/scripts/setup-tools-lib"
  load_config "$repo_dir/tools.env"
  OFFLINE_RELEASE_TOOLS=(nvim rg)
  BUILD_TMUX_PLUGINS=()
  SETUP_SYSTEM_PACKAGES=()
  BUILD_VERSIONS[nvim]=0.12.5
  BUILD_VERSIONS[rg]=15.1.0
  manifest_release=$test_root/stage-mason-manifest/$id_three
  mkdir -p "$test_root/manifest-inputs"
  cp "$repo_dir/nvim2/.config/nvim2/nvim-pack-lock.json" "$manifest_release/config/nvim2/"
  DOTFILES_OFFLINE_RELEASE_ROOT=$manifest_release \
    write_release_metadata "$manifest_release" debian-13-x86_64 \
    "$commit_three" "$commit_three" fixture "$test_root/manifest-inputs"
  awk '
    /^python_locks_sha256:/ {
      getline
      if ($0 != "python_wheels_sha256:") {
        exit 1
      }
      getline
      if ($0 !~ /^nvim_pack_lock_sha256=/) {
        exit 1
      }
      found = 1
    }
    END {
      if (!found) {
        exit 1
      }
    }
  ' "$manifest_release/build-manifest.txt"
)

make_mason_artifact mason-python-launcher python
launcher_release=$test_root/stage-mason-python-launcher/$id_three
cat >"$launcher_release/tools/nvim/bin/nvim" <<'BASH'
#!/usr/bin/env bash
set -euo pipefail
if [[ ${1:-} == shell ]]; then
  exec bash --noprofile --norc -ic 'source "$TEST_BASHRC"; command -v python3'
fi
command -v python3
BASH
system_python_bin=$test_root/system-python-bin
mkdir -p "$system_python_bin"
printf '#!/usr/bin/env bash\nexit 0\n' >"$system_python_bin/python3"
chmod 0755 "$system_python_bin/python3"
python_path=$(HOME=$test_home VIRTUAL_ENV='' NVIM_APPNAME=nvim2 \
  PATH="$system_python_bin:/usr/bin:/bin" "$launcher_release/bin/nvim")
[[ $python_path == "$launcher_release/tools/python/bin/python3" ]] ||
  fail "Neovim did not select its standalone Python without Ansible: $python_path"
# Isolate PATH additions from the caller's mise installation.
python_path=$(
  HOME=$test_home VIRTUAL_ENV='' NVIM_APPNAME=nvim2 \
    MISE_DATA_DIR=$test_root/mise MISE_SYSTEM_DATA_DIR='' \
    PATH="$system_python_bin:/usr/bin:/bin" \
    TEST_BASHRC="$repo_dir/bash/.bashrc" "$launcher_release/bin/nvim" shell 2>/dev/null
)
[[ $python_path == "$system_python_bin/python3" ]] ||
  fail "Neovim terminal retained its private Python: $python_path"

printf 'dotfiles-release tests: Mason subsets and missing declared payload checks passed\n'
