#!/bin/bash
# ==============================================================================
# check-xxksu.sh — Bandingkan pin xxKSU lokal (drivers/kernelsu/)
#                  dengan upstream backslashxx/KernelSU@master
# ==============================================================================
# Usage : scripts/check-xxksu.sh [--json]
# Exit  : 0 = sudah latest | 1 = outdated | 2 = error (jaringan/API)
# Deps  : curl, jq
# ==============================================================================
set -uo pipefail

REPO_OWNER="backslashxx"
REPO_NAME="KernelSU"
API="https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}"
BRANCH="master"

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

# --- pin lokal dari drivers/kernelsu/ ---
if [ ! -d "drivers/kernelsu" ]; then
	echo "Error: drivers/kernelsu tidak ditemukan" >&2
	exit 2
fi

PIN_VERSION=$(sed -n 's/.*-DKSU_VERSION=\([0-9]*\).*/\1/p' drivers/kernelsu/Makefile | head -1)
PIN_TAG="?"
if [ -f "drivers/kernelsu/VERSION" ]; then
	PIN_TAG=$(tr -d ' \n\r' < drivers/kernelsu/VERSION)
fi

if [ -z "$PIN_VERSION" ]; then
	echo "Error: KSU_VERSION tidak terbaca di drivers/kernelsu/Makefile" >&2
	exit 2
fi

# --- upstream: latest release ---
CODE="$(http_get "/releases/latest")"
UP_TAG="?"
UP_RELEASE_NAME="?"
UP_RELEASE_DATE="?"
if [ "$CODE" = "200" ]; then
	UP_TAG="$(jq -r '.tag_name // "?"' "$BODY")"
	UP_RELEASE_NAME="$(jq -r '.name // "?"' "$BODY")"
	UP_RELEASE_DATE="$(jq -r '.published_at // "?"' "$BODY")"
fi

# --- upstream: latest commit master ---
CODE="$(http_get "/commits/${BRANCH}")"
if [ "$CODE" != "200" ]; then
	echo "Error: GET /commits/${BRANCH} -> HTTP ${CODE}" >&2
	exit 2
fi
UP_SHA="$(jq -r '.sha' "$BODY")"
UP_DATE="$(jq -r '.commit.committer.date' "$BODY")"
UP_SUBJ="$(jq -r '.commit.message | split("\n")[0]' "$BODY")"
UP_SHA7="${UP_SHA:0:7}"

# --- status & exit code ---
if [ "$PIN_TAG" = "$UP_TAG" ]; then
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
		--arg up_sha "$UP_SHA" \
		--arg up_tag "$UP_TAG" \
		--arg up_release_name "$UP_RELEASE_NAME" \
		--arg up_release_date "$UP_RELEASE_DATE" \
		--arg up_date "$UP_DATE" \
		--arg up_subject "$UP_SUBJ" \
		'{
			status: $status,
			pin: { tag: $pin_tag, ksu_version: ($pin_version | tonumber? // null) },
			upstream: {
				latest_release: { tag: $up_tag, name: $up_release_name, date: $up_release_date },
				master_commit: { sha: $up_sha, date: $up_date, subject: $up_subject }
			}
		}'
else
	echo "== xxKSU upstream check =="
	echo "Repo     : ${REPO_OWNER}/${REPO_NAME}@${BRANCH}"
	echo "Pin      : ${PIN_TAG} · KSU_VERSION ${PIN_VERSION}"
	echo "Upstream : Release ${UP_TAG} (${UP_RELEASE_DATE})"
	echo "           Master ${UP_SHA7} · ${UP_DATE}"
	echo "           ${UP_SUBJ}"
	case "$STATUS" in
	up-to-date)
		echo "Status   : UP-TO-DATE ✅"
		;;
	outdated)
		echo "Status   : OUTDATED 🔄 (Lokal: ${PIN_TAG} vs Upstream: ${UP_TAG})"
		;;
	*)
		echo "Status   : UNKNOWN ❓"
		;;
	esac
fi

exit "$EXIT_CODE"
