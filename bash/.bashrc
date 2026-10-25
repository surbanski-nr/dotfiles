# shellcheck shell=bash
# ~/.bashrc: executed by bash(1) for non-login shells.
# see /usr/share/doc/bash/examples/startup-files (in the package bash-doc)
# for examples

# If not running interactively, don't do anything
case $- in
*i*) ;;
*) return ;;
esac

_dotfiles_warn() {
  printf 'dotfiles: %s\n' "$*" >&2
}

_dotfiles_eval_init() {
  local integration=$1
  local init
  shift

  if ! init=$("$@" 2>/dev/null); then
    _dotfiles_warn "$integration initialization failed"
    return 1
  fi
  if ! eval "$init" 2>/dev/null; then
    _dotfiles_warn "$integration returned invalid shell initialization"
    return 1
  fi
}

add_to_path() {
  local entry rebuilt=
  local -a entries=()

  [[ -d $1 ]] || return 0
  IFS=: read -r -a entries <<<"${PATH:-}"
  for entry in "${entries[@]}"; do
    [[ -n $entry && $entry != "$1" ]] || continue
    rebuilt+="${rebuilt:+:}$entry"
  done
  PATH="$1${rebuilt:+:$rebuilt}"
  export PATH
}

_dotfiles_restore_launcher_environment() {
  local name marker value

  for name in XDG_CONFIG_HOME XDG_DATA_HOME _ZO_DATA_DIR GOROOT GOTOOLCHAIN; do
    marker=DOTFILES_LAUNCHER_${name#_}_SET
    value=DOTFILES_LAUNCHER_${name#_}
    if [[ ${!marker:-} == 1 ]]; then
      printf -v "$name" '%s' "${!value}"
      export "${name?}"
    elif [[ ${!marker:-} == 0 ]]; then
      unset "$name"
    fi
    unset "$marker" "$value"
  done
}

_dotfiles_restore_launcher_environment

_dotfiles_source=$(readlink -f -- "${BASH_SOURCE[0]}" 2>/dev/null ||
  printf '%s\n' "${BASH_SOURCE[0]}")
_dotfiles_source_root=$(CDPATH='' cd -- "$(dirname -- "$_dotfiles_source")/.." && pwd)
_dotfiles_previous_auto_root=${DOTFILES_AUTO_ROOT:-}
_dotfiles_release_store=${DOTFILES_RELEASE_ROOT:-$HOME/dotfiles-releases}
export GITUSER="${GITUSER:-surbanski}"
export GHREPOS="${GHREPOS:-$HOME/github.com/$GITUSER}"
export LAB="${LAB:-$GHREPOS/lab}"
export NOTES="${NOTES:-$GHREPOS/notes-md}"
if [[ ! -v DOTFILES || (-n $_dotfiles_previous_auto_root && $DOTFILES == "$_dotfiles_previous_auto_root") ]]; then
  export DOTFILES=$_dotfiles_source_root
  export DOTFILES_AUTO_ROOT=$_dotfiles_source_root
else
  unset DOTFILES_AUTO_ROOT
fi
export WORK="${WORK:-$HOME/work}"
# Keep virtual environment activation from modifying the prompt.
export VIRTUAL_ENV_DISABLE_PROMPT=1
# shellcheck source=.bash_history_lib
source "$_dotfiles_source_root/bash/.bash_history_lib" \
  "$_dotfiles_source_root/scripts/bash-history-archive"
unset _dotfiles_source _dotfiles_source_root

# Drop private paths inherited from a release launcher or tmux pane. Shell
# commands follow current; application jobs retain their physical release.
IFS=: read -r -a _dotfiles_path_entries <<<"${PATH:-}"
_dotfiles_clean_path=
for _dotfiles_path_entry in "${_dotfiles_path_entries[@]}"; do
  case $_dotfiles_path_entry in
    "$HOME/bin" | "$_dotfiles_release_store/current/bin") continue ;;
  esac
  if [[ $_dotfiles_path_entry =~ /dotfiles-[0-9a-f]{12}/(bin|dotfiles/scripts|share/nvim2/mason/bin|share/nvim2/mason/packages/ansible-lint/venv/bin)$ ]]; then
    continue
  fi
  if [[ -n $_dotfiles_previous_auto_root &&
    $_dotfiles_path_entry == "$_dotfiles_previous_auto_root/scripts" ]]; then
    continue
  fi
  [[ -n $_dotfiles_path_entry ]] || continue
  _dotfiles_clean_path+="${_dotfiles_clean_path:+:}$_dotfiles_path_entry"
done
PATH=$_dotfiles_clean_path
export PATH
unset _dotfiles_path_entries _dotfiles_path_entry _dotfiles_clean_path \
  _dotfiles_previous_auto_root

add_to_path "$HOME/.local/share/nvim2/mason/bin"
add_to_path "$HOME/.local/bin"
add_to_path "$DOTFILES/scripts"
add_to_path "$HOME/.krew/bin"
add_to_path "$HOME/.asdf/shims"
add_to_path "$_dotfiles_release_store/current/bin"
unset _dotfiles_release_store
if [[ ${DOTFILES_IGNORE_USER_BIN:-} != 1 ]]; then
  add_to_path "$HOME/bin"
fi
if [[ -n ${VIRTUAL_ENV:-} ]]; then
  add_to_path "$VIRTUAL_ENV/bin"
fi

_dotfiles_ssh_agent_reachable() {
  local status

  ssh-add -l >/dev/null 2>&1 && return 0
  status=$?
  [[ $status -eq 1 ]]
}

_dotfiles_init_ssh_agent() {
  local attempt service socket

  command -v ssh-add >/dev/null 2>&1 || return 0
  # Keep working agents inherited from another shell or SSH forwarding.
  if [[ -n ${SSH_AUTH_SOCK:-} ]] && _dotfiles_ssh_agent_reachable; then
    return 0
  fi
  service=$HOME/.config/systemd/user/dotfiles-ssh-agent.service
  [[ -r $service && -n ${XDG_RUNTIME_DIR:-} && -d $XDG_RUNTIME_DIR ]] || return 0
  command -v systemctl >/dev/null 2>&1 || return 0

  socket=$XDG_RUNTIME_DIR/dotfiles-ssh-agent.socket
  SSH_AUTH_SOCK=$socket
  export SSH_AUTH_SOCK
  unset SSH_AGENT_PID
  if _dotfiles_ssh_agent_reachable; then
    return 0
  fi

  if ! systemctl --user start dotfiles-ssh-agent.service >/dev/null 2>&1; then
    _dotfiles_warn 'failed to start the shared ssh-agent service'
    unset SSH_AUTH_SOCK
    return 0
  fi
  for ((attempt = 0; attempt < 20; attempt++)); do
    _dotfiles_ssh_agent_reachable && return 0
    sleep 0.05
  done

  _dotfiles_warn "shared ssh-agent did not create $socket"
  unset SSH_AUTH_SOCK
}

_dotfiles_init_ssh_agent
unset -f _dotfiles_init_ssh_agent _dotfiles_ssh_agent_reachable

# Warn about active jobs on exit and keep terminal dimensions current.
shopt -s checkjobs checkwinsize

# Preserve failures from the left side of pipelines used by shell helpers.
set -o pipefail

# Require three consecutive Ctrl-D presses before exiting the shell.
set -o ignoreeof
export IGNOREEOF=3

# If set, the pattern "**" used in a pathname expansion context will
# match all files and zero or more directories and subdirectories.
#shopt -s globstar

# Make less more friendly for non-text input files when the integration works.
if [ -x /usr/bin/lesspipe ]; then
  _dotfiles_eval_init lesspipe env SHELL=/bin/sh /usr/bin/lesspipe || true
fi

# Keep a usable fallback when Oh My Posh is absent or fails to initialize.
case ${TERM:-} in
xterm-color | *-256color)
  PS1='\[\e[38;5;214m\]$?\[\e[0m\] \[\e[38;5;214m\]\u@\h\[\e[0m\] \[\e[38;5;214m\]\W\[\e[0m\] \[\e[38;5;142m\]\\$\[\e[0m\] '
  ;;
*) PS1='\u@\h:\w\$ ' ;;
esac

# If this is an xterm set the title to user@host:dir
case ${TERM:-} in
xterm* | rxvt*)
  PS1="\[\e]0;\u@\h: \w\a\]$PS1"
  ;;
esac

# enable color support of ls and also add handy aliases
if [ -x /usr/bin/dircolors ]; then
  if [ -r ~/.dircolors ]; then
    _dotfiles_eval_init dircolors dircolors -b ~/.dircolors || true
  else
    _dotfiles_eval_init dircolors dircolors -b || true
  fi
  alias ls='ls --color=auto'
  #alias dir='dir --color=auto'
  #alias vdir='vdir --color=auto'

  alias grep='grep --color=auto'
  alias fgrep='fgrep --color=auto'
  alias egrep='egrep --color=auto'
fi

# colored GCC warnings and errors
#export GCC_COLORS='error=01;31:warning=01;35:note=01;36:caret=01;32:locus=01:quote=01'

# some more ls aliases
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'

# Add an "alert" alias on desktop systems that provide notify-send.
if command -v notify-send >/dev/null 2>&1; then
  alias alert='notify-send --urgency=low -i "$([ $? = 0 ] && echo terminal || echo error)" "$(history|tail -n1|sed -e '\''s/^\s*[0-9]\+\s*//;s/[;&|]\s*alert$//'\'')"'
fi

# Alias definitions.
# You may want to put all your additions into a separate file like
# ~/.bash_aliases, instead of adding them here directly.
# See /usr/share/doc/bash-doc/examples in the bash-doc package.

if [ -f ~/.bash_aliases ]; then
  # shellcheck source=.bash_aliases
  if ! . ~/.bash_aliases 2>/dev/null; then
    _dotfiles_warn 'failed to load ~/.bash_aliases'
  fi
fi

# Use MC's shell wrapper when packaged so F10 returns to its final directory.
for mc_profile in /usr/lib/mc/mc.sh /usr/libexec/mc/mc.sh; do
  if [ -r "$mc_profile" ]; then
    # The distribution selects one of two external wrapper locations.
    # shellcheck disable=SC1090
    if ! . "$mc_profile" 2>/dev/null; then
      _dotfiles_warn "failed to load Midnight Commander wrapper: $mc_profile"
    fi
    break
  fi
done
unset mc_profile

# enable programmable completion features (you don't need to enable
# this, if it's already enabled in /etc/bash.bashrc and /etc/profile
# sources /etc/bash.bashrc).
if ! shopt -oq posix; then
  if [ -f /usr/share/bash-completion/bash_completion ]; then
    # Distribution-owned optional integration.
    # shellcheck disable=SC1091
    if ! . /usr/share/bash-completion/bash_completion 2>/dev/null; then
      _dotfiles_warn 'failed to load bash completion'
    fi
  elif [ -f /etc/bash_completion ]; then
    # Distribution-owned optional integration.
    # shellcheck disable=SC1091
    if ! . /etc/bash_completion 2>/dev/null; then
      _dotfiles_warn 'failed to load bash completion'
    fi
  fi
fi

if command -v google-chrome >/dev/null 2>&1; then
  export BROWSER="google-chrome"
elif command -v wslview >/dev/null 2>&1; then
  export BROWSER="wslview"
elif command -v xdg-open >/dev/null 2>&1; then
  export BROWSER="xdg-open"
fi

export GOPRIVATE="github.com/$GITUSER/*,gitlab.com/$GITUSER/*"

# set -o vi

bind -x '"\C-l":clear'

if command -v fd >/dev/null 2>&1; then
  export FZF_DEFAULT_COMMAND='fd --type f --strip-cwd-prefix --hidden --follow --exclude .git'
elif command -v fdfind >/dev/null 2>&1; then
  export FZF_DEFAULT_COMMAND='fdfind --type f --strip-cwd-prefix --hidden --follow --exclude .git'
else
  export FZF_DEFAULT_COMMAND='find . -type f -not -path "*/.git/*" -print'
fi
export FZF_CTRL_T_COMMAND=$FZF_DEFAULT_COMMAND

# fzf key bindings
_dotfiles_fzf_provider=$(type -P fzf 2>/dev/null || true)
[[ -z $_dotfiles_fzf_provider ]] || _dotfiles_fzf_provider=$(readlink -f -- "$_dotfiles_fzf_provider")
if [[ -n $_dotfiles_fzf_provider ]]; then
  if [[ ${_DOTFILES_FZF_PROVIDER:-} != "$_dotfiles_fzf_provider" ]]; then
    unset -f __fzf_select__ __fzf_cd__ __fzf_history__ 2>/dev/null || true
    _DOTFILES_FZF_PROVIDER=$_dotfiles_fzf_provider
  fi
  _dotfiles_eval_init fzf fzf --bash || true
fi
unset _dotfiles_fzf_provider

_dotfiles_zoxide_provider=$(type -P zoxide 2>/dev/null || true)
[[ -z $_dotfiles_zoxide_provider ]] || _dotfiles_zoxide_provider=$(readlink -f -- "$_dotfiles_zoxide_provider")
if [[ -n $_dotfiles_zoxide_provider &&
  (${_DOTFILES_ZOXIDE_PROVIDER:-} != "$_dotfiles_zoxide_provider" ||
    $(type -t __zoxide_hook 2>/dev/null) != function) ]]; then
  _DOTFILES_ZOXIDE_PROVIDER=$_dotfiles_zoxide_provider
  _dotfiles_eval_init zoxide zoxide init bash || true
fi
unset _dotfiles_zoxide_provider

if command -v kubectl >/dev/null 2>&1; then
  if ! declare -F __start_kubectl >/dev/null; then
    _dotfiles_eval_init kubectl kubectl completion bash || true
  fi
  if declare -F __start_kubectl >/dev/null && ! complete -F __start_kubectl k; then
    _dotfiles_warn 'failed to register kubectl completion for k'
  fi
fi

_dotfiles_omp_provider=$(type -P oh-my-posh 2>/dev/null || true)
[[ -z $_dotfiles_omp_provider ]] || _dotfiles_omp_provider=$(readlink -f -- "$_dotfiles_omp_provider")
if [[ -n $_dotfiles_omp_provider &&
  (${_DOTFILES_OMP_PROVIDER:-} != "$_dotfiles_omp_provider" ||
    $(type -t _omp_hook 2>/dev/null) != function) ]]; then
  _DOTFILES_OMP_PROVIDER=$_dotfiles_omp_provider
  if [[ -r $HOME/.oh-my-posh.omp.json ]]; then
    if _dotfiles_eval_init 'Oh My Posh' oh-my-posh init bash --config "$HOME/.oh-my-posh.omp.json"; then
      command oh-my-posh toggle kubectl ||
        _dotfiles_warn 'failed to disable Kubernetes prompt by default'
    fi
  else
    _dotfiles_warn 'Oh My Posh is installed but ~/.oh-my-posh.omp.json is missing'
  fi
fi
unset _dotfiles_omp_provider

export NVIM_APPNAME="${NVIM_APPNAME:-nvim2}"
export VISUAL=vi
export EDITOR=vi

if [ -f ~/.extras ]; then
  # Private optional configuration is outside this repository's analysis.
  # shellcheck disable=SC1090
  if ! source ~/.extras 2>/dev/null; then
    _dotfiles_warn 'failed to load ~/.extras'
  fi
fi

_dotfiles_install_prompt_command
_dotfiles_install_history_exit
