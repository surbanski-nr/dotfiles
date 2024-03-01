
if [[ "$OSTYPE" == "darwin"* ]]; then
	eval "$(/opt/homebrew/bin/brew shellenv)"
fi

if [[ $(grep -E "^(ID|NAME)=" /etc/os-release | grep -q "ubuntu")$? == 0 ]]; then
	eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
fi

if [ -r ~/.bashrc ]; then
	source ~/.bashrc
fi

export XDG_CONFIG_HOME="$HOME"/.config

#export PATH="/opt/homebrew/opt/postgresql@15/bin:$PATH"
