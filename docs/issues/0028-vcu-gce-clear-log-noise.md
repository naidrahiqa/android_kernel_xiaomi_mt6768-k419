---
id: 0028
title: VCU — "vcu_gce_clear_inst_id not found" sebagai pr_info spam (clear idempotent by design)
status: fixed
severity: low
area: drivers
opened: 2026-10-18
updated: 2026-10-18
fix_commit: "61c1a889d324"
verified_on: ""
tags: [vcodec, vcu, gce, log-noise]
related: [0018]
---

## Issue

`vcu_gce_clear_inst_id()` (`drivers/media/platform/mtk-vcu/mtk_vcu.c`)
melempar `pr_info("%s ctx %p not found!")` setiap kali konteks tidak
terdaftar di tabel `gce_info[]`. Clear dipanggil dari
`vcu_clear_codec_ctx()` (stop/release encoder & decoder) dan bersifat
**idempotent** — jalur stop yang tidak pernah lewat
`vcu_gce_set_inst_id()` (mis. sesi tanpa GCE flush, atau double-clear
release) adalah kondisi normal, bukan error.

Hasilnya: **±18 "not found" per sesi** di dmesg (capture 18 Okt 2026)
yang menutupi sinyal penting di area yang sama — pola serupa issue
0018 (flood nutupin signal).

## Evidence

- `log-dump/full-analysis/dmesg.txt` — "vcu_gce_clear_inst_id not
  found" berulang saat aktivitas kamera/video.
- Kode: clear hanya loop scan + log; tidak ada state yang bocor atau
  gagal dirilis pada miss — set/get sukses sendiri sudah memakai
  `vcu_dbg_log`.

## Root cause

Level log salah: miss pada operasi idempoten dinaikkan ke `pr_info`
padahal flow by-design bisa miss.

## Fix

`mtk_vcu.c` — turunkan ke `vcu_dbg_log()` (konsisten dengan jalur
sukses set/get) + komentar WHY bahwa miss adalah normal.

## Verification

- [ ] Build-only (masuk batch berikutnya).
- [ ] Rekam video / buka kamera → `dmesg | grep -c "clear_inst_id"` = 0.
