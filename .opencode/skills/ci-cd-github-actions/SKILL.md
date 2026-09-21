---
name: ci-cd-github-actions
description: GitHub Actions CI/CD untuk kernel MT6768. Build workflow, Telegram notifications, AnyKernel3 packaging, ccache acceleration, release automation. Trigger: ci, cd, github actions, workflow, build, release, telegram.
---

# CI/CD — GitHub Actions

## Workflow Location

`.github/workflows/build.yml`

## Setup Requirements

### Repository Secrets
| Secret | Description | Target |
|--------|-------------|--------|
| `TELEGRAM_BOT_TOKEN` | Telegram bot token (`@naidradev_bot`) | Bot API |
| `TELEGRAM_GROUP_ID` | Telegram Supergroup ID (`-1004414006944` — Naidrahiqa Stuff) | Gambar Kiri |
| `TELEGRAM_TOPIC_CI` | Thread ID untuk CI notifications (`47` — Selene CI topic) [HANYA NOTIF, NO ZIP] | Gambar Kiri |
| `TELEGRAM_TOPIC_LOG` | Thread ID untuk build logs (`8` — log topic) [Cuplikan log error] | Gambar Kiri |
| `TELEGRAM_CHANNEL_ID` | Telegram Private Channel ID (`-1003752197403` — Nai project update) | Gambar Kanan (Kirim File .ZIP) |
| `TELEGRAM_ERROR_CHANNEL_ID` | Telegram Private Channel ID (`-1003945405514` — Nai Error Dump) | Gambar Kanan (Error Dump) |

### Notification & Artifact Routing
1. **Gambar Kiri — Supergroup Naidrahiqa Stuff (`-1004414006944`)**:
   - **Topic `⁉️ Selene CI` (#47)**: HANYA menerima teks notifikasi Build Start dan Build Success. **TIDAK dikirimi file .zip**.
   - **Topic `🔍 log` (#8)**: Menerima potongan 3000 karakter terakhir `build.log` jika build gagal.
2. **Gambar Kanan — Private Channels**:
   - **Channel `Nai project update` (`-1003752197403`)**: Menerima file kernel `.zip` AnyKernel3 via `sendDocument` lengkap dengan caption spesifikasi & commit.
   - **Channel `Nai Error Dump` (`-1003945405514`)**: Menerima error dump saat kompilasi gagal.

> [!NOTE]
> GitHub Releases menggunakan default token `${{ secrets.GITHUB_TOKEN }}` dengan permission `contents: write`.

### Workflow Pipeline

```
Trigger (Push / Dispatch / Tag)
  → Checkout (fetch-depth: 0)
  → Read VERSION & Determine Channel (nightly / beta / stable)
  → Cache Greenforce Clang (hindari download ulang ~1.5GB)
  → Install build dependencies & cross-compilers
  → Build kernel clean from scratch (selene_defconfig)
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

## Toolchain Caching (Greenforce Clang)

- GitHub Actions cache (`actions/cache@v4`) digunakan **eksklusif** untuk toolchain Greenforce Clang (`greenforce-clang/`, ~1.5GB) agar runner tidak perlu mendownload ulang setiap kali build.
- **Kernel objek (`.o`) TIDAK di-cache** (tanpa ccache) sehingga setiap build kernel selalu 100% bersih dari awal (*clean build from scratch*), menjamin tidak ada artefak usang (*stale objects*) atau bug kompilasi yang terlewat selama fase porting.
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
