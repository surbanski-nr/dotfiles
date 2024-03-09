# use fp to do a fzf search and preview the files
alias fp="fzf --preview 'bat --style=numbers --color=always --line-range :500 {}'"
# search for a file with fzf and open it in vim
alias vf='v $(fp)'

alias kc='kubectx'
alias kn='kubens'
alias k='kubectl'

alias tp='terraform plan'

alias gf='git fetch'
alias gp='git pull'
alias gs='git status'

# finds all files recursively and sorts by last modification, ignore hidden files
alias last='find . -type f -not -path "*/\.*" -exec ls -lrt {} +'

alias t='tmux'
alias e='exit'

alias ..="cd .."
alias cdnotes='cd $NOTES'
alias cdlab='cd $LAB'
alias cddot='cd $DOTFILES'
alias cdrepos='cd $GHREPOS'
alias c="clear"
alias in="cd \$NOTES/0-inbox/"

