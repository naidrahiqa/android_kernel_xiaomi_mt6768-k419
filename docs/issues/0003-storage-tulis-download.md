---
id: 0003
title: Tidak bisa menyimpan / download file di storage
status: open
severity: high
area: device
opened: 2026-10-07
updated: 2026-10-07
fix_commit: ""
verified_on: ""
tags: [storage, fuse, fuse_bpf, f2fs, download, scoped-storage]
related: []
---

## Issue

User tidak bisa menyimpan maupun download file. Kata "masih" → diduga sudah
terjadi sebelum flash `g41bffda248fe`, jadi kemungkinan **bukan regresi batch
656 commit hari ini** — tapi ini belum terkonfirmasi (lihat Evidence/TODO).

**Belum diketahui:** aplikasi mana, tujuan ke mana (internal vs SD card),
pesan error apa, dan apakah juga terjadi di build `g282da32602fa`.

## Evidence

Dari device (`g41bffda248fe`, 2026-10-07):

**Konfigurasi sehat** — gotcha `select FUSE_BPF` yang pernah bikin file
0-byte TIDAK kena:

```
CONFIG_FUSE_BPF=y
CONFIG_FUSE_FS=y
CONFIG_F2FS_FS=y
```

`drivers/misc/mediatek/Kconfig.default:77` masih `select FUSE_BPF`
(restored oleh `292efc29c873`).

**Mount sehat:**

```
/dev/fuse on /storage/emulated type fuse (rw,lazytime,...,allow_other)
/dev/fuse on /storage/7FCE-FD09 type fuse (...)     # SD card exfat
/dev/block/dm-49 on /data type f2fs
```

**Ruang & tulis-tulis pakai shell adb normal:**

```
/dev/block/dm-49  105G  56G   49G  54% /data
/dev/fuse         119G  26G   93G  23% /storage/7FCE-FD09

echo ok > /sdcard/Download/.wtest   -> rc=0, file terbentuk
```

**Sinyal kernel (belum tentu penyebab):**

```
F2FS-fs (dm-49): Unexpected flush for atomic writes: ino=95296, npages=8
F2FS-fs (dm-49): Unexpected flush for atomic writes: ino=6619, npages=3
```

Dari `fs/f2fs/file.c:2080` (`f2fs_ioc_start_atomic_write`) — app memanggil
`F2FS_IOC_START_ATOMIC_WRITE` pada file yang masih punya dirty pages.
`f2fs_warn` saja, jalan lanjut. **Belum dibuktikan berkaitan.**

**Red herring yang SUDAH PERNAH salah diagnosis** (AGENTS gotcha FUSE_BPF):

```
W FuseDaemon: Rejected access to app-private dir on FUSE:
  /storage/emulated/0/Android/data/com.ss.android.ugc.trill from uid: 10452
```

Log ini = scoped storage Android 11+ menolak akses lintas app ke
`Android/data`. Dulu bikin salah simpul "FUSE_BPF rusak" (fix `43bb291`
justru memperparah). **Verifikasi wajib dengan test download beneran dari
app, bukan dengan membaca log.**

**SELinux denial (pre-existing? perlu dicek):**

```
avc: denied { read } comm="Lacrima_single_" name="sdcard" dev="tmpfs"
  scontext=u:r:untrusted_app tcontext=u:object_r:mnt_sdcard_file
  tclass=lnk_file permissive=0
```

## Root cause

Belum ketemu. Kandidat yang harus dikecualikan satu per satu:

1. Scoped storage / MediaProvider (userspace) — **bukan kernel**, kalau ini
   maka gak ada hubungannya dengan build kita.
2. FUSE_BPF — config `y`, tapi **fungsinya belum diuji**.
3. f2fs: batch `282da..HEAD` menyentuh `fs/f2fs/{acl,checkpoint,data,inline}.c`
   (`41d84924e4e9`, `4e0d049f7c10`, `64d0251cd5c9`, `22c38d6f024f`, `d5626e50a7d7`).
   `fs/fuse/` **tidak berubah sama sekali** di range itu.
4. `avc: denied mnt_sdcard_file` — kalau semua app pada umumnya bisa
   menulis, ini cuma noise.

### Sinyal FUSE yang ketemu 2026-10-07 (belum jadi root cause)

Suspend dibatalkan karena **satu task nyangkut di FUSE** — ini satu-satunya
jejak FUSE di dmesg build `g41bffda248fe`:

```
[2436.453565] Freezing user space processes ...
[2436.454911] [tz_vfs][ERROR]: [tz_vfs_read][155] wait_for_completion was interrupt
[2438.466845] Freezing of tasks failed after 2.012 seconds
              (1 tasks refusing to freeze, wq_busy=0):
[2438.469233] LocatorThumbnai D 0 8957 1501
Call trace:
 schedule
 fuse_simple_request+0x3f4/0x594
 fuse_atomic_open+0x458/0x908
 path_openat → do_filp_open → do_sys_open → __arm64_sys_openat
[2438.530057] Abort: One or more tasks refusing to freeze
```

Artinya: ada app (`LocatorThumbnai`, anak zygote 1501) lagi `openat()` ke
jalur `/storage/emulated` → menunggu balasan FuseDaemon (MediaProvider
pid 4027) → MediaProvider ikut ke-freeze → deadlock → freeze gagal →
suspend dibatalkan.

**Kalau pola ini kejadian saat layar ON**, app yang lagi nulis bakal
dibekuin berulang → persis gejala "gagal tanpa pesan, muter".

Korelasi angka (`suspend_stats`):

```
success: 45   fail: 26         <- 36% gagal
failed_freeze: 10
failed_suspend: 2   failed_suspend_noirq: 2
last_failed_dev: alarmtimer   last_failed_errno: -16 (EBUSY)
last_failed_step: freeze
```

dmesg: `Freezing user space processes` ×70, `Restarting tasks` ×70,
`Freezing of tasks failed` ×1, `PM: noirq suspend of devices failed` ×2,
`PM: Some devices failed to suspend` ×2.

**Yang sudah DISANGKAL:**
- FUSE source identik antar build (`git diff 282da..HEAD -- fs/fuse/` kosong)
- `CONFIG_FUSE_BPF=y`, `select FUSE_BPF` utuh, `ro.fuse.bpf.is_running=true`
- Tulis dari shell sehat: 64MB → `/sdcard/Download` 400 MB/s, `sync` 0.8s,
  `DCIM/Pictures/Movies/Download` semua OK
- DNS sehat: google/cloudflare/instagram resolve; Private DNS
  `hostname → dns.adguard.com` reachable (ping 80ms, 0% loss)
- WiFi sehat: 0% loss, avg 59ms, tanpa disconnect 40 menit,
  `TCPBacklogDrop=0`, `ListenOverflows=0`
- Kapasitas: `/data` 49GB kosong, `/storage/7FCE-FD09` 93GB kosong

## Fix

Belum.

## Verification

Belum. Minimal: satu app menyimpan ke `/sdcard/Download` + satu download
dari browser, file-nya ada isinya (bukan 0-byte) dan kebaca ulang.

## Regression test

- Test download beneran dari app (bukan baca dmesg — gotcha FUSE_BPF).
- Simpan foto/screenshot → kebaca di galeri.
- Tulis ke SD card `7FCE-FD09`.
