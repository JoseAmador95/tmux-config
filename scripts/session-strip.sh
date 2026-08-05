#!/bin/sh
# session-strip.sh — render the CURRENT session's pill into the @session_strip user option, which
# status-right reads back with #{E:@session_strip}. Driven by the session hooks in tmux.conf.
#
# IT USED TO RENDER ALL NINE. That list was 40 columns wide with only four sessions open, and
# `status-justify absolute-centre` centres the window list on the TERMINAL without regard for what
# is in status-right — tmux clips rather than reflows, so the tabs overwrote the right-hand side.
# The mode indicator was the casualty: with 4 sessions on 90 columns it rendered as the two
# characters "de", the tail of "tree-mode". Round 4 wrote that off as "KNOWN, ACCEPTED"; it was not.
#
# So the bar now says WHERE YOU ARE and the Alt-s tree says where you can go. One pill, ~10 columns,
# and the collision has room to spare.
#
# The digit is kept because it is the one piece of the old strip that earned its space: it tells you
# which `prefix + <digit>` you are sitting on, which is the anchor for the ones either side of it.
#
# WHY an option written by a hook instead of a format: tmux's #{S:…} session loop has no index
# variable, so the NUMBER cannot be produced by a format at all. The other option, #(…) in
# status-right, would need status-interval > 0 to ever refresh (see §3b) — and this changes only
# when a session is created, renamed, killed or switched to, which is exactly what the hooks catch.
# Reading #{@…} is free.
#
# Order comes from session-order.sh — `main` first, then most recently used — and NOTHING here
# sorts. session-goto.sh calls the same script, which is what keeps the digit shown here and the
# digit you press pointing at the same session.
#
# Session names are UNTRUSTED here — they are whatever the user typed. status-right expands this
# option with #{E:…}, so every "#" in a name is doubled: without that, a session called
# "#[bg=red]" would inject a style into the bar and "#{session_name}" would be expanded. Our own
# #[…] markup is added after the escaping, so it still works.
set -u

# Colours come from the @thm_* theme block in tmux.conf, the single place the palette lives; the
# literals are only a fallback for a run outside tmux. This script always runs from a tmux hook.
thm() {
  v=$(tmux display-message -p "#{E:@thm_$1}" 2>/dev/null) || v=''
  [ -n "$v" ] || v="$2"
  printf '%s' "$v"
}
CHIP=$(thm chip '#ccd0da')   # the neutral half of the current-session pill
TEXT=$(thm text '#4c4f69')
# The COLOURED half is the session's own @pill / @pill_ink, not the global accent: that is what
# makes an ssh_<host> session keep its per-host tint here as well as in the left pill.
PILL=$(tmux display-message -p '#{@pill}' 2>/dev/null) || PILL=''
[ -n "$PILL" ] || PILL='#1e66f5'
PINK=$(tmux display-message -p '#{@pill_ink}' 2>/dev/null) || PINK=''
[ -n "$PINK" ] || PINK='#ffffff'

# Which session to mark. It has to come from the ATTACHED CLIENT, not from `#S`: this script runs
# from the session-created hook too, and there "#S" is the session that was just created — which
# for a detached `new-session -d` is precisely the one you are NOT looking at. With no client at
# all (a scripted server), fall back to #S so the strip still marks something.
# @session_strip is a GLOBAL option, so the "current" mark is shared: with two clients attached to
# different sessions both bars would highlight the first client's. This config is built around one
# terminal window (see README), so that is an accepted limitation, not an oversight.
cur=$(tmux list-clients -F '#{client_session}' 2>/dev/null | head -n 1)
[ -n "$cur" ] || cur=$(tmux display-message -p '#S' 2>/dev/null)

# Find the current session's position in the canonical order, then render just that one pill.
# The loop still walks the list because the POSITION is the thing being looked up; it stops as soon
# as it finds the match. Keeping it inside one command substitution is the POSIX way to stop the
# accumulator being lost to a subshell.
strip=$(
  "$(cd "$(dirname "$0")" && pwd)/session-order.sh" 2>/dev/null | {
    i=0
    acc=''
    while IFS= read -r s; do
      i=$((i + 1))
      [ "$s" = "$cur" ] || continue
      esc=$(printf '%s' "$s" | sed 's/#/##/g')
      # Two chips, the same shape as a window tab: the accent holds the index, the name sits on a
      # neutral chip, and each cap takes the colour of the chip it terminates. The spaces around
      # ${i} are the padding that makes the accent 3 columns wide, matching a tab's.
      acc=" #[fg=${PILL},bg=terminal]#[fg=${PINK},bg=${PILL},bold] ${i} #[fg=${TEXT},bg=${CHIP},nobold] ${esc} #[fg=${CHIP},bg=terminal]#[default]"
      break
    done
    printf '%s' "$acc"
  }
)

tmux set-option -g @session_strip "$strip "
