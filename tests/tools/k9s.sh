#!/usr/bin/env bash

health_k9s() {
  local bin=$1 health_home=$2 config=$3 yamllint=${4:-}
  local work=$health_home/k9s

  mkdir -p "$work" || return
  local kubeconfig=$work/kubeconfig
  health_kubeconfig "$kubeconfig" || return
  mkdir -p "$work/.config" || return
  cp -a "$config" "$work/.config/k9s" || return
  if [[ -n $yamllint ]]; then
    "$yamllint" -d relaxed "$work/.config/k9s"/*.yaml || return
  fi
  HOME="$work" XDG_CONFIG_HOME="$work/.config" \
    XDG_DATA_HOME="$work/.local/share" \
    XDG_CACHE_HOME="$work/.cache" XDG_STATE_HOME="$work/.local/state" \
    KUBECONFIG="$kubeconfig" "$bin/k9s" info || return
}
