#!/usr/bin/env bash

# Fixture globals are consumed by the scenario scripts.
# shellcheck disable=SC2034

repo_dir=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)

cleanup() {
  local status=$? pid
  trap - EXIT
  set +e
  for pid in "${lock_holder_pid:-}" "${old_process:-}"; do
    [[ -n $pid ]] || continue
    kill "$pid" 2>/dev/null
    wait "$pid" 2>/dev/null
  done
  find "$test_root" -depth -delete
  exit "$status"
}

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_link() {
  local path=$1 target=$2
  [[ -L $path ]] || fail "$path is not a symlink"
  [[ $(readlink -- "$path") == "$target" ]] ||
    fail "$path does not point to $target"
}

write_fake_tool() {
  local path=$1
  local version=${2:-1.0}
  mkdir -p "$(dirname -- "$path")"
  cat >"$path" <<EOF
#!/usr/bin/env bash
set -euo pipefail
self=\$(readlink -f -- "\$0")
if [[ \${1:-} == hold ]]; then
  printf 'before=%s\nconfig-before=%s\n' "\$self" "\$XDG_CONFIG_HOME" >"\$2"
  for ((attempt = 0; attempt < 600; attempt++)); do
    [[ ! -e \$3 ]] || break
    sleep 0.05
  done
  [[ -e \$3 ]] || exit 97
  printf 'after=%s\nconfig-after=%s\n' "\$self" "\$XDG_CONFIG_HOME" >>"\$2"
  exit 0
fi
if [[ \${0##*/} == tmux && \${1:-} == -f ]]; then
  [[ \$2 == "\$TMUX_OFFLINE_CONFIG" ]] || exit 98
  shift 2
fi
if [[ \${self##*/} == helm-* ]]; then
  if [[ \${1:-} == schema ]]; then
    shift
    exec "\$HELM_PLUGINS/helm-values-schema-json/schema" "\$@"
  elif [[ \$* == 'plugin list' ]]; then
    printf 'NAME VERSION DESCRIPTION\\n'
    awk '\$1 == "name:" { name = \$2 } \$1 == "version:" { gsub(/"/, "", \$2); version = \$2 } END { print name, version, "fixture" }' \\
      "\$HELM_PLUGINS/helm-values-schema-json/plugin.yaml"
    exit 0
  elif [[ \${1:-} == fixture-plugins ]]; then
    printf 'plugins=%s\\n' "\${HELM_PLUGINS-unset}"
  fi
fi
if [[ \${0##*/} == yq ]]; then
  if [[ \${1:-} == --version ]]; then
    printf 'yq (https://github.com/mikefarah/yq/) version v$version\\n'
  elif [[ \$* == 'eval -r .name '* ]]; then
    awk '/^name:/ { print \$2 } /^---\$/ { print }' "\${!#}"
  else
    exit 93
  fi
  exit 0
fi
case \$(basename -- "\$0") in
  k9s) [[ \$* == 'version --short' ]] || exit 93 ;;
  oh-my-posh | terraform | go | kind) [[ \$* == version ]] || exit 94 ;;
  tmux) [[ \$* == -V ]] || exit 95 ;;
esac
printf '%s fixture $version\n' "\$(basename -- "\$0")"
EOF
  if [[ ${path##*/} == nvim ]]; then
    cat >>"$path" <<'EOF'
release=${self%/tools/nvim/bin/nvim}
[[ ${DOTFILES_OFFLINE_RELEASE_ROOT:-} == "$release" ]] || exit 96
[[ ${DOTFILES_IGNORE_BIN_EXTRAS:-} == 1 ]] || exit 99
[[ -z ${VIRTUAL_ENV:-} ]] || exit 98
EOF
  fi
  if [[ ${path##*/} == kubectl-* || ${path##*/} == helm-* ]]; then
    cat >>"$path" <<'EOF'
if [[ ${1:-} == fixture-args ]]; then
  shift
  printf '<%s>\n' "$@"
elif [[ ${1:-} == fixture-fail ]]; then
  exit 42
fi
EOF
  fi
  chmod 0755 "$path"
}

write_fake_python() {
  local path=$1
  mkdir -p "$(dirname -- "$path")"
  cat >"$path" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ ${FIXTURE_FAIL_PYTHON_IMPORT:-} == 1 &&
  ${1:-} == -I && ${2:-} == - && ${!#} == ansible-lint ]]; then
  exit 95
fi
if [[ " $* " == *' -m venv '* ]]; then
  destination=${!#}
  mkdir -p "$destination/bin"
  printf 'home = fixture\n' >"$destination/pyvenv.cfg"
  cp "$0" "$destination/bin/python"
  for command_name in ansible ansible-config ansible-lint ansible-playbook yamllint; do
    printf '%s\n' \
      '#!/usr/bin/env bash' \
      'if [[ $(basename -- "$0") == ansible-lint && " $* " != *" --offline "* ]]; then exit 97; fi' \
      'printf "%s fixture 1.0\n" "$(basename -- "$0")"' \
      >"$destination/bin/$command_name"
    chmod 0755 "$destination/bin/$command_name"
  done
fi
exit 0
EOF
  chmod 0755 "$path"
}

make_artifact() {
  local commit=$1 marker=$2 destination=$3
  local release_version=${4:-1.0}
  local include_fd=${5:-true}
  local include_go=${6:-true}
  local include_current_tools=${7:-false}
  local include_validation_tools=${8:-false}
  local offline_profile=nvim,nodejs,python,rg,tmux,oh-my-posh,k9s,zoxide,kubectx,kubens,task,fzf,terraform,kubectl,helm
  local id=dotfiles-${commit:0:12}
  local stage=$test_root/stage-$marker release=$test_root/stage-$marker/$id
  local command_name plugin plugin_dir version

  mkdir -p "$release/bin" "$release/config/nvim2/tests" \
    "$release/dotfiles/bash" "$release/dotfiles/git" \
    "$release/dotfiles/ssh/.ssh" "$release/dotfiles/ssh/.config/systemd/user" \
    "$release/dotfiles/tmux" "$release/dotfiles/vim" \
    "$release/dotfiles/oh-my-posh" \
    "$release/dotfiles/k9s/.config/k9s/skins" \
    "$release/share/nvim2/mason/bin" "$release/share/nvim2/mason/packages/ansible-lint" \
    "$release/share/nvim2/mason/packages/yamllint" \
    "$release/python-wheelhouse" "$release/share/tmux/plugins" \
    "$release/tools/bin" "$release/tools/nvim/bin" "$release/tools/tmux/bin"

  {
    printf '#!/usr/bin/env bash\n'
    cat "$repo_dir/tools-probes.env" "$repo_dir/scripts/dotfiles-release"
  } >"$release/dotfiles-release"
  chmod 0755 "$release/dotfiles-release"
  ln -s ../dotfiles-release "$release/bin/dotfiles-release"
  for command_name in nvim tmux; do
    write_fake_tool "$release/tools/$command_name/bin/$command_name" "$release_version"
  done
  write_fake_python "$release/tools/python-3.12.12/bin/python3"
  for command_name in node npm npx corepack rg zoxide k9s kubectx kubens \
    oh-my-posh task fzf terraform; do
    write_fake_tool "$release/tools/bin/$command_name" "$release_version"
    ln -s "../tools/bin/$command_name" "$release/bin/$command_name"
  done
  for command_name in kubectl helm; do
    for version in "$release_version" 0.9; do
      write_fake_tool "$release/tools/bin/$command_name-$version" "$version"
      ln -s "../tools/bin/$command_name-$version" "$release/bin/$command_name-$version"
    done
    ln -s "$command_name-$release_version" "$release/tools/bin/$command_name"
    install -m 0755 "$repo_dir/scripts/offline-kubernetes-client" "$release/bin/$command_name"
  done
  if [[ $include_fd == true ]]; then
    write_fake_tool "$release/tools/bin/fd" "$release_version"
    ln -s ../tools/bin/fd "$release/bin/fd"
    offline_profile+=,fd
  fi
  if [[ $include_go == true ]]; then
    write_fake_tool "$release/tools/go/bin/go" "$release_version"
    write_fake_tool "$release/tools/go/bin/gofmt" "$release_version"
    install -m 0755 "$repo_dir/scripts/offline-go" "$release/bin/go"
    ln -s ../tools/go/bin/gofmt "$release/bin/gofmt"
    offline_profile+=,go
  fi
  if [[ $include_current_tools == true ]]; then
    for command_name in kind uv uvx actionlint shellcheck gh kubeconform kyverno trivy; do
      write_fake_tool "$release/tools/bin/$command_name" "$release_version"
      ln -s "../tools/bin/$command_name" "$release/bin/$command_name"
    done
    write_fake_tool "$release/tools/htop/bin/htop" "$release_version"
    ln -s ../tools/htop/bin/htop "$release/bin/htop"
    ln -s ../share/nvim2/mason/packages/yamllint/venv/bin/yamllint \
      "$release/bin/yamllint"
    offline_profile+=,kind,uv,actionlint,shellcheck,yamllint,gh,htop,kubeconform,kyverno,trivy
  fi
  if [[ $include_validation_tools == true ]]; then
    write_fake_tool "$release/tools/bin/yq" "$release_version"
    ln -s ../tools/bin/yq "$release/bin/yq"
    mkdir -p "$release/share/licenses/yq"
    cp "$repo_dir/licenses/yq/LICENSE" "$release/share/licenses/yq/LICENSE"
    plugin_dir=$release/share/helm/plugins/helm-values-schema-json
    mkdir -p "$plugin_dir"
    printf 'name: schema\nversion: "%s"\n' "$release_version" >"$plugin_dir/plugin.yaml"
    printf 'fixture plugin license\n' >"$plugin_dir/LICENSE"
    cat >"$plugin_dir/schema" <<EOF
#!/usr/bin/env bash
set -euo pipefail
if [[ \${1:-} == version ]]; then
  printf 'helm schema version v$release_version\\n'
  exit 0
fi
[[ \$* == '-f values.yaml -o schema.json --bundle --bundle-without-id --bundle-root '* ]] || exit 93
jq '{properties:{replicas:{type:"integer"},tls:{"\$ref":"#/\$defs/tls.schema.json"}},"\$defs":{"tls.schema.json":del(."\$id")}}' \\
  tls.schema.json >schema.json
EOF
    chmod 0755 "$plugin_dir/schema"
    offline_profile+=,yq
  fi
  ln -s ../tools/python-3.12.12/bin/python3 "$release/bin/python"
  ln -s ../tools/python-3.12.12/bin/python3 "$release/bin/python3"
  for command_name in nvim tmux; do
    install -m 0755 "$repo_dir/scripts/offline-$command_name" "$release/bin/$command_name"
  done
  for plugin in tmux-sensible tmux-resurrect tmux-continuum; do
    plugin_dir=$release/share/tmux/plugins/$plugin
    mkdir -p "$plugin_dir"
    printf 'fixture %s\n' "$plugin" >"$plugin_dir/${plugin#tmux-}.tmux"
    git -C "$plugin_dir" init -q
    git -C "$plugin_dir" remote add origin "https://github.com/tmux-plugins/$plugin.git"
    git -C "$plugin_dir" add .
    GIT_AUTHOR_NAME=fixture GIT_AUTHOR_EMAIL=fixture@example.invalid \
      GIT_COMMITTER_NAME=fixture GIT_COMMITTER_EMAIL=fixture@example.invalid \
      GIT_AUTHOR_DATE='2026-01-01T00:00:00Z' GIT_COMMITTER_DATE='2026-01-01T00:00:00Z' \
      git -C "$plugin_dir" commit -q -m fixture
  done
  ln -s ../packages/ansible-lint/venv/bin/ansible-lint \
    "$release/share/nvim2/mason/bin/ansible-lint"
  ln -s ../packages/yamllint/venv/bin/yamllint \
    "$release/share/nvim2/mason/bin/yamllint"
  printf '#!/usr/bin/env bash\nexit 0\n' >"$release/config/nvim2/tests/check.sh"
  chmod 0755 "$release/config/nvim2/tests/check.sh"
  printf 'fixture %s\n' "$marker" >"$release/config/nvim2/init.lua"
  mkdir -p "$release/config/nvim2/tests/bad%new.dir"
  printf 'fixture percent path\n' >"$release/config/nvim2/tests/bad%new.dir/example"
  printf 'fixture punctuation path\n' \
    >"$release/config/nvim2/tests/reference_screenshot()---respects-\`opts.directory\`"
  mkdir -p "$release/config/nvim2/tests/Lua 5.4 zh-cn utf8"
  printf 'fixture spaced target\n' >"$release/config/nvim2/tests/Lua 5.4 zh-cn utf8/target file"
  ln -s 'target file' "$release/config/nvim2/tests/Lua 5.4 zh-cn utf8/link with space"
  for file in .bashrc .bash_profile .bash_aliases; do printf '%s\n' "$marker" >"$release/dotfiles/bash/$file"; done
  printf '%s\n' "$marker" >"$release/dotfiles/ssh/.ssh/config"
  printf '%s\n' "$marker" \
    >"$release/dotfiles/ssh/.config/systemd/user/dotfiles-ssh-agent.service"
  printf '%s\n' "$marker" >"$release/dotfiles/git/.gitconfig"
  printf '%s\n' "$marker" >"$release/dotfiles/tmux/.tmux.conf"
  printf '%s\n' "$marker" >"$release/dotfiles/vim/.vimrc"
  printf '%s\n' "$marker" >"$release/dotfiles/oh-my-posh/.oh-my-posh.omp.json"
  for file in config.yaml aliases.yaml plugins.yaml; do
    printf '%s\n' "$marker" >"$release/dotfiles/k9s/.config/k9s/$file"
  done
  printf '%s\n' "$marker" >"$release/dotfiles/k9s/.config/k9s/skins/skin.yaml"
  mkdir -p "$release/python-locks"
  printf 'ansible-lint==26.1.1\n' >"$release/python-locks/ansible-lint.in"
  printf 'ansible-lint==26.1.1 --hash=sha256:fixture\n' \
    >"$release/python-locks/ansible-lint.lock"
  printf 'yamllint==1.38.0\n' >"$release/python-locks/yamllint.in"
  printf 'yamllint==1.38.0 --hash=sha256:fixture\n' >"$release/python-locks/yamllint.lock"
  printf 'ansible-lint\t26.1.1\nyamllint\t1.38.0\n' \
    >"$release/python-locks/inventory.tsv"
  printf 'fixture wheel\n' >"$release/python-wheelhouse/fixture.whl"
  printf '%s\n' \
    "RELEASE_ID=$id" \
    'PLATFORM_ID=debian-13-x86_64' \
    "SOURCE_COMMIT=$commit" \
    'SOURCE_TREE=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb' \
    'BUILDER_IMAGE=fixture@sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc' \
    "NVIM_VERSION=v$release_version" \
    "NODE_VERSION=$release_version" \
    "NPM_VERSION=$release_version" \
    "NODE_UPSTREAM_NPM_VERSION=$release_version" \
    'PYTHON_VERSION=3.12.12' \
    'PYTHON_BUILD=20260127' \
    "TMUX_VERSION=$release_version" \
    "RG_VERSION=$release_version" \
    "FZF_VERSION=$release_version" \
    "ZOXIDE_VERSION=$release_version" \
    "K9S_VERSION=$release_version" \
    "KUBECTX_VERSION=$release_version" \
    "OMP_VERSION=$release_version" \
    "TASK_VERSION=$release_version" \
    "TERRAFORM_VERSION=$release_version" \
    "KUBECTL_VERSIONS=$release_version,0.9" \
    "HELM_VERSIONS=$release_version,0.9" \
    "OFFLINE_TOOLS=$offline_profile" \
    'PAYLOAD_PATHS=bin,config,dotfiles,python-locks,python-wheelhouse,share,tools' \
    >"$release/release.env"
  if [[ $include_fd == true ]]; then
    printf 'FD_VERSION=%s\n' "$release_version" >>"$release/release.env"
  fi
  if [[ $include_go == true ]]; then
    printf 'GO_VERSION=%s\n' "$release_version" >>"$release/release.env"
  fi
  if [[ $include_current_tools == true ]]; then
    printf '%s\n' \
      "KIND_VERSION=$release_version" \
      "UV_VERSION=$release_version" \
      "ACTIONLINT_VERSION=$release_version" \
      "SHELLCHECK_VERSION=$release_version" \
      "GH_VERSION=$release_version" \
      "HTOP_VERSION=$release_version" \
      "KUBECONFORM_VERSION=$release_version" \
      "KYVERNO_VERSION=$release_version" \
      "TRIVY_VERSION=$release_version" \
      >>"$release/release.env"
  fi
  if [[ $include_validation_tools == true ]]; then
    printf 'YQ_VERSION=%s\nHELM_SCHEMA_PLUGIN_VERSION=%s\n' \
      "$release_version" "$release_version" >>"$release/release.env"
  fi
  printf 'marker=%s\n' "$marker" >"$release/build-manifest.txt"
  (
    cd "$release" || exit
    find . -type f ! -name SHA256SUMS -print0 | sort -z |
      xargs -0 sha256sum >../SHA256SUMS
    mv ../SHA256SUMS SHA256SUMS
  )
  tar -C "$stage" -czf "$destination" "$id"
}

repack_artifact() {
  local marker=$1 id=$2 destination=$3 release
  release=$test_root/stage-$marker/$id

  (
    cd "$release" || exit
    find . -type f ! -name SHA256SUMS -print0 | sort -z |
      xargs -0 sha256sum >"$test_root/$marker-SHA256SUMS"
    mv "$test_root/$marker-SHA256SUMS" SHA256SUMS
  )
  tar -C "$test_root/stage-$marker" -czf "$destination" "$id"
}

run_manager() {
  HOME=$test_home DOTFILES_OS_RELEASE_FILE=$os_release DOTFILES_RELEASE_TEST_MODE=1 \
    bash "$repo_dir/scripts/dotfiles-release" "$@"
}

create_fixture() {
  test_root=$(mktemp -d)
  os_release=$test_root/os-release
  test_home=$test_root/home
  trap cleanup EXIT
  printf 'ID=debian\nVERSION_ID=13\n' >"$os_release"

  commit_one=1111111111111111111111111111111111111111
  commit_two=2222222222222222222222222222222222222222
  commit_three=3333333333333333333333333333333333333333
  id_one=dotfiles-${commit_one:0:12}
  id_two=dotfiles-${commit_two:0:12}
  id_three=dotfiles-${commit_three:0:12}
  artifact_one=$test_root/one.tar.gz
  artifact_two=$test_root/two.tar.gz
  artifact_three=$test_root/three.tar.gz
  make_artifact "$commit_one" one "$artifact_one" 1.0 false false
  make_artifact "$commit_two" two "$artifact_two" 2.0
  make_artifact "$commit_three" three "$artifact_three" 3.0 true true true
}
