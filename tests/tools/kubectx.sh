#!/usr/bin/env bash

health_kubectx() {
  local release=$1 health_home=$2 output
  local work=$health_home/kubectx

  mkdir -p "$work" || return
  local kubeconfig=$work/kubeconfig
  health_kubeconfig "$kubeconfig" || return
  output=$(KUBECONFIG="$kubeconfig" "$release/bin/kubectx" --current) || return
  printf 'kubectx-current=%s\n' "$output"
  [[ $output == offline-a ]] || {
    report_error 'kubectx did not read the isolated kubeconfig'
    return 1
  }
  KUBECONFIG="$kubeconfig" "$release/bin/kubectx" offline-b || return
  [[ $(KUBECONFIG="$kubeconfig" "$release/bin/kubectx" --current) == offline-b ]] || {
    report_error 'kubectx did not switch the isolated context'
    return 1
  }
}
