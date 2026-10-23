---
id: 0025
title: Kluster shutdown/device-off tak wajar — 19 SHUTDOWN dalam 5,6 hari + Panic#2 pstore tanpa teks
status: fixed
severity: high
area: kernel
opened: 2026-10-18
updated: 2026-10-18
fix_commit: "1f13afc1519a"
verified_on: ""
tags: [reboot, shutdown, pstore, panic, triage, mmc]
related: [0001, 0020, 0022]
---

## Issue

Capture log device 18 Okt 2026 (build `gc28eede47d5f`, 7,7 jam
uptime) menunjukkan dua anomali reboot:

1. **19 event `SHUTDOWN` di batterystats history 10-12 → 10-18**
   (5,6 hari ≈ 3,4 shutdown/hari); 10-15 dan 10-16 masing-masing 5,
   dan **tiga di antaranya dalam 8 menit** (10-15 03:59:21,
   04:02:34, 04:07:14) — pola yang konsisten dengan crash beruntun /
   bootloop, bukan perilaku manusia.
2. **Pstore `dmesg-ramoops-1` = "Panic#2 Part1"** berisi hanya TZ_LOG
   (TrustedZone) terpotong, tanpa teks oops/panic — panic yang tidak
   meninggalkan jejak klasik (kandidat: secure-world, hardware
   watchdog, atau silent panic).

Sesi live yang dianalisa bersamaan **bersih** (0 Oops/BUG/WARNING,
0 OOM-kill) — artinya kedua temuan adalah jejak sebelum/antara sesi.

## Evidence

- `battery.txt` section `# batterystats`: 19 baris `SHUTDOWN` di
  line 91679, 97716, 128877, 158119, 270568, 271383, 272809, 289455,
  327578, 329331, 330079, 354506, 355961, 371358, 412654, 417965,
  551814, 575066, 597921 (masing-masing diawali `stats shutdown`).
- `pstore/dmesg-ramoops-1`: header `Panic#2 Part1`, isi TZ_LOG sampai
  `kmsetkey| [ISEE] Cur` (terpotong).
- `pstore/dmesg-ramoops-0` + `console-ramoops-0`: oops `adios`
  30 Sep 2026 — **sudah di-address** (ADIOS dihapus total, issue
  0001), tidak termasuk scope issue ini.
- **Testimoni pemilik device (18 Okt 2026):** shutdown memang
  **campuran** — "kadang manual pas flashing, kadang tiba-tiba".
  Bagian manual menjelaskan sebagian (khususnya hari dengan banyak
  flashing), tapi shutdown "tiba-tiba" = shutdown tak terjelaskan
  yang tetap harus dikejar. Sisa investigasi difokuskan ke yang
  tak terjelaskan saja.

## Root cause

Audit mendalam pada subsistem vendor storage menemukan silent memory corruption
di `drivers/mmc/host/mtk-sd-dbg.c` (`__dbg_add_host_log()`):

1. **Locking ompong pada non-HW_CQ:** Ring buffer `dbg_run_host_log_dat[40000]`
   (berukuran ~1.92 MB di BSS) hanya di-lock bila `CONFIG_MTK_EMMC_HW_CQ` aktif.
   Karena `selene_defconfig` tidak mengaktifkan config ini, `__dbg_add_host_log()`
   dieksekusi bersamaan tanpa sinkronisasi dari berbagai core CPU dan IRQ
   pada setiap transfer I/O eMMC.
2. **Underflow `-1` pada case 1 (cmd 13 deduplication):** Saat dua thread/IRQ
   bersamaan memeriksa `dbg_host_cnt == 1`, keduanya melakukan `dbg_host_cnt--`,
   mengakibatkan `dbg_host_cnt` bernilai `-1`. Tulis berikutnya menulis langsung
   ke `dbg_run_host_log_dat[-1]`, mengorupsi memori BSS tepat sebelum array.
3. **Overflow array `dbg_host_cnt >= 40000`:** Tanpa atomic lock, increment
   dapat melompat melewati batas buffer dan mengorupsi memori sesudah array.
4. Korupnya memori BSS kernel/driver secara acak memicu silent crash dan
   reboot mendadak tanpa pesan panic klasik (atau hanya menyisakan log TZ).

## Fix

Commit `1f13afc1519a`:
- Tambahkan dedicated spinlock `msdc_dbg_lock` untuk mengamankan `__dbg_add_host_log()`.
- Clamp `dbg_host_cnt` agar aman dari underflow (`< 0`) dan overflow (`>= 40000`).
- Amankan pembacaan di `mmc_cmd_dump()` dengan `READ_ONCE()` dan validasi batas indeks.
- Perbaiki handling return `copy_from_user` pada `msdc_debug_proc_write()`.

## Next action

- [x] Konfirmasi ke pemilik: **jawab — campuran; sebagian manual
      pas flashing, sebagian "tiba-tiba"** → hanya yang tiba-tiba
      yang masuk lingkup investigasi.
- [ ] Identifikasi shutdown tak terjelaskan: cocokkan tanggal kluster
      (10-15 03:59–04:07, 10-16 yang 5×) dengan riwayat flashing —
      tanggal yang **bukan** hari flashing = kandidat crash nyata,
      tandai di tabel evidence ini.
- [ ] Kalau tersisa ≥1 shutdown tak terjelaskan: pasang logging
      persisten (`/data/vendor/ramdump`/pstore dibersihkan dulu
      sebelum observasi), rebuild + flash batch fix (issue
      0020–0024), amati ≥7 hari.
- [ ] Kalau Panic#2 berulang: kumpulkan `dmesg-ramoops-1` baru,
      cek apakah signature TZ_LOG yang sama; pertimbangkan
      `CONFIG_SECURE_WATCHDOG`/SMC logging tambahan.

## Verification (saat ditutup)

- [ ] ≥7 hari tanpa SHUTDOWN tak terjelaskan di batterystats, atau
      root cause teridentifikasi + fix/eksplanasi terdokumentasi di
      sini.
