#!/usr/bin/env bash

health_bash() {
  local release=$1 health_home=$2 check invocation
  local -A metadata=()
  read_release_metadata "$release/release.env" metadata || return

  mkdir -p "$health_home/dotfiles-releases" || return
  ln -s "$release" "$health_home/dotfiles-releases/current" || return
  ln -s "$release/dotfiles/bash/.bashrc" "$health_home/.bashrc" || return
  ln -s "$release/dotfiles/bash/.bash_aliases" "$health_home/.bash_aliases" || return
  if [[ -v metadata[OMP_VERSION] ]]; then
    ln -s "$release/dotfiles/oh-my-posh/.oh-my-posh.omp.json" "$health_home/.oh-my-posh.omp.json" || return
  fi
  check=$health_home/bash-health.sh
  cat >"$check" <<'BASH' || return
set -e

_dotfiles_health_fail() {
  printf 'dotfiles-release: Bash health check failed: %s\n' "$*" >&2
  exit 1
}

source "$HOME/.bashrc" || _dotfiles_health_fail 'first .bashrc load returned an error'
source "$HOME/.bashrc" || _dotfiles_health_fail 'second .bashrc load returned an error'
hash -r
[[ $DOTFILES == "$EXPECTED_RELEASE/dotfiles" ]] ||
  _dotfiles_health_fail "DOTFILES does not select the candidate release: ${DOTFILES:-unset}"

if [[ ${HEALTH_NODE_VERSION:-} == 1 ]]; then
  [[ $(readlink -f -- "$(type -P node)") == "$(readlink -f -- "$EXPECTED_RELEASE/bin/node")" ]] ||
    _dotfiles_health_fail 'node does not select the candidate release'
fi
if [[ ${HEALTH_ZOXIDE_VERSION:-} == 1 ]]; then
  [[ $(type -t __zoxide_hook) == function ]] ||
    _dotfiles_health_fail 'zoxide initialization is missing'
fi
if [[ ${HEALTH_FZF_VERSION:-} == 1 ]]; then
  [[ -n ${_DOTFILES_FZF_PROVIDER:-} ]] ||
    _dotfiles_health_fail 'fzf initialization is missing'
fi
[[ ${VIRTUAL_ENV_DISABLE_PROMPT:-} == 1 ]] ||
  _dotfiles_health_fail 'virtual-environment prompt suppression is missing'
prompt=${PROMPT_COMMAND[*]}
without=${prompt//_dotfiles_history_sync/}
[[ $(( (${#prompt} - ${#without}) / 22 )) -eq 1 ]] ||
  _dotfiles_health_fail 'history synchronization is missing or duplicated'
[[ $PS1 != *VIRTUAL_ENV* ]] || _dotfiles_health_fail 'the prompt embeds VIRTUAL_ENV'
printf 'bash-dotfiles=%s\n' "$DOTFILES"
printf 'bash-prompt-command=%s\n' "$prompt"
exit 0
BASH
  # shellcheck disable=SC2016
  printf -v invocation '%q ' env -u DOTFILES -u DOTFILES_AUTO_ROOT \
    HOME="$health_home" EXPECTED_RELEASE="$release" \
    DOTFILES_RELEASE_ROOT="$health_home/dotfiles-releases" \
    HEALTH_NODE_VERSION="${metadata[NODE_VERSION]:+1}" \
    HEALTH_ZOXIDE_VERSION="${metadata[ZOXIDE_VERSION]:+1}" \
    HEALTH_FZF_VERSION="${metadata[FZF_VERSION]:+1}" \
    TERM=xterm-256color PATH=/usr/bin:/bin bash --noprofile --norc -i -c \
    'source "$1"' bash-health "$check"
  timeout 120s script --quiet --return --command "$invocation" /dev/null </dev/null || return
}
