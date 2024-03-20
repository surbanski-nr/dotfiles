# Dotfiles

My configuration files for bash, neovim, tmux and so forth.

The intention is to be able to run a setup script after cloning the repo on Ubuntu (WSL) system (or any linux) and be up and running very quickly.

# Setup Notes

```bash
mv ~/.bashrc ~/bashrc_backup
mv ~/.bash_profile ~/bash_profile_backup
mv ~/.bash_aliases ~/bash_aliases_backup

ssh-keygen -t rsa -b 4096 -C "122265380+surbanski-nr@users.noreply.github.com"
cat .ssh/github.pub
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/github

GH_REPOS=$HOME/github.com/surbanski
mkdir -p $GH_REPOS
git clone git@github.com:surbanski-nr/notes-md.git $GH_REPOS/notes-md
git clone git@github.com:surbanski-nr/dotfiles.git $GH_REPOS/dotfiles

/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
/home/linuxbrew/.linuxbrew/bin/brew install stow

cd $GH_REPOS/dotfiles
stow -vvv -t ~ git
stow -vvv -t ~ tmux
stow -vvv -t ~ bash
stow -vvv -t ~ oh-my-posh
mkdir -p ~/.config/k9s && stow -vvv -t ~ k9s
mkdir -p ~/.config/nvim && stow -vvv -t ~ nvim

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

brew install krew
brew install tree
brew install mc
brew install kubectx
brew install coreutils
brew install awscli
brew install azure-cli
brew install terraform
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

# post brew installation
$(brew --prefix)/opt/fzf/install

# for podman
sudo apt install uidmap
# for nvim
sudo apt install g++


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
