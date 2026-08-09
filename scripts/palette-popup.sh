#!/bin/sh
# Own the two popup sizes behind M-Space. The palette exits with the reserved
# status below when review is selected; only then is a second, larger popup
# created after the first popup has fully closed and restored its terminal.
set -u

REVIEW_SELECTED=42
client=${1:-}
pane=${2:-}
script_dir=$(cd "$(dirname "$0")" && pwd -P) || exit 1

say() {
  tmux display-message -c "$client" "palette: $*" 2>/dev/null || true
}

if [ -z "$client" ]; then
  exit 1
fi
case "$pane" in
  %*[!0-9]*|'%'|[!%]*) say "invalid source pane"; exit 1 ;;
esac
if ! repo=$(tmux display-message -p -t "$pane" '#{pane_current_path}' 2>/dev/null); then
  say "could not resolve the source pane directory"
  exit 1
fi
case "$repo" in
  /*) ;;
  *) say "source pane has no usable directory"; exit 1 ;;
esac
if [ ! -d "$repo" ]; then
  say "source pane has no usable directory"
  exit 1
fi

tmux display-popup -E -c "$client" -d "$repo" -w 60% -h 55% \
  -T " palette " "$script_dir/palette.sh"
palette_status=$?
# fzf reports an intentional q/Ctrl-C dismissal as 130. Treat that one status
# as a normal close so run-shell does not surface it as a tmux command error.
if [ "$palette_status" -eq 130 ]; then
  exit 0
fi
if [ "$palette_status" -ne "$REVIEW_SELECTED" ]; then
  exit "$palette_status"
fi

exec tmux display-popup -E -c "$client" -d "$repo" -w 95% -h 95% \
  -T " review " -e "TMUX_PALETTE_SOURCE_PATH=$repo" "$script_dir/tuicr-review.sh"
