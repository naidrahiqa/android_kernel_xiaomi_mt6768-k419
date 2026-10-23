---
id: 0002
title: Kamera makin burik setelah ganti kernel
status: open
severity: medium
area: device
opened: 2026-10-03
updated: 2026-10-07
fix_commit: "b291949aa61c"
verified_on: ""
tags: [camera, isp, vir-cqcnt, regression]
related: []
---

## Issue

Kualitas kamera memburuk dibanding build sebelumnya. Belum jelas ini
kamera utama / ultrawide / hasil foto / hanya preview — **perlu
dikonfirmasi dulu ke user** sebelum diagnose.

## Evidence

Belum ada. Butuh:

- Foto contoh sebelum vs sesudah (mode sama, cahaya sama).
- `logcat` kamera saat capture: `adb logcat -d | grep -iE 'cam|mfnr|nr|raw'`.
- dmesg ISP/`cam` saat sesi foto.

## Root cause

Hipotesis: Perubahan command processor ISP terkait Virtual CQ Counter
(`ISP_SET_VIR_CQCNT`, upstream `1b9d19378e`) yang sebelumnya tertinggal
menyebabkan sinkronisasi hardware CQ counter dan virtual counter desync.

## Fix

1. Di-cherry-pick commit `b291949aa61c` (`cameraisp: Reapply ISP_CMD_SET_VIR_CQCNT`):
- Implementasi handler IOCTL `ISP_SET_VIR_CQCNT` & `COMPAT_ISP_SET_VIR_CQCNT`
- Sinkronisasi checking CQ count pada IRQ SOF CAMA (`g_virtual_cq_cnt_a`) dan CAMB (`g_virtual_cq_cnt_b`)
- Reset IRQ ref count via `disable_irq` saat probe dan balancing `enable_irq`/`disable_irq` saat clock toggle

2. Diaktifkan driver VCM / autofocus lens `CONFIG_MTK_LENS_DW9714AF_SUPPORT=y` (`selene_defconfig`, commit `e121052e36a5`) melengkapi GT9764AF dan CN3927AF_J19 sesuai acuan kernel stock selene 4.14.

## Verification

Staged for hardware testing pada build Valhall r56p0 (`3033ab527d99`). Cek dmesg: `dmesg | grep -iE 'dw9714af|gt9764af|lens'`.

## Regression test

- Bandingkan foto sebelum/sesudah di kondisi sama.
- Kalau ketahuan commit penyebab, test ulang minimal 2x sebelum `verified`.
