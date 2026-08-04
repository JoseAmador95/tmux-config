#!/bin/sh
# session-goto.sh N — jump to the N-th session (1-based) of the status bar's session list.
# Bound to `prefix + <digit>` and launched via `run-shell`, so it switches the client WITHOUT
# opening a pane. tmux has no stable session index, so the order comes from session-order.sh —
# the SAME script the bar and the Alt-s popup use, which is what makes the visible position and
# the digit the same session. Do not sort here.
set -u

SELF_DIR=$(cd "$(dirname "$0")" && pwd)

n="${1:-}"
case "$n" in
  '' | *[!0-9]*) exit 0 ;;   # no argument or non-numeric: do nothing
esac
[ "$n" -ge 1 ] || exit 0

# N maps to the N-th line of the canonical order.
target=$("$SELF_DIR/session-order.sh" 2>/dev/null | sed -n "${n}p")

# Out of range (fewer sessions than the digit pressed) or already there → no-op.
[ -n "$target" ] || exit 0

tmux switch-client -t "=$target"
