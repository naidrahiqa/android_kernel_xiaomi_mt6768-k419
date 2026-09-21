---
name: ci-cd-github-actions
description: GitHub Actions CI/CD untuk kernel MT6768. Build workflow, Telegram notifications, AnyKernel3 packaging, ccache acceleration, release automation. Trigger: ci, cd, github actions, workflow, build, release, telegram.
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

> [!NOTE]
> GitHub Releases menggunakan default token `${{ secrets.GITHUB_TOKEN }}` dengan permission `contents: write`.

### Workflow Pipeline

```
Trigger (Push / Dispatch / Tag)
  → Checkout (fetch-depth: 0)
  → Read VERSION & Determine Channel (nightly / beta / stable)
  → Setup ccache (~25m → ~8m rebuilds)
  → Install Clang & cross-compilers
  → Build kernel (selene_defconfig)
  → Verify critical configs & dangerous partitions
  → Package AnyKernel3 (embed Kaeru LK if present)
  → Upload artifacts
  → Generate changelog & GitHub Release (beta/stable only)
  → Notify Telegram (with build time & file attachment)
```

## Build Triggers & Release Channels

| Channel | Trigger | Output | GitHub Release? |
|---|---|---|---|
| **nightly** | Push ke `Mocchipyon23.2` (ignore `*.md`, `.opencode/**`, `VERSION`) | `Mocchipyon-v{ver}-nightly-{date}-{hash}.zip` | ❌ Artifact only (90d) |
| **beta** | Manual `workflow_dispatch` (channel: beta) | `Mocchipyon-v{ver}-beta.{date}.zip` | ✅ Pre-release + changelog |
| **stable** | Git tag `v*` (misal `v0.1.0`) | `Mocchipyon-v{ver}.zip` | ✅ Full release + changelog |

## Build Performance (ccache)

- `ccache` diaktifkan di CI menggunakan GitHub Actions cache (`~/.cache/ccache`).
- Durasi clean build: ~25-30 menit.
- Durasi rebuild dengan ccache hit: ~6-8 menit.
- Waktu build dilaporkan di notifikasi Telegram (`*Build:* Xm Ys`).

## AnyKernel3 Packaging

- Source: `scripts/anykernel.sh`
- AK3 repo: `osm0sis/AnyKernel3` pinned ke commit `dca9dc3`
- Includes: `Image.gz-dtb` (atau `Image.gz`), `dtb`, `dtbo.img`, dan opsional `lk_a.img` jika Kaeru LK tersedia di `kaeru/kaeru_selene.bin`.
- Keamanan: Ada automated check yang memblokir file partisi sensitif (`preloader`, `tee`, `sspm`, `vbmeta`, dll).

## Telegram Notifications

### Setup — Group with Topics
- **Group**: "Naidrahiqa Stuff" (forum topics enabled)
- **CI topic**: thread_id `47` (notifikasi start, build success dengan file attachment zip, build failed)
- **Log topic**: thread_id `8` (upload log saat build error)

### Gotcha: Thread IDs Hardcoded
**DO NOT** use `${{ secrets.TELEGRAM_TOPIC_CI }}` in curl — GitHub Actions silently strips `-d message_thread_id` jika variable kosong atau tersembunyi. Thread IDs di-hardcode langsung di `build.yml`:
- CI notifications: `message_thread_id=47`
- Log topic: `message_thread_id=8`

## Debug Build Failures

1. Check GitHub Actions logs
2. Download `build-log-{hash}` artifact dari Actions run
3. Search for `error:` patterns
4. Common errors:
   - Clang IAS → check `build-system-fixes` skill
   - Missing config → check `defconfig-management` skill
   - Link error → check `resukisu-integration` skill
