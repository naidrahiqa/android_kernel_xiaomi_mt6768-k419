---
name: versioning-releases
description: Versioning scheme, release channels (nightly/beta/stable), localversion branding, GitHub Releases, and release workflow for Mocchipyon Kernel. Trigger: version, release, tag, changelog, channel, nightly, beta, stable, localversion.
---

# Versioning & Release Channels — Mocchipyon Kernel

Pedoman versioning, release channels, branding kernel version, dan otomatisasi release untuk Mocchipyon Kernel.

## 1. Versioning Scheme

Format: `Mocchipyon-v<major>.<minor>.<patch>[-<channel>]`

| Component | Format | Keterangan |
|---|---|---|
| **Major** | `v1.0.0` | Milestone besar: first boot, first daily-usable stable, major architecture rework |
| **Minor** | `v0.1.0`, `v0.2.0` | Penambahan fitur baru: BBR, WireGuard, driver baru, subsystem upgrade |
| **Patch** | `v0.1.1` | Bugfix / security fix only tanpa fitur baru |
| **Channel** | `nightly`, `beta` | Suffix channel (stable tidak memiliki suffix channel) |

### Single Source of Truth: `VERSION` File

File `VERSION` di root repository mengontrol versioning:

```bash
MOCCHIPYON_VERSION=0.1.0
MOCCHIPYON_CODENAME=Kucing
MOCCHIPYON_STATUS=unstable
```

- **`MOCCHIPYON_VERSION`**: Semver version string (dibaca oleh CI dan release scripts)
- **`MOCCHIPYON_CODENAME`**: Nama rilis bertema (misal tema kucing/hewan per major cycle)
- **`MOCCHIPYON_STATUS`**: Status porting saat ini (`unstable`, `testing`, `stable`)

---

## 2. Release Channels

| Channel | Trigger | Tag Format | GitHub Release? | Changelog | Target Audience |
|---|---|---|---|---|---|
| **Nightly** | Auto push ke `Mocchipyon23.2` | `Mocchipyon-v{ver}-nightly-{date}-{hash}` | ❌ No (Artifact 90d) | ❌ No | Developer & internal test |
| **Beta** | Manual `workflow_dispatch` (channel: beta) | `Mocchipyon-v{ver}-beta.{date}` | ✅ Pre-release + Zip | ✅ Auto-changelog | Early testers |
| **Stable** | Push git tag `v*` (misal `v0.1.0`) | `Mocchipyon-v{ver}` | ✅ Full Release + Zip | ✅ Auto-changelog | All users |

### Zip File Naming

- Nightly: `Mocchipyon-v0.1.0-nightly-20260921-60e26c0.zip`
- Beta: `Mocchipyon-v0.1.0-beta.20260921.zip`
- Stable: `Mocchipyon-v0.1.0.zip`

---

## 3. Kernel `uname -r` Branding (`localversion`)

Kernel Makefile menggabungkan semua file yang berawalan `localversion*` secara alfabetis (`scripts/setlocalversion`):

1. `localversion` → `-Mocchipyon`
2. `localversion-cip` → `-cip136`
3. `localversion-st` → `-st20`

Hasil string `uname -r` di perangkat:
```
4.19.325-Mocchipyon-cip136-st20
```

> [!NOTE]
> Urutan ini mempertahankan upstream tracking CIP dan ST sembari menampilkan branding `-Mocchipyon` di depan.

---

## 4. GitHub Releases & Auto-Changelog

Pada channel **Beta** dan **Stable**, CI secara otomatis:
1. Mengambil rentang commit antara tag sebelumnya dan `HEAD` (atau 20 commit terakhir jika belum ada tag).
2. Mengkategorikan commit berdasarkan conventional commits:
   - `✨ Features` (`feat:`, `add:`)
   - `🐛 Fixes` (`fix:`)
   - `⚡ CI/CD` (`ci:`)
   - `📋 Other`
3. Membuat GitHub Release via `softprops/action-gh-release@v2`.
4. Mengunggah AnyKernel3 flashable zip ke Release.

---

## 5. Release Playbook (Cara Release)

### A. Manual Beta Release

1. Pastikan `VERSION` file sudah sesuai.
2. Buka GitHub Actions → `Build MT6768 Kernel 4.19`.
3. Klik **Run workflow** → pilih channel **beta** → klik **Run workflow**.
4. CI akan build, paket AnyKernel3, buat GitHub Pre-release, dan kirim notifikasi Telegram.

### B. Stable Release

1. Update `VERSION` di root jika versi naik:
   ```bash
   sed -i 's/MOCCHIPYON_VERSION=.*/MOCCHIPYON_VERSION=0.2.0/' VERSION
   git commit -am "build: bump version to v0.2.0"
   git push origin Mocchipyon23.2
   ```
2. Buat tag release berawalan `v`:
   ```bash
   git tag -a v0.2.0 -m "Release Mocchipyon v0.2.0"
   git push origin v0.2.0
   ```
3. GitHub Actions otomatis tertrigger oleh tag `v*`, mengeset channel ke `stable`, membuat Full GitHub Release, dan upload zip.
