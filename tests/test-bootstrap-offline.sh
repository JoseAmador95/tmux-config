#!/bin/sh
set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd -P) || exit 1
# shellcheck source=tests/lib/runtime-fixture.sh
. "$ROOT/tests/lib/runtime-fixture.sh"

TMP=$(mktemp -d "${TMPDIR:-/tmp}/tmux-bootstrap-test.XXXXXX") || exit 1
cleanup() {
  case "$TMP" in */tmux-bootstrap-test.*) rm -rf "$TMP" ;; esac
}
trap cleanup 0
trap 'exit 1' 1 2 3 15

CHECKOUT=$TMP/repo
HOME_DIR=$TMP/home
fixture_build_repo "$CHECKOUT" || fixture_fail 'cannot build bootstrap checkout'
fixture_make_home "$HOME_DIR" "$CHECKOUT" || fixture_fail 'cannot wire fixture HOME'

REAL_GIT=$(command -v git) || fixture_fail 'git is unavailable'
NETWORK_LOG=$TMP/network.log
GUARD_BIN=$TMP/guard-bin
mkdir -p "$GUARD_BIN" || exit 1
{
  printf '%s\n' '#!/bin/sh' 'set -u'
  printf '%s\n' 'case " $* " in'
  printf '%s\n' '  *" submodule update "*|*" fetch "*|*" clone "*|*" pull "*)'
  # Generated wrapper variables expand when the wrapper runs.
  # shellcheck disable=SC2016
  printf '%s\n' '    printf "git %s\\n" "$*" >> "$NETWORK_LOG"; exit 97 ;;'
  printf '%s\n' 'esac'
  # shellcheck disable=SC2016
  printf '%s\n' 'exec "$REAL_GIT" "$@"'
} > "$GUARD_BIN/git"
for guarded_tool in curl wget; do
  {
    printf '%s\n' '#!/bin/sh'
    printf '%s\n' "printf '$guarded_tool %s\\n' \"\$*\" >> \"\$NETWORK_LOG\""
    printf '%s\n' 'exit 97'
  } > "$GUARD_BIN/$guarded_tool"
done
chmod +x "$GUARD_BIN/git" "$GUARD_BIN/curl" "$GUARD_BIN/wget"
export REAL_GIT NETWORK_LOG
: > "$NETWORK_LOG"

if ! PATH=$GUARD_BIN:$PATH HOME=$HOME_DIR SHELL=/bin/bash TMPDIR=$TMP \
  sh "$CHECKOUT/bootstrap.sh" --offline > "$TMP/bootstrap.out" 2>&1; then
  sed 's/^/  /' "$TMP/bootstrap.out" >&2
  fixture_fail 'valid offline bootstrap failed'
fi
[ ! -s "$NETWORK_LOG" ] || fixture_fail 'offline bootstrap attempted a network operation'
grep -F -q '# >>> tmux-functions >>>' "$HOME_DIR/.bashrc" ||
  fixture_fail 'offline success did not wire Bash functions'

# Re-running a complete offline bootstrap is idempotent and remains network-free.
FIRST_RC=$(cksum "$HOME_DIR/.bashrc")
if ! PATH=$GUARD_BIN:$PATH HOME=$HOME_DIR SHELL=/bin/bash TMPDIR=$TMP \
  sh "$CHECKOUT/bootstrap.sh" --offline >/dev/null 2>&1; then
  fixture_fail 'second valid offline bootstrap failed'
fi
[ "$(cksum "$HOME_DIR/.bashrc")" = "$FIRST_RC" ] ||
  fixture_fail 'second offline bootstrap changed the shell rc'
[ ! -s "$NETWORK_LOG" ] || fixture_fail 'second offline bootstrap attempted network access'

# The shared cross-shell rc takes precedence over the shell-specific fallback.
SHARED_HOME=$TMP/shared-home
fixture_make_home "$SHARED_HOME" "$CHECKOUT" || fixture_fail 'cannot wire shared-rc HOME'
mkdir -p "$SHARED_HOME/.config/sh" || exit 1
: > "$SHARED_HOME/.config/sh/rc.sh"
if ! PATH=$GUARD_BIN:$PATH HOME=$SHARED_HOME SHELL=/bin/bash TMPDIR=$TMP \
  sh "$CHECKOUT/bootstrap.sh" --offline >/dev/null 2>&1; then
  fixture_fail 'offline bootstrap with shared rc failed'
fi
grep -F -q '# >>> tmux-functions >>>' "$SHARED_HOME/.config/sh/rc.sh" ||
  fixture_fail 'offline bootstrap did not prefer the shared shell rc'
[ ! -e "$SHARED_HOME/.bashrc" ] || fixture_fail 'shared shell rc unexpectedly created .bashrc'

RC_BEFORE=$(cksum "$HOME_DIR/.bashrc")
chmod 644 "$CHECKOUT/scripts/agent.sh" || exit 1

expect_invalid_args() {
  invalid_label=$1
  shift
  if PATH=$GUARD_BIN:$PATH HOME=$HOME_DIR SHELL=/bin/bash TMPDIR=$TMP \
    sh "$CHECKOUT/bootstrap.sh" "$@" >/dev/null 2>&1; then
    fixture_fail "$invalid_label was accepted"
  else
    invalid_rc=$?
  fi
  [ "$invalid_rc" -eq 2 ] || fixture_fail "$invalid_label did not exit 2"
  [ "$(fixture_mode "$CHECKOUT/scripts/agent.sh")" = 644 ] ||
    fixture_fail "$invalid_label changed script permissions"
  [ "$(cksum "$HOME_DIR/.bashrc")" = "$RC_BEFORE" ] ||
    fixture_fail "$invalid_label changed the shell rc"
  [ ! -s "$NETWORK_LOG" ] || fixture_fail "$invalid_label attempted network access"
}

expect_invalid_args 'unknown option' --unknown-runtime-option
expect_invalid_args 'duplicate offline option' --offline --offline
expect_invalid_args 'duplicate no-plugins option' --no-plugins --no-plugins
expect_invalid_args 'help combined with another option' --help --offline
expect_invalid_args 'offline/no-plugins combination' --offline --no-plugins

# An exact gitlink does not make a dirty loader pinned. Strict offline preflight must reject tracked
# submodule changes before chmod or shell-RC mutation while still permitting the ignored artifact.
DIRTY_LOADER=$CHECKOUT/plugins/extrakto/extrakto.tmux
cp "$DIRTY_LOADER" "$TMP/extrakto.clean" || exit 1
printf '%s\n' '# dirty fixture change' >> "$DIRTY_LOADER"
if PATH=$GUARD_BIN:$PATH HOME=$HOME_DIR SHELL=/bin/bash TMPDIR=$TMP \
  sh "$CHECKOUT/bootstrap.sh" --offline >/dev/null 2>&1; then
  fixture_fail 'offline bootstrap accepted a dirty tracked submodule loader'
fi
[ "$(fixture_mode "$CHECKOUT/scripts/agent.sh")" = 644 ] ||
  fixture_fail 'dirty-submodule preflight changed script permissions'
[ "$(cksum "$HOME_DIR/.bashrc")" = "$RC_BEFORE" ] ||
  fixture_fail 'dirty-submodule preflight changed the shell rc'
cp "$TMP/extrakto.clean" "$DIRTY_LOADER" || exit 1

# Version stdout is byte-exact: a correct first line plus any suffix must fail before mutation.
FINGERS_BINARY=$CHECKOUT/plugins/tmux-fingers/bin/tmux-fingers
cp "$FINGERS_BINARY" "$TMP/tmux-fingers.clean" || exit 1
{
  printf '%s\n' '#!/bin/sh' "printf '2.7.1\\nEXTRA\\n'"
} > "$FINGERS_BINARY"
chmod +x "$FINGERS_BINARY"
if PATH=$GUARD_BIN:$PATH HOME=$HOME_DIR SHELL=/bin/bash TMPDIR=$TMP \
  sh "$CHECKOUT/bootstrap.sh" --offline >/dev/null 2>&1; then
  fixture_fail 'offline bootstrap accepted extra Fingers version output'
fi
[ "$(fixture_mode "$CHECKOUT/scripts/agent.sh")" = 644 ] ||
  fixture_fail 'version preflight changed script permissions'
[ "$(cksum "$HOME_DIR/.bashrc")" = "$RC_BEFORE" ] ||
  fixture_fail 'version preflight changed the shell rc'
cp "$TMP/tmux-fingers.clean" "$FINGERS_BINARY" || exit 1
chmod +x "$FINGERS_BINARY"

chmod 644 "$FINGERS_BINARY" || exit 1
if PATH=$GUARD_BIN:$PATH HOME=$HOME_DIR SHELL=/bin/bash TMPDIR=$TMP \
  sh "$CHECKOUT/bootstrap.sh" --offline >/dev/null 2>&1; then
  fixture_fail 'offline bootstrap accepted a non-executable Fingers binary'
fi
[ "$(fixture_mode "$CHECKOUT/scripts/agent.sh")" = 644 ] ||
  fixture_fail 'non-executable Fingers preflight changed script permissions'
[ "$(cksum "$HOME_DIR/.bashrc")" = "$RC_BEFORE" ] ||
  fixture_fail 'non-executable Fingers preflight changed the shell rc'
chmod +x "$FINGERS_BINARY" || exit 1

rm -f "$FINGERS_BINARY"
ln -s "$TMP/tmux-fingers.clean" "$FINGERS_BINARY" || exit 1
if PATH=$GUARD_BIN:$PATH HOME=$HOME_DIR SHELL=/bin/bash TMPDIR=$TMP \
  sh "$CHECKOUT/bootstrap.sh" --offline >/dev/null 2>&1; then
  fixture_fail 'offline bootstrap accepted a symlinked Fingers binary'
fi
[ "$(fixture_mode "$CHECKOUT/scripts/agent.sh")" = 644 ] ||
  fixture_fail 'symlinked Fingers preflight changed script permissions'
[ "$(cksum "$HOME_DIR/.bashrc")" = "$RC_BEFORE" ] ||
  fixture_fail 'symlinked Fingers preflight changed the shell rc'
rm -f "$FINGERS_BINARY"
cp "$TMP/tmux-fingers.clean" "$FINGERS_BINARY" || exit 1
chmod +x "$FINGERS_BINARY" || exit 1

rm -f "$CHECKOUT/plugins/tmux-fingers/bin/tmux-fingers"
# A PATH binary must not satisfy the repository-local production contract.
cp "$ROOT/tests/fixtures/tmux-fingers" "$GUARD_BIN/tmux-fingers" || exit 1
chmod +x "$GUARD_BIN/tmux-fingers"
if PATH=$GUARD_BIN:$PATH HOME=$HOME_DIR SHELL=/bin/bash TMPDIR=$TMP \
  sh "$CHECKOUT/bootstrap.sh" --offline >/dev/null 2>&1; then
  fixture_fail 'offline bootstrap accepted a missing repository-local Fingers binary'
fi
[ "$(fixture_mode "$CHECKOUT/scripts/agent.sh")" = 644 ] ||
  fixture_fail 'failed offline preflight changed script permissions'
[ "$(cksum "$HOME_DIR/.bashrc")" = "$RC_BEFORE" ] ||
  fixture_fail 'failed offline preflight changed the shell rc'
[ ! -s "$NETWORK_LOG" ] || fixture_fail 'failed offline preflight attempted network access'

# An exact pinned submodule with its required loader genuinely removed must fail before mutation.
MISSING_CHECKOUT=$TMP/missing-fixture/repo
MISSING_HOME=$TMP/missing-fixture/home
fixture_build_repo "$MISSING_CHECKOUT" || fixture_fail 'cannot build missing-loader checkout'
rm -f "$MISSING_CHECKOUT/plugins/tmux-fuzzback/fuzzback.tmux"
fixture_git_commit "$MISSING_CHECKOUT/plugins/tmux-fuzzback" 'remove fixture loader' || exit 1
git -C "$MISSING_CHECKOUT" add plugins/tmux-fuzzback || exit 1
git -C "$MISSING_CHECKOUT" -c user.name='Runtime Fixture' \
  -c user.email='runtime-fixture@example.invalid' commit -q -m 'pin missing loader' || exit 1
fixture_make_home "$MISSING_HOME" "$MISSING_CHECKOUT" || exit 1
chmod 644 "$MISSING_CHECKOUT/scripts/agent.sh" || exit 1
if PATH=$GUARD_BIN:$PATH HOME=$MISSING_HOME SHELL=/bin/bash TMPDIR=$TMP \
  sh "$MISSING_CHECKOUT/bootstrap.sh" --offline >/dev/null 2>&1; then
  fixture_fail 'offline bootstrap accepted an exactly pinned missing loader'
fi
[ "$(fixture_mode "$MISSING_CHECKOUT/scripts/agent.sh")" = 644 ] ||
  fixture_fail 'missing-loader preflight changed script permissions'
[ ! -e "$MISSING_HOME/.bashrc" ] || fixture_fail 'missing-loader preflight changed the shell rc'
[ ! -s "$NETWORK_LOG" ] || fixture_fail 'missing-loader preflight attempted network access'

printf 'bootstrap offline contract: pass\n'
