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
  local candidate kind label path
  label=$1
  shift

  for candidate in "$@"; do
    if path=$(command -v "$candidate" 2>/dev/null); then
      kind=$(type -t "$candidate")
      if [[ $kind == alias || $kind == function ]]; then
        printf '  SHADOWED %-21s %s is a %s\n' "$label" "$candidate" "$kind"
        return 1
      fi
      printf '  OK      %-22s %s: %s\n' "$label" "$candidate" "$path"
      return 0
    fi
  done
  printf '  MISSING %s\n' "$label"
  return 1
}

_dotfiles_check_backing_command() {
  local command_name=$2
  local kind path

  if ! path=$(type -P "$command_name" 2>/dev/null); then
    printf '  MISSING %s\n' "$1"
    return 1
  fi
  kind=$(type -t "$command_name")
  if [[ $kind == alias || $kind == function ]]; then
    printf '  OK      %-22s %s: %s (shell wrapper: %s)\n' \
      "$1" "$command_name" "$path" "$kind"
  else
    printf '  OK      %-22s %s: %s\n' "$1" "$command_name" "$path"
  fi
}

_dotfiles_check_version() {
  local label=$1
  local command_name=$2
  local expected=${3#v}
  local actual output path
  shift 3

  if ! path=$(command -v "$command_name" 2>/dev/null); then
    printf '  ABSENT  %-22s selected=%s\n' "$label" "$expected"
    return 0
  fi
  if [[ $(type -t "$command_name") == alias || $(type -t "$command_name") == function ]]; then
    printf '  SHADOWED %-21s selected=%s provider=%s\n' \
      "$label" "$expected" "$(type -t "$command_name")"
    return 1
  fi
  if ! output=$(timeout 5s "$command_name" "$@" 2>&1); then
    printf '  BROKEN  %-22s selected=%s path=%s\n' "$label" "$expected" "$path"
    return 1
  fi
  actual=${output%%$'\n'*}
  if [[ $output != *"$expected"* ]]; then
    printf '  MISMATCH %-20s selected=%s actual=%s path=%s\n' \
      "$label" "$expected" "$actual" "$path"
    return 1
  fi
  if [[ (-e $HOME/bin/$command_name || -L $HOME/bin/$command_name) &&
    $path != "$HOME/bin/$command_name" ]]; then
    printf '  SHADOWED %-21s selected=%s path=%s managed=%s\n' \
      "$label" "$expected" "$path" "$HOME/bin/$command_name"
    return 1
  fi
  printf '  OK      %-22s selected=%s actual=%s path=%s\n' \
    "$label" "$expected" "$actual" "$path"
}

_dotfiles_check_release_version() {
  local label=$1
  local command_name=$2
  local catalog=$3
  local tool=$4
  shift 4

  setup_release_first "$catalog" "$tool" || return 1
  _dotfiles_check_version "$label" "$command_name" "$RELEASE_VERSION" "$@"
}

dotfiles-check() (
  local manifest_dir=${DOTFILES:-}
  local missing=0
  local release_id release_root

  if [[ -z $manifest_dir ]]; then
    manifest_dir=$(CDPATH='' cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/.." && pwd)
  fi
  release_root=${manifest_dir%/dotfiles}
  if [[ -f $release_root/release.env && -x $release_root/bin/dotfiles-release ]]; then
    release_id=${release_root##*/}
    "$release_root/bin/dotfiles-release" health "$release_id" || return
    for command_name in dotfiles-release nvim tmux node npm npx corepack rg \
      zoxide k9s kubectx kubens oh-my-posh task fzf terraform; do
      [[ $(readlink -f -- "$HOME/bin/$command_name" 2>/dev/null) == \
        "$release_root/"* ]] || {
        printf '  MISMATCH active release command: %s\n' "$command_name" >&2
        return 1
      }
    done
    return 0
  fi
  if [[ -r $manifest_dir/versions.env && -r $manifest_dir/validation.env ]]; then
    # shellcheck source=../validation.env
    source "$manifest_dir/validation.env"
    # shellcheck source=../versions.env
    source "$manifest_dir/versions.env"
    # Loaded only when dotfiles-check runs, never during normal shell startup.
    # shellcheck source=../scripts/setup-lib
    source "$manifest_dir/scripts/setup-lib"
    SETUP_PROGRAM=dotfiles-check
    setup_validate_versions || return
    setup_validate_validation_versions || return
  fi

  printf 'Required:\n'
  _dotfiles_check_tool git git || missing=1
  _dotfiles_check_tool nvim nvim || missing=1
  _dotfiles_check_tool tmux tmux || missing=1
  _dotfiles_check_tool less less || missing=1
  _dotfiles_check_backing_command mc mc || missing=1
  _dotfiles_check_tool node node || missing=1
  _dotfiles_check_tool Python python python3 || missing=1
  _dotfiles_check_tool ripgrep rg || missing=1

  printf '\nOptional integrations:\n'
  _dotfiles_check_tool fzf fzf || true
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
  _dotfiles_check_tool jq jq || true
  _dotfiles_check_tool yq yq || true
  _dotfiles_check_tool 'GitHub CLI' gh || true
  _dotfiles_check_tool 'Oh My Posh' oh-my-posh || true
  _dotfiles_check_tool ssh-agent ssh-agent || true
  _dotfiles_check_tool ssh-add ssh-add || true

  if declare -p TOOL_RELEASES VALIDATION_RELEASES >/dev/null 2>&1; then
    printf '\nSelected versions:\n'
    _dotfiles_check_release_version gh gh TOOL_RELEASES gh --version || missing=1
    _dotfiles_check_release_version kyverno kyverno TOOL_RELEASES kyverno version || missing=1
    _dotfiles_check_release_version Task task VALIDATION_RELEASES task --version || missing=1
    _dotfiles_check_release_version Trivy trivy TOOL_RELEASES trivy --version || missing=1
    _dotfiles_check_release_version k9s k9s TOOL_RELEASES k9s version --short || missing=1
    _dotfiles_check_release_version kubeconform kubeconform TOOL_RELEASES kubeconform -v || missing=1
    _dotfiles_check_release_version ShellCheck shellcheck TOOL_RELEASES shellcheck --version || missing=1
    _dotfiles_check_release_version 'Oh My Posh' oh-my-posh TOOL_RELEASES oh-my-posh version || missing=1
    _dotfiles_check_release_version kubectx kubectx TOOL_RELEASES kubectx --version || missing=1
    _dotfiles_check_release_version kubens kubens TOOL_RELEASES kubens --version || missing=1
    _dotfiles_check_release_version ripgrep rg TOOL_RELEASES rg --version || missing=1
    _dotfiles_check_release_version zoxide zoxide TOOL_RELEASES zoxide --version || missing=1
    _dotfiles_check_release_version uv uv TOOL_RELEASES uv --version || missing=1
    _dotfiles_check_release_version Neovim nvim TOOL_RELEASES nvim --version || missing=1
    _dotfiles_check_release_version Terraform terraform TOOL_RELEASES terraform version || missing=1
    _dotfiles_check_release_version kubectl kubectl TOOL_RELEASES kubectl version --client || missing=1
    _dotfiles_check_release_version Helm helm TOOL_RELEASES helm version --short || missing=1
    _dotfiles_check_release_version Node.js node TOOL_RELEASES nodejs --version || missing=1
    _dotfiles_check_release_version Python python TOOL_RELEASES python --version || missing=1
    _dotfiles_check_release_version Terragrunt terragrunt TOOL_RELEASES terragrunt --version || missing=1
  fi

  return "$missing"
)

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

unalias vz vold v zz kc kn k tp t 2>/dev/null || true
unset -f vz 2>/dev/null || true
vold() {
  _dotfiles_require vold nvim || return
  NVIM_APPNAME=old-nvim command nvim "$@"
}
v() {
  _dotfiles_require v nvim || return
  NVIM_APPNAME=nvim2 command nvim "$@"
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
  local toggles

  _dotfiles_require kp oh-my-posh || return
  toggles=$(command oh-my-posh get toggles) || return
  command oh-my-posh toggle kubectl || return
  if [[ $toggles == *'- kubectl'* ]]; then
    printf 'Kubernetes prompt enabled\n'
  else
    printf 'Kubernetes prompt disabled\n'
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
alias cdnotes='cd "$NOTES"'
alias cdlab='cd "$LAB"'
alias cddot='cd "$DOTFILES"'
alias cdrepos='cd "$GHREPOS"'
alias cdwork='cd "$WORK"'
alias c="clear"
alias in="cd \$NOTES/00-inbox/"
