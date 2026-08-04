#!/bin/sh
# open-selection.sh <pane-current-path> — open the copy-mode selection in $EDITOR, in a new window.
# The selection arrives on STDIN, from `copy-pipe-and-cancel`. Bound to C-o in copy-mode-vi.
#
# This replaces tmux-open's editor binding, which is loaded for `o` (plain open, which works) but
# overridden for C-o. Upstream builds this instead:
#
#     sed s/##/####/g | xargs -I {} tmux send-keys '$editor -- "{}"'; tmux send-keys 'C-m'
#
# and it has four defects, the last two of which are why it opens an EMPTY BUFFER:
#   1. $editor is resolved when the CONFIG LOADS, from the tmux server's environment rather than
#      the shell's. With EDITOR unset there it silently degrades to `vi`.
#   2. It TYPES the command into whatever the pane is running instead of running it — which needs
#      a shell sitting at a prompt to work at all.
#   3. The selection is passed untrimmed, so the whitespace a copy-mode selection always picks up
#      becomes part of the filename.
#   4. The path is resolved against the shell's cwd, not the pane's, and never checked for
#      existence — so anything that does not resolve opens an empty buffer named after the text.
#
# THE SELECTION IS UNTRUSTED. It is whatever happened to be on screen, and it ends up inside a
# command string that tmux hands to a shell. Every interpolation below is single-quoted through
# q(); the line number is validated numeric. Do not "simplify" that away — a selection reading
# `; rm -rf ~` is a plausible thing to have on screen.
set -u

dir="${1:-$HOME}"
[ -d "$dir" ] || dir="$HOME"

sel=$(cat)
[ -n "$sel" ] || { tmux display-message "nothing selected"; exit 0; }

# One target per invocation: a multi-line selection means the first line is the interesting one.
# (Upstream ran the editor once per line, which is where the user's "pasa las líneas" came from.)
sel=$(printf '%s\n' "$sel" | head -n 1)

# Trim whitespace, then wrapping punctuation. The character class is grab.sh's, kept because it was
# fixed in round 4 for exactly this: a blanket [[:punct:]] strip turns /var/log/x into var/log/x.
# Trailing ':' is NOT trimmed here — it carries the line number, which is parsed first below.
sel=$(printf '%s' "$sel" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')

# file:line[:col] — grep -n, compiler and stack-trace output. Anchored so a Windows path or a URL
# does not get mangled, and the line number is captured only when it is entirely digits.
line=''
case "$sel" in
  *:[0-9]*)
    cand_line=$(printf '%s' "$sel" | sed -n 's/^.*:\([0-9][0-9]*\):[0-9][0-9]*:\{0,1\}.*$/\1/p')  # file:LINE:col
    [ -n "$cand_line" ] || cand_line=$(printf '%s' "$sel" | sed -n 's/^.*:\([0-9][0-9]*\):\{0,1\}$/\1/p')  # file:LINE
    if [ -n "$cand_line" ]; then
      # Strip from the first :<digits> that ends the path, leaving the filename.
      cand_file=$(printf '%s' "$sel" | sed 's/:[0-9][0-9]*\(:[0-9][0-9]*\)\{0,1\}:\{0,1\}$//')
      [ -n "$cand_file" ] && { sel="$cand_file"; line="$cand_line"; }
    fi ;;
esac

# Now the wrapping punctuation, once the ':' has done its job.
# The ']' is FIRST in the trailing class on purpose: inside a bracket expression a ']' anywhere
# else CLOSES the class, so the obvious-looking [...)]}>...] silently means "( or ' or ) " followed
# by the literal text "}>,;:.". That bug shipped in the first draft and ate nothing at all.
sel=$(printf '%s' "$sel" | sed -e 's/^["'"'"'`([{<]*//' -e 's/[]"'"'"'`)}>,;:.]*$//')
[ -n "$sel" ] || { tmux display-message "nothing usable in the selection"; exit 0; }

# Resolve against the PANE's directory, not this script's and not the shell's.
case "$sel" in
  /*) target="$sel" ;;
  ~*) target=$(printf '%s' "$sel" | sed "s|^~|$HOME|") ;;
  *)  target="$dir/$sel" ;;
esac

if [ ! -e "$target" ]; then
  # The whole point of this script: say what was tried instead of opening an empty buffer.
  tmux display-message "not a file: $sel   (looked in $dir)"
  exit 0
fi

# Resolve the editor NOW, at runtime, not when the config was parsed. run-shell inherits the tmux
# server's environment, which may predate a login shell that sets EDITOR — hence the fallbacks.
ed="${EDITOR:-}"
[ -n "$ed" ] || ed=$(tmux show-environment -g EDITOR 2>/dev/null | sed -n 's/^EDITOR=//p')
[ -n "$ed" ] || { command -v nvim >/dev/null 2>&1 && ed=nvim; }
[ -n "$ed" ] || ed=vi

q() { printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"; }

# `--` stops a filename that begins with '-' being read as an option; +N must precede it.
if [ -n "$line" ]; then
  cmd="$ed +$line -- $(q "$target")"
else
  cmd="$ed -- $(q "$target")"
fi

tmux new-window -c "$dir" "$cmd"
