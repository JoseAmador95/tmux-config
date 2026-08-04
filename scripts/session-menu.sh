#!/bin/sh
# session-menu.sh — fzf-popup session manager (bound to M-s and to a click on the session strip
# at the right end of the bar). Runs inside `display-popup -E`.
#
# TWO MODES, like vim, and it OPENS IN INSERT. You start typing immediately and the list filters;
# nothing you type can fire an action. `jj` or `kk` leaves for NORMAL mode, exactly the way the
# same keys leave insert in nvim, and there every letter is a command: 1..9 jump+switch, j/k move,
# g/G ends, r rename, n new, x kill, s classic tree, q quit. `i` or `/` goes back to typing.
# Esc always means one level back: insert -> normal, normal -> close.
#
# WHY THIS WAY ROUND. Round 1's complaint was that typing r/x/n/s fired actions instead of
# filtering. That was first fixed by making ACTION mode the default and putting search behind `/`.
# Opening in insert fixes the same complaint from the other side and is what the muscle memory
# already expects: typing is always safe, and you leave deliberately. The destructive keys stay
# NORMAL-ONLY for that reason — `x` must not be reachable while typing.
#
# WHY THE MODES ARE NEEDED AT ALL: an fzf --bind ALWAYS beats character insertion, so with a
# keyboard full of literal action keys there is no room left to type. `enable-search` alone does not
# fix it — `r` would still rename instead of typing an "r" — so insert mode must unbind() every
# action key and leaving it must rebind() them. That unbind/rebind pair is junegunn's own
# documented "Vim-like mode switch" (fzf CHANGELOG 0.59.0).
#
# WHY NORMAL MODE USES hide-input AND NOT --disabled. --disabled turns the MATCHER off but keeps the
# input line, so a key that happens not to be bound — b, e, t, h... — is still swallowed into the
# query and echoed in the prompt. The list would not filter, but the prompt would read
# "session hello" as you typed, which looks exactly like a search that is not working. hide-input
# removes the line outright: in normal mode an unbound key does nothing and shows nothing.
#
# WHY fzf (not choose-tree/display-menu): choose-tree's keys are hardcoded (r=reverse-sort) and
# display-menu has no vi navigation; only fzf gives numbers + vim-motions + literal action keys
# together. Order comes from session-order.sh — the same list the status bar and `prefix + <digit>`
# use — so the popup numbers line up with those.
#
# Both mode switches need to know which mode they are in, and that comes from $FZF_INPUT_STATE
# (fzf >= 0.59). On an older fzf the variable is empty: Esc simply aborts and j/k simply move,
# degraded but never broken.
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

# --- the two modes -------------------------------------------------------------------------------
# Every key that means "do something" in normal mode, and therefore every key that must be UNBOUND
# while typing. One comma-separated string because that is exactly the argument shape unbind() and
# rebind() want.
#
# `i` and `/` are in the list: they enter insert mode, so in insert mode they must type like any
# other character. `j` and `k` are deliberately NOT — see --mode-key below.
ACTIONS='g,G,r,n,x,s,q,i,1,2,3,4,5,6,7,8,9,/'

HDR_NORMAL='NORMAL · i or / to filter · j/k move · 1-9 switch · r rename · n new · x kill · s tree · q quit · right-drag outside for Close'
HDR_INSERT='INSERT · type to filter · jj or kk for normal mode · Enter switch · Esc back'

# to NORMAL. The trailing reload() is NOT decoration: neither clear-query nor disable-search re-runs
# the matcher (tested on fzf 0.74.2 — the rows stayed filtered to the last query in both orders), so
# without it you would land in normal mode still looking at a filtered list, with the digit keys
# pointing at the wrong sessions. Rebuilding is also the cheapest way to pick up sessions created or
# killed while you were typing.
TO_NORMAL="clear-query+disable-search+hide-input+rebind(${ACTIONS})+change-prompt(session )+change-header(${HDR_NORMAL})+reload(${SELF} --list)"
# to INSERT. show-input comes BEFORE clear-query, and the order is load-bearing: with the input
# hidden, clear-query does nothing, so `clear-query+show-input` reveals whatever was in the query
# when normal mode was entered. Measured — after `jj` the query still held the first `j`, and
# pressing `i` re-enabled search against it, leaving the list EMPTY because no session matches "j".
TO_INSERT="show-input+clear-query+enable-search+unbind(${ACTIONS})+change-prompt(search )+change-header(${HDR_INSERT})"

# Sub-commands. --list feeds fzf; --rename/--new/--kill are what r/n/x run through execute();
# --mode-key is the j/k decision. All are kept here rather than inlined in the --bind strings so
# that the quoting stays readable and the cancel path (ask.sh exits non-zero) can be handled with a
# plain `|| exit 0`.
case "${1:-}" in
  --list)
    # "rawname<TAB>pretty" (numbered, current marked with a bullet). Field 1 = raw name, which is
    # what the actions target; field 2 = the pretty column fzf shows (--with-nth 2).
    cur=$(tmux display-message -p '#S' 2>/dev/null)
    i=0
    "$(dirname "$SELF")/session-order.sh" 2>/dev/null | while IFS= read -r s; do
      i=$((i + 1))
      if [ "$s" = "$cur" ]; then mark="▸"; else mark=" "; fi
      printf '%s\t%s %2d  %s\n' "$s" "$mark" "$i" "$s"
    done
    exit 0 ;;

  --mode-key)
    # THE jj/kk MAPPING. fzf has no multi-key sequences, so a two-key gesture has to be built from
    # one key plus the state it can see. fzf exports $FZF_INPUT_STATE and $FZF_QUERY to a transform
    # child, and a transform's stdout is a list of fzf actions — so this prints what `j` (or `k`)
    # should mean right now:
    #
    #   normal mode                        -> move the cursor
    #   insert mode, query already ends j  -> that is the second j: switch to normal
    #   insert mode, anything else         -> `put`, which inserts the TRIGGERING character
    #
    # `put` has to be explicit because binding a key at all removes its default insertion. The
    # stray first `j` left in the query does not need removing: TO_NORMAL clear-query's anyway.
    #
    # NO TIMEOUT, unlike vim. vim's `jj` depends on timeoutlen, so a slow j...j inserts two of them;
    # here the second `j` always switches, however long you waited. The consequence is that a query
    # can never contain "jj" — a session named with a double j is unreachable BY SEARCH, though
    # j/k and the digits still reach it in normal mode.
    key="${2:-j}"
    case "${FZF_INPUT_STATE:-}" in
      enabled)
        case "${FZF_QUERY:-}" in
          *"$key") printf '%s' "$TO_NORMAL" ;;
          *)       printf '%s' 'put' ;;
        esac ;;
      # Not enabled means normal mode — and also an fzf too old to export the variable, where
      # moving the cursor is the right fallback.
      *) [ "$key" = "k" ] && printf '%s' 'up' || printf '%s' 'down' ;;
    esac
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

# Esc: leave insert mode if we are in it, otherwise close the popup — so Esc always means one level
# back. `transform` runs a command whose stdout is a list of fzf actions, which is the only way to
# make one key mean two things. ${FZF_INPUT_STATE:-} and a POSIX `case` (not the bash [[ ]] of the
# upstream example) keep this working under /bin/sh, and make an older fzf fall back to plain abort.
ESC="esc:transform:case \"\${FZF_INPUT_STATE:-}\" in enabled) printf '%s' '${TO_NORMAL}' ;; *) printf '%s' 'abort' ;; esac"

# Switching is the same action from three inputs, so it is written once.
SWITCH='become(s={1}; tmux switch-client -t "=$s")'

# interactive: build the fzf argument vector in $@ (POSIX has no arrays).
#
# `start:unbind(...)` is what makes INSERT the opening mode. The action keys have to be declared
# with --bind and then unbound, because rebind() only restores bindings that were unbound — it
# cannot invent one. So they are all bound normally below and switched off the moment fzf starts.
set -- $(fzf_style) \
  --no-sort --info=hidden --cycle --pointer '›' \
  --delimiter '\t' --with-nth 2 --prompt 'search ' \
  --header "${HDR_INSERT}" \
  --bind "start:unbind(${ACTIONS})" \
  --bind 'ctrl-j:down,ctrl-k:up,ctrl-d:half-page-down,ctrl-u:half-page-up' \
  --bind "j:transform:${SELF} --mode-key j" \
  --bind "k:transform:${SELF} --mode-key k" \
  --bind 'g:first,G:last' \
  --bind "enter:${SWITCH}" \
  --bind "double-click:${SWITCH}" \
  --bind 's:become(tmux choose-tree -Zs)' \
  --bind 'q:abort' \
  --bind "i:${TO_INSERT}" \
  --bind "/:${TO_INSERT}" \
  --bind "${ESC}" \
  --bind "r:execute(${SELF} --rename {1})+reload(${SELF} --list)" \
  --bind "n:execute(${SELF} --new)+reload(${SELF} --list)" \
  --bind "x:execute(${SELF} --kill {1})+reload(${SELF} --list)"

# number keys: pos(N) then switch to that row (jump + switch in one press). These stay in sync with
# the printed column because digits are unbound while typing and every mode switch clears the query
# and reloads, so pos(N) is only ever evaluated against the full, unfiltered list.
n=1
while [ "$n" -le 9 ]; do
  set -- "$@" --bind "${n}:pos(${n})+${SWITCH}"
  n=$((n + 1))
done

"$SELF" --list | fzf "$@"
