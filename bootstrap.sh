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
#   1) check tmux >= 3.4
#   2) warn if the repo is not at ~/.config/tmux (tmux auto-loads ~/.config/tmux/tmux.conf)
#   3) fetch the plugin submodules and the one plugin binary that needs fetching
#   4) chmod +x the scripts
#   5) wire `source shell/functions.sh` into the rc, idempotently
#   6) warn about missing dependencies
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

# --- 3. plugins (git submodules) ---------------------------------------------
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
# is allowed to simply not work rather than break the config.
FINGERS_DIR="$DIR/plugins/tmux-fingers"
if [ "$SKIP_PLUGINS" -eq 1 ] || [ ! -f "$FINGERS_DIR/install-wizard.sh" ]; then
  :
elif command -v tmux-fingers >/dev/null 2>&1; then
  info "tmux-fingers found in PATH"
elif [ -x "$FINGERS_DIR/bin/tmux-fingers" ]; then
  info "tmux-fingers binary already installed"
elif ! command -v curl >/dev/null 2>&1; then
  warn "curl not found — cannot fetch the tmux-fingers binary; prefix + f will do nothing"
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
    warn "  prefix + f will do nothing until it is installed; nothing else is affected"
    warn "  brew install morantron/tmux-fingers/tmux-fingers — or build it with Crystal"
  fi
fi

# --- 4. executables ----------------------------------------------------------
chmod +x "$DIR"/scripts/*.sh "$DIR"/bootstrap.sh 2>/dev/null || true
info "scripts marked executable"

# --- 5. wire the rc (idempotent) ---------------------------------------------
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

# --- 6. dependencies (warn, do not abort) ------------------------------------
for dep in tmux hostname cksum ssh; do
  command -v "$dep" >/dev/null 2>&1 || warn "missing '$dep' in PATH"
done
# fzf is NOT optional any more, whatever this script used to say: Alt-s (session manager), the
# click on the session pill, Alt-Space (palette) and prefix + ? (keys) are all fzf popups, and
# there is no fallback anywhere in the code — the popup simply fails to launch. The session
# manager's `/` search mode additionally needs $FZF_INPUT_STATE, which landed in fzf 0.59; on an
# older fzf everything still works except that Esc leaves search by closing the popup.
if ! command -v fzf >/dev/null 2>&1; then
  warn "'fzf' not found — Alt-s, Alt-Space and prefix + ? will not open (macOS: brew install fzf)"
else
  fver=$(fzf --version 2>/dev/null | awk '{print $1}')
  fmaj=$(printf '%s' "$fver" | cut -d. -f1 | tr -dc '0-9')
  fmin=$(printf '%s' "$fver" | cut -d. -f2 | tr -dc '0-9')
  if [ -z "$fmaj" ] || [ -z "$fmin" ]; then
    warn "could not parse fzf version ('$fver'); the session popup's / search needs >= 0.59"
  elif [ "$fmaj" -eq 0 ] && [ "$fmin" -lt 59 ]; then
    warn "fzf $fver < 0.59 — the session popup works, but Esc leaves its / search by closing it"
  else
    info "fzf $fver (>= 0.59)"
  fi
fi

cat <<'EOF'

  tmux-config installed. Open a new shell (or `source` your rc), then:
    t             attach/create the "main" session
    tcwd          session rooted in the current directory (dev layout)
    tssh <host>   dedicated SSH session (every pane enters the host)

  The AI-agent window resolves its command from $TMUX_AGENT, else
  ~/.config/tmux/agent.local. Per-machine tmux overrides go in
  ~/.config/tmux/local.conf (gitignored).
EOF
