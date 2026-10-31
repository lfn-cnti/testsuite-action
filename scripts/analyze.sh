#!/usr/bin/env bash
# The step behind `analyze` (#21): the suite prepares the request to the model
# and checks its answer (cnti-testsuite analyze prepare / render,
# lfn-cnti/testsuite#2871); this sends the request, with the key from the
# job's secret, so the key never enters the suite, whose debug log is in the
# artifact. Provider formats, facts, expected results and rendering are all
# the suite's. Every failure is a warning: the analysis is advisory.
#
# Environment: ANALYZE_PROVIDER, ANALYZE_ENDPOINT, ANALYZE_MODEL,
# ANALYZE_API_KEY, ANALYZE_INCLUDE, ANALYZE_MAX_FACTS_KB, EXPECTED_RESULTS,
# ANALYZE_EXPECTED, RESULTS_FILE.
set -uo pipefail

skip() { echo "::warning::AI analysis skipped: $*"; exit 0; }
[[ -n "${ANALYZE_API_KEY:-}" ]] && echo "::add-mask::$ANALYZE_API_KEY"

dir=cnti/analysis
args=(analyze prepare --provider "${ANALYZE_PROVIDER:-anthropic}" --model "${ANALYZE_MODEL:-}" --dir "$dir"
  --results-file "$RESULTS_FILE" --include "${ANALYZE_INCLUDE:-facts}" --max-facts-kb "${ANALYZE_MAX_FACTS_KB:-48}")
[[ -n "${ANALYZE_ENDPOINT:-}" ]] && args+=(--endpoint "$ANALYZE_ENDPOINT")
[[ -n "${EXPECTED_RESULTS:-}" ]] && args+=(--expected "$EXPECTED_RESULTS")
[[ "${ANALYZE_EXPECTED:-false}" == "true" ]] && args+=(--analyze-expected)

mkdir -p "$dir"
cnti-testsuite "${args[@]}" > "$dir/prepare.log" 2>&1
rc=$?
grep -E '^(note|Request|No test)' "$dir/prepare.log" || true
if [[ $rc -ne 0 ]]; then
  if ! cnti-testsuite help 2>/dev/null | grep -qw analyze; then
    skip "this cnti-testsuite has no 'analyze' (it needs a release with lfn-cnti/testsuite#2873)"
  fi
  skip "cnti-testsuite analyze prepare refused: $(grep -v '^\[' "$dir/prepare.log" | tail -3 | tr '\n' ' ' | head -c 400)"
fi

if [[ -f "$dir/request.json" ]]; then
  # shellcheck source=/dev/null
  source "$dir/request.env"
  # The key goes in a header file, not on curl's command line, where other
  # processes on the runner could read it.
  work=$(mktemp -d)
  trap 'rm -rf "$work"' EXIT
  : > "$work/key.header"
  chmod 600 "$work/key.header"
  if [[ -n "${ANALYZE_API_KEY:-}" ]]; then
    printf '%s: %s%s\n' "$KEY_HEADER" "$KEY_PREFIX" "$ANALYZE_API_KEY" > "$work/key.header"
  elif [[ "${ANALYZE_PROVIDER:-anthropic}" == "anthropic" ]]; then
    skip "analyze_api_key is not set"
  fi
  # A small model on a CPU takes minutes; rate limits and server errors (529,
  # overloaded, too) get two more tries.
  send() {
    status=""
    for attempt in 1 2 3; do
      status=$(curl -sS --max-time 600 -o "$dir/response.json" -w '%{http_code}' -H @"$dir/request.headers" -H @"$work/key.header" \
        --data-binary @"$1" "$URL" 2> "$work/curl.err") || status=""
      case "$status" in
        429 | 500 | 502 | 503 | 504 | 529 | "") [[ $attempt -lt 3 ]] && sleep $((attempt * 10)) ;;
        *) break ;;
      esac
    done
  }
  send "$dir/request.json"
  # A server that refuses a field of the request gets the suite's alternative.
  if [[ "$status" == 400 && -f "$dir/request.retry.json" ]]; then
    echo "The endpoint answered 400: sending request.retry.json, the request without response_format"
    send "$dir/request.retry.json"
  fi
  [[ -n "$status" ]] || skip "the endpoint did not answer: $(head -c 300 "$work/curl.err")"
  # The suite's warnings become annotations; everything else goes to the log.
  cnti-testsuite analyze render --dir "$dir" --response "$dir/response.json" --http-status "$status" 2>> "$dir/prepare.log" |
    while IFS= read -r line; do
      case "$line" in
        "warning: "*) echo "::warning::${line#warning: }" ;;
        *) echo "$line" ;;
      esac
    done
fi

if [[ -s "$dir/analysis.md" ]]; then
  cp "$dir/analysis.md" cnti/analysis.md
  { echo; cat cnti/analysis.md; } >> "$GITHUB_STEP_SUMMARY"
  echo "file=cnti/analysis.md" >> "$GITHUB_OUTPUT"
fi
