#!/bin/sh
# promote.sh <pane-id> — turn this pane into a session of its own.
# Bound to `prefix + @`. This is tmux-sessionist's promote, without the plugin.
#
# tmux has `break-pane`, but that only makes a WINDOW. This config is built around sessions — one
# terminal window, many sessions — so a pane that has grown into its own piece of work wants a
# session, not another tab.
#
# The awkward part is that `new-session` always creates a placeholder window with a shell in it,
# and `move-pane` then joins ours alongside it. Capturing the placeholder's pane id with -P -F at
# creation time is what makes it removable afterwards without guessing an index — with
# pane-base-index 1 and renumber-windows on, guessing would be exactly the kind of off-by-one that
# only shows up later.
#
# The name is asked for with ask.sh, so Esc cancels, like every other prompt here.
set -u
SELF_DIR=$(cd "$(dirname "$0")" && pwd)

pane="${1:-}"
[ -n "$pane" ] || exit 0

# Refuse to strand the session: if this is the only pane, promoting it would leave an empty husk
# behind and tmux would close the old session under you.
panes=$(tmux display-message -p -t "$pane" '#{session_windows}:#{window_panes}' 2>/dev/null)
case "$panes" in
  1:1) tmux display-message "this is the only pane in the session — nothing to promote it out of"; exit 0 ;;
esac

name=$("$SELF_DIR/ask.sh" 'promote pane to session') || exit 0
[ -n "$name" ] || exit 0

if tmux has-session -t "=$name" 2>/dev/null; then
  tmux display-message "session '$name' already exists"
  exit 0
fi

dir=$(tmux display-message -p -t "$pane" '#{pane_current_path}' 2>/dev/null)

# -P -F prints the placeholder's pane id, which is the only reliable handle on it.
placeholder=$(tmux new-session -d -P -F '#{pane_id}' -s "$name" -c "${dir:-$HOME}" 2>/dev/null) || {
  tmux display-message "could not create session '$name'"; exit 0; }

tmux move-pane -s "$pane" -t "$name:" 2>/dev/null || {
  tmux kill-session -t "=$name" 2>/dev/null
  tmux display-message "could not move the pane; '$name' rolled back"; exit 0; }

tmux kill-pane -t "$placeholder" 2>/dev/null || true
tmux switch-client -t "=$name" 2>/dev/null || true
