FROM docker.io/library/debian:13@sha256:9cc080028c43b27d2074d63a5f9caf7166d731494965616c1a6d2827a004585c AS mise

ARG MISE_VERSION=2026.11.5
ARG MISE_SHA256=d7dee029352bf4b8986e7c4696b8ce54746c3eb648ffca3cc69bdeecc0ff06e9

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
    MISE_YES=1

FROM mise AS tools

COPY mise.toml /etc/mise/config.toml
COPY mise.lock /etc/mise/mise.lock
COPY .mise/locks /etc/mise/.mise/locks

RUN chmod 0644 \
        /etc/mise/config.toml \
        /etc/mise/mise.lock \
    && chmod -R a+rX /etc/mise/.mise/locks \
    && mise install \
        --locked \
        --jobs 4 \
    && mise reshim \
    && rm -rf \
        /opt/mise/downloads \
        /opt/mise/cache

FROM tools AS runtime

# fixed group keeps image data writable for any runtime UID
RUN groupadd --gid 1000 dotfiles \
    && mkdir -p \
        /home/devcontainer \
        /opt/nvim2 \
        /opt/tmux/plugins \
    && chgrp -R dotfiles \
        /home/devcontainer \
        /opt/nvim2 \
        /opt/tmux \
    && chmod -R g+rwX \
        /home/devcontainer \
        /opt/nvim2 \
        /opt/tmux \
    && find /home/devcontainer /opt/nvim2 /opt/tmux \
        -type d -exec chmod g+s {} +

# mise updates version aliases beside the tools bundled in the image.
RUN chgrp dotfiles /opt/mise/installs/* \
    && chmod g+ws /opt/mise/installs/*

# plugin updates use a different UID from the image build.
RUN git config --system --add safe.directory '/opt/nvim2/site/pack/core/opt/*'

ENV HOME=/home/devcontainer \
    XDG_CONFIG_HOME=/home/devcontainer/.config \
    XDG_DATA_HOME=/home/devcontainer/.local/share \
    XDG_CACHE_HOME=/home/devcontainer/.cache \
    XDG_STATE_HOME=/home/devcontainer/.local/state \
    MISE_DATA_DIR=/home/devcontainer/.local/share/mise \
    MISE_SYSTEM_DATA_DIR=/opt/mise \
    MISE_CACHE_DIR=/home/devcontainer/.cache/mise \
    MISE_STATE_DIR=/home/devcontainer/.local/state/mise \
    NVIM_APPNAME=nvim2 \
    GOTOOLCHAIN=local

COPY --chown=root:dotfiles . /opt/dotfiles/
RUN chmod -R g+rwX /opt/dotfiles \
    && find /opt/dotfiles -type d -exec chmod g+s {} +
WORKDIR /opt/dotfiles

RUN mkdir -p \
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
    && ln -s /opt/tmux/plugins "$HOME/.tmux/plugins" \
    && mise reshim

RUN printf 'image: installing tmux-sensible\n' \
    && git init -q /opt/tmux/plugins/tmux-sensible \
    && git -C /opt/tmux/plugins/tmux-sensible remote add origin \
        https://github.com/tmux-plugins/tmux-sensible.git \
    && timeout --kill-after=5s 180s \
        git -C /opt/tmux/plugins/tmux-sensible fetch --depth=1 origin \
        25cb91f42d020f675bb0a2ce3fbd3a5d96119efa \
    && git -C /opt/tmux/plugins/tmux-sensible checkout --detach --quiet FETCH_HEAD \
    && chmod -R g+rwX /opt/tmux/plugins/tmux-sensible \
    && find /opt/tmux/plugins/tmux-sensible -type d -exec chmod g+s {} +

RUN printf 'image: installing tmux-resurrect\n' \
    && git init -q /opt/tmux/plugins/tmux-resurrect \
    && git -C /opt/tmux/plugins/tmux-resurrect remote add origin \
        https://github.com/tmux-plugins/tmux-resurrect.git \
    && timeout --kill-after=5s 180s \
        git -C /opt/tmux/plugins/tmux-resurrect fetch --depth=1 origin \
        cff343cf9e81983d3da0c8562b01616f12e8d548 \
    && git -C /opt/tmux/plugins/tmux-resurrect checkout --detach --quiet FETCH_HEAD \
    && chmod -R g+rwX /opt/tmux/plugins/tmux-resurrect \
    && find /opt/tmux/plugins/tmux-resurrect -type d -exec chmod g+s {} +

RUN printf 'image: installing tmux-continuum\n' \
    && git init -q /opt/tmux/plugins/tmux-continuum \
    && git -C /opt/tmux/plugins/tmux-continuum remote add origin \
        https://github.com/tmux-plugins/tmux-continuum.git \
    && timeout --kill-after=5s 180s \
        git -C /opt/tmux/plugins/tmux-continuum fetch --depth=1 origin \
        0698e8f4b17d6454c71bf5212895ec055c578da0 \
    && git -C /opt/tmux/plugins/tmux-continuum checkout --detach --quiet FETCH_HEAD \
    && chmod -R g+rwX /opt/tmux/plugins/tmux-continuum \
    && find /opt/tmux/plugins/tmux-continuum -type d -exec chmod g+s {} +

# Ex mode makes installation errors fail the build.
RUN printf 'image: installing Neovim plugins, Mason tools and parsers\n' \
    && timeout --kill-after=30s 2400s \
        mise exec -- \
        nvim \
            --headless \
            -e \
            '+Nvim2ToolsInstallSync' \
            '+qa!' \
    && chgrp -R dotfiles /opt/nvim2 \
    && chmod -R g+rwX /opt/nvim2 \
    && find /opt/nvim2 -type d -exec chmod g+s {} + \
    && mise exec -- go clean -cache -modcache \
    && rm -rf \
        "$HOME/.cache" \
        "$HOME/.npm" \
        "$HOME/go" \
        "$XDG_STATE_HOME/nvim2" \
        "$XDG_STATE_HOME/mise" \
    && mkdir -p \
        "$XDG_CACHE_HOME" \
        "$XDG_STATE_HOME/nvim2" \
        "$XDG_DATA_HOME/tmux/resurrect" \
    && chgrp -R dotfiles "$HOME" \
    && chmod -R g+rwX "$HOME" \
    && find "$HOME" -type d -exec chmod g+s {} +

# mason exposes ansible-lint, but its Ansible LSP helpers stay inside the venv.
# to be decided if I want to use separate ansible tools and remove ansible-lint from mason.
RUN set -eu; \
    if [ -d /opt/nvim2/mason/packages/ansible-lint ]; then \
        for command_name in \
            ansible \
            ansible-config \
            ansible-playbook; do \
            test -x "/opt/nvim2/mason/packages/ansible-lint/venv/bin/$command_name"; \
            ln -s "../packages/ansible-lint/venv/bin/$command_name" \
                "/opt/nvim2/mason/bin/$command_name"; \
        done; \
    fi; \
    printf 'image: ready\n'

WORKDIR /home/devcontainer
COPY --chmod=0755 scripts/devcontainer-entrypoint /usr/local/bin/devcontainer-entrypoint
ENTRYPOINT ["/usr/local/bin/devcontainer-entrypoint"]
HEALTHCHECK \
    --start-period=5s \
    --start-interval=1s \
    --timeout=5s \
    CMD test "$(getent passwd devcontainer | cut -d: -f3,4,6)" \
        = "${DOTFILES_UID:-1000}:${DOTFILES_GID:-1000}:$HOME"
CMD ["sleep", "infinity"]
