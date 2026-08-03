#!/bin/sh
# session-created.sh — the target of the `session-created` AND `session-renamed` hooks, and of a
# one-shot `--all` sweep when the config loads. Runs once per session (created by ANY path: the t*
# functions, `tmux new`, choose-tree, a sourced file, …).
#
# Two jobs:
#   1) SSH shield (second layer): for every "ssh_<host>" session set a per-session
#      `default-command` that enters the host over SSH — even sessions NOT created by tssh
#      (e.g. `tmux new -s ssh_foo`), so a new window or split can never fall back to a local shell.
#      `default-command` is a SESSION option: it applies to new-window AND split-window and does
#      NOT leak to other (local) sessions. NEVER set it with `set -g` — every local session would SSH.
#   2) Per-session colour: publish this name's deterministic colour (session-color.sh) as the
#      session-scoped `@pill` user option, which the global `status-left` in tmux.conf reads.
#
# WHY @pill and not a whole status-left string: the colour used to be baked into a literal
# status-left at CREATION time, so a rename re-rendered #S with the OLD colour, and the pill format
# existed in two places that had to be kept identical. Publishing one value instead means the pill's
# shape lives only in tmux.conf and re-tinting is just this hook firing again.
#
# WHY it must be idempotent: it now runs on rename too, and renaming crosses the ssh_ boundary in
# both directions — so a session renamed AWAY from ssh_* has to have its default-command removed,
# or it would keep SSHing into a host whose name is no longer anywhere on screen.
set -u

SCRIPTS=$(cd "$(dirname "$0")" && pwd)

apply() {
  s="$1"

  case "$s" in
    ssh_?*)
      host=${s#ssh_}
      tmux set-option -t "$s" default-command "$SCRIPTS/ssh-host.sh $host"
      ;;
    *)
      # -u drops the SESSION option only; the global one is never set (see the NEVER above).
      # The flags must stay separate: `-tu <name>` is parsed as `-t u`, which silently targets a
      # session called "u" and leaves the real default-command in place.
      tmux set-option -u -t "$s" default-command 2>/dev/null || true
      ;;
  esac

  # Deterministic pill colour (stable per name; ssh_<host> → stable per host).
  tmux set-option -t "$s" @pill "$("$SCRIPTS/session-color.sh" "$s")"
}

# The status bar's session strip is derived from the same list, so anything that changes a session
# has to refresh it. Calling it from here covers create and rename; tmux.conf hooks the two events
# that do not pass through this script (a session closing, and the client switching session).
refresh_strip() { "$SCRIPTS/session-strip.sh"; }

# --all: tint every live session. Sessions that existed before this config was loaded never got a
# session-created hook, so without this sweep they kept the default pill forever.
if [ "${1:-}" = '--all' ]; then
  tmux list-sessions -F '#{session_name}' 2>/dev/null | while IFS= read -r s; do
    [ -n "$s" ] && apply "$s"
  done
  refresh_strip
  exit 0
fi

s="${1:-}"
[ -n "$s" ] || exit 0
apply "$s"
refresh_strip
