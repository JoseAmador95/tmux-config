#!/bin/sh
# grab.sh <pane-id> — pick something off the screen and type it into the command line.
# Bound to `prefix + e`. This is the useful 80% of extrakto, without extrakto's Python.
#
# The tokens are whatever the pane is showing: paths, URLs, git hashes, flags, filenames. They are
# sent with `send-keys -l` (literal), so the chosen text lands on your command line ready to edit
# rather than being executed — you stay in control of what runs.
#
# `prefix + Tab` is extrakto's usual key and is NOT used here: this config already binds it to
# last-session, which is reached far more often.
#
# NOT a substitute for tmux-thumbs / tmux-fingers, and deliberately so. Those paint hint letters
# over the live pane, which needs a compiled binary repainting the pane — there is no tmux
# primitive for it at any version. A popup over capture-pane is the honest alternative: you lose
# in-place hints, you keep "grab that thing off the screen", at zero new dependencies.
set -u
. "$(cd "$(dirname "$0")" && pwd)/fzf-style.sh"

pane="${1:-}"
[ -n "$pane" ] || exit 0

# Both granularities in one list: the whole line AND each token on it. fzf filters across both, so
# there is no mode to pick — type a fragment and take whichever comes up. One awk pass does the
# trimming and the de-duplication together; `seen` is shared, so a line that is also a single token
# appears once. -J joins wrapped lines, so a long path is one token rather than two.
tokens=$(
  tmux capture-pane -pJS -32768 -t "$pane" 2>/dev/null | awk '
    {
      line = $0
      gsub(/^[ \t]+|[ \t]+$/, "", line)
      if (length(line) > 2 && !seen[line]++) print line
      # Trim only what is really wrapping punctuation. A blanket [[:punct:]] strip eats exactly the
      # characters worth grabbing: it turns /var/log/x into var/log/x and --verbose into verbose.
      for (i = 1; i <= NF; i++) {
        t = $i
        gsub(/^["'"'"'`([{<]+|["'"'"'`)\]}>,;:.]+$/, "", t)
        if (length(t) > 2 && !seen[t]++) print t
      }
    }'
)
[ -n "$tokens" ] || { tmux display-message "nothing to grab in this pane"; exit 0; }

sel=$(printf '%s\n' "$tokens" | fzf $(fzf_style) --info=inline --no-sort \
        --prompt 'grab ' --header 'Enter types it into the command line · Esc cancels') || exit 0
[ -n "$sel" ] || exit 0

tmux send-keys -t "$pane" -l -- "$sel"
