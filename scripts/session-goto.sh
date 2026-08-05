#!/bin/sh
# session-goto.sh N — jump to the N-th session (1-based) of session-order.sh's canonical order.
# Bound to `prefix + <digit>` and launched via `run-shell`, so it switches the client WITHOUT
# opening a pane. tmux has no stable session index, so the order comes from session-order.sh.
#
# THIS SCRIPT IS session-order.sh's ONLY REMAINING CONSUMER. The status bar used to share this
# order too — first showing every session's digit, then, after round 8 cut the bar down to one
# pill, at least that pill's own — but the bar reads nothing from this file any more (see
# session-order.sh's own header for why). So a digit pressed here is no longer something you can
# read off the bar first; it is memorised, or looked up in the `Alt-s` tree, which numbers its
# entries by a DIFFERENT rule (choose-tree's own `-O`, not this file). Do not sort here.
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
