#!/usr/bin/env bash
# Reads the newest cnti-testsuite results file, exports step outputs, writes a job summary
# and emits annotations for failed/errored tests. Never fails the job itself.
set -uo pipefail

if [[ -f cnti/results/latest.yml ]]; then
  file=cnti/results/latest.yml
else
  file=$(ls -1t cnti/results/cnti-testsuite-results-*.yml 2>/dev/null | head -n1 || true)
fi

if [[ -z "$file" ]]; then
  echo "::warning::No cnti-testsuite results file found"
  { echo "status=error"; echo "exit_code=${RUN_EXIT_CODE:-2}"; echo "results_file="; } >> "$GITHUB_OUTPUT"
  exit 0
fi

if ! command -v yq >/dev/null; then
  echo "::error::yq is required to parse results"
  { echo "status="; echo "exit_code=${RUN_EXIT_CODE:-2}"; echo "results_file=$file"; } >> "$GITHUB_OUTPUT"
  exit 0
fi

q() { yq -r "$1 // \"\"" "$file"; }
# Scalars on one line, anything structured (e.g. summary.criteria, a map) as compact JSON.
qj() { yq -o=json -I=0 "$1 // \"\"" "$file"; }
# GITHUB_OUTPUT needs the heredoc form for values that could contain newlines.
out() { printf '%s<<__CNTI_EOF__\n%s\n__CNTI_EOF__\n' "$1" "$2" >> "$GITHUB_OUTPUT"; }

# The process exit code is the run's verdict (0 objective met, 1 not met, 2 errored).
# The results file is written after every test, so a run that aborted part-way still
# carries the last per-test snapshot ("passed", exit_code 0): trust the file's verdict
# only when the process gave none.
if [[ -n "${RUN_EXIT_CODE:-}" ]]; then
  exit_code=$RUN_EXIT_CODE
  case "$exit_code" in 0) status=passed ;; 1) status=failed ;; *) status=error ;; esac
else
  status=$(q '.status')
  exit_code=$(q '.exit_code')
  [[ -n "$exit_code" ]] || exit_code=2
  if [[ -z "$status" ]]; then
    case "$exit_code" in 0) status=passed ;; 1) status=failed ;; *) status=error ;; esac
  fi
fi

out status "$status"
out exit_code "$exit_code"
out results_file "$file"
for k in passed max_passed essential_passed essential_max_passed total failed skipped na error points maximum_points; do
  out "$k" "$(q ".summary.$k")"
done
out criteria "$(qj .summary.criteria)"
# The run's date, from the timestamped results file name (the newest file the
# latest.yml link points at), for the evidence path.
real=$file
[[ -L "$file" ]] && real=$(readlink -f "$file")
if [[ "$(basename "$real")" =~ ([0-9]{4})([0-9]{2})([0-9]{2})-([0-9]{2})([0-9]{2})([0-9]{2}) ]]; then
  out run_date "${BASH_REMATCH[1]}-${BASH_REMATCH[2]}-${BASH_REMATCH[3]}T${BASH_REMATCH[4]}${BASH_REMATCH[5]}${BASH_REMATCH[6]}Z"
else
  out run_date "$(date -u +%Y-%m-%dT%H%M%SZ)"
fi

# message/remediation may be a string or a list of strings: flatten to one line.
STR='(. // "") | (select(tag == "!!seq") | map(tostring) | join("; ")) // tostring | sub("\n"; " ")'

# Annotations for failed / errored tests
yq -r ".items[] | select(.status == \"failed\" or .status == \"error\")
  | [.status, (.type // \"\"), (.name // \"\"), (.message | $STR), (.remediation | $STR),
     ((.impacted_resources // []) | map((.kind // \"\") + \"/\" + (.name // \"\") + ((.namespace // \"\") | (select(. != \"\") | \" (\" + . + \")\") // \"\")) | join(\", \"))]
  | @tsv" "$file" | sed "s/\t/\x1f/g" |
while IFS=$'\x1f' read -r st type name msg rem impacted; do
  level=warning; [[ "$type" == "essential" || "$st" == "error" ]] && level=error
  echo "::${level} title=cnti-testsuite ${name:-unknown} ${st}::${msg}${impacted:+ — impacted: $impacted}${rem:+ — remediation: $rem}"
done

# Job summary
case "$status" in passed) icon="✅" ;; failed) icon="❌" ;; *) icon="💥" ;; esac
{
  echo "## $icon CNTi Test Suite: $status"
  echo
  echo "| Tests passed | Essential passed | Points | Failed | Errors | Skipped | N/A |"
  echo "|---|---|---|---|---|---|---|"
  echo "| $(q .summary.passed) / $(q .summary.max_passed) | $(q .summary.essential_passed) / $(q .summary.essential_max_passed) | $(q .summary.points) / $(q .summary.maximum_points) | $(q .summary.failed) | $(q .summary.error) | $(q .summary.skipped) | $(q .summary.na) |"
  echo
  echo "<details><summary>Per-test results</summary>"
  echo
  echo "| Test | Type | Status | Message |"
  echo "|---|---|---|---|"
  yq -r ".items[] | \"| \" + (.name // \"\") + \" | \" + (.type // \"\") + \" | \" + (.status // \"\") + \" | \" + (.message | $STR | sub(\"\\|\"; \"&#124;\")) + \" |\"" "$file"
  echo
  echo "</details>"
  echo
  echo "Results file: \`$file\` (schema \`$(q .schema_version)\`)"
} >> "$GITHUB_STEP_SUMMARY"
