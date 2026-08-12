#!/bin/sh
# Open one LazyGit file in the existing editor window of this tmux session.
# The request is direct argv throughout: no filename, path or pane metadata is
# interpolated into a shell command.
set -u

say() {
  tmux display-message "LazyGit editor: $*" 2>/dev/null || true
}

line=1
if [ "${1:-}" = --line ]; then
  [ "$#" -ge 2 ] || { say 'usage: [--line N] -- FILE'; exit 1; }
  line=$2
  shift 2
fi
[ "${1:-}" = -- ] || { say 'usage: [--line N] -- FILE'; exit 1; }
shift
[ "$#" -eq 1 ] || { say 'usage: [--line N] -- FILE'; exit 1; }
file=$1

case "$line" in
  ''|0|*[!0-9]*) say 'line must be a positive integer'; exit 1 ;;
esac

pane=${TMUX_PANE:-}
case "$pane" in
  ''|'%'|%*[!0-9]*|[!%]*) say 'no valid source pane'; exit 1 ;;
esac

session=$(tmux display-message -p -t "$pane" '#{session_id}' 2>/dev/null) || {
  say "source pane no longer exists: $pane"
  exit 1
}
window_name=$(tmux display-message -p -t "$pane" '#{window_name}' 2>/dev/null) || exit 1
[ "$window_name" = git ] || {
  say 'this editor route is available only from the git window'
  exit 1
}

dir=$(tmux display-message -p -t "$pane" '#{pane_current_path}' 2>/dev/null) || exit 1
repo=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null) || {
  say 'git window is not inside a Git repository'
  exit 1
}
repo=$(cd "$repo" && pwd -P) || exit 1

ssh_host=$(tmux show-option -qv -t "$session" @ssh_host 2>/dev/null) || ssh_host=''
[ -z "$ssh_host" ] || {
  say 'local editor routing is unavailable in SSH sessions'
  exit 1
}

case "$file" in
  /*) target=$file ;;
  *) target=$repo/$file ;;
esac
[ -e "$target" ] || {
  say "file does not exist: $file"
  exit 1
}
target_dir=$(cd "$(dirname "$target")" && pwd -P) || {
  say "file directory is not accessible: $file"
  exit 1
}
target=$target_dir/$(basename "$target")
case "$target" in
  "$repo"|"$repo"/*) ;;
  *) say "file is outside the repository: $file"; exit 1 ;;
esac

editor_windows=$(tmux list-windows -t "$session" -F '#{window_id} #{window_name}' 2>/dev/null |
  awk '$2 == "editor" { print $1 }') || exit 1
editor_count=$(printf '%s\n' "$editor_windows" | awk 'NF { count++ } END { print count + 0 }')
[ "$editor_count" -eq 1 ] || {
  say "expected exactly one editor window; found $editor_count"
  exit 1
}
editor_window=$(printf '%s\n' "$editor_windows" | sed -n '1p')
editor_panes=$(tmux list-panes -t "$editor_window" -F '#{pane_id}' 2>/dev/null) || exit 1
editor_count=$(printf '%s\n' "$editor_panes" | awk 'NF { count++ } END { print count + 0 }')
[ "$editor_count" -eq 1 ] || {
  say "editor window must contain exactly one pane; found $editor_count"
  exit 1
}

devpod_helper=${HOME:-}/.config/nvim/scripts/devpod-nvim
if [ -x "$devpod_helper" ]; then
  devpod_output=$(
    "$devpod_helper" open-location \
      --cwd "$repo" \
      --file "$target" \
      --line "$line" \
      --column 1 2>&1
  )
  devpod_status=$?
  if [ "$devpod_status" -eq 0 ]; then
    tmux select-window -t "$editor_window"
    exit $?
  fi
  # Exit 3 is the public no-active-DevPod result. Any other status belongs
  # to an active or ambiguous bridge and must not fall through to host RPC.
  if [ "$devpod_status" -ne 3 ]; then
    [ -n "$devpod_output" ] || devpod_output='DevPod editor rejected the request'
    say "$devpod_output"
    exit "$devpod_status"
  fi
fi

rpc_helper=${HOME:-}/.config/nvim/scripts/nvim-review-open
[ -x "$rpc_helper" ] || {
  say "Neovim RPC helper is not executable: $rpc_helper"
  exit 1
}
rpc_output=$(
  "$rpc_helper" \
    --cwd "$repo" \
    --file "$target" \
    --line "$line" \
    --column 1 2>&1
)
rpc_status=$?
if [ "$rpc_status" -ne 0 ]; then
  [ -n "$rpc_output" ] || rpc_output='registered editor rejected the request'
  say "$rpc_output"
  exit "$rpc_status"
fi

tmux select-window -t "$editor_window"
