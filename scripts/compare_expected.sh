#!/usr/bin/env bash
# Compares the run's results with the results the adopter expects (#11): the
# file expected_results names lists the tests known not to pass, each
# {test, status, reason}; a test it doesn't list is expected to pass. Every
# test whose result differs is reported in the job summary and as a warning,
# and named in the outputs regressions, improvements and changed. The badge
# doesn't change, and this never fails the job itself: on_regression: fail is
# enforced at the end (enforce_expected.sh).
#
# Environment: RESULTS_FILE, EXPECTED_RESULTS.
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=plain.sh
source "$here/plain.sh"
out() { echo "$1=$2" >> "$GITHUB_OUTPUT"; }
none() { out regressions ""; out improvements ""; out changed ""; exit 0; }

[[ -n "${EXPECTED_RESULTS:-}" ]] || none
if [[ ! -f "$EXPECTED_RESULTS" ]]; then
  echo "::warning::expected_results '$EXPECTED_RESULTS' is not a file: the results are not compared"
  none
fi
[[ -f "${RESULTS_FILE:-}" ]] || none

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

if [[ "$(yq 'tag' "$EXPECTED_RESULTS" 2>/dev/null)" != "!!seq" ]] ||
   ! yq -oy -r '.[] | ((.test // "") | tostring) + "\t" + ((.status // "") | tostring) + "\t" + ((.reason // "") | tostring | sub("[\t\n]"; " "))' \
       "$EXPECTED_RESULTS" > "$work/entries.tsv" 2>/dev/null; then
  echo "::warning::expected_results '$EXPECTED_RESULTS' is not a list of {test, status, reason}: the results are not compared"
  none
fi
# An entry without a status a results file has (a missing one, a misspelled
# key, a typo) says the test is known but not how: that test is not compared,
# so a known failure is never taken for a regression.
: > "$work/expected.tsv"
: > "$work/uncompared.txt"
# cut, not read: read would merge the tabs around an empty field.
while IFS= read -r line; do
  test=$(cut -f1 <<< "$line") status=$(cut -f2 <<< "$line") reason=$(cut -f3 <<< "$line")
  if [[ -z "$test" ]]; then
    echo "::warning::expected_results has an entry without a test: it is ignored"
    continue
  fi
  case "$status" in
    passed | failed | skipped | na | error) printf '%s\t%s\t%s\n' "$test" "$status" "$reason" >> "$work/expected.tsv" ;;
    *)
      echo "::warning::expected_results lists $test without a status of a results file (passed, failed, skipped, na, error; it has '$status'): $test is not compared"
      echo "$test" >> "$work/uncompared.txt"
      ;;
  esac
done < "$work/entries.tsv"

yq -r '.items[] | .name + "\t" + .status' "$RESULTS_FILE" > "$work/results.tsv" 2>/dev/null || none

regressions=() improvements=() changed=() rows=()
while IFS=$'\t' read -r test now; do
  [[ -n "$test" ]] || continue
  grep -qxF -- "$test" "$work/uncompared.txt" && continue
  entry=$(awk -F'\t' -v t="$test" '$1 == t { print; exit }' "$work/expected.tsv")
  expected=passed reason=""
  if [[ -n "$entry" ]]; then
    expected=$(cut -f2 <<< "$entry")
    reason=$(cut -f3 <<< "$entry")
  fi
  [[ "$now" == "$expected" ]] && continue
  changed+=("$test")
  if [[ "$now" == failed || "$now" == error ]] && [[ "$expected" != failed && "$expected" != error ]]; then
    regressions+=("$test")
    kind="regression"
  elif [[ "$now" == passed ]]; then
    improvements+=("$test")
    kind="improvement: remove its entry"
  else
    kind="changed"
  fi
  echo "::warning::$test: expected $expected, now $now ($kind)"
  rows+=("| \`$(plain "$test")\` | $(plain "$expected") | **$(plain "$now")** | $kind${reason:+; listed because: $(plain "$reason")} |")
done < "$work/results.tsv"

join_by() { local IFS=,; echo "$*"; }
out regressions "$(join_by "${regressions[@]}")"
out improvements "$(join_by "${improvements[@]}")"
out changed "$(join_by "${changed[@]}")"

run=$(wc -l < "$work/results.tsv" | tr -d ' ')
{
  echo
  echo "### Compared with the expected results (\`$(plain "$EXPECTED_RESULTS")\`)"
  echo
  if [[ ${#rows[@]} -eq 0 ]]; then
    echo "Every one of the $run tests has the result the file expects."
  else
    echo "${#changed[@]} of the $run tests differ from the file: ${#regressions[@]} regression(s), ${#improvements[@]} improvement(s). A test the file doesn't list is expected to pass."
    echo
    echo "| Test | Expected | Now | |"
    echo "|---|---|---|---|"
    printf '%s\n' "${rows[@]}"
  fi
} >> "$GITHUB_STEP_SUMMARY"
echo "Compared with $EXPECTED_RESULTS: ${#changed[@]} change(s), ${#regressions[@]} regression(s), ${#improvements[@]} improvement(s)"
