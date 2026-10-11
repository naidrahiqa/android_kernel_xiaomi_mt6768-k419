#!/bin/bash
# Telegram notify: multibuild release published, with per-variant statistics.
#
# Env:
#   RELEASE_TAG   e.g. R01 (required)
#   RELEASE_URL   release page URL (required)
#   STATS_DIR     stats directory (default: stats)
#   KCK_NOTIFY    path to kit notify script (default: kit/scripts/notify-telegram.sh)
#   TELEGRAM_*    destination env, passed through to notify-telegram.sh
set -euo pipefail

TAG="${RELEASE_TAG:?RELEASE_TAG is required}"
URL="${RELEASE_URL:?RELEASE_URL is required}"
# post to the CI topic AND the release channel — the channel is where users watch
export KCK_CUSTOM_ALL=1
STATS_DIR="${STATS_DIR:-stats}"
KCK_NOTIFY="${KCK_NOTIFY:-kit/scripts/notify-telegram.sh}"
VARIANT_ORDER="xxksu-nomount xxksu bakasu-nomount bakasu"

STATS_BLOCK=""
for v in $VARIANT_ORDER; do
  f="$STATS_DIR/$v.env"
  [ -f "$f" ] || continue
  # shellcheck disable=SC1090
  . "$f"
  STATS_BLOCK+="• ${VARIANT}: ${DURATION} | md5: ${MD5}"$'\n'
done
STATS_BLOCK="${STATS_BLOCK:-• stats unavailable}"
SHA_SHORT="${GITHUB_SHA:-unknown}"
SHA_SHORT="${SHA_SHORT:0:7}"

HTML="🐾 <b>PawwwNunungggg</b> · <code>${TAG}</code>
━━━━━━━━━━━━━━━━━━━━
✅ <b>Multibuild Released — 4 variants</b>
🌿 <b>Branch:</b> <code>PawwwNunungggg24.0</code>
💬 <code>${SHA_SHORT}</code>

📊 <b>Build Statistics:</b>
<pre><code>${STATS_BLOCK%$'\n'}</code></pre>

📦 4 zip assets (xxKSU / BakaSU × NoMount on/off)
🔗 <a href='${URL}'>Download ${TAG}</a>"

exec "$KCK_NOTIFY" custom "$HTML"
