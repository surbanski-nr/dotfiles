#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=fixture.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/fixture.sh"
create_fixture

candidate=$test_root/validation-tools.tar.gz
make_artifact "$commit_three" validation-tools "$candidate" 3.0 true true true true
test_home=$test_root/fresh-validation-home
mkdir -p "$test_home"
run_manager install "$candidate" >/dev/null
run_manager health >/dev/null
run_manager uninstall >/dev/null
test_home=$test_root/'validation tools home'
mkdir -p "$test_home/bin" "$test_home/.local/state/dotfiles/setup-tools" "$test_root/user-plugins"
write_fake_tool "$test_home/bin/yq-0.9" 0.9
ln -s yq-0.9 "$test_home/bin/yq"
content=$(tar --sort=name --mtime=@0 --owner=0 --group=0 --numeric-owner \
  -C "$test_home/bin" -cf - -- yq-0.9 | sha256sum | awk '{print $1}')
printf 'complete\t%s\t%s\n' \
  aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa "$content" \
  >"$test_home/.local/state/dotfiles/setup-tools/yq-0.9.state"
export HELM_PLUGINS="$test_root/user-plugins"
run_manager install "$artifact_two" >/dev/null
run_manager install "$candidate" >/dev/null
run_manager install "$candidate" >/dev/null
[[ $("$test_home/bin/yq" --version) == *'version v3.0' ]] || fail 'new profile did not select yq'
output=$(HELM_PLUGINS='' "$test_home/bin/helm" fixture-plugins)
[[ $output == *"plugins=$test_home/dotfiles-releases/$id_three/share/helm/plugins"* ]] || fail 'Helm plugin directory did not follow its release'
run_manager health >/dev/null
run_manager rollback >/dev/null
[[ ! -x $test_home/bin/yq ]] || fail 'rollback to an older profile retained new yq'
output=$(env -u HELM_PLUGINS "$test_home/bin/helm" fixture-plugins)
[[ $output == *'plugins=unset'* ]] || fail 'old Helm borrowed the new plugin'
run_manager rollback >/dev/null
[[ $("$test_home/bin/yq" --version) == *'version v3.0' ]] || fail 'return to new profile lost yq'
run_manager uninstall >/dev/null
assert_link "$test_home/bin/yq" yq-0.9
[[ -d $test_root/user-plugins ]] || fail 'uninstall removed user Helm plugins'

for defect in missing-yq wrong-yq-provider broken-yaml missing-plugin missing-manifest missing-license wrong-manifest \
  wrong-plugin broken-generation missing-yq-version missing-plugin-version \
  invalid-version duplicate-key unknown-key legacy-fields; do
  marker=validation-$defect
  archive=$test_root/$marker.tar.gz
  make_artifact "$commit_three" "$marker" "$archive" 3.0 true true true true
  release=$test_root/stage-$marker/$id_three
  plugin=$release/share/helm/plugins/helm-values-schema-json
  case $defect in
    missing-yq) rm "$release/tools/bin/yq" ;;
    wrong-yq-provider) sed -i 's@https://github.com/mikefarah/yq/@https://example.invalid/another-yq/@' "$release/tools/bin/yq" ;;
    broken-yaml) sed -i '/awk.*name:/c\    exit 92' "$release/tools/bin/yq" ;;
    missing-plugin) rm "$plugin/schema" ;;
    missing-manifest) rm "$plugin/plugin.yaml" ;;
    missing-license) rm "$plugin/LICENSE" ;;
    wrong-manifest) sed -i 's/version: "3.0"/version: "9.9"/' "$plugin/plugin.yaml" ;;
    wrong-plugin) sed -i 's/version v3.0/version v9.9/' "$plugin/schema" ;;
    broken-generation) sed -i '/^jq /,$c\exit 91' "$plugin/schema" ;;
    missing-yq-version) sed -i '/^YQ_VERSION=/d' "$release/release.env" ;;
    missing-plugin-version) sed -i '/^HELM_SCHEMA_PLUGIN_VERSION=/d' "$release/release.env" ;;
    invalid-version) sed -i 's/^HELM_SCHEMA_PLUGIN_VERSION=.*/HELM_SCHEMA_PLUGIN_VERSION=invalid/' "$release/release.env" ;;
    duplicate-key) printf 'YQ_VERSION=3.0\n' >>"$release/release.env" ;;
    unknown-key) printf 'NEW_UNKNOWN_VERSION=3.0\n' >>"$release/release.env" ;;
    legacy-fields) sed -i 's/,yq$//' "$release/release.env" ;;
  esac
  repack_artifact "$marker" "$id_three" "$archive"
  test_home=$test_root/$marker-home
  mkdir -p "$test_home"
  run_manager install "$artifact_two" >/dev/null
  if run_manager install "$archive" >"$test_root/$marker.log" 2>&1; then
    fail "installed validation tools with $defect"
  fi
  assert_link "$test_home/dotfiles-releases/current" "$id_two"
  [[ ! -e $test_home/dotfiles-releases/.state/pending.env ]] || fail "$defect retained incomplete activation"
done

printf 'dotfiles_release: validation tools passed\n'
