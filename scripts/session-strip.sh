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
# THE PILL IS ROUNDED, matching the window tabs:  and  are the same Nerd Font caps
# (U+E0B6/U+E0B4) window-status-current-format uses in tmux.conf — a cap's fg is the pill colour it
# terminates and its bg is the bar, which is what makes the join seamless. This pill used to be a
# flat #[…] block with no caps at all; a comment two sections up in tmux.conf claimed otherwise
# ("the session name in a rounded pill") but the glyphs it named were never actually typed into the
# string next to it — that comment described intent, not the code, until now.
#
# THE ACCENT SHOWS AN ICON, NOT THE INDEX. It used to hold the digit `prefix + <digit>` would land
# on, which was worth the space back when the strip listed every session and you could compare
# digits at a glance. With only the current session shown, a lone number has nothing to be compared
# against — so it is spent on a tmux glyph instead (, cod-terminal_tmux, U+EBC8, verified
# against Nerd Fonts' own glyphnames.json rather than guessed). `prefix + <digit>` still works
# exactly as before; it simply is not spelled out on the bar any more.
#
# WHY an option written by a hook instead of a format: tmux's #{S:…} session loop has no index
# variable, and more basically a format has no way to ask "which client is attached here" the way
# `tmux list-clients` below does. The other option, #(…) in status-right, would need
# status-interval > 0 to ever refresh (see §3b) — and this changes only when a session is created,
# renamed, killed or switched to, which is exactly what the hooks catch. Reading #{@…} is free.
#
# session-order.sh is NOT used here any more. It existed to answer "which position is the current
# session at", which only mattered while that position was drawn as a digit. Once the digit went,
# walking the whole ordered list just to re-find the session `cur` already names became a wasted
# subprocess and a wasted loop — `cur` was already valid, live output. `session-goto.sh` is the
# script's only remaining reader; see AGENTS.md.
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

if [ -n "$cur" ]; then
  esc=$(printf '%s' "$cur" | sed 's/#/##/g')
  # Two chips, the same shape as a window tab: the accent holds the icon, the name sits on a
  # neutral chip, and the caps take the colour of whichever chip they terminate — that hard edge
  # between the two fills is what stops the pill reading as one flat slab.
  strip=" #[fg=${PILL},bg=terminal]#[fg=${PINK},bg=${PILL},bold]  #[fg=${TEXT},bg=${CHIP},nobold] ${esc} #[fg=${CHIP},bg=terminal]#[default]"
else
  strip=''
fi

tmux set-option -g @session_strip "$strip "
