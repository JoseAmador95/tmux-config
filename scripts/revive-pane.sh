#!/bin/sh
# Revive one exact dead pane without bypassing a Dev Container lifecycle.
set -u

say() {
  tmux display-message "revive pane: $*" 2>/dev/null || true
}

pane=${1:-}
[ "$#" -eq 1 ] || { say 'usage: <pane-id>'; exit 1; }
case "$pane" in
  ''|'%'|%*[!0-9]*|[!%]*) say 'invalid pane id'; exit 1 ;;
esac

resolved=$(tmux display-message -p -t "$pane" '#{pane_id}' 2>/dev/null) || {
  say "pane no longer exists: $pane"
  exit 1
}
[ "$resolved" = "$pane" ] || {
  say 'pane did not resolve exactly'
  exit 1
}

dead=$(tmux display-message -p -t "$pane" '#{pane_dead}' 2>/dev/null) || exit 1
[ "$dead" = 1 ] || {
  say 'pane is still running'
  exit 1
}

marker=$(tmux show-option -pqv -t "$pane" @devcontainer_active 2>/dev/null) || marker=''
if [ -n "$marker" ]; then
  adapter=${HOME:-}/.config/tmux/scripts/devcontainer-editor.sh
  [ -x "$adapter" ] || {
    say "Dev Container adapter is not executable: $adapter"
    exit 1
  }
  "$adapter" up "$pane"
  exit $?
fi

window_name=$(tmux display-message -p -t "$pane" '#{window_name}' 2>/dev/null) || exit 1
if [ "$window_name" = git ]; then
  cwd=$(tmux display-message -p -t "$pane" '#{pane_current_path}' 2>/dev/null) || exit 1
  tmux respawn-pane -t "$pane" -c "$cwd" 'exec ~/.config/tmux/scripts/lazygit-window.sh' || exit 1
else
  tmux respawn-pane -t "$pane" || exit 1
fi

say 'pane respawned'
