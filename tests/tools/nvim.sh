#!/usr/bin/env bash

health_nvim() {
  local release=$1 health_home=$2

  local -A metadata=()
  read_release_metadata "$release/release.env" metadata || return
  if [[ -v metadata[HELM_VERSIONS] ]]; then
    if [[ ! -v metadata[NVIM_TOOLS_FORMAT] ]] ||
      awk -F '\t' '$1 == "helm-ls" { found = 1 } END { exit !found }' \
        "$release/share/nvim2/mason/inventory.tsv"; then
      health_chart "$health_home/nvim-chart" || return
      (cd "$health_home/nvim-chart" && "$release/share/nvim2/mason/bin/helm_ls" lint) || return
    fi
  fi
  need setsid || return
  (
    if [[ -n ${LOCK_FD:-} ]]; then
      exec {LOCK_FD}>&-
    fi
    # Interactive Bash fixtures open /dev/tty even with redirected stdin.
    # Detach from the terminal so timeout's background group cannot get SIGTTIN.
    HOME="$health_home" XDG_CACHE_HOME="$health_home/.cache" \
      XDG_STATE_HOME="$health_home/.local/state" GIT_OPTIONAL_LOCKS=0 \
      DOTFILES_OFFLINE_RELEASE_ROOT="$release" \
      PYTHONDONTWRITEBYTECODE=1 NVIM_APPNAME=nvim2 NVIM2_CHECK_TOOLS=1 \
      NVIM2_BENCHMARK_RUNS=3 setsid --wait timeout 1200s \
      bash "$release/config/nvim2/tests/check.sh" </dev/null
  )
}
