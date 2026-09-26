---
name: ci-cd-github-actions
description: GitHub Actions CI/CD untuk kernel MT6768. Build workflow, Telegram notifications, AnyKernel3 packaging, ccache acceleration, release automation. Trigger: ci, cd, github actions, workflow, build, release, telegram.
---

# CI/CD — GitHub Actions

## Workflow Location

- `.github/workflows/build.yml` — build, package, release, notif
- `.github/workflows/notify-tested.yml` — notif "tested & booting aman" (manual dispatch)

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
   - **Topic `⁉️ Selene CI` (#47)**: Notif teks saja — **TIDAK dikirimi file .zip**:
     - `start` — build dimulai
     - `success` — **singkat, TANPA link download / tombol / changelog** (hanya "✅ Build succeeded" + info ringkas)
     - `tested` — **notif lengkap + tombol ⬇️ Download**, hanya setelah build dites di device & booting aman (lihat workflow `notify-tested.yml`)
     - `failed` — ringkasan error
   - **Topic `🔍 log` (#8)**: Menerima potongan 3000 karakter terakhir `build.log` jika build gagal.
2. **Gambar Kanan — Private Channels**:
   - **Channel `Nai project update` (`-1003752197403`)**: Menerima file kernel `.zip` AnyKernel3 via `sendDocument` — sumber zip buat dites (tetap dikirim tiap build sukses).
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
  → Package AnyKernel3 (boot-only, tanpa LK/DTBO)
  → Upload artifacts
  → Generate changelog & GitHub Release (beta/stable only)
  → Notify Telegram (success = notif singkat; zip → private channel)
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
- Includes: `Image.gz-dtb` (atau `Image.gz` / `Image`).
- Keamanan: Partisi `dtb`, `dtbo.img`, dan `lk` DILARANG di-bundle dalam zip AnyKernel3 karena berisiko brick. Automated check memblokir file partisi sensitif (`lk`, `dtbo`, `dtb`, `preloader`, `tee`, `sspm`, `vbmeta`, dll).

## Telegram Notifications

### Dua Fase (by design — jangan digabung!)
1. **Build sukses** → topic Selene CI: notif **singkat tanpa link download**
   ("✅ Build succeeded" + branch/file/build log). Zip tetap dikirim ke private
   channel `Nai project update` supaya bisa dites.
2. **Setelah tes di device & booting aman** → kirim notif **lengkap + tombol ⬇️ Download**:

   ```bash
   # tanpa tag = ambil build SUKSES terakhir otomatis
   gh workflow run "Announce Tested Build" -f notes="booting aman, GPU ok"

   # atau pilih build tertentu
   gh workflow run "Announce Tested Build" \
     -f tag="Mocchipyon-23.2-v0.1.0-nightly-20260926-abcdef1" \
     -f notes="booting aman"
   ```

   Resolve download URL otomatis: GitHub Release jika tag punya release,
   selain itu halaman Actions run (artifact zip). Implementasi:
   `notify-telegram.sh tested <version> <tag> [notes] [download_url]`.

### Setup — Group with Topics
- **Group**: "Naidrahiqa Stuff" (forum topics enabled)
- **CI topic**: thread_id `47` (start, success singkat, tested lengkap + download, failed)
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
