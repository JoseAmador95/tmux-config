#!/bin/sh
# copy-last-output.sh <pane-id> — copy ONLY the last command's output. Bound to `prefix + Y`.
#
# WHY THIS IS A SCRIPT AND NOT A CHAIN OF send-keys IN tmux.conf: it used to be that chain, and it
# ended with an unconditional `display-message "last output copied"`. When the copy produced
# nothing the message still said it had. From tmux.1, on previous-prompt / next-prompt:
#
#     …require the shell to emit an escape sequence (\033]133;A) to tell tmux where the prompts
#     are located… The -o flag jumps to the beginning of the command output… requires the shell to
#     emit (\033]133;C)… If the shell does not send these escape sequences, THESE COMMANDS DO
#     NOTHING.
#
# Nothing, silently. So the cursor never moves, the selection is empty, and the bar cheerfully
# reports success. This script does the same sequence and then checks whether a buffer actually
# appeared, so the failure names its own cause instead of looking like a broken key.
#
# The marks come from shell/functions.sh, which emits both from zsh — but only when the shell is
# zsh, $TMUX is set at rc-source time, T_NO_OSC133 is unset, and `autoload -Uz add-zsh-hook`
# succeeds. If this reports no shell integration, run THIS inside a tmux pane:
#
#     typeset -f _t_osc133_precmd >/dev/null && echo loaded || echo "functions.sh not sourced here"
#     print -l $precmd_functions | grep osc133
#
# The usual answer is that the rc carrying functions.sh is only read by LOGIN shells, so `t` works
# from outside tmux while the non-login shell tmux starts never sees the block.
#
# `prefix + y` (the whole scrollback) depends on none of this and is unaffected.
set -u

pane="${1:-}"
[ -n "$pane" ] || pane=$(tmux display-message -p '#{pane_id}')

pos() { tmux display-message -p -t "$pane" '#{scroll_position}/#{copy_cursor_y}'; }

# DETECT FIRST, COPY SECOND. Entering copy-mode puts the cursor on the last line of the pane, and
# the previous command's output always begins above that — so if `previous-prompt -o` leaves the
# cursor exactly where it was, there are no marks to find.
#
# Checking the result instead of the precondition does NOT work, which is why this looks
# roundabout. Measured on a shell that emits no marks: the sequence still produces a buffer, and
# that buffer contains an empty line and the prompt line — the cursor never moved, so it "selected"
# from the bottom up one line. A non-empty buffer is therefore not evidence of anything, and the
# real failure is a WRONG copy rather than an absent one.
tmux copy-mode -t "$pane"
start=$(pos)
tmux send-keys -t "$pane" -X previous-prompt -o
if [ "$(pos)" = "$start" ]; then
  tmux send-keys -t "$pane" -X cancel 2>/dev/null
  tmux display-message "prefix + Y needs OSC 133 marks — shell integration is not active (see scripts/copy-last-output.sh)"
  exit 0
fi

# The marks are there. Select from the start of the output to the line above the next prompt.
tmux send-keys -t "$pane" -X begin-selection
tmux send-keys -t "$pane" -X next-prompt
tmux send-keys -t "$pane" -X cursor-up
tmux send-keys -t "$pane" -X end-of-line
tmux send-keys -t "$pane" -X copy-selection-and-cancel
tmux display-message "last output copied"
