#!/bin/sh
# Start the standalone dev-layout LazyGit with a process-local editor override.
#
# The user's normal LazyGit config remains the base. This script appends only the
# tmux git-window overlay, so LazyGit embedded inside Neovim can keep its separate
# nvim-remote overlay and open files in the parent Neovim instance.
set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd -P) || exit 1
overlay=$ROOT/sessions/lazygit.yml

[ -r "$overlay" ] || {
  printf 'lazygit window: overlay is not readable: %s\n' "$overlay" >&2
  exit 1
}
command -v lazygit >/dev/null 2>&1 || {
  printf 'lazygit window: lazygit is not in PATH\n' >&2
  exit 1
}

config_files=${LG_CONFIG_FILE:-}
if [ -z "$config_files" ]; then
  config_output=$(
    unset LG_CONFIG_FILE
    lazygit --print-config-dir
  ) || {
    printf 'lazygit window: could not resolve the user config directory\n' >&2
    exit 1
  }
  config_dir=$(printf '%s\n' "$config_output" | sed -n '1p')
  if [ -n "$config_dir" ] && [ -r "$config_dir/config.yml" ]; then
    config_files=$config_dir/config.yml
  fi
fi

# Later LazyGit config files win. Do not append the overlay twice when a caller
# deliberately supplied the complete list through LG_CONFIG_FILE.
case ",$config_files," in
  *",$overlay,"*) ;;
  *) config_files=${config_files:+$config_files,}$overlay ;;
esac

exec env LG_CONFIG_FILE="$config_files" lazygit "$@"
