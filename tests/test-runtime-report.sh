#!/bin/sh
set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd -P) || exit 1
# shellcheck source=tests/lib/runtime-fixture.sh
. "$ROOT/tests/lib/runtime-fixture.sh"

TMP=$(mktemp -d "${TMPDIR:-/tmp}/tmux-runtime-report-test.XXXXXX") || exit 1
cleanup() { case "$TMP" in */tmux-runtime-report-test.*) rm -rf "$TMP" ;; esac; }
trap cleanup 0
trap 'exit 1' 1 2 3 15

CHECKOUT=$TMP/repo
fixture_build_repo "$CHECKOUT" || fixture_fail 'cannot build runtime checkout'
mkdir -p "$TMP/reports" "$TMP/runtime-tmp" || exit 1

# Trace only paths created by this test's checker invocations. Never scan the shared /tmp namespace.
REAL_MKTEMP=$(command -v mktemp) || fixture_fail 'mktemp is unavailable'
REAL_GIT=$(command -v git) || fixture_fail 'git is unavailable'
TRACE_BIN=$TMP/trace-bin
MKTEMP_LOG=$TMP/mktemp.log
NETWORK_LOG=$TMP/network.log
mkdir -p "$TRACE_BIN" || exit 1
: > "$MKTEMP_LOG"
: > "$NETWORK_LOG"
{
  printf '%s\n' '#!/bin/sh' 'set -u'
  # Generated wrapper variables expand when the wrapper runs.
  # shellcheck disable=SC2016
  printf '%s\n' 'created=$("$REAL_MKTEMP" "$@") || exit'
  # shellcheck disable=SC2016
  printf '%s\n' 'printf "%s\n" "$created" >> "$MKTEMP_LOG"'
  # shellcheck disable=SC2016
  printf '%s\n' 'printf "%s\n" "$created"'
} > "$TRACE_BIN/mktemp"
{
  printf '%s\n' '#!/bin/sh' 'set -u' 'case " $* " in'
  # Generated wrapper variables expand when the wrapper runs.
  # shellcheck disable=SC2016
  printf '%s\n' '  *" submodule update "*|*" fetch "*|*" clone "*|*" pull "*)'
  # shellcheck disable=SC2016
  printf '%s\n' '    printf "git %s\n" "$*" >> "$NETWORK_LOG"; exit 97 ;;'
  printf '%s\n' 'esac'
  # shellcheck disable=SC2016
  printf '%s\n' 'exec "$REAL_GIT" "$@"'
} > "$TRACE_BIN/git"
for guarded_tool in curl wget; do
  {
    printf '%s\n' '#!/bin/sh'
    printf '%s\n' "printf '$guarded_tool %s\\n' \"\$*\" >> \"\$NETWORK_LOG\""
    printf '%s\n' 'exit 97'
  } > "$TRACE_BIN/$guarded_tool"
done
chmod +x "$TRACE_BIN/mktemp" "$TRACE_BIN/git" "$TRACE_BIN/curl" "$TRACE_BIN/wget"
export REAL_MKTEMP REAL_GIT MKTEMP_LOG NETWORK_LOG

assert_exact_cleanup() {
  while IFS= read -r traced_path; do
    [ -n "$traced_path" ] || continue
    [ ! -e "$traced_path" ] || fixture_fail "checker left its exact temporary path: $traced_path"
  done < "$MKTEMP_LOG"
}

expect_cli_error() {
  cli_label=$1
  shift
  cli_mktemp_before=$(cksum "$MKTEMP_LOG")
  if PATH=$TRACE_BIN:$PATH "$CHECKOUT/scripts/check-runtime.sh" "$@" >/dev/null 2>&1; then
    fixture_fail "$cli_label was accepted"
  else
    cli_rc=$?
  fi
  [ "$cli_rc" -eq 2 ] || fixture_fail "$cli_label did not exit 2"
  [ "$(cksum "$MKTEMP_LOG")" = "$cli_mktemp_before" ] ||
    fixture_fail "$cli_label created a temporary path"
  [ ! -s "$NETWORK_LOG" ] || fixture_fail "$cli_label attempted network access"
}

# The committed fixture loader sources this file only if the smoke exposes live untracked submodule
# content. A tracked-tree exposure omits it and therefore retains the expected theme invariant.
printf '%s\n' "tmux set-option -g @thm_accent ''" > \
  "$CHECKOUT/plugins/extrakto/untracked-runtime.sh" || exit 1

version_output=$(PATH=/usr/bin:/bin "$CHECKOUT/scripts/check-runtime.sh" --contract-version) ||
  fixture_fail 'contract-version failed without the runtime PATH'
[ "$version_output" = 1 ] || fixture_fail 'contract-version output is not exactly 1'
expect_cli_error 'missing arguments'
expect_cli_error 'missing shell value' --shell
expect_cli_error 'missing report option' --shell /bin/bash
expect_cli_error 'missing shell option' --report "$TMP/reports/missing-shell.json"
expect_cli_error 'relative shell path' --shell bin/bash --report "$TMP/reports/relative-shell.json"
expect_cli_error 'relative report path' --shell /bin/bash --report relative.json
expect_cli_error 'duplicate shell option' --shell /bin/bash --shell /bin/bash \
  --report "$TMP/reports/duplicate-shell.json"
expect_cli_error 'duplicate shell option after empty value' --shell '' --shell /bin/bash \
  --report "$TMP/reports/duplicate-empty-shell.json"
expect_cli_error 'duplicate report option' --shell /bin/bash \
  --report "$TMP/reports/one.json" --report "$TMP/reports/two.json"
expect_cli_error 'duplicate report option after empty value' --shell /bin/bash \
  --report '' --report "$TMP/reports/duplicate-empty-report.json"
expect_cli_error 'unknown option' --shell /bin/bash --unknown \
  --report "$TMP/reports/unknown.json"
expect_cli_error 'help mixed with runtime options' --help --shell /bin/bash \
  --report "$TMP/reports/help-mixed.json"
expect_cli_error 'contract-version mixed with runtime options' --contract-version \
  --report "$TMP/reports/version-mixed.json"

REPORT_ONE=$TMP/reports/pass-one.json
REPORT_TWO=$TMP/reports/pass-two.json
PATH=$TRACE_BIN:$PATH TMPDIR=$TMP/runtime-tmp "$CHECKOUT/scripts/check-runtime.sh" \
  --shell /bin/bash --report "$REPORT_ONE" >/dev/null || fixture_fail 'runtime contract failed'
PATH=$TRACE_BIN:$PATH TMPDIR=$TMP/runtime-tmp "$CHECKOUT/scripts/check-runtime.sh" \
  --shell /bin/bash --report "$REPORT_TWO" >/dev/null || fixture_fail 'repeat runtime contract failed'
cmp -s "$REPORT_ONE" "$REPORT_TWO" || fixture_fail 'success reports are not deterministic'
[ "$(fixture_mode "$REPORT_ONE")" = 600 ] || fixture_fail 'success report mode is not 0600'
python3 -m json.tool "$REPORT_ONE" >/dev/null || fixture_fail 'success report is not valid JSON'
grep -F -q '"schema_version": 1' "$REPORT_ONE" || fixture_fail 'schema version is absent'
grep -F -q '"contract_version": 1' "$REPORT_ONE" || fixture_fail 'contract version is absent'
grep -F -q '"status": "pass"' "$REPORT_ONE" || fixture_fail 'success status is absent'
grep -F -q '"bash_osc133": "pass"' "$REPORT_ONE" || fixture_fail 'Bash OSC evidence is absent'
grep -F -q '"prefix_y": "pass"' "$REPORT_ONE" || fixture_fail 'prefix Y evidence is absent'
grep -F -q '"fingers_version_observed": "2.7.1"' "$REPORT_ONE" || fixture_fail 'Fingers evidence is absent'
python3 -c '
import json
import sys

with open(sys.argv[1], encoding="utf-8") as stream:
    report = json.load(stream)
assert list(report) == ["schema_version", "contract_version", "status", "checks", "evidence", "failures"]
assert list(report["checks"]) == [
    "bash_osc133", "bindings", "config", "fingers", "functions", "loaders",
    "prefix_y", "repository", "shell", "submodules", "tmux",
]
assert list(report["evidence"]) == [
    "fingers_path", "fingers_version_expected", "fingers_version_observed",
    "shell", "tmux_minimum", "tmux_version",
]
assert set(report["checks"].values()) == {"pass"}
assert report["failures"] == []
' "$REPORT_ONE" || fixture_fail 'success report does not match the exact schema-v1 shape'
! grep -F -q "$TMP" "$REPORT_ONE" || fixture_fail 'report leaked a temporary path'
! grep -E -q 'timestamp|"pid"|runtime\.sock|secret' "$REPORT_ONE" ||
  fixture_fail 'report contains forbidden evidence'
assert_exact_cleanup
[ -z "$(find "$TMP/runtime-tmp" -mindepth 1 -print -quit)" ] ||
  fixture_fail 'runtime success left TMPDIR resources behind'
[ ! -s "$NETWORK_LOG" ] || fixture_fail 'runtime success attempted network access'

# An arbitrary executable that ignores Bash flags must not satisfy --shell.
TRUE_BINARY=/usr/bin/true
[ -x "$TRUE_BINARY" ] || TRUE_BINARY=/bin/true
NON_BASH_REPORT=$TMP/reports/non-bash.json
if PATH=$TRACE_BIN:$PATH TMPDIR=$TMP/runtime-tmp "$CHECKOUT/scripts/check-runtime.sh" \
  --shell "$TRUE_BINARY" --report "$NON_BASH_REPORT" >/dev/null 2>&1; then
  fixture_fail 'runtime accepted an arbitrary non-Bash executable'
else
  non_bash_rc=$?
fi
[ "$non_bash_rc" -eq 1 ] || fixture_fail 'non-Bash executable failure did not exit 1'
grep -F -q '"shell": "fail"' "$NON_BASH_REPORT" || fixture_fail 'non-Bash failure was not reported'
grep -F -q '"config": "not_run"' "$NON_BASH_REPORT" ||
  fixture_fail 'non-Bash failure started downstream config checks'
assert_exact_cleanup

# Root worktree dirt is not executed: the smoke materializes committed files. The consuming image
# builder separately rejects a dirty checkout before invoking this health check.
cp "$CHECKOUT/tmux.conf" "$TMP/tmux.conf.clean" || exit 1
printf '%s\n' 'this is not valid tmux syntax' >> "$CHECKOUT/tmux.conf"
COMMITTED_REPORT=$TMP/reports/committed-tree.json
PATH=$TRACE_BIN:$PATH TMPDIR=$TMP/runtime-tmp "$CHECKOUT/scripts/check-runtime.sh" \
  --shell /bin/bash --report "$COMMITTED_REPORT" >/dev/null ||
  fixture_fail 'runtime exposed dirty root worktree content instead of the committed tree'
grep -F -q '"status": "pass"' "$COMMITTED_REPORT" || fixture_fail 'committed-tree report did not pass'
cp "$TMP/tmux.conf.clean" "$CHECKOUT/tmux.conf" || exit 1
assert_exact_cleanup

# Force the exact-socket kill command to fail. The checker must terminate only the numeric PID it
# captured from that server, wait for it, and still remove the disposable runtime.
REAL_TMUX=$(command -v tmux) || fixture_fail 'tmux is unavailable'
TMUX_WRAPPER_BIN=$TMP/tmux-wrapper-bin
TMUX_KILL_LOG=$TMP/kill-server.log
mkdir -p "$TMUX_WRAPPER_BIN" || exit 1
{
  printf '%s\n' '#!/bin/sh' 'set -u'
  printf '%s\n' 'case " $* " in'
  # Generated wrapper variables expand when the wrapper runs.
  # shellcheck disable=SC2016
  printf '%s\n' '  *" kill-server "*) printf "blocked\\n" >> "$TMUX_KILL_LOG"; exit 88 ;;'
  printf '%s\n' 'esac'
  # shellcheck disable=SC2016
  printf '%s\n' 'exec "$REAL_TMUX" "$@"'
} > "$TMUX_WRAPPER_BIN/tmux"
chmod +x "$TMUX_WRAPPER_BIN/tmux"
FALLBACK_REPORT=$TMP/reports/fallback.json
PATH=$TMUX_WRAPPER_BIN:$TRACE_BIN:$PATH REAL_TMUX=$REAL_TMUX TMUX_KILL_LOG=$TMUX_KILL_LOG \
  TMPDIR=$TMP/runtime-tmp "$CHECKOUT/scripts/check-runtime.sh" \
  --shell /bin/bash --report "$FALLBACK_REPORT" >/dev/null ||
  fixture_fail 'numeric PID cleanup fallback failed'
grep -F -q 'blocked' "$TMUX_KILL_LOG" || fixture_fail 'kill-server failure was not exercised'
grep -F -q '"status": "pass"' "$FALLBACK_REPORT" || fixture_fail 'fallback report did not pass'
assert_exact_cleanup
[ -z "$(find "$TMP/runtime-tmp" -mindepth 1 -print -quit)" ] ||
  fixture_fail 'PID fallback left TMPDIR resources behind'
[ ! -s "$NETWORK_LOG" ] || fixture_fail 'PID fallback attempted network access'

# Dirty tracked submodule files must fail before the isolated server starts.
DIRTY_LOADER=$CHECKOUT/plugins/extrakto/extrakto.tmux
cp "$DIRTY_LOADER" "$TMP/extrakto.clean" || exit 1
printf '%s\n' '# dirty fixture change' >> "$DIRTY_LOADER"
DIRTY_REPORT=$TMP/reports/dirty.json
if PATH=$TRACE_BIN:$PATH TMPDIR=$TMP/runtime-tmp "$CHECKOUT/scripts/check-runtime.sh" \
  --shell /bin/bash --report "$DIRTY_REPORT" >/dev/null 2>&1; then
  fixture_fail 'runtime accepted a dirty tracked submodule loader'
else
  dirty_rc=$?
fi
[ "$dirty_rc" -eq 1 ] || fixture_fail 'dirty submodule failure did not exit 1'
grep -F -q '"submodules": "fail"' "$DIRTY_REPORT" ||
  fixture_fail 'dirty submodule failure was not reported'
grep -F -q '"config": "not_run"' "$DIRTY_REPORT" ||
  fixture_fail 'dirty submodule failure started downstream config checks'
cp "$TMP/extrakto.clean" "$DIRTY_LOADER" || exit 1

# Commit a loader removal and update the parent gitlink so this is an exact pinned checkout whose
# loader prerequisite is genuinely absent (rather than merely dirty).
rm -f "$CHECKOUT/plugins/tmux-fuzzback/fuzzback.tmux"
fixture_git_commit "$CHECKOUT/plugins/tmux-fuzzback" 'remove fixture loader' || exit 1
git -C "$CHECKOUT" add plugins/tmux-fuzzback || exit 1
git -C "$CHECKOUT" -c user.name='Runtime Fixture' \
  -c user.email='runtime-fixture@example.invalid' commit -q -m 'pin missing loader' || exit 1
FAIL_REPORT=$TMP/reports/fail.json
if PATH=$TRACE_BIN:$PATH TMPDIR=$TMP/runtime-tmp "$CHECKOUT/scripts/check-runtime.sh" \
  --shell /bin/bash --report "$FAIL_REPORT" >/dev/null 2>&1; then
  fixture_fail 'runtime accepted a missing required loader'
else
  failure_rc=$?
fi
[ "$failure_rc" -eq 1 ] || fixture_fail 'contract failure did not exit 1'
[ "$(fixture_mode "$FAIL_REPORT")" = 600 ] || fixture_fail 'failure report mode is not 0600'
python3 -m json.tool "$FAIL_REPORT" >/dev/null || fixture_fail 'failure report is not valid JSON'
grep -F -q '"status": "fail"' "$FAIL_REPORT" || fixture_fail 'failure status is absent'
grep -F -q '"loaders": "fail"' "$FAIL_REPORT" || fixture_fail 'loader failure is absent'
grep -F -q '"config": "not_run"' "$FAIL_REPORT" || fixture_fail 'failure did not bound downstream checks'
grep -F -q '"failures": ["loaders"]' "$FAIL_REPORT" || fixture_fail 'failure code is unstable'
assert_exact_cleanup
[ -z "$(find "$TMP/runtime-tmp" -mindepth 1 -print -quit)" ] ||
  fixture_fail 'runtime failure left TMPDIR resources behind'
[ ! -s "$NETWORK_LOG" ] || fixture_fail 'runtime failure attempted network access'

printf 'runtime report contract: pass\n'
