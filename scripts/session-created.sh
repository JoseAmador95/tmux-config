#!/bin/sh
# session-created.sh — the `session-created` hook target. Runs once per new session (created by
# ANY path: the t* functions, `tmux new`, choose-tree, a sourced file, …).
#
# Two jobs:
#   1) SSH shield (second layer): for every "ssh_<host>" session set a per-session
#      `default-command` that enters the host over SSH — even sessions NOT created by tssh
#      (e.g. `tmux new -s ssh_foo`), so a new window or split can never fall back to a local shell.
#      `default-command` is a SESSION option: it applies to new-window AND split-window and does
#      NOT leak to other (local) sessions. NEVER set it with `set -g` — every local session would SSH.
#   2) Per-session colour: tint the status-bar pill with a deterministic colour for this name
#      (session-color.sh), overriding the global status-left for this session only.
set -u

s="${1:-}"
[ -n "$s" ] || exit 0

case "$s" in
  ssh_?*)
    host=${s#ssh_}
    tmux set-option -t "$s" default-command "$HOME/.config/tmux/scripts/ssh-host.sh $host"
    ;;
esac

# Deterministic pill colour (stable per name; ssh_<host> → stable per host).
color=$("$HOME/.config/tmux/scripts/session-color.sh" "$s")
tmux set-option -t "$s" status-left "#[bg=$color,fg=#FFFFFF,bold] #S #[default] "
