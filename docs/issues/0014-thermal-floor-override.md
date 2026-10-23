---
id: 0014
title: Thermal throttle CPU dinonaktifkan oleh floor XM_THERM; SoC 51-56°C saat pemakaian ringan, drain ikut naik
status: fixed
severity: high
area: kernel
opened: 2026-10-14
updated: 2026-10-14
fix_commit: c0fb3c228528
verified_on: ""
tags: [thermal, battery, drain, ppm, xm_therm]
related: [0005, 0007]
---

## Issue

Keluhan owner (14 Okt 2026): drain baterai cepat; HP tembus 45°C saat
pemakaian sosmed **padahal tidak sedang ngecas**; ngecas panas masih
diterima, tapi thermal management tetap dibutuhkan.

## Evidence

Device: `65cb03c00702`, build `g1951bbc122b3` (≈ `f793229d29b4`),
uptime ~12 menit, USB plugged (USB 500mA), screen on.

Suhu (snapshot `drain-dump/baseline-20261014-181922`):

```
mtktspmic=51459  mtktscpu=51100  mtktsAP=49000  mtktsbattery=44600
```

dmesg — cap thermal di-override berulang:

```
thermal_sys: cpu_limits: cluster 1 cap 1176000 kHz raised to floor 2000000 kHz
thermal_sys: cpu_limits: cluster 0 cap 1100000 kHz raised to floor 1800000 kHz
[Thermal/TZ/CPU][Warning] active 1 -> 0 but Tc(55000) > cetj(-1)
[Thermal/TZ/CPU]exit but Tc(54500) > cetj(-1)
```

(Berulang sampai Tc 56.9°C — thermal trip naik-turun tanpa efek karena
cap selalu diangkat ke floor.)

Bukti pendukung drain:

- `Mem: 5650804K used / 5850920K total`, `Swap: 2109620K used / 2923728K`
  dalam 12 menit — reclaim/zram churn tinggi (app sosmed berat:
  WA 612MB PSS, TikTok×2 ~800MB, plus FB/IG/Shopee/Binance resident).
- `load average: 12.80, 13.72, 9.73` (8 core) saat snapshot.
- Battery health: `Maximum capacity 4876300 / Design 6000000` = **81%** —
  kehilangan ~1.1Ah kapasitas (faktor hardware, bukan kernel).
- Device belum pernah suspend sejak boot (`last_suspend_time 0.0`),
  wajar karena `mStayOn=true` saat charging + screen on.

## Root cause

`CONFIG_THERMAL_XM_FREQ_FLOOR=y` (commit `e74df8e5ee9b`, 8 Okt 2026)
menclamp setiap cap `mi_thermald` dari bawah di `cpu_limits_store()`
(`drivers/thermal/thermal_core.c:1337`). `selene_defconfig` menyetel
floor = **OPP maksimum** (CLUSTER0=1800000, CLUSTER1=2000000):

```
CONFIG_THERMAL_XM_FREQ_FLOOR=y
CONFIG_THERMAL_XM_FREQ_FLOOR_CLUSTER0=1800000
CONFIG_THERMAL_XM_FREQ_FLOOR_CLUSTER1=2000000
```

Konsekuensinya thermal tidak pernah bisa menurunkan frekuensi CPU —
effectively CPU thermal throttling mati; backstop tersisa hanya thermal
shutdown (`mtktscpu-sysrst`). Trade-off ini disadari saat dibuat:
floor dipilih karena `mi_thermald` ROM meng-pin kedua cluster di
~1.1GHz saat hangat (HP lambat), dan userspace tidak bisa meng undo-nya
(PDM owns `scaling_max_freq`, write = -EPERM).

## Fix

Diterapkan `c0fb3c228528` (disetujui owner 14 Okt 2026, tuning-guard:
satu perubahan per siklus):

| | Nilai |
|---|---|
| **Sebelum** | CLUSTER0=1800000 / CLUSTER1=2000000 (throttle mati; SoC 51-57°C sustain) |
| **Proposed** | CLUSTER0=1270000 / CLUSTER1=1443000 (thermal boleh menurunkan sampai situ; mid-OPP, sosmed tetap halus; daya turun signifikan karena OPP lebih rendah = tegangan lebih rendah) |
| **Risiko** | Performa turun saat thermal pressure aktif (by design — itu gunanya); kalau floor terlalu rendah, keluhan "HP lemot saat panas" (motivasi floor lama) bisa balik |
| **Plan** | 1 commit defconfig terpisah, revert = 2 baris |

## Verification

- [ ] flash build dengan floor baru → dmesg `raised to floor ... 1270000/1443000` saat thermal pressure
- [ ] suhu sosmed non-charging turun (target < 45°C mtktscpu)
- [ ] drain per jam unplugged diukur (belum diukur — device tercolok saat triage)

## Regression test

- Kalau HP terasa lemot saat hangat → floor naik bertahap (1375000/1532000),
  jangan langsung balik ke maks.
- Pantau juga `mi_thermald` behavior asli (dia tetap menulis cap ~1.1GHz;
  floor hanya mengangkat cap ke minimum yang kita izinkan).
- Terkait: oops `remove_request`/`adios_dispatch_request` di sesi
  sebelum reboot (build `g282da32602fa`, kworker kblockd) — scheduler
  device kini mq-deadline (lihat issue 0013); adios tetap terpasang
  sebagai opsional, pantau kalau ada yang mengaktifkannya lagi.
