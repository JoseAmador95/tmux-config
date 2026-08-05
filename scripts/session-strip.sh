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
# THE ACCENT SHOWS AN ICON, NOT THE INDEX. It used to hold the digit a numbered `prefix +
# <digit>` jump would land on, which was worth the space back when the strip listed every
# session and you could compare digits at a glance. With only the current session shown, a lone
# number had nothing left to be compared against — so it was spent on a tmux glyph instead
# (, cod-terminal_tmux, U+EBC8, verified against Nerd Fonts' own glyphnames.json rather
# than guessed). The numbered jump itself is gone now too — see tmux.conf's §2b comment for why
# — so there is no digit this icon could show even if it wanted to.
#
# WHY an option written by a hook instead of a format: tmux's #{S:…} session loop has no index
# variable, and more basically a format has no way to ask "which client is attached here" the way
# `tmux list-clients` below does. The other option, #(…) in status-right, would need
# status-interval > 0 to ever refresh (see §3b) — and this changes only when a session is created,
# renamed, killed or switched to, which is exactly what the hooks catch. Reading #{@…} is free.
#
# There is no session-order.sh any more. It used to answer "which position is the current session
# at" for two readers: this script (to draw the digit) and the `prefix + <digit>` jump it fed. Once
# this script stopped drawing a digit, walking that list just to re-find the session `cur` already
# names became a wasted subprocess and a wasted loop — `cur` was already valid, live output — and
# once `prefix + <digit>` was removed outright there was no reader left at all, so the file went
# with it rather than staying as unused ceremony. See tmux.conf's §2b comment and AGENTS.md.
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
