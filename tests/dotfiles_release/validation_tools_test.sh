#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=fixture.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/fixture.sh"
create_fixture

candidate=$test_root/validation-tools.tar.gz
make_artifact "$commit_three" validation-tools "$candidate" 3.0 true true true true
test_home=$test_root/'validation tools home'
mkdir -p "$test_home/bin" "$test_root/user-plugins"
write_fake_tool "$test_home/bin/yq-0.9" 0.9
ln -s yq-0.9 "$test_home/bin/yq"
export HELM_PLUGINS="$test_root/user-plugins"
run_manager install "$artifact_two" >/dev/null
run_manager install "$candidate" >/dev/null
run_manager install "$candidate" >/dev/null
[[ $("$test_home/bin/yq" --version) == *'version v3.0' ]] || fail 'new profile did not select yq'
output=$(HELM_PLUGINS='' "$test_home/bin/helm" fixture-plugins)
[[ $output == *"plugins=$test_home/dotfiles-releases/$id_three/share/helm/plugins"* ]] ||
  fail 'Helm plugin directory did not follow its release'
run_manager set "$id_two" >/dev/null
[[ ! -x $test_home/bin/yq ]] || fail 'older profile retained new yq'
output=$(env -u HELM_PLUGINS "$test_home/bin/helm" fixture-plugins)
[[ $output == *'plugins=unset'* ]] || fail 'old Helm borrowed the new plugin'
run_manager set "$id_three" >/dev/null
run_manager uninstall >/dev/null
assert_link "$test_home/bin/yq" yq-0.9
[[ -d $test_root/user-plugins ]] || fail 'uninstall removed user Helm plugins'

for defect in missing-yq missing-plugin missing-manifest missing-license wrong-manifest \
  missing-yq-version missing-plugin-version invalid-version duplicate-key unknown-key legacy-fields; do
  marker=validation-$defect
  archive=$test_root/$marker.tar.gz
  make_artifact "$commit_three" "$marker" "$archive" 3.0 true true true true
  release=$test_root/stage-$marker/$id_three
  plugin=$release/share/helm/plugins/helm-values-schema-json
  case $defect in
    missing-yq) unlink "$release/tools/bin/yq" ;;
    missing-plugin) unlink "$plugin/schema" ;;
    missing-manifest) unlink "$plugin/plugin.yaml" ;;
    missing-license) unlink "$plugin/LICENSE" ;;
    wrong-manifest) sed -i 's/version: "3.0"/version: "9.9"/' "$plugin/plugin.yaml" ;;
    missing-yq-version) sed -i '/^YQ_VERSION=/d' "$release/release.env" ;;
    missing-plugin-version) sed -i '/^HELM_SCHEMA_PLUGIN_VERSION=/d' "$release/release.env" ;;
    invalid-version) sed -i 's/^HELM_SCHEMA_PLUGIN_VERSION=.*/HELM_SCHEMA_PLUGIN_VERSION=invalid/' "$release/release.env" ;;
    duplicate-key) printf 'YQ_VERSION=3.0\n' >>"$release/release.env" ;;
    unknown-key) printf 'NEW_UNKNOWN_VERSION=3.0\n' >>"$release/release.env" ;;
    legacy-fields) sed -i 's/,yq$//' "$release/release.env" ;;
  esac
  repack_artifact "$marker" "$id_three" "$archive"
  if run_manager verify "$archive" >"$test_root/$marker.log" 2>&1; then
    fail "verified validation tools with $defect"
  fi
done

for defect in wrong-plugin broken-yaml broken-generation; do
  marker=runtime-$defect
  archive=$test_root/$marker.tar.gz
  make_artifact "$commit_three" "$marker" "$archive" 3.0 true true true true
  release=$test_root/stage-$marker/$id_three
  plugin=$release/share/helm/plugins/helm-values-schema-json
  case $defect in
    wrong-plugin) sed -i 's/version v3.0/version v9.9/' "$plugin/schema" ;;
    broken-yaml) sed -i '/awk.*name:/c\    exit 92' "$release/tools/bin/yq" ;;
    broken-generation) sed -i '/^jq /,$c\exit 91' "$plugin/schema" ;;
  esac
  repack_artifact "$marker" "$id_three" "$archive"
  run_manager verify "$archive" >/dev/null
  test_home=$test_root/$marker-home
  mkdir -p "$test_home"
  if [[ $defect == wrong-plugin ]]; then
    if run_manager install "$archive" >/dev/null 2>&1; then fail 'install accepted a wrong plugin version'; fi
  else
    run_manager install "$archive" >/dev/null
    status=0
    bash -c 'source "$1"; health_stage "validation tools" health_validation_tools "$2" "$3" 3.0 3.0 3.0' \
      checker-test "$repo_dir/scripts/check-dotfiles-release" \
      "$test_home/dotfiles-releases/$id_three" "$test_root/checker-$defect" \
      >"$test_root/checker-$defect.log" 2>&1 || status=$?
    [[ $status != 0 && $(<"$test_root/checker-$defect.log") == *'validation tools health check failed'* ]] ||
      fail "CI runtime check accepted $defect"
  fi
done

printf 'dotfiles_release: validation tools passed\n'
