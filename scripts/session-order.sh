#!/bin/sh
# session-order.sh — print the live sessions in THE canonical order, one name per line.
#
# THIS IS THE ONLY DEFINITION OF THAT ORDER, the same way theme.sh is the only definition of the
# palette. Three things must agree or the config lies to you: the numbers on the status bar
# (session-strip.sh), the digits `prefix + <digit>` jumps to (session-goto.sh), and the rows in the
# Alt-s popup (session-menu.sh). They each used to run their own `list-sessions | sort`, which is
# three copies of a rule and one refactor away from drifting. They now all call this.
#
# The order:
#   1. `main` first, always. It is the session you come back to, so it gets the digit you never
#      have to look up.
#   2. Everything else by #{session_last_attached} descending — most recently used first.
#
# CONSEQUENCE, chosen deliberately: the digits are NOT stable. Switching sessions reorders the
# strip, because client-session-changed already re-renders it. In practice `prefix + 2` becomes an
# alt-tab between the two sessions you actually use, which is the point — but it does mean a digit
# is a position on the bar you are looking at, not a name you can memorise. The bar is always right
# because it is drawn from this same list.
#
# The field separator is a TAB: session names may contain spaces (rename-session allows them), and
# session-menu.sh already uses tab for the same reason. A name containing a literal tab would break
# this, as it already breaks the popup.
set -u

# `#{session_last_attached}` is a unix timestamp ("Time session last attached"). A session that has
# never been attached reports the EMPTY STRING, not 0 (measured — `sort -n` treats it as 0 either
# way, so it sorts last among the non-main entries, which is right). The empty field is also why
# `cut -f2-` is used rather than anything that assumes a width.
tmux list-sessions -F '#{session_last_attached}	#{session_name}' 2>/dev/null |
  sort -t'	' -k1,1nr |
  cut -f2- |
  awk '
    { lines[NR] = $0; if ($0 == "main") has_main = 1 }
    END {
      if (has_main) print "main"
      for (i = 1; i <= NR; i++) if (lines[i] != "main") print lines[i]
    }'
