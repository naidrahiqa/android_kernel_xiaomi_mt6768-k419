---
name: unbrick-brom
description: Unbrick Xiaomi selene (MT6768) via BROM mode dengan mtkclient. Flash LK/boot/dtb, dump source, partition backup, mtk-unbrick tool, error DRAM/udev. Trigger: brick, unbrick, brom, mtkclient, dead phone, mati total, bootloop, fastboot gagal, flash gagal.
---

# Unbrick BROM Skill — Xiaomi Selene (MT6768)

## Overview

Device mati total (stuck di MTK BROM port / MTK USB Port VCOM) = preloader/LK rusak.
Satu-satunya jalan: **flash via BROM mode** pakai [bkerler/mtkclient](https://github.com/bkerler/mtkclient).

Catatan nyata: brick 19–26 Sep 2026 **disebabkan flash LK** (AnyKernel3 bundle `lk_a.img` + `do_kaeru=1`). Stock LK direstore → device hidup lagi.

## Kondisi & fakta device

| Item | Nilai |
|---|---|
| Device | Xiaomi selene (Redmi 10 Prime 2022, `21061119AG`), MT6768 |
| GPT | **A/B** — `lk_a/lk_b` (2MB), `boot_a/b`, `dtbo_a/b`, `vbmeta_a/b` |
| BROM USB ID | `0e8d:xxxx` (muncul saat Vol+ + Vol- dicolok) |
| Flash LK | **WAJIB dua-duanya** (`lk_a` + `lk_b`), tidak cukup satu slot |
| DRAM setup | **Butuh `--preloader <file>`** — tanpa itu error `unpack requires a buffer of 12 bytes` |
| adb path | `/home/naidra/Android/Sdk/platform-tools/adb` |
| Python | PEP 668 — pakai venv / `pip install --user` |

## Flash (working flow)

```bash
# 1. Siapkan mtkclient + image stock
git clone https://github.com/bkerler/mtkclient ~/mtkclient
pip install -r ~/mtkclient/requirements.txt   # venv dulu kalau PEP 668

# Image stock (lk/boot/dtbo/vbmeta/preloader) — dump source:
#   https://github.com/naidrahiqa/gitload-dump/releases/tag/dump-miui_SELENEGlobal_V14.0.7.0.TKUMIXM_76066530fb_13.0

# 2. Masuk BROM: MATIKAN HP (tahan power ~10s) → tahan Vol+ + Vol- → colok USB

# 3. Cek koneksi + tabel partisi
python3 ~/mtkclient/mtk.py --preloader /path/preloader.img printgpt

# 4. Flash (contoh restore LK — ingat: DUA SLOT)
python3 ~/mtkclient/mtk.py --preloader preloader.img w lk_a lk.img
python3 ~/mtkclient/mtk.py --preloader preloader.img w lk_b lk.img

# 5. Reboot
python3 ~/mtkclient/mtk.py --preloader preloader.img reset
```

Atau pakai tool wrapper: `mtk-unbrick` di `github.com/naidrahiqa/mtk-unbrick`
(`./unbrick.sh flash <rom_dir>` / `unbrick.bat` — auto GPT map, auto A/B, auto preloader, safety guard).

## Tool: mtk-unbrick (wrapper lokal user)

- Repo: `github.com/naidrahiqa/mtk-unbrick` (working copy: `/tmp/opencode/mtk-unbrick`)
- v0.2.0 = subprocess wrapper mtkclient (protocol homemade v0.1.0 sudah dihapus — tidak pernah jalan)
- Fitur: interactive menu tanpa args, `flash|info|read|erase|backup|reset`, auto `--preloader` dari folder ROM, `--slot a|b|both`, safety skip (`lk/nvram/seccfg/preloader...` butuh `--force`, preloader tidak pernah di-flash)
- Launcher: `unbrick.sh` (Linux, auto-hint udev), `unbrick.bat` (Windows), `50-mtkclient.rules` (udev tanpa sudo)

## Backup (sebelum utak-atik)

Kalau device **hidup** (adb + `su`), backup via dd:

```bash
adb shell su -c 'dd if=/dev/block/by-name/lk_a of=/sdcard/lk_a.img'
adb shell su -c 'dd if=/dev/block/by-name/lk_b of=/sdcard/lk_b.img'
adb pull /sdcard/lk_a.img && adb pull /sdcard/lk_b.img
# atau kalau device mati: mtkclient `r <partisi> <file>`
```

Backup tersimpan: `/home/naidra/Backups/selene-unbrick-20260926/`
(`lk_a.img`, `lk_b.img`, `seccfg.img`, `nvram.img` + md5 — lk_a == lk_b, md5 `7d88995e2470a9c0c5ccf717ac90e93b`)

Partisi kritis yang jangan asal dihapus: `nvram`, `nvdata`, `nvcfg`, `seccfg`, `proinfo`, `protect1/2`, `persist`, `para`, `expdb` — hilang = IMEI/serial lenyap.

## Error & solusi

| Error | Solusi |
|---|---|
| `DRAM setup failed: unpack requires a buffer of 12 bytes` | Tambah `--preloader <preloader.img>` (wajib untuk selene) |
| Device not found | Ulang BROM: cabut → Vol+ + Vol- → colok; ganti kabel/port data |
| `Permission denied` (Linux) | Pasang udev rule (`50-mtkclient.rules`) atau `sudo` |
| Windows: device tidak terdeteksi | Install driver MediaTek Preloader (biasanya otomatis kalau pernah pakai SP Flash Tool) |
| Gagal di tengah flashing | Cabut → replug BROM → ulangi partisi yang gagal |
| `mtkclient not found` | Clone ke `~/mtkclient` atau `--mtkclient /path/mtk.py` / env `MTKCLIENT` |

## JANGAN (brick risk)

1. **JANGAN flash LK** (`lk_a`/`lk_b`) tanpa image stock yang terverifikasi — ini penyebab brick terakhir.
2. **JANGAN flash `dtbo`** — hardware overlay ROM; salah = layar mati.
3. **JANGAN flash `preloader`/`nvram`/`nvdata`/`seccfg`** sembarangan — hard brick / IMEI hilang.
4. **JANGAN pakai AnyKernel3 yang bundle LK/DTBO** — see AGENTS.md flashing rules.
5. **JANGAN asumsi satu slot cukup** — A/B, flash `lk_a` DAN `lk_b`.

## Referensi

- Root cause brick + recovery log: see `AGENTS.md` (Flashing Partisi & Charger DTS rules)
- Dump: `naidrahiqa/gitload-dump` release `dump-miui_SELENEGlobal_V14.0.7.0.TKUMIXM_76066530fb_13.0` (asset: lk.img, boot.img, dtbo.img, vbmeta.img, preloader.img) — asset cepat; codeload lambat
- mtkclient docs: `https://github.com/bkerler/mtkclient` (commands: `printgpt`, `w`, `r`, `e`, `reset`)
