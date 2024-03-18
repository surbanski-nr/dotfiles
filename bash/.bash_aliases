alias ff="fzf -m --preview 'bat --style=numbers --color=always --line-range :500 {}'"
alias ffv='nvim $(ff)'

alias zz='z -'

alias kc='kubectx'
alias kn='kubens'
alias k='kubectl'
complete -F __start_kubectl k

alias tp='terraform plan'

alias ga='git add .'
alias gf='git fetch'
alias gs='git status'
alias gc='git commit -m'

# finds all files recursively and sorts by last modification, ignore hidden files
alias last='find . -type f -not -path "*/\.*" -exec ls -lrt {} +'

alias t='tmux'
alias e='exit'

alias ..="cd .."
alias cdnotes='cd $NOTES'
alias cdlab='cd $LAB'
alias cddot='cd $DOTFILES'
alias cdrepos='cd $GHREPOS'
alias cdwork='cd $WORK'
alias c="clear"
alias in="cd \$NOTES/0-inbox/"

