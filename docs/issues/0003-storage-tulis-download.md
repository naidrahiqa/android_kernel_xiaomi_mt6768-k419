---
id: 0003
title: Tidak bisa menyimpan konten dari TikTok (Android/data ditolak FUSE)
status: fixed
severity: high
area: device
opened: 2026-10-07
updated: 2026-10-08
fix_commit: ""
verified_on: 4.19.325-PawwwNunungggg-cip136-st20-ge6c6772cbec6
tags: [storage, fuse, fuse_bpf, fuse-daemon, scoped-storage, mediaprovider, tiktok]
related: [0004]
---

## Issue

TikTok (`com.ss.android.ugc.trill` v47.1.4) tidak bisa menyimpan konten:

- **video** → nyangkut di **0%**, tidak ada progres
- **foto** → **error instan**

Facebook **tidak** terpengaruh (simpan gambar aman). App lain juga bisa
menulis normal ke shared storage.

## Root cause (TERKONFIRMASI)

**Bukan bug kernel, bukan juga ROM rusak.** Yang rusak adalah **hierarki
mount**: `Android/data|media|obb` di-bind-mount vold **hanya** di
`/mnt/user/0/emulated/0/Android/...`, sedangkan app menavigasi lewat
**`/storage/emulated/0/Android/...` yang masih dilayani FUSE** — dan FUSE
itu **menolak** semua akses app ke app-private dir.

### Rantai penyebab

`MediaProvider` (Android 16, `BP4A.251205.006`) `FuseDaemon.cpp:829`:

```cpp
if (!fuse->bpf && android::base::StartsWith(path, PRIMARY_VOLUME_PREFIX)) {
    LOG(WARNING) << "Rejected access to app-private dir on FUSE: " << path
                 << " from uid: " << uid;
    return false;                       // -> errno ENOENT
}
```

Jadi selama `fuse->bpf == false`, **setiap** akses app ke
`Android/data|media|obb/<pkg>` mengembalikan `ENOENT`. Nilai itu di
`FuseDaemon.cpp:2468` dan `:2523`:

1. `IsFuseBpfEnabled()` → `ro.fuse.bpf.is_running` = **true**
   (vold mengaturnya karena kernel mengekspos
   `/sys/fs/fuse/features/fuse_bpf` = `supported`)
2. karena `true`, daemon lanjut ke
   `retrieveProgram("/sys/fs/bpf/prog_fuseMedia_fuse_media")`
3. pin tersebut **tidak pernah ada** → `bpf_enabled = false` (diam-diam)
4. → seluruh akses app-private ditolak

Kenapa pin tidak ada: **ROM ini tidak menyertakan program FUSE-BPF sama
sekali.**

```
$ find /apex -name "*.o"
/apex/com.android.tethering/etc/bpf/mainline/{clatd,dscpPolicy,netd,offload,test}.o
/apex/com.android.uprobestats/etc/bpf/uprobestats/*.o        # tidak ada fuse_bpf.o
```

`MediaProvider.apk` berisi `libfuse_jni.so` + `libfuse.so` tetapi **tanpa
objek BPF** (tidak ada `.o`/asset bpf) → daemon tidak bisa memuat sendiri;
`bpfloader` juga tidak memuatnya (`NetBpfLoad: detected 5 of 5`, daftar
program tidak memuat fuse).

### BuktiIRL

```
$ logcat | grep -c "Rejected access to app-private dir"
9901
$ logcat | grep "Rejected access to app-private dir" | sed -E 's|.*FUSE: ||;s| from uid.*||' | sort -u
/storage/emulated/0/Android/data/com.ss.android.ugc.trill      <- TikTok, uid 10452
```

Izin sudah benar sebelum fix (`drwxrwsrwx 4 u0_a452 ext_data_rw`), jadi
ini murni penolakan di level FUSE, bukan masalah permission.

`Android/media/com.ss.android.ugc.trill` dan `Android/obb/...` **tidak pernah
pernah dibuat** — konsistensi dengan fungsi yang selalu ditolak.

### Kenapa TikTok dan bukan Facebook

Pipeline simpan TikTok menulis file sementara ke `Android/data/<pkg>`-nya
sendiri dulu baru dipublish ke MediaStore → sesi pertama ditolak → video
0% (nggak ada byte masuk), foto langsung gagal. Facebook menulis langsung
lewat MediaStore dan tidak menyentuh `Android/data` → aman.

## Fix

Bind-mount direktori app-private dari backing store langsung ke jalur FUSE,
sehingga **FUSE dilewati sepenuhnya**. Diterapkan sebagai modul KernelSU
`storage-fix` (bukan perubahan kernel — kernel sudah benar):

```
/data/adb/modules/storage-fix/
  module.prop
  service.sh      # bind /data/media/<u>/Android/{data,media,obb}
                  #   -> /storage/emulated/<u>/Android/{...}
                  #   -> /mnt/user/<u>/emulated/<u>/Android/{...}
```

Script menunggu `/storage/emulated/0`, sleep 20 s agar vold selesai,
memproses semua user yang ada, skip yang sudah ter-mount (`mountpoint -q`),
dan log ke `/data/adb/storage-fix.log`.

## Verification

```
sebelum:  9901  "Rejected access to app-private dir on FUSE"
sesudah:     0  "Rejected access to app-private dir on FUSE"
error FUSE/MediaProvider setelah tes: 0
12 bind mount aktif (4 mountpoint x 3 direktori)
$ ls /storage/emulated/0/Android/data/com.ss.android.ugc.trill
cache
files
```

User mengonfirmasi: **simpan video & foto TikTok berhasil.**

Belum diverifikasi: persistensi setelah reboot (modul baru dibuat).

## Koreksi terhadap catatan sebelumnya

Dokumen versi sebelumnya menandai log `Rejected access to app-private dir`
sebagai **red herring**. Untuk gejala "file 0-byte",時間 itu memang tidak
terbukti — namunj **`symptom simpan TikTok ini ROOT CAUSE-nya persis log
itu.** Gtkedua perlu dibedakan.

Kesalahan investigasi yang sudah dilakukan dan tidak boleh diulang:

1. **`git log -- fs/fuse` tidak bisa dipakai.** Repo ini SHALLOW;
   `c2d027b81ed1` ada di `.git/shallow` dan tidak punya parent — itu batas
   graft yang menambah 21.435 baris (termasuk `.clang-format`, `CREDITS`),
   bukan cherry-pick FUSE. Melihatnya sebagai "commit yang menambah
   `backing.c`" = salah baca.
2. **`mount | grep Android/data` mengKosongkan** padahal bind-mount ada.
   `mount` tidak menampilkan semua entri; `/proc/mounts` /
   `cat /proc/mounts` yang benar. Akibatnya sempat disimpulkan
   "vold tidak pernah bind-mount".
3. **Impersonasi uid app via `su <uid>` tidak valid** sebagai uji FUSE:
   konteks SELinux tetap `u:r:ksu:s0`, sehingga path kontrol
   (`/sdcard/Download`) juga gagal → tidak membuktikan apa pun soal app.

## Perbedaan antar branch (terverifikasi, tapi TIDAK kausal)

`select FUSE_BPF` di `drivers/misc/mediatek/Kconfig.default`:

```
origin/PawwwNunungggg23.2 : 0   (tidak ada)
origin/PawwwNunungggg24.0 : 1   (ada)
```

`fs/fuse/backing.c` ada di semua branch (kecuali `cip/linux-4.19.y-cip`),
jadi FUSE-BPF bawaan tree MTK, bukan tambahan cherry-pick.

Nonetheless `select FUSE_BPF` **bukan** penyebab gejala ini: dengan flag
mati, `IsFuseBpfEnabled()` tetap mengembalikan `false` dan
`is_app_accessible_path()` tetap menolak. Status quo kernel tidak
mengubah hasil akhir.

## Regression test

- Simpan **video** TikTok → file keluar, ukuran > 0, bisa diputar.
- Simpan **foto** TikTok → tanpa error, muncul di galeri.
- `logcat -d | grep -c "Rejected access to app-private dir"` → 0.
- convincingly: **reboot** →ULAH modul jalan → ulangi 3 test di atas.
- Install app baru → `Android/data/<pkg>` & `Android/media/<pkg>` otomatis
  dibuat (sebelumnya `Android/media` gagal dibuat).
- Tulis dari shell tetap sehat: `/sdcard/Download` (shared storage, FUSE)
  tidak boleh ikut terganggu oleh bind mount.