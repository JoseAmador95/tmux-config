#!/bin/sh
# session-menu.sh — fzf-popup session manager (bound to M-s and to a click on the session strip
# at the right end of the bar). Runs inside `display-popup -E`.
#
# TWO MODES, like vim. ACTION mode (the default, `fzf --no-input`) has NO input line at all, so every
# printable key is a binding: 1..9 jump+switch, j/k (and arrows) move, g/G ends, r rename, n new,
# x kill, s classic tree, Enter/double-click switch, q/Esc quit. `/` enters SEARCH mode, where the
# filter is on and letters type; Esc leaves it, clears the query and restores the action keys.
#
# WHY the modes at all: an fzf --bind ALWAYS beats character insertion, so with a keyboard full of
# literal action keys there is no room left to type. `enable-search` alone does NOT fix that -- `r`
# would still rename instead of typing an "r" -- so entering search must unbind() every action key
# and leaving it must rebind() them. That unbind/rebind pair is junegunn's own documented "Vim-like
# mode switch" (fzf CHANGELOG 0.59.0).
#
# WHY --no-input AND NOT --disabled, which is what this used to be. --disabled turns the MATCHER
# off but keeps the input line, so a key that happens not to be bound -- b, e, t, h... -- is still
# swallowed into the query and echoed in the prompt. The list never filtered, but the prompt read
# "session hello" while you typed, which looks exactly like a search that is not working.
# --no-input removes the input line outright: in action mode an unbound key now does nothing and
# shows nothing. `/` calls show-input to bring it back, Esc calls hide-input to put it away.
#
# WHY fzf (not choose-tree/display-menu): choose-tree's keys are hardcoded (r=reverse-sort) and
# display-menu has no vi navigation; only fzf gives numbers + vim-motions + literal action keys
# together. Order = list | sort (same as the status bar and `prefix + <digit>`), so the popup
# numbers line up with those.
#
# Esc has to know which mode it is in, and that comes from $FZF_INPUT_STATE (fzf >= 0.59). On an
# older fzf the variable is empty and Esc simply aborts: degraded, never broken.
#
# DEAD END -- clicking outside the popup cannot close it. tmux's popup_key_cb returns 0 ("keep
# open") for out-of-bounds mouse events in every version from 3.4 to master AND swallows the click,
# so fzf never receives it; `--no-mouse` changes nothing. The native way out is a RIGHT-press
# outside, which opens tmux's own popup menu with a Close entry (tmux >= 3.3) — and it is a
# GESTURE, not a click: press, drag onto Close, release. A right press-and-release in place just
# dismisses the menu again and leaves the popup up. The header says "right-drag" for that reason.
set -u
SELF=$(cd "$(dirname "$0")" && pwd)/$(basename "$0")   # reload() needs an absolute path
. "$(dirname "$SELF")/fzf-style.sh"                    # --reverse + the shared --color, from the theme

ASK="$(dirname "$SELF")/ask.sh"

# Sub-commands. --list feeds fzf; the other three are what the r/n/x keys run through execute(),
# kept here rather than inlined in the --bind strings so that the quoting stays readable and the
# cancel path (ask.sh exits non-zero) can be handled with a plain `|| exit 0`.
case "${1:-}" in
  --list)
    # "rawname<TAB>pretty" (numbered, current marked with a bullet). Field 1 = raw name, which is
    # what the actions target; field 2 = the pretty column fzf shows (--with-nth 2).
    cur=$(tmux display-message -p '#S' 2>/dev/null)
    i=0
    tmux list-sessions -F '#{session_name}' 2>/dev/null | sort | while IFS= read -r s; do
      i=$((i + 1))
      if [ "$s" = "$cur" ]; then mark="▸"; else mark=" "; fi
      printf '%s\t%s %2d  %s\n' "$s" "$mark" "$i" "$s"
    done
    exit 0 ;;

  --rename)
    s="${2:-}"; [ -n "$s" ] || exit 0
    new=$("$ASK" "rename ${s} to" "$s") || exit 0
    [ "$new" = "$s" ] && exit 0
    tmux rename-session -t "=$s" -- "$new"
    exit 0 ;;

  --new)
    name=$("$ASK" 'new session') || exit 0
    tmux new-session -d -s "$name"
    exit 0 ;;

  --kill)
    s="${2:-}"; [ -n "$s" ] || exit 0
    "$ASK" --confirm "kill ${s}?" || exit 0
    tmux kill-session -t "=$s"
    exit 0 ;;
esac

# Every key that means "do something" in action mode. `/` is in the list too: once search is on it
# must type a slash like any other character. Kept as one comma-separated string because that is
# exactly the argument shape unbind()/rebind() want.
# The `/` bind still clear-query's even though --no-input means nothing can land in the query any
# more: it costs nothing and it keeps the leftover from a previous search out of the next one.
ACTIONS='j,k,g,G,r,n,x,s,q,1,2,3,4,5,6,7,8,9,/'

HDR_ACTION='/ search · j/k move · 1-9 switch · r rename · n new · x kill · s tree · q quit · right-drag outside for Close'
HDR_SEARCH='type to filter · Enter switch · Esc back to the action keys'

# Esc: leave search mode if we are in it, otherwise close the popup. `transform` runs a command
# whose stdout is a list of fzf actions, which is the only way to make one key mean two things.
# ${FZF_INPUT_STATE:-} and a POSIX `case` (not the bash [[ ]] of the upstream example) keep this
# working under /bin/sh, and make an older fzf fall back to plain abort.
# The trailing reload() is NOT decoration: neither clear-query nor disable-search re-runs the
# matcher (tested on fzf 0.74.2 -- the rows stayed filtered to the last query in both orders), so
# without it Esc would drop you back into action mode still looking at a filtered list, with the
# digit keys pointing at the wrong sessions. Rebuilding the list is also the cheapest way to pick
# up sessions created or killed while you were searching.
BACK="clear-query+disable-search+hide-input+rebind(${ACTIONS})+change-prompt(session )+change-header(${HDR_ACTION})+reload(${SELF} --list)"
ESC="esc:transform:case \"\${FZF_INPUT_STATE:-}\" in enabled) printf '%s' '${BACK}' ;; *) printf '%s' 'abort' ;; esac"

# Switching is the same action from three inputs, so it is written once.
SWITCH='become(s={1}; tmux switch-client -t "=$s")'

# interactive: build the fzf argument vector in $@ (POSIX has no arrays).
set -- $(fzf_style) \
  --no-sort --info=hidden --cycle --pointer '›' \
  --delimiter '\t' --with-nth 2 --prompt 'session ' \
  --header "${HDR_ACTION}" \
  --no-input \
  --bind 'ctrl-j:down,ctrl-k:up,ctrl-d:half-page-down,ctrl-u:half-page-up' \
  --bind 'j:down,k:up,g:first,G:last' \
  --bind "enter:${SWITCH}" \
  --bind "double-click:${SWITCH}" \
  --bind 's:become(tmux choose-tree -Zs)' \
  --bind 'q:abort' \
  --bind "/:clear-query+show-input+enable-search+unbind(${ACTIONS})+change-prompt(/ )+change-header(${HDR_SEARCH})" \
  --bind "${ESC}" \
  --bind "r:execute(${SELF} --rename {1})+reload(${SELF} --list)" \
  --bind "n:execute(${SELF} --new)+reload(${SELF} --list)" \
  --bind "x:execute(${SELF} --kill {1})+reload(${SELF} --list)"

# number keys: pos(N) then switch to that row (jump + switch in one press). These stay in sync with
# the printed column because digits are unbound while searching and Esc clears the query, so pos(N)
# is only ever evaluated against the full, unfiltered list.
n=1
while [ "$n" -le 9 ]; do
  set -- "$@" --bind "${n}:pos(${n})+${SWITCH}"
  n=$((n + 1))
done

"$SELF" --list | fzf "$@"
