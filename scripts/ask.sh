#!/bin/sh
# ask.sh — the one-line prompt the popups use. Two shapes:
#   ask.sh "<prompt>" ["<initial>"]   -> prints the answer on stdout, exit 0; exit 1 if cancelled
#   ask.sh --confirm "<question>"     -> exit 0 for yes, exit 1 for no or cancelled
#
# WHY fzf and not `read`: these prompts run inside fzf's execute(...), where a raw `IFS= read -r`
# has no key handling at all — Esc is just a byte fed to read, so a rename could not be cancelled
# (only an empty line, a non-y answer, or ^C would do it) and Esc-then-Enter would happily pass an
# ESC control character through as the new session name.
#
# fzf gives Esc for free AND separates the two outcomes by exit code alone: the `print-query`
# action prints the query and exits 0, while abort exits 130 having printed NOTHING — fzf only
# prints the query on the accept path (see the reqClose branch of its terminal.go; this is also why
# --print-query, which sounds like the obvious flag here, is useless: on abort it prints nothing).
# So there is no sentinel string to misparse and no way for a cancel to look like an empty answer.
set -u
# shellcheck source=scripts/fzf-style.sh
. "$(cd "$(dirname "$0")" && pwd)/fzf-style.sh"

if [ "${1:-}" = '--confirm' ]; then
  # A two-row list rather than a y/N read: Esc cancels, and "no" is the row under the cursor, so
  # the destructive answer is never the one Enter lands on by accident.
  # fzf_style's documented contract is one whitespace-free option per line; splitting is wanted.
  # shellcheck disable=SC2046
  ans=$(printf 'no\nyes\n' | fzf $(fzf_style) --no-sort --info=hidden \
          --prompt "${2:-are you sure?} " --header 'Enter confirms · Esc cancels')
  [ "$ans" = 'yes' ] || exit 1
  exit 0
fi

[ "$#" -ge 1 ] || exit 1

# Empty stdin: fzf is being used as a text field, not a picker, so there is nothing to pick and
# Enter is rebound to print-query.
# fzf_style's documented contract is one whitespace-free option per line; splitting is wanted.
# shellcheck disable=SC2046
ans=$(: | fzf $(fzf_style) --info=hidden \
        --prompt "${1} " --query "${2:-}" \
        --header 'Enter confirms · Esc cancels' \
        --bind 'enter:print-query')
rc=$?

[ "$rc" -eq 130 ] && exit 1   # Esc or ^C
[ -n "$ans" ] || exit 1       # an empty answer is a cancel too
printf '%s\n' "$ans"
