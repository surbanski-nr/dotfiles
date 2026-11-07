#!/usr/bin/env bash

health_k9s() {
  local release=$1 health_home=$2
  local work=$health_home/k9s

  mkdir -p "$work" || return
  local kubeconfig=$work/kubeconfig
  local -A metadata=()
  health_kubeconfig "$kubeconfig" || return
  mkdir -p "$work/.config" || return
  cp -a "$release/dotfiles/k9s/.config/k9s" "$work/.config/k9s" || return
  read_release_metadata "$release/release.env" metadata || return
  if [[ -v metadata[NVIM_VERSION] ]]; then
    "$release/share/nvim2/mason/packages/yamllint/venv/bin/yamllint" \
      -d relaxed "$work/.config/k9s"/*.yaml || return
  fi
  HOME="$work" XDG_CONFIG_HOME="$work/.config" \
    XDG_CACHE_HOME="$work/.cache" XDG_STATE_HOME="$work/.local/state" \
    KUBECONFIG="$kubeconfig" "$release/bin/k9s" info || return
}
