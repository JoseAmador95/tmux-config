#!/bin/sh
# Create or reuse the dev session's exact host or Dev Container editor pane.
set -u

say() {
  tmux display-message "Dev Container editor: $*" 2>/dev/null || true
}

quote() {
  escaped=$(printf '%s' "$1" | sed "s/'/'\\\\''/g") || return 1
  printf "'%s'" "$escaped"
}

action=${1:-}
source_pane=${2:-}
[ "$#" -eq 2 ] || { say 'usage: up|host <source-pane>'; exit 1; }
case "$action" in
  up|host) ;;
  *) say 'usage: up|host <source-pane>'; exit 1 ;;
esac
case "$source_pane" in
  ''|'%'|%*[!0-9]*|[!%]*) say 'invalid source pane'; exit 1 ;;
esac

session=$(tmux display-message -p -t "$source_pane" '#{session_id}' 2>/dev/null) || {
  say "source pane no longer exists: $source_pane"
  exit 1
}
case "$session" in
  ''|'$'|'$'*[!0-9]*|[!$]*) say 'tmux returned an invalid source session id'; exit 1 ;;
esac
repo=$(tmux display-message -p -t "$source_pane" '#{pane_current_path}' 2>/dev/null) || exit 1
repo=$(git -C "$repo" rev-parse --show-toplevel 2>/dev/null) || {
  say 'source pane is not inside a Git repository'
  exit 1
}
repo=$(CDPATH='' cd -- "$repo" && pwd -P) || exit 1

ssh_host=$(tmux show-option -qv -t "$session" @ssh_host 2>/dev/null) || ssh_host=''
[ -z "$ssh_host" ] || {
  say 'Dev Container editor is unavailable in SSH sessions'
  exit 1
}

launcher=${HOME:-}/.config/nvim/scripts/devcontainer-editor
[ -x "$launcher" ] || { say "launcher is not executable: $launcher"; exit 1; }
runtime_helper=${HOME:-}/.config/nvim/scripts/devcontainer-runtime

# Window discovery and creation must be one session-scoped transaction. tmux
# serializes each if-shell command in the server, so the empty-option test and
# assignment form an atomic compare-and-set without an unbounded wait-for lock.
lock_option=@devcontainer_editor_window_lock
lock_token=$$
lock_held=0

release_editor_lock() {
  [ "$lock_held" -eq 1 ] || return 0
  tmux if-shell -F -t "$session" \
    "#{==:#{@devcontainer_editor_window_lock},$lock_token}" \
    "set-option -q -u -t '$session' $lock_option" '' >/dev/null 2>&1 || return 1
  owner=$(tmux show-option -qv -t "$session" "$lock_option" 2>/dev/null) || owner=''
  [ "$owner" != "$lock_token" ] || return 1
  lock_held=0
}

acquire_editor_lock() {
  attempts=0
  while [ "$attempts" -lt 40 ]; do
    tmux if-shell -F -t "$session" \
      '#{?#{@devcontainer_editor_window_lock},0,1}' \
      "set-option -q -t '$session' $lock_option '$lock_token'" '' >/dev/null 2>&1 || return 1
    owner=$(tmux show-option -qv -t "$session" "$lock_option" 2>/dev/null) || owner=''
    if [ "$owner" = "$lock_token" ]; then
      lock_held=1
      return 0
    fi
    case "$owner" in
      '')
        # The previous owner may release the lock after our compare-and-set
        # loses but before this read. That is a normal retry, not corruption.
        ;;
      *[!0-9]*) say 'editor window lock has an invalid owner'; return 1 ;;
    esac
    if [ -n "$owner" ] && ! kill -0 "$owner" 2>/dev/null; then
      tmux if-shell -F -t "$session" \
        "#{==:#{@devcontainer_editor_window_lock},$owner}" \
        "set-option -q -u -t '$session' $lock_option" '' >/dev/null 2>&1 || return 1
    fi
    attempts=$((attempts + 1))
    sleep 0.05
  done
  say 'timed out acquiring the editor window lock'
  return 1
}

trap 'release_editor_lock || true' 0
trap 'exit 130' 1 2 15
acquire_editor_lock || exit 1

tab=$(printf '\t')
editor_windows=$(tmux list-windows -t "$session" -F "#{window_id}${tab}#{window_name}" 2>/dev/null |
  awk -F "$tab" '$2 == "editor" && NF == 2 { print $1 }') || exit 1
editor_count=$(printf '%s\n' "$editor_windows" | awk 'NF { count++ } END { print count + 0 }')
case "$editor_count" in
  0)
    editor_pane=$(tmux new-window -d -P -F '#{pane_id}' -t "$session:" -n editor -c "$repo" 'exec tail -f /dev/null') || {
      say 'could not create the editor window'
      exit 1
    }
    editor_window=$(tmux display-message -p -t "$editor_pane" '#{window_id}') || exit 1
    ;;
  1)
    editor_window=$(printf '%s\n' "$editor_windows" | sed -n '1p')
    editor_panes=$(tmux list-panes -t "$editor_window" -F '#{pane_id}') || exit 1
    editor_pane=$(printf '%s\n' "$editor_panes" | sed -n '1p')
    pane_count=$(printf '%s\n' "$editor_panes" | awk 'NF { count++ } END { print count + 0 }')
    { [ -n "$editor_pane" ] && [ "$pane_count" -eq 1 ]; } || {
      say 'editor window must contain exactly one pane'
      exit 1
    }
    ;;
  *)
    say 'session has more than one editor window'
    exit 1
    ;;
esac

tmux set-option -p -t "$editor_pane" remain-on-exit on || exit 1
tmux set-option -w -t "$editor_window" @no_split 1 || exit 1

if [ "$action" = host ]; then
  pane_dead=$(tmux display-message -p -t "$editor_pane" '#{pane_dead}' 2>/dev/null) || exit 1
  pane_pid=$(tmux display-message -p -t "$editor_pane" '#{pane_pid}' 2>/dev/null) || exit 1
  devcontainer_marker=$(tmux show-option -pqv -t "$editor_pane" @devcontainer_active 2>/dev/null) || devcontainer_marker=''
  host_repo=$(tmux show-option -pqv -t "$editor_pane" @host_editor_repo 2>/dev/null) || host_repo=''
  host_pid=$(tmux show-option -pqv -t "$editor_pane" @host_editor_pid 2>/dev/null) || host_pid=''
  if [ "$pane_dead" = 0 ] && [ -z "$devcontainer_marker" ] && \
    [ "$host_repo" = "$repo" ] && [ "$host_pid" = "$pane_pid" ]; then
    release_editor_lock || exit 1
    trap - 0 1 2 15
    tmux select-window -t "$editor_window"
    exit $?
  fi
  output=$("$launcher" host --repo "$repo" --tmux-pane "$editor_pane" 2>&1)
  status=$?
  if [ "$status" -ne 0 ]; then
    [ -n "$output" ] || output='host editor handoff failed'
    say "$output"
    exit "$status"
  fi
  pane_dead=$(tmux display-message -p -t "$editor_pane" '#{pane_dead}' 2>/dev/null) || exit 1
  pane_pid=$(tmux display-message -p -t "$editor_pane" '#{pane_pid}' 2>/dev/null) || exit 1
  devcontainer_marker=$(tmux show-option -pqv -t "$editor_pane" @devcontainer_active 2>/dev/null) || devcontainer_marker=''
  case "$pane_pid" in
    ''|*[!0-9]*) say 'host editor returned an invalid pane pid'; exit 1 ;;
  esac
  [ "$pane_dead" = 0 ] && [ -z "$devcontainer_marker" ] || {
    say 'host editor handoff did not produce an exact live host pane'
    exit 1
  }
  tmux set-option -p -t "$editor_pane" @host_editor_repo "$repo" || exit 1
  tmux set-option -p -t "$editor_pane" @host_editor_pid "$pane_pid" || exit 1
  release_editor_lock || {
    say 'could not release the editor window lock'
    exit 1
  }
  trap - 0 1 2 15
else
  release_editor_lock || {
    say 'could not release the editor window lock'
    exit 1
  }
  trap - 0 1 2 15
  marker=$(tmux show-option -pqv -t "$editor_pane" @devcontainer_active 2>/dev/null) || marker=''
  lifecycle=up
  if [ -n "$marker" ]; then
    pane_dead=$(tmux display-message -p -t "$editor_pane" '#{pane_dead}' 2>/dev/null) || {
      say 'could not inspect the marked Dev Container editor pane'
      exit 1
    }
    if [ "$pane_dead" = 0 ]; then
      output=$("$launcher" check-active --repo "$repo" --tmux-pane "$editor_pane" 2>&1)
      status=$?
      if [ "$status" -ne 0 ]; then
        [ -n "$output" ] || output='marked Dev Container editor is not the active registered lifecycle'
        say "$output"
        exit "$status"
      fi
      tmux select-window -t "$editor_window"
      exit 0
    fi
    [ "$pane_dead" = 1 ] || {
      say 'tmux returned an invalid Dev Container pane state'
      exit 1
    }
    lifecycle=restart-dead
    output=$("$launcher" wait-dead --repo "$repo" --tmux-pane "$editor_pane" --timeout 2 2>&1)
    status=$?
    if [ "$status" -ne 0 ]; then
      [ -n "$output" ] || output='Dev Container lifecycle did not reach its exact dead state'
      say "$output"
      exit "$status"
    fi
  fi
  runtime_cli=''
  runtime_docker=''
  [ -x "$runtime_helper" ] || {
    say "runtime helper is not executable: $runtime_helper"
    exit 1
  }
  if [ "$lifecycle" = up ]; then
    runtime_output=$("$runtime_helper" prepare-up "$repo" 2>&1)
    status=$?
    if [ "$status" -ne 0 ]; then
      [ -n "$runtime_output" ] || runtime_output='Dev Container runtime preflight failed'
      say "$runtime_output"
      exit "$status"
    fi
    visible_output=$(printf '%s' "$runtime_output" | LC_ALL=C tr -d '\001-\010\012-\037\177')
    [ "$visible_output" = "$runtime_output" ] || {
      say 'runtime helper returned control characters'
      exit 1
    }
    case "$runtime_output" in
      "$tab"*|*"$tab"|*"$tab"*"$tab"*)
        say 'runtime helper did not return one absolute CLI/engine pair'
        exit 1
        ;;
      /*"$tab"/*) ;;
      *)
        say 'runtime helper did not return one absolute CLI/engine pair'
        exit 1
        ;;
    esac
    runtime_cli=${runtime_output%%"$tab"*}
    runtime_docker=${runtime_output#*"$tab"}
    case "$runtime_cli" in
      //*)
        say 'runtime helper returned a non-canonical CLI/engine pair'
        exit 1
        ;;
    esac
    case "$runtime_docker" in
      //*)
        say 'runtime helper returned a non-canonical CLI/engine pair'
        exit 1
        ;;
    esac
  else
    runtime_output=$("$runtime_helper" preflight-record "$repo" 2>&1)
    status=$?
    if [ "$status" -ne 0 ]; then
      [ -n "$runtime_output" ] || runtime_output='Dev Container record preflight failed'
      say "$runtime_output"
      exit "$status"
    fi
    [ -z "$runtime_output" ] || {
      say 'record preflight returned unexpected output'
      exit 1
    }
  fi
  claim=$("$launcher" new-claim-id 2>&1)
  status=$?
  if [ "$status" -ne 0 ]; then
    say "$claim"
    exit "$status"
  fi
  command="exec $(quote "$launcher") $lifecycle --repo $(quote "$repo") --tmux-pane $(quote "$editor_pane") --claim-id $(quote "$claim")"
  if [ "$lifecycle" = up ]; then
    command="$command --cli-path $(quote "$runtime_cli") --docker-path $(quote "$runtime_docker")"
  fi
  tmux run-shell -b -t "$editor_pane" "$command" || {
    say 'could not start the detached Dev Container coordinator'
    exit 1
  }
  output=$("$launcher" wait-claim --repo "$repo" --claim-id "$claim" --timeout 2 2>&1)
  status=$?
  if [ "$status" -ne 0 ]; then
    [ -n "$output" ] || output='detached coordinator did not publish its lifecycle claim'
    say "$output"
    exit "$status"
  fi
fi

tmux select-window -t "$editor_window"
