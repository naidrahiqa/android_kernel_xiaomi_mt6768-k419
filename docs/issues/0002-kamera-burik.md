---
id: 0002
title: Kamera makin burik setelah ganti kernel
status: open
severity: medium
area: device
opened: 2026-10-03
updated: 2026-10-07
fix_commit: ""
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

Hipotesis (belum terkonfirmasi): perubahan ISP berkaitan
`VIR_CQCNT` (`1b9d19378e` upstream) yang **sengaja di-skip** dari batch
sync karena diduga men kill kamera pada device ini.

Hipotesis lain yang harus dikesampingkan:

- Perubahan MM / mali / display dari batch cherry-pick besar
  (`bacad55ab49e..41bffda248fe`, 656 commit).
- Artefak tuning ISP/EEPROM yang ke-load dari DTB — bukan kernel.

## Fix

Belum ada. Jangan menebak-nebak: kumpulkan bukti dulu.

## Verification

Belum.

## Regression test

- Bandingkan foto sebelum/sesudah di kondisi sama.
- Kalau ketahuan commit penyebab, test ulang minimal 2x sebelum `verified`.
