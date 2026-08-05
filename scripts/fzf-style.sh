#!/bin/sh
# fzf-style.sh — the ONE definition of how every fzf popup in this config looks. It is *sourced*,
# not executed: palette.sh, keys.sh, urls.sh and ask.sh all pull their flags from here.
#
#   . "$(cd "$(dirname "$0")" && pwd)/fzf-style.sh"
#   set -- $(fzf_style) --prompt 'session '     # deliberately unquoted: see the contract below
#
# The colours are NOT written here. They come from the @thm_* theme block in tmux.conf, the single
# place the palette lives — every popup runs inside `display-popup`, so tmux is always there to ask.
# Hardcoding them is what this file was created to stop: the accent had been rewritten three times
# and each rewrite meant editing four files. The literals below are only a fallback for a popup
# somehow launched outside tmux, and they are the Catppuccin Latte values the theme block ships.
#
# CONTRACT: fzf_style() prints one flag per line and NONE of its words may contain a space, because
# every caller word-splits it (POSIX sh has no arrays — the same reason the popup scripts build their
# argv with `set --`). Anything with spaces (--prompt, --header) stays at the call site.
set -u

# One tmux round-trip per role, at popup-open time only. #{E:…} resolves the role to the palette
# entry it points at (@thm_accent -> @thm_blue -> #1e66f5), so this follows a theme swap for free.
thm() {
  v=$(tmux display-message -p "#{E:@thm_$1}" 2>/dev/null) || v=''
  [ -n "$v" ] || v="$2"
  printf '%s' "$v"
}

FZF_ACCENT=$(thm accent '#1e66f5')   # selected row, prompt, pointer, border
FZF_FG_SEL=$(thm ink    '#ffffff')   # the selected row's text
FZF_DIM=$(thm    dim    '#6c6f85')   # header, and the query line while search is off

fzf_style() {
  printf '%s\n' \
    --reverse \
    --color \
    "fg+:${FZF_FG_SEL},bg+:${FZF_ACCENT},prompt:${FZF_ACCENT},pointer:${FZF_ACCENT},header:${FZF_DIM},border:${FZF_ACCENT},disabled:${FZF_DIM},query:${FZF_ACCENT}"
}
