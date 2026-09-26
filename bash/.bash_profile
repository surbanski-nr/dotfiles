# shellcheck shell=bash

if [ -z "${XDG_CONFIG_HOME:-}" ]; then
  export XDG_CONFIG_HOME="$HOME/.config"
fi

if [ -f ~/.bashrc ]; then
  # shellcheck source=.bashrc
  source ~/.bashrc
fi

_dotfiles_profile_warn() {
  printf 'dotfiles: %s\n' "$*" >&2
}

if [[ -n ${SSH_AUTH_SOCK:-} && ! -S ${SSH_AUTH_SOCK} ]]; then
  _dotfiles_profile_warn "SSH_AUTH_SOCK is not a socket: $SSH_AUTH_SOCK"
  unset SSH_AUTH_SOCK
fi

unset -f _dotfiles_profile_warn
:
