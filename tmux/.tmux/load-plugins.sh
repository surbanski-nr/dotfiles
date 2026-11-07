#!/usr/bin/env bash

set -euo pipefail

self=$(readlink -f -- "${BASH_SOURCE[0]}")
repo_dir=$(CDPATH='' cd -- "$(dirname -- "$self")/../.." && pwd)
# shellcheck source=../../tools.env
source "$repo_dir/tools.env"

if [[ -n ${TMUX_OFFLINE_RELEASE_ROOT:-} ]]; then
  root=$TMUX_OFFLINE_RELEASE_ROOT/share/tmux/plugins
  tools=("${OFFLINE_RELEASE_TOOLS[@]}")
  metadata=$TMUX_OFFLINE_RELEASE_ROOT/release.env
  if [[ -f $metadata ]] && grep -qx 'RELEASE_FORMAT=2' "$metadata"; then
    serialized_profile=$(awk -F= '$1 == "OFFLINE_TOOLS" { print $2 }' "$metadata")
    IFS=, read -r -a tools <<<"$serialized_profile"
  fi
else
  root=${DOTFILES_TMUX_PLUGIN_DIR:-$HOME/.tmux/plugins}
  tools=("${TOOLS[@]}")
fi
if [[ $root != /* || $root == *[[:cntrl:]]* ]]; then
  printf 'tmux plugins: expected an absolute plugin directory without control characters: %s\n' "$root" >&2
  exit 1
fi

entries=()
for name in "${tools[@]}"; do
  [[ -v TMUX_PLUGINS[$name] ]] || continue
  [[ $name =~ ^tmux-[a-z0-9-]+$ ]] || exit 1
  entry=$root/$name/${name#tmux-}.tmux
  if [[ ! -x $entry ]]; then
    printf 'tmux plugins: missing %s; run setup-tools or reinstall the offline release\n' "$entry" >&2
    exit 1
  fi
  entries+=("$entry")
done
for entry in "${entries[@]}"; do
  "$entry"
done
