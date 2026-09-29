---
name: flashing-boot-test
description: Cycle flash kernel AK3 ke selene + verifikasi boot per batch — download artifact CI, flash via ReSukiSU Manager / recovery sideload / dieD fastboot bridge, checklist verify (uname, config.gz, feature probe), rollback. Trigger: flash, install kernel, sideload, fastboot, recovery, artifact, download zip, boot test, verify, uname, rollback, reboot bootloader.
---

# Flashing & Boot-Test Cycle (Selene)

Rutinitas wajib tiap batch: **push → CI hijau → download → flash → verify** —
1 batch = 1 flash, verify dulu sebelum push batch berikutnya (kebijakan:
"tes boot tiap kali").

## 1. Download artifact CI

```bash
gh run list -R naidrahiqa/android_kernel_xiaomi_mt6768-k419 -L3   # ambil run id, status
gh run download <run_id> -R naidrahiqa/android_kernel_xiaomi_mt6768-k419 -D /tmp/opencode/flash/<nama>
```

Isi dua artifact: zip AK3 (`PawwwNunungggg-24.0-v0.1.0-nightly-YYYYMMDD-<hash>.zip`, ~16M) + `kernel-config-<hash>/.config` (referensi).

## 2. Metode flash (pilih sesuai kondisi HP)

### A. ReSukiSU Manager — **metode utama (dari sistem jalan)**
1. `adb -s <serial> push <zip> /sdcard/Download/` (pakai `-s` kalau >1 device)
2. ReSukiSU Manager → **Install** → pilih zip → flash → reboot
3. AK3 cuma tulis `boot` — aman (JANGAN pernah bundle `lk`/`dtbo` — lihat AGENTS CRITICAL).
4. Syarat: root/kernel sekarang masih jalan. Kalau HP gak boot → metode B.

### B. Recovery sideload (via dieD bridge — dipakai kalau manager gak bisa)
Boot image recovery = **dieD**, bukan build kita (boot kita gak punya recovery ramdisk):
```bash
adb reboot bootloader
fastboot flash boot_a /home/naidra/Downloads/dieD_vendor_v2.3_perfmgr419_6/boot.img
fastboot reboot recovery
# tunggu state recovery → sideload:
adb sideload <zip>.zip
```
**Gotcha**: attempt sideload PERTAMA hampir selalu gagal `connection closed` →
tunggu state `sideload` → **retry, jangan nyerah** → jalan, auto-reboot abis selesai.

### C. HP totally mati / bootloop logo
→ skill `unbrick-brom` (BROM/mtkclient). dieD bridge tetap dicoba dulu selama fastboot hidup.

## 3. Verifikasi (wajib, semua)

```bash
# poll boot
for i in $(seq 1 30); do [ "$(adb shell getprop sys.boot_completed)" = 1 ] && break; sleep 5; done

adb shell uname -r                    # HARUS contain g<hash> commit yang di-flash
adb shell su -c id                    # root + konteks u:r:ksu:s0
adb shell su -c "zcat /proc/config.gz | grep -E '<symbol batch>'"   # config batch
adb shell su -c "zcat /proc/config.gz | grep -E 'DEBUG_LIST|BUG_ON_DATA_CORRUPTION'"  # pastikan tetap off
```

Feature probe per jenis batch:
| Batch | Probe |
|---|---|
| qdisc/net | `adb shell su -c "cat /proc/sys/net/core/default_qdisc"` + config `NET_SCH_FQ=y` |
| zram | `adb shell su -c "cat /sys/block/zram0/comp_algorithm"` (bracket = aktif; init vendor paksa `lz4`) |
| driver baru | node sysfs/dev-nya muncul (mis. `/dev/encore_fas`) + dmesg tanpa `undefined symbol`/oops |
| io-sched | `adb shell su -c "cat /sys/block/sda/queue/scheduler"` (atau `mmcblk0`/`sda` sesuai device) |
| charger | skill `charging-diagnostics` |

`/proc/config.gz` = config AKTIF build terakhir (cara pasti ngecek apa yang
ke-flash — jangan percaya ingatan).

## 4. Rollback / gagal boot

- **Bootloop / gak nyala** → cycle metode B (dieD → recovery → sideload zip build lama yang known-good).
- **Zip build lama**: simpan `/tmp/opencode/flash/morning/` (backup known-good) + artifact lama di `/tmp/opencode/flash/`.
- fastboot **selalu** jalan selama LK stock sehat (kita gak pernah sentuh LK) → dieD bridge = jalan selamat.
- Kalau fastboot juga hilang → BROM: skill `unbrick-brom`.

## Gotchas

- **2 adb connections (USB + tcpip)** → semua perintah harus `adb -s <serial>` (keluhan `more than one device/emulator`).
- `adb tcpip 5555` hilang setelah reboot → re-activate kalau perlu capture live (lihat `charging-diagnostics`).
- CI `concurrency: cancel-in-progress` — push baru = run lama cancel. Push docs pas build jalan = buang build.
- Changelog/feature notif Telegram dihasilkan dari config yang SAMA dengan artifact — kalau fitur gak muncul di notif, cek `.github/scripts/notify-telegram.sh` `build_features()` (aturan: cantumin hanya fitur aktif).
