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
# Order is `list-sessions | sort`, the same order session-goto.sh and session-menu.sh use, so the
# digit on screen, the digit you press and the row in the popup are always the same session.
#
# Only the first 9 are rendered: `prefix + <digit>` cannot reach a tenth, so a longer strip would
# be advertising jumps that do not exist.
#
# Session names are UNTRUSTED here — they are whatever the user typed. status-right expands this
# option with #{E:…}, so every "#" in a name is doubled: without that, a session called
# "#[bg=red]" would inject a style into the bar and "#{session_name}" would be expanded. Our own
# #[…] markup is added after the escaping, so it still works.
set -u

ACCENT='#005FB8'
DIM='#8A8F98'

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
  tmux list-sessions -F '#{session_name}' 2>/dev/null | sort | {
    i=0
    acc=''
    while IFS= read -r s; do
      i=$((i + 1))
      [ "$i" -le 9 ] || break
      esc=$(printf '%s' "$s" | sed 's/#/##/g')
      if [ "$s" = "$cur" ]; then
        # The session you are ON is already named in the status-left pill, so the strip shows only
        # its NUMBER — repeating the name put it on screen twice. A mini pill rather than a bare
        # bold digit: among named entries a naked "3" reads as a session called 3, whereas an
        # accent pill is already this bar's word for "this is the current one".
        acc="${acc} #[fg=${ACCENT},bg=terminal]#[fg=#FFFFFF,bg=${ACCENT},bold]${i}#[fg=${ACCENT},bg=terminal]#[default]"
      else
        acc="${acc}#[fg=${DIM},nobold] ${i} ${esc}"
      fi
    done
    printf '%s' "$acc"
  }
)

tmux set-option -g @session_strip "$strip "
