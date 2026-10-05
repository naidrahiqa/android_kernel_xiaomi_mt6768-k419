#!/bin/bash
# ==============================================================================
# check-resukisu.sh — Bandingkan pin ReSukiSU lokal (resukisu/Kbuild)
#                     dengan upstream Baka-SU/BakaSU@main (dulunya ReSukiSU)
# ==============================================================================
# Usage : scripts/check-resukisu.sh [--json]
# Exit  : 0 = sudah latest | 1 = outdated | 2 = error (jaringan/API/Kbuild)
# Deps  : curl, jq
# CI    : kernel-ci-kit .github/workflows/resukisu-check.yml (cron mingguan)
# Sync  : kalau exit 1 -> kernel-ci-kit .github/workflows/resukisu-updater.yml
#         (atau manual: skill ksu-version-management)
# ==============================================================================
set -uo pipefail

# NB: repo ini di-rename GitHub menjadi Baka-SU/BakaSU (2026-10-05). Nama lama
# ReSukiSU/ReSukiSU masih redirect, tapi pakai nama baru supaya tidak bergantung
# pada redirect (nama lama bisa di-squat) — dan tetap pakai -L di http_get supaya
# rename berikutnya tidak mematikan script (301 -> exit 2 -> cron error).
REPO_OWNER="Baka-SU"
REPO_NAME="BakaSU"
API="https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}"

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

# http_get <path> -> print HTTP code; body di $BODY, header di $HDRS
# -L wajib: API membalas 301 untuk repo yang pernah di-rename, dan tanpa -L
# code-nya 301 -> script exit 2. awk di bawah mengambil status HTTP terakhir,
# jadi blok header redirect tidak mengganggu.
http_get() {
	curl -sSL --max-time 30 -H "Accept: application/vnd.github+json" \
		${AUTH[@]+"${AUTH[@]}"} -D "$HDRS" -o "$BODY" "${API}$1" >/dev/null 2>&1
	awk 'toupper($1) ~ /^HTTP\// { c = $2 } END { print c }' "$HDRS" 2>/dev/null
}

# --- pin lokal dari resukisu/Kbuild ---
KBUILD=""
if [ -f resukisu/Kbuild ]; then
	KBUILD="resukisu/Kbuild"
elif [ -f resukisu/kernel/Kbuild ]; then
	KBUILD="resukisu/kernel/Kbuild"
else
	echo "Error: resukisu/Kbuild tidak ditemukan" >&2
	exit 2
fi

PIN_LOCAL="$(grep '^KSU_LOCAL_VERSION' "$KBUILD" | head -1 | sed 's/.*:= *//' | tr -d ' ')"
PIN_TAG="$(grep '^KSU_TAG_NAME' "$KBUILD" | head -1 | sed 's/.*:= *//' | sed 's/\$(shell .*)//; s/^ *//; s/ *$//')"
PIN_SHA="$(grep '^KSU_COMMIT_SHA' "$KBUILD" | head -1 | sed 's/.*:= *//' | sed 's/\$(shell .*)//; s/^ *//; s/ *$//')"

if ! [[ "$PIN_LOCAL" =~ ^[0-9]+$ ]]; then
	echo "Error: KSU_LOCAL_VERSION tidak terbaca di $KBUILD" >&2
	exit 2
fi
PIN_VERSION=$((30000 + PIN_LOCAL + 700))
PIN_TAG="${PIN_TAG:-?}"
PIN_SHA="${PIN_SHA:-?}"

# --- upstream: latest commit main ---
CODE="$(http_get "/commits/main")"
if [ "$CODE" != "200" ]; then
	echo "Error: GET /commits/main -> HTTP ${CODE}" >&2
	exit 2
fi
UP_SHA="$(jq -r '.sha' "$BODY")"
UP_DATE="$(jq -r '.commit.committer.date' "$BODY")"
UP_SUBJ="$(jq -r '.commit.message | split("\n")[0]' "$BODY")"
UP_SHA7="${UP_SHA:0:7}"

# --- upstream: total commit (Link header page=last) ---
CODE="$(http_get "/commits?per_page=1")"
UP_COUNT=""
if [ "$CODE" = "200" ]; then
	UP_COUNT="$(grep -i '^link:' "$HDRS" | grep -o 'page=[0-9]*>; rel="last"' | grep -o '[0-9]*' || true)"
fi
UP_COUNT="${UP_COUNT:-?}"

# --- upstream: tag terbaru ---
UP_TAG="?"
CODE="$(http_get "/tags?per_page=1")"
if [ "$CODE" = "200" ]; then
	[ "$(jq -r 'type' "$BODY")" = "array" ] && UP_TAG="$(jq -r '.[0].name // "?"' "$BODY")"
fi

# --- cocokkan pin dengan upstream ---
AHEAD=0
BEHIND=0
DELTA_COMMITS=""
DELTA_FILES=""
COMPARE_NOTE=""
if [ "$PIN_SHA" != "?" ] && { [ "$UP_SHA" = "$PIN_SHA"* ] || [ "$PIN_SHA" = "$UP_SHA"* ]; }; then
	AHEAD=0
else
	# resolve pin ke SHA penuh
	CODE="$(http_get "/commits/$PIN_SHA")"
	if [ "$CODE" = "200" ]; then
		PIN_FULL="$(jq -r '.sha' "$BODY")"
		CODE="$(http_get "/compare/${PIN_FULL}...${UP_SHA}")"
		if [ "$CODE" = "200" ]; then
			AHEAD="$(jq -r '.ahead_by // 0' "$BODY")"
			BEHIND="$(jq -r '.behind_by // 0' "$BODY")"
			DELTA_COMMITS="$(jq -r '.commits[]? | .sha[0:7] + " " + (.commit.message | split("\n")[0])' "$BODY" | head -5)"
			DELTA_FILES="$(jq -r '.files[]?.filename' "$BODY")"
		else
			AHEAD=-1
			COMPARE_NOTE="compare HTTP ${CODE} (pin kemungkinan sudah hilang dari history / force-push)"
		fi
	else
		AHEAD=-1
		COMPARE_NOTE="resolve pin HTTP ${CODE} (pin tidak ditemukan di upstream)"
	fi
fi

# --- klasifikasi relevansi perubahan ---
KERN_FILES=""
MGR_FILES=""
if [ -n "$DELTA_FILES" ]; then
	KERN_FILES="$(printf '%s\n' "$DELTA_FILES" | grep -E '^(kernel|uapi)/' || true)"
	MGR_FILES="$(printf '%s\n' "$DELTA_FILES" | grep '^manager/' || true)"
fi
if [ -n "$KERN_FILES" ]; then
	RELEVANCE="kernel/uapi -> butuh rebuild Image + flash"
elif [ -n "$MGR_FILES" ]; then
	RELEVANCE="manager APK saja -> update Manager, kernel tak perlu rebuild"
elif [ -n "$DELTA_FILES" ]; then
	RELEVANCE="userspace/ksud/docs -> tak butuh rebuild kernel"
elif [ "$AHEAD" -eq 0 ]; then
	RELEVANCE="-"
else
	RELEVANCE="tidak diketahui (bandingkan manual)"
fi

# --- status & exit code ---
UP_VERSION="?"
if [[ "$UP_COUNT" =~ ^[0-9]+$ ]]; then
	UP_VERSION=$((30000 + UP_COUNT + 700))
fi
if [ "$AHEAD" -eq 0 ]; then
	STATUS="up-to-date"
	EXIT_CODE=0
elif [ "$AHEAD" -gt 0 ] || [ "$AHEAD" -eq -1 ]; then
	STATUS="outdated"
	EXIT_CODE=1
else
	STATUS="error"
	EXIT_CODE=2
fi

# --- cetak laporan ---
if [ "$JSON_MODE" -eq 1 ]; then
	jq -n \
		--arg status "$STATUS" \
		--arg pin_sha "$PIN_SHA" \
		--arg pin_tag "$PIN_TAG" \
		--argjson pin_local "$PIN_LOCAL" \
		--argjson pin_version "$PIN_VERSION" \
		--arg up_sha "$UP_SHA" \
		--arg up_tag "$UP_TAG" \
		--arg up_date "$UP_DATE" \
		--arg up_subject "$UP_SUBJ" \
		--arg up_count "$UP_COUNT" \
		--arg up_version "$UP_VERSION" \
		--argjson ahead "$AHEAD" \
		--argjson behind "$BEHIND" \
		--arg relevance "$RELEVANCE" \
		--arg note "$COMPARE_NOTE" \
		--arg commits "$DELTA_COMMITS" \
		--arg kern_files "$KERN_FILES" \
		--arg mgr_files "$MGR_FILES" \
		'{
			status: $status,
			pin: { sha: $pin_sha, tag: $pin_tag, local_version: $pin_local, ksu_version: $pin_version },
			upstream: { sha: $up_sha, tag: $up_tag, date: $up_date, subject: $up_subject, total_commits: ($up_count | tonumber? // null), ksu_version: ($up_version | tonumber? // null) },
			ahead_by: $ahead,
			behind_by: $behind,
			relevance: $relevance,
			note: $note,
			commits: ($commits | split("\n") | map(select(length > 0))),
			kernel_files: ($kern_files | split("\n") | map(select(length > 0))),
			manager_files: ($mgr_files | split("\n") | map(select(length > 0)))
		}'
else
	echo "== ReSukiSU upstream check =="
	echo "Repo     : ${REPO_OWNER}/${REPO_NAME}@main"
	echo "Pin      : ${PIN_SHA} · ${PIN_TAG} · KSU_LOCAL_VERSION ${PIN_LOCAL} · KSU_VERSION ${PIN_VERSION}"
	echo "Upstream : ${UP_SHA7} · ${UP_TAG} · ${UP_DATE}"
	echo "           ${UP_SUBJ}"
	echo "Jumlah   : upstream ${UP_COUNT} (KSU_VERSION ${UP_VERSION}) · pin ${PIN_LOCAL} (KSU_VERSION ${PIN_VERSION})"
	if [ "$AHEAD" -gt 0 ]; then
		echo "Delta    : +${AHEAD} commit belum ter-pin (behind_by ${BEHIND})"
		[ -n "$DELTA_COMMITS" ] && printf '%s\n' "$DELTA_COMMITS" | sed 's/^/           - /'
	fi
	if [ "$AHEAD" -eq -1 ]; then
		echo "Delta    : tidak bisa dibandingkan — ${COMPARE_NOTE}"
	fi
	echo "Relevansi: ${RELEVANCE}"
	if [ -n "$KERN_FILES" ]; then
		printf '%s\n' "$KERN_FILES" | sed 's/^/           - /'
	fi
	case "$STATUS" in
	up-to-date)
		echo "Status   : UP-TO-DATE ✅"
		;;
	outdated)
		echo "Status   : OUTDATED 🔄 → jalankan skill ksu-version-management untuk sync"
		;;
	*)
		echo "Status   : ERROR ❌ (lihat pesan di atas)"
		;;
	esac
fi

exit "$EXIT_CODE"
