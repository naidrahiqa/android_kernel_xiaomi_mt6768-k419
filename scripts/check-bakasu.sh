#!/bin/bash
# ==============================================================================
# check-bakasu.sh — Bandingkan pin BakaSU lokal (drivers/bakasu/)
#                   dengan upstream Baka-SU/BakaSU@main
# ==============================================================================
# Usage : scripts/check-bakasu.sh [--json]
# Exit  : 0 = sudah latest | 1 = outdated | 2 = error (jaringan/API)
# Deps  : curl, jq
# ==============================================================================
set -uo pipefail

REPO_OWNER="Baka-SU"
REPO_NAME="BakaSU"
API="https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}"
BRANCH="main"

JSON_MODE=0
[ "${1:-}" = "--json" ] && JSON_MODE=1

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR" || exit 2

command -v jq >/dev/null 2>&1 || { echo "Error: jq tidak ditemukan" >&2; exit 2; }
command -v curl >/dev/null 2>&1 || { echo "Error: curl tidak ditemukan" >&2; exit 2; }

# --- auth opsional (hindari rate-limit 60/jam) ---
AUTH=()
if [ -n "${GITHUB_TOKEN:-}" ]; then
	AUTH=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
elif [ -n "${GH_TOKEN:-}" ]; then
	AUTH=(-H "Authorization: Bearer ${GH_TOKEN}")
fi

TMP="$(mktemp -d)" || exit 2
trap 'rm -rf "$TMP"' EXIT
BODY="$TMP/body"
HDRS="$TMP/headers"

http_get() {
	curl -sSL --max-time 30 -H "Accept: application/vnd.github+json" \
		${AUTH[@]+"${AUTH[@]}"} -D "$HDRS" -o "$BODY" "${API}$1" >/dev/null 2>&1
	awk 'toupper($1) ~ /^HTTP\// { c = $2 } END { print c }' "$HDRS" 2>/dev/null
}

# --- pin lokal dari drivers/bakasu/ ---
if [ ! -d "drivers/bakasu" ]; then
	echo "Error: drivers/bakasu tidak ditemukan" >&2
	exit 2
fi

# Read static pin from Kbuild
PIN_VERSION=$(grep -E '^KSU_VERSION :=' drivers/bakasu/Kbuild | sed 's/.*:= *//')
PIN_TAG=$(grep -E '^KSU_TAG_NAME :=' drivers/bakasu/Kbuild | sed 's/.*:= *//')
PIN_SHA=$(grep -E '^KSU_COMMIT_SHA :=' drivers/bakasu/Kbuild | sed 's/.*:= *//')

if [ -z "$PIN_VERSION" ] || [ -z "$PIN_TAG" ]; then
	echo "Error: KSU_VERSION atau KSU_TAG_NAME tidak terbaca di drivers/bakasu/Kbuild" >&2
	exit 2
fi

# Read rev-count from file
PIN_REV=""
if [ -f "drivers/bakasu/BAKASU_REV_COUNT" ]; then
	PIN_REV=$(tr -d ' \n\r' < drivers/bakasu/BAKASU_REV_COUNT)
fi

# --- upstream: latest release ---
CODE="$(http_get "/releases/latest")"
UP_REL_TAG="?"
UP_REL_NAME="?"
UP_REL_DATE="?"
if [ "$CODE" = "200" ]; then
	UP_REL_TAG="$(jq -r '.tag_name // "?"' "$BODY")"
	UP_REL_NAME="$(jq -r '.name // "?"' "$BODY")"
	UP_REL_DATE="$(jq -r '.published_at // "?"' "$BODY")"
fi

# --- upstream: latest commit on main ---
CODE="$(http_get "/commits/${BRANCH}")"
if [ "$CODE" != "200" ]; then
	echo "Error: GET /commits/${BRANCH} -> HTTP ${CODE}" >&2
	exit 2
fi
UP_SHA="$(jq -r '.sha' "$BODY")"
UP_DATE="$(jq -r '.commit.committer.date' "$BODY")"
UP_SUBJ="$(jq -r '.commit.message | split("\n")[0]' "$BODY")"
UP_SHA7="${UP_SHA:0:7}"

# --- upstream: commit count on main (for KSU_VERSION calc) ---
# Note: GitHub API doesn't easily give total commit count. We'll skip auto-calc.
# Instead compare tag name.
UP_REV_COUNT="?"

# --- status & exit code ---
if [ "$PIN_TAG" = "$UP_REL_TAG" ]; then
	STATUS="up-to-date"
	EXIT_CODE=0
else
	STATUS="outdated"
	EXIT_CODE=1
fi

if [ "$JSON_MODE" -eq 1 ]; then
	jq -n \
		--arg status "$STATUS" \
		--arg pin_tag "$PIN_TAG" \
		--arg pin_version "$PIN_VERSION" \
		--arg pin_rev "$PIN_REV" \
		--arg up_sha "$UP_SHA" \
		--arg up_tag "$UP_REL_TAG" \
		--arg up_release_name "$UP_REL_NAME" \
		--arg up_release_date "$UP_REL_DATE" \
		--arg up_date "$UP_DATE" \
		--arg up_subject "$UP_SUBJ" \
		'{
			status: $status,
			pin: { tag: $pin_tag, ksu_version: ($pin_version | tonumber? // null), rev_count: ($pin_rev | tonumber? // null) },
			upstream: {
				latest_release: { tag: $up_tag, name: $up_release_name, date: $up_release_date },
				master_commit: { sha: $up_sha, date: $up_date, subject: $up_subject }
			}
		}'
else
	echo "== BakaSU upstream check =="
	echo "Repo     : ${REPO_OWNER}/${REPO_NAME}@${BRANCH}"
	echo "Pin      : ${PIN_TAG} · KSU_VERSION ${PIN_VERSION} (rev ${PIN_REV})"
	echo "Upstream : Release ${UP_REL_TAG} (${UP_REL_DATE})"
	echo "           Master ${UP_SHA7} · ${UP_DATE}"
	echo "           ${UP_SUBJ}"
	case "$STATUS" in
	up-to-date)
		echo "Status   : UP-TO-DATE ✅"
		;;
	outdated)
		echo "Status   : OUTDATED 🔄 (Lokal: ${PIN_TAG} vs Upstream: ${UP_REL_TAG})"
		;;
	*)
		echo "Status   : UNKNOWN ❓"
		;;
	esac
fi

exit "$EXIT_CODE"
