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
    printf '  MISSING %-22s selected=%s\n' "$label" "$expected"
    return 1
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
    printf '  SHADOWED %-21s selected=%s path=%s override=%s\n' \
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
  local check
  local -a arguments=()
  shift 4

  select_default_release "$catalog" "$tool" || return 1
  if (($#)); then
    arguments=("$@")
  else
    check=${TOOL_CHECKS[$command_name]:-}
    check=${check#*|}
    read -r -a arguments <<<"${check:---version}"
  fi
  _dotfiles_check_version "$label" "$command_name" "$RELEASE_VERSION" "${arguments[@]}"
}

_dotfiles_check_tmux_plugin() {
  local name=$1 root=${DOTFILES_TMUX_PLUGIN_DIR:-$HOME/.tmux/plugins} actual

  select_git_plugin TMUX_PLUGINS "$name" || return
  if [[ ! -x $root/$name/${name#tmux-}.tmux ]]; then
    printf '  MISSING %s\n' "$name"
    return 1
  fi
  actual=$(git -C "$root/$name" rev-parse HEAD 2>/dev/null) || return
  if [[ $actual != "$PLUGIN_COMMIT" ]]; then
    printf '  MISMATCH %s selected=%s actual=%s\n' "$name" "$PLUGIN_COMMIT" "$actual"
    return 1
  fi
  printf '  OK      %s commit=%s\n' "$name" "$actual"
}

dotfiles-check() (
  local manifest_dir=${DOTFILES:-} missing=0 release_root tool command_name command_output
  local -a selected=()

  if [[ -z $manifest_dir ]]; then
    manifest_dir=$(CDPATH='' cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/.." && pwd)
  fi
  release_root=${manifest_dir%/dotfiles}
  if [[ -L ${DOTFILES_RELEASE_ROOT:-$HOME/dotfiles-releases}/current ]]; then
    release_root=${DOTFILES_RELEASE_ROOT:-$HOME/dotfiles-releases}/current
    if [[ $(readlink -f -- "$release_root/dotfiles") == "$(readlink -f -- "$manifest_dir")" ]]; then
      [[ -x $release_root/bin/dotfiles-release ]] || {
        printf 'dotfiles-check: active release manager is missing: %s\n' \
          "$release_root/bin/dotfiles-release" >&2
        return 1
      }
      DOTFILES_RELEASE_ROOT=${release_root%/current} "$release_root/bin/dotfiles-release" health
      return
    fi
    release_root=${manifest_dir%/dotfiles}
  fi
  if [[ -f $release_root/release.env && -x $release_root/bin/dotfiles-release ]]; then
    DOTFILES_RELEASE_ROOT=${release_root%/*} "$release_root/bin/dotfiles-release" health
    return
  fi
  if [[ -r $manifest_dir/tools.env ]]; then
    # Loaded only for diagnostics, never during normal shell startup.
    # shellcheck source=../scripts/setup-lib
    source "$manifest_dir/scripts/setup-lib"
    source "$manifest_dir/scripts/setup-catalog-lib"
    source "$manifest_dir/scripts/setup-tools-lib"
    load_tool_catalog "$manifest_dir/tools.env"
    validate_tool_config online || return
    validate_tool_selection TOOLS online || return
    selected=("${TOOLS[@]}")
  fi

  printf 'System utilities:\n'
  _dotfiles_check_tool git git || missing=1
  _dotfiles_check_tool less less || missing=1
  _dotfiles_check_backing_command mc mc || missing=1

  if (("${#selected[@]}" > 0)); then
    printf '\nSelected tools:\n'
    for tool in "${selected[@]}"; do
      if [[ -v TMUX_PLUGINS[$tool] ]]; then
        _dotfiles_check_tmux_plugin "$tool" || missing=1
        continue
      fi
      if [[ $tool == python ]]; then
        _dotfiles_check_release_version 'uv Python' uv TOOL_RELEASES python \
          python find --directory "${XDG_CONFIG_HOME:-$HOME/.config}/uv" \
          --no-project --managed-python --offline --show-version || missing=1
        continue
      fi
      command_output=$(tool_commands "$tool") || return
      while IFS= read -r command_name; do
        _dotfiles_check_tool "$command_name" "$command_name" || {
          missing=1
          continue
        }
        [[ -v TOOL_CHECKS[$command_name] ]] || continue
        _dotfiles_check_release_version "$command_name" "$command_name" TOOL_RELEASES "$tool" || missing=1
      done <<<"$command_output"
    done

    printf '\nOptional asdf runtimes:\n'
    if command -v asdf >/dev/null 2>&1; then
      while IFS= read -r tool; do
        command_name=$tool
        [[ $tool != nodejs ]] || command_name=node
        _dotfiles_check_release_version "$tool" "$command_name" TOOL_RELEASES "$tool" || missing=1
      done < <(printf '%s\n' "${!ASDF_PLUGINS[@]}" | LC_ALL=C sort)
    else
      printf '  asdf is not installed\n'
    fi
  fi

  printf '\nOptional integrations:\n'
  _dotfiles_check_tool bat bat batcat || true
  _dotfiles_check_tool ansible ansible || true
  _dotfiles_check_tool 'container runtime' docker podman || true
  _dotfiles_check_tool jq jq || true
  _dotfiles_check_tool ssh-agent ssh-agent || true
  _dotfiles_check_tool ssh-add ssh-add || true
  return "$missing"
)

# Remove the old alias before parsing its function replacement on reload.
unalias ff 2>/dev/null || true
_dotfiles_fzf_preview() {
  local viewer
  if viewer=$(_bat_path); then
    printf '%q --style=numbers --color=always --line-range=:500 -- {}\n' "$viewer"
  else
    printf '%s\n' 'sed -n "1,500p" -- {}'
  fi
}
# FZF parses the option string before passing the preview command to a shell.
printf -v FZF_CTRL_T_OPTS '%s %q' --preview "$(_dotfiles_fzf_preview)"
export FZF_CTRL_T_OPTS

ff() {
  if ! command -v fzf >/dev/null 2>&1; then
    printf 'ff requires fzf\n' >&2
    return 127
  fi
  fzf -m --preview "$(_dotfiles_fzf_preview)"
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
unset -f vz vold 2>/dev/null || true
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
alias gs='git status --short'
alias gd='git diff'
alias gdc='git diff --cached'
alias gc='git commit -m'
alias gti='git'

unalias gca 2>/dev/null || true
gca() {
  if (($#)); then
    command git commit --amend -m "$@"
  else
    command git commit --amend --no-edit
  fi
}

unalias gl 2>/dev/null || true
gl() {
  local -a limit=()
  if [[ ${1:-} =~ ^[0-9]+$ ]]; then
    limit=(-n "$1")
    shift
  fi
  command git log --color=auto --decorate=short \
    --date=format:'%d.%m.%Y' \
    --format='%C(auto)%h%d%C(reset) %s | %an %ad' "${limit[@]}" "$@"
}

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
