#!/bin/sh
# Select one existing window from the source pane's dev-layout session.
# palette-popup.sh passes the real pane explicitly because TMUX_PANE inside a
# display-popup belongs to the transient popup, not to the invoking window.
set -u

say() {
  tmux display-message "dev window: $*" 2>/dev/null || true
}

target=${1:-}
[ "$#" -eq 1 ] || { say 'usage: agent|editor|git|term'; exit 1; }
case "$target" in
  agent|editor|git|term) ;;
  *) say 'usage: agent|editor|git|term'; exit 1 ;;
esac

source_pane=${TMUX_PALETTE_SOURCE_PANE:-}
case "$source_pane" in
  ''|'%'|%*[!0-9]*|[!%]*) say 'no valid palette source pane'; exit 1 ;;
esac

session=$(tmux display-message -p -t "$source_pane" '#{session_id}' 2>/dev/null) || {
  say "source pane no longer exists: $source_pane"
  exit 1
}
layout=$(tmux show-option -qv -t "$session" @layout 2>/dev/null) || layout=''
[ "$layout" = dev ] || {
  say 'current session does not use the dev layout'
  exit 1
}

window_ids=$(tmux list-windows -t "$session" -F '#{window_id} #{window_name}' 2>/dev/null |
  awk -v target="$target" '$2 == target { print $1 }') || exit 1
window_count=$(printf '%s\n' "$window_ids" | awk 'NF { count++ } END { print count + 0 }')
[ "$window_count" -eq 1 ] || {
  say "expected exactly one $target window; found $window_count"
  exit 1
}

window_id=$(printf '%s\n' "$window_ids" | sed -n '1p')
tmux select-window -t "$window_id"
