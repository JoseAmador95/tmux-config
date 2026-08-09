#!/bin/sh
# check-config.sh — the maintained, isolated validation entrypoint for this repository.
#
# It never addresses the default tmux socket. Every server has a unique -L name beneath a private
# TMUX_TMPDIR, and HOME/XDG_STATE_HOME point at disposable directories. Fake SSH/opener/editor
# commands keep focused behaviour tests offline and headless.
set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd -P) || exit 1
cd "$ROOT" || exit 1

FAILURES=0
TESTS=0

run_check() {
  label=$1
  shift
  TESTS=$((TESTS + 1))
  check_output=/tmp/tmux-check-output.$$
  "$@" > "$check_output" 2>&1
  check_rc=$?
  if [ "$check_rc" -eq 0 ]; then
    printf 'PASS  %s\n' "$label"
  else
    FAILURES=$((FAILURES + 1))
    printf 'FAIL  %s\n' "$label"
    sed 's/^/      /' "$check_output"
  fi
  rm -f "$check_output"
}

syntax_posix() {
  sh -n scripts/*.sh bootstrap.sh sessions/*.conf
}

syntax_functions() {
  command -v bash >/dev/null 2>&1 || { printf 'bash is not in PATH\n'; return 1; }
  command -v zsh >/dev/null 2>&1 || { printf 'zsh is not in PATH\n'; return 1; }
  bash -n shell/functions.sh && zsh -n shell/functions.sh
}

lint_posix() {
  command -v shellcheck >/dev/null 2>&1 || {
    printf 'shellcheck is not in PATH\n'
    return 1
  }
  # functions.sh is intentionally Bash/Zsh hybrid and is syntax-checked by both shells above.
  shellcheck -x -s sh scripts/*.sh bootstrap.sh sessions/*.conf
}

run_check 'POSIX shell syntax' syntax_posix
run_check 'Bash/Zsh function syntax' syntax_functions
run_check 'ShellCheck for POSIX files' lint_posix
run_check 'key documentation matches effective bindings' ./scripts/check-docs.sh

if ! command -v tmux >/dev/null 2>&1; then
  printf 'FAIL  isolated tmux tests (tmux is not in PATH)\n'
  printf 'check-config: %s failure(s) across %s checks\n' "$((FAILURES + 1))" "$((TESTS + 1))"
  exit 1
fi

TMP=$(mktemp -d /tmp/tmux-check.XXXXXX) || exit 1
TEST_HOME=$TMP/home
TEST_STATE=$TMP/state
TEST_SOCKETS=$TMP/sockets
TEST_BIN=$TMP/bin
PALETTE_BIN=$TMP/palette-bin
TMUX_REAL=$(command -v tmux)
mkdir -p "$TEST_HOME/.config" "$TEST_STATE" "$TEST_SOCKETS" "$TEST_BIN" "$PALETTE_BIN" || exit 1
chmod 700 "$TEST_SOCKETS" || exit 1
ln -s "$ROOT" "$TEST_HOME/.config/tmux" || exit 1

HOME=$TEST_HOME
XDG_STATE_HOME=$TEST_STATE
TMUX_TMPDIR=$TEST_SOCKETS
export HOME XDG_STATE_HOME TMUX_TMPDIR
unset TMUX

SOCKET_NUMBER=0
ACTIVE_SOCKET=''

# Invoked indirectly by trap.
# shellcheck disable=SC2317,SC2329
cleanup() {
  for socket in $ACTIVE_SERVERS; do
    "$TMUX_REAL" -L "$socket" kill-server 2>/dev/null || true
  done
  case "$TMP" in
    /tmp/tmux-check.*|/private/tmp/tmux-check.*) rm -rf "$TMP" ;;
  esac
}
ACTIVE_SERVERS=''
trap cleanup EXIT INT TERM

new_socket() {
  SOCKET_NUMBER=$((SOCKET_NUMBER + 1))
  ACTIVE_SOCKET="check-$$-${SOCKET_NUMBER}"
  ACTIVE_SERVERS="${ACTIVE_SERVERS}${ACTIVE_SERVERS:+ }$ACTIVE_SOCKET"
}

start_plain_server() {
  new_socket
  start_out=$("$TMUX_REAL" -f /dev/null -L "$ACTIVE_SOCKET" \
    new-session -d -s base -c "$ROOT" 'sleep 120' 2>&1) || {
      printf '%s\n' "$start_out"
      return 1
    }
  "$TMUX_REAL" -L "$ACTIVE_SOCKET" list-sessions >/dev/null 2>&1
}

stop_active_server() {
  "$TMUX_REAL" -L "$ACTIVE_SOCKET" kill-server 2>/dev/null || true
}

server_ref() {
  socket_path=$("$TMUX_REAL" -L "$ACTIVE_SOCKET" display-message -p '#{socket_path}') || return
  server_pid=$("$TMUX_REAL" -L "$ACTIVE_SOCKET" display-message -p '#{pid}') || return
  printf '%s,%s,0\n' "$socket_path" "$server_pid"
}

expect_equal() {
  actual=$1
  expected=$2
  context=$3
  if [ "$actual" != "$expected" ]; then
    printf '%s: expected <%s>, got <%s>\n' "$context" "$expected" "$actual"
    return 1
  fi
}

expect_contains() {
  haystack=$1
  needle=$2
  context=$3
  case "$haystack" in
    *"$needle"*) ;;
    *) printf '%s: missing <%s> in <%s>\n' "$context" "$needle" "$haystack"; return 1 ;;
  esac
}

binding_for() {
  table=$1
  wanted=$2
  "$TMUX_REAL" -L "$ACTIVE_SOCKET" list-keys -T "$table" 2>/dev/null |
    awk -v table="$table" -v wanted="$wanted" '
      {
        for (i = 1; i <= NF; i++) {
          if ($i == "-T" && $(i + 1) == table) {
            key = $(i + 2)
            sub(/^"/, "", key)
            sub(/"$/, "", key)
            if (key == wanted) {
              print
              exit
            }
          }
        }
      }
    '
}

parse_and_invariants() {
  start_plain_server || return
  parse_out=$("$TMUX_REAL" -L "$ACTIVE_SOCKET" source-file "$ROOT/tmux.conf" 2>&1) || {
    printf '%s\n' "$parse_out"
    return 1
  }
  grep -F "'!~/.config/tmux/scripts/tuicr-review.sh'" "$ROOT/scripts/palette.sh" >/dev/null || {
    printf 'stable tuicr review palette entry is absent\n'
    return 1
  }
  grep -F "'editor: DevPod'" "$ROOT/scripts/palette.sh" >/dev/null || {
    printf 'stable DevPod editor palette entry is absent\n'
    return 1
  }
  grep -F "'editor: host'" "$ROOT/scripts/palette.sh" >/dev/null || {
    printf 'stable host editor palette entry is absent\n'
    return 1
  }
  grep -F "TMUX_PALETTE_SOURCE_PATH=\$(pwd -P)" "$ROOT/scripts/palette.sh" >/dev/null || {
    printf 'palette source path capture is absent\n'
    return 1
  }
  # shellcheck disable=SC2016
  grep -F 'selection=$(items | fzf' "$ROOT/scripts/palette.sh" >/dev/null || {
    printf 'palette selection capture is absent\n'
    return 1
  }
  # shellcheck disable=SC2016
  grep -F 'eval "${command#?}"' \
    "$ROOT/scripts/palette.sh" >/dev/null || {
    printf 'palette raw-command execution is absent\n'
    return 1
  }
  if grep -F 'enter:become(' "$ROOT/scripts/palette.sh" >/dev/null; then
    printf 'palette still runs interactive commands inside fzf become\n'
    return 1
  fi
  grep -F 'palette-popup.sh #{q:client_name} #{q:pane_id}' "$ROOT/tmux.conf" >/dev/null || {
    printf 'palette dispatcher binding is absent\n'
    return 1
  }
  grep -F -- '-w 60% -h 55%' "$ROOT/scripts/palette-popup.sh" >/dev/null || {
    printf 'palette popup is not 60%% x 55%%\n'
    return 1
  }
  grep -F -- '-w 95% -h 95%' "$ROOT/scripts/palette-popup.sh" >/dev/null || {
    printf 'review popup is not 95%% x 95%%\n'
    return 1
  }

  value=$("$TMUX_REAL" -L "$ACTIVE_SOCKET" show-options -gqv default-command)
  expect_equal "$value" '' 'global default-command' || return
  value=$("$TMUX_REAL" -L "$ACTIVE_SOCKET" show-options -gqv status-interval)
  expect_equal "$value" 0 'status-interval' || return
  status_right=$("$TMUX_REAL" -L "$ACTIVE_SOCKET" show-options -gqv status-right)
  expect_contains "$status_right" '#{@pill}' 'status-right ownership' || return
  expect_contains "$status_right" '#{@pill_ink}' 'status-right ownership' || return
  expect_contains "$status_right" '#{q/h:session_name}' 'status-right session escape' || return
  case "$status_right" in
    *'#()'*|*'@session_strip'*) printf 'status-right contains derived or periodic shell state\n'; return 1 ;;
  esac

  theme_names='rosewater flamingo pink mauve red maroon peach yellow green teal sky sapphire blue lavender
               text subtext1 subtext0 overlay2 overlay1 overlay0 surface2 surface1 surface0 base mantle crust
               flavor accent urgent attention activity current_search dim line dead card chip sel_bg sel_fg ink
               urgent_ink attention_ink activity_ink current_search_ink ssh_tints'
  for name in $theme_names; do
    value=$("$TMUX_REAL" -L "$ACTIVE_SOCKET" show-options -gqv "@thm_$name")
    [ -n "$value" ] || { printf '@thm_%s is not published\n' "$name"; return 1; }
  done

  tmux_version=$("$TMUX_REAL" -V | awk '{print $2}')
  version_number=$(printf '%s\n' "$tmux_version" | sed 's/[^0-9.].*$//')
  version_major=${version_number%%.*}
  version_minor=${version_number#*.}
  version_minor=${version_minor%%.*}
  if [ "$version_major" -gt 3 ] || { [ "$version_major" -eq 3 ] && [ "$version_minor" -ge 6 ]; }; then
    expect_equal "$("$TMUX_REAL" -L "$ACTIVE_SOCKET" show-options -wgv pane-scrollbars)" modal \
      '3.6 pane-scrollbars guard' || return
    [ -n "$("$TMUX_REAL" -L "$ACTIVE_SOCKET" show-hooks -g client-light-theme 2>/dev/null)" ] || {
      printf '3.6 client-light-theme hook is absent\n'; return 1;
    }
  fi
  if [ "$version_major" -gt 3 ] || { [ "$version_major" -eq 3 ] && [ "$version_minor" -ge 7 ]; }; then
    [ -n "$("$TMUX_REAL" -L "$ACTIVE_SOCKET" show-options -wgv tree-mode-preview-style)" ] || {
      printf '3.7 tree preview style is absent\n'; return 1;
    }
  fi
  stop_active_server
}

detached_smoke() {
  new_socket
  smoke_out=$("$TMUX_REAL" -f "$ROOT/tmux.conf" -L "$ACTIVE_SOCKET" \
    new-session -d -s smoke -c "$ROOT" 'sleep 120' 2>&1) || {
      printf '%s\n' "$smoke_out"
      return 1
    }
  "$TMUX_REAL" -L "$ACTIVE_SOCKET" list-keys >/dev/null 2>&1 || return
  stop_active_server
}

write_fakes() {
  # These are test fixtures in the private temp directory, never repository content.
  printf '%s\n' '#!/bin/sh' 'exec sleep 120' > "$TEST_BIN/ssh"
  # Fixture variables expand when the generated fake runs, not while this harness writes it.
  # shellcheck disable=SC2016
  printf '%s\n' '#!/bin/sh' 'printf "%s\\n" "$1" > "$OPEN_LOG"' > "$TEST_BIN/open"
  mkdir -p "$TEST_HOME/.config/nvim/scripts" "$TEST_HOME/.config/tuicr" || return
  # shellcheck disable=SC2016
  printf '%s\n' '#!/bin/sh' 'printf "%s\\n" "$@" > "$EDITOR_LOG"' \
    > "$TEST_HOME/.config/nvim/scripts/nvim-review-open"
  # Exit 3 is the public no-active-DevPod contract; tests override it to
  # prove active success and active bridge failures do not reach host RPC.
  # shellcheck disable=SC2016
  printf '%s\n' '#!/bin/sh' \
    'printf "%s\\n" "$@" > "$DEVPOD_LOG"' \
    'exit "${DEVPOD_OPEN_STATUS:-3}"' \
    > "$TEST_HOME/.config/nvim/scripts/devpod-nvim"
  # shellcheck disable=SC2016
  printf '%s\n' '#!/bin/sh' 'printf "%s\\n" "$@" > "$REVIEW_LOG"' \
    > "$TEST_HOME/.config/tuicr/tuicr-round"
  # Select only the stable tuicr row from palette input. palette.sh must wait
  # for fzf to exit before it executes the raw command itself.
  # shellcheck disable=SC2016
  printf '%s\n' '#!/bin/sh' \
    'tab=$(printf "\t")' \
    'while IFS="$tab" read -r command label; do' \
    '  [ "$label" = "review current repository (tuicr)" ] || continue' \
    '  printf "%s\t%s\n" "$command" "$label"' \
    '  exit 0' \
    'done' \
    'exit 1' > "$TEST_BIN/fzf"
  # This fake validates the popup dispatcher without requiring an attached
  # client in the headless gate. The small palette either returns fzf's normal
  # cancellation status or its reserved review selection status; the large
  # review popup then succeeds only for the latter.
  # shellcheck disable=SC2016
  printf '%s\n' '#!/bin/sh' \
    'case "$1" in' \
    '  display-message) printf "%s\n" "$PALETTE_REPO"; exit 0 ;;' \
    '  display-popup)' \
    '    for argument in "$@"; do printf "<%s>" "$argument"; done >> "$PALETTE_POPUP_LOG"' \
    '    printf "\n" >> "$PALETTE_POPUP_LOG"' \
    '    case "$*" in' \
    '      *"/palette.sh"*) [ "${PALETTE_CANCEL:-}" = 1 ] && exit 130; exit 42 ;;' \
    '      *"/tuicr-review.sh"*) exit 0 ;;' \
    '    esac' \
    '    exit 3 ;;' \
    'esac' \
    'exit 4' > "$PALETTE_BIN/tmux"
  chmod +x "$TEST_BIN/ssh" "$TEST_BIN/open" "$TEST_BIN/fzf" \
    "$PALETTE_BIN/tmux" \
    "$TEST_HOME/.config/nvim/scripts/devpod-nvim" \
    "$TEST_HOME/.config/nvim/scripts/nvim-review-open" \
    "$TEST_HOME/.config/tuicr/tuicr-round"
}

ssh_behaviour() {
  start_plain_server || return
  "$TMUX_REAL" -L "$ACTIVE_SOCKET" source-file "$ROOT/tmux.conf" >/dev/null 2>&1 || return
  ref=$(server_ref) || return
  write_fakes || return

  session=$(PATH="$TEST_BIN:$PATH" TMUX=$ref "$ROOT/scripts/ssh-session.sh" 'user@host.example') || return
  expect_equal "$session" ssh_user_host_example 'safe SSH session name' || return
  expect_equal "$("$TMUX_REAL" -L "$ACTIVE_SOCKET" show-option -qv -t "$session" @ssh_host)" \
    'user@host.example' 'exact SSH metadata' || return
  default_command=$("$TMUX_REAL" -L "$ACTIVE_SOCKET" show-option -qv -t "$session" default-command)
  expect_contains "$default_command" "'user@host.example'" 'exact SSH shield' || return

  PATH="$TEST_BIN:$PATH" TMUX=$ref "$ROOT/scripts/ssh-session.sh" 'user_host_example' \
    >/dev/null 2>&1 && { printf 'SSH collision was accepted\n'; return 1; }
  PATH="$TEST_BIN:$PATH" TMUX=$ref "$ROOT/scripts/ssh-session.sh" '-oProxyCommand=x' \
    >/dev/null 2>&1 && { printf 'option-like SSH host was accepted\n'; return 1; }
  PATH="$TEST_BIN:$PATH" TMUX=$ref "$ROOT/scripts/ssh-session.sh" 'bad;host' \
    >/dev/null 2>&1 && { printf 'punctuated SSH host was accepted\n'; return 1; }

  "$TMUX_REAL" -L "$ACTIVE_SOCKET" new-session -d -s ssh_manual -c "$ROOT" 'sleep 120' || return
  TMUX=$ref "$ROOT/scripts/session-created.sh" || return
  manual_default=$("$TMUX_REAL" -L "$ACTIVE_SOCKET" show-option -qv -t ssh_manual default-command)
  expect_contains "$manual_default" "'manual'" 'manual SSH fallback' || return

  "$TMUX_REAL" -L "$ACTIVE_SOCKET" rename-session -t "$session" ssh_cosmetic || return
  TMUX=$ref "$ROOT/scripts/session-created.sh" || return
  expect_equal "$("$TMUX_REAL" -L "$ACTIVE_SOCKET" show-option -qv -t ssh_cosmetic @ssh_host)" \
    'user@host.example' 'SSH metadata across cosmetic rename' || return
  "$TMUX_REAL" -L "$ACTIVE_SOCKET" rename-session -t ssh_cosmetic local_now || return
  TMUX=$ref "$ROOT/scripts/session-created.sh" || return
  expect_equal "$("$TMUX_REAL" -L "$ACTIVE_SOCKET" show-option -qv -t local_now @ssh_host)" '' \
    'SSH metadata cleanup' || return
  expect_equal "$("$TMUX_REAL" -L "$ACTIVE_SOCKET" show-option -qv -t local_now default-command)" '' \
    'SSH default-command cleanup' || return
  stop_active_server
}

pane_helpers_and_status() {
  start_plain_server || return
  "$TMUX_REAL" -L "$ACTIVE_SOCKET" source-file "$ROOT/tmux.conf" >/dev/null 2>&1 || return
  ref=$(server_ref) || return
  write_fakes || return

  "$TMUX_REAL" -L "$ACTIVE_SOCKET" new-session -d -s 'log #bad;name' -c "$ROOT" 'sleep 120' || return
  # The '=' exact-match prefix is not accepted for this punctuation-heavy target even though the
  # literal name is unambiguous. Keep the hostile name, but use tmux's working literal lookup.
  pane=$("$TMUX_REAL" -L "$ACTIVE_SOCKET" display-message -p -t 'log #bad;name' '#{pane_id}') || return
  TMUX=$ref "$ROOT/scripts/toggle-log.sh" "$pane" || return
  log_path=$("$TMUX_REAL" -L "$ACTIVE_SOCKET" show-option -pqv -t "$pane" @log_path)
  case "$log_path" in
    "$HOME"/tmux-log__bad_name-w1-p*.log) ;;
    *) printf 'unsafe or unexpected pane log path: %s\n' "$log_path"; return 1 ;;
  esac
  expect_equal "$("$TMUX_REAL" -L "$ACTIVE_SOCKET" display-message -p -t "$pane" '#{pane_pipe}')" 1 \
    'pane logging enabled' || return
  TMUX=$ref "$ROOT/scripts/toggle-log.sh" "$pane" || return
  expect_equal "$("$TMUX_REAL" -L "$ACTIVE_SOCKET" display-message -p -t "$pane" '#{pane_pipe}')" 0 \
    'pane logging disabled' || return

  "$TMUX_REAL" -L "$ACTIVE_SOCKET" new-session -d -s splits -c "$ROOT" 'sleep 120' || return
  split_pane=$("$TMUX_REAL" -L "$ACTIVE_SOCKET" display-message -p -t splits '#{pane_id}') || return
  "$TMUX_REAL" -L "$ACTIVE_SOCKET" set-option -w -t splits @no_split 1 || return
  TMUX=$ref "$ROOT/scripts/split.sh" "$split_pane" auto >/dev/null 2>&1 && {
    printf 'locked window accepted a split\n'; return 1;
  }
  expect_equal "$("$TMUX_REAL" -L "$ACTIVE_SOCKET" list-panes -t splits -F '#{pane_id}' | wc -l | tr -d ' ')" 1 \
    'locked pane count' || return
  "$TMUX_REAL" -L "$ACTIVE_SOCKET" set-option -w -u -t splits @no_split || return
  TMUX=$ref "$ROOT/scripts/split.sh" "$split_pane" horizontal || return
  TMUX=$ref "$ROOT/scripts/split.sh" "$split_pane" vertical || return
  TMUX=$ref "$ROOT/scripts/split.sh" "$split_pane" auto || return
  expect_equal "$("$TMUX_REAL" -L "$ACTIVE_SOCKET" list-panes -t splits -F '#{pane_id}' | wc -l | tr -d ' ')" 4 \
    'all unlocked split modes' || return

  "$TMUX_REAL" -L "$ACTIVE_SOCKET" new-session -d -s 'hash#one' -c "$ROOT" 'sleep 120' || return
  "$TMUX_REAL" -L "$ACTIVE_SOCKET" new-session -d -s second -c "$ROOT" 'sleep 120' || return
  "$TMUX_REAL" -L "$ACTIVE_SOCKET" set-option -t 'hash#one' @pill '#111111' || return
  "$TMUX_REAL" -L "$ACTIVE_SOCKET" set-option -t second @pill '#222222' || return
  first_render=$("$TMUX_REAL" -L "$ACTIVE_SOCKET" display-message -p -t 'hash#one' '#{@pill}|#{q/h:session_name}')
  second_render=$("$TMUX_REAL" -L "$ACTIVE_SOCKET" display-message -p -t second '#{@pill}|#{q/h:session_name}')
  expect_equal "$first_render" '#111111|hash##one' 'hash-safe per-target status data' || return
  expect_equal "$second_render" '#222222|second' 'second per-target status data' || return

  fixture=$ROOT/tmux.conf
  OPEN_LOG=$TMP/open.log
  EDITOR_LOG=$TMP/editor.log
  DEVPOD_LOG=$TMP/devpod.log
  REVIEW_LOG=$TMP/review.log
  export OPEN_LOG EDITOR_LOG DEVPOD_LOG REVIEW_LOG
  printf '%s\n' 'https://example.invalid/path' | PATH="$TEST_BIN:$PATH" TMUX=$ref \
    "$ROOT/scripts/open-selection.sh" --system "$pane" || return
  expect_equal "$(sed -n '1p' "$OPEN_LOG")" 'https://example.invalid/path' 'system opener argv' || return
  printf '%s\n' "$fixture:12:7" | PATH="$TEST_BIN:$PATH" TMUX=$ref \
    "$ROOT/scripts/open-selection.sh" --editor "$pane" || return
  expect_equal "$(sed -n '1p' "$DEVPOD_LOG")" 'open-location' 'DevPod RPC command' || return
  expect_equal "$(sed -n '1p' "$EDITOR_LOG")" '--cwd' 'RPC cwd flag' || return
  expect_equal "$(sed -n '2p' "$EDITOR_LOG")" "$ROOT" 'RPC cwd argv' || return
  expect_equal "$(sed -n '3p' "$EDITOR_LOG")" '--file' 'RPC file flag' || return
  expect_equal "$(sed -n '4p' "$EDITOR_LOG")" "$fixture" 'RPC file argv' || return
  expect_equal "$(sed -n '6p' "$EDITOR_LOG")" '12' 'RPC line argv' || return
  expect_equal "$(sed -n '8p' "$EDITOR_LOG")" '7' 'RPC column argv' || return

  : > "$EDITOR_LOG"
  printf '%s\n' "$fixture:12:7" | DEVPOD_OPEN_STATUS=0 PATH="$TEST_BIN:$PATH" TMUX=$ref \
    "$ROOT/scripts/open-selection.sh" --editor "$pane" || return
  expect_equal "$(sed -n '1p' "$EDITOR_LOG")" '' 'active DevPod skips host RPC' || return
  printf '%s\n' "$fixture:12:7" | DEVPOD_OPEN_STATUS=2 PATH="$TEST_BIN:$PATH" TMUX=$ref \
    "$ROOT/scripts/open-selection.sh" --editor "$pane" >/dev/null 2>&1 && {
      printf 'active DevPod bridge failure fell through or succeeded\n'; return 1;
    }

  PATH="$TEST_BIN:$PATH" TMUX=$ref TMUX_PANE=$pane "$ROOT/scripts/tuicr-review.sh" || return
  expect_equal "$(sed -n '1p' "$REVIEW_LOG")" 'start' 'review launcher command' || return
  expect_equal "$(sed -n '2p' "$REVIEW_LOG")" '--repo' 'review repo flag' || return
  expect_equal "$(sed -n '3p' "$REVIEW_LOG")" "$ROOT" 'review repo argv' || return
  expect_equal "$(sed -n '4p' "$REVIEW_LOG")" '--open' 'review open flag' || return

  (
    cd "$ROOT" || exit 1
    PATH="$TEST_BIN:$PATH" TMUX=$ref TMUX_PANE='%999' "$ROOT/scripts/palette.sh"
  )
  palette_status=$?
  expect_equal "$palette_status" 42 'palette review dispatch status' || return

  PALETTE_REPO=$ROOT
  PALETTE_POPUP_LOG=$TMP/palette-popup.log
  export PALETTE_REPO PALETTE_POPUP_LOG
  PATH="$PALETTE_BIN:$PATH" "$ROOT/scripts/palette-popup.sh" /dev/ttys999 %999 || return
  palette_call=$(sed -n '1p' "$PALETTE_POPUP_LOG")
  review_call=$(sed -n '2p' "$PALETTE_POPUP_LOG")
  expect_contains "$palette_call" \
    "<-w><60%><-h><55%><-T>< palette ><$ROOT/scripts/palette.sh>" \
    'small palette popup dispatch' || return
  expect_contains "$review_call" \
    "<-w><95%><-h><95%><-T>< review ><-e><TMUX_PALETTE_SOURCE_PATH=$ROOT><$ROOT/scripts/tuicr-review.sh>" \
    'large review popup dispatch' || return

  PALETTE_POPUP_LOG=$TMP/palette-cancel.log
  export PALETTE_POPUP_LOG
  PALETTE_CANCEL=1 PATH="$PALETTE_BIN:$PATH" \
    "$ROOT/scripts/palette-popup.sh" /dev/ttys999 %999 || {
      printf 'palette cancellation returned an error\n'
      return 1
    }
  cancel_call=$(sed -n '1p' "$PALETTE_POPUP_LOG")
  expect_contains "$cancel_call" \
    "<-w><60%><-h><55%><-T>< palette ><$ROOT/scripts/palette.sh>" \
    'cancelled palette popup dispatch' || return
  expect_equal "$(sed -n '2p' "$PALETTE_POPUP_LOG")" '' \
    'cancelled palette skips review popup' || return

  TMUX=$ref "$ROOT/scripts/session-save.sh" || return
  "$TMUX_REAL" -L "$ACTIVE_SOCKET" set-option -t second @layout dev || return
  TMUX=$ref "$ROOT/scripts/session-save.sh" || return
  grep -F "second" "$XDG_STATE_HOME/tmux/roster" | grep -F "dev" >/dev/null || {
    printf 'explicit dev layout is absent from roster\n'; return 1;
  }
  grep -F 'dev|"agent editor git term"*' "$ROOT/shell/functions.sh" >/dev/null || {
    printf 'legacy roster migration signature is absent\n'; return 1;
  }
  stop_active_server
}

mode_frame_behaviour() {
  start_plain_server || return
  "$TMUX_REAL" -L "$ACTIVE_SOCKET" source-file "$ROOT/tmux.conf" >/dev/null 2>&1 || return

  active_colour=$("$TMUX_REAL" -L "$ACTIVE_SOCKET" show-options -gqv @pane_active_colour)
  expect_equal "$active_colour" \
    '#{?client_prefix,#{E:@thm_urgent},#{?pane_in_mode,#{E:@thm_current_search},#{?window_zoomed_flag,#{E:@thm_attention},#{E:@thm_accent}}}}' \
    'active frame mode precedence' || return
  active_ink=$("$TMUX_REAL" -L "$ACTIVE_SOCKET" show-options -gqv @pane_active_ink)
  expect_equal "$active_ink" \
    '#{?client_prefix,#{E:@thm_urgent_ink},#{?pane_in_mode,#{E:@thm_current_search_ink},#{?window_zoomed_flag,#{E:@thm_attention_ink},#{E:@thm_ink}}}}' \
    'mode pill ink precedence' || return
  expect_equal "$("$TMUX_REAL" -L "$ACTIVE_SOCKET" show-options -gqv pane-active-border-style)" \
    'fg=#{E:@pane_active_colour},bold' 'active border colour source' || return

  status_left=$("$TMUX_REAL" -L "$ACTIVE_SOCKET" show-options -gqv status-left)
  expect_contains "$status_left" \
    'fg=#{E:@pane_active_colour}#,bg=terminal' 'mode pill cap colour source' || return
  expect_contains "$status_left" \
    'fg=#{E:@pane_active_ink}#,bg=#{E:@pane_active_colour}#,bold' \
    'mode pill body colour and ink sources' || return
  case "$status_left" in
    *'?client_prefix'*) printf 'status-left has a colour precedence separate from the active frame\n'; return 1 ;;
  esac

  # The outer active test is intentional: an active dead pane must use the same dynamic colour as
  # its border line, while only an inactive dead pane falls through to @thm_dead. The content test
  # stays independent so both dead cases retain the exit status and revive hint.
  border_format=$("$TMUX_REAL" -L "$ACTIVE_SOCKET" show-options -gqv pane-border-format)
  expect_contains "$border_format" \
    '#{?pane_active,#[fg=#{E:@pane_active_colour}#,bold],#{?pane_dead,#[fg=#{E:@thm_dead}#,bold],#[fg=#{E:@thm_line}#,nobold]}}' \
    'active, inactive-dead and inactive-live label colours' || return
  expect_contains "$border_format" \
    '#{?pane_dead, ✗ #{pane_index} exit #{pane_dead_status} — prefix + R to revive ,' \
    'dead pane context' || return

  "$TMUX_REAL" -L "$ACTIVE_SOCKET" split-window -d -t base -c "$ROOT" 'sleep 120' || return
  mode_pane=$("$TMUX_REAL" -L "$ACTIVE_SOCKET" display-message -p -t base '#{pane_id}') || return
  accent=$("$TMUX_REAL" -L "$ACTIVE_SOCKET" display-message -p '#{E:@thm_accent}')
  attention=$("$TMUX_REAL" -L "$ACTIVE_SOCKET" display-message -p '#{E:@thm_attention}')
  attention_ink=$("$TMUX_REAL" -L "$ACTIVE_SOCKET" display-message -p '#{E:@thm_attention_ink}')
  current_search=$("$TMUX_REAL" -L "$ACTIVE_SOCKET" display-message -p '#{E:@thm_current_search}')
  current_search_ink=$("$TMUX_REAL" -L "$ACTIVE_SOCKET" display-message -p '#{E:@thm_current_search_ink}')

  expect_equal "$("$TMUX_REAL" -L "$ACTIVE_SOCKET" display-message -p -t "$mode_pane" \
    '#{E:@pane_active_colour}')" "$accent" 'normal active frame' || return
  "$TMUX_REAL" -L "$ACTIVE_SOCKET" set-option -w -t base synchronize-panes on || return
  expect_equal "$("$TMUX_REAL" -L "$ACTIVE_SOCKET" display-message -p -t "$mode_pane" \
    '#{E:@pane_active_colour}')" "$accent" 'synchronized active frame' || return
  "$TMUX_REAL" -L "$ACTIVE_SOCKET" set-option -w -t base synchronize-panes off || return

  "$TMUX_REAL" -L "$ACTIVE_SOCKET" resize-pane -Z -t "$mode_pane" || return
  expect_equal "$("$TMUX_REAL" -L "$ACTIVE_SOCKET" display-message -p -t "$mode_pane" \
    '#{E:@pane_active_colour}')" "$attention" 'zoomed active frame' || return
  expect_equal "$("$TMUX_REAL" -L "$ACTIVE_SOCKET" display-message -p -t "$mode_pane" \
    '#{E:@pane_active_ink}')" "$attention_ink" 'zoomed mode pill ink' || return
  zoom_pill=$("$TMUX_REAL" -L "$ACTIVE_SOCKET" display-message -p -t "$mode_pane" \
    '#{E:status-left}')
  expect_contains "$zoom_pill" "#[fg=$attention,bg=terminal]" \
    'rendered zoom pill cap' || return
  expect_contains "$zoom_pill" "#[fg=$attention_ink,bg=$attention,bold] ZOOM " \
    'rendered zoom pill body' || return
  "$TMUX_REAL" -L "$ACTIVE_SOCKET" copy-mode -t "$mode_pane" || return
  expect_equal "$("$TMUX_REAL" -L "$ACTIVE_SOCKET" display-message -p -t "$mode_pane" \
    '#{E:@pane_active_colour}')" "$current_search" 'copy mode over zoom frame' || return
  expect_equal "$("$TMUX_REAL" -L "$ACTIVE_SOCKET" display-message -p -t "$mode_pane" \
    '#{E:@pane_active_ink}')" "$current_search_ink" 'copy mode pill ink over zoom' || return
  copy_pill=$("$TMUX_REAL" -L "$ACTIVE_SOCKET" display-message -p -t "$mode_pane" \
    '#{E:status-left}')
  expect_contains "$copy_pill" "#[fg=$current_search,bg=terminal]" \
    'rendered copy-mode pill cap' || return
  expect_contains "$copy_pill" \
    "#[fg=$current_search_ink,bg=$current_search,bold] copy-mode ZOOM " \
    'rendered copy-mode pill body' || return
  "$TMUX_REAL" -L "$ACTIVE_SOCKET" send-keys -t "$mode_pane" -X cancel || return
  expect_equal "$("$TMUX_REAL" -L "$ACTIVE_SOCKET" display-message -p -t "$mode_pane" \
    '#{E:@pane_active_colour}')" "$attention" 'zoom frame restored after copy mode' || return

  stop_active_server
}

plugin_and_binding_contract() {
  start_plain_server || return
  native_copy_alt_f=$(binding_for copy-mode-vi M-f)
  "$TMUX_REAL" -L "$ACTIVE_SOCKET" source-file "$ROOT/tmux.conf" >/dev/null 2>&1 || return

  stale_cf=$(binding_for prefix C-f)
  [ -n "$stale_cf" ] && {
    printf 'stale prefix C-f binding remains\n'; return 1;
  }
  [ -z "$(binding_for root M-f)" ] || {
    printf 'Alt-f must remain unbound in the root table\n'; return 1;
  }
  expect_equal "$(binding_for copy-mode-vi M-f)" "$native_copy_alt_f" \
    'copy-mode Alt-f table remains native' || return
  if command -v tmux-fingers >/dev/null 2>&1 || [ -x "$ROOT/plugins/tmux-fingers/bin/tmux-fingers" ]; then
    fingers_binding='@fingers-cli'
    fingers_context='prefix f fingers binding'
    expect_contains "$(binding_for prefix f)" '@fingers-cli' \
      'prefix f fingers binding' || return
  else
    fingers_binding='find-window'
    fingers_context='prefix f fallback'
    expect_contains "$(binding_for prefix f)" 'find-window' \
      'prefix f fallback' || return
  fi

  # A source-file reload is the migration path for a server that already has the retired global
  # Fingers shortcut (and the older prefix C-f override). Seed both stale bindings deliberately,
  # then prove the config removes them without disturbing either prefix f or prefix J.
  "$TMUX_REAL" -L "$ACTIVE_SOCKET" bind-key -T root M-f display-message 'legacy Alt-f' || return
  "$TMUX_REAL" -L "$ACTIVE_SOCKET" bind-key -T prefix C-f display-message 'legacy C-f' || return
  "$TMUX_REAL" -L "$ACTIVE_SOCKET" source-file "$ROOT/tmux.conf" >/dev/null 2>&1 || return
  [ -z "$(binding_for root M-f)" ] || {
    printf 'reload left the legacy root M-f binding behind\n'; return 1;
  }
  [ -z "$(binding_for prefix C-f)" ] || {
    printf 'reload left the legacy prefix C-f binding behind\n'; return 1;
  }
  expect_contains "$(binding_for prefix f)" "$fingers_binding" \
    "$fingers_context after reload" || return
  expect_contains "$(binding_for prefix J)" 'resize-pane -D 5' \
    'prefix J resize binding after Fingers reload' || return

  expect_contains "$(binding_for copy-mode-vi C-o)" \
    'open-selection.sh --editor' 'editor selection binding' || return
  opener_binding=$(binding_for copy-mode-vi o)
  case "$opener_binding" in
    *'open-selection.sh --system'*|*'other-end'*) ;;
    *) printf 'copy-mode o has neither opener nor other-end: %s\n' "$opener_binding"; return 1 ;;
  esac
  [ ! -e "$ROOT/plugins/tmux-open" ] || { printf 'stale tmux-open gitlink remains\n'; return 1; }
  ! grep -F 'plugins/tmux-open' "$ROOT/.gitmodules" >/dev/null 2>&1 || {
    printf 'stale tmux-open submodule entry remains\n'; return 1;
  }
  stop_active_server
}

run_check 'real source-file parse and core invariants' parse_and_invariants
run_check 'detached smoke on a distinct socket' detached_smoke
run_check 'exact SSH metadata, validation and rename cleanup' ssh_behaviour
run_check 'logging, splits, status, opener and roster behaviour' pane_helpers_and_status
run_check 'mode-aware active pane frame' mode_frame_behaviour
run_check 'plugin and binding ownership' plugin_and_binding_contract

printf 'check-config: %s failure(s) across %s checks\n' "$FAILURES" "$TESTS"
[ "$FAILURES" -eq 0 ]
