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
| `TELEGRAM_CHANNEL_ID` | Telegram group ID (`Naidrahiqa Stuff`) |
| `TELEGRAM_TOPIC_CI` | Thread ID untuk CI notifications (`47` — Selene CI topic) |
| `TELEGRAM_TOPIC_LOG` | Thread ID untuk build logs (`8` — log topic) |
| `PAT_TOKEN` | GitHub Personal Access Token (untuk release) |

### Workflow Structure

```
push to Mocchipyon23.2
  → Checkout
  → Generate version tag
  → Install build dependencies (Greenforce Clang + cross-compilers)
  → Build kernel (selene_defconfig)
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

### Setup — Group with Topics
- **Group**: "Naidrahiqa Stuff" (forum topics enabled)
- **CI topic**: thread_id `47` (notifications: start, success, failure)
- **Log topic**: thread_id `8` (build log upload)

### Format
```
🔨 Build Started
Kernel: MT6768 4.19.325
Branch: Mocchipyon23.2
Tag: Mocchipyon-nightly-20260914-a4e679c
Commit: a4e679c

✅ Build berhasil! / ❌ Build gagal! Cek log.
```

### Workflow Secrets
- `TELEGRAM_BOT_TOKEN` — bot token
- `TELEGRAM_CHANNEL_ID` — group ID (`-1004414006944`)

### Gotcha: Thread IDs Hardcoded
**DO NOT** use `${{ secrets.TELEGRAM_TOPIC_CI }}` in curl — GitHub Actions silently strips the `-d message_thread_id` line from the log AND the actual command execution. Thread IDs are hardcoded directly in `build.yml`:
- CI notifications: `message_thread_id=47`
- Log topic: `message_thread_id=8`

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
