#!/bin/sh
# session-color.sh <name> — pill colour for a session name, used by session-created.sh to publish
# the @pill option the status bar reads.
#
# LOCAL sessions all wear the bar accent. The pills are deliberately one colour: the window pill
# and the mode pill are already #005FB8, and a per-session rainbow made the left one look like it
# belonged to a different bar.
#
# ssh_<host> sessions are the exception, and the only one worth having: "this pane is on a remote
# box" is the distinction this whole config exists to make obvious (see the SSH shield in tmux.conf
# section 2). Those keep a deterministic tint — a CRC of the name indexes a fixed palette, so a
# host has the same colour forever, across restarts.
#
# The palette is tuned, not picked. Two constraints, both measured rather than eyeballed:
#   * >= 5:1 against the white pill text (WCAG AA) — the pill is white-on-colour and nothing else;
#   * no entry within 20° of the accent's hue (209°), or a remote session would read as a local
#     one and the tint would be worse than useless. This is why the old palette's #005FB8 (the
#     accent itself) and #1F6FA8 (4° away — the same blue to any eye) are gone.
set -u

name="${1:-}"

# Anything that is not a remote session — including no argument at all — is the accent.
case "$name" in
  ssh_?*) ;;
  *) printf '%s\n' '#005FB8'; exit 0 ;;
esac

# `cksum` is POSIX and on macOS + Linux → "CRC BYTES"; keep the CRC and fold it onto the palette.
# Hashing the full "ssh_<host>" name (not the bare host) keeps every existing host on the colour it
# already had.
crc=$(printf %s "$name" | cksum)
crc=${crc%% *}
idx=$(( crc % 12 ))

# contrast vs the white pill text, and hue distance from the #005FB8 accent — both measured:
case "$idx" in
  0)  c='#8E2A6B' ;;  # magenta  7.80:1   Δhue 112°
  1)  c='#5C6B00' ;;  # olive    5.90:1   Δhue 141°
  2)  c='#00697A' ;;  # cyan     6.36:1   Δhue  21°
  3)  c='#00706B' ;;  # teal     5.95:1   Δhue  32°
  4)  c='#2E7D32' ;;  # green    5.13:1   Δhue  86°
  5)  c='#8A6100' ;;  # amber    5.54:1   Δhue 167°
  6)  c='#A34A00' ;;  # orange   5.94:1   Δhue 178°
  7)  c='#B3261E' ;;  # red      6.54:1   Δhue 154°
  8)  c='#A61C4B' ;;  # crimson  7.27:1   Δhue 131°
  9)  c='#6A3FA0' ;;  # violet   7.42:1   Δhue  58°
  10) c='#4A4BA8' ;;  # indigo   7.33:1   Δhue  30°
  *)  c='#6D4C41' ;;  # brown    7.61:1   Δhue 166°  (idx 11)
esac

printf '%s\n' "$c"
