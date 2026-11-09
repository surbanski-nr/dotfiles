#!/usr/bin/env bash

health_helm() {
  local release=$1 health_home=$2 output versions version
  local work=$health_home/helm

  mkdir -p "$work" || return
  health_chart "$work/chart" || return
  versions=$(metadata_value "$release/release.env" HELM_VERSIONS) || return
  for version in ${versions//,/ }; do
    output=$(HELM_VERSION="$version" HELM_CONFIG_HOME="$health_home/helm/config" \
      HELM_CACHE_HOME="$health_home/helm/cache" HELM_DATA_HOME="$health_home/helm/data" \
      "$release/bin/helm" template offline-health "$work/chart") || return
    printf '%s\n' "$output"
    [[ $output == *'name: offline-health'* ]] || {
      report_error "Helm $version did not render the local chart"
      return 1
    }
  done
}
