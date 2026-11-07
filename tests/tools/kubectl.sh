#!/usr/bin/env bash

health_kubectl() {
  local release=$1 health_home=$2 output versions version
  local work=$health_home/kubectl

  mkdir -p "$work" || return
  local kubeconfig=$work/kubeconfig
  health_kubeconfig "$kubeconfig" || return
  versions=$(metadata_value "$release/release.env" KUBECTL_VERSIONS) || return
  for version in ${versions//,/ }; do
    output=$(KUBECTL_VERSION="$version" KUBECONFIG="$kubeconfig" \
      "$release/bin/kubectl" config current-context) || return
    [[ $output == offline-a ]] || {
      die "kubectl $version did not read the isolated kubeconfig"
      return 1
    }
  done
}
