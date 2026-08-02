#!/bin/sh
# bootstrap.sh — idempotent installer for tmux-config. Re-runnable with no adverse effects.
# Unlike the zellij bootstrap, it downloads NOTHING and seeds no permissions: tmux needs no
# plugin manager here, and tmux.conf is a real versioned file (no template expansion).
#
# What it does:
#   1) check tmux >= 3.4
#   2) warn if the repo is not at ~/.config/tmux (tmux auto-loads ~/.config/tmux/tmux.conf)
#   3) chmod +x the scripts
#   4) wire `source shell/functions.sh` into the rc, idempotently
#   5) warn about missing dependencies (fzf is optional)
set -eu

info() { printf '  \033[32m✓\033[0m %s\n' "$1"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$1"; }

DIR=$(cd "$(dirname "$0")" && pwd)
cd "$DIR"

# --- 0. args -----------------------------------------------------------------
for arg in "$@"; do
  case "$arg" in
    -h|--help)
      printf 'usage: ./bootstrap.sh\n\n'
      printf 'Idempotent installer for tmux-config. Downloads nothing.\n'
      exit 0 ;;
    *) warn "unknown arg: $arg (ignored)" ;;
  esac
done

# --- 1. tmux >= 3.4 ----------------------------------------------------------
if ! command -v tmux >/dev/null 2>&1; then
  warn "tmux is not in PATH — install it (macOS: brew install tmux)"
  exit 1
fi
ver=$(tmux -V 2>/dev/null | awk '{print $2}')          # e.g. "3.7b" or "3.4"
major=$(printf '%s' "$ver" | cut -d. -f1 | tr -dc '0-9')
minor=$(printf '%s' "$ver" | cut -d. -f2 | tr -dc '0-9')
if [ -z "$major" ] || [ -z "$minor" ]; then
  warn "could not parse tmux version ('$ver'); this config needs >= 3.4"
elif [ "$major" -lt 3 ] || { [ "$major" -eq 3 ] && [ "$minor" -lt 4 ]; }; then
  warn "tmux $ver is too old; this config needs >= 3.4"
  exit 1
else
  info "tmux $ver (>= 3.4)"
fi

# --- 2. location -------------------------------------------------------------
if [ "$DIR" = "$HOME/.config/tmux" ]; then
  info "repo is at ~/.config/tmux (auto-loaded)"
else
  warn "repo is at $DIR, not ~/.config/tmux"
  warn "tmux auto-loads ~/.config/tmux/tmux.conf — clone or symlink the repo there"
fi

# --- 3. executables ----------------------------------------------------------
chmod +x "$DIR"/scripts/*.sh "$DIR"/bootstrap.sh 2>/dev/null || true
info "scripts marked executable"

# --- 4. wire the rc (idempotent) ---------------------------------------------
if [ -f "$HOME/.config/sh/rc.sh" ]; then
  RC="$HOME/.config/sh/rc.sh"
else
  case "${SHELL:-}" in
    *bash) RC="$HOME/.bashrc" ;;
    *)     RC="$HOME/.zshrc" ;;
  esac
fi
MARKER='# >>> tmux-functions >>>'
if grep -qF "$MARKER" "$RC" 2>/dev/null; then
  info "shell functions already sourced in $RC"
else
  {
    printf '\n%s  (added by tmux-config bootstrap.sh)\n' "$MARKER"
    printf 'source "$HOME/.config/tmux/shell/functions.sh"\n'
    printf '# <<< tmux-functions <<<\n'
  } >> "$RC"
  info "sourced shell functions into $RC"
fi

# --- 5. dependencies (warn, do not abort) ------------------------------------
for dep in tmux hostname cksum ssh; do
  command -v "$dep" >/dev/null 2>&1 || warn "missing '$dep' in PATH"
done
command -v fzf >/dev/null 2>&1 || \
  warn "optional: 'fzf' not found (Alt-Space palette falls back to the command prompt)"

cat <<'EOF'

  tmux-config installed. Open a new shell (or `source` your rc), then:
    t             attach/create the "main" session
    tcwd          session rooted in the current directory (dev layout)
    tssh <host>   dedicated SSH session (every pane enters the host)

  The AI-agent window resolves its command from $TMUX_AGENT, else
  ~/.config/tmux/agent.local. Per-machine tmux overrides go in
  ~/.config/tmux/local.conf (gitignored).
EOF
