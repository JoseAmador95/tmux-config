#!/bin/sh
# split.sh — the single split entrypoint for bindings and the command palette.
#
# Usage: split.sh <pane-id> [auto|vertical|horizontal]
# `auto` splits the larger fraction of the containing window for a fibonacci-like spiral. A full
# pane goes left/right, either half then goes top/bottom, and a 2x2 cell goes left/right again.
# Every mode enforces both the named tool-window policy and the window-scoped @no_split lock here,
# so adding a new caller cannot accidentally bypass either one.
set -u

usage() {
  printf 'usage: split.sh <pane-id> [auto|vertical|horizontal]\n' >&2
  exit 64
}

case "$#" in
  1|2) ;;
  *) usage ;;
esac

pane=$1
mode=${2:-auto}
digits=${pane#%}
case "$pane:$digits" in
  %*:*) ;;
  *) usage ;;
esac
case "$digits" in
  ''|*[!0-9]*) usage ;;
esac
case "$mode" in
  auto|vertical|horizontal) ;;
  *) usage ;;
esac

actual=$(tmux display-message -p -t "$pane" '#{pane_id}' 2>/dev/null) || {
  printf 'split.sh: pane not found: %s\n' "$pane" >&2
  exit 1
}
[ "$actual" = "$pane" ] || {
  printf 'split.sh: pane not found: %s\n' "$pane" >&2
  exit 1
}

window_name=$(tmux display-message -p -t "$pane" '#{window_name}') || exit
case "$window_name" in
  agent|editor|git) locked=1 ;;
  *) locked=$(tmux display-message -p -t "$pane" '#{@no_split}' 2>/dev/null || true) ;;
esac
if [ -n "$locked" ] && [ "$locked" != 0 ]; then
  tmux display-message 'this pane is locked (no splits)'
  exit 1
fi

cwd=$(tmux display-message -p -t "$pane" '#{pane_current_path}') || exit

case "$mode" in
  horizontal)
    direction=-h
    ;;
  vertical)
    direction=-v
    ;;
  auto)
    width=$(tmux display-message -p -t "$pane" '#{pane_width}') || exit
    height=$(tmux display-message -p -t "$pane" '#{pane_height}') || exit
    window_width=$(tmux display-message -p -t "$pane" '#{window_width}') || exit
    window_height=$(tmux display-message -p -t "$pane" '#{window_height}') || exit
    # Compare occupied fractions without floating point:
    #   pane_width / window_width >= pane_height / window_height
    # Raw cell dimensions made the second split left/right again on ultrawide terminals.
    if [ "$((width * window_height))" -ge "$((height * window_width))" ]; then
      direction=-h
    else
      direction=-v
    fi
    ;;
esac

tmux split-window -t "$pane" "$direction" -c "$cwd"
