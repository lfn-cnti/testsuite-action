#!/usr/bin/env bash
# Completes the statement `cnti-testsuite evidence` wrote, before anything signs or
# publishes it, so the published statement is the one that was signed: the run's
# URL, and, when the bundle is published, the extra files it carries (copied into
# the bundle) and the ones withheld. Never fails the job.
#
# Inputs (environment): EVIDENCE_DIR (the bundle), EVIDENCE_REPOSITORY (set when the
# bundle is published), EVIDENCE_FILES (newline-separated extra files, relative to
# the workspace), EVIDENCE_EXCLUDE (glob patterns never published),
# GITHUB_SERVER_URL, GITHUB_REPOSITORY, GITHUB_RUN_ID.
set -uo pipefail

statement="${EVIDENCE_DIR:-}/cnti-evidence.json"
if [[ ! -f "$statement" ]]; then
  echo "::warning::Evidence: no statement at '$statement' to complete"
  exit 0
fi

# Extra files: copied into the bundle and published verbatim, unless a name
# matches an exclude pattern; the statement lists both.
published=()
withheld=()
excluded() {
  local name=$1 pattern
  while IFS= read -r pattern; do
    [[ -z "$pattern" ]] && continue
    # shellcheck disable=SC2053
    [[ "$(basename "$name")" == $pattern ]] && return 0
  done <<< "${EVIDENCE_EXCLUDE:-}"
  return 1
}
if [[ -n "${EVIDENCE_REPOSITORY:-}" ]]; then
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    if [[ ! -f "$f" ]]; then
      echo "::warning::Evidence: '$f' not found, skipped"
      continue
    fi
    if excluded "$f"; then
      withheld+=("$f")
    else
      mkdir -p "$EVIDENCE_DIR/$(dirname "$f")"
      cp "$f" "$EVIDENCE_DIR/$f"
      published+=("$f")
    fi
  done <<< "${EVIDENCE_FILES:-}"
fi

pub_json=$(printf '%s\n' "${published[@]:-}" | sed '/^$/d' | jq -R . | jq -s .)
with_json=$(printf '%s\n' "${withheld[@]:-}" | sed '/^$/d' | jq -R . | jq -s .)
run_url="${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID:-}"
jq --argjson p "$pub_json" --argjson w "$with_json" --arg u "$run_url" \
   '.predicate.cnti.published_files = $p | .predicate.cnti.withheld_files = $w | .predicate.cnti.run_url = $u' \
   "$statement" > "$statement.tmp" && mv "$statement.tmp" "$statement"
echo "Statement completed: run ${run_url}, ${#published[@]} extra file(s) in the bundle, ${#withheld[@]} withheld"
