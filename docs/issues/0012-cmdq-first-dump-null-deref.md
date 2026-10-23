---
id: 0012
title: CMDQ first-error dump NULL deref → kernel panic saat kamera (ISP CMDQ timeout)
status: fixed
severity: high
area: drivers
opened: 2026-10-13
updated: 2026-10-13
fix_commit: "f76318705ff4"
verified_on: ""
tags: [cmdq, panic, camera, null-deref, mtk]
related: []
---

## Issue

Device reboot kernel_panic saat pakai kamera MIUI (module Leica).
Pipeline ISP kena CMDQ timeout → `cmdq_timeout_handler` jalan →
dump pertama oops di `vsprintf number()` (WRITE ke alamat 0) →
`panic_on_oops=1` → reboot. Terekam live:

```
Workqueue: cmdq_timeout_handler cmdq_thread_handle_timeout_work
pc : number+0x280/0x378   lr : pointer_string+0x38/0x40
Unable to handle kernel NULL pointer dereference at virtual address 0000000000000000
```

## Root cause

`drivers/misc/mediatek/cmdq/v3/cmdq_helper_ext.c`,
`cmdq_core_save_hex_first_dump()` (~1710): menulis ke
`cmdq_first_err.cmdqString + cmdqCount` via `snprintf`, tapi
`cmdqString` **tidak pernah dialokasi** — satu-satunya allocator
(`cmdq_core_save_first_dump()`) dimatikan `#if 0` (dan lock-nya
di-comment, jangan di-enable). Saat timeout pertama `flag=true`,
`cmdqString=NULL`, `cmdqCount=0` → `snprintf(NULL, 32768, ...)` → oops.

Bug sekunder: `cmdqMaxSize` (s32) dikurangi `logLen` tanpa clamp →
underflow → cast `size_t` raksasa → heap overflow; loop juga tidak
break saat buffer penuh.

## Fix

Commit `f76318705ff4`:
- Alokasi lazily `kmalloc(CMDQ_MAX_FIRSTERROR, GFP_ATOMIC)` saat
  pertama dipakai + NULL check bersih (gagal → `flag=false` + log).
- Stop-loop yang benar (`cmdqMaxSize <= 1` di cek SEBELUM snprintf)
  + clamp `logLen = bufSize - 1` → underflow tidak mungkin.
- `kfree(cmdqString)` di `cmdq_core_reset_first_dump()` (anti bocor;
  `kfree(NULL)` aman).
- Blok `#if 0` + spinlock comment dibiarkan mati sesuai keadaan awal.

## Verification

- Compile per-file + full build lokal lulus (`MAKE_EXIT=0`, zip AK3
  `PawwwNunungggg-selene-00d59c9-13102026.zip` ke `/sdcard/Download/`).
- Sudah ke-flash di hardware (build `g1951bbc122b3`, 14 Okt) — menunggu
  test kamera foto+video sambil `dmesg -w`; yang dicari: dump CMDQ
  timeout boleh muncul, `Unable to handle kernel NULL pointer dereference`
  harus HILANG.
- Fix menghilangkan reboot, bukan timeout-nya.

## Regression test

- Kamera normal (foto/video/Leica mode) tanpa reboot.
- Dmesg: `[CMDQ] Error0 dump` mungkin muncul (timeout) tapi tanpa oops.
- `cmdq_core_reset_first_dump` dipanggil berkala → tidak ada leak 32KB
  (worst case sekali alokasi per timeout).
