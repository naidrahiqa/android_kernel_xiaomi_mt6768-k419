---
id: 0004
slug: fuse-freeze-suspend-abort
title: Suspend dibatalkan — task aplikasi nyangkut di FUSE waktu freezer jalan
status: fixed
severity: medium
area: kernel
opened: 2026-10-07
updated: 2026-10-07
fix_commit: e4de8ed591a0
verified_on: ""
tags: [suspend, freezer, fuse, battery]
related: [0003]
---

## Gejala

HP nggak mau deep-sleep bersih. `suspend_stats` device (build
`g41bffda248fe`, boot 2026-10-07 19:48):

```
success: 45   fail: 26        <- 36% attempt gagal
failed_freeze: 10
failed_suspend: 2   failed_suspend_noirq: 2
last_failed_dev:  alarmtimer
last_failed_errno: -16   (-EBUSY)
last_failed_step: freeze
```

dmesg (window buffer, dari ~1152s ke ~2627s):
`Freezing user space processes` ×70, `Restarting tasks` ×70,
`Freezing of tasks failed` ×1, `PM: noirq suspend of devices failed` ×2,
`PM: Some devices failed to suspend` ×2.

## Evidence

```
[2436.453565] Freezing user space processes ...
[2436.454911] [tz_vfs][ERROR]: [tz_vfs_read][155] wait_for_completion was interrupt
[2438.466845] Freezing of tasks failed after 2.012 seconds
              (1 tasks refusing to freeze, wq_busy=0):
[2438.469233] LocatorThumbnai D    0  8957   1501 0x4000000004000809
Call trace:
 __switch_to+0x118/0x124
 __schedule+0x5f0/0x6e0
 schedule+0x70/0x90
 fuse_simple_request+0x3f4/0x594
 fuse_atomic_open+0x458/0x908
 path_openat+0x490/0xe08
 do_filp_open → do_sys_open → __arm64_sys_openat → el0_svc
[2438.530057] Abort: One or more tasks refusing to freeze
[2438.530635] PM: suspend exit 2026-10-07 13:29:36.353163280 UTC
```

`LocatorThumbnai` = worker `com.google.android.apps.photos` (anak zygote
1501) yang `openat()` ke `/storage/emulated/*` → FuseDaemon
(`com.android.providers.media.module`, pid 4027).

## Root cause

Bug desain FUSE 4.19 + keputusan vendor, **bukan regresi range
`282da32602fa..HEAD`** (`fs/fuse/`, `kernel/power/`, `kernel/freezer.c`
tidak berubah; `kernel/power/Kconfig` cuma +8 baris Buoffla wakelock).

Urutan matinya:

1. FuseDaemon baca request dari `/dev/fuse` → `FR_SENT` diset
   (`fs/fuse/dev.c:1343`), balasan belum ditulis.
2. Freezer jalan → `freeze_task()` → `signal_wake_up(p, 0)`
   (`kernel/freezer.c:99-107`) → set `TIF_SIGPENDING` **tanpa**
   mengirim signal nyata.
3. FuseDaemon balik ke usermode → `get_signal()` → `try_to_freeze()` →
   **beku dengan `FR_SENT` masih terpasang**.
4. Requester nunggu di `request_wait_answer()`:
   - `fs/fuse/dev.c:383` `wait_event_interruptible` → kena fake signal,
     return `-ERESTARTSYS`, set `FR_INTERRUPTED`.
   - `fs/fuse/dev.c:397` `wait_event_killable()` (TASK_KILLABLE).
     `signal_pending_state()` (`include/linux/sched/signal.h:372-379`)
     cuma bangun kalau `state & TASK_INTERRUPTIBLE` **atau**
     `__fatal_signal_pending()` — keduanya false → **tidur lagi**.
   - Bailed out hanya kalau `FR_PENDING` (`dev.c:404-410`); karena sudah
     `FR_SENT`, jatuh ke wait-it-out `dev.c:418` — tapi nggak pernah
     kecapai karena `wait_event_killable` nggak pernah return.
5. → `D` state permanen → `try_to_freeze_tasks()` hitung sebagai menolak
   beku → `freeze_processes()` gagal `-EBUSY` (`process.c:114`) →
   `log_suspend_abort_reason("One or more tasks refusing to freeze")`.

Kenapa cuma **2.012 detik** padahal default 20 detik: vendor nulis
`/sys/power/pm_freeze_timeout 2000` di dua tempat:

```
/vendor/etc/init/hw/init.mt6768.rc:76:    write /sys/power/pm_freeze_timeout 2000
/vendor/etc/init/hw/init.mt6768.rc:953:   write /sys/power/pm_freeze_timeout 2000
```
(konfirmasi device: `cat /sys/power/pm_freeze_timeout` → `2000`;
source knob: `kernel/power/main.c:827-840`, default
`freeze_timeout_msecs = 20000` di `kernel/power/process.c:29`.)

Catatan: timeout cuma bikin kasar — untuk kasus FUSE ini wait-nya
**tidak pernah selesai**, jadi diekspand berapa pun tetap gagal.

## Impact

- Suspend gagal & diulang-ulang → baterai boros, deep-sleep putus-putus.
- **Bukan** penyebab issue 0003 (gagal nyimpen/download) — nggak ada
  bukti kegagalan tulis app-level di logcat.
- Moderate: nggak ada data loss, cuma sleep latency.

## Fix

`fs/fuse/dev.c` `request_wait_answer()`: ganti `wait_event_killable()`
menjadi loop `wait_event_interruptible()` dengan kondisi
`FR_FINISHED || freezing(current)`:

- benign signal → re-sleep (semantik killable tetap terjaga)
- `freezing(current)` → `try_to_freeze()` di tempat, request tetap
  pending dan selesai normal setelah thaw
- fatal signal → break, lalu jalur `FR_PENDING` bail / wait-it-out
  seperti semula

`freezer.h` sudah diinclude (`fs/fuse/dev.c:25`), `__fatal_signal_pending`
dari `linux/sched/signal.h:14`.

**Risiko yang harus ditest:** `try_to_freeze()` dipanggil dari konteks
yang mungkin masih memegang `i_rwsem` (jalur `fuse_atomic_open`). Kalau
task lain butuh lock itu untuk membeku juga, freeze bisa tetap gagal
(lebih lambat satu task, bukan lebih buruk). Harus dicek di hardware:
`failed_freeze` harus turun, dan nggak boleh ada lockdep WARN baru.

## Verification

Belum — build `g41bffda248fe` **belum memuat fix ini**.

Kriteria lulus:
1. `su -c 'cat /sys/power/suspend_stats'` → `failed_freeze` berhenti
   naik selama layar mati 10 menit.
2. dmesg nggak ada lagi `Freezing of tasks failed` /
   `fuse_simple_request` di stack.
3. Tidak ada `WARNING` baru (khususnya lockdep) di dmesg/pstore.
4. Jangan lupa juga test jalur normal: buka folder via Files/Media
   selama layar mau mati, pastikan `openat()` nggak balik `EINTR`.

## Regression test

- Layar mati 10 menit → cek `suspend_stats` (success naik, fail diam).
- Copy file besar ke `/sdcard` sambil layar dibiarkan mati.
- Ambil `dmesg` + `pstore` sesudahnya.
