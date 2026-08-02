#!/bin/sh
# session-goto.sh N — jump to the N-th session (1-based) of the status bar's session list.
# Bound to `prefix + <digit>` and launched via `run-shell`, so it switches the client WITHOUT
# opening a pane. tmux has no stable session index; the canonical order is the live session list
# sorted alphabetically — the SAME order the status-right bar renders, so the visible position
# and the digit match.
set -u

n="${1:-}"
case "$n" in
  '' | *[!0-9]*) exit 0 ;;   # no argument or non-numeric: do nothing
esac
[ "$n" -ge 1 ] || exit 0

# N maps to the N-th line of the alphabetically sorted live-session list.
target=$(tmux list-sessions -F '#{session_name}' 2>/dev/null | sort | sed -n "${n}p")

# Out of range (fewer sessions than the digit pressed) or already there → no-op.
[ -n "$target" ] || exit 0

tmux switch-client -t "=$target"
