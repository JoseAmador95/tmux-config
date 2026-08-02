#!/bin/sh
# session-created.sh — the `session-created` hook target. Runs once per new session (created by
# ANY path: the t* functions, `tmux new`, choose-tree, a sourced file, …).
#
# Its job: for every session named "ssh_<host>", set a per-session `default-command` that enters
# the host over SSH. This is the SECOND layer of the SSH shield — even sessions NOT created by
# tssh (e.g. `tmux new -s ssh_foo`) get the remote command, so a new window or split can never
# fall back to a local shell.
#
# `default-command` is a SESSION option: it applies to new-window AND split-window, and does NOT
# leak to other (local) sessions. NEVER set default-command with `set -g` — that would make every
# local session try to SSH.
set -u

s="${1:-}"
case "$s" in
  ssh_?*)
    host=${s#ssh_}
    tmux set-option -t "$s" default-command "$HOME/.config/tmux/scripts/ssh-host.sh $host"
    ;;
esac
