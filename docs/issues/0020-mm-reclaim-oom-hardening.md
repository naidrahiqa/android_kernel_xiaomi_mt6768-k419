---
id: 0020
title: Reclaim stall & premature OOM di bawah tekanan memori — batch hardening mm (MGLRU per-zone, oom_reaper vs freezer, zram CMA, ratelimit pages)
status: fixed
severity: high
area: kernel
opened: 2026-10-18
updated: 2026-10-18
fix_commit: "a2b92d6349ca dcd836923d5e e64d5b166a9e d60bcd6b6b98"
verified_on: ""
tags: [mm, mglru, oom, zram, cma, reclaim, backport, batch]
related: []
---

## Issue

Empat kelemahan `mm` yang berhubungan, ditemukan lewat riset patch
upstream/stable/lore untuk batch perbaikan reboot & OOM (bukan hasil
reproduksi di device — backport preventif):

1. **MGLRU per-zone reclaim stall** → min_seq tidak bisa maju →
   reclaim berhenti sementara memori bebas ada di zona lain →
   premature OOM kill saat tekanan memori.
2. **`oom_reaper` race vs PM freezer** → `oom_killer_disable` (dipakai
   jalur suspend) kehilangan semantiknya: victim bisa masih jalan di
   jalur `do_exit` sementara freezer mengira task sudah mati →
   sentuh device/IO yang sudah di-freeze.
3. **Zram tidak bisa pakai halaman CMA** → alokasi order-0 gagal +
   reclaim berkepanjangan padahal CMA bebas (di MT6768 CMA/SSMR
   lumayan besar).
4. **`ratelimit_pages` terlalu kecil** → fungsi cek writeback dipanggil
   terlalu sering (overhead) di Android dengan RAM 4/6 GB.

## Evidence

- `669281ee7ef7` ("Multi-gen LRU: fix per-zone reclaim") masuk stable
  **6.1.54**; menurut commit body-nya MediaTek, Qualcomm, dan
  Raspberry Pi menabrak stall ini **secara independen** — arsitektur
  mirip (ZONE_MOVABLE/CMA) seperti MT6768.
- Race oom_reaper vs freezer: tabel race dari commit asli
  (`freeze_processes` / `oom_killer_disable` vs `__oom_reap_task`
  → `exit_oom_victim` → `do_exit` yang bisa `perform IO/interfere
  with the freezer`).
- Zram CMA: vendor allocator MTK mensyaratkan `__GFP_CMA` eksplisit;
  tanpa flag itu pageblock CMA tak terpakai untuk page zram yang
  movable (patch Vinayak Menon, LKML 20113/01113).
- `ratelimit_pages` default 32 × 4 KiB = cek writeback tiap 128 KiB;
  `dirty_background_ratio=10` di RAM kita ≈ 1638 KiB → default
  terlalu agresif (angka dari commit).

## Root cause

1. `scan_pages()` hanya memindai zona sampai `sc->reclaim_idx`;
   generasi tertua bisa berisi page hanya di zona tak-eligen
   (ZONE_MOVABLE CMA/SSMR) → `min_seq` tak maju, reclaim stall.
2. `oom_reaper` memanggil `exit_oom_victim` di target task setelah
   unmap — bisa bersamaan dengan `try_to_freeze_tasks`.
3. Alokasi zram tidak membawa `__GFP_CMA` sehingga tidak boleh masuk
   pageblock CMA.
4. Angka 32 diset untuk skala RAM jauh lebih kecil dari Android 2026.

## Fix

| Sha | File | Inti |
|---|---|---|
| `dcd836923d5e` | `mm/vmscan.c` | backport manual `669281ee7ef7`: `sort_page()` dorong page zona tak-eligen ke generasi berikutnya; `scan_pages()` jalan semua zona dengan wrap-around (disesuaikan ke API MGLRU awal kita: `sort_page`/`scan_pages`/`page_inc_gen`, masih `struct page`) |
| `a2b92d6349ca` | `mm/oom_kill.c` | `oom_reaper` jadi freezable — hormati freezer saat `oom_killer_disable` |
| `e64d5b166a9e` | `mm/zsmalloc.c`, `mm/zram/` | izinkan page zram minta `__GFP_CMA`, flag dilepas untuk alokasi metadata (zspage/handle) |
| `d60bcd6b6b98` | `mm/page-writeback.c` | `ratelimit_pages` 32 → 256 (cek writeback per 1 MiB, di bawah `dirty_background_ratio` kita) |

## Verification

- [x] build lokal hijau: `MAKE_EXIT=0` + `Image.gz-dtb`
      (build batch — lihat commit masing-masing)
- [ ] flash → daily driver tekanan berat (banyak app, game) →
      `/proc/vmstat` `oom_kill` tetap 0, `pswpout` tidak disertai
      kill prematur
- [ ] cek zram benar-benar memakai CMA: tekanan memori + `grep Cma /proc/meminfo`
      (CmaFree turun saat reclaim zram)
- [ ] suspend/resume bersih tanpa freeze-task failure baru
      (interaksi `oom_reaper` freezable dengan freezer —
      `Freezing of tasks failed` tidak boleh bertambah)

## Regression test

Kalau ada tanda reclaim melambat: `grep -E 'pgscan|pgsteal' /proc/vmstat`
sebelum/sesudah; bila negatif, revert per-sha (4 commit terpisah,
masing-masing revertible).
