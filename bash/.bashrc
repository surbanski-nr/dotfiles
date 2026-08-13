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

_dotfiles_history_sync() {
  history -a
  history -n
}

_dotfiles_install_prompt_command() {
  local duplicate entry existing
  local -a current=() normalized=()

  if [[ $(declare -p PROMPT_COMMAND 2>/dev/null) == 'declare -a'* ]]; then
    current=("${PROMPT_COMMAND[@]}")
  elif [[ -n ${PROMPT_COMMAND:-} ]]; then
    current=("$PROMPT_COMMAND")
  fi

  for entry in "${current[@]}"; do
    case $entry in
    'history -a; history -r' | 'history -a; history -n' | '_dotfiles_history_sync')
      continue
      ;;
    *';history -a; history -r') entry=${entry%';history -a; history -r'} ;;
    *'; history -a; history -r') entry=${entry%'; history -a; history -r'} ;;
    *';history -a; history -n') entry=${entry%';history -a; history -n'} ;;
    *'; history -a; history -n') entry=${entry%'; history -a; history -n'} ;;
    esac
    entry=${entry%;}
    [[ -n $entry ]] || continue

    duplicate=false
    for existing in "${normalized[@]}"; do
      if [[ $existing == "$entry" ]]; then
        duplicate=true
        break
      fi
    done
    $duplicate || normalized+=("$entry")
  done

  normalized+=('_dotfiles_history_sync')
  PROMPT_COMMAND=("${normalized[@]}")
}

# Keep a large bounded history and share new commands between open shells.
HISTSIZE=100000
HISTFILESIZE=100000
HISTFILE="$HOME/.histfile"
HISTTIMEFORMAT='%F %T '

# don't put duplicate lines or lines starting with space in the history.
# See bash(1) for more options
HISTCONTROL=ignoreboth:erasedups

# Append history, verify history expansion, warn about active jobs on exit, and
# keep terminal dimensions current.
shopt -s histappend histverify checkjobs checkwinsize

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

# set variable identifying the chroot you work in (used in the prompt below)
if [ -z "${debian_chroot:-}" ] && [ -r /etc/debian_chroot ]; then
  debian_chroot=$(cat /etc/debian_chroot)
fi

# set a fancy prompt (non-color, unless we know we "want" color)
case "$TERM" in
xterm-color | *-256color) color_prompt=yes ;;
esac

# uncomment for a colored prompt, if the terminal has the capability; turned
# off by default to not distract the user: the focus in a terminal window
# should be on the output of commands, not on the prompt
#force_color_prompt=yes

if [ -n "$force_color_prompt" ]; then
  if [ -x /usr/bin/tput ] && tput setaf 1 >&/dev/null; then
    # We have color support; assume it's compliant with Ecma-48
    # (ISO/IEC-6429). (Lack of such support is extremely rare, and such
    # a case would tend to support setf rather than setaf.)
    color_prompt=yes
  else
    color_prompt=
  fi
fi

if [ "$color_prompt" = yes ]; then
  #PS1='${debian_chroot:+($debian_chroot)}\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '
  PS1='\[\e[38;5;214m\]$?\[\e[0m\] \[\e[38;5;214m\]\u@\h\[\e[0m\] \[\e[38;5;214m\]\W\[\e[0m\] \[\e[38;5;142m\]\\$\[\e[0m\] '
else
  PS1='${debian_chroot:+($debian_chroot)}\u@\h:\w\$ '
fi
unset color_prompt force_color_prompt

# If this is an xterm set the title to user@host:dir
case "$TERM" in
xterm* | rxvt*)
  PS1="\[\e]0;${debian_chroot:+($debian_chroot)}\u@\h: \w\a\]$PS1"
  ;;
*) ;;
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
  if ! . ~/.bash_aliases 2>/dev/null; then
    _dotfiles_warn 'failed to load ~/.bash_aliases'
  fi
fi

# Use MC's shell wrapper when packaged so F10 returns to its final directory.
for mc_profile in /usr/lib/mc/mc.sh /usr/libexec/mc/mc.sh; do
  if [ -r "$mc_profile" ]; then
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
    if ! . /usr/share/bash-completion/bash_completion 2>/dev/null; then
      _dotfiles_warn 'failed to load bash completion'
    fi
  elif [ -f /etc/bash_completion ]; then
    if ! . /etc/bash_completion 2>/dev/null; then
      _dotfiles_warn 'failed to load bash completion'
    fi
  fi
fi

add_to_path() {
  if [ -d "$1" ] && [[ ":${PATH:-}:" != *":$1:"* ]]; then
    PATH="$1${PATH:+":$PATH"}"
    export PATH
  fi
}

export GITUSER="surbanski"
export GHREPOS="$HOME/github.com/$GITUSER"

export LAB="$GHREPOS/lab"
export NOTES="$GHREPOS/notes-md"
export DOTFILES="$GHREPOS/dotfiles"
export WORK="$HOME/work"

add_to_path "$HOME/.local/share/nvim2/mason/bin"
add_to_path "$HOME/homebrew/bin"
add_to_path "$HOME/homebrew/sbin"
add_to_path "/home/linuxbrew/.linuxbrew/bin"
add_to_path "/home/linuxbrew/.linuxbrew/sbin"

if command -v brew >/dev/null 2>&1; then
  if HOMEBREW_PREFIX=$(brew --prefix 2>/dev/null); then
    _dotfiles_eval_init Homebrew "${HOMEBREW_PREFIX}/bin/brew" shellenv || true
    if [[ -r "${HOMEBREW_PREFIX}/etc/profile.d/bash_completion.sh" ]]; then
      if ! source "${HOMEBREW_PREFIX}/etc/profile.d/bash_completion.sh" 2>/dev/null; then
        _dotfiles_warn 'failed to load Homebrew completion'
      fi
    else
      for COMPLETION in "${HOMEBREW_PREFIX}/etc/bash_completion.d/"*; do
        if [[ -r ${COMPLETION} ]] && ! source "${COMPLETION}" 2>/dev/null; then
          _dotfiles_warn "failed to load Homebrew completion: $COMPLETION"
        fi
      done
    fi
  else
    _dotfiles_warn 'Homebrew is installed but brew --prefix failed'
  fi
fi

add_to_path "$HOME/bin"
add_to_path "$HOME/.local/bin"
add_to_path "$DOTFILES/scripts"
add_to_path "$HOME/.krew/bin"
add_to_path "$HOME/.asdf/shims"

export GIT_PROMPT_THEME=Single_line_Ubuntu

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

# fzf key bindings (prefer distro packages, fallback to user install if compatible)
if command -v fzf >/dev/null 2>&1; then
  if [ -r /usr/share/doc/fzf/examples/key-bindings.bash ]; then
    if ! source /usr/share/doc/fzf/examples/key-bindings.bash 2>/dev/null; then
      _dotfiles_warn 'failed to load fzf key bindings'
    fi
  elif [ -r /usr/share/fzf/shell/key-bindings.bash ]; then
    if ! source /usr/share/fzf/shell/key-bindings.bash 2>/dev/null; then
      _dotfiles_warn 'failed to load fzf key bindings'
    fi
  elif [ -r ~/.fzf.bash ]; then
    if fzf --bash >/dev/null 2>&1; then
      if ! source ~/.fzf.bash 2>/dev/null; then
        _dotfiles_warn 'failed to load ~/.fzf.bash'
      fi
    elif ! grep -q "fzf --bash" ~/.fzf.bash 2>/dev/null; then
      if ! source ~/.fzf.bash 2>/dev/null; then
        _dotfiles_warn 'failed to load ~/.fzf.bash'
      fi
    fi
  fi
fi

if command -v zoxide >/dev/null 2>&1 && ! declare -F __zoxide_hook >/dev/null; then
  _dotfiles_eval_init zoxide zoxide init bash || true
fi

if command -v kubectl >/dev/null 2>&1; then
  if ! declare -F __start_kubectl >/dev/null; then
    if kubectl_completion=$(kubectl completion bash 2>/dev/null); then
      if ! eval "$kubectl_completion" 2>/dev/null; then
        _dotfiles_warn 'kubectl returned invalid Bash completion'
      fi
    else
      _dotfiles_warn 'kubectl completion generation failed'
    fi
  fi
  if declare -F __start_kubectl >/dev/null && ! complete -F __start_kubectl k; then
    _dotfiles_warn 'failed to register kubectl completion for k'
  fi
  unset kubectl_completion
fi

if command -v oh-my-posh >/dev/null 2>&1 && ! declare -F _omp_hook >/dev/null; then
  if [[ -r $HOME/.oh-my-posh.omp.json ]]; then
    _dotfiles_eval_init 'Oh My Posh' oh-my-posh init bash --config "$HOME/.oh-my-posh.omp.json" || true
  else
    _dotfiles_warn 'Oh My Posh is installed but ~/.oh-my-posh.omp.json is missing'
  fi
fi

export NVIM_APPNAME="${NVIM_APPNAME:-nvim2}"
export VISUAL=nvim
export EDITOR=nvim

if [ -f ~/.extras ]; then
  if ! source ~/.extras 2>/dev/null; then
    _dotfiles_warn 'failed to load ~/.extras'
  fi
fi

_dotfiles_install_prompt_command
