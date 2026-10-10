---
id: 0008
slug: manager-version-mismatch
title: xxKSU manager refused the kernel with "manager needs update"
status: fixed
severity: medium
area: root
opened: 2026-10-10
updated: 2026-10-10
fix_commit: [685b5838ab8c]
verified_on: ""
tags: [ksu, folksu, xxksu, uapi, manager]
related: [0007]
---

## Gejala

Setelah flash kernel `685b5838ab8c`, manager di HP nampilin **"manager needs
update"** dan nggak bisa dipakai — padahal manager-nya **baru saja**
dipasang.

```
firstInstallTime = lastUpdateTime = 2026-10-10 13:40:58
```

## Akar masalah

Dua angka yang dilaporkan driver ke manager, dua-duanya lebih besar dari yang
manager kenal.

**1. UAPI version**

```
folksu/uapi/supercall.h:22   KERNEL_SU_UAPI_VERSION = 6
```

Comment di file itu sendiri yang menjelaskan arti tiap nomor:

```
// 5: add EVENT_SERVICES with a start/skip result
// 6: add dynamic-manager commands
```

Manager xxKSU yang dipakai (`me.weishu.kernelsu` v3.3.0-70) mengimplementasi
sampai uapi 5. Release notes-nya juga menyebut *"needs uapi v5"*.

**2. Version code**

```
folksu/Kbuild   KSU_LOCAL_VERSION := 2742
                KSU_VERSION := 30000 + 2742 = 32742

terpasang       me.weishu.kernelsu  v3.3.0-70  versionCode 32671
```

32742 > 32671, jadi manager menganggap dirinya usang.

Dua-duanya harus cocok; memperbaiki satu saja tidak cukup.

## Kenapa FolkSU manager sendiri juga ditolak

`LyraVoid/FolkSU@v0.1.0-beta1` punya versionCode **32776** — di atas
32742, jadi.versionCode-nya lolos. Tapi kalau tetap appellah beta1, manager
itu tetapUuversal parsing-nya bisa menolak.علىanyway, karena lo minta
pakai xxKSU, arahnya lain.

## Fix

Turunkan **angka yang dilaporkan**, bukan kemampuannya.

```c
// folksu/Kbuild
KSU_LOCAL_VERSION := 2742  →  2600      // 32742 → 32600

// folksu/uapi/supercall.h
KERNEL_SU_UAPI_VERSION = 6  →  5
```

Margin 71 kode di bawah 32671, jadi lolos baik kalau manager memakai `>`
maupun `>=`.

## Kenapa ini aman

Kedua konstanta itu **write-only** dari sisi driver:

```
folksu/supercall/dispatch.c:83   cmd.uapi_version = KERNEL_SU_UAPI_VERSION;
folksu/supercall/dispatch.c:65   cmd = { .version = KERNEL_SU_VERSION, ... }
```

Isinya cuma di-copy ke struct get-info lalu `copy_to_user()` ke manager.
`grep -rn 'uapi_version' folksu/*.c` mengembalikan **satu** hasil — assignment itu.
Tidak ada satupun tempat kernel membaca angka itu untuk memutuskan perilaku.
`CONFIG_KSU_TOOLKIT_SUPPORT` yang punya `ksuver_override` (runtime override)
tidak aktif di `selene_defconfig`, jadi tidak ada jalur lain.

Efeknya cuma satu: manager berhenti menganggap kernel ini terlalu baru.
Kode dynamic-manager uapi 6 tetap dikompilasi dan tetap ada di image — cuma
manager uapi 5 memang nggak pernah memanggilnya.

## Trade-off yang diterima

Ini **kompatibilitas**, bukan upgrade. Konsekuensinya:

- Driver masih melaporkan tag `v0.1.0-pre6`, padahal di urutan manager ia
  diposisikan seolah lebih lawas.
- Kalau nanti manager uapi 6 keluar, angka ini perlu dikembalikan ke `2742`/`6`.
  Change-nya satu baris dan sudah didokumentasikan di kedua file.

## Verification

- [x] build): `make` → `-- FolkSU version code: 32600`
- [ ] `dmesg | grep KernelSU` → `driver version: 32600`
- [ ] manager terbuka tanpa "manager needs update"
- [ ] `su` dari manager tetap berfungsi
- [ ] modul tetap bisa dipasang