#!/usr/bin/env bash

set -euo pipefail

self=$(readlink -f -- "${BASH_SOURCE[0]}")
repo_dir=$(CDPATH='' cd -- "$(dirname -- "$self")/../.." && pwd)
# shellcheck source=../../tools.env
source "$repo_dir/tools.env"

if [[ -n ${TMUX_OFFLINE_RELEASE_ROOT:-} ]]; then
  root=$TMUX_OFFLINE_RELEASE_ROOT/share/tmux/plugins
  profile_name=OFFLINE_RELEASE_TOOLS
else
  root=${DOTFILES_TMUX_PLUGIN_DIR:-$HOME/.tmux/plugins}
  profile_name=TOOLS
fi
if [[ $root != /* || $root == *[[:space:][:cntrl:]]* ]]; then
  printf 'tmux plugins: expected an absolute plugin directory without whitespace: %s\n' "$root" >&2
  exit 1
fi

declare -n profile=$profile_name
entries=()
for name in "${profile[@]}"; do
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
