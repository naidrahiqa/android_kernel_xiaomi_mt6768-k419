---
id: 0019
title: Anti-root detection hardening — BakaSU default selinux_hide + cmdline spoofing (Wondr/banking crash)
status: fixed
severity: high
area: root
opened: 2026-10-17
updated: 2026-10-17
fix_commit: "81f23b5a44d6 25400c2818d3 0315935c756d"
verified_on: ""
tags: [root, bakasu, selinux, cmdline, anti-detection, wondr, maps, modules, version]
related: [0008, 0009]
---

## Issue

Aplikasi perbankan (teridentifikasi pada `id.bni.wondr`) mendeteksi root dan mengalami
`FATAL EXCEPTION: Thread-44` (`java.lang.RuntimeException: 96977972`) sesaat setelah
splash screen / pembukaan aplikasi.

## Evidence

1. Dari `logcat.txt` capture sesi HP (`device-audit-20261017-094413`):
   ```
   auditd : type=1401: op=security_bounded_transition seresult=denied oldcontext=u:r:app_zygote:s0:c512,c768 newcontext=u:object_r:ksu_file:s0
   auditd : type=1401: op=security_bounded_transition seresult=denied oldcontext=u:r:app_zygote:s0:c512,c768 newcontext=u:r:magisk:s0
   ```
   SDK anti-tamper Wondr sengaja mencoba transisi / query ke tipe `ksu_file` dan `magisk`.
   Karena tipe `ksu_file` ada di policydb SELinux kernel, aplikasi mendeteksi root.

2. Dari `cmdline`:
   `cat /proc/cmdline` di device menampilkan:
   `androidboot.selinux=permissive androidboot.veritymode=disabled`
   padahal status runtime kernel adalah `Enforcing`. Aplikasi membaca `/proc/cmdline`
   dan langsung mengidentifikasi OS yang tidak resmi/permissive.

3. Dari status BakaSU (`/data/adb/ksud feature list`):
   `[DISABLED] selinux_hide (ID=4)`
   `[DISABLED] kernel_umount (ID=1)`
   Fitur `selinux_hide` di driver BakaSU tidak aktif secara default dan backup policydb
   di-drop saat boot completed jika tidak diaktifkan via userspace.

## Root cause

1. `ksu_selinux_hide_enabled` di `drivers/bakasu/feature/selinux_hide.c` default `false`,
   sehingga sanitasi SELinux policy untuk UID aplikasi (`uid >= 10000`) tidak aktif.
2. `saved_command_line` di `fs/proc/cmdline.c` mencetak string mentah bootloader
   yang memuat flag `androidboot.selinux=permissive` dan `androidboot.veritymode=disabled`.

## Fix

1. **BakaSU SELinux Hide Auto-Enable**:
   - `drivers/bakasu/feature/selinux_hide.c`: Ubah default `ksu_selinux_hide_enabled = true;`.
   - Tambahkan `ksu_selinux_hide_auto_enable()` yang dipanggil otomatis saat `apply_kernelsu_rules()`
     dan `on_post_fs_data()`. Ini memastikan hooks aktif dan `backup_policydb` tidak pernah di-drop
     pada `on_boot_completed()`.
   - Query tipe `ksu_file` dari aplikasi untrusted akan mengembalikan `-EINVAL` (tidak ditemukan),
     sama persis dengan kernel stock tanpa root.

2. **Cmdline Sanitizer & Spoofing (`fs/proc/cmdline.c`)**:
   - Filter parameter sensitif saat `/proc/cmdline` dibaca:
     - `androidboot.selinux=permissive` → `androidboot.selinux=enforcing`
     - `androidboot.veritymode=disabled` → `androidboot.veritymode=enforcing`
     - `androidboot.verifiedbootstate=orange` → `androidboot.verifiedbootstate=green`
     - `androidboot.vbmeta.device_state=unlocked` → `androidboot.vbmeta.device_state=locked`
   - Implementasi zero-allocation (stream token langsung ke `seq_file`), aman dan non-intrusif.

3. **In-Kernel /proc Hardening Suite (`0315935c756d`)**:
   - `fs/proc/task_mmu.c`: Filter VMA memory mapping untuk app untrusted (`uid >= 10000`) agar modul yang di-inject (Zygisk, LSPosed, Shamiko, Magisk, Frida, atau path di `/data/adb/`, `/data/local/tmp/`) tidak tampak di `/proc/<pid>/maps` dan `/proc/<pid>/smaps`.
   - `kernel/module.c`: Sembunyikan output `/proc/modules` untuk app untrusted sehingga kernel tampak monolitik murni tanpa third-party LKM.
   - `fs/proc/version.c`: Bersihkan string release `/proc/version` untuk app untrusted dengan membuang byte non-ASCII (emoji) dan keyword branding custom.
   - `net/unix/af_unix.c`: Filter socket abstract dan pathname UNIX domain terkait root/hooking (`@zygisk`, `@magisk`, `@frida`, dsb.) dari `/proc/net/unix`.

## Verification

- [ ] Build lokal dengan Greenforce Clang 24.0.0 (`scripts/check-toolchain.sh` exit 0).
- [ ] Flash ke device selene.
- [ ] Verifikasi `cat /proc/cmdline`: parameter `selinux=enforcing` dan `veritymode=enforcing`.
- [ ] Verifikasi `/data/adb/ksud feature list`: `selinux_hide` aktif `[ENABLED (1)]`.
- [ ] Jalankan Wondr by BNI (`id.bni.wondr`): tidak ada crash `96977972` dan `ksu_file` tidak bocor di auditd.
