#!/bin/sh
# session-color.sh <name> — the pill colours for a session, printed as "background<TAB>ink".
# scripts/session-created.sh publishes them as the @pill / @pill_ink options the status bar reads.
#
# LOCAL sessions all wear the theme accent. The pills are deliberately one colour: the window pill
# and the mode pill are the accent too, and a per-session rainbow made the left one look like it
# belonged to a different bar.
#
# ssh_<host> sessions are the exception, and the only one worth having: "this pane is on a remote
# box" is the distinction this whole config exists to make obvious (see the SSH shield in tmux.conf
# section 2). Those get a deterministic tint — a CRC of the name indexes the cycle, so a host keeps
# the same colour forever, across restarts.
#
# BOTH colours come from the @thm_* theme block in tmux.conf, never from here. The tint cycle is
# @thm_ssh_tints, a list of "background:ink" pairs; the ink travels WITH the background because
# Latte's accents sit at wildly different luminances — white text is legible on mauve and illegible
# on yellow — so a single pill foreground cannot serve them all. The literals below are only a
# fallback for a run outside tmux.
set -u

name="${1:-}"

thm() {
  v=$(tmux display-message -p "#{E:@thm_$1}" 2>/dev/null) || v=''
  [ -n "$v" ] || v="$2"
  printf '%s' "$v"
}

# Anything that is not a remote session — including no argument at all — is the accent.
case "$name" in
  ssh_?*) ;;
  *) printf '%s\t%s\n' "$(thm accent '#1e66f5')" "$(thm ink '#ffffff')"; exit 0 ;;
esac

tints=$(tmux display-message -p '#{E:@thm_ssh_tints}' 2>/dev/null) || tints=''
[ -n "$tints" ] || tints='#dc8a78:#000000 #dd7878:#000000 #ea76cb:#000000 #8839ef:#ffffff #e64553:#000000 #fe640b:#000000 #df8e1d:#000000 #40a02b:#000000 #179299:#000000 #04a5e5:#000000 #209fb5:#000000 #7287fd:#000000'

# Split the cycle into the argument vector — POSIX sh has no arrays, and `set --` is how this repo
# indexes a list. Word-splitting is the point here, so no quotes.
# shellcheck disable=SC2086
set -- $tints
[ "$#" -gt 0 ] || { printf '%s\t%s\n' '#8839ef' '#ffffff'; exit 0; }

# `cksum` is POSIX and on macOS + Linux → "CRC BYTES"; keep the CRC and fold it onto the cycle.
# Hashing the full "ssh_<host>" name (not the bare host) keeps every existing host on the colour it
# already had.
crc=$(printf %s "$name" | cksum)
crc=${crc%% *}
idx=$(( crc % $# ))

# Walk to the chosen entry: shift idx times, then $1 is it.
while [ "$idx" -gt 0 ]; do
  shift
  idx=$(( idx - 1 ))
done

printf '%s\t%s\n' "${1%%:*}" "${1#*:}"
