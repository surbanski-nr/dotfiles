export PATH="$HOME/.local/bin:$HOME/bin:$PATH"

if [ -f ~/.bashrc ]; then
    source ~/.bashrc
fi

if [ -z "$XDG_CONFIG_HOME" ]; then
    export XDG_CONFIG_HOME="$HOME/.config"
fi

if [ -z "$SSH_AUTH_SOCK" ]; then
    eval "$(ssh-agent -s)"
	ssh-add ~/.ssh/github
fi
