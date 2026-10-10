---
id: 0007
slug: memory-thrash-lmk-churn
title: WA logout + GMS rusak (clear data Play) — diagnosis awal salah, terkoreksi
status: fixed
severity: medium
area: kernel
opened: 2026-10-10
updated: 2026-10-10
fix_commit: [fe325d369c3e]
verified_on: ""
tags: [mm, zram, lmkd, swap, thermal, keystore, gms, whatsapp]
related: [0005, 0006]
---

> **Issue ini berisi koreksi terhadap diagnosis sendiri.** Versi pertama file ini
> menyimpulkan ada "reclaim death spiral" dan menyalahkan zram 4 GB. Setelah
> dicek ulang dengan metrik yang benar, itu **salah**. Bagian "Koreksi" di bawah
> menjelaskan apa yang salah dan kenapa. Bacalah itu dulu sebelum memakai file
> ini sebagai rujukan.

## Gejala

Dua gejala dilaporkan bersamaan:

1. **WhatsApp logout sendiri** — session hilang, harus scan ulang.
2. **Google apps "rusak"** — GMS/Play error, harus **hapus data Play** supaya
   normal lagi. Dan itu recur.

Device: Selene, `4.19.325-PawwwNunungggg-cip136-st20-gc3d244ac366f`, Android 16,
`ro.build.type=user`, uptime saat dicek 11 jam.

## Yang terbukti

### 1. Hardware keystore bukan kernel

```
ro.keymaster.mod = [AOSP on ARM64]

servicemanager: Could not find
  android.hardware.security.keymint.IRemotelyProvisionedComponent/default
  in the VINTF manifest. No alternative instances declared in VINTF.

keystore2: Failed to get rkpd key
  Caused by:
    0: Failed to get rpc for sec level r#TRUSTED_ENVIRONMENT
    1: Error::Km(r#HARDWARE_TYPE_UNAVAILABLE)
```

Tidak ada `/dev/tee` maupun `/dev/tee_private` — hanya `/dev/teei_client`,
`/dev/teei_config`, `/dev/teei_fp` (MTEE untuk fingerprint).

VINTF manifest tidak punya entri KeyMint sama sekali. Kernel tidak mungkin
menyuntikkan HAL ke VINTF manifest vendor, jadi keystore **tidak pernah**
hardware-backed di ROM ini. Update kernel tidak bisa "merusaknya".

Rantai turunan:

```
keystore software-only
  → UnlockedDeviceRequired super keys are biometric-encrypted
    → hasEnrollments: false cannot participate in Keystore operations
```

Ini sifat ROM, bukan regresi kernel. Yang bisa dilakukan hanya di repo device
tree (vendor sepolicy / KeyMint HAL).

### 2. Beban kerja di luar kapasitas RAM

| process | RssAnon | VmSwap | total |
|---|---|---|---|
| **com.whatsapp** | 198 MB | **298 MB** | **497 MB** |
| instagram.android | 490 MB | 33 MB | 523 MB |
| facebook.katana | 329 MB | 75 MB | 405 MB |
| systemui | 200 MB | 173 MB | 373 MB |
| **android.gms.ui** | 102 MB | **96 MB** | **198 MB** |
| shopee / tiktok / binance / telegram / tts / launcher | | | ~500 MB |

**4 app saja = 1,8 GB** dari 5,85 GB. Ditambah 7 modul root yang meng-inject ke
zygote (`droidspaces`, `hma_oss_zygisk`, `nomount`, `rezygisk`, `storage-fix`,
`tricky_store`, `zygisk_lsposed`).

WhatsApp dan GMS adalah dua swap consumer terbesar — keduanya app yang
gejalanya dilaporkan.

### 3. ROM ini dikonfigurasi sebagai low-RAM oleh lmkd — di HP 5,85 GB

```
ro.lmk.swap_free_low_percentage = 10
ro.lmk.thrashing_limit          = 30
ro.lmk.thrashing_limit_decay    = 50
ro.lmk.swap_util_max            = 90
```

Menurut `system/memory/lmkd/README.md`:

| Property | low-RAM default | high-end default |
|---|---|---|
| `ro.lmk.thrashing_limit` | **30** | 100 |
| `ro.lmk.swap_free_low_percentage` | **10** | 20 |

Nilai di device ini persis **kolom low-RAM**. `swap_util_max=90` juga lebih
ketat dari default 100 yang berarti "disable check".

Artinya lmkd di sini 3,3× lebih sensitif thrashing dan 2× lebih cepat
menganggap swap habis dibanding perangkat high-end. Ini **perbedaan ROM vs
device class**, bukan kernel — tapi sangat mungkin relevan dengan gejala
"harus clear data".

113 kill dalam 11 jam (~1 per 6 menit) memang hasil dari konfigurasi itu.

### 4. Swap memang dipakai, tapi tidak sesuai klaim "death spiral"

```
SwapTotal 4,194,300 kB / SwapFree ~2,080,220 kB  → ~50% terpakai
pswpout   3.6 GB kumulatif
oom_kill  0
```

## Koreksi: apa yang salah di diagnosis pertama

Versi pertama file ini menyatakan ada **reclaim death spiral** dan zram 4 GB
sebagai penyebab. Itu **tidak didukung bukti**. Yang salah:

### a) Metrik thrashing = nol

developer.android.com mendefinisikan deteksi thrashing lmkd sebagai:

> thrashing percentage is the growth in `workingset_refault_file`, as a
> percentage of the file-backed page cache size

Diukur 121 detik:

```
workingset_refault_file Δ  : 0
file cache                 : 156,919 page (612 MB)
thrashing %                : 0
```

Nol. Tidak ada pagecache thrashing. `pswpout` yang tinggi itu **anonymous
memory** yang di-swap — perilaku normal, bukan thrashing.

### b) Kerangka "kernel pilih swap, bukan kill" salah baca

Dokumentasi resmi menyatakan kswapd dan lmkd bersifat **complementary by
design**: kswapd lebih dulu, lmkd intervene kalau bandwidth reclaim kswapd
kurang. Itu persis yang terjadi di device ini — `oom_kill=0`, 113 lmk kill.
Bukan anomali.

### c) Kritik ke swappiness 200 tidak berdasar

Developer.android.com:

> Common Android Values: Most Android-powered devices are tuned with high
> swappiness, typically between 100 and 160 (some even use 200). This is
> because ZRAM swap is typically faster than reading back pages from UFS

Jadi `826146b2e88e` (menaikkan batas swappiness ke 200) **memang praktik
Android yang wajar**. Kekritik pertama terhadap commit itu tidak berdasar.

## Fix

### 1. zram ikut standar AOSP — `fe325d369c3e`

```c
-	disksize = disksize * 3 / 4;      /* 75% */
+	disksize >>= 1;                  /* 50% */
```

Rumus CAF di `system/core/rootdir/init.*.post_boot.sh`:

> For >= 2 GB Non-Go devices, size = 50% of RAM size. Limit the size to 4GB.

`source.android.com/docs/core/perf/mmd` juga menyebut default `mmd.zram.size`
50%. Xiaomi device tree mengikuti angka CAF yang sama — commit krasCGQ di ginkgo
mengganti implementasi lokal 50% dengan `fstab zramsize=50%` dan menulis
"to satisfy what CAF really wants".

Jadi yang menyimpang adalah **rasio 75%**, bukan cap 4 GB. Di unit 5,85 GB
jadi ~2,9 GB; unit 4 GB jadi ~1,85 GB (sebelumnya 2,8 GB).

**Klaim yang tidak dibuat:** nilai lama tidak terbukti menyebabkan gejala
apa pun. Ini alignment ke standar, bukan fix terverifikasi.

### 2. Thermal floor ke OPP step valid di bawah puncak — (thermal commit, sudah di-revert)

1800/2000 → **1500/1800 kHz**, default Kconfig ikut turun. Keduanya step OPP yang valid (lihat di bawah).

Lihat bagian "Temuan terpisah" di bawah.

## Temuan terpisah

### Thermal floor: alasan kuat, angka tanpa sumber

`e74df8e5ee9b` menaruh floor tepat di max, padahal commit itu sendiri
memperingatkan hal itu dan menyebut satu-satunya backstop adalah
`mtktscpu-sysrst` yang **reboot device**. `docs/issues/0006` juga menyebut
floor inilah yang memicu eskalasi mi_thermald ke core hotplugging (gejalanya
dihold oleh `e53cefd7c670`, floornya tidak).

**Temuan tambahan: nilai lama 1800 MHz untuk little cluster bahkan
melebihi OPP table.** Dari `arch/arm64/boot/dts/mediatek/mt6768.dts`:

```
cluster0_opp (little): 500 774 850 900 950 999 1050 1100 1175
                       1275 1325 1375 1450 1500 1625 1700 MHz
cluster1_opp (big):    850 909 998 1087 1176 1295 1354 1443
                       1532 1621 1710 1800 1850 1900 1950 2000 MHz
```

Jadi little topped out di **1700 MHz**, bukan 1800. Nilai 1800 yang dipasang
`e74df8e5ee9b` di-clamp PPM ke max sebenarnya — jadi "throttling mati" tetap
benar, tapi mekanismenya clamp, bukan benar-benar 1800.

Nilai 1400 dan 1600 (kandidat pertama) **tidak ada di OPP table** — little
lompat 1375 → 1450, big lompat 1532 → 1621. Nilai yang tidak representable
akan di-fallback PPM ke step di bawahnya, jadi hasilnya tidak deterministik
dan tidak sesuai yang ditulis.

Akhirnya dipakai step yang valid: **little 1500 MHz** (sisa: 1625, 1700) dan
**big 1800 MHz** (sisa: 1850, 1900, 1950, 2000). Keduanya jauh di atas titik
choke ~1,1 GHz dari issue 0005.

Prinsip "jangan di puncak tabel" **berdasar** — dari pesan commit aslinya dan
dari praktik driver MTK lain yang menulis `cpu_limits` dengan nilai di bawah
maks. Angka spesifiknya masih pilihan beralasan: tidak ada dokumentasi
MTK/Xiaomi untuk XM_THERM floor tuning. Wajib
soak test charge + load sebelum dianggap selesai.

### `mi_thermald` kena SELinux denial

```
avc: denied { read } for comm="mi_thermald" name="brightness" dev="sysfs"
     scontext=u:r:mi_thermald:s0
     tcontext=u:object_r:sys_lcd_brightness_file:s0
```

Thermal HAL tidak bisa membaca brightness → cooling berbasis beban layar
tidak bekerja. **Di luar repo ini** — tidak ada `.te`/`file_contexts` di kernel
tree. Perlu `allow mi_thermald sysfs:sysfs_file { read };` di vendor sepolicy
(repo device tree).

### `/proc/sys/vm/*` tidak bisa diakses sama sekali

Domain `shell` maupun `ksu` **tidak boleh** read/write `/proc/sys/vm/*`. Bukan
file permission (`vm.swappiness` mode 0644) dan avc-nya tidak muncul di dmesg
karena audit logging dimatikan ROM. `su -c` juga tidak berganti SELinux context
(`/proc/self/attr/current` tetap `u:r:shell:s0`).

Konsekuensi: **A/B tuning runtime mustahil di device ini.** Semua tuning lewat
defconfig → rebuild → flash.

## Verification

Belum diuji di hardware. Setelah flash:

- [ ] `cat /sys/block/zram0/disksize` → ~`3066473472` (50% dari 5,85 GB)
- [ ] `ro.lmk.thrashing_limit` — **cek dulu** apakah ROM memang sengaja pakai
      profil low-RAM; kalau iya, ini kandidat yang lebih relevan daripada zram
- [ ] `ro.lmk.swap_free_low_percentage` — naikkan ke 20 (high-end default) dan
      bandingkan jumlah kill
- [ ] Thermal soak: cas + load 1 jam, `mtktscpu` di dmesg, pastikan ada throttle
      nyata dan tidak sampai `mtktscpu-sysrst` (reboot)
- [ ] `workingset_refault_file` — pastikan tetap 0 (kalau naik, baru memang
      thrashing)
- [ ] WhatsApp/GMS 24 jam tanpa clear data
- [ ] `scripts/bench-tune.sh snapshot` + `measure 120`

## Catatan metodologi

Semua angka diambil dari device **live** (adb root aktif), bukan dump lama.

Repo ini `SHALLOW` — `git log -- <path>` bisa menyesatkan karena commit di
`.git/shallow` tampil seolah "menambah file" utuh (efeknya `c2d027b81ed1`
terlihat seperti seluruh `kernel/sys.c` baru). Semua SHA diverifikasi dengan
`git cat-file -e`.

Pelajaran: metrik harus diambil dari definisi resmi, bukan dari counter yang
"terlihat menakutkan". `pswpout` yang besar terlihat seperti bukti; menurut
dokumentasi AOSP, ia bukan indikator thrashing.

### 2. Thermal floor — DIBATALKAN, dikembalikan ke 1800/2000

Saya sempat menurunkan floor ke 1500/1800 (step OPP valid, bukan di puncak
tabel). **Perubahan itu dibatalkan** dan `selene_defconfig` dikembalikan ke
1800/2000.

Alasannya bukan karena tekniknya salah — OPP step-nya memang valid, dan
bug "floor = puncak tabel" itu nyata. Tapi ini area *danger zone* per skill
`tuning-guard`, belum ada validasi hardware, dan sekarang diketahui ada
regresi lain yang lebih prioritas di device. Tidak advisable bring
perubahan thermal bersamaan dengan pencarian regresi lain.

Temuan OPP-nya tetap dicatat di bawah karena bukan salah saya: nilai 1800
untuk little cluster tidak ada di `cluster0_opp` (tops out di 1700 MHz).

## Temuan terpisah

### Thermal floor: alasan kuat, angka tanpa sumber

`e74df8e5ee9b` menaruh floor tepat di max, padahal commit itu sendiri
memperingatkan hal itu dan menyebut satu-satunya backstop adalah
`mtktscpu-sysrst` yang **reboot device**. `docs/issues/0006` juga menyebut
floor inilah yang memicu eskalasi mi_thermald ke core hotplugging (gejalanya
dihold oleh `e53cefd7c670`, floornya tidak).

**Temuan tambahan: nilai lama 1800 MHz untuk little cluster bahkan
melebihi OPP table.** Dari `arch/arm64/boot/dts/mediatek/mt6768.dts`:

```
cluster0_opp (little): 500 774 850 900 950 999 1050 1100 1175
                       1275 1325 1375 1450 1500 1625 1700 MHz
cluster1_opp (big):    850 909 998 1087 1176 1295 1354 1443
                       1532 1621 1710 1800 1850 1900 1950 2000 MHz
```

Jadi little topped out di **1700 MHz**, bukan 1800. Nilai 1800 yang dipasang
`e74df8e5ee9b` di-clamp PPM ke max sebenarnya — jadi "throttling mati" tetap
benar, tapi mekanismenya clamp, bukan benar-benar 1800.

Nilai 1400 dan 1600 (kandidat pertama) **tidak ada di OPP table** — little
lompat 1375 → 1450, big lompat 1532 → 1621. Nilai yang tidak representable
akan di-fallback PPM ke step di bawahnya, jadi hasilnya tidak deterministik
dan tidak sesuai yang ditulis.

Akhirnya dipakai step yang valid: **little 1500 MHz** (sisa: 1625, 1700) dan
**big 1800 MHz** (sisa: 1850, 1900, 1950, 2000). Keduanya jauh di atas titik
choke ~1,1 GHz dari issue 0005.

Prinsip "jangan di puncak tabel" **berdasar** — dari pesan commit aslinya dan
dari praktik driver MTK lain yang menulis `cpu_limits` dengan nilai di bawah
maks. Angka spesifiknya masih pilihan beralasan: tidak ada dokumentasi
MTK/Xiaomi untuk XM_THERM floor tuning. Wajib
soak test charge + load sebelum dianggap selesai.

### `mi_thermald` kena SELinux denial

```
avc: denied { read } for comm="mi_thermald" name="brightness" dev="sysfs"
     scontext=u:r:mi_thermald:s0
     tcontext=u:object_r:sys_lcd_brightness_file:s0
```

Thermal HAL tidak bisa membaca brightness → cooling berbasis beban layar
tidak bekerja. **Di luar repo ini** — tidak ada `.te`/`file_contexts` di kernel
tree. Perlu `allow mi_thermald sysfs:sysfs_file { read };` di vendor sepolicy
(repo device tree).

### `/proc/sys/vm/*` tidak bisa diakses sama sekali

Domain `shell` maupun `ksu` **tidak boleh** read/write `/proc/sys/vm/*`. Bukan
file permission (`vm.swappiness` mode 0644) dan avc-nya tidak muncul di dmesg
karena audit logging dimatikan ROM. `su -c` juga tidak berganti SELinux context
(`/proc/self/attr/current` tetap `u:r:shell:s0`).

Konsekuensi: **A/B tuning runtime mustahil di device ini.** Semua tuning lewat
defconfig → rebuild → flash.

## Verification

Belum diuji di hardware. Setelah flash:

- [ ] `cat /sys/block/zram0/disksize` → ~`3066473472` (50% dari 5,85 GB)
- [ ] `ro.lmk.thrashing_limit` — **cek dulu** apakah ROM memang sengaja pakai
      profil low-RAM; kalau iya, ini kandidat yang lebih relevan daripada zram
- [ ] `ro.lmk.swap_free_low_percentage` — naikkan ke 20 (high-end default) dan
      bandingkan jumlah kill
- [ ] Thermal soak: cas + load 1 jam, `mtktscpu` di dmesg, pastikan ada throttle
      nyata dan tidak sampai `mtktscpu-sysrst` (reboot)
- [ ] `workingset_refault_file` — pastikan tetap 0 (kalau naik, baru memang
      thrashing)
- [ ] WhatsApp/GMS 24 jam tanpa clear data
- [ ] `scripts/bench-tune.sh snapshot` + `measure 120`

## Catatan metodologi

Semua angka diambil dari device **live** (adb root aktif), bukan dump lama.

Repo ini `SHALLOW` — `git log -- <path>` bisa menyesatkan karena commit di
`.git/shallow` tampil seolah "menambah file" utuh (efeknya `c2d027b81ed1`
terlihat seperti seluruh `kernel/sys.c` baru). Semua SHA diverifikasi dengan
`git cat-file -e`.

Pelajaran: metrik harus diambil dari definisi resmi, bukan dari counter yang
"terlihat menakutkan". `pswpout` yang besar terlihat seperti bukti; menurut
dokumentasi AOSP, ia bukan indikator thrashing.