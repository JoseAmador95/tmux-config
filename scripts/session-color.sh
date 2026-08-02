#!/bin/sh
# session-color.sh <name> — deterministic pill colour for a session name.
# Same name → same colour, stable across restarts (the Zellij "each session has its colour" cue):
# a CRC of the name indexes a fixed palette. Colours are dark enough for white pill text. Used by
# session-created.sh to tint the status-bar session pill; ssh_<host> names get a stable per-host
# colour for free. No host/name given → a neutral blue, so the pill never renders empty.
set -u

name="${1:-}"
[ -n "$name" ] || { printf '%s\n' '#005A9E'; exit 0; }

# `cksum` is POSIX and on macOS + Linux → "CRC BYTES"; keep the CRC and fold it onto the palette.
crc=$(printf %s "$name" | cksum)
crc=${crc%% *}
idx=$(( crc % 12 ))

case "$idx" in
  0)  c='#C0392B' ;;  # red
  1)  c='#D35400' ;;  # orange
  2)  c='#B9770E' ;;  # amber
  3)  c='#1E8449' ;;  # green
  4)  c='#148F77' ;;  # teal
  5)  c='#2874A6' ;;  # blue
  6)  c='#6C3483' ;;  # purple
  7)  c='#A93226' ;;  # crimson
  8)  c='#1F618D' ;;  # steel
  9)  c='#7D3C98' ;;  # violet
  10) c='#117A65' ;;  # sea green
  *)  c='#B7950B' ;;  # gold (idx 11)
esac

printf '%s\n' "$c"
