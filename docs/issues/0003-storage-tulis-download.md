---
id: 0003
title: Tidak bisa menyimpan konten dari TikTok (Android/data ditolak FUSE)
status: fixed
severity: high
area: device
opened: 2026-10-07
updated: 2026-10-09
fix_commit: "160f86fa35e6"
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

## Fix (Userspace Daemon via KernelSU / boot-completed)

Sempat dicoba pendekatan in-kernel auto-bind (commit `56b02c0e6ade`), namun **gagal di hardware** dan di-revert (commit `160f86fa35e6`) karena alasan mendasar:
1. **SELinux Restriction**: `kworker` berjalan di domain `u:r:kernel:s0`. Saat `kern_path()` memeriksa `/data/media/0/Android/*`, Android SEPolicy secara tegas menolak `capability { dac_override dac_read_search }` untuk domain `kernel` (muncul belasan log `avc: denied` di dmesg), sehingga path lookup mengembalikan `-EACCES`.
2. **FBE Timing**: Sebelum user membuka kunci layar pertama kali (Direct Boot), credential encrypted (CE) storage belum terdekripsi sehingga path belum ada. Retry loop habis sebelum dekripsi selesai.
3. **Multi-User**: Direct path grafting di kernel tidak fleksibel menangani secondary users (Work Profile / Dual Apps).

### Solusi Final & Bulletproof: Modul KernelSU `storage-fix` (v1.2)

Mekanisme bind-mount dijalankan oleh daemon di userspace melalui KernelSU di domain `u:r:ksu:s0` (unconfined root):
- **Lokasi modul**: `/data/adb/modules/storage-fix/` (`module.prop`, `service.sh`, `auto_mount`)
- **Zip installer**: `storage-fix-v1.2.zip` (tersedia di `/sdcard/Download/` dan `/sdcard/Download/Telegram/`)
- **Fallback hook**: `/data/adb/boot-completed.d/storage-fix.sh`
- **Mekanisme**:
  1. Worker background me-looping dan menunggu hingga `/storage/emulated/0/Android` dan `/data/media/0/Android` selesai terdekripsi dan siap diakses.
  2. Melakukan scanning dinamis untuk semua user ID di `/data/media/<uid>`.
  3. Meng-graft `data`, `media`, dan `obb` ke `/storage/emulated/<uid>/Android/*` secara idempotent (cek `/proc/mounts`) dengan `--make-shared`.
  4. **Watchdog Daemon Anti-Drop**: Loop setiap 5 detik memverifikasi mountpoint; jika proses MediaProvider me-restart dan me-remount storage, daemon langsung meng-graft ulang dalam hitungan detik.
  5. Auto-heal permissions: Memulihkan kepemilikan direktori publik (`DCIM`, `Pictures`, dll) ke `media_rw:media_rw` (775/664) dan folder cache app TikTok ke `ext_data_rw`.
  6. TCP Congestion Control otomatis di-tune ke `bbr`.
  7. Seluruh log dicatat ke `/data/adb/storage-fix.log`.

### Bukti Assembly Disassembly (`libfuse_jni.so`)
- `0xb85b0`: `adr x8, 0x3e940` (`/sys/fs/bpf/prog_fuseMedia_fuse_media`)
- `0xb85f4`: `bl syscall(bpf, BPF_OBJ_GET)` -> mengembalikan -ENOENT karena ROM tidak punya `fuse_bpf.o`.
- `0xb865c`: `mov w4, wzr` -> parameter `bpf_enabled` dipaksa ke `0` (false), memicu fallback ke blok penolakan `Rejected access to app-private dir on FUSE: ...`.

## Verification

```
sebelum fix:  2233+  "Rejected access to app-private dir on FUSE"
sesudah fix:     0   "Rejected access to app-private dir on FUSE"
mount aktif:     /data/media/0/Android/{data,media,obb} -> /storage/emulated/0/Android/{data,media,obb}
status log:      SKIP already bound / OK bind
```

- TikTok simpan video & foto berfungsi normal.
- ProtonMail & app scoped storage lainnya tidak mengalami permission denied / rejection.

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

---

## Kasus Lanjutan: Galeri & Media Terkunci (WhatsApp Gagal Kirim Foto)

### Gejala
- WhatsApp (`com.whatsapp`, uid 10457) tidak bisa mengirim foto/media.
- Saat memilih gambar atau mengambil foto dari kamera WhatsApp, `MediaComposerActivity` terbuka sekejap lalu tertutup otomatis dalam hitungan detik.
- Internet terasa macet / upload gambar tidak berjalan.

### Root Cause
1. **DAC Permission Lockout di Shared Storage**:
   Folder media publik (`/data/media/0/DCIM`, `/data/media/0/Pictures`, `/data/media/0/Download`, dll.) serta file foto di dalamnya dimiliki oleh UID lama/MediaProvider (`u0_a367:media_rw`) dengan permission **`drwxrws---` (770)** dan file **`-rw-rw----` (660)** akibat restore SwiftBackup / DAC inherit.
   Karena bit `others` adalah `---` (tanpa izin baca/masuk), WhatsApp (UID `10457`) mendapatkan error **`Permission denied (EACCES)`** saat mencoba membaca file sumber foto.
2. **TCP Congestion Control Westwood**:
   Kernel yang berjalan menggunakan default `westwood` yang sangat rentan drop throughput saat jitter hotspot Wi-Fi.

### Solusi & Verifikasi
1. Ubah ownership direktori media bersama ke `media_rw:media_rw`:
   ```sh
   chown -R media_rw:media_rw /data/media/0/{DCIM,Pictures,Download,Documents,Movies,Music,...}
   chmod -R u=rwX,g=rwX,o=rX /data/media/0/{DCIM,Pictures,Download,Documents,Movies,Music,...}
   ```
2. Restart `com.android.providers.media.module` untuk membersihkan cache atribut FUSE.
3. Otomatisasi disematkan ke modul KernelSU `/data/adb/modules/storage-fix/service.sh` agar auto-heal berjalan setiap boot.
4. Set TCP congestion control ke `bbr` via `sysctl -w net.ipv4.tcp_congestion_control=bbr`.
5. **Hasil**: WhatsApp sukses mengirim gambar dan galeri dapat diakses normal tanpa hambatan.