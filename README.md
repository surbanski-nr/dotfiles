# Dotfiles

My configuration files for bash, neovim, tmux and so forth.

The intention is to be able to run a setup script after cloning the repo on Ubuntu (WSL) system (or any linux) and be up and running very quickly.

Homebrew is still an option, but it is intended as a last resort. Prefer distro package manager (`apt`, `dnf`/`yum`) for most tools.

## Setup Notes

### Backup existing files (optional)

```bash
mv ~/.bashrc ~/bashrc_backup
mv ~/.bash_profile ~/bash_profile_backup
mv ~/.bash_aliases ~/bash_aliases_backup
```

### SSH key for GitHub (optional)

```bash
ssh-keygen -t rsa -b 4096 -C "122265380+surbanski-nr@users.noreply.github.com" -f ~/.ssh/github
cat ~/.ssh/github.pub
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/github
```

### Install dependencies (preferred: apt/dnf/yum)

Ubuntu / Debian:

```bash
sudo apt update
sudo apt install -y \
  git stow curl unzip coreutils \
  gcc make ripgrep fd-find xclip neovim
```

Fedora / RHEL (dnf/yum):

```bash
sudo dnf install -y \
  git stow curl unzip coreutils \
  gcc make ripgrep fd-find neovim
```

Note: on Debian/Ubuntu, the `fd-find` package installs the `fdfind` binary. If you need `fd` in `PATH`:

```bash
mkdir -p ~/bin
ln -sf "$(command -v fdfind)" ~/bin/fd
```

### Oh My Posh

Dependencies: `curl`, `unzip`, `realpath`, `dirname` (`realpath`/`dirname` come from `coreutils` on most distros).

```bash
mkdir -p ~/bin
curl -s https://ohmyposh.dev/install.sh | bash -s -- -d ~/bin
```

### Clone and stow

```bash
GH_REPOS=$HOME/github.com/surbanski
mkdir -p $GH_REPOS
git clone git@github.com:surbanski-nr/notes-md.git $GH_REPOS/notes-md
git clone git@github.com:surbanski-nr/dotfiles.git $GH_REPOS/dotfiles

cd $GH_REPOS/dotfiles
stow -vvv -t ~ git
stow -vvv -t ~ tmux
stow -vvv -t ~ bash
stow -vvv -t ~ oh-my-posh
mkdir -p ~/.config/k9s && stow -vvv -t ~ k9s
mkdir -p ~/.config/nvim && stow -vvv -t ~ nvim
mkdir -p ~/.config/nvim2 && stow -vvv -t ~/.config/nvim2 nvim2
mkdir -p ~/.gnupg && stow -vvv -t ~ gnupg

# On Ubuntu Desktop
mkdir -p ~/.config/kitty && stow -vvv -t ~ kitty
```

### Tmux plugins

```bash
git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
```

### asdf

Ubuntu / Debian dependencies:

```bash
sudo apt install -y dirmngr gpg curl gawk
```

Example plugin setup:

```bash
asdf plugin add kubectl https://github.com/asdf-community/asdf-kubectl.git
asdf list all kubectl
asdf install kubectl 1.33
asdf global kubectl 1.33

asdf plugin add golang https://github.com/asdf-community/asdf-golang.git
asdf install golang latest
asdf global golang latest

asdf plugin add nodejs https://github.com/asdf-vm/asdf-nodejs.git
asdf install nodejs latest
asdf global nodejs latest

asdf plugin add python https://github.com/asdf-community/asdf-python.git
asdf list all python
asdf install python latest
asdf global python latest
```

### Optional: Homebrew (fallback only)

If your distro packages are missing or too old for a specific tool:

```bash
# Ubuntu / Debian dependencies for linuxbrew
sudo apt install -y build-essential procps curl file git

/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Follow the linuxbrew "brew shellenv" output after install.
```

### For issues when stow cannot be installed

```bash
ln -sv "$PWD/git/.gitconfig" ~
ln -sv "$PWD/tmux/.tmux.conf" ~
ln -sv "$PWD/bash/.bash_profile" ~
ln -sv "$PWD/bash/.bashrc" ~
ln -sv "$PWD/bash/.bash_aliases" ~
ln -sv "$PWD/oh-my-posh/.oh-my-posh.omp.json" ~

mkdir -p ~/.config
ln -sv "$PWD/k9s/.config/k9s" ~/.config/k9s
ln -sv "$PWD/kitty/.config/kitty" ~/.config/kitty
ln -sv "$PWD/nvim/.config/nvim" ~/.config/nvim
ln -sv "$PWD/nvim2" ~/.config/nvim2

mkdir -p ~/.gnupg
ln -sv "$PWD/gnupg/.gnupg/gpg-agent.conf" ~/.gnupg/gpg-agent.conf

```

### Fixing asdf shim issues (after upgrades)

```bash
asdf reshim
```
