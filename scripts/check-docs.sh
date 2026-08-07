#!/bin/sh
# check-docs.sh — assert every effective binding this config adds or overrides is documented in
# BOTH README.md and scripts/keys.sh.
#
# This is deliberately one-directional: deleting a binding still means removing its prose by hand.
# Parsing arbitrary prose back into a complete key map would create false build failures. What this
# script does prove is the useful direction: no configured key can ship without appearing in both
# user-facing lists.
#
# HOW IT DECIDES what is "ours". Two fresh isolated servers are started from /dev/null. The config
# is sourced into one of them and each table is compared as key<TAB>command pairs. Comparing the
# command is load-bearing: prefix + 0 already existed in vanilla tmux, so a key-name-only diff once
# missed that this config had replaced its command entirely. The configured server uses source-file
# rather than 'tmux -f ... new-session -d', because the latter hides parse errors when no client is
# attached to receive them.
#
# Both servers use exact sockets in a fresh temporary directory and receive the same unique SHELL
# symlink, so a host that already uses Zsh cannot hide an override back to /bin/zsh. HOME exposes
# only the checkout's tracked tmux.conf, scripts and plugins; it deliberately has neither local.conf
# nor the private tmux-work tree. Every XDG directory and TMUX_TMPDIR is temporary too, so hooks
# cannot replace the user's roster, read machine-specific state or reach the live tmux server.
#
# The docs spell keys for humans — Alt-h/j/k/l, M-1..9, prefix H/J/K/L, mouse-click — while tmux
# prints M-h, M-1, H and MouseDown1Pane. doc_spelling() lists the accepted aliases explicitly; no
# extended-regexp sed syntax is used, so the lint behaves the same with macOS's POSIX tools.
set -u

cd "$(dirname "$0")/.." || exit 1
[ -f tmux.conf ] || { echo "check-docs: run from the repo"; exit 1; }
command -v tmux >/dev/null 2>&1 || { echo "check-docs: tmux is not in PATH"; exit 1; }

ROOT=$(pwd -P)
# Unix-domain socket paths are short (104 bytes on macOS), so do not nest this under macOS's long
# per-user $TMPDIR. /tmp is private after mktemp creates the directory and works on macOS/Linux.
TMP=$(mktemp -d "/tmp/tmux-docs.XXXXXX") || {
  echo "check-docs: cannot create temporary directory"
  exit 1
}
VAN="$TMP/vanilla.sock"
CFG="$TMP/configured.sock"
CHECK_HOME="$TMP/home"
CHECK_XDG_CONFIG="$TMP/xdg/config"
CHECK_XDG_CACHE="$TMP/xdg/cache"
CHECK_XDG_DATA="$TMP/xdg/data"
CHECK_STATE="$TMP/xdg/state"
CHECK_RUNTIME="$TMP/xdg/runtime"
CHECK_TMUX_RUNTIME="$TMP/tmux-runtime"
CHECK_SHELL="$TMP/native-shell"

isolated_tmux() (
  HOME="$CHECK_HOME"
  SHELL="$CHECK_SHELL"
  XDG_CONFIG_HOME="$CHECK_XDG_CONFIG"
  XDG_CACHE_HOME="$CHECK_XDG_CACHE"
  XDG_DATA_HOME="$CHECK_XDG_DATA"
  XDG_STATE_HOME="$CHECK_STATE"
  XDG_RUNTIME_DIR="$CHECK_RUNTIME"
  TMUX_TMPDIR="$CHECK_TMUX_RUNTIME"
  export HOME SHELL XDG_CONFIG_HOME XDG_CACHE_HOME XDG_DATA_HOME XDG_STATE_HOME
  export XDG_RUNTIME_DIR TMUX_TMPDIR
  unset TMUX
  exec tmux "$@"
)

# Invoked indirectly by trap.
# shellcheck disable=SC2329
cleanup() {
  isolated_tmux -S "$CFG" kill-server 2>/dev/null || :
  isolated_tmux -S "$VAN" kill-server 2>/dev/null || :
  case "$TMP" in
    /tmp/tmux-docs.*|/private/tmp/tmux-docs.*) rm -rf "$TMP" ;;
  esac
}
trap cleanup 0
trap 'exit 1' 1 2 3 15

mkdir -p "$CHECK_HOME/.config/tmux" "$CHECK_XDG_CONFIG" "$CHECK_XDG_CACHE" \
  "$CHECK_XDG_DATA" "$CHECK_STATE" "$CHECK_RUNTIME" "$CHECK_TMUX_RUNTIME" || exit 1
chmod 700 "$CHECK_HOME" "$CHECK_HOME/.config" "$CHECK_HOME/.config/tmux" \
  "$CHECK_XDG_CONFIG" "$CHECK_XDG_CACHE" "$CHECK_XDG_DATA" "$CHECK_STATE" \
  "$CHECK_RUNTIME" "$CHECK_TMUX_RUNTIME" || exit 1
ln -s /bin/sh "$CHECK_SHELL" || exit 1
[ -x "$CHECK_SHELL" ] || { echo "check-docs: temporary shell is not executable"; exit 1; }
# Do not link the checkout directory itself: a developer's ignored local.conf would then become
# part of the check. These are the only tracked paths tmux.conf needs while it is being sourced.
for path in tmux.conf scripts plugins; do
  ln -s "$ROOT/$path" "$CHECK_HOME/.config/tmux/$path" || exit 1
done

start_out=$(isolated_tmux -S "$VAN" -f /dev/null new-session -d -s doc-vanilla \
  'exec sleep 300' 2>&1) || {
  echo "check-docs: cannot start baseline tmux"
  printf '%s\n' "$start_out" | sed 's/^/  /'
  exit 1
}
start_out=$(isolated_tmux -S "$CFG" -f /dev/null new-session -d -s doc-configured \
  'exec sleep 300' 2>&1) || {
  echo "check-docs: cannot start configured tmux"
  printf '%s\n' "$start_out" | sed 's/^/  /'
  exit 1
}

source_out=$(isolated_tmux -S "$CFG" source-file \
  "$CHECK_HOME/.config/tmux/tmux.conf" 2>&1) || {
  echo "check-docs: tmux.conf failed to parse:"
  printf '%s\n' "$source_out" | sed 's/^/  /'
  exit 1
}

baseline_shell=$(isolated_tmux -S "$VAN" show-options -gv default-shell) || exit 1
configured_shell=$(isolated_tmux -S "$CFG" show-options -gv default-shell) || exit 1
[ "$baseline_shell" = "$CHECK_SHELL" ] || {
  printf 'check-docs: baseline ignored temporary SHELL: expected %s, got %s\n' \
    "$CHECK_SHELL" "$baseline_shell"
  exit 1
}
fail=0
if [ "$configured_shell" != "$baseline_shell" ]; then
  printf '  shared config changed default-shell: %s -> %s\n' \
    "$baseline_shell" "$configured_shell"
  fail=1
fi

# pairs <socket> <table> — normalized effective key<TAB>command rows.
# list-keys quotes punctuation when needed, but never puts whitespace inside a key token. Find the
# key relative to '-T <table>' so repeat flags before -T do not shift a hard-coded field number.
pairs() {
  isolated_tmux -S "$1" list-keys -T "$2" 2>/dev/null |
    awk -v table="$2" '
      {
        key_at = 0
        for (i = 1; i <= NF; i++) {
          if ($i == "-T" && $(i + 1) == table) {
            key_at = i + 2
            break
          }
        }
        if (key_at == 0 || key_at > NF) next
        key = $key_at
        sub(/^"/, "", key)
        sub(/"$/, "", key)
        command = ""
        for (i = key_at + 1; i <= NF; i++)
          command = command (command == "" ? "" : " ") $i
        print key "\t" command
      }
    ' | LC_ALL=C sort -u
}

# Lowercase ASCII and remove Markdown backticks. Alias matching below handles grouped notation;
# leaving the prose otherwise intact makes every accepted spelling visible and reviewable.
normalize_doc() {
  sed 's/`//g' "$1" | LC_ALL=C tr '[:upper:]' '[:lower:]'
}
normalize_doc README.md > "$TMP/readme"
normalize_doc scripts/keys.sh > "$TMP/keys"

# doc_spelling <table> <tmux-key> — every spelling either document may use; any one is enough.
doc_spelling() {
  table=$1
  key=$2
  low=$(printf '%s' "$key" | LC_ALL=C tr '[:upper:]' '[:lower:]')

  case "$key" in
    MouseDown1StatusRight) printf 'session pill\n' ;;
    MouseDown1Pane)        printf 'mouse-click\n' ;;
    MouseDragEnd1Pane)     printf 'mouse-drag-release\nmouse-drag\n' ;;
    M-Left)                printf 'alt-left\nalt-←\nm-left\n' ;;
    M-Right)               printf 'alt-right\nalt-→\nm-right\n' ;;
    M-h|M-j|M-k|M-l)
      printf 'alt-%s\nm-%s\nalt-h/j/k/l\nm-h/j/k/l\n' "${low#m-}" "${low#m-}" ;;
    M-[1-9])
      printf 'alt-%s\nm-%s\nalt-1..9\nalt-1…alt-9\nm-1..9\n' "${low#m-}" "${low#m-}" ;;
    M-*)
      printf 'alt-%s\nm-%s\n' "${low#m-}" "${low#m-}" ;;
    H|J|K|L)
      printf 'prefix + %s\nprefix %s\nprefix + h/j/k/l\nprefix h/j/k/l\n' "$low" "$low" ;;
    '<'|'>')
      printf 'prefix + %s\nprefix %s\nprefix < / >\nprefix + < / >\n' "$low" "$low" ;;
    '"'|\\)
      printf 'prefix + "\nprefix "\nprefix " / %%\n' ;;
    '%'|'\%')
      printf 'prefix + %%\nprefix %%\nprefix " / %%\n' ;;
    C-c) printf 'ctrl-c\nc-c\n' ;;
    *)
      case "$table" in
        prefix) printf 'prefix + %s\nprefix %s\n' "$low" "$low" ;;
        *)      printf '%s\n' "$low" ;;
      esac
      ;;
  esac
}

# Plumbing is not a user-facing action. Everything else must be documented.
exempt() {
  table=$1
  key=$2
  case "$table:$key" in
    prefix:C-a|prefix:C-Space) return 0 ;; # send-prefix passthrough for the two leaders
    *) return 1 ;;
  esac
}

tab=$(printf '\t')
for table in prefix root copy-mode-vi off; do
  pairs "$VAN" "$table" > "$TMP/van-$table"
  pairs "$CFG" "$table" > "$TMP/cfg-$table"
  LC_ALL=C comm -13 "$TMP/van-$table" "$TMP/cfg-$table" > "$TMP/ours-$table"

  while IFS="$tab" read -r key command; do
    [ -n "$key" ] || continue
    exempt "$table" "$key" && continue
    doc_spelling "$table" "$key" > "$TMP/spellings"
    for doc in readme keys; do
      hit=0
      while IFS= read -r spelling; do
        [ -n "$spelling" ] || continue
        if grep -F -q -e "$spelling" "$TMP/$doc"; then
          hit=1
          break
        fi
      done < "$TMP/spellings"
      if [ "$hit" -eq 0 ]; then
        case "$doc" in
          readme) printf '  undocumented in README.md : [%s] %s -> %s\n' "$table" "$key" "$command" ;;
          keys)   printf '  undocumented in keys.sh   : [%s] %s -> %s\n' "$table" "$key" "$command" ;;
        esac
        fail=1
      fi
    done
  done < "$TMP/ours-$table"
done

if [ "$fail" -eq 0 ]; then
  echo "check-docs: every custom or overridden binding appears in README.md and scripts/keys.sh"
fi
exit "$fail"
