#!/usr/bin/env bash
# Completes the statement `cnti-testsuite evidence` wrote, before anything signs or
# publishes it, so the published statement is the one that was signed: the run's
# URL, and, when the bundle is published, the extra files it carries (copied into
# the bundle) and the ones withheld. Never fails the job; sets the output
# completed=true once the statement is complete, which the steps that sign,
# attach, upload or publish it require.
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
workspace=$(readlink -f -- "${GITHUB_WORKSPACE:-.}")
if [[ -n "${EVIDENCE_REPOSITORY:-}" ]]; then
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    # The bundle's own files stay the suite's: an entry may neither point
    # outside the bundle nor replace one of its files (the statement, the
    # badge, the results file, the configuration).
    if [[ "$f" == /* || "/$f/" == */../* ]]; then
      echo "::warning::Evidence: '$f' is outside the workspace, skipped (evidence_files are paths relative to it)"
      continue
    fi
    if [[ ! -f "$f" ]]; then
      echo "::warning::Evidence: '$f' not found, skipped"
      continue
    fi
    # A symlink is published as its target: only a target in the workspace.
    target=$(readlink -f -- "$f" 2> /dev/null || true)
    if [[ -z "$target" || "$target" != "$workspace"/* ]]; then
      echo "::warning::Evidence: '$f' leads outside the workspace (${target:-unresolved}), skipped"
      continue
    fi
    if [[ -e "$EVIDENCE_DIR/$f" ]]; then
      echo "::warning::Evidence: '$f' would replace the bundle's own $f, skipped"
      continue
    fi
    if excluded "$f"; then
      withheld+=("$f")
    # Listed only once it is in the bundle: a path through one of the
    # bundle's files (cnti-evidence.json/x) cannot be.
    elif mkdir -p "$EVIDENCE_DIR/$(dirname "$f")" 2> /dev/null && cp "$f" "$EVIDENCE_DIR/$f" 2> /dev/null; then
      published+=("$f")
    else
      echo "::warning::Evidence: '$f' could not be copied into the bundle, skipped"
    fi
  done <<< "${EVIDENCE_FILES:-}"
fi

pub_json=$(printf '%s\n' "${published[@]:-}" | sed '/^$/d' | jq -R . | jq -s .)
with_json=$(printf '%s\n' "${withheld[@]:-}" | sed '/^$/d' | jq -R . | jq -s .)
run_url="${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID:-}"
if ! jq --argjson p "$pub_json" --argjson w "$with_json" --arg u "$run_url" \
   '.predicate.cnti.published_files = $p | .predicate.cnti.withheld_files = $w | .predicate.cnti.run_url = $u' \
   "$statement" > "$statement.tmp" || ! mv "$statement.tmp" "$statement"; then
  rm -f "$statement.tmp"
  echo "::warning::Evidence: the statement could not be completed; it is neither signed, uploaded on its own nor published"
  exit 0
fi
echo "Statement completed: run ${run_url}, ${#published[@]} extra file(s) in the bundle, ${#withheld[@]} withheld"
# What signs, attaches, uploads or publishes the statement goes ahead only on this.
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then echo "completed=true" >> "$GITHUB_OUTPUT"; fi
