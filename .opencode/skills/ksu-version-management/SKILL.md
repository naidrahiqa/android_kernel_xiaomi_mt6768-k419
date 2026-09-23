---
name: ksu-version-management
description: Manage ReSukiSU driver version pins, sync with upstream, generate version notes, and keep documentation in sync. Use when user says "update KSU", "update ReSukiSU", "new KSU version", "bump KSU", "generate notes resukisu", or checks for upstream releases.
---

# KSU Version Management — ReSukiSU Version Notes & Sync

Panduan dan otomatisasi manajemen versi ReSukiSU untuk kernel MT6768 (Mocchipyon 4.19 & Phrolova 4.14).

## Current State

| Info | Value |
|---|---|
| **Driver** | ReSukiSU (`ReSukiSU/ReSukiSU`) |
| **Driver Path** | `resukisu/` (4.19) / `resukisu/kernel/` (4.14) |
| **Latest Commit** | `5cfdd725aa92` (2026-09-22) |
| **Commit Count (`KSU_LOCAL_VERSION`)** | `4460` |
| **Latest Tag** | `v4.2.0-rc2` |
| **KSU_VERSION Code** | `35160` |
| **Hook Mode** | Manual hook (`CONFIG_KSU_MANUAL_HOOK=y`) |

## Rumus Perhitungan KSU_VERSION

```
KSU_VERSION = 30000 + KSU_LOCAL_VERSION + 700
```
- `KSU_LOCAL_VERSION` adalah jumlah total commit di branch `main` ReSukiSU (`git rev-list --count HEAD`).
- Contoh: 4460 commit → `30000 + 4460 + 700` = **35160**.

> **CRITICAL GOTCHA:** Karena `resukisu/` disimpan langsung (bukan git submodule terpisah), pemanggilan `git rev-list --count HEAD` di dalam Kbuild kernel akan menghitung total commit kernel Linux (830.000+) sehingga KSU_VERSION menjadi 865.000+!
> **Wajib selalu di-pin manual** di `resukisu/Kbuild` (atau `resukisu/kernel/Kbuild`).

## Generate Notes Otomatis

Gunakan script helper yang sudah disediakan:

```bash
# Output format Markdown (untuk GitHub Release / docs)
.github/scripts/generate-ksu-notes.sh markdown

# Output format Changelog (untuk append ke CHANGELOG.md)
.github/scripts/generate-ksu-notes.sh changelog

# Output format Telegram HTML (untuk notifikasi bot)
.github/scripts/generate-ksu-notes.sh tg
```

## Workflow Update ReSukiSU

### 1. Cek Upstream Latest
```bash
# Clone shallow atau cek commit terbaru
git clone --depth=1 https://github.com/ReSukiSU/ReSukiSU.git /tmp/resukisu-latest
cd /tmp/resukisu-latest
git log -1 --format="%h %s"
git describe --tags --always
git rev-list --count HEAD
```

### 2. Hitung KSU_VERSION
```bash
COMMITS=$(git rev-list --count HEAD)
KSU_VER=$((30000 + COMMITS + 700))
echo "KSU_LOCAL_VERSION := $COMMITS"
echo "KSU_VERSION := $KSU_VER"
```

### 3. Update File Code
Bandingkan folder `kernel/` dan `uapi/` upstream dengan folder tree di repo kernel. Salin file C/H yang berubah (jangan menimpa local patches di Kbuild).

### 4. Pin Versi di Kbuild
Update nilai di `resukisu/Kbuild`:
```makefile
KSU_LOCAL_VERSION := <JUMLAH_COMMIT>
KSU_VERSION := $(shell expr 30000 + $(KSU_LOCAL_VERSION) + 700)
KSU_TAG_NAME    := <TAG_NAME>
KSU_COMMIT_SHA  := <SHORT_SHA>
KSU_BRANCH_NAME := main
```

### 5. Generate Notes & Update Dokumentasi
```bash
# Tambahkan notes ke CHANGELOG.md
.github/scripts/generate-ksu-notes.sh changelog >> CHANGELOG.md

# Update referensi docs jika diperlukan
sed -i 's/{OLD_KSU_VER}/{NEW_KSU_VER}/g' AGENTS.md
```

### 6. Verifikasi & Commit
Pastikan notifikasi Telegram dan CI build membaca tag & version code yang baru:
```bash
git add resukisu/ .github/ CHANGELOG.md AGENTS.md
git commit -m "build: update ReSukiSU to <TAG> (<SHA>, KSU_VERSION <CODE>)"
git push
```
