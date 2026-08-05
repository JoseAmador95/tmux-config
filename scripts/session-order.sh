#!/bin/sh
# session-order.sh — print the live sessions in THE canonical order, one name per line.
#
# THIS IS THE ONLY DEFINITION OF THAT ORDER, the same way theme.sh is the only definition of the
# palette. Originally three consumers had to agree on it or the config would lie to you about which
# digit went where; they each used to run their own `list-sessions | sort`, which is three copies of
# a rule and one refactor away from drifting, so they were made to call this instead.
#
# ONE CONSUMER IS LEFT: `session-goto.sh`, which is what `prefix + <digit>` runs. The other two are
# gone, not just refactored away from this file:
#   - the status bar (session-strip.sh) rendered every session's digit, then round 8 cut that down
#     to one pill for the CURRENT session, which made walking this list pointless — the pill already
#     knows which session it is without asking where it ranks — and a later round replaced even that
#     pill's digit with an icon. The bar does not read this file any more.
#   - the Alt-s popup was replaced in round 8 by tmux's own `choose-tree`, which has its own `-O`
#     sort (activity/creation/index/key/modifier/name/order/size/z — verified against tmux's source;
#     it does NOT include a "last attached" option) and cannot be pointed at this rule at all. Its
#     numbering and `prefix + <digit>` can disagree beyond the first entry; see AGENTS.md.
#
# The order:
#   1. `main` first, always. It is the session you come back to, so it gets the digit you never
#      have to look up.
#   2. Everything else by #{session_last_attached} descending — most recently used first.
#
# CONSEQUENCE, chosen deliberately: the digits are NOT stable. `prefix + 2` becomes an alt-tab
# between the two sessions you actually use most, which is the point — but a digit is not a name
# you can memorise, and with the bar showing none of them any more, `prefix + <digit>` is something
# you either remember or go check in the `Alt-s` tree (whose own numbers are a different order).
#
# The field separator is a TAB: session names may contain spaces (rename-session allows them). A
# name containing a literal tab would break this.
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
