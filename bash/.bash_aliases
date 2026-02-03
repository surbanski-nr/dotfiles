alias ff="fzf -m --preview 'bat --style=numbers --color=always --line-range :500 {}'"
alias ffv='nvim $(ff)'

alias vz='NVIM_APPNAME=nvim-lazy nvim'
alias vn='nvim'
alias v='NVIM_APPNAME=nvim2 nvim'

alias zz='z -'
kl() {
  kubectl logs "$1" | batcat --style=numbers --color=always
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
  pods=$(kubectl get pods --no-headers -o custom-columns=":metadata.name" | grep "^$1")
  for pod in $pods; do kubectl logs $pod >$pod.log; done
}
alias kcl='kubectl get pods --sort-by=.metadata.creationTimestamp --no-headers | grep "^configurator-" | tail -n1 | awk "{print \$1}" | xargs kubectl logs | less'

complete -F __start_kubectl k

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
