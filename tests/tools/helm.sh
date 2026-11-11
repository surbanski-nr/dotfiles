#!/usr/bin/env bash

health_helm() {
  local bin=$1 health_home=$2 versions=${3:-} output version
  local work=$health_home/helm
  local -a selected_versions=('')

  mkdir -p "$work" || return
  health_chart "$work/chart" || return
  if [[ -n $versions ]]; then
    IFS=, read -r -a selected_versions <<<"$versions"
  fi
  for version in "${selected_versions[@]}"; do
    output=$(HELM_VERSION="$version" HELM_CONFIG_HOME="$health_home/helm/config" \
      HELM_CACHE_HOME="$health_home/helm/cache" HELM_DATA_HOME="$health_home/helm/data" \
      "$bin/helm" template offline-health "$work/chart") || return
    printf '%s\n' "$output"
    [[ $output == *'name: offline-health'* ]] || {
      report_error "Helm $version did not render the local chart"
      return 1
    }
  done
}
