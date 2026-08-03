#!/bin/sh
# session-created.sh — re-applies the per-session state that is DERIVED FROM THE SESSION NAME.
# Wired to the `session-created` and `session-renamed` hooks and run once when the config loads.
#
# Two jobs, for every live session:
#   1) SSH shield (second layer): for every "ssh_<host>" session set a per-session
#      `default-command` that enters the host over SSH — even sessions NOT created by tssh
#      (e.g. `tmux new -s ssh_foo`), so a new window or split can never fall back to a local shell.
#      `default-command` is a SESSION option: it applies to new-window AND split-window and does
#      NOT leak to other (local) sessions. NEVER set it with `set -g` — every local session would SSH.
#   2) Per-session colour: publish this name's deterministic colour (session-color.sh) as the
#      session-scoped `@pill` user option, which the global `status-left` in tmux.conf reads.
#
# WHY IT TAKES NO ARGUMENTS. The hooks used to pass `#{hook_session_name}`, which tmux interpolates
# RAW into the shell command line — so a session called "my proj" reached the script as $1="my"
# (and the rename silently kept the old colour), and a name containing $(…) would have been
# executed. Session names are user input, and the popup's rename/new prompts make that input easy
# to type. Sweeping every session instead means no name ever reaches a command line: the loop reads
# them into a shell variable, which is quoted. A sweep costs one list-sessions plus one set-option
# per session, on an event that happens when a human creates or renames something.
#
# WHY @pill and not a whole status-left string: the colour used to be baked into a literal
# status-left at CREATION time, so a rename re-rendered #S with the OLD colour, and the pill format
# existed in two places that had to be kept identical. Publishing one value instead means the
# pill's shape lives only in tmux.conf.
#
# WHY it must be idempotent: it runs on rename too, and renaming crosses the ssh_ boundary in both
# directions — so a session renamed AWAY from ssh_* has to have its default-command removed, or it
# would keep SSHing into a host whose name is no longer anywhere on screen.
set -u

SCRIPTS=$(cd "$(dirname "$0")" && pwd)

apply() {
  s="$1"

  case "$s" in
    ssh_?*)
      host=${s#ssh_}
      # default-command is a SHELL command string, so the host goes through a shell a second time.
      # Rather than quote it and hope, refuse anything that is not plausibly a host: a name is
      # whatever the user typed into the rename prompt.
      case "$host" in
        *[!A-Za-z0-9._@-]*)
          tmux display-message "ssh shield: '$s' has an unusable host name; no default-command set"
          tmux set-option -u -t "$s" default-command 2>/dev/null || true
          ;;
        *)
          tmux set-option -t "$s" default-command "$SCRIPTS/ssh-host.sh $host"
          ;;
      esac
      ;;
    *)
      # -u drops the SESSION option only; the global one is never set (see the NEVER above).
      # The flags must stay separate: `-tu <name>` is parsed as `-t u`, which silently targets a
      # session called "u" and leaves the real default-command in place.
      tmux set-option -u -t "$s" default-command 2>/dev/null || true
      ;;
  esac

  # Deterministic pill colour (stable per name; ssh_<host> → stable per host).
  # Plain -t is already an exact session lookup here (a session "foo" does not match "foobar");
  # the "=" exact-match prefix that works for switch-client is REJECTED by set-option.
  tmux set-option -t "$s" @pill "$("$SCRIPTS/session-color.sh" "$s")"
}

tmux list-sessions -F '#{session_name}' 2>/dev/null | while IFS= read -r s; do
  [ -n "$s" ] && apply "$s"
done

# The status bar's session strip is derived from the same list, so refresh it here too.
"$SCRIPTS/session-strip.sh"
