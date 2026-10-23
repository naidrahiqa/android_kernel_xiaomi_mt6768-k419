---
id: 0023
title: Layar gelap/salah terang setelah resume — cache level backlight tak di-invalidate saat suspend
status: fixed
severity: medium
area: drivers
opened: 2026-10-18
updated: 2026-10-18
fix_commit: "c0912a886bc1"
verified_on: ""
tags: [display, backlight, suspend, resume, primary_display, shockwave]
related: [0022]
---

## Issue

`primary_display_setbacklight_nolock()` menyimpan level backlight
terakhir dan **melewatkan** write hardware kalau nilai baru sama
dengan cache. Status LCM backlight hilang lintas suspend — setelah
resume panel datang dalam kondisi gelap/beda brightness, tapi driver
mengira level masih terprogram sehingga **percobaan write pertama
dibuang** sampai userspace kebetulan mengubah nilai.

Gejala: setelah layar off→on, layar gelap atau brightness salah sampai
ada yang menggeser slider.

## Evidence

- Port dari ShockWAVE kernel `0fb5ac597de7` ("mediatek: video:
  Invalidate cached backlight level on suspend") — patch perbaikan
  konkret dari kernel komunitas MT6768 lain.
- Logika cache: `if (new_level == cached_level) return;` tanpa
  invalidasi di `primary_display_suspend()` — ketidakkonsistenan
  antara state cache (RAM) dan state panel (hardware) sudah jelas di
  kode.

## Root cause

Cache level backlight bertahan melewati suspend/resume padahal
hardware panel tidak — write pertama pasca-resume tidak pernah
mengenai panel.

## Fix

`c0912a886bc1` — promosikan cache per-fungsi ke file scope, reset ke
`UINT_MAX` di `primary_display_suspend()` sehingga write pertama
setelah resume selalu mencapai panel. Berlaku untuk semua salinan
platform MTK di tree (mt6739/65/68/79/85/33/53/85); yang diuji di
selene hanya mt6768.

## Verification

- [x] build lokal hijau: `MAKE_EXIT=0` + `Image.gz-dtb`
- [ ] flash → screen off/on 10× → brightness tetap konsisten, tidak
      ada layar gelap setelah resume
- [ ] cek `dmesg` tidak ada spam write backlight aneh pasca-resume

## Regression test

Kalau muncul kedipan brightness saat resume: cache di-reset terlalu
agresif — opsi turunkan ke invalidasi sekali per resume (memang
intinya), jangan kembalikan cache tanpa invalidasi.
