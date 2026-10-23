---
id: 0031
title: 0.6X ultra-wide hangs — driver imgsensor IMX355 tak pernah dibawa ke tree k419
status: verified
severity: high
area: drivers
opened: 2026-10-24
updated: 2026-10-24
fix_commit: "e195ab7d5beb6aad368d231767ba8339dfbb2453"
verified_on: "2026-10-24 · selene 65cb03c00702 · 4.19.325-cip136-st20-EsTehAnget+ #1 SMP PREEMPT Sat Oct 24 04:57:42 WIB 2026 · NoMount v2.2.0 (605)"
tags: [imgsensor, imx355, ultrawide, camera, selene, defconfig]
related: [0008, 0030]
---

## Gejala

Leica Camera 5.0 di selene: tombol **0.6X** (Photo/Night) bikin preview beku,
shutter mati, tidak ada file tersimpan; `com.android.camera` harus di-force-stop.
Dokumentasi lama menyebut "Redmi 10 tidak punya ultra-wide" — **itu salah**:
sensor IMX355 (Sunny, vendor_id 104) ada di unit ini seharian.

## Root cause

Root cause-nya bukan vendor/HAL — kernel k419 yang tidak pernah membawa
drivernya. Bukti inventaris:

1. `git ls-tree -r 8b6e0db^ --name-only | grep -c imx355` → **0** — bahkan
   sebelum "fresh import of core integrations" (8b6e0db, Issue 0030) sudah
   tidak ada; driver IMX355 tidak pernah di-carried ke garis EsTehAnget.
2. Defconfig `CONFIG_CUSTOM_KERNEL_IMGSENSOR` hanya memuat 9 sensor —
   tanpa `imx355_sunny_ultra_mipi_raw` / `imx355_aac_ultra_mipi_raw`.
3. Vendor/HAL di sisi lain siap terima: blob `/vendor/lib64/*imx355*`
   ada, `persist.vendor.camera.ultra` menunjuk varian Sunny.
4. Dampak rantai: HAL hanya mendaftar 5 kamera → tidak ada role ultra-wide
   (21) → tombol 0.6X milih path kamera yang tidak eksis → hang.

## Fix

- Pulihkan kedua dir driver verbatim dari branch `lineage-23.2-selene`
  (sumber asli): `imx355_sunny_ultra_mipi_raw`, `imx355_aac_ultra_mipi_raw`.
- Tambah kedua nama ke baris `CONFIG_CUSTOM_KERNEL_IMGSENSOR` di
  `selene_defconfig`.
- Commit: `e195ab7d5beb6aad368d231767ba8339dfbb2453` (EsTehAnget24.0),
  cherry-pick `6bf3ad33caa7badd210ebd9d9498a6c3c6cd6c2e` (EsTehAnget-HyperOS).

## Bukti di hardware (verified)

Kernel yang di-flash: `4.19.325-cip136-st20-EsTehAnget+` (build 24 Okt 2026
04:57 WIB, Greenforce Clang 24.0.0).

```
dmesg: IMX355_SUNNY[get_imgsensor_id] get vendor_id=104
dmesg: IMGSENSOR: sensor id: 0x356 (sensor_idx 2)
props: persist.vendor.camera.ultra = sunny_imx355_ultra_i
dumpsys media.camera>> cameras: 6   # sebelumnya 5
camera 2 → role 21 (ultra-wide)
```

## Catatan ops

- Manajer KSU lama (`me.weishu.kernelsu` v3.3.1-22, versionCode 32702) tidak
  mau mount module terhadap kernel ini — bukan bug driver. Manager wajib
  versionCode >= 35229 (Issue 0008); NoMount dinaikkan ke v2.2.0 (605).
- Kernel level sudah verified; retest **UI-level** 0.6X (Photo/Night/Video)
  di device masih menunggu — jalankan setelah reboot, dan konfirmasikan
  `dumpsys media.camera` tetap `cameras: 6`.

## Gotcha tetap

Mau bawa sensor lain dari branch lain? Copy **dir drivernya lengkap** +
tambah nama sensor ke `CUSTOM_KERNEL_IMGSENSOR` — dua-duanya, jangan cuma
satu; yang paling sering luput justru nama di defconfig.
