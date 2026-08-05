#!/bin/sh
# keys.sh — which-key style cheatsheet of the custom bindings, in a searchable fzf popup. Replaces
# the raw `list-keys` of `prefix + ?`. Reference only: type to filter, Esc closes.
set -u
. "$(cd "$(dirname "$0")" && pwd)/fzf-style.sh"   # --reverse + the shared --color, from the theme

cat <<'EOF' | fzf $(fzf_style) --info=inline --no-sort --prompt 'keys ' \
    --header 'filter · Esc closes'
NAVIGATION
  M-h/j/k/l     move focus between panes (or nvim splits)
  M-n           split (Zellij-like, longer axis)  M-t   new window in the cwd
  M-1..9        go to window N                    M-; / M-'   previous / next window
  M-, / M-.     previous / next session           M-s   session tree
  M--           last session (toggle)             M-0 / prefix 0  always jump to main
  prefix Tab    last session (toggle), same as M--
  click the session pill on the right to open the session tree too
SESSION TREE (M-s) — tmux's own picker, no modes
  1-9 / Enter  switch      j/k  move           C-s  search by name (n/N repeat)
  x  kill session          t  tag   X  kill tagged        q / Esc  close
  rename & create a session live in the M-Space palette
PANES
  prefix H/J/K/L   resize                         prefix z  zoom (default)
  prefix R         revive dead pane               prefix x  kill pane (default)
COPY
  M-i           enter copy-mode                    prefix [  enter copy-mode (tmux default)
  prefix y      copy the WHOLE scrollback          prefix Y  copy only the last output
  v / y         (copy-mode) select / copy          C-c    (copy-mode) copy
  d / u         (copy-mode) jump 10 lines down / up
  o / C-o       (copy-mode) open selection / open it in $EDITOR
FIND / GRAB
  prefix e      grab a path/URL/token off screen   prefix F  search scrollback, jump to hit
  prefix f      label every match on screen, press its letter to copy
  M-f           same, no prefix
  prefix u      pick a URL and open it             U / O     (copy-mode) prev URL / prev path
  s             (copy-mode) easy-motion jump
WINDOWS & SESSIONS
  prefix < / >  move this window left / right       prefix @  promote this pane to a session
  prefix P      toggle logging this pane to a file  prefix N  alert when this window goes quiet
GENERAL
  M-Space       command palette                    prefix :  command prompt (tmux)
  prefix ?      this help                          prefix r  reload config
  F12           OFF mode (all tmux keys off)
EOF
