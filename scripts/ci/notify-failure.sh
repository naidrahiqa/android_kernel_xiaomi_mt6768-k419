#!/bin/bash
# Telegram notify: multibuild failed — one line per job so it's obvious which
# variant broke.
#
# Env (job results from the workflow `needs` context):
#   RES_PREPARE RES_XXKSU_NM RES_XXKSU RES_BAKASU_NM RES_BAKASU RES_RELEASE
#   KCK_NOTIFY  path to kit notify script (default: kit/scripts/notify-telegram.sh)
set -euo pipefail

KCK_NOTIFY="${KCK_NOTIFY:-kit/scripts/notify-telegram.sh}"
# post to the CI topic AND the release channel — the channel is where users watch
export KCK_CUSTOM_ALL=1

row() {
  local name="$1" result="$2" mark
  case "$result" in
    success) mark="✅" ;;
    failure) mark="❌" ;;
    cancelled) mark="⏹" ;;
    skipped) mark="⏭" ;;
    *) mark="❓" ;;
  esac
  printf '%s <b>%s</b>: %s' "$mark" "$name" "$result"
}

ROWS=""
ROWS+="$(row "prepare (R##)"    "${RES_PREPARE:-skipped}")"$'\n'
ROWS+="$(row "xxksu-nomount"    "${RES_XXKSU_NM:-skipped}")"$'\n'
ROWS+="$(row "xxksu"            "${RES_XXKSU:-skipped}")"$'\n'
ROWS+="$(row "bakasu-nomount"   "${RES_BAKASU_NM:-skipped}")"$'\n'
ROWS+="$(row "bakasu"           "${RES_BAKASU:-skipped}")"$'\n'
ROWS+="$(row "release"          "${RES_RELEASE:-skipped}")"

SHA_SHORT="${GITHUB_SHA:-unknown}"
SHA_SHORT="${SHA_SHORT:0:7}"
BUILD_URL="${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY:-}/actions/runs/${GITHUB_RUN_ID:-0}"

HTML="🐾 <b>PawwwNunungggg</b> · CI
━━━━━━━━━━━━━━━━━━━━
❌ <b>Multibuild Failed</b>
🌿 <b>Branch:</b> <code>PawwwNunungggg24.0</code>
💬 <code>${SHA_SHORT}</code>

📍 <b>Job status:</b>
<pre><code>${ROWS}</code></pre>

🔗 <a href='${BUILD_URL}'>Build Log</a>"

exec "$KCK_NOTIFY" custom "$HTML"
