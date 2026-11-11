#!/usr/bin/env bash

health_tmux() {
  local tmux=$1 health_home=$2 config=$3 plugin_dir=$4
  local socket socket_dir plugin entry option command
  local client client_input client_stderr client_pid reload_value
  local state_dir=$health_home/'tmux saved state'
  shift 4
  local -a selected_tools=("$@")

  mkdir -p "$state_dir" || return
  (
    # Unix socket paths are short; a valid HOME may exceed their limit.
    socket_dir=$(mktemp -d /tmp/dotfiles-tmux.XXXXXX) || exit
    socket=$socket_dir/socket
    unset TMUX
    export HOME="$health_home"
    export DOTFILES_TMUX_PLUGIN_DIR="$plugin_dir"
    # shellcheck disable=SC2329
    cleanup_health_tmux() {
      # shellcheck disable=SC2317
      "$tmux" -S "$socket" kill-server >/dev/null 2>&1 || true
      cleanup_path "$socket_dir"
    }
    trap cleanup_health_tmux EXIT
    "$tmux" -S "$socket" -f "$config" new-session -d -s health || exit
    option=$("$tmux" -S "$socket" show-options -gv prefix)
    [[ $option == C-a ]] || {
      report_error "tmux prefix is $option, expected C-a"
      exit 1
    }
    option=$("$tmux" -S "$socket" show-options -gv @dotfiles-config)
    [[ $option == "$config" ]] || {
      report_error 'tmux did not retain its physical config'
      exit 1
    }
    "$tmux" -S "$socket" set-option -g status-position bottom || exit
    client_input=$health_home/tmux-client-input
    client_stderr=$health_home/tmux-client-stderr
    mkfifo "$client_input" || exit
    exec {client_input_fd}<>"$client_input"
    TERM=xterm-256color timeout 10s script -qefc \
      "$(printf '%q ' "$tmux" -S "$socket" attach-session -t health)" /dev/null \
      <"$client_input" >/dev/null 2>"$client_stderr" &
    client_pid=$!
    client=
    for _ in {1..50}; do
      client=$("$tmux" -S "$socket" list-clients -F '#{client_name}' 2>/dev/null | head -n 1)
      [[ -n $client ]] && break
      sleep 0.02
    done
    [[ -n $client ]] || {
      report_error 'tmux health client did not attach'
      exit 1
    }
    "$tmux" -S "$socket" send-keys -K -c "$client" C-a R || exit
    reload_value=
    for _ in {1..50}; do
      reload_value=$("$tmux" -S "$socket" show-options -gv status-position 2>/dev/null || true)
      [[ $reload_value == top ]] && break
      sleep 0.02
    done
    [[ $reload_value == top ]] || {
      report_error 'tmux Shift-R did not reload the physical config'
      exit 1
    }
    if list_has selected_tools tmux-resurrect; then
      "$tmux" -S "$socket" set-option -g @resurrect-dir "$state_dir" || exit
      "$tmux" -S "$socket" send-keys -K -c "$client" C-a C-s || exit
      for _ in {1..100}; do
        [[ -s $state_dir/last ]] && break
        sleep 0.05
      done
      [[ -s $state_dir/last ]] || {
        report_error 'tmux save key did not persist its session state'
        exit 1
      }
    fi
    [[ ! -s $client_stderr ]] || {
      report_error 'tmux reload client wrote to stderr'
      exit 1
    }
    "$tmux" -S "$socket" detach-client -t "$client" || exit
    exec {client_input_fd}>&-
    wait "$client_pid" || exit
    for plugin in "${selected_tools[@]}"; do
      [[ $plugin == tmux-* ]] || continue
      entry=$plugin_dir/$plugin/${plugin#tmux-}.tmux
      [[ $plugin != tmux-sensible ]] || entry=$plugin_dir/$plugin/sensible.tmux
      [[ -x $entry || -f $entry ]] || {
        report_error "tmux plugin entry point is missing: $entry"
        exit 1
      }
      printf -v command 'exec %q' "$entry"
      "$tmux" -S "$socket" run-shell "$command" || exit
      printf 'tmux-plugin=%s exit=0\n' "$plugin"
    done
    if list_has selected_tools tmux-resurrect; then
      "$tmux" -S "$socket" list-keys -T prefix C-s || exit
    fi
  ) || return
}
