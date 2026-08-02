#!/bin/sh
# keys.sh — which-key style cheatsheet of the custom bindings, in a searchable fzf popup. Replaces
# the raw `list-keys` of `prefix + ?`. Reference only: type to filter, Esc closes.
cat <<'EOF' | fzf --reverse --info=inline --no-sort --prompt 'keys ' \
    --header 'filter · Esc closes' \
    --color 'fg+:#ffffff,bg+:#007ACC,prompt:#007ACC,header:#005A9E,border:#007ACC'
NAVIGATION
  M-h/j/k/l     move focus between panes (or nvim splits)
  M-n           split (Zellij-like, longer axis)  M-t   new window in the cwd
  M-1..9        go to window N
  M-, / M-.     previous / next session           M-s   session manager (popup)
  prefix Tab    last session                      prefix 1..9  go to the N-th session
PANES
  prefix H/J/K/L   resize                         prefix z  zoom (default)
  prefix R         revive dead pane               prefix x  kill pane (default)
COPY
  prefix y      copy the WHOLE scrollback          prefix Y  copy only the last output
  v / y         (copy-mode) select / copy          C-c    (copy-mode) copy
  d / u         (copy-mode) half page down / up
GENERAL
  M-Space       command palette                    prefix :  command prompt (tmux)
  prefix ?      this help                          prefix r  reload config
EOF
