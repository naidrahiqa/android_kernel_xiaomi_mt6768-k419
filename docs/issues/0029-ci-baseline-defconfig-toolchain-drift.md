# 0029 — CI baseline EsTehAnget gagal 2× sebelum hijau

**Status:** fixed & verified (build lokal + CI); hardware flash: pending
**Tanggal:** 23 Okt 2026
**Branch:** `EsTehAnget24.0`
**Commit:**
- `b18304328bf7` defconfig: add selene_defconfig from the baseline defconfig plus fragment
- `9b30b0ec3b79` drivers: wlan: store channel tables as unsigned

## Gejala

Tes build baseline baru (mt6768-S + delta creativchic) di kit, run 1 & 2 gagal:

1. Run `39890275567` (`defconfig=mt6768_defconfig`):
   `*** Can't find default configuration "arch/arm64/configs/mt6768_defconfig"!`
   — defconfig baseline ada di subfolder `vendor/`, bukan di root configs.
2. Run `39892504822` (`defconfig=vendor/mt6768_defconfig`): dua error compile
   — `flashlight-core.c` `#define -DKBUILD_BASENAME` (flag nyasar ke define)
   dan `rlm_domain.c` 16× initializer error — keduanya hanya muncul **tanpa**
   fragment `vendor/selene.config`.

## Root cause

1. Baseline memakai resep 2 langkah (`make vendor/mt6768_defconfig` + merge
   `vendor/selene.config`), sedangkan semua entry point (kit default, resep
   lokal) mengharapkan satu target `selene_defconfig`. Rule kbuild `%.config`
   juga tidak bisa melihat subdirektori `vendor/` (wildcard tanpa path itu).
2. Build lokal dengan `selene_defconfig` lulus, tapi CI gagal di
   `rlm_domain.c:399` `-Werror,-Wconstant-conversion` (165 → int8_t) —
   **toolchain drift**: clang lokal (Cirrus `c1100cd9`) diam menerima file itu,
   clang CI menolak. Tabel `gTx_Pwr_Limit_*_Ch` berisi nomor channel s/d 165
   bertipe `int8_t`.

## Fix

1. `selene_defconfig` baru = savedefconfig canonical hasil merge
   `vendor/mt6768_defconfig` + `vendor/selene.config`, plus
   `CONFIG_LOCALVERSION="-EsTehAnget"`. Reproduce-checked: apply ke direktori
   fresh → `.config` byte-identik.
2. Tabel channel + pointer `prChannelList` di `rlm_domain.c` → `uint8_t`.
   Semua pemakaiannya assign ke field `uint8_t` (`ucChannel`, `ucCentralCh`,
   `u1CentralCh`) — roundtrip two's complement sebelumnya sudah mengirim
   channel number asli, jadi bit identik (ukuran `Image.gz-dtb` tidak berubah,
   12223225).

## Verifikasi

- Build lokal Greenforce (Cirrus clang 24.0.0): `MAKE_EXIT=0`, `Image.gz-dtb`
  ada — sebelum dan sesudah patch wlan.
- CI kit run `39899882633`: **hijau** 12m55s, artifact zip + notif channel OK.

## Catatan

- `CONFIG_MTK_AB_OTA_UPDATER` dari fragment dibuang senyap kconfig — simbol
  tidak ada di tree baseline.
- Regenerasi defconfig ke depan: panggil `merge_config.sh` manual pada
  `arch/arm64/configs/vendor/selene.config` (rule `%.config` tidak menemukan
  path vendor).
