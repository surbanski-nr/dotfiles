# shellcheck shell=bash

_bat_path() {
  command -v bat 2>/dev/null || command -v batcat 2>/dev/null
}

_dotfiles_require() {
  local caller=$1
  local command_name=$2

  if ! command -v "$command_name" >/dev/null 2>&1; then
    printf 'dotfiles: %s requires %s\n' "$caller" "$command_name" >&2
    return 127
  fi
}

_dotfiles_check_tool() {
  local candidate label path
  label=$1
  shift

  for candidate in "$@"; do
    if path=$(command -v "$candidate" 2>/dev/null); then
      printf '  OK      %-22s %s: %s\n' "$label" "$candidate" "$path"
      return 0
    fi
  done
  printf '  MISSING %s\n' "$label"
  return 1
}

dotfiles-check() {
  local missing=0

  printf 'Required:\n'
  _dotfiles_check_tool git git || missing=1
  _dotfiles_check_tool nvim nvim || missing=1
  _dotfiles_check_tool tmux tmux || missing=1
  _dotfiles_check_tool fzf fzf || missing=1
  _dotfiles_check_tool less less || missing=1
  _dotfiles_check_tool mc mc || missing=1

  printf '\nOptional integrations:\n'
  _dotfiles_check_tool bat bat batcat || true
  _dotfiles_check_tool fd fd fdfind || true
  _dotfiles_check_tool zoxide zoxide || true
  _dotfiles_check_tool kubectl kubectl || true
  _dotfiles_check_tool kubectx kubectx || true
  _dotfiles_check_tool kubens kubens || true
  _dotfiles_check_tool k9s k9s || true
  _dotfiles_check_tool helm helm || true
  _dotfiles_check_tool terraform terraform || true
  _dotfiles_check_tool ansible ansible || true
  _dotfiles_check_tool 'container runtime' docker podman || true
  _dotfiles_check_tool ripgrep rg || true
  _dotfiles_check_tool jq jq || true
  _dotfiles_check_tool yq yq || true
  _dotfiles_check_tool 'GitHub CLI' gh || true
  _dotfiles_check_tool 'Oh My Posh' oh-my-posh || true
  _dotfiles_check_tool Homebrew brew || true
  _dotfiles_check_tool ssh-agent ssh-agent || true
  _dotfiles_check_tool ssh-add ssh-add || true

  return "$missing"
}

# bat pages long output with less: j/k scroll, Space/b page, / searches,
# n/N moves between matches, g/G jumps to the ends, h shows help, and q quits.
unalias cat 2>/dev/null || true
if command -v bat >/dev/null 2>&1; then
  alias cat='bat'
elif command -v batcat >/dev/null 2>&1; then
  alias cat='batcat'
fi

# Remove the old alias before parsing its function replacement on reload.
unalias ff 2>/dev/null || true
ff() {
  local preview viewer
  if ! command -v fzf >/dev/null 2>&1; then
    printf 'ff requires fzf\n' >&2
    return 127
  fi
  if viewer=$(_bat_path); then
    preview="$viewer --style=numbers --color=always --line-range=:500 -- {}"
  else
    preview='sed -n "1,500p" -- {}'
  fi
  fzf -m --preview "$preview"
}

unalias ffv 2>/dev/null || true
ffv() {
  local selection
  local -a files=()
  _dotfiles_require ffv nvim || return
  selection=$(ff) || return
  [[ -n $selection ]] || return 0
  mapfile -t files <<<"$selection"
  NVIM_APPNAME=nvim2 command nvim -- "${files[@]}"
}

unalias vz vold v vi vim zz kc kn k tp t 2>/dev/null || true
vz() {
  _dotfiles_require vz nvim || return
  NVIM_APPNAME=nvim-lazy command nvim "$@"
}
vold() {
  _dotfiles_require vold nvim || return
  NVIM_APPNAME=old-nvim command nvim "$@"
}
v() {
  _dotfiles_require v nvim || return
  NVIM_APPNAME=nvim2 command nvim "$@"
}
vi() {
  v "$@"
}
vim() {
  v "$@"
}

zz() {
  _dotfiles_require zz z || return
  z -
}
kl() {
  local viewer

  _dotfiles_require kl kubectl || return
  if [[ $# -ne 1 ]]; then
    printf 'Usage: kl POD\n' >&2
    return 2
  fi
  if viewer=$(_bat_path); then
    kubectl logs "$1" | "$viewer" --style=numbers --color=always
  else
    _dotfiles_require kl less || return
    kubectl logs "$1" | less
  fi
}
kc() {
  _dotfiles_require kc kubectx || return
  command kubectx "$@"
}
kn() {
  _dotfiles_require kn kubens || return
  command kubens "$@"
}
k() {
  _dotfiles_require k kubectl || return
  command kubectl "$@"
}
kp() {
  if [[ -n ${POSH_KUBE:-} ]]; then
    unset POSH_KUBE
    printf 'Kubernetes prompt disabled\n'
  else
    export POSH_KUBE=1
    printf 'Kubernetes prompt enabled\n'
  fi
}
kgp() {
  _dotfiles_require kgp kubectl || return
  if [ "$#" -eq 0 ]; then
    kubectl get pods --sort-by=.metadata.creationTimestamp
  else
    kubectl get pods --sort-by=.metadata.creationTimestamp | grep -- "$1"
  fi
}
kge() {
  _dotfiles_require kge kubectl || return
  if [ "$#" -eq 0 ]; then
    kubectl get events --sort-by=.metadata.creationTimestamp -w
  else
    kubectl get events --sort-by=.metadata.creationTimestamp -w -n "$1"
  fi
}
kpl() {
  local pod pods prefix status temporary

  _dotfiles_require kpl kubectl || return
  prefix=${1:-}
  pods=$(kubectl get pods --no-headers -o custom-columns=":metadata.name") || return
  while IFS= read -r pod; do
    [[ -n $pod && $pod == "$prefix"* ]] || continue
    temporary=$(mktemp ".${pod}.log.XXXXXX") || return
    if kubectl logs "$pod" >"$temporary"; then
      if mv -- "$temporary" "$pod.log"; then
        :
      else
        status=$?
        rm -f -- "$temporary"
        return "$status"
      fi
    else
      status=$?
      rm -f -- "$temporary"
      return "$status"
    fi
  done <<<"$pods"
}
kcl() {
  local candidate pod pods

  _dotfiles_require kcl kubectl || return
  _dotfiles_require kcl less || return
  pods=$(kubectl get pods --sort-by=.metadata.creationTimestamp --no-headers) || return
  while read -r candidate _; do
    [[ $candidate == configurator-* ]] && pod=$candidate
  done <<<"$pods"
  if [ -z "$pod" ]; then
    printf 'No configurator pod found\n' >&2
    return 1
  fi
  kubectl logs "$pod" | less
}

tp() {
  _dotfiles_require tp terraform || return
  command terraform plan "$@"
}

alias ga='git add .'
alias gf='git fetch'
alias gp='git pull'
alias gs='git status'
alias gd='git diff'
alias gdc='git diff --cached'
alias gc='git commit -m'
alias gti='git'

# finds all files recursively and sorts by last modification, ignore hidden files
alias last='find . -type f -not -path "*/\.*" -exec ls -lrt {} +'

t() {
  _dotfiles_require t tmux || return
  command tmux "$@"
}
alias e='exit'

alias mkdir='mkdir -p'

alias ..="cd .."
alias cdnotes='cd $NOTES'
alias cdlab='cd $LAB'
alias cddot='cd $DOTFILES'
alias cdrepos='cd $GHREPOS'
alias cdwork='cd $WORK'
alias c="clear"
alias in="cd \$NOTES/00-inbox/"
