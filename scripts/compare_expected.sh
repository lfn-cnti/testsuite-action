#!/usr/bin/env bash
# Compares the run's results with the results the adopter expects (#11): the
# file expected_results names lists the tests known not to pass, each
# {test, status, reason}; a test it doesn't list is expected to pass. The
# suite compares (cnti-testsuite compare, lfn-cnti/testsuite#2872); this puts
# its report in the job summary, as warnings and in the outputs regressions,
# improvements and changed. The badge doesn't change, and this never fails the
# job itself: on_regression: fail is enforced at the end.
#
# Environment: RESULTS_FILE, EXPECTED_RESULTS.
set -uo pipefail

out() { echo "$1=$2" >> "$GITHUB_OUTPUT"; }
none() { out regressions ""; out improvements ""; out changed ""; exit 0; }
skip() { echo "::warning::$1: the results are not compared"; none; }

[[ -n "${EXPECTED_RESULTS:-}" ]] || none
[[ -f "${RESULTS_FILE:-}" ]] || none

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

args=(compare --results-file "$RESULTS_FILE" --expected "$EXPECTED_RESULTS")
if ! cnti-testsuite "${args[@]}" --output json > "$work/report.json" 2> "$work/err"; then
  if ! cnti-testsuite help 2>/dev/null | grep -qw compare; then
    skip "this cnti-testsuite has no 'compare' (it needs a release with lfn-cnti/testsuite#2872)"
  fi
  skip "cnti-testsuite compare refused: $(grep -v '^\[' "$work/err" | tail -3 | tr '\n' ' ' | head -c 400)"
fi
cnti-testsuite "${args[@]}" > "$work/report.md" 2> /dev/null || skip "cnti-testsuite compare could not write its report"

report() { yq -p json -r "$1" "$work/report.json"; }
report '.warnings[] | "::warning::" + .'
# cut, not read: read would merge the tabs around an empty reason.
while IFS= read -r line; do
  reason=$(cut -f5 <<< "$line")
  echo "::warning::$(cut -f1 <<< "$line"): expected $(cut -f2 <<< "$line"), now $(cut -f3 <<< "$line") ($(cut -f4 <<< "$line"))${reason:+; listed because: $reason}"
done < <(report '.changes[] | [.test, .expected, .actual, .kind, .reason] | @tsv')
for list in regressions improvements changed; do out "$list" "$(report ".$list | join(\",\")")"; done

{ echo; cat "$work/report.md"; } >> "$GITHUB_STEP_SUMMARY"
echo "Compared with $EXPECTED_RESULTS: $(report '.changes | length') change(s), $(report '.regressions | length') regression(s), $(report '.improvements | length') improvement(s)"
