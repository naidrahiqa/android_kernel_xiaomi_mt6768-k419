#!/bin/bash
set -euo pipefail

# Determine release number
releases=$(gh api repos/naidrahiqa/selene-releases/releases --paginate --jq '.[].tag_name' 2>/dev/null || echo "")
max_num=0
for tag in $releases; do
  if [[ $tag =~ ^R([0-9]+)$ ]]; then
    num=${BASH_REMATCH[1]}
    if [ $num -gt $max_num ]; then max_num=$num; fi
  fi
done
next=$((max_num + 1))
printf "num=%02d\n" "$next" >> "$GITHUB_OUTPUT"
printf "tag=R%02d\n" "$next" >> "$GITHUB_OUTPUT"

# Prepare release notes
KERNEL_VER="4.19.325-PawwwNunungggg-cip136-st20"
COMMIT_SHA="${GITHUB_SHA}"
COMMIT_SHORT="${COMMIT_SHA:0:8}"
DATE_UTC=$(date -u '+%Y-%m-%d %H:%M UTC')

cat > release-notes.md <<'NOTES'
## PawwwNunungggg ${REL_TAG}

**Kernel:** `4.19.325-PawwwNunungggg-cip136-st20`  
**Commit:** `${COMMIT_SHORT}` (PawwwNunungggg24.0)  
**Date:** ${DATE_UTC}  
**Toolchain:** Greenforce Clang 24.0.0

### Root Drivers
- **xxKSU** `v3.3.0-70` · `KSU_VERSION=32670` · UAPI v5
- **BakaSU** `v4.2.0-rc3` · `KSU_VERSION=35223` · manual hook

### Variants (4 assets)
| Asset | Driver | NoMount | Size |
|---|---|---|---|
| `PawwwNunungggg-xxksu-nomount-R${GITHUB_RUN_NUMBER}-*.zip` | xxKSU | ✅ | ~15 MB |
| `PawwwNunungggg-xxksu-R${GITHUB_RUN_NUMBER}-*.zip` | xxKSU | ❌ | ~15 MB |
| `PawwwNunungggg-bakasu-nomount-R${GITHUB_RUN_NUMBER}-*.zip` | BakaSU | ✅ | ~15 MB |
| `PawwwNunungggg-bakasu-R${GITHUB_RUN_NUMBER}-*.zip` | BakaSU | ❌ | ~15 MB |

### Changelog
*(auto dari CHANGELOG.md header terbaru)*
NOTES

# Substitute variables
sed -i "s/\${REL_TAG}/${REL_TAG}/g" release-notes.md
sed -i "s/\${COMMIT_SHORT}/${COMMIT_SHORT}/g" release-notes.md
sed -i "s/\${DATE_UTC}/${DATE_UTC}/g" release-notes.md
sed -i "s/\${GITHUB_RUN_NUMBER}/${GITHUB_RUN_NUMBER}/g" release-notes.md

cat release-notes.md

# Create release
gh release create ${REL_TAG} \
  --repo naidrahiqa/selene-releases \
  --title "${REL_TAG}" \
  --notes-file release-notes.md \
  artifacts/*.zip
