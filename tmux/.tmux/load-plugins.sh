#!/usr/bin/env bash

set -euo pipefail

self=$(readlink -f -- "${BASH_SOURCE[0]}")
repo_dir=$(CDPATH='' cd -- "$(dirname -- "$self")/../.." && pwd)
# shellcheck source=../../scripts/setup-lib
source "$repo_dir/scripts/setup-lib"
load_config "$repo_dir/tools.env"

if [[ -n ${TMUX_OFFLINE_RELEASE_ROOT:-} ]]; then
  root=$TMUX_OFFLINE_RELEASE_ROOT/share/tmux/plugins
  metadata=$TMUX_OFFLINE_RELEASE_ROOT/release.env
  serialized_tools=$(awk -F= '
    $1 == "OFFLINE_RELEASE_TOOLS" { tools = $2; count++ }
    END {
      if (count != 1 || tools == "") {
        exit 1
      }
      print tools
    }
  ' "$metadata") || {
    printf 'tmux plugins: release is missing its OFFLINE_RELEASE_TOOLS selection: %s\n' "$metadata" >&2
    exit 1
  }
  IFS=, read -r -a selected_tools <<<"$serialized_tools"
else
  store=${DOTFILES_RELEASE_ROOT:-$HOME/dotfiles-releases}
  root=${DOTFILES_TMUX_PLUGIN_DIR:-$store/online/share/tmux/plugins}
  if [[ -z ${DOTFILES_TMUX_PLUGIN_DIR:-} && ! -d $root ]]; then
    root=$HOME/.tmux/plugins
  fi
  selected_tools=("${TOOLS[@]}")
fi
if [[ $root != /* || $root == *[[:cntrl:]]* ]]; then
  printf 'tmux plugins: expected an absolute plugin directory without control characters: %s\n' "$root" >&2
  exit 1
fi

entries=()
for name in "${selected_tools[@]}"; do
  [[ -v TMUX_PLUGINS[$name] ]] || continue
  [[ $name =~ ^tmux-[a-z0-9-]+$ ]] || exit 1
  entry=$root/$name/${name#tmux-}.tmux
  if [[ ! -x $entry ]]; then
    printf 'tmux plugins: missing %s; run setup-tools or reinstall the offline release\n' "$entry" >&2
    exit 1
  fi
  entries+=("$entry")
done
if ((${#entries[@]})) && [[ $root == *[[:space:]]* ]]; then
  printf 'tmux plugins: upstream plugins require a directory without whitespace: %s\n' "$root" >&2
  exit 1
fi
for entry in "${entries[@]}"; do
  "$entry"
done
