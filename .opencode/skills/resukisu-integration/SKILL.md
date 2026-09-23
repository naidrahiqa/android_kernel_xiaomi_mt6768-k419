---
name: resukisu-integration
description: ReSukiSU (KernelSU) integration untuk kernel 4.19 non-GKI. Manual hooks, KSU_VERSION pin, Kconfig setup, build verification. Trigger: kernelsu, ksu, resukisu, root, su, manual hook.
---

# ReSukiSU Integration — MT6768 Kernel 4.19

## Overview

- **Source**: https://github.com/ReSukiSU/ReSukiSU
- **Driver path**: `resukisu/kernel/`
- **Mode**: Manual hook (non-GKI 4.19)
- **Status**: Latest dari upstream

## Kconfig Setup

```kconfig
CONFIG_KSU=y
CONFIG_KSU_MANUAL_HOOK=y          # wajib untuk non-GKI 4.19
CONFIG_KSU_MULTI_MANAGER_SUPPORT=y
# CONFIG_KSU_SHELL_NOT_ROOT is not set
```

### Manual Hook Mode
4.19 non-GKI gak support TP-hook (syscall table). Wajib pakai manual hook:
- `fs/exec.c` → `ksu_handle_execveat`
- `fs/open.c` → `ksu_handle_faccessat`
- `fs/stat.c` → `ksu_handle_stat`, `ksu_handle_newfstat_ret`, `ksu_handle_fstat64_ret`
- `kernel/reboot.c` → `ksu_handle_sys_reboot`
- LSM hooks: `KSU_MANUAL_HOOK_AUTO_SETUID_HOOK`, `AUTO_INITRC_HOOK`
- Input hook: `AUTO_INPUT_HOOK` (otomatis, default y)

## Build Integration

### Symlink driver
```bash
ln -sf "$(realpath resukisu)" drivers/kernelsu
```

### Verify hooks exist
```bash
make -C resukisu/kernel/tools manual_hook_check.mk
```
Hook hilang = compile error.

### Compat layer
`resukisu/kernel/tools/kernel_compat.mk` — auto-detect 30+ API differences:
- SELinux structs
- hashtab signatures
- backport features
- vendor-specific detection

## KSU_VERSION Calculation

```
KSU_VERSION = 30000 + KSU_LOCAL_VERSION + 700
```

Example: `KSU_LOCAL_VERSION = 4414` → `KSU_VERSION = 35114`

## Manager APK

- `CONFIG_KSU_MULTI_MANAGER_SUPPORT=y` — support KernelSU/MKSU/RKSU/SukiSU-Ultra
- Rekomendasi: ReSukiSU manager (match KSU_VERSION)
- Download: t.me/ReSukiSU atau nightly.link

## Compat Layer (4.14 → 4.19)

File di `resukisu/kernel/compat/`:
- `kernel_compat.c` — Runtime compat: `flex_array`, hashtab 3-arg, `struct selinux_ss`
- `kernel_compat.h` — Header untuk compat layer
- `backport/hashtable.h` — Hashtable backport (4.14 3-arg vs 4.19 4-arg)

### API Differences (4.14 vs 4.19)
| API | 4.14 | 4.19 |
|-----|------|------|
| `iterate_dir` | `iterate` | `iterate_shared` |
| `getattr` | 3-arg | 4-arg |
| `notify_change` | 3-arg | 4-arg |
| `hashtab` | 3-arg | 4-arg |
| `selinux_state` | `ss->policydb` | different struct |

## Troubleshooting

### `__stack_chk_guard` undefined
Prebuilt `gf_spi_tee.o_shipped` depends on stack protector.
- **Fix**: Disable `CONFIG_CC_STACKPROTECTOR_STRONG` atau provide stubs

### Hook verification fails
Pastikan semua manual hook ada di kernel source:
```bash
grep -r "ksu_handle_execveat\|ksu_handle_faccessat\|ksu_handle_stat" fs/ kernel/
```

### SELinux denials
KernelSU butuh SELinux policy adjustments. Cek `resukisu/kernel/selinux/` untuk rules.

### Static symbol export check failure
`resukisu/tools/static_export_check.mk` gagal jika `CONFIG_KALLSYMS_ALL` tidak aktif dan simbol SELinux masih `static`.
- **Fix 1**: Hapus `static` dari `sel_handle_status_ops` dan `write_op` di `security/selinux/selinuxfs.c`
- **Fix 2**: Aktifkan `CONFIG_KALLSYMS_ALL=y` di `selene.config` agar runtime symbol lookup via kallsyms aktif
- **UAPI**: Pastikan `resukisu/uapi/` ter-bundle dan symlink `resukisu/include/uapi` -> `../uapi` valid
