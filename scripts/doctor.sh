#!/bin/sh
# doctor.sh — read-only diagnosis for this tmux configuration and its optional features.
#
# Usage: doctor.sh [--brief]
# Hard requirements fail the command. Optional tools and machine wiring are warnings because the
# config deliberately degrades without them. The parse probe gets its own HOME, state directory
# and tmux socket, so it cannot discover a live server or source private work/local overrides.
set -u

case "${1:-}" in
  '') BRIEF=0 ;;
  --brief) BRIEF=1 ;;
  -h|--help) printf 'usage: doctor.sh [--brief]\n'; exit 0 ;;
  *) printf 'doctor: unknown argument: %s\n' "$1" >&2; exit 64 ;;
esac
[ "$#" -le 1 ] || { printf 'usage: doctor.sh [--brief]\n' >&2; exit 64; }

ROOT=$(cd "$(dirname "$0")/.." && pwd -P) || exit 1
USER_HOME=$HOME
HARD=0
WARN=0

pass() {
  [ "$BRIEF" -eq 1 ] || printf 'PASS  %s\n' "$*"
}
warn() {
  WARN=$((WARN + 1))
  printf 'WARN  %s\n' "$*"
}
fail() {
  HARD=$((HARD + 1))
  printf 'FAIL  %s\n' "$*" >&2
}
manual() {
  [ "$BRIEF" -eq 1 ] || printf 'INFO  %s\n' "$*"
}

version_at_least() {
  have=$1
  need_major=$2
  need_minor=$3
  major=${have%%.*}
  rest=${have#*.}
  minor=$(printf '%s' "$rest" | sed 's/[^0-9].*$//')
  case "$major:$minor" in
    *[!0-9:]*|:|*:) return 1 ;;
  esac
  [ "$major" -gt "$need_major" ] || {
    [ "$major" -eq "$need_major" ] && [ "$minor" -ge "$need_minor" ]
  }
}

# Keep this list aligned with commands used by the maintained POSIX helpers, not optional popups.
core_missing=''
for cmd in awk basename cat chmod cksum grep hostname locale mkdir mktemp mv rm sed sleep sort ssh tr; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    core_missing="${core_missing}${core_missing:+, }$cmd"
  fi
done
if [ -n "$core_missing" ]; then
  fail "core commands missing: $core_missing"
else
  pass 'core POSIX commands are available'
fi

if [ -r "$ROOT/tmux.conf" ]; then
  pass "tmux.conf is readable"
else
  fail "tmux.conf is not readable: $ROOT/tmux.conf"
fi

canonical=$USER_HOME/.config/tmux
canonical_real=''
if [ -d "$canonical" ]; then
  canonical_real=$(cd "$canonical" 2>/dev/null && pwd -P)
fi
if [ "$canonical_real" = "$ROOT" ]; then
  pass 'repo is wired at ~/.config/tmux'
else
  warn "repo is not wired at ~/.config/tmux (current: $ROOT)"
fi

selected_shell=${SHELL:-/bin/sh}
shell_path=$(command -v "$selected_shell" 2>/dev/null || true)
if [ -n "$shell_path" ] && [ -x "$shell_path" ]; then
  pass "selected shell is executable: $shell_path"
else
  fail "selected shell is absent or not executable: $selected_shell"
fi

charset=''
if command -v locale >/dev/null 2>&1; then
  charset=$(locale charmap 2>/dev/null || true)
fi
case "$charset" in
  UTF-8|utf8|UTF8|utf-8) pass "locale character map is $charset" ;;
  '') fail 'cannot determine the locale character map' ;;
  *) fail "locale is not UTF-8 (character map: $charset)" ;;
esac

TMUX_VERSION=''
if ! command -v tmux >/dev/null 2>&1; then
  fail 'tmux is not in PATH'
else
  raw_version=$(tmux -V 2>/dev/null || true)
  TMUX_VERSION=$(printf '%s\n' "$raw_version" | awk '{print $2}')
  if [ -z "$TMUX_VERSION" ] || ! version_at_least "$TMUX_VERSION" 3 4; then
    case "$TMUX_VERSION" in
      '') fail "cannot parse tmux version: $raw_version" ;;
      *) fail "tmux $TMUX_VERSION is below the supported floor 3.4" ;;
    esac
  else
    pass "tmux $TMUX_VERSION satisfies the 3.4 floor"
    if version_at_least "$TMUX_VERSION" 3 6; then
      pass 'tmux 3.6 guarded light/dark hooks and copy-mode scrollbar are active'
    else
      [ "$BRIEF" -eq 1 ] || printf 'INFO  tmux 3.6 guarded theme/scrollbar surfaces are inactive\n'
    fi
    if version_at_least "$TMUX_VERSION" 3 7; then
      pass 'tmux 3.7 tree preview and native floating-pane support are active'
    else
      [ "$BRIEF" -eq 1 ] || printf 'INFO  tmux 3.7 tree/floating support is inactive\n'
    fi
  fi
fi

# Parse in a subshell so none of these environment overrides leak into the remaining checks.
parse_probe() (
  probe=$(mktemp -d /tmp/tmux-doctor.XXXXXX) || exit 1
  probe_home=$probe/home
  probe_state=$probe/state
  probe_sockets=$probe/sockets
  probe_sock=doctor-$$
  # Invoked indirectly by trap.
  # shellcheck disable=SC2317,SC2329
  probe_cleanup() {
    HOME=$probe_home XDG_STATE_HOME=$probe_state TMUX_TMPDIR=$probe_sockets \
      tmux -L "$probe_sock" kill-server 2>/dev/null || true
    case "$probe" in
      /tmp/tmux-doctor.*|/private/tmp/tmux-doctor.*) rm -rf "$probe" ;;
    esac
  }
  trap probe_cleanup EXIT INT TERM
  mkdir -p "$probe_home/.config" "$probe_state" "$probe_sockets" || exit 1
  chmod 700 "$probe_sockets" || exit 1
  ln -s "$ROOT" "$probe_home/.config/tmux" || exit 1
  # This override is deliberately scoped to the parse-probe subshell.
  # shellcheck disable=SC2030
  HOME=$probe_home
  XDG_STATE_HOME=$probe_state
  TMUX_TMPDIR=$probe_sockets
  export HOME XDG_STATE_HOME TMUX_TMPDIR
  unset TMUX
  tmux -f /dev/null -L "$probe_sock" new-session -d -s doctor 'sleep 120' || exit 1
  tmux -L "$probe_sock" list-sessions >/dev/null 2>&1 || exit 1
  tmux -L "$probe_sock" source-file "$ROOT/tmux.conf"
)

if [ -n "$TMUX_VERSION" ] && version_at_least "$TMUX_VERSION" 3 4 && [ -r "$ROOT/tmux.conf" ] && \
   command -v mktemp >/dev/null 2>&1; then
  parse_out=$(parse_probe 2>&1)
  parse_rc=$?
  if [ "$parse_rc" -eq 0 ]; then
    pass 'tmux.conf parses in a private server'
  else
    fail 'tmux.conf does not parse in a private server'
    printf '%s\n' "$parse_out" | sed 's/^/      /' >&2
  fi
fi

# bootstrap.sh uses the same rc choice. Exactly one complete pair means the functions are wired
# idempotently; this remains a warning because tmux.conf itself does not require shell helpers.
if [ -f "$USER_HOME/.config/sh/rc.sh" ]; then
  rc_file=$USER_HOME/.config/sh/rc.sh
else
  case "$selected_shell" in
    *bash) rc_file=$USER_HOME/.bashrc ;;
    *) rc_file=$USER_HOME/.zshrc ;;
  esac
fi
start_count=$(grep -F -c '# >>> tmux-functions >>>' "$rc_file" 2>/dev/null || true)
end_count=$(grep -F -c '# <<< tmux-functions <<<' "$rc_file" 2>/dev/null || true)
if [ "$start_count" -eq 1 ] && [ "$end_count" -eq 1 ] && [ -r "$ROOT/shell/functions.sh" ]; then
  pass "shell function marker is complete in $rc_file"
else
  warn "shell function marker is incomplete or duplicated in $rc_file (start=$start_count, end=$end_count)"
fi

for optional in fzf nvim lazygit; do
  if command -v "$optional" >/dev/null 2>&1; then
    pass "$optional is available"
  else
    warn "$optional is missing; its optional tmux surfaces remain unavailable"
  fi
done
if command -v python3 >/dev/null 2>&1 || command -v python >/dev/null 2>&1; then
  pass 'Python is available for extrakto'
else
  warn 'Python is missing; extrakto remains unavailable'
fi
if command -v open >/dev/null 2>&1 || command -v xdg-open >/dev/null 2>&1; then
  pass 'a system opener is available'
else
  warn 'open/xdg-open is missing; copy-mode o keeps tmux other-end'
fi

agent_cmd=${TMUX_AGENT:-}
agent_file=$ROOT/agent.local
if [ -z "$agent_cmd" ] && [ -r "$agent_file" ]; then
  agent_cmd=$(awk '{ sub(/#.*/, ""); gsub(/^[ \t]+|[ \t]+$/, ""); if ($0 != "") { print; exit } }' "$agent_file")
fi
if [ -z "$agent_cmd" ]; then
  warn 'no AI agent is configured (TMUX_AGENT or agent.local)'
elif command -v "${agent_cmd%% *}" >/dev/null 2>&1; then
  pass "AI agent resolves to ${agent_cmd%% *}"
else
  warn "configured AI agent is not in PATH: ${agent_cmd%% *}"
fi

if command -v git >/dev/null 2>&1 && git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then
  submodules=$(git -C "$ROOT" submodule status --recursive 2>&1)
  submodule_rc=$?
  if [ "$submodule_rc" -ne 0 ]; then
    submodule_error=$(printf '%s\n' "$submodules" | sed -n '/^fatal:/ { p; q; }')
    [ -n "$submodule_error" ] || submodule_error=$(printf '%s\n' "$submodules" | sed -n '1p')
    warn "plugin submodule status could not be read: $submodule_error"
  elif printf '%s\n' "$submodules" | grep -q '^-' ; then
    warn 'one or more plugin submodules are uninitialized'
  elif printf '%s\n' "$submodules" | grep -q '^+' ; then
    warn 'one or more plugin submodules differ from their pinned commit'
  elif printf '%s\n' "$submodules" | grep -q '^U' ; then
    warn 'one or more plugin submodules have unresolved commits'
  else
    pass 'plugin submodules match their pins'
  fi
else
  warn 'git checkout metadata is unavailable; submodule pins were not checked'
fi

if command -v tmux-fingers >/dev/null 2>&1 || [ -x "$ROOT/plugins/tmux-fingers/bin/tmux-fingers" ]; then
  pass 'tmux-fingers binary is available'
else
  warn 'tmux-fingers binary is missing; prefix + f keeps find-window and Alt-f stays unbound'
fi

manual 'Nerd Font glyph coverage cannot be proven automatically; inspect the status bar manually.'
manual 'Live OSC 133 prompt marks cannot be proven outside a pane; use prefix + Y in an active shell.'

printf 'doctor: %s failure(s), %s warning(s)\n' "$HARD" "$WARN"
[ "$HARD" -eq 0 ]
