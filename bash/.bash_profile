if [ -f ~/.bashrc ]; then
	source ~/.bashrc
fi

export PATH="$HOME/.asdf/shims:${KREW_ROOT:-$HOME/.krew}/bin:$HOME/.local/share/nvim/mason/bin:$DOTFILES/scripts:$HOME/.local/bin:$HOME/bin:$PATH"
if [ -z "$XDG_CONFIG_HOME" ]; then
	export XDG_CONFIG_HOME="$HOME/.config"
fi

if [ -z "$SSH_AUTH_SOCK" ]; then
	eval "$(ssh-agent -s)" >/dev/null 2>&1
	ssh-add ~/.ssh/github >/dev/null 2>&1
fi
