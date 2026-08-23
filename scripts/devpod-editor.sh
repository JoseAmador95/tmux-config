#!/bin/sh
# Create or reuse only the named dev session's editor window for host or DevPod Neovim.
set -u

say() {
  tmux display-message "DevPod editor: $*" 2>/dev/null || true
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

session=$(tmux display-message -p -t "$source_pane" '#{session_name}' 2>/dev/null) || {
  say "source pane no longer exists: $source_pane"
  exit 1
}
repo=$(tmux display-message -p -t "$source_pane" '#{pane_current_path}' 2>/dev/null) || exit 1
repo=$(git -C "$repo" rev-parse --show-toplevel 2>/dev/null) || {
  say 'source pane is not inside a Git repository'
  exit 1
}

ssh_host=$(tmux show-option -qv -t "$session" @ssh_host 2>/dev/null) || ssh_host=''
[ -z "$ssh_host" ] || {
  say 'DevPod editor is unavailable in SSH sessions'
  exit 1
}

launcher=${HOME:-}/.config/nvim/scripts/devpod-nvim
[ -x "$launcher" ] || { say "launcher is not executable: $launcher"; exit 1; }
launcher_quoted=$(printf '%s' "$launcher" | sed "s/'/'\\\\''/g")

editor_windows=$(tmux list-windows -t "$session" -F '#{window_id}	#{window_name}' 2>/dev/null |
  awk -F '	' '$2 == "editor" { print $1 }') || exit 1
editor_count=$(printf '%s\n' "$editor_windows" | awk 'NF { count++ } END { print count + 0 }')
case "$editor_count" in
  0)
    editor_pane=$(tmux new-window -d -P -F '#{pane_id}' -t "$session:" -n editor -c "$repo" 'sleep 120') || {
      say 'could not create the editor window'
      exit 1
    }
    editor_window=$(tmux display-message -p -t "$editor_pane" '#{window_id}') || exit 1
    ;;
  1)
    editor_window=$(printf '%s\n' "$editor_windows" | sed -n '1p')
    editor_panes=$(tmux list-panes -t "$editor_window" -F '#{pane_id}') || exit 1
    editor_pane=$(printf '%s\n' "$editor_panes" | sed -n '1p')
    { [ -n "$editor_pane" ] && [ "$(printf '%s\n' "$editor_panes" | awk 'NF { count++ } END { print count + 0 }')" -eq 1 ]; } || {
      say 'editor window must contain exactly one pane'
      exit 1
    }
    ;;
  *)
    say 'session has more than one editor window'
    exit 1
    ;;
esac

tmux set-option -p -t "$editor_pane" remain-on-exit on
tmux set-option -w -t "$editor_window" @no_split 1

if [ "$action" = host ]; then
  tmux select-pane -t "$editor_pane" -T '' 2>/dev/null || true
  tmux set-option -p -u -t "$editor_pane" @devpod_active 2>/dev/null || true
  tmux respawn-pane -k -t "$editor_pane" -c "$repo" nvim
else
  tmux respawn-pane -k -t "$editor_pane" -c "$repo" "exec '$launcher_quoted' up"
fi
tmux select-window -t "$editor_window"
