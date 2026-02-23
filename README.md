# Dotfiles

My configuration files for bash, neovim, tmux and so forth.

The intention is to be able to run a setup script after cloning the repo on Ubuntu (WSL) system (or any linux) and be up and running very quickly.

Homebrew is still an option, but it is intended as a last resort. Prefer distro package manager (`apt`, `dnf`/`yum`) for most tools. Symlinks are managed by `./bstow` (a bash-based stow replacement included in this repo) -- no need to install GNU `stow`.

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
  gcc make \
  neovim ripgrep fd-find xclip \
  tmux dos2unix fzf bat zoxide htop tree mc \
  gnupg
```

Fedora / RHEL (dnf/yum):

```bash
sudo dnf install -y \
  git stow curl unzip coreutils \
  gcc make \
  neovim ripgrep fd-find xclip \
  tmux dos2unix fzf bat zoxide htop tree mc \
  gnupg2
```

Amazon Linux:

```bash
sudo dnf install -y \
  git curl unzip coreutils \
  gcc make \
  tmux dos2unix htop tree mc
```

On Amazon Linux many tools are not in the repos (`neovim`, `ripgrep`, `fd`, `bat`, `zoxide`, `kubectx`). Install them via Homebrew or manual methods described below.

Note: on Debian/Ubuntu, the `fd-find` package installs the `fdfind` binary. If you need `fd` in `PATH`:

```bash
mkdir -p ~/bin
ln -sf "$(command -v fdfind)" ~/bin/fd
```

Note: on Debian/Ubuntu, `bat` is sometimes installed as `batcat`. If you need `bat` in `PATH`:

```bash
mkdir -p ~/bin
ln -sf "$(command -v batcat)" ~/bin/bat
```

### Optional: Homebrew (fallback for missing tools)

Requires internet access. If you're on a restricted network, see [Restricted network](#restricted-network-no-internet-access) below.

Ubuntu / Debian:

```bash
sudo apt-get install -y build-essential procps curl file git
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
# Follow the "brew shellenv" output after install.
```

Amazon Linux (standard installer may not work):

```bash
export HOMEBREW_NO_INSTALL_FROM_API=1
mkdir homebrew && curl -L https://github.com/Homebrew/brew/tarball/main | tar xz --strip-components 1 -C homebrew
eval "$(homebrew/bin/brew shellenv)"
brew update --force --verbose --debug
```

Install tools via Homebrew (only when missing in `apt`/`dnf`):

```bash
brew update && brew upgrade
brew install asdf k9s kubeconform krew helm terragrunt kind
brew tap hashicorp/tap
brew install hashicorp/tap/terraform

# Amazon Linux only (not in dnf repos):
brew install neovim fd ripgrep bat
```

### zoxide (when not in repos)

```bash
curl -sSfL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | sh
```

### kubectx / kubens (when not in repos)

Not available in `apt` on Debian/Ubuntu or `dnf` on Amazon Linux. Install manually:

```bash
sudo git clone https://github.com/ahmetb/kubectx /opt/kubectx
mkdir -p ~/bin
sudo ln -s /opt/kubectx/kubectx ~/bin/kubectx
sudo ln -s /opt/kubectx/kubens ~/bin/kubens
```

### Oh My Posh

Dependencies: `curl`, `unzip`, `realpath`, `dirname` (`realpath`/`dirname` come from `coreutils` on most distros).

```bash
mkdir -p ~/bin
curl -s https://ohmyposh.dev/install.sh | bash -s -- -d ~/bin
```

On a restricted network, download the binary from [GitHub releases](https://github.com/JanDeDobbeleer/oh-my-posh/releases) on another machine and copy it to `~/bin/oh-my-posh`.

### Clone and stow

```bash
GH_REPOS=$HOME/github.com/surbanski
mkdir -p $GH_REPOS
git clone git@github.com:surbanski-nr/notes-md.git $GH_REPOS/notes-md
git clone git@github.com:surbanski-nr/dotfiles.git $GH_REPOS/dotfiles
# Without SSH key: git clone https://github.com/surbanski-nr/dotfiles.git $GH_REPOS/dotfiles

cd $GH_REPOS/dotfiles
./bstow -v -t ~ stow git
./bstow -v -t ~ stow tmux
./bstow -v -t ~ stow bash
./bstow -v -t ~ stow oh-my-posh
./bstow -v -t ~ stow k9s
./bstow -v -t ~ stow nvim2
./bstow -v -t ~ stow gnupg

# On Ubuntu Desktop
./bstow -v -t ~ stow kitty
```

### Tmux

Install TPM (plugin manager):

```bash
git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
```

Quick reference (prefix is `Ctrl+a`):

| Action | Keys |
|---|---|
| Reload config | `Ctrl+a` then `:source-file ~/.tmux.conf` |
| Install plugins | `Ctrl+a` then `Shift+I` |
| Update plugins | `Ctrl+a` then `Shift+U` |

Or reload from the shell: `tmux source-file ~/.tmux.conf`

### asdf

Ubuntu / Debian dependencies:

```bash
sudo apt install -y dirmngr gpg curl gawk
```

Example plugin setup:

Since v0.16.0 `asdf global` is replaced by `asdf set`. Use `asdf list all <name>` to browse available versions.

```bash
asdf plugin add kubectl https://github.com/asdf-community/asdf-kubectl.git
asdf list all kubectl
asdf install kubectl 1.33.7
asdf set -u kubectl 1.33.7

asdf plugin add golang https://github.com/asdf-community/asdf-golang.git
asdf install golang latest
asdf set -u golang latest

asdf plugin add nodejs https://github.com/asdf-vm/asdf-nodejs.git
asdf install nodejs latest
asdf set -u nodejs latest

asdf plugin add python https://github.com/asdf-community/asdf-python.git
asdf list all python
asdf install python latest
asdf set -u python latest
```

The `-u` flag writes to `~/.tool-versions` (user-wide default, equivalent to the old `asdf global`).

### krew (kubectl plugin manager)

Install krew (requires internet):

```bash
(
  set -x; cd "$(mktemp -d)" &&
  OS="$(uname | tr '[:upper:]' '[:lower:]')" &&
  ARCH="$(uname -m | sed -e 's/x86_64/amd64/' -e 's/\(arm\)\(64\)\?.*/\1\2/' -e 's/aarch64$/arm64/')" &&
  KREW="krew-${OS}_${ARCH}" &&
  curl -fsSLO "https://github.com/kubernetes-sigs/krew/releases/latest/download/${KREW}.tar.gz" &&
  tar zxvf "${KREW}.tar.gz" &&
  ./"${KREW}" install krew
)
```

Make sure `~/.krew/bin` is in your `PATH`. Then install plugins:

```bash
kubectl krew install cnpg
```

On a restricted network, download the krew tarball and plugin archives on another machine and transfer them over. See [Restricted network](#restricted-network-no-internet-access).

### Restricted network (no internet access)

On environments without open internet (e.g. corporate Amazon Linux instances), Homebrew and install scripts won't work. Download binaries on a machine with internet access and `scp`/copy them over.

```bash
mkdir -p ~/bin
```

kubectl:

```bash
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl
sudo mv kubectl /usr/local/bin/
```

helm:

```bash
curl -LO https://get.helm.sh/helm-v3.17.3-linux-amd64.tar.gz
tar -zxvf helm-v3.17.3-linux-amd64.tar.gz
sudo mv linux-amd64/helm /usr/local/bin/helm
```

k9s:

```bash
curl -LO https://github.com/derailed/k9s/releases/download/v0.50.2/k9s_Linux_amd64.tar.gz
tar -zxvf k9s_Linux_amd64.tar.gz
sudo mv k9s /usr/local/bin/k9s
```

yq:

```bash
sudo wget https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -O /usr/local/bin/yq
sudo chmod 755 /usr/local/bin/yq
```

trivy:

```bash
curl -LO https://github.com/aquasecurity/trivy/releases/download/v0.55.2/trivy_0.55.2_Linux-64bit.tar.gz
tar zxf trivy_0.55.2_Linux-64bit.tar.gz
sudo mv trivy /usr/local/bin/
```

minikube:

```bash
curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
sudo install minikube-linux-amd64 /usr/local/bin/minikube
```

oh-my-posh -- download from [GitHub releases](https://github.com/JanDeDobbeleer/oh-my-posh/releases), then:

```bash
chmod +x posh-linux-amd64
mv posh-linux-amd64 ~/bin/oh-my-posh
```

### Manual symlinks (fallback if bstow is unavailable)

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
