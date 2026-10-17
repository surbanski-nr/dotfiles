#!/usr/bin/env bash

set -euo pipefail

socket=${1:?tmux socket is required}
action=${2:?timer action is required}
shift 2
tmux=(tmux -S "$socket")

get_option() {
  "${tmux[@]}" show-options -gqv "@eye-timer-$1"
}

menu_command() {
  printf 'run-shell -b %q' "$command $*"
}

case $action in
  init | start | pause | reset | off | set-minutes | status) ;;
  *) printf 'eye-timer: unknown action: %s\n' "$action" >&2; exit 2 ;;
esac

# A short-lived OS lock serializes clients and is released if a job is stopped.
umask 077
exec {lock_fd}>"$socket.eye-timer.lock"
flock --exclusive --timeout 5 "$lock_fd"

state=$(get_option state)
minutes=$(get_option minutes)
remaining=$(get_option remaining)
deadline=$(get_option deadline)
state=${state:-off}
minutes=${minutes:-60}
remaining=${remaining:-$((minutes * 60))}
deadline=${deadline:-0}
printf -v now '%(%s)T' -1

label() {
  case $state in
    off | done) printf '' ;;
    *)
      [[ $state != paused ]] || printf '|| '
      printf '%02d:%02d' "$((remaining / 60))" "$((remaining % 60))"
      ;;
  esac
}

save() {
  "${tmux[@]}" set-option -g @eye-timer-state "$state" \; \
    set-option -g @eye-timer-minutes "$minutes" \; \
    set-option -g @eye-timer-remaining "$remaining" \; \
    set-option -g @eye-timer-deadline "$deadline" \; \
    set-option -g @eye-timer-label "$(label)"
}

finish() {
  state='done'
  remaining=0
  deadline=0
  save
}

case $action in
  init)
    self=$(readlink -f -- "${BASH_SOURCE[0]}")
    printf -v command '%q ' bash "$self" "$socket"
    # Keep editable input as tmux data, then shell-quote it when launching the action.
    printf -v submit 'run-shell -b %q' "$command set-minutes #{q:@eye-timer-input}"
    printf -v prompt 'command-prompt -b -p %q { set-option -g @eye-timer-input "%%1"; %s; set-option -gu @eye-timer-input; }' \
      'Minutes (1-1440; current #{@eye-timer-minutes}):' \
      "$submit"
    # Native UI commands retain the client that pressed t, even after a suspended attach.
    "${tmux[@]}" set-option -g @eye-timer-command "$command" \; \
      bind-key t display-menu -T 'Eye break timer' -x R -y S \
      'Start / Resume' s "$(menu_command start)" \
      'Pause' p "$(menu_command pause)" \
      'Reset' r "$(menu_command reset)" \
      'Set minutes' m "$prompt" \
      'Off' o "$(menu_command off)"
    save
    ;;
  start)
    [[ $state != running ]] || exit 0
    if [[ $state != paused && $state != ready ]]; then remaining=$((minutes * 60)); fi
    state=running
    deadline=$((now + remaining))
    save
    ;;
  pause)
    [[ $state == running ]] || exit 0
    remaining=$((deadline - now))
    if ((remaining <= 0)); then
      finish
    else
      state=paused
      deadline=0
      save
    fi
    ;;
  reset | off | set-minutes)
    if [[ $action == set-minutes ]]; then
      value=${1:-}
      if [[ ! $value =~ ^[0-9]{1,4}$ ]] || ((10#$value < 1 || 10#$value > 1440)); then
        printf 'eye-timer: minutes must be between 1 and 1440\n' >&2
        exit 2
      fi
      minutes=$((10#$value))
    fi
    state=ready
    [[ $action != off ]] || state=off
    remaining=$((minutes * 60))
    deadline=0
    save
    ;;
  status)
    if [[ $state == running ]]; then
      remaining=$((deadline - now))
      if ((remaining <= 0)); then finish; fi
    fi
    label
    ;;
esac
