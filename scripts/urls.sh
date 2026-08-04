#!/bin/sh
# urls.sh <pane-id> — every URL in the pane, in an fzf popup; Enter opens the ones you marked.
# Bound to `prefix + u`. This is tmux-fzf-url plus tmux-open, minus both plugins.
#
# WHY A SCRIPT and not the one-line `display-popup` the plugin READMEs show. Two reasons, both
# about actually working on the target machine: that one-liner ends in `xargs -r open`, and `-r`
# is a GNU extension — BSD xargs on macOS does not have it, so an empty selection would run `open`
# with no argument and open the current directory. And a script can source fzf-style.sh, so the
# popup follows the theme like every other popup here instead of being the one unstyled odd one.
#
# The pane id is passed in because the popup is its own pane: tmux expands #{pane_id} in the
# binding, before the popup exists, so the capture targets the pane you invoked it from.
set -u
. "$(cd "$(dirname "$0")" && pwd)/fzf-style.sh"

pane="${1:-}"
[ -n "$pane" ] || exit 0

# -J joins wrapped lines, so a URL broken across the pane width is still one match.
urls=$(tmux capture-pane -pJS -32768 -t "$pane" 2>/dev/null |
       grep -oE "(https?|ftp|file)://[^ \"'\`<>\\\\]+" | sed 's/[.,;:)]*$//' | sort -u)
[ -n "$urls" ] || { tmux display-message "no URLs in this pane"; exit 0; }

sel=$(printf '%s\n' "$urls" | fzf $(fzf_style) --multi --info=inline \
        --prompt 'url ' --header 'Tab marks · Enter opens · Esc cancels') || exit 0
[ -n "$sel" ] || exit 0

# macOS first, then the Linux equivalent; if neither exists, say so rather than failing silently.
if   command -v open     >/dev/null 2>&1; then opener=open
elif command -v xdg-open >/dev/null 2>&1; then opener=xdg-open
else tmux display-message "no opener found (open / xdg-open)"; exit 0
fi

printf '%s\n' "$sel" | while IFS= read -r u; do
  [ -n "$u" ] && "$opener" "$u" >/dev/null 2>&1 &
done
wait
