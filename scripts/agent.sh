#!/bin/sh
# agent.sh — resolve WHICH AI agent to launch on THIS host (claude at home, codex at
# work, …) and exec it. Used by the `dev` layout (the "agent" window) and by the `agent`
# shell function (shell/functions.sh).
#
# Why a script and not an alias: a tmux window/pane started with a command runs the binary
# DIRECTLY, without going through your shell, so an `agent` alias in .zshrc would NOT be
# visible here.
#
# EXPLICIT resolution (no autodetection), by precedence:
#   1) $TMUX_AGENT                 e.g.  export TMUX_AGENT="codex"  in a per-host rc
#   2) ~/.config/tmux/agent.local  first useful line; e.g.  echo claude > …/agent.local
#   3) if nothing resolves → open a shell with a warning (the pane stays usable, doesn't die)
set -u

cmd="${TMUX_AGENT:-}"

local_file="$HOME/.config/tmux/agent.local"
if [ -z "$cmd" ] && [ -f "$local_file" ]; then
  # First useful line: strip inline comment (#…), trim whitespace, skip blank lines.
  # awk (not `sed '/./{p;q}'`, which BSD sed on macOS rejects).
  cmd=$(awk '{ sub(/#.*/, ""); gsub(/^[ \t]+|[ \t]+$/, ""); if ($0 != "") { print; exit } }' "$local_file")
fi

# Run the command (arguments allowed: unquoted `exec $cmd` performs word-splitting).
if [ -n "$cmd" ] && command -v "${cmd%% *}" >/dev/null 2>&1; then
  # shellcheck disable=SC2086
  exec $cmd
fi

if [ -n "$cmd" ]; then
  printf 'agent.sh: "%s" is not in PATH.\n' "${cmd%% *}" >&2
else
  printf 'agent.sh: set the agent with  export TMUX_AGENT=<cmd>  or  echo <cmd> > %s\n' \
    "$local_file" >&2
fi
printf 'Opening a shell.\n' >&2
exec "${SHELL:-/bin/sh}" -l
