#!/bin/sh
# Validate the pinned tmux runtime on one exact disposable socket and emit schema-v1 JSON.
set -u
umask 077

ROOT=$(cd "$(dirname "$0")/.." && pwd -P) || exit 1
# shellcheck source=scripts/runtime-contract.sh
. "$ROOT/scripts/runtime-contract.sh"

usage() {
  if [ "$1" = stderr ]; then
    printf 'usage: check-runtime.sh --shell /bin/bash --report ABSOLUTE_PATH\n' >&2
    printf '       check-runtime.sh --contract-version\n' >&2
  else
    printf 'usage: check-runtime.sh --shell /bin/bash --report ABSOLUTE_PATH\n'
    printf '       check-runtime.sh --contract-version\n'
    printf '\nValidates the complete local runtime, including repository-local tmux-fingers 2.7.1.\n'
    printf 'Writes deterministic schema-v1 JSON mode 0600; it never downloads or uses the live server.\n'
  fi
}

if [ "$#" -eq 1 ] && [ "$1" = --contract-version ]; then
  printf '%s\n' "$T_RUNTIME_CONTRACT_VERSION"
  exit 0
fi
if [ "$#" -eq 1 ] && { [ "$1" = -h ] || [ "$1" = --help ]; }; then
  usage stdout
  exit 0
fi

SHELL_PATH=''
REPORT=''
SHELL_SEEN=0
REPORT_SEEN=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --shell)
      [ "$SHELL_SEEN" -eq 0 ] && [ "$#" -ge 2 ] || { usage stderr; exit 2; }
      SHELL_SEEN=1
      SHELL_PATH=$2
      shift 2 ;;
    --report)
      [ "$REPORT_SEEN" -eq 0 ] && [ "$#" -ge 2 ] || { usage stderr; exit 2; }
      REPORT_SEEN=1
      REPORT=$2
      shift 2 ;;
    *) usage stderr; exit 2 ;;
  esac
done

case "$SHELL_PATH" in
  /*) ;;
  *) usage stderr; exit 2 ;;
esac
case "$SHELL_PATH" in
  *[!A-Za-z0-9_./+-]*) usage stderr; exit 2 ;;
esac
case "$REPORT" in
  /*) ;;
  *) usage stderr; exit 2 ;;
esac

CHECK_REPOSITORY=not_run
CHECK_SUBMODULES=not_run
CHECK_LOADERS=not_run
CHECK_FINGERS=not_run
CHECK_SHELL=not_run
CHECK_TMUX=not_run
CHECK_CONFIG=not_run
CHECK_BINDINGS=not_run
CHECK_FUNCTIONS=not_run
CHECK_BASH_OSC133=not_run
CHECK_PREFIX_Y=not_run
FAILURE_CODES=''
TMUX_VERSION=''
FINGERS_VERSION=''

add_failure() {
  failure_code=$1
  case " $FAILURE_CODES " in
    *" $failure_code "*) ;;
    *) FAILURE_CODES="${FAILURE_CODES}${FAILURE_CODES:+ }$failure_code" ;;
  esac
}

version_at_least() {
  version_have=$1
  version_need_major=$2
  version_need_minor=$3
  version_major=${version_have%%.*}
  version_rest=${version_have#*.}
  version_minor=$(printf '%s' "$version_rest" | sed 's/[^0-9].*$//')
  case "$version_major:$version_minor" in
    *[!0-9:]*|:|*:) return 1 ;;
  esac
  [ "$version_major" -gt "$version_need_major" ] || {
    [ "$version_major" -eq "$version_need_major" ] &&
      [ "$version_minor" -ge "$version_need_minor" ]
  }
}

write_report() {
  if [ -n "$FAILURE_CODES" ]; then report_status=fail; else report_status=pass; fi
  report_tmp=$(mktemp "${REPORT}.tmp.XXXXXX") || {
    printf 'check-runtime: cannot create report beside %s\n' "$REPORT" >&2
    return 1
  }
  chmod 600 "$report_tmp" || {
    rm -f "$report_tmp"
    printf 'check-runtime: cannot secure report file\n' >&2
    return 1
  }
  {
    printf '{\n'
    printf '  "schema_version": 1,\n'
    printf '  "contract_version": %s,\n' "$T_RUNTIME_CONTRACT_VERSION"
    printf '  "status": "%s",\n' "$report_status"
    printf '  "checks": {\n'
    printf '    "bash_osc133": "%s",\n' "$CHECK_BASH_OSC133"
    printf '    "bindings": "%s",\n' "$CHECK_BINDINGS"
    printf '    "config": "%s",\n' "$CHECK_CONFIG"
    printf '    "fingers": "%s",\n' "$CHECK_FINGERS"
    printf '    "functions": "%s",\n' "$CHECK_FUNCTIONS"
    printf '    "loaders": "%s",\n' "$CHECK_LOADERS"
    printf '    "prefix_y": "%s",\n' "$CHECK_PREFIX_Y"
    printf '    "repository": "%s",\n' "$CHECK_REPOSITORY"
    printf '    "shell": "%s",\n' "$CHECK_SHELL"
    printf '    "submodules": "%s",\n' "$CHECK_SUBMODULES"
    printf '    "tmux": "%s"\n' "$CHECK_TMUX"
    printf '  },\n'
    printf '  "evidence": {\n'
    printf '    "fingers_path": "%s",\n' "$T_FINGERS_RELATIVE_PATH"
    printf '    "fingers_version_expected": "%s",\n' "$T_FINGERS_VERSION"
    printf '    "fingers_version_observed": "%s",\n' "$FINGERS_VERSION"
    printf '    "shell": "bash",\n'
    printf '    "tmux_minimum": "3.4",\n'
    printf '    "tmux_version": "%s"\n' "$TMUX_VERSION"
    printf '  },\n'
    printf '  "failures": ['
    report_separator=''
    for report_failure in $FAILURE_CODES; do
      printf '%s"%s"' "$report_separator" "$report_failure"
      report_separator=', '
    done
    printf ']\n'
    printf '}\n'
  } > "$report_tmp" || {
    rm -f "$report_tmp"
    printf 'check-runtime: cannot write report\n' >&2
    return 1
  }
  chmod 600 "$report_tmp" || { rm -f "$report_tmp"; return 1; }
  mv -f "$report_tmp" "$REPORT" || {
    rm -f "$report_tmp"
    printf 'check-runtime: cannot publish report\n' >&2
    return 1
  }
}

if t_contract_check_checkout "$ROOT"; then
  CHECK_REPOSITORY=pass
else
  CHECK_REPOSITORY=fail
  add_failure repository_checkout
fi
if [ "$CHECK_REPOSITORY" = pass ]; then
  if t_contract_check_submodules "$ROOT"; then
    CHECK_SUBMODULES=pass
  else
    CHECK_SUBMODULES=fail
    add_failure submodules
  fi
fi
if [ "$CHECK_SUBMODULES" = pass ]; then
  if t_contract_check_loaders "$ROOT"; then
    CHECK_LOADERS=pass
  else
    CHECK_LOADERS=fail
    add_failure loaders
  fi
  if t_contract_check_fingers "$ROOT"; then
    CHECK_FINGERS=pass
    FINGERS_VERSION=$T_FINGERS_OBSERVED_VERSION
  else
    CHECK_FINGERS=fail
    add_failure "$T_CONTRACT_FAILURE"
  fi
fi

# Require observable Bash identity, not merely a zero exit from an arbitrary executable that
# ignores --noprofile/--norc/-c. The reported version is deliberately not persisted.
shell_probe=''
if [ -f "$SHELL_PATH" ] && [ -x "$SHELL_PATH" ]; then
  # The expression is evaluated by the requested shell.
  # shellcheck disable=SC2016
  shell_probe=$(env -i PATH=/usr/bin:/bin "$SHELL_PATH" --noprofile --norc -c \
    'if [ -n "${BASH_VERSION:-}" ]; then printf "bash:%s\n" "$BASH_VERSION"; fi' 2>/dev/null)
fi
case "$shell_probe" in
  bash:?*)
    CHECK_SHELL=pass
    ;;
  *)
    CHECK_SHELL=fail
    add_failure bash_shell
    ;;
esac

TMUX_REAL=$(command -v tmux 2>/dev/null || true)
if [ -n "$TMUX_REAL" ]; then
  tmux_raw_version=$("$TMUX_REAL" -V 2>/dev/null || true)
  tmux_candidate=$(printf '%s\n' "$tmux_raw_version" | awk 'NR == 1 { print $2 }')
  if version_at_least "$tmux_candidate" 3 4; then
    CHECK_TMUX=pass
    TMUX_VERSION=$(printf '%s' "$tmux_candidate" | LC_ALL=C tr -cd 'A-Za-z0-9._+-' | cut -c1-32)
  else
    CHECK_TMUX=fail
    add_failure tmux_version
  fi
else
  CHECK_TMUX=fail
  add_failure tmux_missing
fi

RUNTIME_TMP=''
SOCKET=''
TMUX_STARTED=0
SERVER_PID=''

server_pid_alive() {
  case "$SERVER_PID" in ''|*[!0-9]*) return 1 ;; esac
  kill -0 "$SERVER_PID" 2>/dev/null
}

wait_for_server_exit() {
  cleanup_attempt=0
  while [ "$cleanup_attempt" -lt 30 ]; do
    server_pid_alive || return 0
    cleanup_attempt=$((cleanup_attempt + 1))
    sleep 0.1
  done
  return 1
}

runtime_cleanup_resources() {
  cleanup_failed=0
  if [ "$TMUX_STARTED" -eq 1 ]; then
    if "$TMUX_REAL" -S "$SOCKET" kill-server >/dev/null 2>&1; then
      cleanup_socket_rc=0
    else
      cleanup_socket_rc=$?
    fi
    case "$SERVER_PID" in
      ''|*[!0-9]*) [ "$cleanup_socket_rc" -eq 0 ] || cleanup_failed=1 ;;
      *)
        if ! wait_for_server_exit; then
          # SERVER_PID came from this exact -S server immediately after startup. Never use a name,
          # pattern, process scan or ambient socket as fallback.
          kill -TERM "$SERVER_PID" 2>/dev/null || :
          wait_for_server_exit || {
            kill -KILL "$SERVER_PID" 2>/dev/null || :
            wait_for_server_exit || cleanup_failed=1
          }
        fi
        ;;
    esac
    if [ "$cleanup_failed" -eq 0 ]; then
      TMUX_STARTED=0
    else
      printf 'check-runtime: exact tmux server %s did not terminate; preserving %s\n' \
        "$SERVER_PID" "$RUNTIME_TMP" >&2
    fi
  fi
  if [ "$cleanup_failed" -eq 0 ]; then
    case "$RUNTIME_TMP" in
      */tmux-runtime.*) rm -rf "$RUNTIME_TMP" ;;
    esac
    RUNTIME_TMP=''
    SOCKET=''
    SERVER_PID=''
  fi
  [ "$cleanup_failed" -eq 0 ]
}

# Invoked indirectly by traps.
# shellcheck disable=SC2317,SC2329
runtime_cleanup() {
  cleanup_rc=$?
  trap - 0 1 2 3 15
  if ! runtime_cleanup_resources && [ "$cleanup_rc" -eq 0 ]; then
    cleanup_rc=1
  fi
  exit "$cleanup_rc"
}
trap runtime_cleanup 0
trap 'exit 129' 1
trap 'exit 130' 2
trap 'exit 131' 3
trap 'exit 143' 15

isolated_tmux() (
  HOME=$CHECK_HOME
  SHELL=$SHELL_PATH
  PATH=$RUNTIME_PATH
  XDG_CONFIG_HOME=$CHECK_XDG_CONFIG
  XDG_CACHE_HOME=$CHECK_XDG_CACHE
  XDG_DATA_HOME=$CHECK_XDG_DATA
  XDG_STATE_HOME=$CHECK_XDG_STATE
  XDG_RUNTIME_DIR=$CHECK_XDG_RUNTIME
  TMUX_TMPDIR=$CHECK_TMUX_RUNTIME
  TMPDIR=$CHECK_TMP
  export HOME SHELL PATH XDG_CONFIG_HOME XDG_CACHE_HOME XDG_DATA_HOME XDG_STATE_HOME
  export XDG_RUNTIME_DIR TMUX_TMPDIR TMPDIR
  unset TMUX
  exec "$TMUX_REAL" -S "$SOCKET" "$@"
)

expose_tracked_config() {
  # Materialize the committed root tree rather than linking back into the mutable checkout. This
  # prevents a root-file TOCTOU change from entering the smoke after repository validation. Git
  # archives omit gitlink contents; those are materialized independently from their exact SHAs.
  tracked_root_archive=$RUNTIME_TMP/root-config.tar
  git -C "$ROOT" archive --format=tar HEAD > "$tracked_root_archive" || return
  tar -xf "$tracked_root_archive" -C "$CONFIG_EXPOSURE" || return

  # Materialize every recursively pinned submodule from its committed Git tree. A directory symlink
  # would expose dirty or untracked plugin content from the live checkout even though its gitlink is
  # exact. The only untracked exception is the separately validated Fingers executable copied below.
  git -C "$ROOT" submodule status --recursive > "$RUNTIME_TMP/submodules" || return
  tracked_archive_index=0
  while read -r tracked_sha tracked_plugin _; do
    [ -n "$tracked_sha" ] && [ -n "$tracked_plugin" ] || return 1
    case "$tracked_sha" in *[!0-9A-Fa-f]*) return 1 ;; esac
    case "$tracked_plugin" in /*|../*|*/../*) return 1 ;; esac
    tracked_parent=${tracked_plugin%/*}
    mkdir -p "$CONFIG_EXPOSURE/$tracked_parent" || return
    mkdir -p "$CONFIG_EXPOSURE/$tracked_plugin" || return
    tracked_archive_index=$((tracked_archive_index + 1))
    tracked_archive=$RUNTIME_TMP/submodule-$tracked_archive_index.tar
    git -C "$ROOT/$tracked_plugin" archive --format=tar "$tracked_sha" > "$tracked_archive" || return
    tar -xf "$tracked_archive" -C "$CONFIG_EXPOSURE/$tracked_plugin" || return
  done < "$RUNTIME_TMP/submodules"

  tracked_fingers_parent=${T_FINGERS_RELATIVE_PATH%/*}
  mkdir -p "$CONFIG_EXPOSURE/$tracked_fingers_parent" || return
  cp "$ROOT/$T_FINGERS_RELATIVE_PATH" "$CONFIG_EXPOSURE/$T_FINGERS_RELATIVE_PATH" || return
  chmod 700 "$CONFIG_EXPOSURE/$T_FINGERS_RELATIVE_PATH" || return
}

binding_for() {
  binding_table=$1
  binding_key=$2
  isolated_tmux list-keys -T "$binding_table" 2>/dev/null |
    awk -v table="$binding_table" -v wanted="$binding_key" '
      {
        for (i = 1; i <= NF; i++) {
          if ($i == "-T" && $(i + 1) == table) {
            key = $(i + 2)
            sub(/^"/, "", key)
            sub(/"$/, "", key)
            if (key == wanted) { print; exit }
          }
        }
      }
    '
}

wait_for_capture() {
  wait_pane=$1
  wait_pattern=$2
  wait_attempt=0
  while [ "$wait_attempt" -lt 80 ]; do
    isolated_tmux capture-pane -p -S -100 -t "$wait_pane" 2>/dev/null |
      grep -E "$wait_pattern" >/dev/null && return 0
    wait_attempt=$((wait_attempt + 1))
    sleep 0.1
  done
  return 1
}

prerequisites_ready=1
for prerequisite in "$CHECK_REPOSITORY" "$CHECK_SUBMODULES" "$CHECK_LOADERS" \
  "$CHECK_FINGERS" "$CHECK_SHELL" "$CHECK_TMUX"; do
  [ "$prerequisite" = pass ] || prerequisites_ready=0
done

if [ "$prerequisites_ready" -eq 1 ]; then
  # Unix-domain sockets are limited to 104 bytes on macOS. Keep the exact -S socket under the
  # deliberately short /tmp path even when TMPDIR is a long per-user directory.
  RUNTIME_TMP=$(mktemp -d "/tmp/tmux-runtime.XXXXXX") || {
    add_failure temporary_runtime
    prerequisites_ready=0
  }
  if [ "$prerequisites_ready" -eq 1 ]; then
    chmod 700 "$RUNTIME_TMP" || {
      add_failure temporary_runtime
      prerequisites_ready=0
    }
  fi
fi

if [ "$prerequisites_ready" -eq 1 ]; then
  CHECK_HOME=$RUNTIME_TMP/home
  CHECK_XDG_CONFIG=$RUNTIME_TMP/xdg/config
  CHECK_XDG_CACHE=$RUNTIME_TMP/xdg/cache
  CHECK_XDG_DATA=$RUNTIME_TMP/xdg/data
  CHECK_XDG_STATE=$RUNTIME_TMP/xdg/state
  CHECK_XDG_RUNTIME=$RUNTIME_TMP/xdg/runtime
  CHECK_TMUX_RUNTIME=$RUNTIME_TMP/tmux-runtime
  CHECK_TMP=$RUNTIME_TMP/tmp
  CONFIG_EXPOSURE=$CHECK_HOME/.config/tmux
  RUNTIME_BIN=$RUNTIME_TMP/bin
  RUNTIME_PATH=$RUNTIME_BIN:/usr/bin:/bin:/usr/sbin:/sbin
  SOCKET=$RUNTIME_TMP/runtime.sock
  mkdir -p "$CONFIG_EXPOSURE" "$CHECK_XDG_CONFIG" "$CHECK_XDG_CACHE" "$CHECK_XDG_DATA" \
    "$CHECK_XDG_STATE" "$CHECK_XDG_RUNTIME" "$CHECK_TMUX_RUNTIME" "$CHECK_TMP" "$RUNTIME_BIN" ||
    add_failure temporary_runtime
  chmod 700 "$CHECK_HOME" "$CHECK_HOME/.config" "$CONFIG_EXPOSURE" "$CHECK_XDG_CONFIG" \
    "$CHECK_XDG_CACHE" "$CHECK_XDG_DATA" "$CHECK_XDG_STATE" "$CHECK_XDG_RUNTIME" \
    "$CHECK_TMUX_RUNTIME" "$CHECK_TMP" "$RUNTIME_BIN" 2>/dev/null || add_failure temporary_runtime
  ln -s "$TMUX_REAL" "$RUNTIME_BIN/tmux" 2>/dev/null || add_failure temporary_runtime
  expose_tracked_config || add_failure tracked_exposure
fi

if [ "$prerequisites_ready" -eq 1 ] && [ -z "$FAILURE_CODES" ]; then
  start_out=$(isolated_tmux -f /dev/null new-session -d -s runtime -c "$CHECK_HOME" \
    'exec sleep 300' 2>&1)
  start_rc=$?
  if [ "$start_rc" -eq 0 ]; then
    TMUX_STARTED=1
    SERVER_PID=$(isolated_tmux display-message -p '#{pid}' 2>/dev/null || true)
    case "$SERVER_PID" in
      ''|*[!0-9]*) source_out='server PID is unavailable'; source_rc=1 ;;
      *) source_out=$(isolated_tmux source-file "$CONFIG_EXPOSURE/tmux.conf" 2>&1); source_rc=$? ;;
    esac
  else
    source_out=$start_out
    source_rc=$start_rc
  fi

  if [ "$source_rc" -eq 0 ]; then
    # Reload is the supported migration path for a long-lived server. Validate idempotence here,
    # including cleanup of stale keys/options, rather than accepting a first-source-only runtime.
    source_out=$(isolated_tmux source-file "$CONFIG_EXPOSURE/tmux.conf" 2>&1)
    source_rc=$?
  fi

  if [ "$source_rc" -eq 0 ]; then
    config_ok=1
    [ "$(isolated_tmux show-options -gqv default-command)" = '' ] || config_ok=0
    [ "$(isolated_tmux show-options -gqv default-shell)" = "$SHELL_PATH" ] || config_ok=0
    [ "$(isolated_tmux show-options -gqv default-terminal)" = tmux-256color ] || config_ok=0
    terminal_features=$(isolated_tmux show-options -sv terminal-features)
    terminal_feature_count=$(printf '%s\n' "$terminal_features" | tr ',' '\n' | awk '
      $0 == "xterm-ghostty:RGB:sync" { count++ }
      END { print count + 0 }
    ')
    [ "$terminal_feature_count" -eq 1 ] || config_ok=0
    [ "$(isolated_tmux show-options -gqv status-interval)" = 0 ] || config_ok=0
    status_right=$(isolated_tmux show-options -gqv status-right)
    case "$status_right" in
      *'#{@pill}'*'#{@pill_ink}'*'#{q/h:session_name}'*) ;;
      *) config_ok=0 ;;
    esac
    case "$status_right" in *'#('*|*'@session_strip'*) config_ok=0 ;; esac
    theme_names='rosewater flamingo pink mauve red maroon peach yellow green teal sky sapphire blue lavender
                 text subtext1 subtext0 overlay2 overlay1 overlay0 surface2 surface1 surface0 base mantle crust
                 flavor accent urgent attention activity current_search dim line dead card chip sel_bg sel_fg ink
                 urgent_ink attention_ink activity_ink current_search_ink ssh_tints'
    for theme_name in $theme_names; do
      [ -n "$(isolated_tmux show-options -gqv "@thm_$theme_name")" ] || config_ok=0
    done
    fingers_cli=$(isolated_tmux show-options -gqv @fingers-cli)
    case "$fingers_cli" in
      "$CONFIG_EXPOSURE/plugins/tmux-fingers/bin/tmux-fingers"*) ;;
      *) config_ok=0 ;;
    esac
    if version_at_least "$TMUX_VERSION" 3 6; then
      [ "$(isolated_tmux show-options -wgv pane-scrollbars)" = off ] || config_ok=0
      runtime_pane=$(isolated_tmux display-message -p -t runtime '#{pane_id}')
      normal_width=$(isolated_tmux display-message -p -t "$runtime_pane" '#{pane_width}')
      isolated_tmux copy-mode -t "$runtime_pane" >/dev/null 2>&1 || config_ok=0
      copy_width=$(isolated_tmux display-message -p -t "$runtime_pane" '#{pane_width}')
      isolated_tmux send-keys -t "$runtime_pane" -X cancel >/dev/null 2>&1 || config_ok=0
      [ "$copy_width" = "$normal_width" ] || config_ok=0
      [ -n "$(isolated_tmux show-hooks -g client-light-theme 2>/dev/null)" ] || config_ok=0
    fi
    if version_at_least "$TMUX_VERSION" 3 7; then
      [ -n "$(isolated_tmux show-options -wgv tree-mode-preview-style 2>/dev/null)" ] || config_ok=0
    fi
    if [ "$config_ok" -eq 1 ]; then
      CHECK_CONFIG=pass
    else
      CHECK_CONFIG=fail
      add_failure config_invariants
    fi

    bindings_ok=1
    [ -z "$(binding_for root M-f)" ] || bindings_ok=0
    case "$(binding_for prefix f)" in *'@fingers-cli'*) ;; *) bindings_ok=0 ;; esac
    case "$(binding_for prefix J)" in *'resize-pane -D 5'*) ;; *) bindings_ok=0 ;; esac
    case "$(binding_for prefix Y)" in *'copy-last-output.sh'*) ;; *) bindings_ok=0 ;; esac
    case "$(binding_for root M-i)" in *'copy-mode'*) ;; *) bindings_ok=0 ;; esac
    mouse_click_binding=$(binding_for copy-mode-vi MouseDown1Pane)
    case "$mouse_click_binding" in *'select-pane'*'clear-selection'*) ;; *) bindings_ok=0 ;; esac
    case "$(binding_for copy-mode-vi C-o)" in *'open-selection.sh --editor'*) ;; *) bindings_ok=0 ;; esac
    if [ "$bindings_ok" -eq 1 ]; then
      CHECK_BINDINGS=pass
    else
      CHECK_BINDINGS=fail
      add_failure bindings
    fi
  else
    CHECK_CONFIG=fail
    add_failure config_parse
    printf 'check-runtime: isolated tmux config load failed:\n' >&2
    printf '%s\n' "$source_out" | sed -n '1,8p' | sed 's/^/  /' >&2
  fi
fi

if [ "$CHECK_CONFIG" = pass ]; then
  BASH_RC=$RUNTIME_TMP/bashrc
  {
    printf '%s\n' '_t_runtime_prompt_count=0'
    printf '%s\n' '_t_runtime_debug_count=0'
    # These are literal Bash rc lines; expansion belongs to the interactive pane.
    # shellcheck disable=SC2016
    printf '%s\n' 'PROMPT_COMMAND="_t_runtime_prompt_count=$((_t_runtime_prompt_count + 1))"'
    printf '%s\n' "trap '_t_runtime_debug_count=\$((_t_runtime_debug_count + 1))' DEBUG"
    printf '%s\n' 'PS1="runtime> "'
    # shellcheck disable=SC2016
    printf '%s\n' '. "$HOME/.config/tmux/shell/functions.sh"'
  } > "$BASH_RC" || add_failure bash_rc
  chmod 600 "$BASH_RC" || add_failure bash_rc

  pane=$(isolated_tmux display-message -p -t runtime:1.1 '#{pane_id}')
  bash_command="exec $SHELL_PATH --noprofile --rcfile $BASH_RC -i"
  isolated_tmux respawn-pane -k -t "$pane" "$bash_command" >/dev/null 2>&1 || add_failure bash_start
  if wait_for_capture "$pane" '^runtime>$'; then
    # This command is expanded by the interactive Bash pane.
    # shellcheck disable=SC2016
    function_probe='type t tp tssh tcopy agent >/dev/null 2>&1 && printf "__runtime_functions__:ok:%s:%s\n" "$_t_runtime_prompt_count" "$_t_runtime_debug_count"'
    isolated_tmux send-keys -l -t "$pane" "$function_probe" && isolated_tmux send-keys -t "$pane" Enter
    if wait_for_capture "$pane" '__runtime_functions__:ok:[1-9][0-9]*:[1-9][0-9]*'; then
      CHECK_FUNCTIONS=pass
    else
      CHECK_FUNCTIONS=fail
      add_failure functions
    fi

    output_probe="printf 'runtime-contract-output\\n'"
    isolated_tmux send-keys -l -t "$pane" "$output_probe" && isolated_tmux send-keys -t "$pane" Enter
    if wait_for_capture "$pane" '^runtime-contract-output$'; then
      isolated_tmux delete-buffer >/dev/null 2>&1 || :
      server_pid=$(isolated_tmux display-message -p '#{pid}')
      server_ref=$SOCKET,$server_pid,0
      HOME=$CHECK_HOME PATH=$RUNTIME_PATH XDG_CONFIG_HOME=$CHECK_XDG_CONFIG \
        XDG_CACHE_HOME=$CHECK_XDG_CACHE XDG_DATA_HOME=$CHECK_XDG_DATA \
        XDG_STATE_HOME=$CHECK_XDG_STATE XDG_RUNTIME_DIR=$CHECK_XDG_RUNTIME \
        TMUX_TMPDIR=$CHECK_TMUX_RUNTIME TMUX=$server_ref \
        "$CONFIG_EXPOSURE/scripts/copy-last-output.sh" "$pane" >/dev/null 2>&1
      prefix_rc=$?
      copied=$(isolated_tmux show-buffer 2>/dev/null || true)
      if [ "$prefix_rc" -eq 0 ] && [ "$copied" = runtime-contract-output ]; then
        CHECK_BASH_OSC133=pass
        if [ "$CHECK_BINDINGS" = pass ]; then
          CHECK_PREFIX_Y=pass
        else
          CHECK_PREFIX_Y=fail
          add_failure prefix_y
        fi
      else
        CHECK_BASH_OSC133=fail
        CHECK_PREFIX_Y=fail
        add_failure bash_osc133
        add_failure prefix_y
      fi
    else
      CHECK_BASH_OSC133=fail
      CHECK_PREFIX_Y=fail
      add_failure bash_osc133
      add_failure prefix_y
    fi
  else
    CHECK_FUNCTIONS=fail
    CHECK_BASH_OSC133=fail
    CHECK_PREFIX_Y=fail
    add_failure interactive_bash
  fi
fi

if ! runtime_cleanup_resources; then
  add_failure cleanup
fi

umask 077
if ! write_report; then
  exit 1
fi
if [ -n "$FAILURE_CODES" ]; then
  printf 'check-runtime: contract failed (%s); report: %s\n' "$FAILURE_CODES" "$REPORT" >&2
  exit 1
fi
printf 'check-runtime: contract passed; report: %s\n' "$REPORT"
