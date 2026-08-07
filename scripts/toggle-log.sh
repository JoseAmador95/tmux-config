#!/bin/sh
# toggle-log.sh — safely start or stop one pane's append-only log.
#
# Session names are user input, so they never enter pipe-pane's shell command. The basename is
# reduced to [A-Za-z0-9_-], and the complete path is shell-quoted before /bin/sh sees it.
set -u

usage() {
  printf 'usage: toggle-log.sh <pane-id>\n' >&2
  exit 64
}

[ "$#" -eq 1 ] || usage
pane=$1
digits=${pane#%}
case "$pane:$digits" in
  %*:*) ;;
  *) usage ;;
esac
case "$digits" in
  ''|*[!0-9]*) usage ;;
esac

actual=$(tmux display-message -p -t "$pane" '#{pane_id}' 2>/dev/null) || {
  printf 'toggle-log.sh: pane not found: %s\n' "$pane" >&2
  exit 1
}
[ "$actual" = "$pane" ] || {
  printf 'toggle-log.sh: pane not found: %s\n' "$pane" >&2
  exit 1
}

pipe=$(tmux display-message -p -t "$pane" '#{pane_pipe}') || exit
if [ "$pipe" = 1 ]; then
  path=$(tmux show-option -p -qv -t "$pane" @log_path 2>/dev/null || true)
  tmux pipe-pane -t "$pane" || exit
  tmux set-option -p -u -t "$pane" @log_path 2>/dev/null || true
  [ -n "$path" ] || path='unknown path'
  tmux display-message "pane log off: $path"
  exit 0
fi

session=$(tmux display-message -p -t "$pane" '#{session_name}') || exit
window=$(tmux display-message -p -t "$pane" '#{window_index}') || exit
# tr also replaces embedded newlines; sed works line-by-line and would preserve them in a name.
safe_session=$(printf '%s' "$session" | LC_ALL=C tr -c 'A-Za-z0-9_-' '_')
[ -n "$safe_session" ] || safe_session=session
path=${HOME:?}/tmux-${safe_session}-w${window}-p${digits}.log

# Quote for the shell command consumed by pipe-pane, including the uncommon case of a quote in
# $HOME. The session-derived part is already restricted to the portable filename allowlist.
quoted=$(printf '%s' "$path" | sed "s/'/'\\\\''/g")
quoted="'$quoted'"
tmux pipe-pane -o -t "$pane" "cat >> $quoted" || exit
tmux set-option -p -t "$pane" @log_path "$path"
tmux display-message "pane log ON: $path"
