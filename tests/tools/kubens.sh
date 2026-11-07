#!/usr/bin/env bash

health_kubens() {
  local release=$1 health_home=$2
  local work=$health_home/kubens

  mkdir -p "$work" || return
  local kubeconfig=$work/kubeconfig
  health_kubeconfig "$kubeconfig" || return
  [[ $(KUBECONFIG="$kubeconfig" "$release/bin/kubens" --current) == default ]] || {
    die 'kubens did not read the isolated namespace'
    return 1
  }
  KUBECONFIG="$kubeconfig" "$release/bin/kubens" --force offline-namespace || return
  [[ $(KUBECONFIG="$kubeconfig" "$release/bin/kubens" --current) == offline-namespace ]] || {
    die 'kubens did not update the isolated namespace'
    return 1
  }
}
