#!/usr/bin/env bash
# Decides once whether this run is on the default branch: the badge, the
# evidence and the signatures come only from runs of the default branch.
# A schedule event's payload has no repository, and a self-hosted runner may
# have no gh, so: the payload names the default branch when it has one; a
# scheduled run is on the default branch (GitHub runs schedules only there);
# otherwise the REST API names it, with curl (and sed: this runs before the
# job could have jq).
# Writes default_branch and on_default (true or false) to GITHUB_OUTPUT.
#
# Environment: EVENT, PAYLOAD_DEFAULT_BRANCH, GH_TOKEN, GITHUB_REF, GITHUB_REF_NAME,
# GITHUB_REPOSITORY, GITHUB_API_URL, GITHUB_OUTPUT.
set -uo pipefail

ref=${GITHUB_REF_NAME:-}
default=${PAYLOAD_DEFAULT_BRANCH:-}
how="the event"
if [[ -z "$default" && "${EVENT:-}" == schedule ]]; then
  default=$ref how="a scheduled run"
fi
if [[ -z "$default" && -n "${GITHUB_REPOSITORY:-}" ]]; then
  how="the API"
  auth=()
  [[ -n "${GH_TOKEN:-}" ]] && auth=(-H "Authorization: Bearer $GH_TOKEN")
  # Only a whole, successful answer counts; the field is read wherever it
  # is in the JSON (a branch name holds no '"').
  if body=$(curl -sSf --connect-timeout 10 --max-time 30 "${auth[@]}" -H "Accept: application/vnd.github+json" \
      "${GITHUB_API_URL:-https://api.github.com}/repos/${GITHUB_REPOSITORY}" 2>/dev/null); then
    default=$(grep -o '"default_branch"[[:space:]]*:[[:space:]]*"[^"]*"' <<< "$body" | head -n1 | sed 's/.*"\([^"]*\)"$/\1/')
  fi
fi

# The full ref: a tag named like the default branch is not it. A pull
# request is never the default branch's run, though pull_request_target
# reports the base branch as its ref.
on_default=false
case "${EVENT:-}" in
  pull_request|pull_request_target) ;;
  *) [[ -n "$default" && "${GITHUB_REF:-}" == "refs/heads/$default" ]] && on_default=true ;;
esac
echo "default_branch=$default" >> "$GITHUB_OUTPUT"
echo "on_default=$on_default" >> "$GITHUB_OUTPUT"
if [[ -z "$default" ]]; then
  echo "::warning::The default branch is unknown (the event names none and the API did not answer): no badge, evidence or signature from this run"
else
  echo "Default branch: $default (from $how); this run: ${ref:-?}, on the default branch: $on_default"
fi
