---
id: 0005
slug: thermal-throttle-lag
title: CPU ter-cap ~1.1 GHz saat SoC panas — semua terasa lambat
status: fixed
severity: high
area: kernel
opened: 2026-10-08
updated: 2026-10-08
fix_commit: e74df8e5ee9b
verified_on: ""
tags: [thermal, cpufreq, ppm, lag]
related: [0004]
---

## Gejala

HP "kok lambat", scroll nge-lag, semua core terasa mentok. Ditemukan waktu
mendiagnosis issue 0003 (storage): load average 16–23 padahal RAM masih
lega (`MemAvailable` 1.74 GB dari 5.85 GB, PSI `memory full avg300=0.13%`).

## Evidence

```
policy0  aff=0-5  cur=950000   min=900000   max=1100000  hwmax=1800000
policy6  aff=6-7  cur=1087000  min=1087000  max=1176000  hwmax=2000000
```

Kedua cluster ter-cap di OPP pertama saja di atas 1.1 GHz, padahal hw
mampu 1.8 / 2.0 GHz.

Suhu saat itu:

```
mtktsAP   = 44000   (44.0 C)
mtktscpu  = 46900   (46.9 C)
battery   = 405     (40.5 C)
dumpsys battery: AC powered: true, level 96
```

Pelaku di dmesg:

```
[Power/PPM] sys boost by XM_THERM: cluster 1 min/max freq = -1/1176000
[Power/PPM] sys boost by XM_THERM: cluster 0 min/max freq = -1/1100000
```

Di-tulis ulang tiap **< 1 detik** (timestamp `725.59 -> 726.09 -> 726.59 ->
726.91`).

## Root cause

Ini **bukan** setting kernel kita yang salah, dan **bukan** tuning yang
lupa di-revert. Rantainya:

1. Xiaomi thermal daemon (`mi_thermald`, `thermalloadalgod`) memetakan
   sensor `mtktsAP`/`mtktscpu` ke level yang lebih rendah yang lebih rendah.
2. Daemon menuliskan batas frekuensi ke
   `/sys/devices/virtual/thermal/thermal_message/cpu_limits` format
   `cpu<N> <max_khz>`.
3. `drivers/thermal/thermal_core.c` `cpu_limits_store()` meneruskan ke PPM:

```c
mt_ppm_sysboost_set_freq_limit(BOOST_BY_XM_THERMAL, cpu, -1, max);
```

4. PPM membatasi semua governor di bawahnya, jadi `scaling_max_freq`
   yang di-userland **mengembalikan -EPERM**:

```
/system/bin/sh: can't create .../policy6/scaling_max_freq: Permission denied
```

Jadi dari userspace **tidak bisa** menaikkan lagi — daemon menulis ulang
setiap sub-detik.

## Mapping cluster (WAJIB tidak salah paham)

`cpu_limits_store()` memetakan indeks CPU ke cluster:

```c
if (cpu >= 0 && cpu <= 5)   /* little cluster = policy0 */
	cpu = 0;
else                        /* big cluster = policy6 */
	cpu = 1;
```

Jadi **bukan** bug: `cpu1` memang big cluster — tidak, salah. `cpu1` masih
little. Big cluster harus pakai **`cpu6` atau `cpu7`**. Ini sempat
disalahpahami saat investigasi.

## Fix

`CONFIG_THERMAL_XM_FREQ_FLOOR` — kernel menaikkan *dari bawah* setiap cap
XM_THERM, jadi mi_thermald menulis 1 100 000, kernel menaikkan ke
1 800 000 sebelum diteruskan ke PPM. Tidak ada loop, tidak ada module
userspace, tidak ada lawanan daemon.

- `drivers/thermal/Kconfig` — config baru (`depends on MTK_THERMAL`)
- `drivers/thermal/thermal_core.c` — clamp di `cpu_limits_store()`
- `selene_defconfig` — floor 1800000 (little) / 2000000 (big)

### Catatan gate Kconfig

`depends on MTK_PPM` **salah** — `drivers/misc/mediatek/ppm_v3/Makefile`
memakai `obj-y += src/` unconditional, jadi symbol `MTK_PPM` tidak pernah
set (`# CONFIG_MTK_PPM is not set` di `.config`) tapi kodenya tetap
ter-build. Gate yang benar: `MTK_THERMAL` (default y via
`depends on ARCH_MEDIATEK`).

## Verified

Belum — menunggu flash build yang memuat `e74df8e5ee9b`.

Bukti bahwa mekanismenya bekerja (diuji live dengan tulis manual):

```
echo "cpu0 1800000" > .../thermal_message/cpu_limits
echo "cpu6 2000000" > .../thermal_message/cpu_limits
→ policy0 max=1800000 cur=1800000
→ policy6 max=2000000 cur=2000000
```

Lalu di-override `mi_thermald` dalam < 1 detik — yang akan dicegah oleh
floor kernel.

## Risiko (WAJIB dibaca)

Menaikkan floor ke maksimum **mematikan CPU thermal throttling**. Yang
tersisa hanya thermal shutdown (`mtktscpu-sysrst`) yang akan me-reboot
device, bukan mendinginkan. Kalau HP dipakai sambil ngecas + game berat,
SoC bisa kena shutdown thermal.

Kalau kejadian: turunkan floor di `selene_defconfig` (mis. 1500000 /
1710000), **jangan** naikkan `mtkts*` trip point.

## Regression test

1. Flash, buka app berat sambil ngecas selama 10 menit.
2. `cat /sys/devices/system/cpu/cpufreq/policy*/scaling_max_freq` → harus
   tetap di 1800000 / 2000000 meski `mtktscpu` naik.
3. `dmesg | grep sysboost` → baris `XM_THERM ... -1/1800000` dan
   `-1/2000000`.
4. **Pantau suhu**: `cat /sys/class/thermal/thermal_zone*/temp`. Kalau
   `mtktscpu` tembus ~55°C, floor **harus** diturunkan.
5. Cek tidak ada reboot: `cat /sys/power/suspend_stats` +
   `scripts/triage-pstore.sh`.