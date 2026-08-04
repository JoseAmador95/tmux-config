#!/bin/sh
# session-save.sh — write down which sessions exist and where they are rooted, so a reboot does not
# lose them. Driven by the same session hooks the status bar already uses; costs one file write on
# an event a human triggers by hand. `t` replays it (shell/functions.sh).
#
# WHAT IT SAVES: name, directory, and the window names. That is all, and it is deliberate — the
# window names are not for rebuilding windows, they are a SIGNATURE: "agent editor git term" means
# the session came from `tp`, so the restore can rebuild it through sessions/dev.conf instead of
# handing back a bare shell where four tool windows used to be.
#
# WHY NOT tmux-resurrect. Resurrect is ~1500 lines because it tries to rebuild *anything*: pane
# geometry via #{window_layout}, plus a `ps`-based stack for guessing argv (pane_current_command
# gives you "ruby", not "rails server"), plus a process whitelist, plus an @resurrect-processes
# ':all:' escape hatch its own docs warn can re-run `sudo mkfs`. None of that machinery earns its
# keep HERE, because these sessions are reproducible by construction: `tp <dir>` rebuilds a dev
# session deterministically and `tssh <host>` rebuilds a remote one. What a reboot actually
# destroys is only *which projects and hosts I had open* — which is a name and a path.
#
# WHY NOT tmux-continuum for the timing. Continuum triggers its save by appending to status-right
# and leaning on the status redraw, so it needs status-interval > 0 and an unmodified status-right.
# This config sets status-interval 0 on purpose and builds status-right by hand — continuum's own
# README calls out theme-owned status-right as the thing that breaks it. Hooks are both available
# and more correct than a 15-minute timer.
set -u

state="${XDG_STATE_HOME:-$HOME/.local/state}/tmux"
roster="$state/roster"

mkdir -p "$state" 2>/dev/null || exit 0

# Write via a temp file and rename, so a roster is never half-written when a reboot lands on it.
tmp="$roster.$$"
# #{W:…} takes TWO bodies — the second is used for the CURRENT window. Passing only one silently
# drops the current window from the list and emits no separators, which makes the signature wrong
# for exactly the session you are looking at.
tmux list-sessions -F '#{session_name}	#{session_path}	#{W:#{window_name} ,#{window_name} }' \
  2>/dev/null > "$tmp" || { rm -f "$tmp"; exit 0; }

# An empty list means the server is going away; keep the last good roster rather than blanking it,
# otherwise the final session-closed on shutdown would erase exactly what we are trying to keep.
if [ -s "$tmp" ]; then
  mv -f "$tmp" "$roster"
else
  rm -f "$tmp"
fi
