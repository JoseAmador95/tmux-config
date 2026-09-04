#!/bin/sh
# Shared constants and strict, read-only repository checks for bootstrap.sh --offline and
# scripts/check-runtime.sh. This file is sourced; callers choose how to report failures.

# Public values are consumed by scripts that source this library.
# shellcheck disable=SC2034
T_RUNTIME_CONTRACT_VERSION=1
T_FINGERS_VERSION=2.7.1
T_FINGERS_RELATIVE_PATH=plugins/tmux-fingers/bin/tmux-fingers
T_REQUIRED_SUBMODULES='plugins/extrakto
plugins/tmux-easy-motion
plugins/tmux-fingers
plugins/tmux-fuzzback'
T_REQUIRED_LOADERS='plugins/extrakto/extrakto.tmux
plugins/tmux-easy-motion/easy_motion.tmux
plugins/tmux-fingers/tmux-fingers.tmux
plugins/tmux-fuzzback/fuzzback.tmux'
T_CONTRACT_FAILURE=''
T_FINGERS_OBSERVED_VERSION=''

t_contract_fail() {
  T_CONTRACT_FAILURE=$1
  shift
  printf 'runtime contract: %s\n' "$*" >&2
  return 1
}

t_contract_check_checkout() {
  contract_root=$1
  command -v git >/dev/null 2>&1 ||
    t_contract_fail repository_checkout 'git is not in PATH' || return

  contract_top=$(git -C "$contract_root" rev-parse --show-toplevel 2>/dev/null) ||
    t_contract_fail repository_checkout 'repository metadata is unavailable' || return
  contract_top=$(cd "$contract_top" 2>/dev/null && pwd -P) ||
    t_contract_fail repository_checkout 'repository top level is unreadable' || return
  [ "$contract_top" = "$contract_root" ] ||
    t_contract_fail repository_checkout 'this directory is not a direct Git checkout' || return
}

t_contract_check_submodules() {
  contract_root=$1
  contract_status=$(git -C "$contract_root" submodule status --recursive 2>/dev/null) ||
    t_contract_fail submodules 'recursive submodule status is unavailable' || return

  if printf '%s\n' "$contract_status" | LC_ALL=C grep '^[+U-]' >/dev/null; then
    t_contract_fail submodules 'a recursive submodule is missing, moved, or unresolved'
    return
  fi

  for contract_path in $T_REQUIRED_SUBMODULES; do
    contract_index_entry=$(git -C "$contract_root" ls-files -s -- "$contract_path" 2>/dev/null) || {
      t_contract_fail submodules "required gitlink is unreadable: $contract_path"
      return
    }
    contract_index_count=$(printf '%s\n' "$contract_index_entry" |
      awk 'NF { count++ } END { print count + 0 }')
    contract_mode=$(printf '%s\n' "$contract_index_entry" | awk 'NR == 1 { print $1 }')
    contract_index_sha=$(printf '%s\n' "$contract_index_entry" | awk 'NR == 1 { print $2 }')
    contract_stage=$(printf '%s\n' "$contract_index_entry" | awk 'NR == 1 { print $3 }')
    contract_head_entry=$(git -C "$contract_root" ls-tree HEAD -- "$contract_path" 2>/dev/null) || {
      t_contract_fail submodules "recorded gitlink is unreadable: $contract_path"
      return
    }
    contract_head_mode=$(printf '%s\n' "$contract_head_entry" | awk 'NR == 1 { print $1 }')
    contract_head_sha=$(printf '%s\n' "$contract_head_entry" | awk 'NR == 1 { print $3 }')
    [ "$contract_index_count" -eq 1 ] && [ "$contract_mode" = 160000 ] &&
      [ "$contract_stage" = 0 ] && [ "$contract_head_mode" = 160000 ] &&
      [ "$contract_index_sha" = "$contract_head_sha" ] || {
      t_contract_fail submodules "required gitlink does not match recorded HEAD: $contract_path"
      return
    }
    contract_checkout_sha=$(git -C "$contract_root/$contract_path" rev-parse HEAD 2>/dev/null) || {
      t_contract_fail submodules "required submodule is unreadable: $contract_path"
      return
    }
    [ "$contract_checkout_sha" = "$contract_head_sha" ] || {
      t_contract_fail submodules "required submodule does not match HEAD: $contract_path"
      return
    }
    contract_matches=$(printf '%s\n' "$contract_status" |
      awk -v wanted="$contract_path" '$2 == wanted { count++ } END { print count + 0 }')
    [ "$contract_matches" -eq 1 ] || {
      t_contract_fail submodules "required submodule is not initialized exactly once: $contract_path"
      return
    }
  done

  # A matching gitlink only proves the submodule HEAD. Reject staged or tracked worktree changes as
  # well, so a locally edited loader cannot run after this strict preflight. Untracked files remain
  # ignored deliberately: custom-cloud supplies the ignored Fingers executable below its pinned
  # submodule, and check-runtime exposes that one validated artifact explicitly.
  contract_paths=$(printf '%s\n' "$contract_status" | awk '{ print $2 }')
  for contract_path in $contract_paths; do
    case "$contract_path" in
      ''|/*|../*|*/../*)
        t_contract_fail submodules 'recursive submodule status contains an unsafe path'
        return
        ;;
    esac
    contract_dirty=$(git -C "$contract_root/$contract_path" status --porcelain=v1 \
      --untracked-files=no --ignore-submodules=dirty 2>/dev/null) || {
      t_contract_fail submodules "required submodule worktree is unreadable: $contract_path"
      return
    }
    [ -z "$contract_dirty" ] || {
      t_contract_fail submodules "required submodule has tracked changes: $contract_path"
      return
    }
  done
}

t_contract_check_loaders() {
  contract_root=$1
  for contract_loader in $T_REQUIRED_LOADERS; do
    [ -f "$contract_root/$contract_loader" ] && [ -r "$contract_root/$contract_loader" ] || {
      t_contract_fail loaders "required plugin loader is missing: $contract_loader"
      return
    }
  done
}

t_contract_check_fingers() {
  contract_root=$1
  contract_binary=$contract_root/$T_FINGERS_RELATIVE_PATH
  contract_expected_dir=$contract_root/plugins/tmux-fingers/bin

  [ -f "$contract_binary" ] && [ ! -L "$contract_binary" ] && [ -x "$contract_binary" ] || {
    t_contract_fail fingers_binary \
      "repository-local tmux-fingers is not a regular executable: $T_FINGERS_RELATIVE_PATH"
    return
  }
  contract_real_dir=$(cd "$(dirname "$contract_binary")" 2>/dev/null && pwd -P) || {
    t_contract_fail fingers_binary 'repository-local tmux-fingers directory is unreadable'
    return
  }
  [ "$contract_real_dir" = "$contract_expected_dir" ] || {
    t_contract_fail fingers_binary 'repository-local tmux-fingers path resolves outside its bin directory'
    return
  }

  contract_probe=$(mktemp -d "${TMPDIR:-/tmp}/tmux-fingers-version.XXXXXX") || {
    t_contract_fail fingers_version 'cannot create the isolated tmux-fingers version probe'
    return
  }
  chmod 700 "$contract_probe" || {
    case "$contract_probe" in
      */tmux-fingers-version.*) rm -rf "$contract_probe" ;;
    esac
    t_contract_fail fingers_version 'cannot secure the isolated tmux-fingers version probe'
    return
  }
  mkdir -p "$contract_probe/home" "$contract_probe/state" "$contract_probe/cache" || {
    case "$contract_probe" in
      */tmux-fingers-version.*) rm -rf "$contract_probe" ;;
    esac
    t_contract_fail fingers_version 'cannot prepare the isolated tmux-fingers version probe'
    return
  }
  chmod 700 "$contract_probe/home" "$contract_probe/state" "$contract_probe/cache" || {
    case "$contract_probe" in
      */tmux-fingers-version.*) rm -rf "$contract_probe" ;;
    esac
    t_contract_fail fingers_version 'cannot secure the isolated tmux-fingers version probe'
    return
  }
  contract_version_output=$contract_probe/version.out
  contract_version_expected=$contract_probe/version.expected
  env -i "HOME=$contract_probe/home" "XDG_STATE_HOME=$contract_probe/state" \
    "XDG_CACHE_HOME=$contract_probe/cache" "TMPDIR=$contract_probe" \
    PATH=/usr/bin:/bin "$contract_binary" version \
    > "$contract_version_output" 2>/dev/null
  contract_version_rc=$?
  printf '%s\n' "$T_FINGERS_VERSION" > "$contract_version_expected"
  contract_version_exact=0
  if [ "$contract_version_rc" -eq 0 ] &&
     cmp -s "$contract_version_expected" "$contract_version_output"; then
    contract_version_exact=1
    T_FINGERS_OBSERVED_VERSION=$T_FINGERS_VERSION
  fi
  case "$contract_probe" in
    */tmux-fingers-version.*) rm -rf "$contract_probe" ;;
  esac
  [ "$contract_version_exact" -eq 1 ] || {
    t_contract_fail fingers_version "tmux-fingers must report version $T_FINGERS_VERSION"
    return
  }
}

t_contract_preflight() {
  contract_root=$1
  # Public failure state is consumed by the caller after this function returns.
  # shellcheck disable=SC2034
  T_CONTRACT_FAILURE=''
  T_FINGERS_OBSERVED_VERSION=''
  t_contract_check_checkout "$contract_root" || return
  t_contract_check_submodules "$contract_root" || return
  t_contract_check_loaders "$contract_root" || return
  t_contract_check_fingers "$contract_root" || return
}
