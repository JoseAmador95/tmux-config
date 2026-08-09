#!/bin/sh
# Replace only the named dev session's editor pane with host or DevPod Neovim.
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

editor_panes=$(tmux list-panes -t "$session:=editor" -F '#{pane_id}' 2>/dev/null) || {
  say "session $session has no editor window"
  exit 1
}
editor_pane=$(printf '%s\n' "$editor_panes" | sed -n '1p')
[ -n "$editor_pane" ] && [ "$(printf '%s\n' "$editor_panes" | wc -l | tr -d ' ')" -eq 1 ] || {
  say 'editor window must contain exactly one pane'
  exit 1
}

launcher=${HOME:-}/.config/nvim/scripts/devpod-nvim
[ -x "$launcher" ] || { say "launcher is not executable: $launcher"; exit 1; }
launcher_quoted=$(printf '%s' "$launcher" | sed "s/'/'\\\\''/g")
tmux set-option -p -t "$editor_pane" remain-on-exit on

if [ "$action" = host ]; then
  tmux select-pane -t "$editor_pane" -T '' 2>/dev/null || true
  tmux set-option -p -u -t "$editor_pane" @devpod_active 2>/dev/null || true
  tmux respawn-pane -k -t "$editor_pane" -c "$repo" nvim
else
  tmux respawn-pane -k -t "$editor_pane" -c "$repo" "exec '$launcher_quoted' up"
fi
tmux select-window -t "$session:=editor"
