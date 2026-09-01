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
  parse_out=$("$TMUX_REAL" -L "$ACTIVE_SOCKET" source-file "$ROOT/tmux.conf" 2>&1) || {
    printf '%s\n' "$parse_out"
    return 1
  }
  default_terminal=$("$TMUX_REAL" -L "$ACTIVE_SOCKET" show-options -gv default-terminal) || return
  expect_equal "$default_terminal" 'tmux-256color' 'default-terminal' || return
  terminal_features=$("$TMUX_REAL" -L "$ACTIVE_SOCKET" show-options -sv terminal-features) || return
  terminal_feature_count=$(printf '%s\n' "$terminal_features" | tr ',' '\n' | awk '
    $0 == "xterm-ghostty:RGB:sync" { count++ }
    END { print count + 0 }
  ')
  [ "$terminal_feature_count" -eq 1 ] || {
    printf 'terminal-features must contain exactly one xterm-ghostty:RGB:sync entry; got %s\n' \
      "$terminal_feature_count"
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
  for tool_window in agent editor git; do
    grep -Eq "tmux set-option -w -t \"\\\$SESS:${tool_window}\"[[:space:]]+remain-on-exit on" \
      "$ROOT/sessions/dev.conf" || {
        printf '%s tool window does not retain its pane on application exit\n' "$tool_window"
        return 1
      }
    grep -Eq "tmux set-option -w -t \"\\\$SESS:${tool_window}\"[[:space:]]+@no_split 1" \
      "$ROOT/sessions/dev.conf" || {
        printf '%s tool window is not protected from splits\n' "$tool_window"
        return 1
      }
  done

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
  # The blocking-editor mode reports readiness, observes the selected window,
  # then returns a caller-controlled status. Ordinary editor RPC still only
  # records argv and exits successfully.
  # shellcheck disable=SC2016
  printf '%s\n' '#!/bin/sh' \
    'printf "%s\\n" "$@" > "$EDITOR_LOG"' \
    'if [ "${1:-}" = --wait-editor ]; then' \
    '  [ "${PR_EDITOR_NO_READY:-}" != 1 ] || exit "${PR_EDITOR_STATUS:-1}"' \
    '  if [ "${PR_EDITOR_HANG_READY:-}" = 1 ]; then while :; do sleep 1; done; fi' \
    '  if [ "${PR_EDITOR_INVALID_READY:-}" = 1 ]; then printf "READY\\nextra\\n"; sleep 1; exit 0; fi' \
    '  printf "READY\\n"' \
    '  sleep 0.15' \
    '  if [ -n "${PR_EDITOR_FOCUS_LOG:-}" ]; then' \
    '    session=$(tmux display-message -p -t "$TMUX_PANE" "#{session_id}")' \
    '    tmux display-message -p -t "$session" "#{window_name}" > "$PR_EDITOR_FOCUS_LOG"' \
    '  fi' \
    '  sleep 0.05' \
    '  exit "${PR_EDITOR_STATUS:-0}"' \
    'fi' \
    'exit 0' > "$TEST_HOME/.config/nvim/scripts/nvim-review-open"
  # Exit 3 is the public no-active-DevPod contract; tests override it to
  # prove active success and active bridge failures do not reach host RPC.
  # shellcheck disable=SC2016
  printf '%s\n' '#!/bin/sh' \
    'printf "%s\\n" "$@" > "${DEVPOD_LOG:-$HOME/devpod.log}"' \
    'if [ "${1:-}" = up ] && [ -n "${TMUX_REFRESH_EVENT_LOG:-}" ]; then' \
    '  printf "editor-devpod|%s\\n" "$*" >> "$TMUX_REFRESH_EVENT_LOG"' \
    'fi' \
    '[ "${1:-}" = up ] && exec sleep 120' \
    'exit "${DEVPOD_OPEN_STATUS:-3}"' \
    > "$TEST_HOME/.config/nvim/scripts/devpod-nvim"
  # shellcheck disable=SC2016
  printf '%s\n' '#!/bin/sh' \
    'if [ -n "${TMUX_REFRESH_EVENT_LOG:-}" ]; then' \
    '  printf "editor-host|restore=%s|%s\\n" "${NVIM_TMUX_REFRESH_RESTORE:-}" "$*" >> "$TMUX_REFRESH_EVENT_LOG"' \
    'fi' \
    'exec sleep 120' > "$TEST_BIN/nvim"
  # shellcheck disable=SC2016
  printf '%s\n' '#!/bin/sh' \
    'printf "agent\\n" >> "$TMUX_REFRESH_EVENT_LOG"' \
    'exec sleep 120' > "$TEST_BIN/refresh-agent"
  # The standalone LazyGit wrapper first asks for the normal user config, then
  # execs the same binary with a process-local LG_CONFIG_FILE list.
  # shellcheck disable=SC2016
  printf '%s\n' '#!/bin/sh' \
    'if [ "${1:-}" = --print-config-dir ]; then printf "%s\n" "$LAZYGIT_CONFIG_DIR"; exit 0; fi' \
    'printf "%s\n" "${LG_CONFIG_FILE:-}" > "$LAZYGIT_LOG"' \
    'printf "%s\n" "${GH_EDITOR:-}" > "${LAZYGIT_EDITOR_LOG:-/dev/null}"' \
    'printf "%s\n" "$@" >> "$LAZYGIT_LOG"' \
    'if [ -n "${TMUX_REFRESH_EVENT_LOG:-}" ]; then' \
    '  printf "git\\n" >> "$TMUX_REFRESH_EVENT_LOG"' \
    '  exec sleep 120' \
    'fi' \
    > "$TEST_BIN/lazygit"
  # shellcheck disable=SC2016
  printf '%s\n' '#!/bin/sh' 'printf "%s\\n" "$@" > "$REVIEW_LOG"' \
    > "$TEST_HOME/.config/tuicr/tuicr-round"
  # Select one requested stable row from palette input. palette.sh must wait
  # for fzf to exit before it executes the raw command itself.
  # shellcheck disable=SC2016
  printf '%s\n' '#!/bin/sh' \
    'tab=$(printf "\t")' \
    'wanted=${PALETTE_SELECTION:-review current repository (tuicr)}' \
    'while IFS="$tab" read -r command label; do' \
    '  [ "$label" = "$wanted" ] || continue' \
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
  chmod +x "$TEST_BIN/ssh" "$TEST_BIN/open" "$TEST_BIN/fzf" "$TEST_BIN/nvim" \
    "$TEST_BIN/refresh-agent" \
    "$TEST_BIN/lazygit" \
    "$PALETTE_BIN/tmux" \
    "$TEST_HOME/.config/nvim/scripts/devpod-nvim" \
    "$TEST_HOME/.config/nvim/scripts/nvim-review-open" \
    "$TEST_HOME/.config/tuicr/tuicr-round"
}

dev_window_palette_behaviour() {
  start_plain_server || return
  ref=$(server_ref) || return
  write_fakes || return

  "$TMUX_REAL" -L "$ACTIVE_SOCKET" new-session -d -s palette-dev -n agent \
    -c "$ROOT" 'sleep 120' || return
  source_pane=$(
    "$TMUX_REAL" -L "$ACTIVE_SOCKET" display-message -p -t palette-dev:agent '#{pane_id}'
  ) || return
  for target in editor git term; do
    "$TMUX_REAL" -L "$ACTIVE_SOCKET" new-window -d -t palette-dev: -n "$target" \
      -c "$ROOT" 'sleep 120' || return
  done
  "$TMUX_REAL" -L "$ACTIVE_SOCKET" set-option -t palette-dev @layout dev || return

  for target in agent editor git term; do
    (
      cd "$ROOT" || exit 1
      PALETTE_SELECTION="window: $target" PATH="$TEST_BIN:$PATH" \
        TMUX=$ref TMUX_PALETTE_SOURCE_PANE=$source_pane "$ROOT/scripts/palette.sh"
    ) || return
    expect_equal "$($TMUX_REAL -L "$ACTIVE_SOCKET" display-message -p \
      -t palette-dev '#{window_name}')" "$target" "palette selects $target window" || return
  done

  "$TMUX_REAL" -L "$ACTIVE_SOCKET" set-option -t palette-dev @layout shell || return
  TMUX=$ref TMUX_PALETTE_SOURCE_PANE=$source_pane \
    "$ROOT/scripts/dev-window.sh" agent >/dev/null 2>&1 && {
      printf 'non-dev session accepted dev-window selection\n'
      return 1
    }
  "$TMUX_REAL" -L "$ACTIVE_SOCKET" set-option -t palette-dev @layout dev || return

  "$TMUX_REAL" -L "$ACTIVE_SOCKET" kill-window -t palette-dev:term || return
  TMUX=$ref TMUX_PALETTE_SOURCE_PANE=$source_pane \
    "$ROOT/scripts/dev-window.sh" term >/dev/null 2>&1 && {
      printf 'missing dev window was accepted\n'
      return 1
    }

  "$TMUX_REAL" -L "$ACTIVE_SOCKET" new-window -d -t palette-dev: -n editor \
    -c "$ROOT" 'sleep 120' || return
  TMUX=$ref TMUX_PALETTE_SOURCE_PANE=$source_pane \
    "$ROOT/scripts/dev-window.sh" editor >/dev/null 2>&1 && {
      printf 'duplicate dev windows were accepted\n'
      return 1
    }
  TMUX=$ref TMUX_PALETTE_SOURCE_PANE=$source_pane \
    "$ROOT/scripts/dev-window.sh" shell >/dev/null 2>&1 && {
      printf 'unknown dev window name was accepted\n'
      return 1
    }

  stop_active_server
}

dev_refresh_behaviour() {
  start_plain_server || return
  ref=$(server_ref) || return
  write_fakes || return

  refresh_helper=$ROOT/scripts/dev-session-refresh.sh
  refresh_work_dir=$TEST_HOME/.config/tmux-work
  refresh_lazygit_dir=$TMP/refresh-lazygit-config
  refresh_lazygit_log=$TMP/refresh-lazygit.log
  refresh_lazygit_editor_log=$TMP/refresh-lazygit-editor.log
  refresh_devpod_log=$TMP/refresh-devpod.log
  refresh_bin=$TMP/refresh-bin
  refresh_command_log=$TMP/refresh-commands.log
  mkdir -p "$refresh_work_dir" "$refresh_lazygit_dir" "$refresh_bin" || return
  : > "$refresh_lazygit_dir/config.yml"
  : > "$refresh_lazygit_log"
  : > "$refresh_lazygit_editor_log"
  : > "$refresh_devpod_log"
  : > "$refresh_command_log"
  # Log only the argv boundary, then forward to the exact real tmux binary.
  # This makes respawn order observable without adding refresh state to tmux.
  # shellcheck disable=SC2016
  printf '%s\n' '#!/bin/sh' \
    'if [ "${1:-}" = respawn-pane ]; then' \
    '  for argument in "$@"; do printf "<%s>" "$argument"; done >> "$TMUX_REFRESH_COMMAND_LOG"' \
    '  printf "\\n" >> "$TMUX_REFRESH_COMMAND_LOG"' \
    'fi' \
    'exec "$TMUX_REFRESH_REAL_TMUX" "$@"' > "$refresh_bin/tmux"
  chmod +x "$refresh_bin/tmux" || return

  "$TMUX_REAL" -L "$ACTIVE_SOCKET" set-environment -g PATH \
    "$refresh_bin:$TEST_BIN:$PATH" || return
  "$TMUX_REAL" -L "$ACTIVE_SOCKET" set-environment -g TMUX_REFRESH_REAL_TMUX "$TMUX_REAL" || return
  "$TMUX_REAL" -L "$ACTIVE_SOCKET" set-environment -g TMUX_REFRESH_COMMAND_LOG \
    "$refresh_command_log" || return
  "$TMUX_REAL" -L "$ACTIVE_SOCKET" set-environment -g TMUX_AGENT "$TEST_BIN/refresh-agent" || return
  "$TMUX_REAL" -L "$ACTIVE_SOCKET" set-environment -g LAZYGIT_CONFIG_DIR "$refresh_lazygit_dir" || return
  "$TMUX_REAL" -L "$ACTIVE_SOCKET" set-environment -g LAZYGIT_LOG "$refresh_lazygit_log" || return
  "$TMUX_REAL" -L "$ACTIVE_SOCKET" set-environment -g LAZYGIT_EDITOR_LOG \
    "$refresh_lazygit_editor_log" || return
  "$TMUX_REAL" -L "$ACTIVE_SOCKET" set-environment -g DEVPOD_LOG "$refresh_devpod_log" || return

  create_refresh_fixture() {
    fixture_session=$1
    fixture_mode=$2
    "$TMUX_REAL" -L "$ACTIVE_SOCKET" new-session -d -s "$fixture_session" -n agent \
      -c "$ROOT" 'sleep 120' || return
    for fixture_window in editor git term; do
      "$TMUX_REAL" -L "$ACTIVE_SOCKET" new-window -d -t "$fixture_session:" \
        -n "$fixture_window" -c "$ROOT" 'sleep 120' || return
    done
    "$TMUX_REAL" -L "$ACTIVE_SOCKET" set-option -t "$fixture_session" @layout dev || return
    for fixture_window in agent editor git; do
      "$TMUX_REAL" -L "$ACTIVE_SOCKET" set-option -w -t "$fixture_session:$fixture_window" \
        remain-on-exit on || return
      "$TMUX_REAL" -L "$ACTIVE_SOCKET" set-option -w -t "$fixture_session:$fixture_window" \
        @no_split 1 || return
    done
    fixture_editor=$(
      "$TMUX_REAL" -L "$ACTIVE_SOCKET" display-message -p -t "$fixture_session:editor" '#{pane_id}'
    ) || return
    if [ "$fixture_mode" = devpod ]; then
      "$TMUX_REAL" -L "$ACTIVE_SOCKET" set-option -p -t "$fixture_editor" @devpod_active 1 || return
    fi
    printf '%s\n' "$fixture_editor"
  }

  wait_for_event_count() {
    event_file=$1
    wanted_count=$2
    event_attempts=0
    while [ "$(awk 'END { print NR + 0 }' "$event_file" 2>/dev/null || printf 0)" -lt "$wanted_count" ] &&
      [ "$event_attempts" -lt 500 ]; do
      sleep 0.02
      event_attempts=$((event_attempts + 1))
    done
    event_count=$(awk 'END { print NR + 0 }' "$event_file" 2>/dev/null || printf 0)
    [ "$event_count" -ge "$wanted_count" ] || {
      printf 'refresh event log reached %s line(s), expected %s\n' "$event_count" "$wanted_count"
      printf 'recorded refresh events:\n'
      sed 's/^/  /' "$event_file"
      printf 'recorded respawn commands:\n'
      sed 's/^/  /' "$refresh_command_log"
      printf 'editor state: '
      "$TMUX_REAL" -L "$ACTIVE_SOCKET" display-message -p -t "$refresh_source" \
        '#{session_id}|#{window_id}|#{pane_id}|#{pane_dead}|#{pane_pid}|#{pane_current_command}' \
        2>&1 || true
      printf 'tmux messages:\n'
      "$TMUX_REAL" -L "$ACTIVE_SOCKET" show-messages -JT 2>&1 | tail -n 12 | sed 's/^/  /'
      for debug_window in agent editor git; do
        printf '%s pane output:\n' "$debug_window"
        "$TMUX_REAL" -L "$ACTIVE_SOCKET" capture-pane -p -S -20 \
          -t "$refresh_session:$debug_window" 2>&1 | sed 's/^/  /'
      done
      return 1
    }
  }

  exercise_refresh() {
    refresh_session=$1
    refresh_mode=$2
    expected_editor_event=$3
    refresh_event_log=$TMP/$refresh_session-events.log
    : > "$refresh_event_log"
    : > "$refresh_command_log"
    "$TMUX_REAL" -L "$ACTIVE_SOCKET" set-environment -g TMUX_REFRESH_EVENT_LOG \
      "$refresh_event_log" || return
    printf 'set-option -g @refresh_test_work_loaded %s\n' "$refresh_mode" \
      > "$refresh_work_dir/work.conf" || return
    "$TMUX_REAL" -L "$ACTIVE_SOCKET" set-option -gu @refresh_test_work_loaded 2>/dev/null || true

    refresh_source=$(create_refresh_fixture "$refresh_session" "$refresh_mode") || return

    before_ids=$(
      "$TMUX_REAL" -L "$ACTIVE_SOCKET" list-windows -t "$refresh_session" \
        -F '#{window_name}|#{window_id}|#{pane_id}' | sort
    ) || return
    before_agent_pid=$(
      "$TMUX_REAL" -L "$ACTIVE_SOCKET" display-message -p -t "$refresh_session:agent" '#{pane_pid}'
    ) || return
    before_editor_pid=$(
      "$TMUX_REAL" -L "$ACTIVE_SOCKET" display-message -p -t "$refresh_session:editor" '#{pane_pid}'
    ) || return
    before_git_pid=$(
      "$TMUX_REAL" -L "$ACTIVE_SOCKET" display-message -p -t "$refresh_session:git" '#{pane_pid}'
    ) || return
    before_term_pane=$(
      "$TMUX_REAL" -L "$ACTIVE_SOCKET" display-message -p -t "$refresh_session:term" '#{pane_id}'
    ) || return
    before_term_pid=$(
      "$TMUX_REAL" -L "$ACTIVE_SOCKET" display-message -p -t "$before_term_pane" '#{pane_pid}'
    ) || return
    before_term_cwd=$(
      "$TMUX_REAL" -L "$ACTIVE_SOCKET" display-message -p -t "$before_term_pane" '#{pane_current_path}'
    ) || return

    TMUX=$ref "$refresh_helper" check "$refresh_source" >/dev/null 2>&1 || return
    expect_equal "$("$TMUX_REAL" -L "$ACTIVE_SOCKET" list-windows -t "$refresh_session" \
      -F '#{window_name}|#{window_id}|#{pane_id}' | sort)" "$before_ids" \
      "$refresh_session check is topology-read-only" || return
    for check_window in agent editor git term; do
      case "$check_window" in
        agent) check_pid=$before_agent_pid ;;
        editor) check_pid=$before_editor_pid ;;
        git) check_pid=$before_git_pid ;;
        term) check_pid=$before_term_pid ;;
      esac
      expect_equal "$("$TMUX_REAL" -L "$ACTIVE_SOCKET" display-message -p \
        -t "$refresh_session:$check_window" '#{pane_pid}')" "$check_pid" \
        "$refresh_session check leaves $check_window process unchanged" || return
    done

    TMUX=$ref "$refresh_helper" schedule "$refresh_source" >/dev/null 2>&1 || return
    sleep 0.2
    expect_equal "$($TMUX_REAL -L "$ACTIVE_SOCKET" display-message -p \
      -t "$refresh_session:agent" '#{pane_pid}')" "$before_agent_pid" \
      "$refresh_session agent remains live while refresh waits" || return
    expect_equal "$($TMUX_REAL -L "$ACTIVE_SOCKET" display-message -p \
      -t "$refresh_session:git" '#{pane_pid}')" "$before_git_pid" \
      "$refresh_session git remains live while refresh waits" || return
    expect_equal "$(sed -n '1p' "$refresh_event_log")" '' \
      "$refresh_session performs no respawn before editor exit" || return

    kill -TERM "$before_editor_pid" || return
    wait_for_event_count "$refresh_event_log" 3 || return
    expect_equal "$(grep -Fxc agent "$refresh_event_log")" 1 \
      "$refresh_session starts agent once" || return
    expect_equal "$(grep -Fxc git "$refresh_event_log")" 1 \
      "$refresh_session starts git once" || return
    expect_equal "$(grep -Fxc "$expected_editor_event" "$refresh_event_log")" 1 \
      "$refresh_session starts the expected editor once" || return

    refresh_agent_pane=$(
      "$TMUX_REAL" -L "$ACTIVE_SOCKET" display-message -p -t "$refresh_session:agent" '#{pane_id}'
    ) || return
    refresh_git_pane=$(
      "$TMUX_REAL" -L "$ACTIVE_SOCKET" display-message -p -t "$refresh_session:git" '#{pane_id}'
    ) || return
    expect_contains "$(sed -n '1p' "$refresh_command_log")" \
      "<respawn-pane><-k><-t><$refresh_agent_pane>" \
      "$refresh_session respawns agent first" || return
    expect_contains "$(sed -n '2p' "$refresh_command_log")" \
      "<respawn-pane><-k><-t><$refresh_git_pane>" \
      "$refresh_session respawns git second" || return
    expect_contains "$(sed -n '3p' "$refresh_command_log")" \
      "<respawn-pane><-k><-t><$refresh_source>" \
      "$refresh_session respawns editor last" || return

    after_ids=$(
      "$TMUX_REAL" -L "$ACTIVE_SOCKET" list-windows -t "$refresh_session" \
        -F '#{window_name}|#{window_id}|#{pane_id}' | sort
    ) || return
    expect_equal "$after_ids" "$before_ids" "$refresh_session exact tmux ids" || return
    after_agent_pid=$(
      "$TMUX_REAL" -L "$ACTIVE_SOCKET" display-message -p -t "$refresh_session:agent" '#{pane_pid}'
    ) || return
    after_editor_pid=$(
      "$TMUX_REAL" -L "$ACTIVE_SOCKET" display-message -p -t "$refresh_session:editor" '#{pane_pid}'
    ) || return
    after_git_pid=$(
      "$TMUX_REAL" -L "$ACTIVE_SOCKET" display-message -p -t "$refresh_session:git" '#{pane_pid}'
    ) || return
    [ "$after_agent_pid" != "$before_agent_pid" ] || { printf 'agent PID did not change\n'; return 1; }
    [ "$after_editor_pid" != "$before_editor_pid" ] || { printf 'editor PID did not change\n'; return 1; }
    [ "$after_git_pid" != "$before_git_pid" ] || { printf 'git PID did not change\n'; return 1; }

    expect_equal "$($TMUX_REAL -L "$ACTIVE_SOCKET" display-message -p \
      -t "$before_term_pane" '#{pane_id}')" "$before_term_pane" \
      "$refresh_session term pane id" || return
    expect_equal "$($TMUX_REAL -L "$ACTIVE_SOCKET" display-message -p \
      -t "$before_term_pane" '#{pane_pid}')" "$before_term_pid" \
      "$refresh_session term PID" || return
    expect_equal "$($TMUX_REAL -L "$ACTIVE_SOCKET" display-message -p \
      -t "$before_term_pane" '#{pane_current_path}')" "$before_term_cwd" \
      "$refresh_session term cwd" || return
    for refresh_window in agent editor git; do
      expect_equal "$($TMUX_REAL -L "$ACTIVE_SOCKET" show-option -wqv \
        -t "$refresh_session:$refresh_window" remain-on-exit)" on \
        "$refresh_session $refresh_window remain-on-exit" || return
      expect_equal "$($TMUX_REAL -L "$ACTIVE_SOCKET" show-option -wqv \
        -t "$refresh_session:$refresh_window" @no_split)" 1 \
        "$refresh_session $refresh_window split lock" || return
      expect_equal "$($TMUX_REAL -L "$ACTIVE_SOCKET" display-message -p \
        -t "$refresh_session:$refresh_window" '#{pane_current_path}')" "$ROOT" \
        "$refresh_session $refresh_window cwd" || return
    done
    expect_equal "$($TMUX_REAL -L "$ACTIVE_SOCKET" show-option -gqv @refresh_test_work_loaded)" \
      "$refresh_mode" "$refresh_session disposable work config reload" || return
  }

  "$TMUX_REAL" -L "$ACTIVE_SOCKET" new-session -d -s refresh-guard -c "$ROOT" 'sleep 120' || return
  guard_pane=$(
    "$TMUX_REAL" -L "$ACTIVE_SOCKET" display-message -p -t refresh-guard '#{pane_id}'
  ) || return
  guard_pid=$(
    "$TMUX_REAL" -L "$ACTIVE_SOCKET" display-message -p -t "$guard_pane" '#{pane_pid}'
  ) || return

  exercise_refresh refresh-host host 'editor-host|restore=1|' || return
  expect_equal "$($TMUX_REAL -L "$ACTIVE_SOCKET" display-message -p -t "$guard_pane" '#{pane_pid}')" \
    "$guard_pid" 'host refresh leaves second session process unchanged' || return
  exercise_refresh refresh-devpod devpod 'editor-devpod|up --restore-session' || return
  expect_equal "$($TMUX_REAL -L "$ACTIVE_SOCKET" display-message -p -t "$guard_pane" '#{pane_pid}')" \
    "$guard_pid" 'DevPod refresh leaves second session process unchanged' || return

  TMUX=$ref "$refresh_helper" check 'editor' >/dev/null 2>&1 && {
    printf 'refresh accepted a non-tmux pane token\n'; return 1;
  }
  TMUX=$ref "$refresh_helper" check '%999999' >/dev/null 2>&1 && {
    printf 'refresh accepted a missing pane id\n'; return 1;
  }

  invalid_source=$(create_refresh_fixture refresh-invalid-layout host) || return
  invalid_agent_pid=$(
    "$TMUX_REAL" -L "$ACTIVE_SOCKET" display-message -p -t refresh-invalid-layout:agent '#{pane_pid}'
  ) || return
  "$TMUX_REAL" -L "$ACTIVE_SOCKET" set-option -t refresh-invalid-layout @layout shell || return
  TMUX=$ref "$refresh_helper" check "$invalid_source" >/dev/null 2>&1 && {
    printf 'refresh accepted a non-dev layout\n'; return 1;
  }
  expect_equal "$($TMUX_REAL -L "$ACTIVE_SOCKET" display-message -p \
    -t refresh-invalid-layout:agent '#{pane_pid}')" "$invalid_agent_pid" \
    'invalid layout performs no tool respawn' || return

  missing_source=$(create_refresh_fixture refresh-missing host) || return
  "$TMUX_REAL" -L "$ACTIVE_SOCKET" kill-window -t refresh-missing:term || return
  TMUX=$ref "$refresh_helper" check "$missing_source" >/dev/null 2>&1 && {
    printf 'refresh accepted a missing term window\n'; return 1;
  }

  duplicate_source=$(create_refresh_fixture refresh-duplicate host) || return
  "$TMUX_REAL" -L "$ACTIVE_SOCKET" new-window -d -t refresh-duplicate: -n git \
    -c "$ROOT" 'sleep 120' || return
  TMUX=$ref "$refresh_helper" check "$duplicate_source" >/dev/null 2>&1 && {
    printf 'refresh accepted duplicate git windows\n'; return 1;
  }

  multipane_source=$(create_refresh_fixture refresh-multipane host) || return
  "$TMUX_REAL" -L "$ACTIVE_SOCKET" split-window -d -t refresh-multipane:agent \
    -c "$ROOT" 'sleep 120' || return
  TMUX=$ref "$refresh_helper" check "$multipane_source" >/dev/null 2>&1 && {
    printf 'refresh accepted a multipane tool window\n'; return 1;
  }

  non_editor_source=$(
    "$TMUX_REAL" -L "$ACTIVE_SOCKET" display-message -p -t refresh-multipane:term '#{pane_id}'
  ) || return
  TMUX=$ref "$refresh_helper" check "$non_editor_source" >/dev/null 2>&1 && {
    printf 'refresh accepted a non-editor source pane\n'; return 1;
  }

  timeout_source=$(create_refresh_fixture refresh-timeout host) || return
  timeout_agent_pid=$(
    "$TMUX_REAL" -L "$ACTIVE_SOCKET" display-message -p -t refresh-timeout:agent '#{pane_pid}'
  ) || return
  timeout_git_pid=$(
    "$TMUX_REAL" -L "$ACTIVE_SOCKET" display-message -p -t refresh-timeout:git '#{pane_pid}'
  ) || return
  TMUX=$ref "$refresh_helper" run "$timeout_source" >/dev/null 2>&1 && {
    printf 'refresh did not time out while the editor remained alive\n'; return 1;
  }
  expect_equal "$($TMUX_REAL -L "$ACTIVE_SOCKET" display-message -p \
    -t refresh-timeout:agent '#{pane_pid}')" "$timeout_agent_pid" \
    'timeout performs no agent respawn' || return
  expect_equal "$($TMUX_REAL -L "$ACTIVE_SOCKET" display-message -p \
    -t refresh-timeout:git '#{pane_pid}')" "$timeout_git_pid" \
    'timeout performs no git respawn' || return

  stop_active_server
}

lazygit_editor_behaviour() {
  start_plain_server || return
  "$TMUX_REAL" -L "$ACTIVE_SOCKET" source-file "$ROOT/tmux.conf" >/dev/null 2>&1 || return
  ref=$(server_ref) || return
  write_fakes || return

  EDITOR_LOG=$TMP/lazygit-editor.log
  DEVPOD_LOG=$TMP/lazygit-devpod.log
  PR_EDITOR_FOCUS_LOG=$TMP/lazygit-pr-editor-focus.log
  export EDITOR_LOG DEVPOD_LOG PR_EDITOR_FOCUS_LOG

  "$TMUX_REAL" -L "$ACTIVE_SOCKET" new-session -d -s lazygit-route -n git \
    -c "$ROOT" 'sleep 120' || return
  git_pane=$(
    "$TMUX_REAL" -L "$ACTIVE_SOCKET" display-message -p -t lazygit-route:git '#{pane_id}'
  ) || return
  "$TMUX_REAL" -L "$ACTIVE_SOCKET" new-window -d -t lazygit-route: -n editor \
    -c "$ROOT" 'sleep 120' || return
  editor_window=$(
    "$TMUX_REAL" -L "$ACTIVE_SOCKET" display-message -p -t lazygit-route:editor '#{window_id}'
  ) || return

  PATH="$TEST_BIN:$PATH" TMUX=$ref TMUX_PANE=$git_pane \
    "$ROOT/scripts/lazygit-edit.sh" --line 12 -- "$ROOT/tmux.conf" || return
  expect_equal "$(sed -n '1p' "$DEVPOD_LOG")" open-location \
    'standalone LazyGit tries DevPod editor first' || return
  expect_equal "$(sed -n '1p' "$EDITOR_LOG")" --cwd 'LazyGit host RPC cwd flag' || return
  expect_equal "$(sed -n '2p' "$EDITOR_LOG")" "$ROOT" 'LazyGit host RPC root' || return
  expect_equal "$(sed -n '3p' "$EDITOR_LOG")" --file 'LazyGit host RPC file flag' || return
  expect_equal "$(sed -n '4p' "$EDITOR_LOG")" "$ROOT/tmux.conf" 'LazyGit host RPC file' || return
  expect_equal "$(sed -n '6p' "$EDITOR_LOG")" 12 'LazyGit host RPC line' || return
  expect_equal "$(sed -n '8p' "$EDITOR_LOG")" 1 'LazyGit host RPC column' || return
  expect_equal "$($TMUX_REAL -L "$ACTIVE_SOCKET" display-message -p -t lazygit-route '#{window_id}')" \
    "$editor_window" 'successful host RPC focuses editor window' || return

  "$TMUX_REAL" -L "$ACTIVE_SOCKET" select-window -t lazygit-route:git || return
  : > "$EDITOR_LOG"
  DEVPOD_OPEN_STATUS=0 PATH="$TEST_BIN:$PATH" TMUX=$ref TMUX_PANE=$git_pane \
    "$ROOT/scripts/lazygit-edit.sh" -- "$ROOT/README.md" || return
  expect_equal "$(sed -n '1p' "$EDITOR_LOG")" '' 'active DevPod skips LazyGit host RPC' || return
  expect_equal "$($TMUX_REAL -L "$ACTIVE_SOCKET" display-message -p -t lazygit-route '#{window_id}')" \
    "$editor_window" 'successful DevPod RPC focuses editor window' || return

  "$TMUX_REAL" -L "$ACTIVE_SOCKET" select-window -t lazygit-route:git || return
  DEVPOD_OPEN_STATUS=2 PATH="$TEST_BIN:$PATH" TMUX=$ref TMUX_PANE=$git_pane \
    "$ROOT/scripts/lazygit-edit.sh" -- "$ROOT/README.md" >/dev/null 2>&1 && {
      printf 'active DevPod bridge failure fell through or succeeded for LazyGit\n'
      return 1
    }
  expect_equal "$($TMUX_REAL -L "$ACTIVE_SOCKET" display-message -p -t lazygit-route '#{window_name}')" \
    git 'failed LazyGit RPC keeps focus in git window' || return

  pr_dir=$(cd "$TMP" && pwd -P) || return
  pr_file="$pr_dir/gh body ; [literal].md"
  printf '%s\n' 'Pull request body' > "$pr_file" || return
  : > "$EDITOR_LOG"
  : > "$PR_EDITOR_FOCUS_LOG"
  PATH="$TEST_BIN:$PATH" TMUX=$ref TMUX_PANE=$git_pane \
    "$ROOT/scripts/lazygit-pr-editor.sh" "$pr_file" || return
  expect_equal "$(sed -n '1p' "$EDITOR_LOG")" --wait-editor \
    'PR text uses blocking Neovim editor mode' || return
  expect_equal "$(sed -n '2p' "$EDITOR_LOG")" --signal-ready \
    'PR text requests a readiness signal' || return
  expect_equal "$(sed -n '3p' "$EDITOR_LOG")" --tmux-pane \
    'PR text binds the registered editor to one tmux pane' || return
  expect_equal "$(sed -n '4p' "$EDITOR_LOG")" "$($TMUX_REAL -L "$ACTIVE_SOCKET" list-panes -t "$editor_window" -F '#{pane_id}')" \
    'PR text uses the exact editor pane id' || return
  expect_equal "$(sed -n '5p' "$EDITOR_LOG")" "$pr_file" \
    'PR text path remains one exact argument' || return
  expect_equal "$(sed -n '1p' "$PR_EDITOR_FOCUS_LOG")" editor \
    'ready PR editor focuses the editor window while blocked' || return
  expect_equal "$($TMUX_REAL -L "$ACTIVE_SOCKET" display-message -p -t lazygit-route '#{window_name}')" \
    git 'completed PR editor returns focus to git window' || return

  : > "$PR_EDITOR_FOCUS_LOG"
  PR_EDITOR_STATUS=19 PATH="$TEST_BIN:$PATH" TMUX=$ref TMUX_PANE=$git_pane \
    "$ROOT/scripts/lazygit-pr-editor.sh" "$pr_file" >/dev/null 2>&1 && {
      printf 'failed PR editor returned success\n'
      return 1
    }
  expect_equal "$(sed -n '1p' "$PR_EDITOR_FOCUS_LOG")" editor \
    'failing PR editor was focused only after readiness' || return
  expect_equal "$($TMUX_REAL -L "$ACTIVE_SOCKET" display-message -p -t lazygit-route '#{window_name}')" \
    git 'failed PR editor returns focus to git window' || return

  : > "$PR_EDITOR_FOCUS_LOG"
  PR_EDITOR_NO_READY=1 PR_EDITOR_STATUS=23 PATH="$TEST_BIN:$PATH" TMUX=$ref TMUX_PANE=$git_pane \
    "$ROOT/scripts/lazygit-pr-editor.sh" "$pr_file" >/dev/null 2>&1 && {
      printf 'PR editor failure before readiness returned success\n'
      return 1
    }
  expect_equal "$(sed -n '1p' "$PR_EDITOR_FOCUS_LOG")" '' \
    'PR editor failure before readiness never focuses editor' || return
  expect_equal "$($TMUX_REAL -L "$ACTIVE_SOCKET" display-message -p -t lazygit-route '#{window_name}')" \
    git 'PR editor failure before readiness keeps focus in git window' || return

  PR_EDITOR_INVALID_READY=1 PATH="$TEST_BIN:$PATH" TMUX=$ref TMUX_PANE=$git_pane \
    "$ROOT/scripts/lazygit-pr-editor.sh" "$pr_file" >/dev/null 2>&1 && {
      printf 'PR editor accepted a non-exact readiness signal\n'
      return 1
    }
  expect_equal "$($TMUX_REAL -L "$ACTIVE_SOCKET" display-message -p -t lazygit-route '#{window_name}')" \
    git 'invalid PR editor readiness keeps focus in git window' || return

  PR_EDITOR_HANG_READY=1 PATH="$TEST_BIN:$PATH" TMUX=$ref TMUX_PANE=$git_pane \
    "$ROOT/scripts/lazygit-pr-editor.sh" "$pr_file" >/dev/null 2>&1 && {
      printf 'PR editor readiness wait had no timeout\n'
      return 1
    }
  expect_equal "$($TMUX_REAL -L "$ACTIVE_SOCKET" display-message -p -t lazygit-route '#{window_name}')" \
    git 'timed-out PR editor readiness keeps focus in git window' || return

  base_pane=$(
    "$TMUX_REAL" -L "$ACTIVE_SOCKET" display-message -p -t base '#{pane_id}'
  ) || return
  PATH="$TEST_BIN:$PATH" TMUX=$ref TMUX_PANE=$base_pane \
    "$ROOT/scripts/lazygit-edit.sh" -- "$ROOT/README.md" >/dev/null 2>&1 && {
      printf 'non-git source window accepted standalone LazyGit routing\n'
      return 1
    }

  "$TMUX_REAL" -L "$ACTIVE_SOCKET" new-window -d -t lazygit-route: -n editor \
    -c "$ROOT" 'sleep 120' || return
  PATH="$TEST_BIN:$PATH" TMUX=$ref TMUX_PANE=$git_pane \
    "$ROOT/scripts/lazygit-edit.sh" -- "$ROOT/README.md" >/dev/null 2>&1 && {
      printf 'ambiguous editor windows accepted standalone LazyGit routing\n'
      return 1
    }

  LAZYGIT_CONFIG_DIR=$TMP/lazygit-config
  LAZYGIT_LOG=$TMP/lazygit.log
  LAZYGIT_EDITOR_LOG=$TMP/lazygit-gh-editor.log
  export LAZYGIT_CONFIG_DIR LAZYGIT_LOG LAZYGIT_EDITOR_LOG
  mkdir -p "$LAZYGIT_CONFIG_DIR" || return
  : > "$LAZYGIT_CONFIG_DIR/config.yml"
  PATH="$TEST_BIN:$PATH" LG_CONFIG_FILE='' "$ROOT/scripts/lazygit-window.sh" status || return
  expect_equal "$(sed -n '1p' "$LAZYGIT_LOG")" \
    "$LAZYGIT_CONFIG_DIR/config.yml,$ROOT/sessions/lazygit.yml" \
    'standalone LazyGit default config plus overlay' || return
  expect_equal "$(sed -n '2p' "$LAZYGIT_LOG")" status 'standalone LazyGit argv' || return
  expect_equal "$(sed -n '1p' "$LAZYGIT_EDITOR_LOG")" "$ROOT/scripts/lazygit-pr-editor.sh" \
    'standalone LazyGit gets process-local PR editor' || return

  custom_configs=$TMP/one.yml,$TMP/two.yml
  LG_CONFIG_FILE=$custom_configs PATH="$TEST_BIN:$PATH" \
    "$ROOT/scripts/lazygit-window.sh" branch || return
  expect_equal "$(sed -n '1p' "$LAZYGIT_LOG")" \
    "$custom_configs,$ROOT/sessions/lazygit.yml" \
    'standalone LazyGit preserves explicit config list' || return
  expect_equal "$(sed -n '2p' "$LAZYGIT_LOG")" branch 'standalone LazyGit custom argv' || return

  stop_active_server
}

devpod_editor_behaviour() {
  start_plain_server || return
  ref=$(server_ref) || return
  write_fakes || return
  DEVPOD_LOG=$TEST_HOME/devpod.log
  export DEVPOD_LOG
  "$TMUX_REAL" -L "$ACTIVE_SOCKET" set-environment -g DEVPOD_LOG "$DEVPOD_LOG" || return

  "$TMUX_REAL" -L "$ACTIVE_SOCKET" new-session -d -s editor-create -n shell -c "$ROOT" 'sleep 120' || return
  source_pane=$(
    "$TMUX_REAL" -L "$ACTIVE_SOCKET" display-message -p -t editor-create:shell '#{pane_id}'
  ) || return
  PATH="$TEST_BIN:$PATH" TMUX=$ref "$ROOT/scripts/devpod-editor.sh" host "$source_pane" || return
  editor_windows=$(
    "$TMUX_REAL" -L "$ACTIVE_SOCKET" list-windows -t editor-create -F '#{window_id}	#{window_name}' |
      awk -F '	' '$2 == "editor" { print $1 }'
  ) || return
  expect_equal "$(printf '%s\n' "$editor_windows" | awk 'NF { count++ } END { print count + 0 }')" 1 \
    'missing editor window is created exactly once' || return
  editor_window=$(printf '%s\n' "$editor_windows" | sed -n '1p')
  editor_pane=$(
    "$TMUX_REAL" -L "$ACTIVE_SOCKET" display-message -p -t "$editor_window" '#{pane_id}'
  ) || return
  expect_equal "$("$TMUX_REAL" -L "$ACTIVE_SOCKET" show-option -pqv -t "$editor_pane" remain-on-exit)" on \
    'created editor pane remains visible on exit' || return
  expect_equal "$("$TMUX_REAL" -L "$ACTIVE_SOCKET" show-option -wqv -t "$editor_window" @no_split)" 1 \
    'created editor window rejects splits' || return
  "$TMUX_REAL" -L "$ACTIVE_SOCKET" display-message -p -t "$source_pane" '#{pane_id}' >/dev/null || {
    printf 'creating the editor window destroyed the source pane\n'
    return 1
  }

  "$TMUX_REAL" -L "$ACTIVE_SOCKET" respawn-pane -k -t "$editor_pane" false || return
  attempts=0
  while [ "$("$TMUX_REAL" -L "$ACTIVE_SOCKET" display-message -p -t "$editor_pane" \
    '#{pane_dead}' 2>/dev/null || true)" != 1 ] && [ "$attempts" -lt 100 ]; do
    sleep 0.02
    attempts=$((attempts + 1))
  done
  expect_equal "$("$TMUX_REAL" -L "$ACTIVE_SOCKET" display-message -p -t "$editor_pane" '#{pane_dead}')" 1 \
    'editor pane becomes dead instead of disappearing' || return
  expect_equal "$("$TMUX_REAL" -L "$ACTIVE_SOCKET" list-windows -t editor-create -F '#{window_name}' |
    awk '$0 == "editor" { count++ } END { print count + 0 }')" 1 \
    'editor window survives application exit' || return

  PATH="$TEST_BIN:$PATH" TMUX=$ref "$ROOT/scripts/devpod-editor.sh" host "$source_pane" || return
  expect_equal "$("$TMUX_REAL" -L "$ACTIVE_SOCKET" display-message -p -t "$editor_window" '#{pane_id}')" \
    "$editor_pane" 'existing editor pane is reused' || return
  PATH="$TEST_BIN:$PATH" TMUX=$ref "$ROOT/scripts/devpod-editor.sh" up "$source_pane" || return
  attempts=0
  while [ ! -f "$DEVPOD_LOG" ] && [ "$attempts" -lt 100 ]; do
    sleep 0.02
    attempts=$((attempts + 1))
  done
  expect_equal "$(sed -n '1p' "$DEVPOD_LOG")" up 'DevPod launcher starts in the editor pane' || return

  "$TMUX_REAL" -L "$ACTIVE_SOCKET" new-session -d -s editor-ambiguous -n shell -c "$ROOT" 'sleep 120' || return
  "$TMUX_REAL" -L "$ACTIVE_SOCKET" new-window -d -t editor-ambiguous: -n editor -c "$ROOT" 'sleep 120' || return
  "$TMUX_REAL" -L "$ACTIVE_SOCKET" new-window -d -t editor-ambiguous: -n editor -c "$ROOT" 'sleep 120' || return
  ambiguous_source=$(
    "$TMUX_REAL" -L "$ACTIVE_SOCKET" display-message -p -t editor-ambiguous:shell '#{pane_id}'
  ) || return
  PATH="$TEST_BIN:$PATH" TMUX=$ref "$ROOT/scripts/devpod-editor.sh" host "$ambiguous_source" \
    >/dev/null 2>&1 && {
      printf 'ambiguous editor windows were accepted\n'
      return 1
    }

  "$TMUX_REAL" -L "$ACTIVE_SOCKET" new-session -d -s ssh_editor_guard -n shell -c "$ROOT" 'sleep 120' || return
  "$TMUX_REAL" -L "$ACTIVE_SOCKET" set-option -t ssh_editor_guard @ssh_host host.example || return
  ssh_source=$(
    "$TMUX_REAL" -L "$ACTIVE_SOCKET" display-message -p -t ssh_editor_guard:shell '#{pane_id}'
  ) || return
  PATH="$TEST_BIN:$PATH" TMUX=$ref "$ROOT/scripts/devpod-editor.sh" host "$ssh_source" \
    >/dev/null 2>&1 && {
      printf 'SSH session accepted a local editor window\n'
      return 1
    }
  ssh_editor_count=$(
    "$TMUX_REAL" -L "$ACTIVE_SOCKET" list-windows -t ssh_editor_guard -F '#{window_name}' |
      awk '$0 == "editor" { count++ } END { print count + 0 }'
  ) || return
  expect_equal "$ssh_editor_count" 0 'SSH guard creates no editor window' || return
  stop_active_server
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

  "$TMUX_REAL" -L "$ACTIVE_SOCKET" new-session -d -x 240 -y 40 \
    -s splits -c "$ROOT" 'sleep 120' || return
  split_pane=$("$TMUX_REAL" -L "$ACTIVE_SOCKET" display-message -p -t splits '#{pane_id}') || return
  "$TMUX_REAL" -L "$ACTIVE_SOCKET" set-option -w -t splits @no_split 1 || return
  TMUX=$ref "$ROOT/scripts/split.sh" "$split_pane" auto >/dev/null 2>&1 && {
    printf 'locked window accepted a split\n'; return 1;
  }
  expect_equal "$("$TMUX_REAL" -L "$ACTIVE_SOCKET" list-panes -t splits -F '#{pane_id}' | wc -l | tr -d ' ')" 1 \
    'locked pane count' || return
  "$TMUX_REAL" -L "$ACTIVE_SOCKET" set-option -w -u -t splits @no_split || return

  "$TMUX_REAL" -L "$ACTIVE_SOCKET" rename-window -t "$split_pane" editor || return
  TMUX=$ref "$ROOT/scripts/split.sh" "$split_pane" auto >/dev/null 2>&1 && {
    printf 'named editor window accepted a split without @no_split\n'; return 1;
  }
  expect_equal "$("$TMUX_REAL" -L "$ACTIVE_SOCKET" list-panes -t splits -F '#{pane_id}' | wc -l | tr -d ' ')" 1 \
    'named tool-window split guard' || return
  "$TMUX_REAL" -L "$ACTIVE_SOCKET" rename-window -t "$split_pane" term || return

  # The deliberately ultrawide 240x40 geometry reproduced the regression: comparing raw cell
  # dimensions split the selected right half left/right a second time. Window-relative fractions
  # must instead produce left/right -> top/bottom -> top/bottom -> left/right.
  TMUX=$ref "$ROOT/scripts/split.sh" "$split_pane" auto || return
  expect_equal "$("$TMUX_REAL" -L "$ACTIVE_SOCKET" list-panes -t splits -F '#{pane_left}' | sort -nu | wc -l | tr -d ' ')" 2 \
    'first Fibonacci split columns' || return
  expect_equal "$("$TMUX_REAL" -L "$ACTIVE_SOCKET" list-panes -t splits -F '#{pane_top}' | sort -nu | wc -l | tr -d ' ')" 1 \
    'first Fibonacci split rows' || return
  left_pane=$("$TMUX_REAL" -L "$ACTIVE_SOCKET" list-panes -t splits -F '#{pane_left} #{pane_id}' |
    sort -n | sed -n '1s/^[0-9][0-9]* //p') || return
  right_pane=$("$TMUX_REAL" -L "$ACTIVE_SOCKET" list-panes -t splits -F '#{pane_left} #{pane_id}' |
    sort -n | sed -n '$s/^[0-9][0-9]* //p') || return
  [ -n "$left_pane" ] && [ -n "$right_pane" ] || return

  TMUX=$ref "$ROOT/scripts/split.sh" "$right_pane" auto || return
  right_left=$("$TMUX_REAL" -L "$ACTIVE_SOCKET" display-message -p -t "$right_pane" '#{pane_left}') || return
  expect_equal "$("$TMUX_REAL" -L "$ACTIVE_SOCKET" list-panes -t splits -F '#{pane_left} #{pane_top}' |
    awk -v left="$right_left" '$1 == left { seen[$2] = 1 } END { for (row in seen) count++; print count + 0 }')" 2 \
    'selected right half splits into rows' || return

  TMUX=$ref "$ROOT/scripts/split.sh" "$left_pane" auto || return
  expect_equal "$("$TMUX_REAL" -L "$ACTIVE_SOCKET" list-panes -t splits -F '#{pane_left}:#{pane_top}' |
    sort -u | wc -l | tr -d ' ')" 4 'Fibonacci 2x2 grid cells' || return
  expect_equal "$("$TMUX_REAL" -L "$ACTIVE_SOCKET" list-panes -t splits -F '#{pane_left}' | sort -nu | wc -l | tr -d ' ')" 2 \
    'Fibonacci 2x2 grid columns' || return
  expect_equal "$("$TMUX_REAL" -L "$ACTIVE_SOCKET" list-panes -t splits -F '#{pane_top}' | sort -nu | wc -l | tr -d ' ')" 2 \
    'Fibonacci 2x2 grid rows' || return

  grid_pane=$("$TMUX_REAL" -L "$ACTIVE_SOCKET" list-panes -t splits \
    -F '#{pane_left} #{pane_top} #{pane_id}' | sort -n -k1,1 -k2,2 |
    sed -n '1s/^[0-9][0-9]* [0-9][0-9]* //p') || return
  [ -n "$grid_pane" ] || return
  TMUX=$ref "$ROOT/scripts/split.sh" "$grid_pane" auto || return
  expect_equal "$("$TMUX_REAL" -L "$ACTIVE_SOCKET" list-panes -t splits -F '#{pane_left}' | sort -nu | wc -l | tr -d ' ')" 3 \
    'fourth Fibonacci split adds a column' || return
  expect_equal "$("$TMUX_REAL" -L "$ACTIVE_SOCKET" list-panes -t splits -F '#{pane_top}' | sort -nu | wc -l | tr -d ' ')" 2 \
    'fourth Fibonacci split preserves rows' || return

  TMUX=$ref "$ROOT/scripts/split.sh" "$left_pane" horizontal || return
  TMUX=$ref "$ROOT/scripts/split.sh" "$right_pane" vertical || return
  expect_equal "$("$TMUX_REAL" -L "$ACTIVE_SOCKET" list-panes -t splits -F '#{pane_id}' | wc -l | tr -d ' ')" 7 \
    'all unlocked split modes' || return

  "$TMUX_REAL" -L "$ACTIVE_SOCKET" new-session -d -s tool-policy -n agent \
    -c "$ROOT" 'sleep 120' || return
  "$TMUX_REAL" -L "$ACTIVE_SOCKET" new-window -d -t tool-policy: -n editor \
    -c "$ROOT" 'sleep 120' || return
  "$TMUX_REAL" -L "$ACTIVE_SOCKET" new-window -d -t tool-policy: -n git \
    -c "$ROOT" 'sleep 120' || return
  for tool_window in agent editor git; do
    "$TMUX_REAL" -L "$ACTIVE_SOCKET" set-option -w -u -t "tool-policy:$tool_window" \
      @no_split 2>/dev/null || true
    "$TMUX_REAL" -L "$ACTIVE_SOCKET" set-option -w -t "tool-policy:$tool_window" \
      remain-on-exit off || return
  done
  TMUX=$ref "$ROOT/scripts/session-created.sh" || return
  for tool_window in agent editor git; do
    expect_equal "$("$TMUX_REAL" -L "$ACTIVE_SOCKET" show-option -wqv \
      -t "tool-policy:$tool_window" @no_split)" 1 \
      "$tool_window live split-policy repair" || return
    expect_equal "$("$TMUX_REAL" -L "$ACTIVE_SOCKET" show-option -wqv \
      -t "tool-policy:$tool_window" remain-on-exit)" on \
      "$tool_window live remain-on-exit repair" || return
  done

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
    "<-w><60%><-h><55%><-T>< palette ><-e><TMUX_PALETTE_SOURCE_PANE=%999><$ROOT/scripts/palette.sh>" \
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
    "<-w><60%><-h><55%><-T>< palette ><-e><TMUX_PALETTE_SOURCE_PANE=%999><$ROOT/scripts/palette.sh>" \
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
  expect_contains "$(binding_for prefix R)" \
    'lazygit-window.sh' 'dead git pane migrates to standalone LazyGit wrapper' || return
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
run_check 'DevPod editor window creation, reuse and guards' devpod_editor_behaviour
run_check 'dev layout palette window selection' dev_window_palette_behaviour
run_check 'dev session refresh lifecycle and failure guards' dev_refresh_behaviour
run_check 'standalone LazyGit editor routing and config isolation' lazygit_editor_behaviour
run_check 'logging, splits, status, opener and roster behaviour' pane_helpers_and_status
run_check 'mode-aware active pane frame' mode_frame_behaviour
run_check 'plugin and binding ownership' plugin_and_binding_contract

printf 'check-config: %s failure(s) across %s checks\n' "$FAILURES" "$TESTS"
[ "$FAILURES" -eq 0 ]
