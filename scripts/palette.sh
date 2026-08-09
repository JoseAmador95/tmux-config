#!/bin/sh
# palette.sh — command palette (fzf popup, bound to M-Space). Type to filter; Enter runs the
# chosen action. Field 1 = tmux command (curated → `eval tmux …`), or a raw shell command if
# prefixed with `!` (runs in-place inside this same popup pane instead — for anything that isn't
# a tmux command, like paging a file). Review is the one exception: exit 42 asks
# palette-popup.sh to close this popup and open the dedicated 95% review surface. Field 2 is the
# label fzf shows and filters (--with-nth 2). Fills the gap documented in README/AGENTS/bootstrap
# ("Alt-Space command palette").
set -u
# shellcheck source=scripts/fzf-style.sh
. "$(cd "$(dirname "$0")" && pwd)/fzf-style.sh"   # --reverse + the shared --color, from the theme

# The popup's TMUX_PANE is a transient pane that cannot be targeted like a
# normal window pane. Preserve the physical cwd inherited from the source pane
# before fzf runs so review actions keep the correct repository.
TMUX_PALETTE_SOURCE_PATH=$(pwd -P) || exit 1
export TMUX_PALETTE_SOURCE_PATH

items() {   # "tmux command<TAB>label" (printf recycles the format per pair)
  printf '%s\t%s\n' \
    'run-shell "~/.config/tmux/scripts/split.sh '\''#{pane_id}'\'' vertical"'   'split down' \
    'run-shell "~/.config/tmux/scripts/split.sh '\''#{pane_id}'\'' horizontal"' 'split right' \
    'new-window -c "#{pane_current_path}"'                      'new window' \
    'resize-pane -Z'                                            'zoom pane (toggle)' \
    'respawn-pane'                                              'revive pane (respawn)' \
    'command-prompt -I "#W" { rename-window "%%" }'            'rename window' \
    'command-prompt -I "#S" { rename-session "%%" }'           'rename session' \
    'command-prompt -p "new session:" { new-session -s "%%" }' 'new session' \
    'choose-tree -Zs'                                           'choose session (tree)' \
    'confirm-before -p "kill pane? (y/n)" kill-pane'           'kill pane' \
    'confirm-before -p "kill window? (y/n)" kill-window'       'kill window' \
    'copy-mode'                                                 'copy-mode (scroll/search)' \
    'clock-mode'                                                'clock' \
    'detach-client'                                            'detach' \
    'source-file ~/.config/tmux/tmux.conf'                     'reload config' \
    '!~/.config/tmux/scripts/tuicr-review.sh'                  'review current repository (tuicr)' \
    '!less ~/.config/tmux/README.md'                           'show documentation (README)' \
    'set -g @thm_flavor latte     \; run-shell "~/.config/tmux/scripts/theme.sh"'     'theme: latte (light)' \
    'set -g @thm_flavor frappe    \; run-shell "~/.config/tmux/scripts/theme.sh"'     'theme: frappe' \
    'set -g @thm_flavor macchiato \; run-shell "~/.config/tmux/scripts/theme.sh"'     'theme: macchiato' \
    'set -g @thm_flavor mocha     \; run-shell "~/.config/tmux/scripts/theme.sh"'     'theme: mocha (dark)'
}

# Let fzf exit and restore the popup terminal before starting an interactive
# command. `become(...)` leaves a second tmux client alive but invisible inside
# display-popup even though its private pane is rendering normally.
# fzf_style's contract intentionally word-splits.
# shellcheck disable=SC2046
selection=$(items | fzf $(fzf_style) \
  --delimiter '\t' --with-nth 2 --info=inline --cycle \
  --prompt '> ' --header 'filter · Enter runs · Esc cancels') || exit $?

tab=$(printf '\t')
command=${selection%%"$tab"*}
[ "$command" != "$selection" ] || exit 1
case "$command" in
  '!~/.config/tmux/scripts/tuicr-review.sh') exit 42 ;;
  "!"*) eval "${command#?}" ;;
  *) eval tmux "$command" ;;
esac
