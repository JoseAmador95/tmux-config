#!/bin/sh
# session-menu.sh — fzf-popup session manager (bound to M-s and to a click on the status-left
# session pill). Runs inside `display-popup -E`. fzf --disabled turns OFF type-to-filter, so
# EVERY key is a binding: 1..9 jump+switch, j/k (and arrows) move, g/G ends, r rename, n new,
# x kill, s classic tree, Enter switch, q/Esc quit. WHY fzf (not choose-tree/display-menu):
# choose-tree's keys are hardcoded (r=reverse-sort) and display-menu has no vi navigation; only
# fzf --disabled gives numbers + vim-motions + literal action keys together. Order = list | sort
# (same as the status bar and `prefix + <digit>`), so the popup numbers line up with those.
set -u
SELF="$HOME/.config/tmux/scripts/session-menu.sh"
. "$(cd "$(dirname "$0")" && pwd)/fzf-style.sh"   # --reverse + the shared vscode-modern --color

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

# interactive: build the fzf argument vector in $@ (POSIX has no arrays).
set -- $(fzf_style) \
  --no-sort --info=hidden --cycle --pointer '›' \
  --delimiter '\t' --with-nth 2 --prompt 'session ' \
  --header 'j/k move · 1-9 switch · r rename · n new · x kill · s tree · q quit' \
  --disabled \
  --bind 'j:down,k:up,g:first,G:last,ctrl-d:half-page-down,ctrl-u:half-page-up' \
  --bind 'enter:become(s={1}; tmux switch-client -t "=$s")' \
  --bind 's:become(tmux choose-tree -Zs)' \
  --bind 'q:abort,esc:abort' \
  --bind 'r:execute(s={1}; printf "rename %s -> " "$s"; IFS= read -r nn; [ -n "$nn" ] && tmux rename-session -t "=$s" -- "$nn")+reload(~/.config/tmux/scripts/session-menu.sh --list)' \
  --bind 'n:execute(printf "new session: "; IFS= read -r ns; [ -n "$ns" ] && tmux new-session -d -s "$ns")+reload(~/.config/tmux/scripts/session-menu.sh --list)' \
  --bind 'x:execute(s={1}; printf "kill %s? [y/N] " "$s"; read -r a; [ "$a" = y ] && tmux kill-session -t "=$s")+reload(~/.config/tmux/scripts/session-menu.sh --list)'

# number keys: pos(N) then switch to that row (jump + switch in one press).
n=1
while [ "$n" -le 9 ]; do
  set -- "$@" --bind "$n:pos($n)+become(s={1}; tmux switch-client -t \"=\$s\")"
  n=$((n + 1))
done

"$SELF" --list | fzf "$@"
