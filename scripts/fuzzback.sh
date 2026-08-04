#!/bin/sh
# fuzzback.sh <pane-id> — fuzzy-search this pane's scrollback and jump to the hit.
# Bound to `prefix + F`. This is tmux-fuzzback without the plugin.
#
# copy-mode's own `/` already searches, but it shows you one match at a time; this shows every
# match at once and lands the cursor on the one you pick.
#
# THE LINE MATH IS THE WHOLE SCRIPT, and it is not what you would guess. `goto-line N` counts
# BACKWARDS FROM THE BOTTOM: N=0 is the last line, not the first. And the addressable range is only
# 0..history_size, while `capture-pane -S -` hands back history_size + pane_height lines — so the
# oldest lines of a naive capture cannot be reached at all, and a naive index silently lands you
# somewhere else entirely (measured: index 3 of 61 jumped to the line at index 10).
#
# So: keep exactly the last (history_size + 1) lines, which is precisely the addressable window,
# and then N = keep - i for a 1-based index i. Verified line by line on an isolated socket.
set -u
. "$(cd "$(dirname "$0")" && pwd)/fzf-style.sh"

pane="${1:-}"
[ -n "$pane" ] || exit 0

hist=$(tmux display-message -p -t "$pane" '#{history_size}' 2>/dev/null) || exit 0
keep=$((hist + 1))

# -J joins wrapped lines so a match is not split by the pane width; grep -n numbers what fzf shows,
# and that number is what the jump is computed from.
sel=$(tmux capture-pane -pJS - -t "$pane" 2>/dev/null | tail -n "$keep" | grep -n '.' |
      fzf $(fzf_style) --delimiter ':' --with-nth '2..' --info=inline --no-sort --tac \
          --prompt 'scrollback ' --header 'Enter jumps there · Esc cancels') || exit 0
[ -n "$sel" ] || exit 0

i=${sel%%:*}
case "$i" in ''|*[!0-9]*) exit 0 ;; esac

tmux copy-mode -t "$pane"
tmux send-keys -t "$pane" -X goto-line "$((keep - i))"
