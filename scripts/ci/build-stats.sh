#!/bin/bash
# Collect per-variant build statistics (duration + md5) for the multibuild.
#
# Usage: build-stats.sh <variant>
#   BUILD_SECONDS      wall-clock seconds from kernel-ci-kit build step
#   ZIP_PATH           flashable zip path from kernel-ci-kit package step
#   CCACHE_HIT_RATE    ccache hit rate % (optional)
#   KERNEL_VERSION     make kernelrelease output (optional)
#
# Writes stats/<variant>.env (sourceable) and appends a bullet to
# $GITHUB_STEP_SUMMARY. The release job aggregates all stats/*.env into the
# "Build Statistics" section of the release notes and the Telegram notify.
set -euo pipefail

VARIANT="${1:?usage: build-stats.sh <variant>}"
cd "${GITHUB_WORKSPACE:-.}"

SECS="${BUILD_SECONDS:-0}"
case "$SECS" in ''|*[!0-9]*) SECS=0 ;; esac
DURATION="$((SECS / 60))m $((SECS % 60))s"

MD5="n/a"
SIZE="n/a"
if [ -n "${ZIP_PATH:-}" ] && [ -f "${ZIP_PATH}" ]; then
  MD5="$(md5sum "${ZIP_PATH}" | cut -d' ' -f1)"
  SIZE="$(du -h "${ZIP_PATH}" | cut -f1)"
fi

mkdir -p stats
{
  printf "VARIANT='%s'\n" "$VARIANT"
  printf "DURATION='%s'\n" "$DURATION"
  printf "BUILD_SECONDS='%s'\n" "$SECS"
  printf "MD5='%s'\n" "$MD5"
  printf "SIZE='%s'\n" "$SIZE"
  printf "CCACHE='%s'\n" "${CCACHE_HIT_RATE:-n/a}"
  printf "KERNEL_VERSION='%s'\n" "${KERNEL_VERSION:-unknown}"
} > "stats/${VARIANT}.env"

LINE="• ${VARIANT}: ${DURATION} | md5: ${MD5}"
printf '%s\n' "$LINE"

if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  {
    echo "### 📊 ${VARIANT}"
    echo
    echo '```'
    echo "$LINE"
    echo '```'
    echo
    echo "size ${SIZE} · ccache ${CCACHE_HIT_RATE:-n/a}% · \`${KERNEL_VERSION:-unknown}\`"
    echo
  } >> "$GITHUB_STEP_SUMMARY"
fi
