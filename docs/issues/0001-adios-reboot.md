---
id: 0001
title: HP random reboot — NULL deref di adios_dispatch_request (kblockd)
status: fixed
severity: critical
area: kernel
opened: 2026-10-03
updated: 2026-10-07
fix_commit: 447d4e39bb35 eec34a0ddfeb 44b942c85cc6 6c4e04cc842e
verified_on: ""
tags: [reboot, block, adios, pstore, union-aliasing]
related: []
---

## Issue

HP reboot random, seringnya saat telepon / pakai speaker. Dapat dari
`pstore` (`dmesg-ramoops-0`), bukan dari keluhan user semata.

## Evidence

```
Oops: 96000045 [#1] PREEMPT SMP
pc : remove_request+0x38
lr : adios_dispatch_request+0x404
Workqueue: kblockd
```

Union aliasing di `block/adios.c`: field `flush.list` menimpa `elv.priv[0]`
→ pointer sampah terbaca di `adios_dispatch_request` → `list_del_init`
ke pointer kosong (akses tulis NULL, `96000045`).

## Root cause

`flush.list` dan `elv.priv[0]` berbagi storage yang sama. Request yang
masuk lewat jalur flush membuat pointer dispatch jadi tidak valid.

## Fix

- `44d4e39bb35` — validasi `rd` vs alias `flush` sebelum dipakai (fix #1)
- `282da32602fa` — hardening setelah fix #1
- `44b942c85cc6`, `eec34a0ddfeb` — lanjutan

**Jangan di-revert.** Sudah di-test A/B (panggilan + speaker) lulus.

## Verification

**Masih `fixed` — bukan regressed. Koreksi 2026-10-07 setelah cek ancestry.**

Bukti crash ada di `/sys/fs/pstore/console-ramoops-0` (ditulis saat boot
19:48, isinya sesi kernel **`g282da32602fa`**):

```
Internal error: Oops: 96000045 [#1] PREEMPT SMP
Comm: kworker/3:1H Tainted: G S      W   4.19.325-...-g282da32602fa
Workqueue: kblockd blk_mq_run_work_fn
pc : remove_request+0x38/0x114
lr : adios_dispatch_request+0x404/0x7bc
Call trace:
 remove_request+0x38/0x114
 adios_dispatch_request+0x404/0x7bc
 blk_mq_sched_dispatch_requests → __blk_mq_run_hw_queue → blk_mq_run_work_fn
```

Tapi `g282da32602fa` = HEAD di titik `282da32602fa`, dan:

```
$ git merge-base --is-ancestor 447d4e39bb35 282da32602fa   # TIDAK (exit 1)
$ git merge-base --is-ancestor 44b942c85cc6 282da32602fa   # TIDAK (exit 1)
$ git merge-base --is-ancestor eec34a0ddfeb 282da32602fa   # TIDAK (exit 1)
```

Urutan asli di `block/adios.c`:

```
94218840ef17 block: add ADIOS adaptive deadline io scheduler
282da32602fa block: fix adios NULL rd crash on flush and unprepared requests
447d4e39bb35 block: validate adios rd ownership against flush union aliasing
eec34a0ddfeb block: restore mq elevator init with mq-deadline default
44b942c85cc6 block: harden adios against queue loss and accounting leaks
```

→ Crash di pstore = **bug yang memang sudah di-fix sesudahnya**. Tanda
tangan oops-nya persis sesuai diagnosis fix #1: `list_del_init` NULL write
karena `rq->queuelist.prev == NULL`, dipanggil dari
`fill_batch_queues` → `remove_request` (ter-inline ke
`adios_dispatch_request`, makanya ukurannya `0x7bc`).

Build sekarang `g41bffda248fe` **sudah memuat ketiganya**. Dmesg build
baru (dicek 20:40): `WARNING: 0  BUG: 0  Oops: 0`.

**Hal lain di pstore build lama** (satu sesi yang sama, bukan bagian dari
issue ini, dicatat di `2-kamera-burik`-style):
```
WARNING: CPU: 2 PID: 1962 at irq_set_irq_wake+0xf0/0x1a4
Unbalanced IRQ 141 wake disable
 gf_disable_irq+0x24/0x70 → gf_ioctl+0x828/0xd2c    (Goodix fingerprint)
```

## Regression test

- Telepon masuk + pakai speaker ≥ 5 menit, beberapa kali.
- Ambil `pstore` sesudahnya: baris `remove_request` / `adios_dispatch_request`
  wajib absen.
- **Wajib `git merge-base --is-ancestor` fix terhadap SHA yang ada di
  `uname -r` sebelum mengklaim regresi** — jangan nebak dari tanggal
  build. (Kesalahan yang pernah terjadi di issue ini 2026-10-07.)
- Isi `verified_on` dengan `uname -r` build yang lulus test di atas.
