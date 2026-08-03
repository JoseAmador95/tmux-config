#!/bin/sh
# fzf-style.sh — the ONE definition of how every fzf popup in this config looks. It is *sourced*,
# not executed: session-menu.sh, palette.sh, keys.sh and ask.sh all pull their flags from here.
#
#   . "$(cd "$(dirname "$0")" && pwd)/fzf-style.sh"
#   set -- $(fzf_style) --prompt 'session '     # deliberately unquoted: see the contract below
#
# WHY a sourced helper instead of four --color strings: the palette moved from VSCode Light+
# (#007ACC) to Light/Dark Modern (#005FB8) and it was copy-pasted, byte for byte, in three scripts
# plus tmux.conf — one accent change meant five edits, and they had already drifted (different key
# order, lowercase vs uppercase hex). Now the popups follow the bar from a single place.
#
# CONTRACT: fzf_style() prints one flag per line and NONE of its words may contain a space, because
# every caller word-splits it (POSIX sh has no arrays — the same reason session-menu.sh builds its
# argv with `set --`). Anything with spaces (--prompt, --header) stays at the call site.
set -u

# vscode-modern palette — mirrors tmux.conf section 3. Keep the two in sync.
#   accent  #005FB8  selected row, prompt, pointer, border (white on it = 6.31:1, WCAG AA)
#   fg+     #FFFFFF  the selected row's text
#   dim     #8A8F98  inert text: header, and the query line while search is off
FZF_ACCENT='#005FB8'
FZF_FG_SEL='#FFFFFF'
FZF_DIM='#8A8F98'

fzf_style() {
  printf '%s\n' \
    --reverse \
    --color \
    "fg+:${FZF_FG_SEL},bg+:${FZF_ACCENT},prompt:${FZF_ACCENT},pointer:${FZF_ACCENT},header:${FZF_DIM},border:${FZF_ACCENT},disabled:${FZF_DIM},query:${FZF_ACCENT}"
}
