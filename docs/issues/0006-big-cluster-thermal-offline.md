---
id: 0006
slug: big-cluster-thermal-offline
title: Big cluster (CPU 6-7) mati setelah boot / saat panas akibat eskalasi mi_thermald
status: fixed
severity: high
area: kernel
opened: 2026-10-08
updated: 2026-10-08
fix_commit: e53cefd7c670
verified_on: "selene (4.19.325-PawwwNunungggg-cip136-st20-g3b7dc70f40e3)"
tags: [thermal, hotplug, cpuhp, mi_thermald, big-cluster, lag]
related: [0005]
---

## Gejala

Setelah shutdown lalu dihidupkan (atau saat device warm/charging), device terasa
sangat lambat dan patah-patah (stuttering). Saat dicek di pengaturan/kernel manager,
kedua core performa Big Cluster (CPU 6 dan 7 Cortex-A75) berada dalam kondisi **offline**.

## Evidence

Terekam persis di dmesg device pada detik 103 (beberapa saat setelah boot) dan detik 600:

```
[ 600.142626] cpu down prepare for 6.
[ 600.143352] [handle_switch_core][361]before cpumask set cpu, find 0
[ 600.144299] change cpu id from 6(0x81000600) to 0(0x81000000)
[ 600.145488] CPU6: shutdown
[ 600.145687] psci: CPU6 killed (polled 0 ms)
[ 600.160734] CPU5: update max cpu_capacity 516
[ 600.198633] IRQ 6: no longer affine to CPU7
[ 600.199550] CPU7: shutdown
[ 600.199742] psci: CPU7 killed (polled 0 ms)
[ 600.216657] mtk_leds_drv setMaxbrightness(138) :Set max brightness go through AAL
[ 600.217851] mtk_cooler_backlight_cus: thermal/cooler/backlight 100
```

Korelasi hard:
1. CPU 6 dan 7 dimatikan via PSCI.
2. Tepat 18 ms setelah CPU 7 shutdown, thermal cooler backlight dipaksa ke 100
   (`mtk_cooler_backlight_cus`).
3. Binary `/vendor/bin/mi_thermald` memuat target path:
   `/sys/devices/system/cpu/cpu%d/online`
   bersama tabel trip virtual sensor Xiaomi.

## Root cause

Ini adalah efek samping eskalasi proteksi thermal userspace setelah perbaikan
issue 0005:
1. Pada commit `e74df8e5ee9b` (issue 0005), kita mengunci floor frekuensi CPU
   via `CONFIG_THERMAL_XM_FREQ_FLOOR` (1.8 GHz little / 2.0 GHz big) agar
   `mi_thermald` tidak mencekik frekuensi ke 1.1 GHz.
2. Saat SoC hangat (misalnya beban tinggi boot atau saat dicas), `mi_thermald`
   mencoba membatasi CPU. Karena batas frekuensi tidak bisa diturunkan di bawah floor,
   suhu tetap berada di atas ambang batas trip point Xiaomi.
3. `mi_thermald` eskalasi ke metode pendinginan berikutnya: **core hotplugging**.
   Daemon menulis `0` langsung ke `/sys/devices/system/cpu/cpu6/online` dan
   `/sys/devices/system/cpu/cpu7/online`.
4. Akibatnya, CPU 6 dan 7 mati total. Seluruh task Android terpaksa berjalan
   di 6 core Cortex-A55 Little, menyebabkan UI lag parah.

## Fix

Tambahkan proteksi dual-layer via `CONFIG_HOTPLUG_LOCK_BIG_CLUSTER`:
1. **Sysfs level (`drivers/base/cpu.c`)**:
   Di `cpu_subsys_offline()`, tolak request offline untuk CPU >= 6 dari sysfs
   dengan `-EPERM`. Userspace daemon (`mi_thermald`) tidak dapat lagi
   mematikan big core secara sepihak.
2. **PPM Hotplug level (`drivers/misc/mediatek/base/power/cpuhotplug/mtk_cpuhp_ppm.c`)**:
   - Guard down-loop agar tidak pernah mengeksekusi shutdown pada CPU >= 6.
   - Pastikan CPU 6 dan 7 selalu dipertahankan di mask `ppm_online_cpus`.
3. Aktifkan `CONFIG_HOTPLUG_LOCK_BIG_CLUSTER=y` di `selene_defconfig`.

Suspend/resume tidak terpengaruh karena kernel freezer (`freeze_secondary_cpus`)
memanggil `_cpu_down()` langsung tanpa melewati sysfs subsystem.

## Verification

- [x] Flash build `g3b7dc70f40e3` ke hardware Selene.
- [x] Cek status online semua core: `cat /sys/devices/system/cpu/online` terbukti `0-7` (semua 8 core online).
- [x] Terekam penolakan otomatis eskalasi `mi_thermald` di dmesg saat boot/panas:
  - `[ 135.455601] cpu6: refusing sysfs offline request`
  - `[ 135.456047] cpu7: refusing sysfs offline request`
  - `[ 323.480090] cpu6: refusing sysfs offline request`
  - `[ 323.482951] cpu7: refusing sysfs offline request`
- [x] Uji manual penulisan sysfs offline: return code error 1 / `-EPERM`. Core 6 dan 7 tetap online dan scaling aktif di 774 MHz - 2.0 GHz.
- [x] Warning Goodix `Unbalanced IRQ 141 wake disable` terkonfirmasi 100% hilang dari dmesg.
