#!/bin/bash
# ==============================================================================
# generate-ksu-notes.sh — Generate ReSukiSU Version Release Notes & Changelog
# ==============================================================================
set -euo pipefail

# Locate Kbuild
KBUILD_PATH=""
if [ -f "resukisu/Kbuild" ]; then
    KBUILD_PATH="resukisu/Kbuild"
elif [ -f "resukisu/kernel/Kbuild" ]; then
    KBUILD_PATH="resukisu/kernel/Kbuild"
else
    echo "Error: Cannot find resukisu/Kbuild or resukisu/kernel/Kbuild" >&2
    exit 1
fi

# Extract version components
KSU_LOCAL_VERSION=$(grep '^KSU_LOCAL_VERSION' "$KBUILD_PATH" | head -1 | sed 's/.*:= *//' | tr -d ' ')
KSU_TAG_NAME=$(grep '^KSU_TAG_NAME' "$KBUILD_PATH" | head -1 | sed 's/.*:= *//' | sed 's/\$(shell .*)//; s/^ *//; s/ *$//')
KSU_COMMIT_SHA=$(grep '^KSU_COMMIT_SHA' "$KBUILD_PATH" | head -1 | sed 's/.*:= *//' | sed 's/\$(shell .*)//; s/^ *//; s/ *$//')
KSU_BRANCH_NAME=$(grep '^KSU_BRANCH_NAME' "$KBUILD_PATH" | head -1 | sed 's/.*:= *//' | sed 's/\$(shell .*)//; s/^ *//; s/ *$//')

# Fallbacks
KSU_LOCAL_VERSION="${KSU_LOCAL_VERSION:-4460}"
KSU_TAG_NAME="${KSU_TAG_NAME:-v4.2.0-rc2}"
KSU_COMMIT_SHA="${KSU_COMMIT_SHA:-5cfdd725}"
KSU_BRANCH_NAME="${KSU_BRANCH_NAME:-main}"
KSU_VERSION=$((30000 + KSU_LOCAL_VERSION + 700))

DATE_TODAY=$(date +%Y-%m-%d 2>/dev/null || echo "2026-09-22")

# Format output mode: markdown (default), tg, or changelog
MODE="${1:-markdown}"

case "$MODE" in
    tg|telegram)
        cat << EOF
⚠️ <b>ReSukiSU ${KSU_TAG_NAME} (${KSU_VERSION})</b>
━━━━━━━━━━━━━━━━━━━━
• <b>Commit:</b> <code>${KSU_COMMIT_SHA}</code> (${KSU_BRANCH_NAME})
• <b>Local Version:</b> ${KSU_LOCAL_VERSION} commits
• <b>Formula:</b> 30000 + ${KSU_LOCAL_VERSION} + 700 = <b>${KSU_VERSION}</b>
• <b>Manager APK:</b> <a href="https://github.com/ReSukiSU/ReSukiSU/releases/tag/${KSU_TAG_NAME}">ReSukiSU ${KSU_TAG_NAME}</a>
EOF
        ;;
    changelog)
        cat << EOF
## ${DATE_TODAY} — ReSukiSU ${KSU_TAG_NAME} Upstream (KSU_VERSION ${KSU_VERSION})

- **ReSukiSU ${KSU_TAG_NAME} (\`${KSU_COMMIT_SHA}\`, KSU_VERSION ${KSU_VERSION}):**
  - Synced driver with upstream ReSukiSU \`${KSU_TAG_NAME}\` + latest commits from \`${KSU_BRANCH_NAME}\` (commit \`${KSU_COMMIT_SHA}\`).
  - Total upstream commits: ${KSU_LOCAL_VERSION}.
  - Pinned version in Kbuild: \`KSU_LOCAL_VERSION := ${KSU_LOCAL_VERSION}\`, \`KSU_TAG_NAME := ${KSU_TAG_NAME}\`, \`KSU_COMMIT_SHA := ${KSU_COMMIT_SHA}\` (\`30000 + ${KSU_LOCAL_VERSION} + 700 = ${KSU_VERSION}\`).
  - Required Manager: ReSukiSU Manager matching KSU_VERSION \`${KSU_VERSION}\` ([GitHub Release](https://github.com/ReSukiSU/ReSukiSU/releases/tag/${KSU_TAG_NAME})).
EOF
        ;;
    markdown|*)
        cat << EOF
### 🛡️ Root Solution: ReSukiSU ${KSU_TAG_NAME}

| Field | Value |
|---|---|
| **Version Tag** | \`${KSU_TAG_NAME}\` |
| **KSU_VERSION Code** | \`${KSU_VERSION}\` (\`30000 + ${KSU_LOCAL_VERSION} + 700\`) |
| **Commit SHA** | [\`${KSU_COMMIT_SHA}\`](https://github.com/ReSukiSU/ReSukiSU/commit/${KSU_COMMIT_SHA}) |
| **Commit Count** | ${KSU_LOCAL_VERSION} commits |
| **Upstream Branch** | \`${KSU_BRANCH_NAME}\` |
| **Hook Mode** | Manual Hook (\`CONFIG_KSU_MANUAL_HOOK=y\`) |
| **Manager APK** | [Download ${KSU_TAG_NAME}](https://github.com/ReSukiSU/ReSukiSU/releases/tag/${KSU_TAG_NAME}) |

> **⚠️ Penting:** Versi Manager APK harus match dengan KSU_VERSION \`${KSU_VERSION}\` agar module & root terdeteksi sempurna.
EOF
        ;;
esac
