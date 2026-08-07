#!/bin/sh
# bootstrap.sh — idempotent installer for tmux-config. Re-runnable with no adverse effects.
# tmux.conf is a real versioned file (no template expansion) and there is no plugin manager:
# plugins are git SUBMODULES under plugins/, so the SHA in this repo IS the pin. TPM was
# evaluated and rejected — its `#tag` pin is honoured on install only, changing one is a no-op,
# and its own last substantive commit was in 2023. `git submodule` does the same job natively.
#
# It DOES download, unlike the zellij bootstrap: step 3 fetches the submodules. Everything else
# is local. It still seeds no permissions and expands no templates.
#
# What it does:
#   1) warn if the repo is not at ~/.config/tmux (tmux auto-loads ~/.config/tmux/tmux.conf)
#   2) fetch the plugin submodules and the one plugin binary that needs fetching
#   3) chmod +x the scripts
#   4) wire `source shell/functions.sh` into the rc, idempotently
#   5) run the read-only environment doctor once installation is complete
set -eu

info() { printf '  \033[32m✓\033[0m %s\n' "$1"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$1"; }

DIR=$(cd "$(dirname "$0")" && pwd)
cd "$DIR"

# --- 0. args -----------------------------------------------------------------
SKIP_PLUGINS=0
for arg in "$@"; do
  case "$arg" in
    -h|--help)
      printf 'usage: ./bootstrap.sh [--no-plugins]\n\n'
      printf 'Idempotent installer for tmux-config.\n'
      printf 'Fetches the plugin submodules unless --no-plugins is given.\n'
      exit 0 ;;
    --no-plugins) SKIP_PLUGINS=1 ;;
    *) warn "unknown arg: $arg (ignored)" ;;
  esac
done

# --- 1. location -------------------------------------------------------------
if [ "$DIR" = "$HOME/.config/tmux" ]; then
  info "repo is at ~/.config/tmux (auto-loaded)"
else
  warn "repo is at $DIR, not ~/.config/tmux"
  warn "tmux auto-loads ~/.config/tmux/tmux.conf — clone or symlink the repo there"
fi

# --- 2. plugins (git submodules) ---------------------------------------------
# The only step that touches the network. Submodules are pinned by SHA, so this is reproducible:
# it checks out exactly what this repo records, never "whatever upstream has today". Updating a
# plugin is a deliberate `git submodule update --remote <path>` plus a commit.
if [ "$SKIP_PLUGINS" -eq 1 ]; then
  warn "skipping plugins (--no-plugins); tmux.conf degrades gracefully without them"
elif [ ! -f "$DIR/.gitmodules" ]; then
  warn "no .gitmodules — nothing to fetch"
elif ! command -v git >/dev/null 2>&1; then
  warn "git is not in PATH — cannot fetch the plugin submodules"
elif ! git -C "$DIR" rev-parse --git-dir >/dev/null 2>&1; then
  warn "$DIR is not a git checkout — plugins can only be fetched from a clone"
else
  if git -C "$DIR" submodule update --init --recursive >/dev/null 2>&1; then
    info "plugin submodules up to date"
  else
    warn "could not fetch the plugin submodules (offline?); tmux.conf still loads without them"
  fi
fi

# tmux-fingers is the one plugin that is a compiled binary rather than a script. Its own loader
# would fetch it by firing an install wizard through `run-shell -b` DURING config parsing — a
# network call every time tmux.conf is sourced. tmux.conf sets @fingers-skip-wizard to stop that,
# which makes fetching the binary this script's job. Prebuilt binaries exist for Linux x86_64 and
# macOS arm64 only; anywhere else this warns and fingers stays inert, which is why its key binding
# is allowed to stay unavailable rather than break the config.
FINGERS_DIR="$DIR/plugins/tmux-fingers"
if [ "$SKIP_PLUGINS" -eq 1 ] || [ ! -f "$FINGERS_DIR/install-wizard.sh" ]; then
  :
elif command -v tmux-fingers >/dev/null 2>&1; then
  info "tmux-fingers found in PATH"
elif [ -x "$FINGERS_DIR/bin/tmux-fingers" ]; then
  info "tmux-fingers binary already installed"
elif ! command -v curl >/dev/null 2>&1; then
  warn "curl not found — cannot fetch the tmux-fingers binary; its hints remain unavailable"
else
  # Surface the wizard's own reason. It fails for two very different causes — an unsupported
  # platform, or its release lookup (api.github.com) being unreachable — and reporting the wrong
  # one sends you off building Crystal when the real problem was a proxy.
  # </dev/null is load-bearing: the wizard installs `trap finish EXIT`, and on any failure that
  # handler blocks on `read -n 1` waiting for a keypress. Without this, a failed download hangs
  # bootstrap.sh forever on an interactive terminal.
  fingers_out=$(bash "$FINGERS_DIR/install-wizard.sh" download-binary </dev/null 2>&1) && fingers_ok=1 || fingers_ok=0
  if [ "$fingers_ok" -eq 1 ] && [ -x "$FINGERS_DIR/bin/tmux-fingers" ]; then
    info "tmux-fingers binary downloaded"
  else
    warn "could not install the tmux-fingers binary:"
    printf '%s\n' "$fingers_out" | tail -2 | sed 's/^/      /'
    warn "  hints remain unavailable; prefix + f keeps find-window and Alt-f stays unbound"
    warn "  brew install morantron/tmux-fingers/tmux-fingers — or build it with Crystal"
  fi
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
    # This writes a literal rc snippet; expansion must happen when that rc is sourced.
    # shellcheck disable=SC2016
    printf 'source "$HOME/.config/tmux/shell/functions.sh"\n'
    printf '# <<< tmux-functions <<<\n'
  } >> "$RC"
  info "sourced shell functions into $RC"
fi

cat <<'EOF'

  Installation steps complete. Open a new shell (or `source` your rc), then:
    t             attach/create the "main" session
    tcwd          session rooted in the current directory (dev layout)
    tssh <host>   dedicated SSH session (every pane enters the host)

  The AI-agent window resolves its command from $TMUX_AGENT, else
  ~/.config/tmux/agent.local. Per-machine tmux overrides go in
  ~/.config/tmux/local.conf (gitignored).
EOF

# --- 5. environment doctor ---------------------------------------------------
# One source of truth for required versions, dependencies and config parsing. Optional feature
# gaps are warnings and return success; a hard failure propagates through set -e.
"$DIR/scripts/doctor.sh" --brief
