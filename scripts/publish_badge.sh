#!/usr/bin/env bash
# Publishes cnti-badge.svg and cnti-badge.json (shields.io endpoint format) to an
# orphan branch of the repository using the job's GITHUB_TOKEN. Only runs on the
# default branch so a pull request never overwrites the badge. Never fails the job.
# BADGE_DRY_RUN=1 writes the two files to the current directory instead of pushing.
set -uo pipefail

# CNTi logo (symbol + wordmark, colour) from https://github.com/lfn-cnti/artwork
# (cnti-logo/stacked/color/CNTi Logo_COLOR.svg), viewBox 0 0 255.99 69.68.
LOGO_VIEWBOX="0 0 255.99 69.68"
LOGO_PATHS='<path fill="#213666" d="M156.58,31.9l-6.74,5.71c-3.02-3.4-6.8-5.07-11.35-5.07-3.98,0-7.31,1.35-10.07,4.04s-4.11,6.03-4.11,10.07,1.35,7.38,4.04,10.07c2.76,2.63,6.09,3.98,10.14,3.98,4.62,0,8.4-1.73,11.42-5.13l6.74,5.71c-4.55,5.32-11.03,8.4-18.15,8.4-6.73,0-12.38-2.18-17.06-6.54-4.68-4.43-6.99-9.88-6.99-16.48s2.31-12.06,6.99-16.49,10.33-6.61,17.06-6.61c7.12,0,13.53,3.14,18.09,8.34Z"/><path fill="#213666" d="M162.23,68.97V24.26h8.79l21.42,27.77v-27.77h9.56v44.71h-8.08l-22.13-28.54v28.54h-9.56Z"/><path fill="#213666" d="M219.32,68.97v-35.73h-12.12v-8.98h33.93v8.98h-11.93v35.73h-9.88Z"/><path fill="#213666" d="M246.4,68.97v-32.33h9.56v32.33h-9.56Z"/><rect fill="#4fb04e" x="246.36" y="24.28" width="9.63" height="9"/><path fill="#0086c1" d="M80.83,24.71v7.62c6.34,1.9,10.97,7.78,10.97,14.72s-4.59,12.77-10.89,14.69v7.64c10.43-2.08,18.31-11.31,18.31-22.34s-7.92-20.29-18.39-22.34Z"/><path fill="#0086c1" d="M21.82,61.86h-4.51c-.16-.02-.39-.03-.55-.04-.17-.01-.47-.02-.63-.06-.61-.09-1.31-.22-1.89-.41-4.49-1.39-7.63-5.88-6.66-10.58,1.66-7.71,11.75-10.1,17.25-4.79l5.66-4.73c-2.2-3.44-3.43-7.43-3.54-11.49-.23-7.32,3.15-14.33,9.45-18.2,6.76-4.17,16.15-4.44,23.19-.81,3.92,2.03,6.86,5.46,8.37,9.55h8.71c-.13-.59-.29-1.17-.48-1.75-2.03-6.43-6.75-12.1-12.75-15.14C59.53,1.37,55.17.32,50.82.08c-17.64-1.22-32.51,11.96-31.61,29.98.09,1.96.38,3.91.86,5.82-5-.69-10.26.72-14.13,4.02C2.51,42.75.24,47.08.03,51.55c-.56,10.27,8.19,18.05,18.2,17.73h1.74s.67,0,1.86,0v-7.42Z"/><rect fill="#4fb04e" x="68.23" y="24.19" width="8.86" height="45.17"/><rect fill="#4fb04e" x="54.17" y="33.06" width="8.9" height="36.3"/><rect fill="#4fb04e" x="40.15" y="42.17" width="8.89" height="27.2"/><rect fill="#4fb04e" x="26.09" y="51.23" width="8.93" height="18.13"/>'
# Monochrome symbol for shields.io endpoint badges (their logo slot is on a dark
# panel); the gist badge step reads the same file.
LOGO_SVG=$(cat "$(dirname "${BASH_SOURCE[0]}")/../assets/cnti-symbol-white.svg")


# Only a completed run has a verdict worth publishing: 0 (objective met) or 1
# (not met). An errored run (2), a usage error (64) or no exit code at all
# leaves the previous badge in place.
case "${RUN_EXIT_CODE:-}" in
  0|1) ;;
  *) echo "Badge not published: the run did not complete with a verdict (exit code '${RUN_EXIT_CODE:-none}')"; exit 0 ;;
esac

if [[ "${BADGE_DRY_RUN:-}" != "1" ]]; then
  default_branch=$(gh api "repos/${GITHUB_REPOSITORY}" --jq .default_branch 2>/dev/null || true)
  if [[ -z "$default_branch" || "${GITHUB_REF_NAME:-}" != "$default_branch" ]]; then
    echo "Badge not published: ${GITHUB_REF_NAME:-?} is not the default branch (${default_branch:-unknown})"
    exit 0
  fi
fi

label="CNTi ${TESTS:-cert}"          # shields/aria text; the SVG shows the wordmark + task
svg_label="${TESTS:-cert}"
message="${PASSED:-?}/${MAX_PASSED:-?}"
case "${STATUS:-error}" in
  passed) color="4c1"; color_name="brightgreen" ;;
  failed) color="e05d44"; color_name="red" ;;
  *)      color="9f9f9f"; color_name="lightgrey" ;;
esac

# Flat shields-style SVG: white panel with the colour logo (16px high) and the task
# name in the logo's navy, then the coloured verdict panel; ~6.5px per character of
# Verdana 11px, plus padding.
# 13px logo puts the wordmark cap height at ~8px, the same as the 11px text; everything
# shares one baseline (y=14.5): logo bottom, task name and the numbers.
logo_h=13; logo_w=48; logo_y=1.5; pad=5; gap=5
label_tw=$(( ${#svg_label} * 65 / 10 ))
lw=$(( pad + logo_w + gap + label_tw + pad ))
mw=$(( ${#message} * 65 / 10 + 10 ))
tw=$(( lw + mw ))
label_x=$(( pad + logo_w + gap + label_tw / 2 ))
svg=$(cat <<SVG
<svg xmlns="http://www.w3.org/2000/svg" width="${tw}" height="20" role="img" aria-label="${label}: ${message}">
  <title>${label}: ${message}</title>
  <linearGradient id="s" x2="0" y2="100%"><stop offset="0" stop-color="#bbb" stop-opacity=".1"/><stop offset="1" stop-opacity=".1"/></linearGradient>
  <clipPath id="r"><rect width="${tw}" height="20" rx="3" fill="#fff"/></clipPath>
  <g clip-path="url(#r)"><rect width="${lw}" height="20" fill="#fff"/><rect x="${lw}" width="${mw}" height="20" fill="#${color}"/><rect x="${lw}" width="${mw}" height="20" fill="url(#s)"/></g>
  <rect x=".5" y=".5" width="$(( tw - 1 ))" height="19" rx="3" fill="none" stroke="#ccc"/>
  <svg x="${pad}" y="${logo_y}" width="${logo_w}" height="${logo_h}" viewBox="${LOGO_VIEWBOX}">${LOGO_PATHS}</svg>
  <g text-anchor="middle" font-family="Verdana,Geneva,DejaVu Sans,sans-serif" font-size="11">
    <text x="${label_x}" y="14.5" fill="#213666">${svg_label}</text>
    <text x="$(( lw + mw / 2 ))" y="15.5" fill="#010101" fill-opacity=".3">${message}</text><text x="$(( lw + mw / 2 ))" y="14.5" fill="#fff">${message}</text>
  </g>
</svg>
SVG
)

write_badge_files() {
  printf '%s\n' "$svg" > cnti-badge.svg
  # logoSvg lets shields.io's endpoint badge show the same symbol.
  python3 - "$label" "$message" "$color_name" "$LOGO_SVG" > cnti-badge.json <<'PY' || \
    printf '{"schemaVersion":1,"label":"%s","message":"%s","color":"%s"}\n' "$label" "$message" "$color_name" > cnti-badge.json
import json, sys
print(json.dumps({"schemaVersion": 1, "label": sys.argv[1], "message": sys.argv[2], "color": sys.argv[3], "logoSvg": sys.argv[4]}))
PY
}

if [[ "${BADGE_DRY_RUN:-}" == "1" ]]; then
  write_badge_files
  echo "Dry run: wrote cnti-badge.svg and cnti-badge.json (${label} ${message}, ${STATUS:-error})"
  exit 0
fi

work=$(mktemp -d)
cd "$work"
git init -q -b "$BADGE_BRANCH"
git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
write_badge_files
git add cnti-badge.svg cnti-badge.json
git commit -q -m "CNTi badge: ${label} ${message} (${STATUS:-error})"
remote="${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY}.git"
remote="${remote/https:\/\//https://x-access-token:${GH_TOKEN}@}"
# The branch holds nothing but the current badge: one commit, replaced on every publish.
if git push -q --force "$remote" "HEAD:refs/heads/${BADGE_BRANCH}"; then
  echo "Badge published to branch ${BADGE_BRANCH}: ${label} ${message}"
  echo "Embed: ![${label}](${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY}/raw/${BADGE_BRANCH}/cnti-badge.svg)"
else
  echo "::warning::Could not push the badge branch '${BADGE_BRANCH}' - does the job have 'permissions: contents: write'?"
fi
