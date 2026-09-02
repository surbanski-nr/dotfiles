#!/usr/bin/env bash

set -euo pipefail

repo_dir=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=/dev/null
source "$repo_dir/scripts/nvim2-release"

missing_uid=4294967294
[[ -z $(lookup_uid_owner "$missing_uid") ]]

current_uid=$(id -u)
[[ $(lookup_uid_owner "$current_uid") == "$(id -un)" ]]

printf 'Nvim2 release tests passed\n'
