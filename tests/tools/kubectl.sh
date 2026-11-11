#!/usr/bin/env bash

health_kubectl() {
  local bin=$1 health_home=$2 versions=${3:-} output version
  local work=$health_home/kubectl
  local -a selected_versions=('')

  mkdir -p "$work" || return
  local kubeconfig=$work/kubeconfig
  health_kubeconfig "$kubeconfig" || return
  if [[ -n $versions ]]; then
    IFS=, read -r -a selected_versions <<<"$versions"
  fi
  for version in "${selected_versions[@]}"; do
    output=$(KUBECTL_VERSION="$version" KUBECONFIG="$kubeconfig" \
      "$bin/kubectl" config current-context) || return
    [[ $output == offline-a ]] || {
      report_error "kubectl $version did not read the isolated kubeconfig"
      return 1
    }
  done
}
