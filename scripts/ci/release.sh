#!/bin/bash
# Create the multibuild release (R##) in naidrahiqa/selene-releases.
#
# The tag itself is computed once in the workflow's "prepare" job and passed
# in as RELEASE_TAG — every zip and the release share the same R number.
#
# Env:
#   RELEASE_TAG      required — e.g. R01
#   STATS_DIR        stats directory with per-variant .env files (default: stats)
#   ARTIFACTS_DIR    directory with the 4 kernel zips (default: artifacts)
#   RELEASE_REPO     target repo (default: naidrahiqa/selene-releases)
#   GH_TOKEN         required — PAT with repo scope
#
# Outputs (GITHUB_OUTPUT): tag, url
# Side effects: release-notes.md, stats-block.txt, GITHUB_STEP_SUMMARY entry.
set -euo pipefail

TAG="${RELEASE_TAG:?RELEASE_TAG is required}"
STATS_DIR="${STATS_DIR:-stats}"
ART_DIR="${ARTIFACTS_DIR:-artifacts}"
RELEASE_REPO="${RELEASE_REPO:-naidrahiqa/selene-releases}"
BRANCH="${KCK_SOURCE_BRANCH:-PawwwNunungggg24.0}"
SHA="${GITHUB_SHA:-$(git rev-parse HEAD)}"
SHA_SHORT="${SHA:0:7}"
DATE_UTC="$(date -u '+%Y-%m-%d %H:%M UTC')"
VARIANT_ORDER="xxksu-nomount xxksu bakasu-nomount bakasu"

# ---- guard: all 4 zips must be present (any variant failed => no release) ----
shopt -s nullglob
zips=("$ART_DIR"/*.zip)
if [ "${#zips[@]}" -ne 4 ]; then
  echo "ERROR: expected 4 zips in $ART_DIR, found ${#zips[@]}" >&2
  ls -la "$ART_DIR" >&2 || true
  exit 1
fi

# ---- aggregate per-variant stats ----
STATS_BLOCK=""
TABLE_ROWS=""
KERNEL_VER=""
for v in $VARIANT_ORDER; do
  f="$STATS_DIR/$v.env"
  if [ ! -f "$f" ]; then
    echo "ERROR: missing stats for variant $v ($f)" >&2
    exit 1
  fi
  # shellcheck disable=SC1090
  . "$f"
  STATS_BLOCK+="• ${VARIANT}: ${DURATION} | md5: ${MD5}"$'\n'
  TABLE_ROWS+="| \`${VARIANT}\` | ${DURATION} | ${SIZE} | \`${MD5:0:16}…\` |"$'\n'
  KERNEL_VER="${KERNEL_VERSION:-$KERNEL_VER}"
done
printf '%s' "$STATS_BLOCK" > stats-block.txt
KERNEL_VER="${KERNEL_VER:-4.19.325-PawwwNunungggg-cip136-st20}"

# ---- latest changelog section (first ## heading in CHANGELOG.md) ----
CHANGELOG_SECTION=""
if [ -f CHANGELOG.md ]; then
  CHANGELOG_SECTION="$(awk '/^## /{if(found)exit; found=1; print; next} found{print}' CHANGELOG.md \
    | sed 's/^## /### /' \
    | head -30)"
fi

# ---- release notes ----
{
  echo "## PawwwNunungggg ${TAG}"
  echo
  echo "**Kernel:** \`${KERNEL_VER}\`  "
  echo "**Commit:** \`${SHA_SHORT}\` (${BRANCH})  "
  echo "**Date:** ${DATE_UTC}  "
  echo "**Toolchain:** Greenforce Clang 24.0.0"
  echo
  echo "### Root Drivers"
  echo "- **xxKSU** \`v3.3.0-70\` · \`KSU_VERSION=32670\` · UAPI v5"
  echo "- **BakaSU** \`v4.2.0-rc3\` · \`KSU_VERSION=35223\` · manual hook"
  echo
  echo "### Variants (4 assets)"
  echo "| Variant | Build | Size | md5 |"
  echo "|---|---|---|---|"
  printf '%s' "$TABLE_ROWS"
  echo
  echo "### Build Statistics"
  printf '%s' "$STATS_BLOCK"
  echo
  if [ -n "$CHANGELOG_SECTION" ]; then
    echo "### Changelog"
    printf '%s\n' "$CHANGELOG_SECTION"
    echo
  fi
  echo "---"
  echo "*Build: [run #${GITHUB_RUN_ID:-local}](${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY:-}/actions/runs/${GITHUB_RUN_ID:-0})*"
} > release-notes.md

# ---- create release ----
URL="$(gh release create "$TAG" \
  --repo "$RELEASE_REPO" \
  --title "$TAG" \
  --notes-file release-notes.md \
  "${zips[@]}")"

echo "release created: $URL"

if [ -n "${GITHUB_OUTPUT:-}" ]; then
  printf 'tag=%s\n' "$TAG" >> "$GITHUB_OUTPUT"
  printf 'url=%s\n' "$URL" >> "$GITHUB_OUTPUT"
fi

if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  {
    echo "## 🚀 Release ${TAG}"
    echo
    printf '%s' "$STATS_BLOCK"
    echo
    echo "[${URL}](${URL})"
    echo
  } >> "$GITHUB_STEP_SUMMARY"
fi
