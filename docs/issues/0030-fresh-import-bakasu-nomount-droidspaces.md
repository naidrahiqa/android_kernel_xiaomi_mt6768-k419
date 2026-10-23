---
id: 0030
title: Re-import integrasi inti di baseline baru — BakaSU rev 4536, NoMount v2.2.0, DroidSpaces v6.6.0
status: fixed
severity: high
area: integration
opened: 2026-10-23
updated: 2026-10-23
fix_commit: ""
verified_on: ""
tags: [bakasu, nomount, droidspaces, integration, defconfig, manual-hook]
related: ["0008", "0015", "0029"]
---

## Issue

Baseline `EsTehAnget24.0` (mt6768-S + delta creativchic) adalah tree bersih:
tidak membawa driver root, systemless redirection, maupun dukungan
container. Tiga komponen inti di tree PawwwNunungggg lama harus di-port ulang
dari upstream terbaru, bukan dari tree lama:

1. **BakaSU** — upstream `Baka-SU/BakaSU@dac2d186` (rev-count 4536, 20 Okt
   2026). Delta kernel sejak pin lama (`d7260ca1`, rev 4529) hanya 1 commit
   (`522081c5` compat 32-bit userspace).
2. **NoMount** — upstream `maxsteeel/nomount` tag **v2.2.0**
   (`NOMOUNT_BASE_VERSION "22"`, 22 Okt 2026), naik dari v2.1.1.
3. **DroidSpaces** — requirements v6.6.0 dari `ravindu644/Droidspaces-OSS`
   (`Documentation/Kernel-Configuration.md`), lanjutan issue 0015.

## Evidence

- Tanpa hook anchor, build gagal total:
  `drivers/bakasu/tools/manual_hook_check.mk:70: *** You should integrate
  BakaSU in your kernel..  Stop.` — baseline tidak membawa `ksu_handle_*`
  anchor sama sekali.
- Upstream NoMount Meta layout membuang 5 guard 4.19 lokal (skill nomount):
  baseline v2.2.0 tanpa guard berisiko NULL deref `d_backing_inode`/`i_private`
  pada `nm_listxattr`/`nm_getattr`/`nm_setattr`/dir-lookup, dan akses
  `get_user_pages_fast` tanpa cek `TASK_SIZE`.

## Fix

**BakaSU (`drivers/bakasu/`, 119 file):**
- rsync `kernel/` + `uapi/` upstream `dac2d186`; Kbuild dipatch statis:
  `BAKASU_REV_COUNT := 4536`, **`KSU_VERSION := 35229` (sengaja ditahan** —
  formula memberi 35236 di rev 4536, tapi manager APK terpasang baru ≥ 35229;
  naikkan hanya bersama manager baru, lihat issue 0008), tag `v4.2.0-rc3`,
  sha `dac2d186`; blok guard `.git` upstream dibuang (in-tree copy, bukan
  submodule).
- `feature/hostsredirect.{c,h}` di-restore dari branch lama (fitur lokal,
  tidak ada di upstream) + blok `kernelsu-objs` & Kconfig
  `CONFIG_KSU_HOSTSREDIRECT` (default y).
- Wiring: `drivers/Kconfig` `source "drivers/bakasu/Kconfig"`,
  `drivers/Makefile` `obj-$(CONFIG_KSU) += bakasu/`.

**Manual hook anchors (syarat `manual_hook_check.mk`, walau `AUTO_*=y`):**
- `fs/open.c`: `ksu_handle_faccessat` di `do_faccessat`.
- `fs/stat.c`: `ksu_handle_stat` di `newfstatat` & `fstatat64`,
  `ksu_handle_newfstat_ret` di `newfstat`, `ksu_handle_fstat64_ret` di
  `fstat64`.
- `fs/exec.c`: `ksu_handle_execveat` di `do_execve` & `do_execveat`.
- `kernel/reboot.c`: `ksu_handle_sys_reboot` di `SYSCALL_DEFINE4(reboot)`.
- `CONFIG_KSU_MANUAL_HOOK=y` (`KSU_TRACEPOINT_HOOK` dimatikan); `AUTO_*`
  dibiarkan `=y` (LSM path, kernel 4.19 < 6.8 aman).

**NoMount (`fs/nomount.{c,h}` v2.2.0):**
- 5 guard 4.19 di-re-apply manual (6/7 hunk otomatis dari delta v2.1.1→legacy,
  hunk rule-init di-apply ulang tangan karena upstream v2.2.0 memindahkan
  blok ke fungsi `nm_resolve_anchor_locked`).
- Wiring: `fs/Kconfig` `config NOMOUNT` (select KEYS, default y),
  `fs/Makefile` `obj-$(CONFIG_NOMOUNT) += nomount.o` +
  `CFLAGS_nomount.o += -std=gnu11 -Wno-declaration-after-statement`
  (upstream pakai `for (int i…)` — tree kita `-std=gnu89`).
- Userspace `nm.{c,h}` v2.2.0 → `tools/nomount/src/`.

**DroidSpaces (`selene_defconfig`, refs 0015):**
- Aktif: SYSVIPC, POSIX_MQUEUE (→ IPC_NS ikut), USER_NS, CGROUP_DEVICE,
  CGROUP_NET_PRIO/CLASSID, CGROUP_PIDS, CFS_BANDWIDTH, DEVTMPFS,
  TMPFS_POSIX_ACL/XATTR, FW_LOADER_USER_HELPER, NF_TABLES, IP6_NF_NAT,
  IP6_NF_TARGET_MASQUERADE, MACVLAN, NETFILTER_XT_MATCH_ADDRTYPE,
  NF_CT_NETLINK.
- Di-skip (simbol tidak ada di tree 4.19 ini): `FW_LOADER_COMPRESS`,
  `NETFILTER_XT_TARGET_MASQUERADE` (ganti nama), `NF_CONNTRACK_NETLINK`
  (jadi `NF_CT_NETLINK`), `NF_CONNTRACK_IPV4` (merged), `IP_SET` (blok
  firewall opsional — tidak dipakai), `ANDROID_PARANOID_NETWORK` (tidak ada
  = tidak ada pembatasan, target `=n` tercapai).
- Patch 02 (cgroup prefix) **tidak dibutuhkan**: `CONFIG_BLK_CGROUP=y` sudah
  di baseline; patch 01 (xt_qtaguid) tidak ada simbolnya (no-op).

## Verifikasi

- `savedefconfig` → apply ke direktori fresh → savedefconfig ulang:
  **byte-identik** (deterministik).
- Build lokal Greenforce (Cirrus clang 24.0.0): `MAKE_EXIT=0`,
  `Image.gz-dtb` 12.415.867 byte (baseline 12.223.225; +193 KB dari tiga
  komponen).
- `manual_hook_check.mk` lolos semua anchor.

## Catatan / gotcha yang tidak ikut terbawa

- `KSU_VERSION` 35229 vs formula 35236: **disengaja**, baca issue 0008
  sebelum naikkan.
- Regenerasi defconfig WAJIB lewat `merge_config.sh` manual (rule kbuild
  `%.config` tidak melihat `vendor/`) — issue 0029.
- NoMount v2.2.0 memindahkan blok rule-init ke fungsi terpisah — guard
  lama tidak bisa di-patch otomatis penuh, satu hunk manual.
