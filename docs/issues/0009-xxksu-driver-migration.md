---
id: 0009
slug: xxksu-driver-migration
title: Migrasi driver root dari LyraVoid/FolkSU ke backslashxx/KernelSU
status: unverified
severity: high
area: root
opened: 2026-10-10
updated: 2026-10-10
fix_commit: []
verified_on: ""
tags: [ksu, xxksu, migration, driver, root]
related: [0008]
---

> **STATUS: BELUM DIVERIFIKASI DI HARDWARE.** Driver ini belum pernah boot
> di perangkat. Lihat "Yang belum diketahui" di bawah.

## Tujuan

Ganti driver root dari `folksu/` (upstream LyraVoid/FolkSU) ke
**backslashxx/KernelSU**, supaya satu-satunya root solution yang dipakai adalah
xxKSU.

## Yang dihapus

```
folksu/                    1.1 MB, dihapus
drivers/kernelsu           symlink -> ../folksu, diganti direktori nyata
```

Sudah tidak ada satu pun referral `folksu` di source, dan string `folksu`
nol di dalam Image.

## Yang ditambahkan

`drivers/kernelsu/` berisi `kernel/` dari backslashxx/KernelSU (branch `master`)
plus `uapi/` dari root repo tersebut.

Strukturnya ternyata sangat mirip — 15 direktori identik (`feature`, `hook`,
`include`, `infra`, `manager`, `policy`, `runtime`, `selinux`, `sulog`,
`supercall`, `Kconfig`, `Makefile`, `LICENSE`, `setup.sh`).

Bedanya:

| Hanya di FolkSU (lama) | Hanya di xxKSU (baru) |
|---|---|
| `compat/`, `core/`, `tools/`, `uapi/` | `downstream/`, `external/`, `kernel_compat.h`, `kernel_includes.h`, `ksu.c` |
| `Kbuild` | `Makefile` |

## Dua adaptasi yang wajib

### 1. Config di `selene_defconfig`

Lima config lama dibuang karena tidak ada di Kconfig xxKSU:

```
CONFIG_KSU_MULTI_MANAGER_SUPPORT=y
CONFIG_KSU_MANUAL_HOOK=y
CONFIG_KSU_MANUAL_HOOK_AUTO_SETUID_HOOK=y
CONFIG_KSU_MANUAL_HOOK_AUTO_INITRC_HOOK=y
CONFIG_KSU_MANUAL_HOOK_AUTO_INPUT_HOOK=y
```

Diganti dengan:

```
CONFIG_KSU_LSM_SECURITY_HOOKS=y
CONFIG_KSU_HEURISTIC_IN_TREE_BUILD=y
```

Manual hook **tidak hilang**, hanya cara ekspresinya berbeda — padanannya
`hook/lsm_hooks_manual.c`. Config `CONFIG_KSU=y` dan `CONFIG_KSU_HOSTSREDIRECT=y`
tetap dipakai.

### 2. `downstream/ksu_hostsredirect.h` — `static` jadi non-static

Ini blocker yang muncul saat link:

```
ld.lld: error: undefined symbol: ksu_hosts_file_redirect
>>> referenced by open.c
>>>               fs/open.o:(do_sys_open) in archive built-in.a
```

`fs/open.c:1117` mendeklarasikan `extern void ksu_hosts_file_redirect(...)`
lalu memanggilnya — hook yang ada di kernel kita sendiri, bukan dari driver.
Driver lama mengekspor fungsi itu sebagai simbol non-static. Versi upstream
xxKSU menyimpannya sebagai `static __always_inline`, sehingga tidak pernah
tereksekusi ke `ksu.o` sebagai simbol eksternal.

Perbaikannya: `static __always_inline` -> non-static. Edit pertama sempat
membuat brace dobel; itu sudah dibersihkan. Tidak ada perubahan
perilaku, hanya visibilitas simbol.

## Versi

`Makefile` xxKSU meng-hardcode:

```makefile
CFLAGS_ksu.o += -DKSU_VERSION=32670
KSU_PACKAGE_NAME := me.weishu.kernelsu
KSU_EXPECTED_SIZE := 0x033b
KSU_EXPECTED_HASH := c371061b19d8c7d7d6133c6a9bafe198fa944e50c1b31c9d8daa8d7f1fc2d2d6
```

32670 < 32671 (versionCode `me.weishu.kernelsu` v3.3.0-70), jadi manager
menerima kernel ini **tanpa** perlu lowering manual seperti yang dilakukan
di issue 0008.

`apk_sign.c` upstream hanya memuat satu manager — tidak ada
`EXPECTED_SIZE_XXKSU`. Jadi driver ini memang single-manager by design, dan
hanya mengenali APK xxKSU. Ini sesuai tujuan, tapi menutup jalan ke manager
lain.

## Yang berubah perilaku

**Multi-manager mati.** Sebelumnya driver mengenali 9 manager. Sekarang satu.

**`ksu_handle_faccessat` pindah sumber.** Sebelumnya dari
`hook/lsm_hook_magic.c`; sekarang dari `hook/syscall_table_hook_arm64.c`,
yang men-tamper `sys_call_table`. Ini subsystem berbeda dan belum diuji di
4.19.325 — bagian paling berisiko dari migrasi ini.

## Yang belum diketahui

- Apakah device boot dengan driver ini.
- Apakah `su` dari manager berfungsi (hook manual di 4.19 belum pernah jalan).
- Apakah `ksu_handle_faccessat` via `sys_call_table` tidak merusak syscall
  path di kernel 4.19.
- Apakah `CONFIG_KSU_HOSTSREDIRECT` masih benar-benar bekerja di driver baru.
- Apakah Play Integrity masih bisa dibaca tanpa framework hardware.

## Verification

- [x] clean rebuild dari nol (`rm -rf out`) — berhasil
- [x] 160 simbol `ksu_` di `vmlinux`
- [x] `ksu_hosts_file_redirect` dan `ksu_handle_faccessat` ter-export (T)
- [x] nol string `folksu` di Image
- [ ] boot di perangkat
- [ ] `dmesg | grep KernelSU` → versi 32670
- [ ] manager terbuka tanpa "manager needs update"
- [ ] `su` berfungsi
- [ ] `/system/etc/hosts` redirect aktif
- [ ] 24 jam pemakaian normal tanpa Oops