---
name: ci-cd-github-actions
description: GitHub Actions CI/CD untuk kernel MT6768. Build workflow, Telegram notifications, AnyKernel3 packaging, release automation. Trigger: ci, cd, github actions, workflow, build, release, telegram.
---

# CI/CD — GitHub Actions

## Workflow Location

`.github/workflows/build.yml`

## Setup Requirements

### Repository Secrets
| Secret | Description |
|--------|-------------|
| `TELEGRAM_BOT_TOKEN` | Telegram bot token untuk notifikasi |
| `TELEGRAM_CHANNEL_ID` | Telegram channel/group ID |
| `PAT_TOKEN` | GitHub Personal Access Token (untuk release) |

### Workflow Structure

```
push to Mocchipyon23.2
  → Checkout
  → Generate version tag
  → Install build dependencies (Greenforce Clang + cross-compilers)
  → Build kernel (mt6768_defconfig + selene.config)
  → Verify critical configs
  → Package AnyKernel3
  → Upload artifacts
  → Create GitHub Release (optional)
  → Notify Telegram
```

## Build Triggers

### Auto trigger
- Push ke branch `Mocchipyon23.2`
- Path filter: ignore `*.md`, `.opencode/**`

### Manual trigger
- Workflow dispatch dengan variant selection (nightly/test)

## Version Tag Format

```
Mocchipyon-{variant}-{date}-{short_hash}
Example: Mocchipyon-nightly-20260914-a4e679c
```

## AnyKernel3 Packaging

- Source: `scripts/anykernel.sh` (dari project 4.14)
- AK3 repo: `osm0sis/AnyKernel3` pinned ke commit `dca9dc3`
- Output: `Mocchipyon-{tag}.zip`

## Telegram Notifications

### Format
```
🔨 Build Started
Kernel: MT6768 4.19.325
Branch: Mocchipyon23.2
Tag: Mocchipyon-nightly-20260914-a4e679c

✅ Build berhasil! / ❌ Build gagal! Cek log.
```

### Dual channel
- Main channel: `TELEGRAM_CHANNEL_ID`
- Error channel: `TELEGRAM_ERROR_CHANNEL_ID` (optional)

## Debug Build Failures

1. Check GitHub Actions logs
2. Download `build-log-{hash}` artifact
3. Search for `error:` patterns
4. Common errors:
   - Clang IAS → check `build-system-fixes` skill
   - Missing config → check `defconfig-management` skill
   - Link error → check `resukisu-integration` skill

## Release Workflow

```bash
# Manual release
gh workflow run build.yml -f variant=nightly

# Check status
gh run list --limit 5

# Download artifact
gh run download {run_id} -n {artifact_name}
```
