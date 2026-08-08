# shellcheck shell=bash

_bat_path() {
  command -v bat 2>/dev/null || command -v batcat 2>/dev/null
}

ff() {
  local preview viewer
  if viewer=$(_bat_path); then
    preview="$viewer --style=numbers --color=always --line-range=:500 -- {}"
  else
    preview='sed -n "1,500p" -- {}'
  fi
  fzf -m --preview "$preview"
}

alias ffv='nvim $(ff)'

alias vz='NVIM_APPNAME=nvim-lazy nvim'
alias vn='nvim'
alias v='NVIM_APPNAME=nvim2 nvim'

alias zz='z -'
kl() {
  local viewer
  if viewer=$(_bat_path); then
    kubectl logs "$1" | "$viewer" --style=numbers --color=always
  else
    kubectl logs "$1" | less
  fi
}
alias kc='kubectx'
alias kn='kubens'
alias k='kubectl'
kgp() {
  if [ "$#" -eq 0 ]; then
    kubectl get pods --sort-by=.metadata.creationTimestamp
  else
    kubectl get pods --sort-by=.metadata.creationTimestamp | grep "$1"
  fi
}
kge() {
  if [ "$#" -eq 0 ]; then
    kubectl get events --sort-by=.metadata.creationTimestamp -w
  else
    kubectl get events --sort-by=.metadata.creationTimestamp -w -n "$1"
  fi
}
kpl() {
  local pod
  while IFS= read -r pod; do
    kubectl logs "$pod" >"$pod.log"
  done < <(kubectl get pods --no-headers -o custom-columns=":metadata.name" |
    awk -v prefix="${1:-}" 'index($0, prefix) == 1')
}
kcl() {
  local pod
  pod=$(kubectl get pods --sort-by=.metadata.creationTimestamp --no-headers |
    awk '/^configurator-/ { pod=$1 } END { print pod }')
  if [ -z "$pod" ]; then
    echo "No configurator pod found" >&2
    return 1
  fi
  kubectl logs "$pod" | less
}

alias tp='terraform plan'

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

alias t='tmux'
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
