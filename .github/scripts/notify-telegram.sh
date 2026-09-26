#!/bin/bash
# Telegram Notification - Mocchipyon Kernel 4.19
# Usage: bash notify-telegram.sh <status> <version> <tag> [arg4] [arg5]
# Status: start | success | failed | tested
#   start   - build dimulai
#   success - build SUKSES: notif singkat TANPA link download, tanpa changelog
#   failed  - build gagal (ringkasan + log)
#   tested  - build sudah DITES & BOOTING AMAN: notif lengkap + tombol download
#             arg4 = catatan testing, arg5 = download URL
#
# Target Channels / Topics:
#   Left (Supergroup Naidrahiqa Stuff):
#     TELEGRAM_GROUP_ID       - Chat ID supergroup (-1004414006944)
#     TELEGRAM_TOPIC_CI       - Thread ID topic ⁉️ Selene CI (47) [NOTIF ONLY, NO ZIP]
#     TELEGRAM_TOPIC_LOG      - Thread ID topic 🔍 log (8) [Build error log]
#
#   Right (Private Channels):
#     TELEGRAM_CHANNEL_ID     - Chat ID channel Nai project update (-1003752197403) [KIRIM FILE .ZIP KERNEL]
#     TELEGRAM_ERROR_CHANNEL_ID - Chat ID channel Nai Error Dump (-1003945405514) [Full error dump]

STATUS="${1:-unknown}"
VERSION="${2:-unknown}"
TAG="${3:-$VERSION}"

BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-}"
GROUP_ID="${TELEGRAM_GROUP_ID:-}"
TOPIC_CI="${TELEGRAM_TOPIC_CI:-47}"
TOPIC_LOG="${TELEGRAM_TOPIC_LOG:-8}"
CHANNEL_ID="${TELEGRAM_CHANNEL_ID:-}"
ERROR_CHANNEL_ID="${TELEGRAM_ERROR_CHANNEL_ID:-}"

if [ -z "$BOT_TOKEN" ]; then
	echo "TELEGRAM_BOT_TOKEN not set. Skipping."
	exit 0
fi

SHA=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
COMMIT_MSG=$(git log -1 --pretty=%s 2>/dev/null || echo "unknown")
BUILD_NUM="${GITHUB_RUN_NUMBER:-0}"
BUILD_URL="${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY:-naidrahiqa/android_kernel_xiaomi_mt6768-k419}/actions/runs/${GITHUB_RUN_ID:-0}"
REPO_URL="${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY:-naidrahiqa/android_kernel_xiaomi_mt6768-k419}"
DATE=$(date +%d/%m/%y 2>/dev/null || echo "??/??/??")

# KSU tag extraction — supports both pinned (:= v4.2.0-rc2) and dynamic ($(shell ...)) formats
KSU_VER_TAG="v4.1.0"
KSU_VER_CODE=""
if [ -f resukisu/Kbuild ]; then
	# Try pinned format first: KSU_TAG_NAME    := v4.2.0-rc2
	KSU_TAG_VAL=$(grep '^KSU_TAG_NAME' resukisu/Kbuild | head -1 | sed 's/.*:= *//')
	# Strip any $(shell ...) wrapper if present
	KSU_TAG_VAL=$(echo "$KSU_TAG_VAL" | sed 's/\$(shell .*)//; s/^ *//; s/ *$//')
	[ -n "$KSU_TAG_VAL" ] && KSU_VER_TAG="$KSU_TAG_VAL"
	# Extract KSU_VERSION (computed: 30000 + local + 700)
	KSU_LOCAL=$(grep '^KSU_LOCAL_VERSION' resukisu/Kbuild | head -1 | sed 's/.*:= *//')
	[ -n "$KSU_LOCAL" ] && KSU_VER_CODE=$((30000 + KSU_LOCAL + 700))
fi

# NOTIFY_BRANCH: override saat announce build lintas-branch (notify-tested workflow)
BRANCH="${NOTIFY_BRANCH:-${GITHUB_REF_NAME:-$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")}}"
ANDROID_TARGET="AOSP"
case "$BRANCH" in
	*24.0*|*lineage-24*)
		ANDROID_TARGET="Android 17 / Lineage 24.0"
		;;
	*23.2*|*lineage-23*)
		ANDROID_TARGET="Android 16 / Lineage 23.2"
		;;
	*22*|*lineage-22*)
		ANDROID_TARGET="Android 15 / Lineage 22"
		;;
	*21*|*lineage-21*)
		ANDROID_TARGET="Android 14 / Lineage 21"
		;;
	*20*|*lineage-20*)
		ANDROID_TARGET="Android 13 / Lineage 20"
		;;
esac

function html_escape() {
	if [ -n "$1" ]; then
		echo "$1" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g'
	else
		sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g'
	fi
}

function tg_send() {
	local target="$1" message="$2" thread_id="${3:-}" buttons="${4:-}"
	local extra_args=()
	if [ -n "$thread_id" ]; then
		extra_args+=(-d "message_thread_id=${thread_id}")
	fi
	if [ -n "$buttons" ]; then
		extra_args+=(-d "reply_markup=${buttons}")
	fi
	local resp
	resp=$(curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
		-d chat_id="${target}" \
		"${extra_args[@]}" \
		-d text="${message}" \
		-d parse_mode="HTML" \
		-d disable_web_page_preview=true)
	if ! echo "$resp" | grep -q '"ok":true'; then
		echo "Telegram API error: $(echo "$resp" | grep -o '"description":"[^"]*"' | cut -d\" -f4)"
		return 1
	fi
	return 0
}

function tg_photo() {
	local target="$1" photo_url="$2" caption="$3" thread_id="${4:-}" buttons="${5:-}"
	local extra_args=()
	if [ -n "$thread_id" ]; then
		extra_args+=(-d "message_thread_id=${thread_id}")
	fi
	if [ -n "$buttons" ]; then
		extra_args+=(-d "reply_markup=${buttons}")
	fi
	local resp
	resp=$(curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendPhoto" \
		-d chat_id="${target}" \
		-d photo="${photo_url}" \
		-d caption="${caption}" \
		-d parse_mode="HTML" \
		"${extra_args[@]}")
	if ! echo "$resp" | grep -q '"ok":true'; then
		echo "Telegram photo API error: $(echo "$resp" | grep -o '"description":"[^"]*"' | cut -d\" -f4)"
		return 1
	fi
	return 0
}

function tg_document() {
	local target="$1" doc_path="$2" caption="$3" thread_id="${4:-}"
	local extra_args=()
	if [ -n "$thread_id" ]; then
		extra_args+=(-F "message_thread_id=${thread_id}")
	fi
	local resp
	resp=$(curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendDocument" \
		-F chat_id="${target}" \
		-F document=@"${doc_path}" \
		-F caption="${caption}" \
		-F parse_mode="HTML" \
		"${extra_args[@]}")
	if ! echo "$resp" | grep -q '"ok":true'; then
		echo "Telegram document API error: $(echo "$resp" | grep -o '"description":"[^"]*"' | cut -d\" -f4)"
		return 1
	fi
	return 0
}

function build_start() {
	local safe_commit_msg
	safe_commit_msg=$(html_escape "$COMMIT_MSG")
	local msg="🍡 <b>Mocchipyon</b> · <code>${VERSION}</code> · <b>[${BRANCH}]</b>
━━━━━━━━━━━━━━━━━━━━
🔨 <b>Building...</b>
🌿 <b>Branch:</b> <code>${BRANCH}</code> (${ANDROID_TARGET})
<code>${SHA}</code> ${safe_commit_msg}
<a href='${BUILD_URL}'>Build Log</a>"

	local target_group="${GROUP_ID:-$CHANNEL_ID}"
	if [ -n "$target_group" ]; then
		tg_send "$target_group" "$msg" "$TOPIC_CI" && echo "Start notification sent to CI topic." || echo "Start notification to CI topic FAILED."
	fi
}

function build_success() {
	local changelog_file="${1:-}"
	local zip_file="${2:-}"

	if [ -z "$zip_file" ] || [ ! -f "$zip_file" ]; then
		zip_file=$(ls Mocchipyon-*.zip 2>/dev/null | head -1)
	fi

	local changelog_items=""
	if [ -n "$changelog_file" ] && [ -f "$changelog_file" ]; then
		changelog_items=$(grep '^- ' "$changelog_file" 2>/dev/null | head -20 | html_escape)
	fi
	if [ -z "$changelog_items" ] && [ -f "CHANGELOG.md" ]; then
		changelog_items=$(awk '/^## /{if(found)exit; found=1; next} found && /^- /{print}' CHANGELOG.md 2>/dev/null | head -20 | html_escape)
	fi

	local safe_commit_msg
	safe_commit_msg=$(html_escape "$COMMIT_MSG")

	# 1. KIRIM NOTIFIKASI KE GAMBAR KIRI (Supergroup Naidrahiqa Stuff -> Topic ⁉️ Selene CI)
	# HANYA "build berhasil" — TANPA link download, tanpa changelog, tanpa tombol.
	# Pengumuman download dikirim terpisah lewat status `tested` SETELAH device tes booting.
	local notif_msg="🍡 <b>Mocchipyon</b> · <code>${VERSION}</code> · <b>[${BRANCH}]</b>
━━━━━━━━━━━━━━━━━━━━
✅ <b>Build succeeded</b>
🌿 <b>Branch:</b> <code>${BRANCH}</code> (${ANDROID_TARGET})
📦 <code>$(basename "$zip_file")</code>${BUILD_TIME:+ · ⏱ $((BUILD_TIME / 60))m$((BUILD_TIME % 60))s}
<code>${SHA}</code> ${safe_commit_msg}
<a href='${BUILD_URL}'>Build Log</a>

<i>Belum diuji — pengumuman download menyusul setelah tes booting aman.</i>"

	local target_group="${GROUP_ID:-$CHANNEL_ID}"
	if [ -n "$target_group" ]; then
		tg_send "$target_group" "$notif_msg" "$TOPIC_CI" "" && echo "Success notification sent to CI topic." || echo "Success notification to CI topic FAILED."
	fi

	# 2. KIRIM FILE KERNEL .ZIP KE GAMBAR KANAN (Private Channel 'Nai project update')
	if [ -n "$CHANNEL_ID" ] && [ -n "$zip_file" ] && [ -f "$zip_file" ]; then
		local file_size
		file_size=$(du -h "$zip_file" | cut -f1)
		local doc_caption="🍡 <b>Mocchipyon Kernel</b> · <code>${VERSION}</code> · <b>[${BRANCH}]</b>
━━━━━━━━━━━━━━━━━━━━
<b>Device:</b> Redmi 10 (selene) · MT6768 · Linux 4.19
🌿 <b>Target:</b> <code>${BRANCH}</code> (${ANDROID_TARGET})
📦 <b>File:</b> <code>$(basename "$zip_file")</code>
<b>Root:</b> ReSukiSU <code>${KSU_VER_TAG}</code>${KSU_VER_CODE:+ (${KSU_VER_CODE})}
<b>Redirection:</b> NoMount v20
<b>Size:</b> ${file_size}
<b>Commit:</b> <code>${SHA}</code> ${safe_commit_msg}

Changelog:
${changelog_items:-<i>No changes recorded</i>}

⚠️ <i>Flash via AnyKernel3 recovery (TWRP/OrangeFox).</i>"

		tg_document "$CHANNEL_ID" "$zip_file" "$doc_caption" && echo "Kernel zip document sent to release channel." || echo "Failed to send kernel zip to release channel."
	fi
}

function build_tested() {
	local notes="${1:-booting aman}"
	local download_url="${2:-${REPO_URL}/releases/tag/${TAG}}"
	local zip_name="${TAG}.zip"

	local changelog_items=""
	if [ -f "CHANGELOG.md" ]; then
		changelog_items=$(awk '/^## /{if(found)exit; found=1; next} found && /^- /{print}' CHANGELOG.md 2>/dev/null | head -20 | html_escape)
	fi

	local notif_msg="🍡 <b>Mocchipyon</b> · <code>${VERSION}</code> · <b>[${BRANCH}]</b>
━━━━━━━━━━━━━━━━━━━━
✅ <b>Tested — booting aman</b>
<b>Redmi 10</b> · selene · MT6768 · Linux 4.19 (CIP)
🌿 <b>Target:</b> <code>${BRANCH}</code> (${ANDROID_TARGET})
📦 <b>File:</b> <code>${zip_name}</code>
⚠️ ReSukiSU <code>${KSU_VER_TAG}</code>${KSU_VER_CODE:+ (${KSU_VER_CODE})} · NoMount v20
🧪 <b>Catatan:</b> ${notes}

Changelog:
${changelog_items:-<i>No changes recorded</i>}"

	local BUTTONS='{"inline_keyboard":[[{"text":"⬇️ Download","url":"'"${download_url}"'"}],[{"text":"📱 ReSukiSU APK","url":"https://github.com/ReSukiSU/ReSukiSU/releases/tag/'"${KSU_VER_TAG}"'"}],[{"text":"📦 NoMount","url":"https://github.com/maxsteeel/nomount/releases"}]]}'

	local target_group="${GROUP_ID:-$CHANNEL_ID}"
	if [ -n "$target_group" ]; then
		tg_send "$target_group" "$notif_msg" "$TOPIC_CI" "$BUTTONS" && echo "Tested notification sent to CI topic." || echo "Tested notification to CI topic FAILED."
	fi
}

function build_failed() {
	local error_log="${1:-build.log}"
	local error_context="No error context available."
	local error_type="UNKNOWN ERROR"
	local failed_step="Unknown step"

	if [ "${MAKE_EXIT_CODE:-1}" -eq 0 ]; then
		# make succeeded — a later pipeline step (verify/package) failed
		error_type="CI STEP ERROR"
		failed_step="Post-build step (verify/package)"
		if [ -f "$error_log" ]; then
			error_context=$(tail -12 "$error_log")
		fi
	elif [ -f "$error_log" ]; then
		if grep -q "make\[" "$error_log" && grep -q "Error" "$error_log"; then
			error_type="MAKE ERROR"
		elif grep -q "fatal:" "$error_log"; then
			error_type="FATAL ERROR"
		elif grep -q "error:" "$error_log"; then
			error_type="COMPILE ERROR"
		fi

		if grep -q "CC\s" "$error_log" || grep -q "\.c:" "$error_log"; then
			failed_step="Build kernel (compile error)"
		elif grep -q "LD\s" "$error_log" || grep -q "ld.lld:" "$error_log"; then
			failed_step="Build kernel (link error)"
		else
			failed_step="Build kernel (make error)"
		fi

		error_context=$(grep -iE "(\.c:[0-9]+:|\.S:[0-9]+:|error:|fatal error:|clang: error:)" "$error_log" | grep -v "sub-make" | head -20)
		if [ -z "$error_context" ]; then
			error_context=$(tail -12 "$error_log")
		fi
	fi

	local safe_error_type safe_failed_step safe_error_context
	safe_error_type=$(html_escape "$error_type")
	safe_failed_step=$(html_escape "$failed_step")
	safe_error_context=$(html_escape "$error_context")

	local simple_msg="🍡 <b>Mocchipyon</b> · <code>${VERSION}</code> · <b>[${BRANCH}]</b>
━━━━━━━━━━━━━━━━━━━━
🌿 <b>Branch:</b> <code>${BRANCH}</code> (${ANDROID_TARGET})
❌ <b>${safe_error_type}</b>
<a href='${BUILD_URL}'>Check Log</a>"

	local target_group="${GROUP_ID:-$CHANNEL_ID}"
	if [ -n "$target_group" ]; then
		# Kirim ringkasan error ke topic ⁉️ Selene CI
		tg_send "$target_group" "$simple_msg" "$TOPIC_CI" && echo "Fail notification sent to CI topic." || echo "Fail notification to CI topic FAILED."

		# Kirim cuplikan log ke topic 🔍 log di supergroup
		if [ -n "$TOPIC_LOG" ] && [ -f "$error_log" ]; then
			local log_lines
			log_lines=$(wc -l < "$error_log" 2>/dev/null || echo "0")
			local log_tail
			log_tail=$(tail -c 3000 "$error_log" 2>/dev/null | html_escape)
			local topic_log_msg="📋 <b>Build Log (${log_lines} lines)</b>
<b>Tag:</b> <code>${TAG}</code>
<b>Branch:</b> <code>${BRANCH}</code> (${ANDROID_TARGET})
<b>Step:</b> ${safe_failed_step}

<pre><code>${log_tail}</code></pre>"
			tg_send "$target_group" "$topic_log_msg" "$TOPIC_LOG" && echo "Log sent to log topic." || echo "Log to log topic FAILED."
		fi
	fi

	# Kirim ke Gambar Kanan (Private Channel 'Nai Error Dump')
	if [ -n "$ERROR_CHANNEL_ID" ]; then
		local detail_msg="🍡 <b>Mocchipyon</b> · <code>${VERSION}</code> · <b>[${BRANCH}]</b>
🌿 <b>Branch:</b> <code>${BRANCH}</code> (${ANDROID_TARGET})
<b>${safe_error_type}</b> · ${safe_failed_step}

<pre><code>${safe_error_context}</code></pre>
<a href='${BUILD_URL}'>Full Log</a>"
		tg_send "$ERROR_CHANNEL_ID" "$detail_msg" && echo "Error log sent to Nai Error Dump." || echo "Error log to Nai Error Dump FAILED."
	fi
}

case "$STATUS" in
	start)
		build_start
		;;
	success)
		build_success "$4" "$5"
		;;
	failed)
		build_failed "$4"
		;;
	tested)
		build_tested "$4" "$5"
		;;
	*)
		echo "Unknown status: $STATUS"
		echo "Usage: notify-telegram.sh <start|success|failed|tested> <version> <tag> [arg4] [arg5]"
		exit 1
		;;
esac
