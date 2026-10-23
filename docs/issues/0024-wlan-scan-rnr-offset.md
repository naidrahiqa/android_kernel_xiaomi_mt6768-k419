---
id: 0024
title: Scan RNR 6 GHz parsing korup — index skip saat neighbor AP tanpa BSSID
status: fixed
severity: low
area: drivers
opened: 2026-10-18
updated: 2026-10-18
fix_commit: "994b9414c6ef"
verified_on: ""
tags: [wifi, wlan, scan, rnr, 6ghz, gen4m]
related: [0022]
---

## Issue

`scanParsingRnrElement()` di driver wlan gen4m menangani neighbor AP
entry **tanpa BSSID** dengan `continue` — yang melewati advance index
`ucCurrentLength` di label `next_neighbor_ap`. Parser RNR lalu
melanjutkan di offset basi, membaca entry NeighborAPInfo berikutnya
di posisi salah, dan **merusak parsing neighbor report 6 GHz selama
scan**.

Gejala potensial: 6 GHz neighbor discovery tidak akurat / AP 6 GHz
tak terdeteksi konsisten saat scan. 2.4/5 GHz tidak terpengaruh
(fungsi ini hanya dilewati jalur RNR).

## Evidence

- Port dari lineage-24.0-perf `2faa512bd530` ("wlan: Fix wifi scan
  locking").
- Logika bug jelas di kode: `continue` di dalam loop entry tanpa
  BSSID ≠ `goto next_neighbor_ap`, dan hanya jalur label itu yang
  melakukan advance offset — ketidakkonsistenan state walk antar
  entry.
- Driver gen4m di tree ini identik dengan sumber patch, tanpa
  adaptasi.

## Root cause

Early-out entry tanpa BSSID pakai `continue` (skip loop iteration
lengkap) alih-alih `goto next_neighbor_ap` (advance offset + lanjut),
sehingga posisi walk parser tidak konsisten per entry.

## Fix

`994b9414c6ef` — arahkan early-out melewati label
`next_neighbor_ap` supaya advance index selalu berjalan untuk setiap
entry.

## Verification

- [x] build lokal hijau: `MAKE_EXIT=0` + `Image.gz-dtb`
- [ ] flash → scan wifi normal, SSID 2.4/5 GHz tetap terdeteksi;
      kalau ada router 6 GHz di lingkungan uji, cek neighbor-nya
      terbaca konsisten antar scan

## Regression test

Scan wifi tidak menemukan jaringan yang biasanya ada → revert
`994b9414c6ef` (commit tunggal, jalur RNR saja).
