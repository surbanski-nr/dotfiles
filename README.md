# Dotfiles

My configuration files for bash, neovim, tmux and so forth.

The setup targets WSL Ubuntu, regular Ubuntu, Amazon Linux and Rocky Linux.

Homebrew is still an option, but it is intended as a last resort. Prefer distro package manager (`apt`, `dnf`/`yum`) for most tools. Symlinks are managed by `./bstow` (a bash-based stow replacement included in this repo) -- no need to install GNU `stow`.

## New VM quick start

Use this order on a machine with internet access:

1. Install the packages for the VM's distribution from
   [Install dependencies](#install-dependencies-preferred-aptdnfyum).
2. Check that Neovim is version 0.12 or newer. If the distribution package is
   older, use [Install Neovim 0.12](#install-neovim-012).
3. Back up any existing dotfiles that would conflict with the symlinks.
4. Clone and stow the main packages:

   ```bash
   GH_REPOS="$HOME/github.com/surbanski"
   mkdir -p "$GH_REPOS"
   git clone https://github.com/surbanski-nr/dotfiles.git "$GH_REPOS/dotfiles"
   cd "$GH_REPOS/dotfiles"
   ./bstow -v -t "$HOME" stow bash git tmux oh-my-posh nvim2
   source ~/.bashrc
   ```

5. Install the pinned Nvim2 plugins, Mason tools and Treesitter parsers. The
   command can take several minutes and requires access to GitHub and the
   package registries used by Mason:

   ```bash
   cd "$GH_REPOS/dotfiles"
   timeout 600s env NVIM_APPNAME=nvim2 \
     nvim --headless '+Nvim2ToolsInstallSync' '+qa!'
   ```

   `Nvim2ToolsInstallSync` already runs `MasonToolsInstallSync`; do not run the
   latter separately. Start `nvim`, then use `:checkhealth kickstart`,
   `:checkhealth vim.lsp`, `:Mason` and `:ConformInfo` to inspect the result.
   Install `ansible-core` from the distro package manager when working on
   Ansible projects. Terraform, Helm and Docker CLIs remain project-level
   dependencies rather than editor dependencies.

6. Optionally install TPM and its tmux plugins as described under
   [Tmux](#tmux). Plain tmux works without TPM.

The remaining sections explain each step, optional tools and restricted-network
setup in more detail.

## Detailed setup

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
  git curl unzip coreutils \
  gcc make \
  python3 python3-venv python3-pip nodejs npm \
  neovim ripgrep fd-find xclip \
  tmux dos2unix fzf bat zoxide htop tree mc \
  gnupg
```

Fedora / RHEL (dnf/yum):

On Rocky/RHEL, enable EPEL first when packages such as `fzf`, `fd-find`,
`bat` or `zoxide` are unavailable:

```bash
sudo dnf install -y epel-release
```

```bash
sudo dnf install -y \
  git curl unzip coreutils \
  gcc make \
  python3 python3-pip nodejs npm \
  neovim ripgrep fd-find xclip \
  tmux dos2unix fzf bat zoxide htop tree mc \
  gnupg2
```

Amazon Linux:

```bash
sudo dnf install -y \
  git curl unzip coreutils \
  gcc make \
  python3 python3-pip nodejs npm \
  tmux dos2unix htop tree mc
```

On Amazon Linux many tools are not in the repos (`neovim`, `ripgrep`, `fd`, `bat`, `zoxide`, `kubectx`). Install them via Homebrew or manual methods described below.

Mason needs `node`/`npm` for Node-based language servers and Python with
virtual-environment support for Python-based tools. Package names can vary on
older Amazon Linux and Rocky releases.

### Install Neovim 0.12

Nvim2 requires Neovim 0.12 or newer. The version supplied by `apt` or `dnf`
may be too old; check it before continuing:

```bash
nvim --version | head -n 1
```

If necessary, install the pinned official Neovim 0.12.0 archive under your
home directory. This supports x86-64 and ARM64 Linux without writing to
`/usr/local`:

```bash
version=v0.12.0
case "$(uname -m)" in
  x86_64) asset=nvim-linux-x86_64.tar.gz ;;
  aarch64) asset=nvim-linux-arm64.tar.gz ;;
  *) printf 'Unsupported architecture: %s\n' "$(uname -m)" >&2; exit 1 ;;
esac

install_dir="$HOME/.local/opt/nvim-$version"
mkdir -p "$install_dir" "$HOME/bin"
curl -fL "https://github.com/neovim/neovim/releases/download/$version/$asset" \
  -o "/tmp/$asset"
tar -xzf "/tmp/$asset" -C "$install_dir" --strip-components=1
ln -sfn "$install_dir/bin/nvim" "$HOME/bin/nvim"
"$HOME/bin/nvim" --version | head -n 1
```

The stowed Bash configuration puts `~/bin` on `PATH`.

### Portability notes

The Bash, Git and tmux files use Bash and GNU/Linux conventions and are
portable across WSL Ubuntu, regular Ubuntu, Amazon Linux and Rocky Linux. The
configuration checks before loading optional desktop and CLI integrations;
missing tools affect only their related aliases or workflows.

- Bash 4 or newer is required. `ff` supports both the Fedora/RHEL `fd` command
  and Debian/Ubuntu's `fdfind`, with GNU `find` as a fallback. `ff` and `ffv`
  still require `fzf` when invoked.
- Git over HTTPS uses `gh auth git-credential`, so install and authenticate
  GitHub CLI when that transport is needed. Repositories using Git LFS require
  `git-lfs`. SSH Git remotes need neither helper.
- Tmux should provide the `tmux-256color` terminfo entry. Check it with
  `infocmp tmux-256color`; install the distro's `ncurses-term` package if it is
  missing. Current Ubuntu, Amazon Linux 2023 and Rocky 9 packages are
  compatible; Amazon Linux 2 and Rocky 8 may need newer tmux/terminfo packages.
- TPM is optional for starting tmux, but resurrect and continuum require it.
  Install or transfer TPM and its plugin directories before using those
  features on a restricted machine.

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
| Scroll through pane history | Mouse wheel |
| Enter tmux copy mode | `Ctrl+a` then `[` |
| Start a copy-mode selection | Press `v`, then move the cursor |
| Copy selection to tmux's buffer | Press `y` |
| Paste tmux's buffer | `Ctrl+a` then `]` |
| Select text for terminal copy | Hold `Shift` and drag |
| Copy selected text | `Ctrl+Shift+C` |
| Paste text | `Ctrl+Shift+V` |

Or reload from the shell: `tmux source-file ~/.tmux.conf`

Tmux mouse handling is enabled for pane focus and scrollback. Automatic
copy-on-select remains disabled. Hold `Shift` while selecting text to let the
terminal handle selection, then use `Ctrl+Shift+C` or `Ctrl+Shift+V`.

The `v` and `y` copy-mode bindings use tmux's own buffer, not the terminal's
system clipboard. After pressing `y`, paste it with `Ctrl+a` then `]`, or run
`tmux paste-buffer`. Terminal `Ctrl+Shift+C` and `Ctrl+Shift+V` remain a
separate workflow because `set-clipboard` is disabled.

### Neovim

The `nvim2` profile is the default development editor. Bash exports
`NVIM_APPNAME=nvim2`, `EDITOR=nvim` and `VISUAL=nvim`; `nvim`, `vim`, `vi`, `v`
and `ffv` therefore open Nvim2. `ffv` safely opens one or more files selected
with FZF, including paths containing spaces. Use `vn` to explicitly open the
older `~/.config/nvim` profile or `vz` for `nvim-lazy`.
See [the Neovim profile documentation](docs/neovim-nvchad-to-kickstart.md) for
language tooling, installation, and key mappings.

Updates are intentionally manual. For plugins, run
`:lua vim.pack.update()` on a trusted connected machine, review the proposed
commits, and use `:write` to apply them and rewrite `nvim-pack-lock.json`. For
Mason tools, update the exact version in `nvim2/.config/nvim2/init.lua`, restart
Neovim, and run `:Nvim2ToolsInstallSync`; there is no separate Mason lockfile.
See [Plugin and configuration maintenance](nvim2/.config/nvim2/README.md#plugin-and-configuration-maintenance)
for the complete review, verification and restricted-VM workflow.

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
export PATH="$HOME/bin:$PATH"
```

kubectl:

```bash
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
install -m 0755 kubectl ~/bin/kubectl
```

helm:

```bash
curl -LO https://get.helm.sh/helm-v3.17.3-linux-amd64.tar.gz
tar -zxvf helm-v3.17.3-linux-amd64.tar.gz
install -m 0755 linux-amd64/helm ~/bin/helm
```

k9s:

```bash
curl -LO https://github.com/derailed/k9s/releases/download/v0.50.2/k9s_Linux_amd64.tar.gz
tar -zxvf k9s_Linux_amd64.tar.gz
install -m 0755 k9s ~/bin/k9s
```

yq:

```bash
curl -L https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -o ~/bin/yq
chmod 0755 ~/bin/yq
```

trivy:

```bash
curl -LO https://github.com/aquasecurity/trivy/releases/download/v0.55.2/trivy_0.55.2_Linux-64bit.tar.gz
tar zxf trivy_0.55.2_Linux-64bit.tar.gz
install -m 0755 trivy ~/bin/trivy
```

minikube:

```bash
curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
install -m 0755 minikube-linux-amd64 ~/bin/minikube
```

oh-my-posh -- download from [GitHub releases](https://github.com/JanDeDobbeleer/oh-my-posh/releases), then:

```bash
install -m 0755 posh-linux-amd64 ~/bin/oh-my-posh
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
