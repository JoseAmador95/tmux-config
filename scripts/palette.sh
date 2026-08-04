#!/bin/sh
# palette.sh — command palette (fzf popup, bound to M-Space). Type to filter; Enter runs the
# chosen action. Field 1 = tmux command (curated → `eval tmux …`); field 2 = the label fzf shows
# and filters (--with-nth 2). Runs inside display-popup -E; the popup closes on run. Fills the
# gap documented in README/AGENTS/bootstrap ("Alt-Space command palette").
set -u
. "$(cd "$(dirname "$0")" && pwd)/fzf-style.sh"   # --reverse + the shared --color, from the theme

items() {   # "tmux command<TAB>label" (printf recycles the format per pair)
  printf '%s\t%s\n' \
    'split-window -v -c "#{pane_current_path}"'                 'split down' \
    'split-window -h -c "#{pane_current_path}"'                 'split right' \
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
    'set -g @thm_flavor latte     \; run-shell "~/.config/tmux/scripts/theme.sh"'     'theme: latte (light)' \
    'set -g @thm_flavor frappe    \; run-shell "~/.config/tmux/scripts/theme.sh"'     'theme: frappe' \
    'set -g @thm_flavor macchiato \; run-shell "~/.config/tmux/scripts/theme.sh"'     'theme: macchiato' \
    'set -g @thm_flavor mocha     \; run-shell "~/.config/tmux/scripts/theme.sh"'     'theme: mocha (dark)'
}

items | fzf $(fzf_style) \
  --delimiter '\t' --with-nth 2 --info=inline --cycle \
  --prompt '> ' --header 'filter · Enter runs · Esc cancels' \
  --bind 'enter:become(c={1}; eval tmux "$c")'
