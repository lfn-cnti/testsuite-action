#!/usr/bin/env bash
# Publishes the badge `cnti-testsuite evidence` wrote (cnti-badge.svg, and
# cnti-badge.json in shields.io endpoint format) to an orphan branch of the
# repository using the job's GITHUB_TOKEN. Only runs on the default branch so a
# pull request never overwrites the badge. Never fails the job.
# BADGE_DRY_RUN=1 copies the two files to the current directory instead of pushing.
set -uo pipefail

# Only a completed run has a verdict worth publishing: 0 (objective met) or 1
# (not met). An errored run (2), a usage error (64) or no exit code at all
# leaves the previous badge in place.
case "${RUN_EXIT_CODE:-}" in
  0|1) ;;
  *) echo "Badge not published: the run did not complete with a verdict (exit code '${RUN_EXIT_CODE:-none}')"; exit 0 ;;
esac

if [[ ! -f "${BADGE_SOURCE_DIR:-}/cnti-badge.svg" || ! -f "${BADGE_SOURCE_DIR:-}/cnti-badge.json" ]]; then
  echo "::warning::Badge not published: no badge in '${BADGE_SOURCE_DIR:-}' (cnti-testsuite evidence did not run)"
  exit 0
fi
label=$(jq -r '.label + " " + .message' "$BADGE_SOURCE_DIR/cnti-badge.json")

if [[ "${BADGE_DRY_RUN:-}" == "1" ]]; then
  cp "$BADGE_SOURCE_DIR/cnti-badge.svg" "$BADGE_SOURCE_DIR/cnti-badge.json" .
  echo "Dry run: copied cnti-badge.svg and cnti-badge.json (${label})"
  exit 0
fi

default_branch=$(gh api "repos/${GITHUB_REPOSITORY}" --jq .default_branch 2>/dev/null || true)
if [[ -z "$default_branch" || "${GITHUB_REF_NAME:-}" != "$default_branch" ]]; then
  echo "Badge not published: ${GITHUB_REF_NAME:-?} is not the default branch (${default_branch:-unknown})"
  exit 0
fi

work=$(mktemp -d)
cp "$BADGE_SOURCE_DIR/cnti-badge.svg" "$BADGE_SOURCE_DIR/cnti-badge.json" "$work"/
cd "$work"
git init -q -b "$BADGE_BRANCH"
git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
git add cnti-badge.svg cnti-badge.json
git commit -q -m "CNTi badge: ${label}"
remote="${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY}.git"
remote="${remote/https:\/\//https://x-access-token:${GH_TOKEN}@}"
# The branch holds nothing but the current badge: one commit, replaced on every publish.
if git push -q --force "$remote" "HEAD:refs/heads/${BADGE_BRANCH}"; then
  echo "Badge published to branch ${BADGE_BRANCH}: ${label}"
  echo "Embed: ![${label}](${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY}/raw/${BADGE_BRANCH}/cnti-badge.svg)"
else
  echo "::warning::Could not push the badge branch '${BADGE_BRANCH}' - does the job have 'permissions: contents: write'?"
fi
