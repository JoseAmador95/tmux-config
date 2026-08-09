#!/bin/sh
# Start a human-owned review round for the source pane, then attach this popup
# to the round's one private tuicr TUI. The launcher owns all Git/state safety.
set -u

say() {
  tmux display-message "review: $*" 2>/dev/null || true
}

if [ -n "${TMUX_PALETTE_SOURCE_PATH:-}" ]; then
  repo=$TMUX_PALETTE_SOURCE_PATH
else
  pane=${TMUX_PANE:-}
  case "$pane" in
    %*[!0-9]*|'%'|[!%]*) pane='' ;;
  esac
  if [ -n "$pane" ]; then
    if ! repo=$(tmux display-message -p -t "$pane" '#{pane_current_path}' 2>/dev/null); then
      say "could not resolve the source pane directory"
      exit 1
    fi
  elif ! repo=$(tmux display-message -p '#{pane_current_path}' 2>/dev/null); then
    say "could not resolve the source pane directory"
    exit 1
  fi
fi
case "$repo" in
  /*) ;;
  *) say "source pane has no usable directory"; exit 1 ;;
esac
if [ ! -d "$repo" ]; then
  say "source pane has no usable directory"
  exit 1
fi

launcher=${HOME:-}/.config/tuicr/tuicr-round
if [ ! -x "$launcher" ]; then
  say "launcher is not executable: $launcher"
  exit 1
fi

exec "$launcher" start --repo "$repo" --open
