# Issue #0010 — Multibuild 4 Varian + Release Otomatis

## Latar Belakang
Ingin build kernel 4 varian sekaligus tiap push ke `PawwwNunungggg24.0`:
1. **xxksu-nomount** — xxKSU + NoMount aktif
2. **xxksu** — xxKSU tanpa NoMount
3. **bakasu-nomount** — BakaSU + NoMount aktif + hostsredirect
4. **bakasu** — BakaSU tanpa NoMount + hostsredirect

Release dikemas di repo terpisah `naidrahiqa/selene-releases` dengan nama `R01`, `R02`, … (urutan via API count).

## Root Cause / Motivasi
- Sebelumnya hanya 1 build (xxksu + nomount) via `build.yml`
- Butuh opsi root driver (xxKSU vs BakaSU) + toggle NoMount untuk user
- Release otomatis biar gampang distribusi zip ke user

## Solusi
### 1. Tree Changes
- **BakaSU import**: `drivers/bakasu/` dari upstream `Baka-SU/BakaSU@v4.2.0-rc3`
  - Patch Kbuild: pin statis `KSU_VERSION=35223` (rev-count 4523), bypass `.git` check
  - File `BAKASU_REV_COUNT` untuk tracking rev-count dinamis tiap sync
  - Port `hostsredirect` dari folksu → `drivers/bakasu/feature/hostsredirect.{c,h}`
  - Tambah `CONFIG_KSU_HOSTSREDIRECT` di Kconfig BakaSU
- **Kconfig choice**: `drivers/Kconfig` tambah `choice ROOT_SOLUTION` (KSU_XXKSU / KSU_BAKASU)
- **drivers/Makefile**: `obj-$(CONFIG_KSU_XXKSU) += kernelsu/` / `obj-$(CONFIG_KSU_BAKASU) += bakasu/`
- **selene_defconfig**: default `CONFIG_KSU_XXKSU=y`, `CONFIG_NOMOUNT=y`

### 2. Kit Enhancement (`kernel-ci-kit`)
- `example-build.yml` + `action.yml`: input baru `config_overrides`
- `build-kernel.sh`: hook `CONFIG_OVERRIDES` env → `scripts/config` + `olddefconfig`

### 3. CI Workflow (`.github/workflows/multibuild.yml`)
- Matrix 4 job → call kit reusable workflow dengan `config_overrides` per varian
- Zip naming: `PawwwNunungggg-{variant}-R##-{sha7}-{YYYYMMDD}.zip`
- Release job (needs: build, if: success):
  - Download 4 artifact zip
  - Hitung nomor release via `gh api repos/naidrahiqa/selene-releases/releases` → `R##`
  - `gh release create R##` dengan 4 asset + release notes berisi versi driver
  - Butuh classic PAT `RELEASES_TOKEN` (repo scope) di source repo

### 4. Version Tooling
- `scripts/check-bakasu.sh` — mirror `check-xxksu.sh` untuk BakaSU
- Release notes include versi kedua driver

## Testing
- [x] Local build 2 leg: `xxksu-nomount` (baseline) + `bakasu-nomount` (validate)
- [x] CI dry-run via `workflow_dispatch` / push (run `38149689931` + `38153028203`)
- [x] Verifikasi release terbuat di `naidrahiqa/selene-releases` dengan 4 asset
- [x] Verifikasi Telegram notif: release done + statistik (`notify sent -> thread 47`)

## Status
- [x] Phase 1: Kit enhancement (`config_overrides`)
- [x] Phase 2: BakaSU import + hostsredirect + Kconfig/Makefile wiring
- [x] Phase 3: multibuild.yml + release job
- [x] Phase 4: check-bakasu.sh + issue doc
- [x] Testing & verifikasi CI (run `38153028203` — semua job success)

## Verified
- [x] Build 4 varian success di CI (ccache hit ~98%, 2m42s–4m11s per varian)
- [x] Release `R01` terbentuk di `naidrahiqa/selene-releases` dengan 4 zip
- [ ] Flash test minimal 1 varian di device fisik
- [ ] xxKSU & BakaSU manager detection OK

## Catatan
- `RELEASES_TOKEN` (classic PAT) harus dibuat manual di GitHub Settings → Secrets → Actions
- Kit changes backward-compat: `config_overrides` default kosong → behavior lama tidak berubah
- BakaSU `KSU_VERSION` pin statis via `BAKASU_REV_COUNT`; update via script saat sync upstream

## Update 2026-10-11 (CI rework final)
- Satu file `build-all.yml`: `prepare` (R## via API count) → 4 job build sequential (kit composite action per varian, `zip_name_template` pakai tag R##) → `release` (download zip+stats, `scripts/ci/release.sh`, notif `notify-release.sh`) → `notify-failure` (status per job).
- Bug yang difix: heredoc release-notes di YAML nggak ke-indent → block scalar putus → parse error alias `*`; pindahin ke script (`release.sh`).
- Stats: `scripts/ci/build-stats.sh` → `stats/<varian>.env` (durasi, md5, size, ccache) → artifact → digest jadi `### Build Statistics` di notes + Telegram.
- Run lama `38146311462` (workflow versi lama) di-cancel biar nggak bikin release setengah matang.
- Bug kedua: `needs.prepare.outputs.tag` cuma keliatan di job pertama — jobs 2-4 zip-nya jadi `...-bakasu--<sha>-...`. Fix: `prepare` masuk `needs` tiap job build ( rantai sequential tetap ).
- R01 pertama (nama zip rusak) dihapus + tag di-cleanup; R01 final dari run `38153028203` → https://github.com/naidrahiqa/selene-releases/releases/tag/R01 (4 zip benar, statistik lengkap, Telegram OK).
