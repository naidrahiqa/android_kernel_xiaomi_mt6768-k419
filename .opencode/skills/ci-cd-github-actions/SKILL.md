---
name: ci-cd-github-actions
description: GitHub Actions CI/CD untuk kernel MT6768. Build workflow, Telegram notifications, AnyKernel3 packaging, ccache acceleration, release automation. Trigger: ci, cd, github actions, workflow, build, release, telegram.
---

# CI/CD — GitHub Actions

## Workflow Location

- `.github/workflows/build.yml` — build, package, release, notif

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
     - `success` — **singkat, TANPA link download / tombol / changelog** (hanya "✅ Build succeeded" + info ringkas; file zip dikirim terpisah ke channel private)
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
| **nightly** | Push ke `PawwwNunungggg24.0` (satu-satunya branch build; `PawwwNunungggg23.2` frozen) — ignore `*.md`, `.opencode/**`, `VERSION` | `PawwwNunungggg-v{ver}-nightly-{date}-{hash}.zip` | ❌ Artifact only (90d) |
| **beta** | Manual `workflow_dispatch` (channel: beta) | `PawwwNunungggg-v{ver}-beta.{date}.zip` | ✅ Pre-release + changelog |
| **stable** | Git tag `v*` (misal `v0.1.0`) | `PawwwNunungggg-v{ver}.zip` | ✅ Full release + changelog |

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

### Flow — 4 notif aja (final, 27 Sep 2026)
1. **`start`** → topic Selene CI: build dimulai.
2. **`failed`** → topic Selene CI: ringkasan error **+ baris error pertama** (`error: …`); detail log ke channel `Nai Error Dump`.
3. **`success`** → topic Selene CI: **teks singkat** ("✅ Build succeeded" + ringkas, tanpa file/tombol/changelog panjang).
4. **File zip** → channel private `Nai project update`: file + changelog + **SHA-256 pendek** + tombol **⬇️ Download (GitHub)** (link Actions run). Tanpa banner "belum diuji".

> Workflow `notify-tested.yml` (announce "tested & booting aman") sudah **DIHAPUS** — jangan ditambah lagi tanpa diskusi.
> `build.yml` pakai `concurrency: cancel-in-progress` — push beruntun cuma build terakhir; notif result di-guard `success() || failure()` supaya run yang di-cancel diam.

### Setup — Group with Topics
- **Group**: "Naidrahiqa Stuff" (forum topics enabled)
- **CI topic**: thread_id `47` (start, success singkat, failed)
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
