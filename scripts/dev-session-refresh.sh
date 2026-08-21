#!/bin/sh
# Reload the canonical tmux config and restart one exact dev session in place.
# Neovim calls schedule before it exits; tmux owns the background coordinator,
# so run can wait for the editor pane to become dead without depending on it.
set -u

SCRIPTS=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P) || exit 1
SELF=$SCRIPTS/dev-session-refresh.sh
WAIT_ATTEMPTS=50
WAIT_DELAY=0.1

source_pane=''

message() {
  text="dev refresh: $*"
  if [ -n "$source_pane" ]; then
    tmux display-message -t "$source_pane" "$text" 2>/dev/null ||
      tmux display-message "$text" 2>/dev/null || true
  else
    tmux display-message "$text" 2>/dev/null || true
  fi
  printf '%s\n' "$text" >&2
}

fail() {
  message "error: $*"
  return 1
}

valid_pane_id() {
  case "$1" in
    '%'[0-9]*) digits=${1#'%'} ;;
    *) return 1 ;;
  esac
  case "$digits" in
    ''|*[!0-9]*) return 1 ;;
  esac
}

valid_session_id() {
  case "$1" in
    '$'[0-9]*) digits=${1#'$'} ;;
    *) return 1 ;;
  esac
  case "$digits" in
    ''|*[!0-9]*) return 1 ;;
  esac
}

valid_window_id() {
  case "$1" in
    '@'[0-9]*) digits=${1#'@'} ;;
    *) return 1 ;;
  esac
  case "$digits" in
    ''|*[!0-9]*) return 1 ;;
  esac
}

resolve_window() {
  wanted=$1
  tab=$(printf '\t')
  rows=$(tmux list-windows -t "$refresh_session_id" -F "#{window_id}${tab}#{window_name}" 2>/dev/null) || {
    fail "could not inspect session $refresh_session_id"
    return 1
  }
  matches=$(printf '%s\n' "$rows" | awk -F "$tab" -v wanted="$wanted" '$2 == wanted && NF == 2 { print $1 }')
  count=$(printf '%s\n' "$matches" | awk 'NF { count++ } END { print count + 0 }')
  [ "$count" -eq 1 ] || {
    fail "expected exactly one $wanted window; found $count"
    return 1
  }

  window_id=$(printf '%s\n' "$matches" | sed -n '1p')
  valid_window_id "$window_id" || {
    fail "tmux returned an invalid $wanted window id"
    return 1
  }
  panes=$(tmux list-panes -t "$window_id" -F '#{pane_id}' 2>/dev/null) || {
    fail "could not inspect $wanted window $window_id"
    return 1
  }
  count=$(printf '%s\n' "$panes" | awk 'NF { count++ } END { print count + 0 }')
  [ "$count" -eq 1 ] || {
    fail "$wanted window must contain exactly one pane; found $count"
    return 1
  }
  pane_id=$(printf '%s\n' "$panes" | sed -n '1p')
  valid_pane_id "$pane_id" || {
    fail "tmux returned an invalid $wanted pane id"
    return 1
  }
  printf '%s %s\n' "$window_id" "$pane_id"
}

preflight() {
  source_pane=$1
  valid_pane_id "$source_pane" || {
    fail 'source pane must be a tmux-generated %digits id'
    return 1
  }

  resolved_pane=$(tmux display-message -p -t "$source_pane" '#{pane_id}' 2>/dev/null) || {
    fail "source pane no longer exists: $source_pane"
    return 1
  }
  [ "$resolved_pane" = "$source_pane" ] || {
    fail 'source pane did not resolve exactly'
    return 1
  }
  refresh_session_id=$(tmux display-message -p -t "$source_pane" '#{session_id}' 2>/dev/null) || return 1
  valid_session_id "$refresh_session_id" || {
    fail 'tmux returned an invalid session id'
    return 1
  }
  refresh_source_window=$(tmux display-message -p -t "$source_pane" '#{window_id}' 2>/dev/null) || return 1
  valid_window_id "$refresh_source_window" || {
    fail 'tmux returned an invalid source window id'
    return 1
  }

  layout=$(tmux show-option -qv -t "$refresh_session_id" @layout 2>/dev/null) || layout=''
  [ "$layout" = dev ] || {
    fail 'source session does not use @layout=dev'
    return 1
  }

  refresh_root=$(tmux display-message -p -t "$refresh_session_id" '#{session_path}' 2>/dev/null) || {
    fail 'could not resolve the dev session path'
    return 1
  }
  case "$refresh_root" in
    /*) ;;
    *) fail 'dev session path is not absolute'; return 1 ;;
  esac
  [ -d "$refresh_root" ] && [ -x "$refresh_root" ] || {
    fail "dev session path is unusable: $refresh_root"
    return 1
  }

  pair=$(resolve_window agent) || return 1
  refresh_agent_window=${pair% *}
  refresh_agent_pane=${pair#* }
  pair=$(resolve_window editor) || return 1
  refresh_editor_window=${pair% *}
  refresh_editor_pane=${pair#* }
  pair=$(resolve_window git) || return 1
  refresh_git_window=${pair% *}
  refresh_git_pane=${pair#* }
  pair=$(resolve_window term) || return 1
  refresh_term_window=${pair% *}
  refresh_term_pane=${pair#* }

  [ "$source_pane" = "$refresh_editor_pane" ] &&
    [ "$refresh_source_window" = "$refresh_editor_window" ] || {
      fail 'source pane is not the unique single-pane editor window'
      return 1
    }

  devpod_active=$(tmux show-option -pqv -t "$refresh_editor_pane" @devpod_active 2>/dev/null) || devpod_active=''
  if [ "$devpod_active" = 1 ]; then
    refresh_editor_mode=devpod
  else
    refresh_editor_mode=host
  fi

  refresh_home=${HOME:-}
  case "$refresh_home" in
    /*) ;;
    *) fail 'HOME is unavailable or not absolute'; return 1 ;;
  esac
  refresh_config=$refresh_home/.config/tmux/tmux.conf
  refresh_agent=$refresh_home/.config/tmux/scripts/agent.sh
  refresh_lazygit=$refresh_home/.config/tmux/scripts/lazygit-window.sh
  refresh_devpod=$refresh_home/.config/nvim/scripts/devpod-nvim
  [ -r "$refresh_config" ] || { fail "canonical config is not readable: $refresh_config"; return 1; }
  [ -x "$refresh_agent" ] || { fail "canonical agent launcher is not executable: $refresh_agent"; return 1; }
  [ -x "$refresh_lazygit" ] || { fail "canonical LazyGit launcher is not executable: $refresh_lazygit"; return 1; }
  if [ "$refresh_editor_mode" = devpod ]; then
    [ -x "$refresh_devpod" ] || { fail "DevPod launcher is not executable: $refresh_devpod"; return 1; }
  fi
}

capture_expected() {
  expected_session_id=$refresh_session_id
  expected_root=$refresh_root
  expected_agent_window=$refresh_agent_window
  expected_agent_pane=$refresh_agent_pane
  expected_editor_window=$refresh_editor_window
  expected_editor_pane=$refresh_editor_pane
  expected_git_window=$refresh_git_window
  expected_git_pane=$refresh_git_pane
  expected_term_window=$refresh_term_window
  expected_term_pane=$refresh_term_pane
  expected_editor_mode=$refresh_editor_mode
}

same_topology() {
  preflight "$source_pane" || return 1
  [ "$refresh_session_id" = "$expected_session_id" ] &&
    [ "$refresh_root" = "$expected_root" ] &&
    [ "$refresh_agent_window" = "$expected_agent_window" ] &&
    [ "$refresh_agent_pane" = "$expected_agent_pane" ] &&
    [ "$refresh_editor_window" = "$expected_editor_window" ] &&
    [ "$refresh_editor_pane" = "$expected_editor_pane" ] &&
    [ "$refresh_git_window" = "$expected_git_window" ] &&
    [ "$refresh_git_pane" = "$expected_git_pane" ] &&
    [ "$refresh_term_window" = "$expected_term_window" ] &&
    [ "$refresh_term_pane" = "$expected_term_pane" ] &&
    [ "$refresh_editor_mode" = "$expected_editor_mode" ] || {
      fail 'dev session topology or editor mode changed during refresh'
      return 1
    }
}

editor_command() {
  if [ "$expected_editor_mode" = devpod ]; then
    printf '%s\n' 'exec ~/.config/nvim/scripts/devpod-nvim up --restore-session'
  else
    printf '%s\n' 'exec env NVIM_TMUX_REFRESH_RESTORE=1 nvim'
  fi
}

editor_identity() {
  tmux display-message -p -t "$expected_editor_pane" \
    '#{session_id}|#{window_id}|#{pane_id}|#{pane_dead}' 2>/dev/null
}

recover_editor() {
  identity=$(editor_identity) || {
    message 'editor recovery skipped because the original pane no longer exists'
    return 1
  }
  case "$identity" in
    "$expected_session_id|$expected_editor_window|$expected_editor_pane|0")
      return 0
      ;;
    "$expected_session_id|$expected_editor_window|$expected_editor_pane|1")
      recovery_command=$(editor_command)
      if tmux respawn-pane -k -t "$expected_editor_pane" -c "$expected_root" "$recovery_command"; then
        message 'recovered the editor pane with one-shot session restore'
        return 0
      fi
      message 'editor recovery respawn failed'
      return 1
      ;;
    *)
      message 'editor recovery skipped because its tmux identity changed'
      return 1
      ;;
  esac
}

fail_after_editor_exit() {
  reason=$1
  fail "$reason"
  recover_editor || true
  return 1
}

wait_for_editor_exit() {
  attempts=0
  while [ "$attempts" -lt "$WAIT_ATTEMPTS" ]; do
    identity=$(editor_identity) || {
      fail 'editor pane disappeared before it became dead'
      return 1
    }
    case "$identity" in
      "$expected_session_id|$expected_editor_window|$expected_editor_pane|1") return 0 ;;
      "$expected_session_id|$expected_editor_window|$expected_editor_pane|0") ;;
      *) fail 'editor pane identity changed before exit'; return 1 ;;
    esac
    sleep "$WAIT_DELAY"
    attempts=$((attempts + 1))
  done
  fail 'timed out waiting for the editor pane to exit'
  return 1
}

apply_tool_policy() {
  window_id=$1
  tmux set-option -w -t "$window_id" remain-on-exit on &&
    tmux set-option -w -t "$window_id" @no_split 1
}

run_refresh() {
  preflight "$source_pane" || return 1
  capture_expected
  message "waiting for editor exit in $expected_session_id"
  wait_for_editor_exit || return 1

  same_topology || {
    recover_editor || true
    return 1
  }
  message 'reloading canonical tmux config'
  tmux source-file "$refresh_config" || {
    fail_after_editor_exit 'canonical tmux config reload failed'
    return 1
  }
  same_topology || {
    recover_editor || true
    return 1
  }

  apply_tool_policy "$expected_agent_window" || {
    fail_after_editor_exit 'could not restore agent tool-window policy'
    return 1
  }
  apply_tool_policy "$expected_editor_window" || {
    fail_after_editor_exit 'could not restore editor tool-window policy'
    return 1
  }
  apply_tool_policy "$expected_git_window" || {
    fail_after_editor_exit 'could not restore git tool-window policy'
    return 1
  }

  message 'restarting agent'
  tmux respawn-pane -k -t "$expected_agent_pane" -c "$expected_root" \
    'exec ~/.config/tmux/scripts/agent.sh' || {
      fail_after_editor_exit 'agent respawn failed'
      return 1
    }
  message 'restarting git'
  tmux respawn-pane -k -t "$expected_git_pane" -c "$expected_root" \
    'exec ~/.config/tmux/scripts/lazygit-window.sh' || {
      fail_after_editor_exit 'git respawn failed'
      return 1
    }
  message 'restarting editor'
  final_editor_command=$(editor_command)
  tmux respawn-pane -k -t "$expected_editor_pane" -c "$expected_root" "$final_editor_command" || {
    fail_after_editor_exit 'editor respawn failed'
    return 1
  }
  message "refresh complete for $expected_session_id"
}

phase=${1:-}
source_pane=${2:-}
[ "$#" -eq 2 ] || {
  fail 'usage: check|schedule|run <source-pane>'
  exit 1
}

case "$phase" in
  check)
    preflight "$source_pane" || exit 1
    message "ready to refresh $refresh_session_id"
    ;;
  schedule)
    preflight "$source_pane" || exit 1
    self_quoted=$(printf '%s' "$SELF" | sed "s/'/'\\\\''/g")
    tmux run-shell -b "exec '$self_quoted' run '$source_pane'" || {
      fail 'could not schedule the server-owned refresh coordinator'
      exit 1
    }
    message "scheduled refresh for $refresh_session_id"
    ;;
  run)
    run_refresh || exit 1
    ;;
  *)
    fail 'usage: check|schedule|run <source-pane>'
    exit 1
    ;;
esac
