# Dotfiles

Configuration for my Bash, Git, tmux, Nvim2, Midnight Commander, Oh My Posh,
k9s and Codex. The supported targets are WSL Ubuntu, regular Ubuntu, Amazon
Linux 2023 and Rocky Linux.

Prefer the distribution package manager for system tools. Use asdf on
connected machines when a project needs an exact Python, Node.js, Kubernetes
or infrastructure-tool version. Neovim is deliberately installed separately
as a reviewed release under `~/.local/opt` and exposed through `~/bin/nvim`.

`./bstow` manages the symlinks. GNU Stow is not required.

## Set up a connected VM

Follow these steps in order.

### 1. Back up conflicting files

`bstow` never replaces regular files. Preserve any existing configuration
before installing the packages:

```bash
backup_dir="$HOME/dotfiles-backup/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$backup_dir"
for file in .bashrc .bash_profile .bash_aliases .gitconfig .tmux.conf; do
  if [[ -e "$HOME/$file" || -L "$HOME/$file" ]]; then
    mv "$HOME/$file" "$backup_dir/$file"
  fi
done
```

Also back up existing `~/.config/nvim2`, `~/.config/k9s`, `~/.config/mc/ini`,
`~/.oh-my-posh.omp.json` and `~/.codex/AGENTS.md` when they are regular files or
belong to another dotfiles repository.

### 2. Install operating-system packages

Ubuntu or Debian:

```bash
sudo apt update
sudo apt install -y \
  git curl wget ca-certificates openssh-client tar gzip unzip xz-utils coreutils \
  gcc g++ make \
  python3 python3-venv python3-pip nodejs npm \
  ripgrep fd-find iproute2 xclip \
  tmux dos2unix fzf bat zoxide htop tree mc \
  gnupg
```

Rocky, RHEL or Fedora:

```bash
sudo dnf install -y epel-release
sudo dnf install -y \
  git curl wget ca-certificates openssh-clients tar gzip unzip xz coreutils \
  gcc gcc-c++ make \
  python3 python3-pip nodejs npm \
  ripgrep fd-find iproute xclip \
  tmux dos2unix fzf bat zoxide htop tree mc \
  gnupg2
```

Amazon Linux 2023:

```bash
sudo dnf install -y \
  git wget ca-certificates openssh-clients \
  tar gzip unzip xz \
  gcc gcc-c++ make \
  python3.12 python3.12-pip \
  cargo clang-devel \
  iproute tmux dos2unix htop tree mc \
  findutils which patch
```

Amazon Linux 2023 already supplies `curl`, coreutils and GnuPG through either
its minimal or full packages. Do not request the other variant because DNF
would report a conflict. Its packaged Node.js 18 is
also too old for the pinned TypeScript language server, and ripgrep is absent.
Install a current Node.js with asdf in step 5. Follow the
[platform release runbook](docs/nvim2-platform-releases.md#install-nodejs-and-ripgrep-in-the-builder)
to install a checksum-verified ripgrep release in `~/bin`, or follow the whole
runbook to build a complete offline Nvim2 release.

Amazon Linux 2 reached its public support end date on 2026-06-30 and is not a
supported Nvim2 release target.

Python and Node.js are Nvim2 runtime dependencies, not only installation
dependencies:

- Node.js runs Pyright, Prettier, Eslint_d and the configured TypeScript, Bash,
  YAML, HTML, CSS, JSON and Ansible language servers.
- Python runs the Mason virtual environments for Yamllint and Ansible-lint.
- Compiled Treesitter parsers, Lua plugins and native tools such as Ruff,
  ShellCheck and Shfmt do not need either runtime by themselves.

Copying a completed Mason directory does not remove these runtime requirements.

On Debian and Ubuntu, `fd-find` and `bat` may install as `fdfind` and `batcat`.
The Bash configuration recognizes both names. Optional compatibility links are:

```bash
mkdir -p "$HOME/bin"
command -v fdfind >/dev/null && ln -sfn "$(command -v fdfind)" "$HOME/bin/fd"
command -v batcat >/dev/null && ln -sfn "$(command -v batcat)" "$HOME/bin/bat"
```

### 3. Configure GitHub access

This step is optional when HTTPS access is already configured:

```bash
ssh-keygen -t ed25519 \
  -C "122265380+surbanski-nr@users.noreply.github.com" \
  -f "$HOME/.ssh/github"
cat "$HOME/.ssh/github.pub"
eval "$(ssh-agent -s)"
ssh-add "$HOME/.ssh/github"
```

Add the public key to GitHub and verify access before cloning:

```bash
ssh -T git@github.com
```

### 4. Clone and stow the repository

```bash
GH_REPOS="$HOME/github.com/surbanski"
mkdir -p "$GH_REPOS"
git clone git@github.com:surbanski-nr/dotfiles.git "$GH_REPOS/dotfiles"
# Without an SSH key:
# git clone https://github.com/surbanski-nr/dotfiles.git "$GH_REPOS/dotfiles"

cd "$GH_REPOS/dotfiles"
./bstow --dry-run -v -t "$HOME" stow \
  git tmux bash mc oh-my-posh k9s nvim2 gnupg codex
./bstow -v -t "$HOME" stow \
  git tmux bash mc oh-my-posh k9s nvim2 gnupg codex

# Ubuntu desktop only:
./bstow --dry-run -v -t "$HOME" stow kitty
./bstow -v -t "$HOME" stow kitty

source "$HOME/.bashrc"
hash -r
```

Midnight Commander starts with `mc`. Its managed INI contains the daily key
reference. The Bash profile loads the distribution wrapper when available, so
F10 returns the shell to MC's final directory; Shift+F10 keeps the directory
where MC started. The package manages only `~/.config/mc/ini` and the `surb`
skin. MC owns mutable `panels.ini` and history files locally; keep them as
regular files rather than stowing them.

K9s uses the managed `surb` skin under `~/.config/k9s/skins/`, matching Nvim2's
dark background, white text and green primary accents.

The normal setup does not install `old-nvim`. It is an unsupported archive of
the previous NvChad profile.

### 5. Install connected-machine runtimes with asdf

This step is optional when approved operating-system packages already provide
the required versions. It is useful when projects require different versions.
Install the latest reviewed asdf release in `~/bin`. Set
`ASDF_VERSION=vX.Y.Z` first to reproduce an older reviewed release:

```bash
asdf_version=${ASDF_VERSION:-$(
  curl -fsSL https://api.github.com/repos/asdf-vm/asdf/releases/latest |
    python3 -c 'import json, sys; print(json.load(sys.stdin)["tag_name"])'
)}
case "$(uname -m)" in
  x86_64) asdf_arch=amd64 ;;
  aarch64) asdf_arch=arm64 ;;
  *) printf 'Unsupported architecture: %s\n' "$(uname -m)" >&2; exit 1 ;;
esac
asdf_asset="asdf-$asdf_version-linux-$asdf_arch.tar.gz"
asdf_digest=$(
  curl -fsSL \
    "https://api.github.com/repos/asdf-vm/asdf/releases/tags/$asdf_version" |
    ASSET="$asdf_asset" python3 -c '
import json, os, sys
assets = json.load(sys.stdin)["assets"]
print(next(item["digest"] for item in assets if item["name"] == os.environ["ASSET"]))
'
)
case "$asdf_digest" in
  sha256:*) asdf_checksum=${asdf_digest#sha256:} ;;
  *) printf 'Release metadata has no SHA-256 digest for %s\n' "$asdf_asset" >&2; exit 1 ;;
esac

printf 'Version: %s\nAsset:   %s\nSHA-256: %s\n' \
  "$asdf_version" "$asdf_asset" "$asdf_checksum"
mkdir -p "$HOME/bin"
curl -fL \
  "https://github.com/asdf-vm/asdf/releases/download/$asdf_version/$asdf_asset" \
  -o "/tmp/$asdf_asset"
printf '%s  %s\n' "$asdf_checksum" "/tmp/$asdf_asset" |
  sha256sum --check --strict
tar -xzf "/tmp/$asdf_asset" -C "$HOME/bin" asdf
hash -r
asdf --version
```

Alternatively, when Homebrew is already the chosen fallback package manager:

```bash
brew install asdf
```

The stowed Bash configuration already adds `~/.asdf/shims` to `PATH`.
Building Python through the asdf Python plugin also needs the development
libraries for that distribution. On Ubuntu or Debian:

```bash
sudo apt install -y \
  libssl-dev zlib1g-dev libbz2-dev libreadline-dev libsqlite3-dev \
  libffi-dev liblzma-dev tk-dev
```

On Rocky, RHEL or Fedora:

```bash
sudo dnf install -y \
  openssl-devel zlib-devel bzip2-devel readline-devel sqlite-devel \
  libffi-devel xz-devel tk-devel
```

Use asdf for these groups:

| Tool | Why manage it with asdf |
|---|---|
| Python | Project versions and the Python runtime required by some Nvim2 tools |
| Node.js | Project versions and the Node runtime required by several Nvim2 tools |
| kubectl | Match the supported version range of the target Kubernetes clusters |
| Helm | Match chart and CI versions |
| Terraform | Match each repository's `required_version` constraint |
| Terragrunt | Match the version used by the repository or CI |
| Go | Optional, only when developing or building Go projects |

Add the plugins on a connected machine:

```bash
asdf plugin add python https://github.com/asdf-community/asdf-python.git
asdf plugin add nodejs https://github.com/asdf-vm/asdf-nodejs.git
asdf plugin add kubectl https://github.com/asdf-community/asdf-kubectl.git
asdf plugin add helm https://github.com/Antiarchitect/asdf-helm.git
asdf plugin add terraform https://github.com/asdf-community/asdf-hashicorp.git
asdf plugin add terragrunt https://github.com/gruntwork-io/asdf-terragrunt.git
# Optional:
asdf plugin add golang https://github.com/asdf-community/asdf-golang.git
```

Inspect available releases, then replace `VERSION` with one reviewed exact
version. Do not use `latest` in `~/.tool-versions`:

```bash
asdf list all python
asdf install python VERSION
asdf set -u python VERSION

asdf list all nodejs
asdf install nodejs VERSION
asdf set -u nodejs VERSION

# Keep npm on a reviewed current release instead of the older version bundled
# with some Node archives.
npm view npm version
npm install --global npm@NPM_VERSION
asdf reshim nodejs
npm --version

asdf list all kubectl
asdf install kubectl VERSION
asdf set -u kubectl VERSION

asdf list all helm
asdf install helm VERSION
asdf set -u helm VERSION

asdf list all terraform
asdf install terraform VERSION
asdf set -u terraform VERSION

asdf list all terragrunt
asdf install terragrunt VERSION
asdf set -u terragrunt VERSION

asdf reshim
asdf current
```

`asdf set -u` writes the user-wide default to `~/.tool-versions`. A repository
can override it with its own `.tool-versions` file.

Replace `NPM_VERSION` with the reviewed exact release reported by
`npm view npm version`. The Ubuntu 26.04 validation found that npm 11.4.2 could
idle until its five-minute network timeout after Mason downloads, while npm
11.19.0 completed the same concurrent installs.

Do not manage Neovim with asdf. Keeping it outside the asdf shim layer makes
the editor version, checksum, offline artifact and rollback path explicit. It
also prevents an asdf Neovim shim from taking precedence over `~/bin/nvim`.
Mason language servers, formatters and linters remain managed by the Nvim2
configuration, not asdf.

### 6. Install Neovim separately

Nvim2 requires Neovim 0.12.4 or newer. Distribution packages may be older.
Install one reviewed official release under `~/.local/opt` and link it into
`~/bin`.

Resolve the latest stable tag and published SHA-256 digest. Set
`NVIM_VERSION=vX.Y.Z` first to reproduce a previously reviewed release:

```bash
version=${NVIM_VERSION:-$(
  curl -fsSL https://api.github.com/repos/neovim/neovim/releases/latest |
    python3 -c 'import json, sys; print(json.load(sys.stdin)["tag_name"])'
)}
case "$(uname -m)" in
  x86_64) asset=nvim-linux-x86_64.tar.gz ;;
  aarch64) asset=nvim-linux-arm64.tar.gz ;;
  *) printf 'Unsupported architecture: %s\n' "$(uname -m)" >&2; exit 1 ;;
esac

digest=$(
  curl -fsSL "https://api.github.com/repos/neovim/neovim/releases/tags/$version" |
    ASSET="$asset" python3 -c '
import json, os, sys
assets = json.load(sys.stdin)["assets"]
print(next(item["digest"] for item in assets if item["name"] == os.environ["ASSET"]))
'
)
case "$digest" in
  sha256:*) checksum=${digest#sha256:} ;;
  *) printf 'Release metadata has no SHA-256 digest for %s\n' "$asset" >&2; exit 1 ;;
esac

printf 'Version: %s\nAsset:   %s\nSHA-256: %s\n' \
  "$version" "$asset" "$checksum"
```

Review the resolved values and the
[Neovim release notes](https://github.com/neovim/neovim/releases), then install
the exact asset in the same shell:

```bash
install_dir="$HOME/.local/opt/nvim-$version"
mkdir -p "$install_dir" "$HOME/bin"
curl -fL \
  "https://github.com/neovim/neovim/releases/download/$version/$asset" \
  -o "/tmp/$asset"
printf '%s  %s\n' "$checksum" "/tmp/$asset" |
  sha256sum --check --strict
tar -xzf "/tmp/$asset" -C "$install_dir" --strip-components=1
ln -sfn "$install_dir/bin/nvim" "$HOME/bin/nvim"
hash -r
type -a nvim
nvim --version | head -n 1
```

`hash -r` matters in a shell that cached `/usr/bin/nvim` before
`~/bin/nvim` existed.

### 7. Install and verify Nvim2

On Ubuntu or Rocky, install the locked plugins, pinned Mason tools and
configured Treesitter parsers:

```bash
cd "$GH_REPOS/dotfiles"
timeout 1200s env NVIM_APPNAME=nvim2 \
  nvim --headless '+Nvim2ToolsInstallSync' '+qa!'
```

On Amazon Linux 2023, first replace Mason's glibc-2.39 Tree-sitter CLI with the
same pinned version built on AL2023. Follow the AL2023 commands under
[Build a clean Nvim2 data directory](docs/nvim2-platform-releases.md#build-a-clean-nvim2-data-directory).

`Nvim2ToolsInstallSync` already runs `MasonToolsInstallSync`. Do not run the
latter separately outside the documented AL2023 builder step. The command
needs GitHub and the registries used by Mason.
Mason installs one package at a time because its CSS, HTML and JSON entries
otherwise launch concurrent npm installs of the same underlying package.
The command disables npm's audit request only during this pinned Mason install
because the request can idle until npm's five-minute network timeout. Normal
project installs and tool-version review still use npm audit.
If a registry or package download fails, inspect
`~/.local/state/nvim2/mason.log` and rerun the same idempotent command. Do not
accept an installation until the checks below pass.

Run the profile checks:

```bash
timeout 120s bash "$HOME/.config/nvim2/tests/check.sh"
```

Then start `nvim` and inspect:

```vim
:Nvim2Check
:checkhealth vim.lsp
:Mason
:ConformInfo
```

Install `ansible-core` as a project or operating-system dependency when working
with Ansible. Terraform, Helm and Docker CLIs are also project-level runtime
dependencies rather than Mason-owned editor dependencies.

See the [Nvim2 README](nvim2/.config/nvim2/README.md) for daily workflows and
key mappings.

### 8. Install optional tmux plugins

Plain tmux works without TPM. Resurrect and Continuum require the plugin
manager and their checked-out repositories:

```bash
git clone https://github.com/tmux-plugins/tpm "$HOME/.tmux/plugins/tpm"
```

Start tmux and press `Ctrl+a`, then `Shift+I` to install the configured plugins.
The command and key reference is kept at the top of
[`tmux/.tmux.conf`](tmux/.tmux.conf), next to the configuration it describes.

## Optional connected-machine tools

### Homebrew fallback

Use Homebrew only when a required tool is unavailable from `apt`, `dnf` or
`yum`. It requires internet access.

Ubuntu or Debian prerequisites and installation:

```bash
sudo apt-get install -y build-essential procps curl file git
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
# Follow the printed brew shellenv instruction.
```

Examples of tools that may be missing from distribution repositories:

```bash
brew install asdf k9s kubeconform krew helm terragrunt kind
brew tap hashicorp/tap
brew install hashicorp/tap/terraform
```

Do not install Neovim from Homebrew for the Nvim2 platform release. Use the
reviewed installation in step 6.

### Oh My Posh

```bash
mkdir -p "$HOME/bin"
curl -s https://ohmyposh.dev/install.sh | bash -s -- -d "$HOME/bin"
```

The installer needs `curl`, `unzip`, `realpath` and `dirname`. The last two are
usually supplied by `coreutils`.

### zoxide

When it is unavailable from the operating-system repositories:

```bash
curl -sSfL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | sh
```

### kubectx and kubens

When they are unavailable from the operating-system repositories:

```bash
sudo git clone https://github.com/ahmetb/kubectx /opt/kubectx
mkdir -p "$HOME/bin"
sudo ln -sfn /opt/kubectx/kubectx "$HOME/bin/kubectx"
sudo ln -sfn /opt/kubectx/kubens "$HOME/bin/kubens"
```

### krew

Install the kubectl plugin manager on a connected machine:

```bash
(
  set -x
  cd "$(mktemp -d)" || exit
  OS="$(uname | tr '[:upper:]' '[:lower:]')"
  ARCH="$(uname -m | sed -e 's/x86_64/amd64/' -e 's/\(arm\)\(64\)\?.*/\1\2/' -e 's/aarch64$/arm64/')"
  KREW="krew-${OS}_${ARCH}"
  curl -fsSLO "https://github.com/kubernetes-sigs/krew/releases/latest/download/${KREW}.tar.gz"
  tar zxvf "${KREW}.tar.gz"
  "./${KREW}" install krew
)
```

The Bash configuration adds `~/.krew/bin` to `PATH`. For example:

```bash
kubectl krew install cnpg
```

### Mermaid ASCII preview

The Mermaid renderer is optional and is not installed by Mason. Follow the
[Nvim2 Mermaid instructions](nvim2/.config/nvim2/README.md#markdown-colors-and-todo-comments)
to install the reviewed binary in `~/bin`.

## Set up or upgrade a restricted VM

Do not run online installers, asdf plugin commands, `vim.pack.update()` or
Mason installation commands on a restricted target.

Build and test one complete platform artifact on a connected builder matching
the target distribution, architecture, username, home path and Python version.
Transfer and activate it using the
[Nvim2 platform release runbook](docs/nvim2-platform-releases.md).

The transferred release contains Neovim, Node.js, ripgrep, plugins, Mason
packages and Treesitter parsers. The target still needs:

- Python 3.12 for Yamllint and Ansible-lint virtual environments;
- project CLIs such as Terraform, Helm, Docker and Ansible when their features
  are used.

Install Python from the approved operating-system repository. asdf remains a
connected-machine version manager and is not part of the offline release.

Standalone reviewed binaries such as kubectl, Helm, k9s, yq, Trivy,
Oh My Posh and Mermaid ASCII can be downloaded on a connected machine and
copied to `~/bin`. Verify their published checksums before transfer:

```bash
mkdir -p "$HOME/bin"
export PATH="$HOME/bin:$PATH"
```

TPM and tmux plugin directories must also be transferred if Resurrect or
Continuum is required. Amazon Linux 2023 supplies a compatible tmux package.

## Maintenance and recovery

### bstow behavior

`--dry-run` previews planned actions without changing the filesystem. `-n` is
the short form; `-v` only adds diagnostic detail.

`bstow` accepts relative and absolute target links when they resolve to the
expected package file. It never replaces regular target files or foreign target
links unless a foreign link is explicitly adopted with `--force`. Inspect both
paths first:

```bash
./bstow --dry-run --force -t "$HOME" stow bash
./bstow --force -t "$HOME" stow bash
```

`bstow` intentionally manages regular package files as individual links. It
ignores symlinks and empty directories stored inside packages, so it implements
a smaller interface than GNU Stow.

When a parent directory links to the selected package, stow normalizes it to a
real directory containing per-file links. A link to the same package in another
clone requires `--force`. Paths found only in the previous clone disappear from
the target view, but files in that clone are not modified. Preview the operation
first as shown above.

After pulling deletions or renames, use `restow` to remove obsolete links and
create the current set:

```bash
./bstow --dry-run -v -t "$HOME" restow nvim2
./bstow -v -t "$HOME" restow nvim2
```

Package ownership is recorded under `$TARGET_DIR/.local/state/bstow`. Override
that location with `BSTOW_STATE_DIR` when required. If a package was moved to a
different clone, preview and adopt its links explicitly:

```bash
./bstow --dry-run --force -t "$HOME" restow nvim2
./bstow --force -t "$HOME" restow nvim2
```

Run the regression suite after changing `bstow`:

```bash
timeout 60s bash tests/bstow_test.sh
```

### Codex agent instructions

The `codex` package manages only `~/.codex/AGENTS.md`. It does not manage
authentication, sessions, logs, caches or other Codex runtime state. Workspace
guidance remains a standalone `AGENTS.md` owned by that workspace.

On a VM where a workspace `AGENTS.md` is still a symlink into an old dotfiles
checkout, preserve it before pulling rewritten history:

```bash
workspace="$HOME/work/githubactions"
temporary=$(mktemp "$workspace/.AGENTS.md.XXXXXX")
cp --dereference "$workspace/AGENTS.md" "$temporary"
chmod 0644 "$temporary"
mv -Tf "$temporary" "$workspace/AGENTS.md"
test -f "$workspace/AGENTS.md" && test ! -L "$workspace/AGENTS.md"
```

Change `workspace` for other workspaces. Run this while the old link target
still exists.

### Nvim2 updates

Updates are intentionally manual. On a trusted connected machine:

- Run `:lua vim.pack.update()`, review the proposed commits and use `:write` to
  accept them and rewrite `nvim-pack-lock.json`.
- Change exact Mason versions in
  `nvim2/.config/nvim2/lua/custom/lsp.lua`, then run
  `:Nvim2ToolsInstallSync`.
- Run `bash ~/.config/nvim2/tests/check.sh` before creating a new platform
  release.

See [Plugin and configuration maintenance](nvim2/.config/nvim2/README.md#plugin-and-configuration-maintenance)
and the [platform release runbook](docs/nvim2-platform-releases.md).

### Recover an SSH agent socket from tmux

Tmux sessions retain the `SSH_AUTH_SOCK` value present when they started. To
recover the socket stored in the `work` session:

```bash
agent_sock=$(tmux show-environment -t work SSH_AUTH_SOCK | sed 's/^SSH_AUTH_SOCK=//')
if [[ -S "$agent_sock" ]]; then
  export SSH_AUTH_SOCK="$agent_sock"
else
  printf 'The tmux SSH agent socket is missing or stale: %s\n' "$agent_sock" >&2
fi
ssh-add -l
```

Replace `work` with a name from `tmux list-sessions`. To publish a new socket to
the session and reload it in an existing pane:

```bash
tmux set-environment -t work SSH_AUTH_SOCK "$SSH_AUTH_SOCK"
export SSH_AUTH_SOCK="$(tmux show-environment -t work SSH_AUTH_SOCK | sed 's/^SSH_AUTH_SOCK=//')"
ssh-add -l
```

### Portability notes

- Bash 4 or newer is required. `ff` handles `fd`, `fdfind` and GNU `find`; `ff`
  and `ffv` require FZF when invoked.
- Git over HTTPS uses `gh auth git-credential`. SSH remotes do not need that
  helper. Install Git LFS only for repositories that use it.
- Programs inside tmux use `tmux-256color`. Check it with
  `infocmp tmux-256color` and install the distribution's `ncurses-term` package
  when missing. `screen-256color` is a less capable fallback.
- The terminal outside tmux keeps its own type, such as `xterm-kitty` or
  `xterm-256color`.
- Missing optional integrations disable only their related aliases or prompt
  segments.

### Manual symlinks

Use this only when `bstow` is unavailable:

```bash
ln -sv "$PWD/git/.gitconfig" "$HOME/.gitconfig"
ln -sv "$PWD/tmux/.tmux.conf" "$HOME/.tmux.conf"
ln -sv "$PWD/bash/.bash_profile" "$HOME/.bash_profile"
ln -sv "$PWD/bash/.bashrc" "$HOME/.bashrc"
ln -sv "$PWD/bash/.bash_aliases" "$HOME/.bash_aliases"
ln -sv "$PWD/oh-my-posh/.oh-my-posh.omp.json" "$HOME/.oh-my-posh.omp.json"

mkdir -p "$HOME/.config" "$HOME/.codex" "$HOME/.gnupg"
ln -sv "$PWD/k9s/.config/k9s" "$HOME/.config/k9s"
ln -sv "$PWD/kitty/.config/kitty" "$HOME/.config/kitty"
ln -sv "$PWD/nvim2/.config/nvim2" "$HOME/.config/nvim2"
ln -sv "$PWD/codex/.codex/AGENTS.md" "$HOME/.codex/AGENTS.md"
ln -sv "$PWD/gnupg/.gnupg/gpg-agent.conf" "$HOME/.gnupg/gpg-agent.conf"
```
