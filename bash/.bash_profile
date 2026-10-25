# shellcheck shell=bash

if [ -z "${XDG_CONFIG_HOME:-}" ]; then
  export XDG_CONFIG_HOME="$HOME/.config"
fi

if [ -f ~/.bashrc ]; then
  # shellcheck source=.bashrc
  source ~/.bashrc
fi

if [[ -n ${SSH_AUTH_SOCK:-} && ! -S ${SSH_AUTH_SOCK} ]]; then
  printf 'dotfiles: SSH_AUTH_SOCK is not a socket: %s\n' "$SSH_AUTH_SOCK" >&2
  unset SSH_AUTH_SOCK
fi

:
