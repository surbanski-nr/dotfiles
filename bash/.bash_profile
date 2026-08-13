# shellcheck shell=bash

if [ -z "${XDG_CONFIG_HOME:-}" ]; then
  export XDG_CONFIG_HOME="$HOME/.config"
fi

if [ -f ~/.bashrc ]; then
  source ~/.bashrc
fi

_dotfiles_profile_warn() {
  printf 'dotfiles: %s\n' "$*" >&2
}

if [[ -n ${SSH_AUTH_SOCK:-} && ! -S ${SSH_AUTH_SOCK} ]]; then
  _dotfiles_profile_warn "SSH_AUTH_SOCK is not a socket: $SSH_AUTH_SOCK"
  unset SSH_AUTH_SOCK
fi

if [[ -z ${SSH_AUTH_SOCK:-} ]] &&
  command -v ssh-agent >/dev/null 2>&1 &&
  command -v ssh-add >/dev/null 2>&1 &&
  [[ -r $HOME/.ssh/github ]]; then
  if agent_environment=$(ssh-agent -s 2>/dev/null); then
    if eval "$agent_environment" >/dev/null 2>&1 &&
      [[ -n ${SSH_AGENT_PID:-} && -n ${SSH_AUTH_SOCK:-} ]]; then
      if ! ssh_add_error=$(ssh-add "$HOME/.ssh/github" 2>&1); then
        ssh_add_error=${ssh_add_error%%$'\n'*}
        _dotfiles_profile_warn "failed to add ~/.ssh/github: ${ssh_add_error:-unknown error}"
        ssh-agent -k >/dev/null 2>&1 || true
        unset SSH_AGENT_PID SSH_AUTH_SOCK
      fi
    else
      _dotfiles_profile_warn 'ssh-agent returned an invalid environment'
      if [[ -n ${SSH_AGENT_PID:-} ]]; then
        ssh-agent -k >/dev/null 2>&1 || true
      fi
      unset SSH_AGENT_PID SSH_AUTH_SOCK
    fi
  else
    _dotfiles_profile_warn 'failed to start ssh-agent'
    unset SSH_AGENT_PID SSH_AUTH_SOCK
  fi
fi

unset agent_environment ssh_add_error
unset -f _dotfiles_profile_warn
:
