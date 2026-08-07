#!/bin/sh
# split.sh — the single split entrypoint for bindings and the command palette.
#
# Usage: split.sh <pane-id> [auto|vertical|horizontal]
# `auto` splits the longer visual axis for a fibonacci-like spiral. Every mode enforces the
# window-scoped @no_split lock here, so adding a new caller cannot accidentally bypass it.
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

locked=$(tmux display-message -p -t "$pane" '#{@no_split}' 2>/dev/null || true)
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
    # Cells are approximately twice as tall as wide, so weigh height before comparing.
    if [ "$width" -gt "$((height * 2))" ]; then
      direction=-h
    else
      direction=-v
    fi
    ;;
esac

tmux split-window -t "$pane" "$direction" -c "$cwd"
