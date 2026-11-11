FROM docker.io/library/debian:13@sha256:9cc080028c43b27d2074d63a5f9caf7166d731494965616c1a6d2827a004585c AS mise

ARG TARGETARCH
ARG MISE_VERSION=2026.11.5
ARG MISE_SHA256=d7dee029352bf4b8986e7c4696b8ce54746c3eb648ffca3cc69bdeecc0ff06e9

RUN test "$TARGETARCH" = amd64
RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install \
        -y \
        --no-install-recommends \
        bash \
        bash-completion \
        build-essential \
        ca-certificates \
        curl \
        docker-cli \
        docker-compose \
        file \
        gawk \
        git \
        git-lfs \
        htop \
        iproute2 \
        iputils-ping \
        jq \
        less \
        locales \
        mc \
        ncurses-term \
        openssh-client \
        pkg-config \
        procps \
        tmux \
        unzip \
        vim \
        xz-utils \
        zip \
    && rm -rf /var/lib/apt/lists/*

RUN curl \
        --fail \
        --show-error \
        --location \
        --retry 3 \
        "https://github.com/jdx/mise/releases/download/v${MISE_VERSION}/mise-v${MISE_VERSION}-linux-x64.tar.gz" \
        --output /tmp/mise.tar.gz \
    && printf '%s  %s\n' \
        "$MISE_SHA256" \
        /tmp/mise.tar.gz \
        | sha256sum --check --strict \
    && tar \
        --extract \
        --gzip \
        --file /tmp/mise.tar.gz \
        --directory /tmp \
    && install \
        -m 0755 \
        /tmp/mise/bin/mise \
        /usr/local/bin/mise \
    && rm -rf \
        /tmp/mise \
        /tmp/mise.tar.gz

ENV LANG=C.UTF-8 \
    MISE_DATA_DIR=/opt/mise \
    MISE_CACHE_DIR=/opt/mise/cache \
    MISE_STATE_DIR=/opt/mise/state \
    MISE_GLOBAL_CONFIG_FILE=/opt/dotfiles/mise.toml \
    MISE_YES=1

FROM mise AS tools

COPY mise.toml /opt/dotfiles/mise.toml
COPY mise.lock /opt/dotfiles/mise.lock

RUN chmod 0644 \
        /opt/dotfiles/mise.toml \
        /opt/dotfiles/mise.lock \
    && mise install \
        --locked \
        --jobs 4 \
    && mise reshim \
    && rm -rf \
        /opt/mise/downloads \
        /opt/mise/cache

FROM tools AS runtime

ARG DEV_UID=1000
ARG DEV_GID=1000

RUN groupadd --gid "$DEV_GID" dev \
    && useradd \
        --uid "$DEV_UID" \
        --gid "$DEV_GID" \
        --create-home \
        --shell /bin/bash \
        dev \
    && mkdir -p \
        /opt/nvim2 \
        /opt/tmux/plugins \
    && chown -R dev:dev \
        /home/dev \
        /opt/nvim2 \
        /opt/tmux

# rootless uses a different UID from the owner of the image's plugins.
RUN git config --system --add safe.directory '/opt/nvim2/site/pack/core/opt/*'

ENV HOME=/home/dev \
    XDG_CONFIG_HOME=/home/dev/.config \
    XDG_DATA_HOME=/home/dev/.local/share \
    XDG_CACHE_HOME=/home/dev/.cache \
    XDG_STATE_HOME=/home/dev/.local/state \
    MISE_CACHE_DIR=/home/dev/.cache/mise \
    MISE_STATE_DIR=/home/dev/.local/state/mise \
    NVIM_APPNAME=nvim2 \
    GOTOOLCHAIN=local

COPY --chown=dev:dev . /opt/dotfiles/
WORKDIR /opt/dotfiles
USER dev

RUN rm -f \
        "$HOME/.bashrc" \
        "$HOME/.bash_profile" \
        "$HOME/.profile" \
        "$HOME/.bash_logout" \
    && mkdir -p \
        "$HOME/bin" \
        "$XDG_DATA_HOME" \
        "$XDG_CACHE_HOME" \
        "$XDG_STATE_HOME" \
    && ./bstow -t "$HOME" stow \
        bash \
        git \
        tmux \
        vim \
        mc \
        nvim2 \
        k9s \
        oh-my-posh \
    && ln -s /opt/nvim2 "$XDG_DATA_HOME/nvim2" \
    && ln -s /opt/tmux/plugins "$HOME/.tmux/plugins"

RUN /bin/bash <<'BASH'
set -euo pipefail

while read -r plugin url commit; do
  destination=/opt/tmux/plugins/$plugin
  printf 'image: installing %s\n' "$plugin"
  git init -q "$destination"
  git -C "$destination" remote add origin "$url"
  timeout --kill-after=5s 180s \
    git -C "$destination" fetch --depth=1 origin "$commit"
  git -C "$destination" checkout --detach --quiet FETCH_HEAD
done <<'PLUGINS'
tmux-sensible https://github.com/tmux-plugins/tmux-sensible.git 25cb91f42d020f675bb0a2ce3fbd3a5d96119efa
tmux-resurrect https://github.com/tmux-plugins/tmux-resurrect.git cff343cf9e81983d3da0c8562b01616f12e8d548
tmux-continuum https://github.com/tmux-plugins/tmux-continuum.git 0698e8f4b17d6454c71bf5212895ec055c578da0
PLUGINS
BASH

RUN /bin/bash <<'BASH'
set -euo pipefail
printf 'image: installing Neovim plugins, Mason tools and parsers\n'
timeout --kill-after=30s 2400s \
  mise exec -- \
  nvim \
    --headless \
    '+lua dofile("/dev/stdin")' \
    '+qa!' <<'LUA'
local ok, message = xpcall(function()
  vim.cmd 'Nvim2ToolsInstallSync'
end, debug.traceback)
if not ok then
  io.stderr:write(message .. '\n')
  vim.cmd 'cquit 1'
end
LUA

# mason exposes ansible-lint, but its Ansible LSP helpers stay inside the venv.
# to be decided if I want to use separate ansible tools and remove ansible-lint from mason.
if [[ -d /opt/nvim2/mason/packages/ansible-lint ]]; then
  for command_name in ansible ansible-config ansible-playbook; do
    test -x "/opt/nvim2/mason/packages/ansible-lint/venv/bin/$command_name"
    ln -s "../packages/ansible-lint/venv/bin/$command_name" \
      "/opt/nvim2/mason/bin/$command_name"
  done
fi

mise exec -- go clean -cache -modcache
rm -rf \
  "$HOME/.cache" \
  "$HOME/.npm" \
  "$HOME/go" \
  "$XDG_STATE_HOME/nvim2" \
  "$XDG_STATE_HOME/mise"
mkdir -p "$XDG_CACHE_HOME"
printf 'image: ready\n'
BASH

WORKDIR /home/dev
CMD ["sleep", "infinity"]
