#!/usr/bin/env bash
# Publishes the evidence bundle (what `cnti-testsuite evidence` wrote, completed by
# complete_statement.sh with the extra files) to a public repository the project owns, so a
# private repository can show its badge and the evidence behind it, and a public
# one keeps a history of its runs in one place. Commits on top of the target
# branch's history (no force push), retries once on a non-fast-forward push, and
# never fails the job: a push failure is a warning. Only runs on the default
# branch, like the badge, so a pull request never publishes evidence.
#
# Inputs (environment): EVIDENCE_DIR (the bundle), EVIDENCE_REPOSITORY (owner/repo),
# EVIDENCE_TOKEN, EVIDENCE_BRANCH, EVIDENCE_PATH (directory in the repository; its
# parent gets a latest/ copy of the badge), CNF_NAME, RUN_DATE, RUN_EXIT_CODE,
# GITHUB_REPOSITORY, GITHUB_REF_NAME, GITHUB_SERVER_URL. The statement is published
# as it is: it was completed, and possibly signed, before this runs.
set -uo pipefail

case "${RUN_EXIT_CODE:-}" in
  0|1) ;;
  *) echo "Evidence not published: the run did not complete with a verdict (exit code '${RUN_EXIT_CODE:-none}')"; exit 0 ;;
esac

if [[ ! -d "${EVIDENCE_DIR:-}" || ! -f "$EVIDENCE_DIR/cnti-badge.svg" ]]; then
  echo "::warning::Evidence not published: no bundle at '${EVIDENCE_DIR:-}'"
  exit 0
fi

default_branch=$(gh api "repos/${GITHUB_REPOSITORY}" --jq .default_branch 2>/dev/null || true)
if [[ -z "$default_branch" || "${GITHUB_REF_NAME:-}" != "$default_branch" ]]; then
  echo "Evidence not published: ${GITHUB_REF_NAME:-?} is not the default branch (${default_branch:-unknown})"
  exit 0
fi

# The bundle is named relative to the workspace; the work below happens in a
# clone elsewhere, so resolve it first.
EVIDENCE_DIR=$(cd "$EVIDENCE_DIR" && pwd)

work=$(mktemp -d)
remote="${GITHUB_SERVER_URL:-https://github.com}/${EVIDENCE_REPOSITORY}.git"
remote="${remote/https:\/\//https://x-access-token:${EVIDENCE_TOKEN}@}"
branch="${EVIDENCE_BRANCH:-main}"

# A shallow clone of the target branch; an empty repository or a missing
# branch starts it.
if ! git clone -q --depth 1 --branch "$branch" "$remote" "$work" 2>/dev/null; then
  git init -q -b "$branch" "$work"
fi
cd "$work"
git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"

dest="${EVIDENCE_PATH:-cnti/${CNF_NAME:-cnf}/${RUN_DATE:-run}}"
latest="$(dirname "$dest")/latest"
mkdir -p "$dest" "$latest"
# The whole bundle, the extra files included.
cp -r "$EVIDENCE_DIR"/. "$dest"/
# The badge the README embeds: always the latest run of the default branch.
cp "$EVIDENCE_DIR/cnti-badge.svg" "$EVIDENCE_DIR/cnti-badge.json" "$latest"/

git add -A "$dest" "$latest"
if git diff --cached --quiet; then
  echo "::warning::Evidence: nothing to publish (the bundle at ${EVIDENCE_DIR} is empty or already published)"
  exit 0
fi
label=$(jq -r '.label + " " + .message' "$EVIDENCE_DIR/cnti-badge.json" 2>/dev/null || echo "CNTi evidence")
git commit -q -m "CNTi evidence: ${label} (${CNF_NAME:-cnf}, ${RUN_DATE:-run})"

push() { git push -q "$remote" "HEAD:refs/heads/${branch}"; }
if ! push; then
  # Another publisher got there first: take its commits and try once more.
  git pull -q --rebase "$remote" "$branch" 2>/dev/null || true
  push || { echo "::warning::Could not push the evidence to ${EVIDENCE_REPOSITORY}@${branch}: does the token have contents write on that repository?"; exit 0; }
fi
extras=$(jq -r '.predicate.cnti.published_files | length' "$EVIDENCE_DIR/cnti-evidence.json" 2>/dev/null || echo 0)
withheld=$(jq -r '.predicate.cnti.withheld_files | length' "$EVIDENCE_DIR/cnti-evidence.json" 2>/dev/null || echo 0)
echo "Evidence published to ${EVIDENCE_REPOSITORY}@${branch}: ${dest} (${extras} extra file(s), ${withheld} withheld)"
echo "Embed: ![${label}](${GITHUB_SERVER_URL:-https://github.com}/${EVIDENCE_REPOSITORY}/raw/${branch}/${latest}/cnti-badge.svg)"
