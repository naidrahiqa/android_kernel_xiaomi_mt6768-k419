---
id: 0013
title: MQ_CPQ_DEFAULT tidak pernah aktif di perangkat; default mq I/O scheduler dikembalikan ke mq-deadline
status: fixed
severity: low
area: config
opened: 2026-10-14
updated: 2026-10-14
fix_commit: "765671f13404"
verified_on: ""
tags: [iosched, defconfig, cpq, block]
related: [0012]
---

## Issue

Commit `929538d6480e` ("defconfig: set CPQ as default I/O scheduler",
mirror dari fire `343f5153e530`) menyetel `CONFIG_MQ_CPQ_DEFAULT=y`,
tapi device tetap berjalan dengan `mq-deadline` pada storage utama.
Permintaan owner (14 Okt 2026): kembalikan default ke mq-deadline,
scheduler lain tetap tersedia sebagai opsional.

## Evidence

Build berjalan: `4.19.325-PawwwNunungggg-cip136-st20-g1951bbc122b3`
(out/.config milik build itu: `CONFIG_MQ_CPQ_DEFAULT=y`).

```
$ adb shell cat /sys/block/sda/queue/scheduler
[mq-deadline] cpq adios bfq none
```

`elevator_init_mq()` (`block/elevator.c:973`) hanya menempelkan default
mq untuk **single-queue**:

```c
if (q->nr_hw_queues != 1)
        return 0;
```

Bantuan Kconfig choice-nya sendiri bilang hal yang sama
(`block/Kconfig.iosched`, "Default mq I/O scheduler"):
"which will be used by default for **single-queue** blk-mq block devices".

`/vendor/etc/init/` dan `/system/etc/init/` tidak menulis scheduler
(grep kosong) — mq-deadline pada sda berasal dari userspace ROM di luar
init.rc yang terjangkau, bukan dari Kconfig.

## Root cause

Pilihan default mq hanya berlaku untuk blk-mq **single-queue** (zram,
ramdisk). sda (UFS, multi-queue) tidak pernah menerima default dari
Kconfig, jadi `CONFIG_MQ_CPQ_DEFAULT=y` inert untuk storage utama —
efeknya hanya pada device single-queue. Nilai default di defconfig
tidak mencerminkan keadaan nyata perangkat.

## Fix

`arch/arm64/configs/selene_defconfig`: pilihan mq dipindah
`CONFIG_MQ_CPQ_DEFAULT` → `CONFIG_MQ_DEADLINE_DEFAULT`.
CPQ, ADIOS, BFQ, deadline semua tetap dibangun (`=y`) — tersedia
runtime via `/sys/block/<dev>/queue/scheduler`.

## Verification

- [x] `make O=out ARCH=arm64 selene_defconfig` → `out/.config`:
      `CONFIG_MQ_DEADLINE_DEFAULT=y`, `# CONFIG_MQ_CPQ_DEFAULT is not set`,
      `CONFIG_MQ_IOSCHED_DEADLINE/CPQ/ADIOS=y`, `CONFIG_IOSCHED_BFQ=y`
- [ ] flash build berikutnya → `cat /sys/block/sda/queue/scheduler`

## Regression test

Kalau suatu saat ada yang ingin default CPQ lagi: pindah balik pilihan
choice di defconfig — satu baris, revert bersih. Tapi catat: efeknya
hanya device single-queue; untuk sda perlu userspace (init/perf config).
