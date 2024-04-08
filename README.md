# Dotfiles

My configuration files for bash, neovim, tmux and so forth.

The intention is to be able to run a setup script after cloning the repo on Ubuntu (WSL) system (or any linux) and be up and running very quickly.

# Setup Notes

```bash
mv ~/.bashrc ~/bashrc_backup
mv ~/.bash_profile ~/bash_profile_backup
mv ~/.bash_aliases ~/bash_aliases_backup

ssh-keygen -t rsa -b 4096 -C "122265380+surbanski-nr@users.noreply.github.com" -f ~/.ssh/github
cat ~/.ssh/github.pub
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/github

## Homebrew
sudo apt install build-essential procps curl file git

/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
/home/linuxbrew/.linuxbrew/bin/brew install stow

-- optionally if you forgot about brew dependencies: brew reinstall gcc

## Stow
GH_REPOS=$HOME/github.com/surbanski
mkdir -p $GH_REPOS
git clone git@github.com:surbanski-nr/notes-md.git $GH_REPOS/notes-md
git clone git@github.com:surbanski-nr/dotfiles.git $GH_REPOS/dotfiles

cd $GH_REPOS/dotfiles
/home/linuxbrew/.linuxbrew/bin/stow -vvv -t ~ git
/home/linuxbrew/.linuxbrew/bin/stow -vvv -t ~ tmux
/home/linuxbrew/.linuxbrew/bin/stow -vvv -t ~ bash
/home/linuxbrew/.linuxbrew/bin/stow -vvv -t ~ oh-my-posh
mkdir -p ~/.config/k9s && /home/linuxbrew/.linuxbrew/bin/stow -vvv -t ~ k9s
mkdir -p ~/.config/nvim && /home/linuxbrew/.linuxbrew/bin/stow -vvv -t ~ nvim
mkdir -p ~/.gnupg && /home/linuxbrew/.linuxbrew/bin/stow -vvv -t ~ gnupg

-- On Ubuntu Desktop
mkdir -p ~/.config/kitty && /home/linuxbrew/.linuxbrew/bin/stow -vvv -t ~ kitty

## Tmux
git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm

## Tools
brew update && brew upgrade
brew install jandedobbeleer/oh-my-posh/oh-my-posh
brew install tmux
brew install neovim
brew install dos2unix
brew install asdf
brew install fzf
brew install ripgrep
brew install bat
brew install fd
brew install xclip
brew install zoxide
#brew install exa -- no longer maintained

brew install gcc
brew install make
brew install vim
brew install htop
brew install pass
brew install gnupg
brew install pwgen
brew install krew
brew install tree
brew install mc
brew install kubectx
brew install coreutils
brew install awscli
brew install azure-cli
brew tap hashicorp/tap
brew install hashicorp/tap/terraform
brew install terragrunt
brew install helm
brew install k9s
brew install docker
brew install docker-compose
brew install lazygit
brew install gh
brew install gcc
brew install unzip
brew install gpg
brew install gawk
brew install podman
brew install podman-compose
brew install libnotify # for pomodoro

# post brew installation
$(brew --prefix)/opt/fzf/install
git clone git@github.com:surbanski-nr/secrets.git ~/.password-store

# for podman
sudo apt install uidmap

# for pass
sudo apt install wl-clipboard

# for tools where I use multiple versions of
asdf plugin add kubectl https://github.com/asdf-community/asdf-kubectl.git
asdf install kubectl 1.27.11
asdf global kubectl 1.27.11

asdf plugin add golang https://github.com/asdf-community/asdf-golang.git
asdf install golang latest
asdf global golang latest

asdf plugin add nodejs https://github.com/asdf-vm/asdf-nodejs.git
asdf install nodejs latest
asdf global nodejs latest
```
