#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=fixture.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/fixture.sh"
create_fixture

if bash -c '
  set -euo pipefail
  source "$1/scripts/setup-lib"
  source "$1/scripts/setup-catalog-lib"
  source "$1/scripts/setup-recipes-lib"
  source "$1/scripts/setup-tools-lib"
  load_config "$1/tools.env"
  OFFLINE_RELEASE_TOOLS=(nvim)
  validate_tool_config offline
  validate_tool_selection OFFLINE_RELEASE_TOOLS offline
' bash "$repo_dir" >"$test_root/missing-rg-config.log" 2>&1; then
  fail 'offline configuration accepted Nvim without ripgrep'
fi
[[ $(<"$test_root/missing-rg-config.log") == *'nvim requires rg in OFFLINE_RELEASE_TOOLS'* ]] ||
  fail 'offline configuration did not report the missing ripgrep dependency'

bash -c '
  set -euo pipefail
  source "$1/scripts/setup-lib"
  source "$1/scripts/setup-catalog-lib"
  source "$1/scripts/setup-recipes-lib"
  source "$1/scripts/setup-tools-lib"
  load_config "$1/tools.env"
  OFFLINE_RELEASE_TOOLS=(nvim rg)
  validate_tool_config offline
  validate_tool_selection OFFLINE_RELEASE_TOOLS offline
' bash "$repo_dir"

full=$test_root/selected-full.tar.gz
small=$test_root/selected-small.tar.gz
tiny=$test_root/selected-tiny.tar.gz
make_selected_artifact "$commit_one" selected-full "$full" "${OFFLINE_RELEASE_TOOLS[@]}"
make_selected_artifact "$commit_three" selected-tiny "$tiny" rg

chosen=()
for tool in "${OFFLINE_RELEASE_TOOLS[@]}"; do
  case $tool in
    nvim | yamllint | k9s | trivy)
      continue
      ;;
  esac
  chosen+=("$tool")
done
make_selected_artifact "$commit_two" selected-small "$small" "${chosen[@]}"
for archive in "$full" "$small" "$tiny"; do
  run_manager verify "$archive" >/dev/null
done

test_home=$test_root/selected-home
mkdir -p "$test_home/.config/nvim2" "$test_home/.config/k9s" "$test_home/.local/state/nvim2"
printf 'editor original\n' >"$test_home/.config/nvim2/init.lua"
printf 'k9s original\n' >"$test_home/.config/k9s/config.yaml"
printf 'user state\n' >"$test_home/.local/state/nvim2/history"
run_manager install "$full" >/dev/null
run_manager install "$small" >/dev/null
[[ ! -L $test_home/.config/nvim2 && $(<"$test_home/.config/nvim2/init.lua") == 'editor original' ]] ||
  fail 'smaller profile did not restore the original editor configuration'
[[ ! -L $test_home/.config/k9s/config.yaml && $(<"$test_home/.config/k9s/config.yaml") == 'k9s original' ]] ||
  fail 'smaller profile did not restore the original k9s configuration'
[[ ! -L $test_home/.local/share/nvim2 && $(<"$test_home/.local/state/nvim2/history") == 'user state' ]] ||
  fail 'smaller profile retained editor data links or removed user state'
run_manager health >/dev/null
run_manager list >/dev/null
run_manager install "$tiny" >/dev/null
[[ ! -L $test_home/.tmux.conf && ! -L $test_home/.oh-my-posh.omp.json &&
  ! -L $test_home/.tmux/plugins/tmux-resurrect ]] || fail 'tiny profile retained tool configuration links'
run_manager health >/dev/null
run_manager list >/dev/null
run_manager set "$id_one" >/dev/null
[[ -L $test_home/.config/nvim2 && -L $test_home/.config/k9s/config.yaml && -L $test_home/.tmux.conf ]] ||
  fail 'selecting the full profile did not restore its links'

failure_bin=$test_root/selection-failure-bin
mkdir -p "$failure_bin"
cat >"$failure_bin/mv" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[[ ${!#} != "$HOME/dotfiles-releases/current" ]] || exit 91
exec /usr/bin/mv "$@"
EOF
chmod 0755 "$failure_bin/mv"
if PATH="$failure_bin:/usr/bin:/bin" run_manager set "$id_three" >/dev/null 2>&1; then
  fail 'profile switch reported success after publication failed'
fi
assert_link "$test_home/dotfiles-releases/current" "$id_one"
[[ -L $test_home/.config/nvim2 && -L $test_home/.config/k9s/config.yaml && -L $test_home/.tmux.conf ]] ||
  fail 'failed smaller-profile switch did not restore configuration links'
[[ $(<"$test_home/.config/nvim2.before-dotfiles-release/init.lua") == 'editor original' ]] ||
  fail 'failed switch lost the saved original editor configuration'
run_manager health >/dev/null
run_manager uninstall >/dev/null
[[ $(<"$test_home/.config/nvim2/init.lua") == 'editor original' ]] || fail 'uninstall lost the original configuration'

defects=(
  unselected-binary
  unselected-config
  missing-command
  missing-config
  missing-private-go
  missing-dependency
  missing-terraform
  empty
  duplicate
  unknown
  invalid-source-commit
)
for defect in "${defects[@]}"; do
  marker=selected-$defect
  archive=$test_root/$marker.tar.gz
  if [[ $defect == missing-config ]]; then
    make_selected_artifact "$commit_three" "$marker" "$archive" rg k9s
  elif [[ $defect == missing-private-go ]]; then
    make_selected_artifact "$commit_three" "$marker" "$archive" rg go
  elif [[ $defect == missing-terraform ]]; then
    make_selected_artifact "$commit_three" "$marker" "$archive" nvim nodejs python go rg terraform
  elif [[ $defect == missing-dependency ]]; then
    make_selected_artifact "$commit_three" "$marker" "$archive" nvim rg python
  else
    make_selected_artifact "$commit_three" "$marker" "$archive" rg fd
  fi
  release=$test_root/stage-$marker/$id_three
  case $defect in
    unselected-binary)
      write_fake_tool "$release/bin/trivy" 3.0
      ;;
    unselected-config)
      mkdir -p "$release/dotfiles/mc/.config/mc"
      printf 'config\n' >"$release/dotfiles/mc/.config/mc/ini"
      ;;
    missing-command)
      unlink "$release/bin/rg"
      ;;
    missing-private-go)
      unlink "$release/tools/go/bin/go"
      ;;
    missing-config)
      unlink "$release/dotfiles/k9s/.config/k9s/config.yaml"
      ;;
    missing-dependency)
      sed -i 's/^OFFLINE_RELEASE_TOOLS=.*/OFFLINE_RELEASE_TOOLS=nvim,python/; /^RG_VERSION=/d' "$release/release.env"
      unlink "$release/bin/rg"
      unlink "$release/tools/bin/rg"
      ;;
    missing-terraform)
      printf 'terraform\n' >>"$release/share/nvim2/mason/requirements.txt"
      sed -i 's/,terraform$//; /^TERRAFORM_VERSION=/d' "$release/release.env"
      unlink "$release/bin/terraform"
      unlink "$release/tools/bin/terraform"
      ;;
    empty)
      sed -i 's/^OFFLINE_RELEASE_TOOLS=.*/OFFLINE_RELEASE_TOOLS=/' "$release/release.env"
      ;;
    duplicate)
      sed -i 's/^OFFLINE_RELEASE_TOOLS=.*/OFFLINE_RELEASE_TOOLS=rg,rg/' "$release/release.env"
      ;;
    unknown)
      sed -i 's/^OFFLINE_RELEASE_TOOLS=.*/OFFLINE_RELEASE_TOOLS=rg,unknown/' "$release/release.env"
      ;;
    invalid-source-commit)
      sed -i "s/^SOURCE_COMMIT=.*/SOURCE_COMMIT=${commit_three:0:12}invalid/" "$release/release.env"
      ;;
  esac
  repack_artifact "$marker" "$id_three" "$archive"
  if run_manager verify "$archive" >"$test_root/$marker.log" 2>&1; then
    fail "verification accepted $defect"
  fi
  if [[ $defect == missing-terraform ]]; then
    [[ $(<"$test_root/$marker.log") == *'configured Neovim tools require terraform'* ]] ||
      fail 'verification did not report the missing Terraform dependency'
  elif [[ $defect == missing-dependency ]]; then
    [[ $(<"$test_root/$marker.log") == *'nvim requires rg'* ]] ||
      fail 'verification did not report the missing ripgrep dependency'
  fi
done

printf 'dotfiles_release: selection passed\n'
