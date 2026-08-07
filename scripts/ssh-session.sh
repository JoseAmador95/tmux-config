#!/bin/sh
# ssh-session.sh — create or adopt one protected SSH session without losing the exact host.
#
# A tmux session name cannot contain every character accepted by SSH aliases (`.` and `@` are
# useful examples), so the display name is only an identifier. The exact target lives in the
# session-scoped @ssh_host option and session-created.sh uses that metadata for every later pane.
# This also lets cosmetic renames within the ssh_* namespace keep pointing at the same host.
set -u

usage() {
  printf 'usage: ssh-session.sh <host|~/.ssh/config alias>\n' >&2
  exit 64
}

[ "$#" -eq 1 ] || usage
host=$1

# Host options belong in ~/.ssh/config. Refusing leading '-' and shell punctuation makes the
# value safe both as one ssh argv element and inside tmux's session default-command string.
case "$host" in
  ''|-*|*[!A-Za-z0-9._@-]*)
    printf "ssh-session.sh: invalid host: %s\n" "$host" >&2
    exit 64
    ;;
esac

SCRIPTS=$(cd "$(dirname "$0")" && pwd)
safe_host=$(printf '%s\n' "$host" | sed 's/[^A-Za-z0-9_-]/_/g')
session="ssh_$safe_host"

if tmux has-session -t "=$session" 2>/dev/null; then
  existing=$(tmux show-option -qv -t "$session" @ssh_host 2>/dev/null || true)
  if [ -n "$existing" ] && [ "$existing" != "$host" ]; then
    printf "ssh-session.sh: session '%s' already targets '%s' (requested '%s')\n" \
      "$session" "$existing" "$host" >&2
    exit 1
  fi
else
  # The host has already passed the strict allowlist, so this shell-command cannot acquire extra
  # words or operators. ssh-host.sh validates it again before passing it as one quoted ssh argv.
  tmux new-session -d -s "$session" "$SCRIPTS/ssh-host.sh $host" || exit
fi

# Adopt metadata-less manual sessions and refresh the shield synchronously. The hook also does
# this asynchronously on creation, but tssh must not return before every future pane is protected.
tmux set-option -t "$session" @ssh_host "$host"
"$SCRIPTS/session-created.sh"

# stdout is an API consumed by tssh; diagnostics above go to stderr.
printf '%s\n' "$session"
