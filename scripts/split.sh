#!/bin/sh
# split.sh — Zellij-like split for M-n: splits the LONGER axis so repeated splits spiral like
# Zellij's dynamic tiling (fibonacci feel). A wide pane splits left/right (-h), a tall pane splits
# top/bottom (-v). The @no_split lock is enforced by the binding (tmux.conf), not here. Launched
# via run-shell, so the tmux commands target the active pane (like scripts/session-goto.sh).
set -u
w=$(tmux display-message -p '#{pane_width}')
h=$(tmux display-message -p '#{pane_height}')
cwd=$(tmux display-message -p '#{pane_current_path}')
# Cells are ~2x taller than wide, so weigh height x2 before comparing.
if [ "${w:-0}" -gt "$(( ${h:-0} * 2 ))" ]; then
  tmux split-window -h -c "$cwd"
else
  tmux split-window -v -c "$cwd"
fi
