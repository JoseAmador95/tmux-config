#!/bin/sh
# session-menu.sh — fzf-popup session manager (bound to M-s and to a click on the status-left
# session pill). Runs inside `display-popup -E`.
#
# TWO MODES, like vim. ACTION mode (the default, `fzf --disabled`) has type-to-filter OFF, so every
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
# so fzf never receives it; `--no-mouse` changes nothing. The native way out is a RIGHT-click
# outside, which opens tmux's own popup menu with a Close entry (tmux >= 3.3). The header says so.
set -u
SELF=$(cd "$(dirname "$0")" && pwd)/$(basename "$0")   # reload() needs an absolute path
. "$(dirname "$SELF")/fzf-style.sh"                    # --reverse + the shared vscode-modern --color

# --list: emit "rawname<TAB>pretty" lines (numbered, current marked with a bullet). Used for the
# initial feed and by fzf's reload() after r/n/x. Field 1 = raw name (what actions target);
# field 2 = the pretty column fzf shows (--with-nth 2).
if [ "${1:-}" = "--list" ]; then
  cur=$(tmux display-message -p '#S' 2>/dev/null)
  i=0
  tmux list-sessions -F '#{session_name}' 2>/dev/null | sort | while IFS= read -r s; do
    i=$((i + 1))
    if [ "$s" = "$cur" ]; then mark="▸"; else mark=" "; fi
    printf '%s\t%s %2d  %s\n' "$s" "$mark" "$i" "$s"
  done
  exit 0
fi

# Every key that means "do something" in action mode. `/` is in the list too: once search is on it
# must type a slash like any other character. Kept as one comma-separated string because that is
# exactly the argument shape unbind()/rebind() want.
ACTIONS='j,k,g,G,r,n,x,s,q,1,2,3,4,5,6,7,8,9,/'

HDR_ACTION='/ search · j/k move · 1-9 switch · r rename · n new · x kill · s tree · q quit · right-click outside to close'
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
BACK="clear-query+disable-search+rebind(${ACTIONS})+change-prompt(session )+change-header(${HDR_ACTION})+reload(${SELF} --list)"
ESC="esc:transform:case \"\${FZF_INPUT_STATE:-}\" in enabled) printf '%s' '${BACK}' ;; *) printf '%s' 'abort' ;; esac"

# Switching is the same action from three inputs, so it is written once.
SWITCH='become(s={1}; tmux switch-client -t "=$s")'

# interactive: build the fzf argument vector in $@ (POSIX has no arrays).
set -- $(fzf_style) \
  --no-sort --info=hidden --cycle --pointer '›' \
  --delimiter '\t' --with-nth 2 --prompt 'session ' \
  --header "${HDR_ACTION}" \
  --disabled \
  --bind 'ctrl-j:down,ctrl-k:up,ctrl-d:half-page-down,ctrl-u:half-page-up' \
  --bind 'j:down,k:up,g:first,G:last' \
  --bind "enter:${SWITCH}" \
  --bind "double-click:${SWITCH}" \
  --bind 's:become(tmux choose-tree -Zs)' \
  --bind 'q:abort' \
  --bind "/:enable-search+unbind(${ACTIONS})+change-prompt(/ )+change-header(${HDR_SEARCH})" \
  --bind "${ESC}" \
  --bind "r:execute(s={1}; printf \"rename %s -> \" \"\$s\"; IFS= read -r nn; [ -n \"\$nn\" ] && tmux rename-session -t \"=\$s\" -- \"\$nn\")+reload(${SELF} --list)" \
  --bind "n:execute(printf \"new session: \"; IFS= read -r ns; [ -n \"\$ns\" ] && tmux new-session -d -s \"\$ns\")+reload(${SELF} --list)" \
  --bind "x:execute(s={1}; printf \"kill %s? [y/N] \" \"\$s\"; read -r a; [ \"\$a\" = y ] && tmux kill-session -t \"=\$s\")+reload(${SELF} --list)"

# number keys: pos(N) then switch to that row (jump + switch in one press). These stay in sync with
# the printed column because digits are unbound while searching and Esc clears the query, so pos(N)
# is only ever evaluated against the full, unfiltered list.
n=1
while [ "$n" -le 9 ]; do
  set -- "$@" --bind "${n}:pos(${n})+${SWITCH}"
  n=$((n + 1))
done

"$SELF" --list | fzf "$@"
