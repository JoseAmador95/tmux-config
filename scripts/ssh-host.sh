#!/bin/sh
# ssh-host.sh — the command run by every pane of an "ssh_<host>" session: each new pane/window
# enters the host over SSH (instead of a local shell). Wired two ways:
#   1) tssh (shell/functions.sh) creates the session's first pane with `ssh-host.sh <host>`.
#   2) session-created.sh sets it as the session's `default-command`, so new windows AND splits
#      inherit it. `default-command` is a SESSION option → it never leaks to local sessions.
#
# Why a wrapper (and not just `default-command "ssh -t host"`): a single hardened place that
# also guarantees the SHIELD below, shared by both wiring paths.
#
# SHIELD: the host arrives as an ARGUMENT. If there is no host (e.g. this script somehow becomes
# the default-command of a non-ssh session, or is invoked bare), we open a LOCAL login shell —
# NEVER SSH. This is the tmux equivalent of the zellij version's "only SSH from an ssh_ session".
#
# Note: the remote host does NOT run tmux (only the client here) → a flat remote shell, no nesting.
# Per-host options (user, port, -A) belong in ~/.ssh/config, not here.
set -u

host="${1:-}"
[ -n "$host" ] || exec "${SHELL:-/bin/sh}" -l   # no host → local shell, NEVER SSH

case "$host" in
  -*|*[!A-Za-z0-9._@-]*)
    printf 'ssh-host.sh: invalid host: %s\n' "$host" >&2
    exit 64
    ;;
esac

# The pane IS the connection: on exit/logout the window closes, like a normal shell.
# The validated host is one argv element. Connection options belong in ~/.ssh/config, where they
# cannot turn a session name or shell string into extra command-line arguments.
# `-t` forces a PTY so full-screen remote programs behave.
exec ssh -t "$host"
