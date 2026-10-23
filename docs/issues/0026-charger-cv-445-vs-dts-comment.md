---
id: 0026
title: Jalur CV charger 4,45V vs komentar DTS 4,35V — sel verified 4,45Vdc, dynamic-CV BIF sesuai rating; bukan penyebab baterai gembung
status: diagnosed
severity: low
area: drivers
opened: 2026-10-18
updated: 2026-10-18
fix_commit: ""
verified_on: ""
tags: [charger, battery, cv, bq2589x, dynamic-cv, dts, baterai-gembung]
related: [0005]
---

## Issue

Investigasi keluhan "charge terlalu kenceng / baterai makin hari
makin hamil" menemukan **ketidakcocokan dokumentasi**: DTS device
menulis `battery_cv = <4350000>` dengan komentar *"4.35V —
hardware-rated, DO NOT EXCEED"*, tapi jalur charger yang benar-benar
aktif menyetel **4,45V ke IC** sepanjang sesi.

## Evidence

- DTS: `selene.dts` `battery_cv = <4350000>` (komentar "DO NOT
  EXCEED"); default fallback `BATTERY_CV` (`mtk_charger_init.h:9`)
  juga 4350000.
- `mt6768.dts` node charger: `bif_threshold1 = <4250000>`,
  `bif_threshold2 = <4300000>`,
  `bif_cv_under_threshold2 = <4450000>`.
- `mtk_get_dynamic_cv()` (`mtk_charger.c:1670`) + flag default
  `enable_dynamic_cv = true` → saat vbat di bawah threshold, CV
  dilempar ke 4.450.000 µV (dan 4.608.000 µV pada cabang
  `vbat < 4.25V`).
- Log device (console pstore + dmesg live): **204×**
  `bq2589x_set_vchg: charge volt = 4450000`, plus
  `swchg_select_cv, constant_voltage = 4450000`.
- Batterystats 5,6 hari: tegangan baterai terukur **maks 4.465 mV**
  (p99 = 4.410 mV) — sel benar-benar diisi segitu, bukan angka
  virtual.
- **Konfirmasi label fisik baterai oleh pemilik (18 Okt 2026):
  "tertulis 4.45Vdc"** → rating sel = 4,45V.

## Root cause (ketidakcocokan dokumentasi, bukan kerusakan)

Jalur dynamic-CV BIF menyetel 4,45V = **tepat sesuai rating sel
4,45Vdc**. Yang tidak akurat adalah **komentar DTS** yang menyebut
4,35V sebagai hardware-rated — angka itu berlaku sebagai fallback
CV statis, bukan rating sel ini. Kesimpulan: **charge TIDAK
overcharge**; "baterai makin hamil + drop" (HP second, health
4.886/6.000 mAh ≈ 81%) wajar untuk umur + diperparah kebiasaan
panas (476 sampel suhu ≥45°C, maks 50°C dalam 5,6 hari).

## Action

- [x] Dokumentasikan di sini — **JANGAN ada yang "memperbaiki" CV ke
      4,35V** (itu justru under-charge sel 4,45V, kapasitas tak
      terisi penuh) dan **JANGAN menaikkan di atas 4,45V** (di luar
      rating sel → overcharge beneran).
- [ ] Opsional (siklus build berikutnya, komentar saja — nol risiko
      fungsi): ganti komentar `selene.dts` menjadi fakta terverifikasi
      (sel 4,45Vdc, dynamic-CV BIF aktif, jangan diubah tanpa
      validasi hardware).
- [ ] Rekomendasi hardware ke pemilik: baterai fisik gembung
      **tidak bisa dipulihkan** — ganti; hindari charge sambil main
      berat (suhu ≥45°C mempercepat degas).

## Verification

- [ ] Komentar DTS terkoreksi di build berikutnya (opsional)
- [ ] Setelah baterai baru: pantau `volt=` maks tetap ≈4.45–4.47V
      (konsisten dengan rating sel) dan kembung tak berulang
