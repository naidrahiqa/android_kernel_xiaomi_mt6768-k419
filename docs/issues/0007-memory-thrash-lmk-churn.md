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

> **File ini mengandung koreksi terhadap diagnosisnya sendiri.** Versi pertama
> menyimpulkan ada "reclaim death spiral" dan menyalahkan zram 4 GB. Setelah
> dicek dengan metrik resmi, itu **salah**. Baca bagian "Koreksi" dulu.

## Gejala

1. **WhatsApp logout sendiri** — session hilang, harus scan ulang.
2. **Google apps "rusak"** — harus **hapus data Play** supaya normal, dan recur.

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

VINTF manifest **tidak punya entri KeyMint sama sekali**. Kernel tidak mungkin
menyuntikkan HAL ke VINTF manifest vendor, jadi keystore **tidak pernah**
hardware-backed di ROM ini. Update kernel tidak bisa "merusaknya".

Rantai turunan:

```
keystore software-only
  → UnlockedDeviceRequired super keys are biometric-encrypted
    → hasEnrollments: false cannot participate in Keystore operations
```

Ini sifat ROM. Yang bisa dikerjakan hanya di repo device tree.

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
zygote.

### 3. ROM dikonfigurasi low-RAM oleh lmkd — di HP 5,85 GB

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

Nilai di device persis **kolom low-RAM**. `swap_util_max=90` juga lebih ketat
dari default 100 yang berarti "disable check". lmkd di sini 3,3× lebih sensitif
thrashing dan 2× lebih cepat menganggap swap habis dibanding perangkat
high-end. Ini **perbedaan ROM vs device class**, bukan kernel.

### 4. Swap dipakai, tapi tidak ada thrashing

```
SwapTotal 4,194,300 kB   SwapFree ~2,080,220 kB   (~50% terpakai)
pswpout 3.6 GB kumulatif      oom_kill 0      LMK kill 156 (naik terus)
```

## Koreksi: apa yang salah di diagnosis pertama

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

Nol. Tidak ada pagecache thrashing. `pswpout` yang tinggi itu anonymous memory
yang di-swap — normal, bukan indikator thrashing.

### b) "Kernel pilih swap, bukan lmkd kill" adalah salah baca

Dokumentasi resmi menyatakan kswapd dan lmkd **complementary by design**:
kswapd lebih dulu, lmkd intervene kalau bandwidth reclaim-nya kurang. Itu
persis yang terjadi — `oom_kill=0`, banyak lmk kill. Bukan anomali.

### c) Kritik ke swappiness 200 tidak berdasar

developer.android.com:

> Most Android-powered devices are tuned with high swappiness, typically
> between 100 and 160 (some even use 200). This is because ZRAM swap is
> typically faster than reading back pages from UFS

`826146b2e88e` (batas swappiness dinaikkan ke 200) **memang praktik Android
yang wajar**.

### d) `/proc/sys/vm/*` empat — klaim "diblokir sepolicy" salah

Saya sempat menulis bahwa sepolicy memblokir akses sysctl. **Salah** — artefak
dari script diagnos sendiri. Dua sebabnya:

1. Path salah. Key ditulis `vm.swappiness`, jadi `/proc/sys/$key` menghasilkan
   `/proc/sys/vm.swappiness` yang memang tidak ada. Errornya
   `Permission denied`, yang mengesankan seperti blokir SELinux.
2. `toybox sh` menolak `for ... do` di dalam `su -c '...'`.

Faktanya:

```
$ adb shell su -c 'cat /proc/sys/vm/swappiness'
100
```

Akses dari domain `ksu` (uid=0, `u:r:ksu:s0`) **penuh**. A/B tuning runtime
**bisa jalan** di device ini. Pelajaran: pada Android, "Permission denied"
sering berarti path salah, bukan kebijakan.

## Fix

### zram ikut standar AOSP — `fe325d369c3e`

```c
-	disksize = disksize * 3 / 4;      /* 75% */
+	disksize >>= 1;                  /* 50% */
```

Rumus CAF di `system/core/rootdir/init.*.post_boot.sh`:

> For >= 2 GB Non-Go devices, size = 50% of RAM size. Limit the size to 4GB.

`source.android.com/docs/core/perf/mmd` juga menyebut default `mmd.zram.size`
50%. Xiaomi device tree mengikuti angka CAF yang sama — commit krasCGQ di ginkgo
mengganti implementasi lokal dengan `fstab zramsize=50%` dan menulis "to satisfy
what CAF really wants".

Yang menyimpang dari standar adalah **rasio 75%**, bukan cap 4 GB. Di unit
5,85 GB jadi ~2,9 GB; unit 4 GB jadi ~1,85 GB (sebelumnya 2,8 GB).

**Klaim yang tidak dibuat:** nilai lama tidak terbukti menyebabkan gejala
apa pun. Ini alignment ke standar.

Rumus `late_initcall` tetap, jadi masih mengalahkan write `zramsize` dari
vendor fstab (`adcd3ae96c0c`).

## Temuan terpisah

### Thermal floor: bug nyata, tapi perbaikannya DIBATALKAN

`e74df8e5ee9b` menaruh floor di 1800/2000. **Nilai 1800 untuk little cluster
tidak ada di OPP table** — `cluster0_opp` tops out di **1700 MHz**:

```
cluster0_opp (little) 500 774 850 900 950 999 1050 1100 1175
                      1275 1325 1375 1450 1500 1625 1700 MHz
cluster1_opp (big)    850 909 998 1087 1176 1295 1354 1443
                      1532 1621 1710 1800 1850 1900 1950 2000 MHz
```

PPM meng-clamp, jadi hasilnya efektif 1700 = puncak tabel. Help text commit
yang menyebut "tops out at 1800 MHz" memang salah.

Terbukti dari dmesg device:

```
thermal_sys: cpu_limits: cluster 0 cap 1625000 kHz raised to floor 1800000 kHz
thermal_sys: cpu_limits: cluster 0 cap 1500000 kHz raised to floor 1800000 kHz
```

mi_thermald meminta 1625000 dan 1500000 (keduanya OPP little valid), lalu
kernel menaikkan ke 1800000 yang tidak representable.

Saya sempat menurunkan floor ke 1500/1800 (step OPP valid, bukan puncak).
**Perubahan itu dibatalkan** dan defconfig dikembalikan ke 1800/2000 — thermal
adalah *danger zone* per `tuning-guard`, belum ada validasi hardware, dan ada
regresi lain yang lebih prioritas. Temuan OPP-nya tetap dicatat di sini karena
bukan salah saya.

### `mi_thermald` kena SELinux denial

```
avc: denied { read } for comm="mi_thermald" name="brightness" dev="sysfs"
     scontext=u:r:mi_thermald:s0
     tcontext=u:object_r:sys_lcd_brightness_file:s0
```

Thermal HAL tidak bisa membaca brightness → cooling berbasis beban layar tidak
berfungsi. **Di luar repo ini** — tidak ada `.te`/`file_contexts` di kernel
tree. Perlu `allow mi_thermald sysfs:sysfs_file { read };` di vendor sepolicy.

### Tools

`scripts/bench-tune.sh` — snapshot / measure / set / selftest. A/B runtime
sudah terbukti jalan (swappiness 100 → 60: swap-out 145 MB → 24 MB per 120
detik, MemFree berubah dari −91 MB jadi +5 MB). Restore via trap, terverifikasi.

## Verification

Belum diverifikasi end-to-end di hardware.

- [ ] `cat /sys/block/zram0/disksize` → ~`2936012800` (50% dari 5,85 GB)
- [ ] `workingset_refault_file` tetap 0 (kalau naik, baru memang thrashing)
- [ ] WhatsApp/GMS 24 jam tanpa clear data
- [ ] `scripts/bench-tune.sh snapshot` + `measure 120`

## Catatan metodologi

Semua angka diambil dari device **live** (adb root aktif), bukan dump lama.

Repo ini **SHALLOW** — `git log -- <path>` bisa menyesatkan karena commit di
`.git/shallow` tampil seolah "menambah file" utuh, dan `git show <sha>:<file>`
untuk boundary tersebut mengembalikan 0 baris. Semua SHA diverifikasi dengan
`git cat-file -e`.

Pelajaran: metrik harus diambil dari definisi resminya, bukan dari counter yang
"terlihat menakutkan"; dan clock ceiling harus dibaca dari device tree, bukan
diasumsikan.
