if [ -f ~/.bashrc ]; then
  source ~/.bashrc
fi

if [ -z "$XDG_CONFIG_HOME" ]; then
  export XDG_CONFIG_HOME="$HOME/.config"
fi

if [ -z "$SSH_AUTH_SOCK" ] && command -v ssh-agent >/dev/null 2>&1 && command -v ssh-add >/dev/null 2>&1 && [ -r "$HOME/.ssh/github" ]; then
  eval "$(ssh-agent -s)" >/dev/null 2>&1
  ssh-add "$HOME/.ssh/github" >/dev/null 2>&1
fi
