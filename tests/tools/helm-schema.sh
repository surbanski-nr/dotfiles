#!/usr/bin/env bash

health_helm_schema() {
  local release=$1 health_home=$2 output version
  local work=$health_home/helm_schema

  mkdir -p "$work" || return
  local plugin_version helm_versions
  local HELM_PLUGINS=$release/share/helm/plugins
  local HELM_CONFIG_HOME=$work/config HELM_CACHE_HOME=$work/cache HELM_DATA_HOME=$work/data
  export HELM_PLUGINS HELM_CONFIG_HOME HELM_CACHE_HOME HELM_DATA_HOME

  plugin_version=$(metadata_value "$release/release.env" HELM_SCHEMA_PLUGIN_VERSION) || return
  helm_versions=$(metadata_value "$release/release.env" HELM_VERSIONS) || return
  require_command jq || return
  cat >"$work/values.yaml" <<'EOF'
replicas: 2
tls: {} # @schema $ref: tls.schema.json
EOF
  cat >"$work/tls.schema.json" <<'EOF'
{"$id":"https://offline.example/tls.schema.json","type":"object","properties":{"enabled":{"type":"boolean"}},"required":["enabled"],"additionalProperties":false}
EOF
  for version in ${helm_versions//,/ }; do
    output=$(HELM_VERSION="$version" "$release/bin/helm" plugin list) || return
    awk -v expected="${plugin_version#v}" \
      '$1 == "schema" { count++; valid = ($2 == expected) } END { exit !(count == 1 && valid) }' \
      <<<"$output" || {
      report_error "Helm $version schema plugin manifest has an unexpected version"
      return 1
    }
    output=$(HELM_VERSION="$version" "$release/bin/helm" schema version) || return
    [[ $output == "helm schema version v${plugin_version#v}" ]] || {
      report_error "Helm $version schema plugin reported an unexpected version: $output"
      return 1
    }
    (cd "$work" && HELM_VERSION="v${version#v}" "$release/bin/helm" schema \
      -f values.yaml -o schema.json --bundle --bundle-without-id --bundle-root "$work") || return
    jq -e '
      .properties.replicas.type == "integer" and
      .properties.tls."$ref" == "#/$defs/tls.schema.json" and
      (."$defs"."tls.schema.json" |
        .properties.enabled.type == "boolean" and .required == ["enabled"] and (has("$id") | not))
    ' "$work/schema.json" >/dev/null || {
      report_error "Helm $version schema generation failed"
      return 1
    }
  done
  printf '%s\n' '{"properties":{"tls":{"description":"overlay"}}}' >"$work/overlay.json" || return
  jq -s '.[0] * .[1]' "$work/schema.json" "$work/overlay.json" >"$work/merged.json" || return
  jq -e '.properties.tls.description == "overlay" and .properties.tls."$ref" == "#/$defs/tls.schema.json"' \
    "$work/merged.json" >/dev/null || {
    report_error 'jq schema overlay merge failed'
    return 1
  }
}
