---
id: 0021
title: Boot hang (layar hitam → watchdog reset) saat probe dvfs SCP gagal — wait_scp_dvfs_init_done tanpa batas memblokir PID 1
status: fixed
severity: critical
area: drivers
opened: 2026-10-18
updated: 2026-10-18
fix_commit: "565594246e00"
verified_on: ""
tags: [scp, cm4, dvfs, boot, hang, watchdog, reboot, mtk]
related: [0020]
---

## Issue

`scp_init()` memutar `wait_scp_dvfs_init_done()` sampai flag diset oleh
probe dvfs. Kalau probe **gagal**, flag tidak pernah ada → PID 1
terkunci di loop itu selamanya → layar hitam, watchdog reset
(gejala: bootloop logo/hang di awal boot).

## Evidence

Dari commit body (riset backport, bukan reproduksi di selene):

- Pemicu konkret: DT yang dilewatkan bootloader punya node
  `scp_dvfs` **tanpa** `dvfs-opp` → probe gagal → flag tak pernah diset.
- `wait_scp_dvfs_init_done()` hanya `pr_warn` sekali setelah 3 detik
  lalu **tetap loop** — peringatan ada, tapi boot tidak pernah lanjut.
- Konsekuensi di teori: "The screen stays black and the watchdog
  resets the device" — cocok dengan klasifikasi boot-hang/watchdog.

## Root cause

Loop tunggu probe dvfs SCP tanpa batas waktu; kegagalan probe diubah
menjadi deadlock boot, bukan fallback (SCP disabled + boot lanjut).

## Fix

`565594246e00` — `wait_scp_dvfs_init_done()` mengembalikan
`-ETIMEDOUT` setelah 3 detik; `scp_init()` lalu membiarkan SCP
**disabled** dan boot diteruskan (fungsionalitas SCP/co-processor yang
hilang lebih baik daripada HP tidak bisa nyala sama sekali).

## Verification

- [x] build lokal hijau: `MAKE_EXIT=0` + `Image.gz-dtb`
- [ ] flash → boot normal ke launcher (path normal: dvfs probe sukses,
      tidak ada perubahan perilaku)
- [ ] path gagal (kalau DT pernah bermasalah): boot **tetap lanjut**
      dengan log `-ETIMEDOUT`/warn dari jalur wait — bukan hang

## Regression test

Kalau SCP ternyata dibutuhkan tapi mati (mis. gejala MP3/agen SCP):
cek dmesg `scp` — jangan nonaktifkan timeout-nya (balik ke hang lama).
