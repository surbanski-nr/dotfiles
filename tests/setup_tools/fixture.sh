#!/usr/bin/env bash

# Fixture globals are consumed by the scenario scripts.
# shellcheck disable=SC2034

repo_dir=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)

cleanup() {
  local status=$?
  trap - EXIT
  set +e
  if [[ -n ${killed_lock_pid:-} ]]; then
    kill "$killed_lock_pid" 2>/dev/null
    wait "$killed_lock_pid" 2>/dev/null
  fi
  find "$test_root" -depth -delete
  exit "$status"
}

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_link() {
  local path=$1
  local target=$2
  [[ -L $path ]] || fail "$path is not a link"
  [[ $(readlink -- "$path") == "$target" ]] || fail "$path has the wrong target"
}

write_fake() {
  local path=$1
  local name=$2
  local version=${3#v}

  mkdir -p "$(dirname -- "$path")"
  cat >"$path" <<EOF
#!/usr/bin/env bash
if [[ '$name' == k9s && \$* != 'version --short' ]]; then exit 93; fi
if [[ '$name' == oh-my-posh && \$* != version ]]; then exit 94; fi
if [[ '$name' == go && \$* != version ]]; then exit 95; fi
if [[ '$name' == kind && \$* != version ]]; then exit 96; fi
if [[ '$name' == uv && \${1:-} == python ]]; then
  printf '%s\\n' "\$*" >>"\$TEST_UV_LOG"
  case \${2:-} in
    install)
      [[ " \$* " == *' --no-bin '* && " \$* " == *' --no-config '* ]] || exit 97
      for target in "\${@:3}"; do
        [[ \$target != --* ]] || continue
        [[ \$target != \${TEST_UV_FAIL_VERSION:-} ]] || exit 65
        mkdir -p "\$HOME/.local/share/uv/python/\$target"
      done
      ;;
    pin)
      [[ " \$* " == *' --global '* && " \$* " == *' --no-project '* ]] || exit 98
      mkdir -p "\${XDG_CONFIG_HOME:-\$HOME/.config}/uv"
      printf '%s\\n' "\${!#}" >"\${XDG_CONFIG_HOME:-\$HOME/.config}/uv/.python-version"
      ;;
    *) exit 99 ;;
  esac
  exit 0
fi
printf '%s\\n' '$name $version'
EOF
  chmod 0755 "$path"
}

write_source_fixture() {
  local path=$1 name=$2 version=$3

  mkdir -p "$path"
  write_fake "$path/fixture-bin" "$name" "$version"
  cat >"$path/configure" <<EOF
#!/usr/bin/env bash
set -euo pipefail
prefix=
for argument in "\$@"; do
  case \$argument in --prefix=*) prefix=\${argument#*=} ;; esac
done
[[ -n \$prefix ]]
mkdir -p "\$prefix/bin"
cp fixture-bin "\$prefix/bin/$name"
printf 'all:\n\t@:\ninstall:\n\t@:\n' >Makefile
EOF
  chmod 0755 "$path/configure"
}

append_release() {
  local file=$1 catalog=$2 tool=$3 version=$4 url=$5 digest=$6 value

  value=$'\n'"$version|$url|$digest"$'\n'
  printf '%s[%q]=%q\n' "$catalog" "$tool" "$value" >>"$file"
}

load_test_versions() {
  local repository=$1

  # shellcheck disable=SC1090
  source "$repository/tools.env"
  # shellcheck disable=SC1090
  source "$repository/scripts/setup-lib"
  select_default_release TOOL_RELEASES gh; GH_VERSION=$RELEASE_VERSION
  select_default_release TOOL_RELEASES htop; HTOP_VERSION=$RELEASE_VERSION
  select_default_release TOOL_RELEASES k9s; K9S_VERSION=$RELEASE_VERSION
  select_default_release TOOL_RELEASES kind; KIND_VERSION=$RELEASE_VERSION
  select_default_release TOOL_RELEASES yq; YQ_VERSION=$RELEASE_VERSION
  select_default_release TOOL_RELEASES oh-my-posh; OMP_VERSION=$RELEASE_VERSION
  select_default_release TOOL_RELEASES uv; UV_VERSION=$RELEASE_VERSION
  select_default_release TOOL_RELEASES nvim; NVIM_VERSION=$RELEASE_VERSION
  select_default_release TOOL_RELEASES tmux; TMUX_VERSION=$RELEASE_VERSION
  select_default_release TOOL_RELEASES fd; FD_VERSION=$RELEASE_VERSION
  select_default_release TOOL_RELEASES go; GO_VERSION=$RELEASE_VERSION
  select_default_release TOOL_RELEASES python; PYTHON_VERSION=$RELEASE_VERSION
}

make_test_repo() {
  local destination=$1

  mkdir -p "$destination/scripts"
  cp "$repo_dir/setup-tools" "$destination/setup-tools"
  cp "$repo_dir/scripts/setup-lib" "$destination/scripts/setup-lib"
  cp "$repo_dir/tools.env" "$destination/tools.env"
  cp "$repo_dir/system.env" "$destination/system.env"
  cp "$repo_dir/tools-probes.env" "$destination/tools-probes.env"
}

run_setup() {
  local target_home=$1 repository=$2 archives=$3
  shift 3

  HOME="$target_home" TEST_TOOL_ARCHIVES="$archives" PATH="$test_root/shim:$PATH" \
    "$repository/setup-tools" "$@"
}

make_archives() {
  local repository=$1
  local archive_root=$2
  local work=$test_root/archive-work
  local digest

  load_test_versions "$repository"
  mkdir -p "$archive_root" "$work"

  write_fake "$archive_root/yq/$YQ_VERSION/yq_linux_amd64" yq "$YQ_VERSION"
  digest=$(sha256sum "$archive_root/yq/$YQ_VERSION/yq_linux_amd64" | awk '{print $1}')
  append_release "$repository/tools.env" TOOL_RELEASES yq "$YQ_VERSION" \
    "https://example.invalid/yq/$YQ_VERSION/yq_linux_amd64" "$digest"

  write_fake "$work/fd-v${FD_VERSION}-x86_64-unknown-linux-musl/fd" fd "$FD_VERSION"
  mkdir -p "$archive_root/fd/$FD_VERSION"
  tar -C "$work" -czf "$archive_root/fd/$FD_VERSION/fd-v${FD_VERSION}-x86_64-unknown-linux-musl.tar.gz" \
    "fd-v${FD_VERSION}-x86_64-unknown-linux-musl"
  digest=$(sha256sum "$archive_root/fd/$FD_VERSION/fd-v${FD_VERSION}-x86_64-unknown-linux-musl.tar.gz" | awk '{print $1}')
  append_release "$repository/tools.env" TOOL_RELEASES fd "$FD_VERSION" \
    "https://example.invalid/fd/$FD_VERSION/fd-v${FD_VERSION}-x86_64-unknown-linux-musl.tar.gz" "$digest"

  write_fake "$work/gh_${GH_VERSION}_linux_amd64/bin/gh" gh "$GH_VERSION"
  mkdir -p "$archive_root/gh/$GH_VERSION"
  tar -C "$work" -czf "$archive_root/gh/$GH_VERSION/gh_${GH_VERSION}_linux_amd64.tar.gz" \
    "gh_${GH_VERSION}_linux_amd64"
  digest=$(sha256sum "$archive_root/gh/$GH_VERSION/gh_${GH_VERSION}_linux_amd64.tar.gz" | awk '{print $1}')
  append_release "$repository/tools.env" TOOL_RELEASES gh "$GH_VERSION" \
    "https://example.invalid/gh/$GH_VERSION/gh_${GH_VERSION}_linux_amd64.tar.gz" "$digest"

  write_fake "$work/k9s" k9s "$K9S_VERSION"
  mkdir -p "$archive_root/k9s/$K9S_VERSION"
  tar -C "$work" -czf "$archive_root/k9s/$K9S_VERSION/k9s_Linux_amd64.tar.gz" k9s
  digest=$(sha256sum "$archive_root/k9s/$K9S_VERSION/k9s_Linux_amd64.tar.gz" | awk '{print $1}')
  append_release "$repository/tools.env" TOOL_RELEASES k9s "$K9S_VERSION" \
    "https://example.invalid/k9s/$K9S_VERSION/k9s_Linux_amd64.tar.gz" "$digest"

  write_fake "$archive_root/kind/$KIND_VERSION/kind-linux-amd64" kind "$KIND_VERSION"
  digest=$(sha256sum "$archive_root/kind/$KIND_VERSION/kind-linux-amd64" | awk '{print $1}')
  append_release "$repository/tools.env" TOOL_RELEASES kind "$KIND_VERSION" \
    "https://example.invalid/kind/$KIND_VERSION/kind-linux-amd64" "$digest"

  write_fake "$archive_root/oh-my-posh/$OMP_VERSION/posh-linux-amd64" oh-my-posh "$OMP_VERSION"
  digest=$(sha256sum "$archive_root/oh-my-posh/$OMP_VERSION/posh-linux-amd64" | awk '{print $1}')
  append_release "$repository/tools.env" TOOL_RELEASES oh-my-posh "$OMP_VERSION" \
    "https://example.invalid/oh-my-posh/$OMP_VERSION/posh-linux-amd64" "$digest"

  write_fake "$work/uv-x86_64-unknown-linux-gnu/uv" uv "$UV_VERSION"
  write_fake "$work/uv-x86_64-unknown-linux-gnu/uvx" uvx "$UV_VERSION"
  mkdir -p "$archive_root/uv/$UV_VERSION"
  tar -C "$work" -czf "$archive_root/uv/$UV_VERSION/uv-x86_64-unknown-linux-gnu.tar.gz" \
    uv-x86_64-unknown-linux-gnu
  digest=$(sha256sum "$archive_root/uv/$UV_VERSION/uv-x86_64-unknown-linux-gnu.tar.gz" | awk '{print $1}')
  append_release "$repository/tools.env" TOOL_RELEASES uv "$UV_VERSION" \
    "https://example.invalid/uv/$UV_VERSION/uv-x86_64-unknown-linux-gnu.tar.gz" "$digest"

  write_fake "$work/nvim-linux-x86_64/bin/nvim" nvim "$NVIM_VERSION"
  mkdir -p "$work/nvim-linux-x86_64/share/nvim/runtime/syntax"
  printf 'runtime fixture\n' >"$work/nvim-linux-x86_64/share/nvim/runtime/syntax/test.vim"
  mkdir -p "$archive_root/nvim/$NVIM_VERSION"
  tar -C "$work" -czf "$archive_root/nvim/$NVIM_VERSION/nvim-linux-x86_64.tar.gz" \
    nvim-linux-x86_64
  digest=$(sha256sum "$archive_root/nvim/$NVIM_VERSION/nvim-linux-x86_64.tar.gz" | awk '{print $1}')
  append_release "$repository/tools.env" TOOL_RELEASES nvim "$NVIM_VERSION" \
    "https://example.invalid/nvim/$NVIM_VERSION/nvim-linux-x86_64.tar.gz" "$digest"

  write_fake "$work/go/bin/go" go "$GO_VERSION"
  write_fake "$work/go/bin/gofmt" gofmt "$GO_VERSION"
  mkdir -p "$work/go/src/fmt" "$work/go/pkg/tool/linux_amd64" "$archive_root/go/$GO_VERSION"
  printf 'standard library fixture\n' >"$work/go/src/fmt/print.go"
  printf 'compiler fixture\n' >"$work/go/pkg/tool/linux_amd64/compile"
  tar -C "$work" -czf "$archive_root/go/$GO_VERSION/go.linux-amd64.tar.gz" go
  digest=$(sha256sum "$archive_root/go/$GO_VERSION/go.linux-amd64.tar.gz" | awk '{print $1}')
  append_release "$repository/tools.env" TOOL_RELEASES go "$GO_VERSION" \
    "https://example.invalid/go/$GO_VERSION/go.linux-amd64.tar.gz" "$digest"

  write_source_fixture "$work/htop-$HTOP_VERSION" htop "$HTOP_VERSION"
  mkdir -p "$archive_root/htop/$HTOP_VERSION"
  tar -C "$work" -cJf "$archive_root/htop/$HTOP_VERSION/htop-$HTOP_VERSION.tar.xz" \
    "htop-$HTOP_VERSION"
  digest=$(sha256sum "$archive_root/htop/$HTOP_VERSION/htop-$HTOP_VERSION.tar.xz" | awk '{print $1}')
  append_release "$repository/tools.env" TOOL_RELEASES htop "$HTOP_VERSION" \
    "https://example.invalid/htop/$HTOP_VERSION/htop-$HTOP_VERSION.tar.xz" "$digest"

  write_source_fixture "$work/tmux-$TMUX_VERSION" tmux "$TMUX_VERSION"
  mkdir -p "$archive_root/tmux/$TMUX_VERSION"
  tar -C "$work" -czf "$archive_root/tmux/$TMUX_VERSION/tmux-$TMUX_VERSION.tar.gz" \
    "tmux-$TMUX_VERSION"
  digest=$(sha256sum "$archive_root/tmux/$TMUX_VERSION/tmux-$TMUX_VERSION.tar.gz" | awk '{print $1}')
  append_release "$repository/tools.env" TOOL_RELEASES tmux "$TMUX_VERSION" \
    "https://example.invalid/tmux/$TMUX_VERSION/tmux-$TMUX_VERSION.tar.gz" "$digest"
}

create_fixture() {
  test_root=$(mktemp -d)
  trap cleanup EXIT

  test_repository="$test_root/repository"
  archive_root="$test_root/archive files"
  test_home="$test_root/home"
  make_test_repo "$test_repository"
  make_archives "$test_repository" "$archive_root"

  mkdir -p "$test_root/shim"
  cat >"$test_root/shim/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
destination=
url=
while (($#)); do
  case $1 in
    --output) destination=$2; shift 2 ;;
    https://example.invalid/*) url=$1; shift ;;
    *) shift ;;
  esac
done
[[ -n $destination && -n $url ]] || exit 99
source_file=$TEST_TOOL_ARCHIVES/${url#https://example.invalid/}
[[ -f $source_file ]] || { printf 'download failed: %s\n' "$url" >&2; exit 22; }
cp -- "$source_file" "$destination"
EOF
  chmod 0755 "$test_root/shim/curl"
}
