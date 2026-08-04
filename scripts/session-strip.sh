#!/bin/sh
# session-strip.sh — render the numbered session list into the @session_strip user option, which
# status-right reads back with #{E:@session_strip}. Driven by the session hooks in tmux.conf.
#
# WHY an option written by a hook instead of a format: tmux's #{S:…} session loop has no index
# variable, so the NUMBERS cannot be produced by a format at all — and those numbers are the whole
# point, because they are what `prefix + <digit>` (session-goto.sh) and the Alt-s popup jump to.
# The other option, #(…) in status-right, would fork a process on every redraw for a list that only
# changes when a session is created, renamed, killed or switched to. Reading #{@…} is free.
#
# Order comes from session-order.sh — `main` first, then most recently used — and NOTHING here
# sorts. session-goto.sh and session-menu.sh call the same script, which is what makes the digit on
# screen, the digit you press and the row in the popup the same session. It used to be three
# separate `| sort` calls; that is three copies of a rule and one edit away from drifting.
#
# Because the order is by recent use, the digits MOVE as you switch sessions — this script is
# re-run by the client-session-changed hook, so the bar is always right, but a digit is a position
# you are looking at rather than a name you can memorise.
#
# Only the first 9 are rendered: `prefix + <digit>` cannot reach a tenth, so a longer strip would
# be advertising jumps that do not exist.
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
DIM=$(thm  dim  '#6c6f85')
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

# The while loop must not run in a subshell of this script's main body, or the accumulator would be
# lost; keeping the whole pipeline inside one command substitution is the POSIX way to do that.
strip=$(
  "$(cd "$(dirname "$0")" && pwd)/session-order.sh" 2>/dev/null | {
    i=0
    acc=''
    while IFS= read -r s; do
      i=$((i + 1))
      [ "$i" -le 9 ] || break
      esc=$(printf '%s' "$s" | sed 's/#/##/g')
      if [ "$s" = "$cur" ]; then
        # The current session is NAMED here again. It used to be a bare number, because the pill on
        # the left carried the name and having it twice was the complaint; the left pill is now
        # ssh-only, so this is the one place the name lives. Same two-chip shape as a window tab —
        # coloured index, neutral name — so the bar has ONE pill vocabulary rather than three.
        acc="${acc} #[fg=${PILL},bg=terminal]#[fg=${PINK},bg=${PILL},bold]${i}#[fg=${TEXT},bg=${CHIP},nobold] ${esc} #[fg=${CHIP},bg=terminal]#[default]"
      else
        acc="${acc}#[fg=${DIM},nobold] ${i} ${esc}"
      fi
    done
    printf '%s' "$acc"
  }
)

tmux set-option -g @session_strip "$strip "
