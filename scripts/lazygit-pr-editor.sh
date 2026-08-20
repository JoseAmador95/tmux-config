#!/bin/sh
# Let gh edit PR text in the registered host Neovim editor, while its
# interactive questions remain attached to the standalone LazyGit window.
set -u

say() {
  tmux display-message "LazyGit PR editor: $*" 2>/dev/null || true
}

child=''
scratch=''
ready_attempts=0
ready_attempt_limit=100
# Invoked through the signal/exit traps below.
# shellcheck disable=SC2329
cleanup() {
  if [ -n "$child" ]; then
    kill "$child" 2>/dev/null || true
    wait "$child" 2>/dev/null || true
  fi
  if [ -n "$scratch" ] && [ -d "$scratch" ]; then
    [ ! -e "$scratch/ready" ] || rm -f "$scratch/ready"
    [ ! -e "$scratch/error" ] || rm -f "$scratch/error"
    rmdir "$scratch" 2>/dev/null || true
  fi
}
trap cleanup 0
trap 'exit 130' 1 2 15

[ "$#" -eq 1 ] || {
  say 'usage: FILE'
  exit 1
}
file=$1

pane=${TMUX_PANE:-}
case "$pane" in
  ''|'%'|%*[!0-9]*|[!%]*) say 'no valid source pane'; exit 1 ;;
esac

session=$(tmux display-message -p -t "$pane" '#{session_id}' 2>/dev/null) || {
  say "source pane no longer exists: $pane"
  exit 1
}
source_window=$(tmux display-message -p -t "$pane" '#{window_id}' 2>/dev/null) || exit 1
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
[ -f "$target" ] && [ ! -L "$target" ] || {
  say "PR text is not a regular non-symlink file: $file"
  exit 1
}
target_dir=$(cd "$(dirname "$target")" && pwd -P) || {
  say "PR text directory is not accessible: $file"
  exit 1
}
target=$target_dir/$(basename "$target")

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
editor_pane=$(printf '%s\n' "$editor_panes" | sed -n '1p')

rpc_helper=${HOME:-}/.config/nvim/scripts/nvim-review-open
[ -x "$rpc_helper" ] || {
  say "Neovim RPC helper is not executable: $rpc_helper"
  exit 1
}

umask 077
scratch=$(mktemp -d "${TMPDIR:-/tmp}/lazygit-pr-editor.XXXXXX") || {
  say 'could not create private editor handoff state'
  exit 1
}
ready=$scratch/ready
error=$scratch/error

"$rpc_helper" --wait-editor --signal-ready --tmux-pane "$editor_pane" "$target" >"$ready" 2>"$error" &
child=$!
while :; do
  if [ -s "$ready" ]; then
    ready_size=$(LC_ALL=C wc -c < "$ready" | tr -d '[:space:]')
    case "$ready_size" in
      ''|*[!0-9]*)
        say 'registered editor returned an invalid readiness signal'
        exit 1
        ;;
    esac
    if [ "$ready_size" -ge 6 ]; then
      [ "$ready_size" -eq 6 ] && IFS= read -r ready_line < "$ready" && [ "$ready_line" = READY ] || {
        say 'registered editor returned an invalid readiness signal'
        exit 1
      }
      break
    fi
  fi
  if ! kill -0 "$child" 2>/dev/null; then
    wait "$child"
    status=$?
    child=''
    detail=$(sed -n '1,8p' "$error")
    [ -n "$detail" ] || detail='registered editor rejected the PR text request'
    say "$detail"
    [ "$status" -ne 0 ] || status=1
    exit "$status"
  fi
  ready_attempts=$((ready_attempts + 1))
  if [ "$ready_attempts" -ge "$ready_attempt_limit" ]; then
    kill "$child" 2>/dev/null || true
    wait "$child" 2>/dev/null || true
    child=''
    say 'registered editor did not acknowledge the PR text request in time'
    exit 1
  fi
  sleep 0.05
done

tmux select-window -t "$editor_window" || {
  say 'could not focus the editor window'
  exit 1
}

wait "$child"
status=$?
child=''
if ! tmux select-window -t "$source_window"; then
  say 'the original git window no longer exists'
  [ "$status" -ne 0 ] || status=1
fi
if [ "$status" -ne 0 ]; then
  detail=$(sed -n '1,8p' "$error")
  [ -n "$detail" ] || detail='PR text editing did not complete'
  say "$detail"
fi
exit "$status"
