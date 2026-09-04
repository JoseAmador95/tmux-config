#!/bin/sh
set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd -P) || exit 1
FUNCTIONS=$ROOT/shell/functions.sh
BASH_UNDER_TEST=/bin/bash
[ -x "$BASH_UNDER_TEST" ] || BASH_UNDER_TEST=$(command -v bash) || exit 1
TMP=$(mktemp -d "${TMPDIR:-/tmp}/tmux-bash-hooks.XXXXXX") || exit 1
cleanup() { case "$TMP" in */tmux-bash-hooks.*) rm -rf "$TMP" ;; esac; }
trap cleanup 0
trap 'exit 1' 1 2 3 15

run_bash() {
  case_name=$1
  case_body=$2
  TMUX=fixture FUNCTIONS=$FUNCTIONS "$BASH_UNDER_TEST" --noprofile --norc -ic "$case_body" \
    > "$TMP/$case_name.out" 2> "$TMP/$case_name.err"
}

# These bodies are expanded by the nested interactive Bash, not this POSIX harness.
# shellcheck disable=SC2016
scalar_case='PROMPT_COMMAND="scalar_before=kept"; debug_hits=0; trap '\''debug_hits=$((debug_hits + 1))'\'' DEBUG; . "$FUNCTIONS"; . "$FUNCTIONS"; eval "$PROMPT_COMMAND"; printf "\nSCALAR:%s:%s\n" "$scalar_before" "$debug_hits"; declare -p PROMPT_COMMAND; trap -p DEBUG; exit'
run_bash scalar "$scalar_case" || { sed 's/^/  /' "$TMP/scalar.err"; exit 1; }
grep -F -q 'SCALAR:kept:' "$TMP/scalar.out" || { echo 'scalar PROMPT_COMMAND was not preserved'; exit 1; }
[ "$(grep -o '_t_osc133_debug_spec=' "$TMP/scalar.out" | wc -l | tr -d ' ')" -eq 1 ] || {
  echo 'scalar PROMPT_COMMAND hook was duplicated'; exit 1;
}
grep -F -q '_t_osc133_preexec; debug_hits=' "$TMP/scalar.out" || {
  echo 'pre-existing DEBUG trap was not preserved'; exit 1;
}

# Drive a real interactive prompt: Bash 3.2 accepts an array but evaluates only element zero. This
# catches implementations that pass a manual `for` loop yet never emit OSC markers at an actual
# macOS prompt.
{
  printf '%s\n' 'PROMPT_COMMAND=("printf \"__ARRAY_ONE__\\n\"" "printf \"__ARRAY_TWO__\\n\"")'
  printf '%s\n' "trap 'array_debug=kept' DEBUG"
  # Expanded by the interactive Bash, not this POSIX harness.
  # shellcheck disable=SC2016
  printf '%s\n' '. "$FUNCTIONS"' '. "$FUNCTIONS"' ':'
  # shellcheck disable=SC2016
  printf '%s\n' 'printf "__ARRAY_STATE__:%s:%s\n" "${PROMPT_COMMAND[1]}" "$array_debug"'
  printf '%s\n' 'declare -p PROMPT_COMMAND' 'exit'
} > "$TMP/array.in"
TMUX=fixture FUNCTIONS=$FUNCTIONS "$BASH_UNDER_TEST" --noprofile --norc -i \
  < "$TMP/array.in" > "$TMP/array.out" 2> "$TMP/array.err" || {
    sed 's/^/  /' "$TMP/array.err"; exit 1;
  }
grep -F -q '__ARRAY_ONE__' "$TMP/array.out" || { echo 'array element zero was not preserved'; exit 1; }
grep -F -q '__ARRAY_TWO__' "$TMP/array.out" || { echo 'array element one did not run at a real prompt'; exit 1; }
grep -F -q '__ARRAY_STATE__:printf "__ARRAY_TWO__\n":kept' "$TMP/array.out" || {
  echo 'array type/entries or DEBUG trap were not preserved'; exit 1;
}
[ "$(grep -o '_t_osc133_debug_spec=' "$TMP/array.out" | wc -l | tr -d ' ')" -eq 1 ] || {
  echo 'array PROMPT_COMMAND hook was duplicated'; exit 1;
}

# Sparse arrays must not lose an existing high index. Bash <5.1 composes all actions into element
# zero because that is the only prompt entry it executes; 5.1+ appends at max-index + 1.
# shellcheck disable=SC2016
sparse_case='unset PROMPT_COMMAND; declare -a PROMPT_COMMAND; PROMPT_COMMAND[0]="sparse_zero=kept"; PROMPT_COMMAND[5]="sparse_five=kept"; . "$FUNCTIONS"; . "$FUNCTIONS"; if [ "${BASH_VERSINFO[0]}" -lt 5 ] || { [ "${BASH_VERSINFO[0]}" -eq 5 ] && [ "${BASH_VERSINFO[1]}" -lt 1 ]; }; then [[ ${PROMPT_COMMAND[0]} == *sparse_zero=kept* && ${PROMPT_COMMAND[0]} == *sparse_five=kept* && ${PROMPT_COMMAND[0]} == *_t_osc133_debug_spec=* && ${PROMPT_COMMAND[5]} == sparse_five=kept && ${#PROMPT_COMMAND[@]} -eq 2 ]]; else [[ ${PROMPT_COMMAND[0]} == sparse_zero=kept && ${PROMPT_COMMAND[5]} == sparse_five=kept && ${PROMPT_COMMAND[6]} == *_t_osc133_debug_spec=* && ${#PROMPT_COMMAND[@]} -eq 3 ]]; fi && printf "SPARSE:ok\n"; exit'
run_bash sparse "$sparse_case" || { sed 's/^/  /' "$TMP/sparse.err"; exit 1; }
grep -F -q 'SPARSE:ok' "$TMP/sparse.out" || { echo 'sparse PROMPT_COMMAND was not preserved'; exit 1; }

# shellcheck disable=SC2016
optout_case='PROMPT_COMMAND="optout=kept"; trap '\''optout_debug=kept'\'' DEBUG; T_NO_OSC133=1; . "$FUNCTIONS"; printf "OPTOUT:%s\n" "$PROMPT_COMMAND"; trap -p DEBUG; exit'
run_bash optout "$optout_case" || { sed 's/^/  /' "$TMP/optout.err"; exit 1; }
grep -F -q 'OPTOUT:optout=kept' "$TMP/optout.out" || { echo 'source-time opt-out changed PROMPT_COMMAND'; exit 1; }
grep -F -q "trap -- 'optout_debug=kept' DEBUG" "$TMP/optout.out" || {
  echo 'source-time opt-out changed DEBUG'; exit 1;
}
! grep -F -q '_t_osc133_debug_spec=' "$TMP/optout.out" || { echo 'source-time opt-out installed a hook'; exit 1; }

# An interactive Bash outside tmux must remain untouched.
# shellcheck disable=SC2016
no_tmux_case='PROMPT_COMMAND="outside=kept"; trap '\''outside_debug=kept'\'' DEBUG; TMUX=; . "$FUNCTIONS"; printf "NO_TMUX:%s\n" "$PROMPT_COMMAND"; trap -p DEBUG; exit'
run_bash no-tmux "$no_tmux_case" || { sed 's/^/  /' "$TMP/no-tmux.err"; exit 1; }
grep -F -q 'NO_TMUX:outside=kept' "$TMP/no-tmux.out" || {
  echo 'Bash outside tmux changed PROMPT_COMMAND'; exit 1;
}
grep -F -q "trap -- 'outside_debug=kept' DEBUG" "$TMP/no-tmux.out" || {
  echo 'Bash outside tmux changed DEBUG'; exit 1;
}
! grep -F -q '_t_osc133_debug_spec=' "$TMP/no-tmux.out" || {
  echo 'Bash outside tmux installed a hook'; exit 1;
}

# A non-interactive Bash inside tmux must also remain untouched.
# shellcheck disable=SC2016
noninteractive_case='PROMPT_COMMAND="batch=kept"; trap '\''batch_debug=kept'\'' DEBUG; . "$FUNCTIONS"; printf "NONINTERACTIVE:%s\n" "$PROMPT_COMMAND"; trap -p DEBUG'
TMUX=fixture FUNCTIONS=$FUNCTIONS "$BASH_UNDER_TEST" --noprofile --norc \
  -c "$noninteractive_case" > "$TMP/noninteractive.out" 2> "$TMP/noninteractive.err" || {
    sed 's/^/  /' "$TMP/noninteractive.err"; exit 1;
  }
grep -F -q 'NONINTERACTIVE:batch=kept' "$TMP/noninteractive.out" || {
  echo 'non-interactive Bash changed PROMPT_COMMAND'; exit 1;
}
grep -F -q "trap -- 'batch_debug=kept' DEBUG" "$TMP/noninteractive.out" || {
  echo 'non-interactive Bash changed DEBUG'; exit 1;
}
! grep -F -q '_t_osc133_debug_spec=' "$TMP/noninteractive.out" || {
  echo 'non-interactive Bash installed a hook'; exit 1;
}

# The installed prompt hook emits A, arms once, and the next DEBUG event emits C.
# shellcheck disable=SC2016
marks_case='PROMPT_COMMAND=""; . "$FUNCTIONS"; eval "$PROMPT_COMMAND"; :; exit'
run_bash marks "$marks_case" || { sed 's/^/  /' "$TMP/marks.err"; exit 1; }
marks_hex=$(od -An -tx1 "$TMP/marks.out" | tr -d ' \n')
case "$marks_hex" in
  *1b5d3133333b411b5c*1b5d3133333b431b5c*) ;;
  *) echo 'Bash hooks did not emit ordered OSC 133 A/C marks'; exit 1 ;;
esac

printf 'Bash OSC 133 hooks: pass\n'
