#!/bin/sh
# session-color.sh <name> — deterministic pill colour for a session name.
# Same name → same colour, stable across restarts (the Zellij "each session has its colour" cue):
# a CRC of the name indexes a fixed palette. Used by session-created.sh to tint the status-bar
# session pill; ssh_<host> names get a stable per-host colour for free. No name given → the bar's
# own accent, so the pill never renders empty.
#
# The palette is tuned, not picked: index 0 IS the bar accent (#005FB8) and every other entry sits
# at a comparable darkness, so twelve different sessions still read as one design rather than a
# bag of web colours. Every value was measured at >= 5:1 against the white pill text (WCAG AA),
# which is the whole constraint — the pill is white-on-colour and nothing else.
set -u

name="${1:-}"
[ -n "$name" ] || { printf '%s\n' '#005FB8'; exit 0; }

# `cksum` is POSIX and on macOS + Linux → "CRC BYTES"; keep the CRC and fold it onto the palette.
crc=$(printf %s "$name" | cksum)
crc=${crc%% *}
idx=$(( crc % 12 ))

# contrast vs the white pill text, measured:
case "$idx" in
  0)  c='#005FB8' ;;  # blue     6.31:1  (the bar accent itself)
  1)  c='#1F6FA8' ;;  # steel    5.39:1
  2)  c='#00697A' ;;  # cyan     6.36:1
  3)  c='#00706B' ;;  # teal     5.95:1
  4)  c='#2E7D32' ;;  # green    5.13:1
  5)  c='#8A6100' ;;  # amber    5.54:1
  6)  c='#A34A00' ;;  # orange   5.94:1
  7)  c='#B3261E' ;;  # red      6.54:1
  8)  c='#A61C4B' ;;  # crimson  7.27:1
  9)  c='#6A3FA0' ;;  # violet   7.42:1
  10) c='#4A4BA8' ;;  # indigo   7.33:1
  *)  c='#6D4C41' ;;  # brown    7.61:1  (idx 11)
esac

printf '%s\n' "$c"
