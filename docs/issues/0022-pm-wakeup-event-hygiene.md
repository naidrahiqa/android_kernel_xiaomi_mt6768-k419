---
id: 0022
title: Wakeup event hygiene — s2idle_wake berulang, alarmtimer tahan wake 2 dtk, statistik wakeup tak berpath stabil
status: fixed
severity: high
area: kernel
opened: 2026-10-18
updated: 2026-10-18
fix_commit: "c4ef02e5e943 9c0c6ccd2763 3fc09f3275bf"
verified_on: ""
tags: [pm, wakeup, s2idle, suspend, power, alarmtimer, sysfs]
related: [0020]
---

## Issue

Satu issue dengan tiga perbaikan higiene wakeup PM:

1. **`s2idle_wake()` dipanggil berulang** — `pm_system_wakeup()`
   memanggil `s2idle_wake()` setiap kali `pm_abort_suspend` bertambah,
   padahal sekali saja setelah counter naik sudah cukup untuk
   membangunkan dari s2idle. Panggilan berulang = usaha bangun yang
   tidak perlu (overhead di jalur suspend yang sudah sensitif).
2. **Alarmtimer menahan wake source 2 detik tetap** —
   `alarmtimer_suspend()` membatalkan suspend (return `-EBUSY`) untuk
   alarm yang menyala dalam 2 detik, dan menahan wake source penuh
   2 detik supaya sistem tidak re-suspend sebelum userspace
   menangani alarm. 2 detik = worst case tetap yang bikin sistem
   terjaga jauh lebih lama dari perlu pada tiap alarm jangka dekat.
3. **Statistik wakeup tak berpath stabil** — device statistik wakeup
   diparentkan ke device hardware terkait; path sysfs tiap event
   bergantung deskripsi hardware, dan parent vendor bisa bawa label
   yang tak bisa dibaca suspend service (mis. `sysfs_fingerprint`).
   Android melabel sumber wakeup berdasar path sysfs → labeling
   inkonsisten.

## Evidence

- Commit asli (Sultan Alsawaf, kerneltoast — backport ke tree ini via
  branch perf): "Calling s2idle_wake() once after pm_abort_suspend is
  incremented is all that's needed... Avoid multiple unnecessary
  attempts".
- "The s2idle machinery already provides the synchronization needed
  to make this safe" — argumen keamanan dari penulis aslinya.
- **Capture log device 18 Okt 2026 (7,7 jam uptime, build
  `gc28eede47d5f`, sebelum batch ini di-flash):**
  - `/sys/power/suspend_stats`: `success 2649`, `fail 2202` →
    **45,4% percobaan suspend gagal**; `failed_freeze 613`,
    `failed_suspend 1335`.
  - `last_failed_dev: alarmtimer`, `last_failed_errno: -16` (EBUSY),
    `last_failed_step: freeze`.
  - Batterystats history (5,6 hari): **1.789 abort dengan
    `Callback failed on alarmtimer ... returned -16`** — korelasi
    langsung dengan temuan alarmtimer di atas; total 11.142 suspend
    abort dengan `mt635x-auxadc` 737 dan freezer refusal 38 di
    antaranya (target `failed_freeze`).

## Root cause

1. Tidak ada syarat "cukup sekali" pada jalur abort s2idle; setiap
   pemanggil `pm_system_wakeup()` ikut memicu `s2idle_wake()`.
2. Jendela wake alarmtimer dikunci konstan 2 detik — worst case, bukan
   kebutuhan nyata; waktu sisa alarm + 1 ms sudah cukup.
3. Parent device statistik wakeup = device hardware, bukan lokasi
   virtual yang stabil dan terbaca semua pihak.

## Fix

- `c4ef02e5e943` — jalankan wakeup hanya saat `pm_abort_suspend` tepat
  menyentuh 1 (transisi 0→1), bukan di setiap kenaikan.
- `9c0c6ccd2763` — tahan wake source hanya sampai alarm benar-benar
  menyala (sisa waktu alarm + 1 ms), bukan penuh 2 detik. Pendekatan
  yang sama ada di XANMOD dan tree mainline turunan lain
  (upstream: lineage-24.0-perf `37e90946ce2d`).
- `3fc09f3275bf` — parent semua device statistik wakeup ke akar
  virtual sehingga semua event hidup di path stabil
  `/sys/devices/virtual/wakeup/...` (upstream:
  lineage-24.0-perf `e63276643b9d`).

## Verification

- [x] build lokal hijau: `MAKE_EXIT=0` + `Image.gz-dtb` (ketiga commit)
- [ ] flash → suspend/resume normal (layar off → on, alarm tetap
      membangunkan, `dumpsys alarm` tidak berubah pola)
- [ ] cek `/sys/kernel/debug/wakeup_sources` — sumber wakeup tidak
      bertambah aneh setelah batch suspend beberapa siklus
- [ ] **banding `/sys/power/suspend_stats` pasca-flash vs baseline
      2649 success / 2202 fail (45,4%)** — rasio fail harus turun;
      `last_failed_dev: alarmtimer` harus hilang dari daftar
- [ ] path `/sys/devices/virtual/wakeup/` ada dan terisi

## Regression test

- HP tidak bangun dari s2idle saat event (tombol/power/alarm) →
  curigai `c4ef02e5e943`, revert commit tunggal.
- Alarm terlewat (mis. alarm <2 detik tidak membangunkan) →
  curigai `9c0c6ccd2763`, revert commit tunggal (ini gotcha yang
  terdokumentasi di commit message).
- Ada tooling lama yang baca path statistik wakeup hardware lama →
  sesuaikan ke `/sys/devices/virtual/wakeup/` atau revert
  `3fc09f3275bf`; in-tree reader sudah dicek tak ada yang baca path
  lama.
