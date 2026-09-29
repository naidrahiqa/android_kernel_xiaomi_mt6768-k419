---
name: nomount
description: NoMount systemless path redirection untuk kernel 4.19. VFS hooks, keyring control, Magisk module integration. Trigger: nomount, systemless, path redirect, rootless.
---

# NoMount — MT6768 Kernel 4.19

## Overview

- **Source**: https://github.com/maxsteeel/nomount
- **Version**: v20 (`NOMOUNT_VERSION "20"` — upstream masih pakai versi ini)
- **Upstream base**: `6b1be18` (HEAD per 26 Sep 2026) — disinkronkan via
  commit `e8fbb599c68f` (sebelumnya base ~`7919faf`, masih ART-based)
- **Kernel module**: `fs/nomount.c` + `fs/nomount.h`
- **Userspace**: `tools/nomount/src/` (nm.c + nm.h; binary + Magisk module
  upstream `module/` **tidak di-ship** di tree ini)

> **Catatan layout:** repo `upstream/kernel-tree` punya layout alternatif
> "Meta NoMount" (`fs/nomount/` + source di `fs/Kconfig`/`fs/Makefile`) yang
> **sengaja TIDAK dipakai** di sini. Kita tetap wiring flat karena versi
> Meta membuang null-check (`d_backing_inode`, `i_private`) dan guard
> `TASK_SIZE` pada `get_user_pages_fast`. Jangan pernah `source
> "fs/nomount/Kconfig"` — duplikat simbol `NOMOUNT`.

## Architecture

NoMount melakukan virtual file injection + path redirection tanpa mount filesystem:
- Keyring-based control (userspace → kernel communication)
- Hashtable rules (`nomount_rules_ht`, RCU + bloom mask) untuk path matching
  (sejak upstream `146baeb`; dulu RBTree/ART)
- Dentry/inode/superblock operation hijacking; cleanup via `evict_inode`
- Isolated-app blocking (`nm uid block_isolated [on|off]`)

## Integration

### Add ke kernel
```bash
# Copy source
cp /path/to/nomount/kernel/src/nomount.c fs/
cp /path/to/nomount/kernel/src/nomount.h fs/

# Add Kconfig
config NOMOUNT
    bool "NoMount systemless path redirection"
    default y

# Add ke fs/Makefile
obj-$(CONFIG_NOMOUNT) += nomount.o
# upstream HEAD pakai `for (int i...)` — wajib gnu11 (seperti adios)
CFLAGS_nomount.o += -std=gnu11
```

### Guard lokal yang WAJIB di-re-apply tiap sync upstream
(bagian dari delta adaptasi 4.19 — upstream tidak punya ini):
1. `d_backing_inode()` NULL-check di `nm_listxattr`, `nm_getattr` (→ `-EIO`)
2. `d_backing_inode(info->r_path.dentry)` NULL-check di `nm_setattr` (→ `-EIO`)
3. `dir->i_private` NULL-check di `nm_dir_lookup` (→ `ERR_PTR(-ENOENT)`)
4. `target_inode` fallback di rule-init `kern_path()` (v_ino = hash)
5. `user_addr >= TASK_SIZE` sebelum `get_user_pages_fast` (payload keyring)

Cara sync berikutnya: copy `kernel/src/nomount.{c,h}` + `userspace/src/nm.{c,h}`
dari upstream, lalu re-apply 5 guard di atas + pastikan `CFLAGS_nomount.o` tetap
ada. Compile check: `make O=out ... fs/nomount.o`.

### Build userspace binary
```bash
aarch64-linux-gnu-gcc -static -O2 -nostdlib -nostartfiles \
  -Itools/nomount -o nm tools/nomount/src/nm.c
```

## 4.19 API Adaptation

NoMount v20 dari upstream mungkin butuh adaptasi untuk 4.19:

| API | 4.14 | 4.19 | Action |
|-----|------|------|--------|
| `iterate_dir` | `iterate` | `iterate_shared` | Change callback signature |
| `getattr` | 3-arg | 4-arg | Add `struct path *` param |
| `notify_change` | 3-arg | 4-arg | Add `struct iattr *` param |
| C standard | gnu89 | gnu89/gnu11 | Hoist `for(int i...)` declarations |

### `iterate_shared` change
```c
// 4.14
int nomount_iterate(struct file *file, struct dir_context *ctx);

// 4.19
int nomount_iterate(struct file *file, struct dir_context *ctx);
// Signature same, but lock semantics changed:
// 4.14: iterate takes read lock
// 4.19: iterate_shared takes shared read lock
```

### `getattr` change
```c
// 4.14
int nomount_getattr(struct dentry *dentry, struct kstat *stat);

// 4.19
int nomount_getattr(struct path *path, struct kstat *stat, u32 request_mask, unsigned int query_flags);
```

## Control Interface

Userspace communicates via keyring:
```c
// Add key
keyctl(KEYCTL_JOIN_SESSION_KEYRING, "nomount_control", 0, 0);

// Set rules
keyctl(KEYCTL_UPDATE, key_id, rule_data, rule_size);

// Activate
keyctl(KEYCTL_SETPERM, key_id, KEYCTL_VIEW);
```

## Magisk Module

`tools/nomount/module/` berisi Magisk module:
- `module.prop` — Module metadata
- `service.sh` — Boot service
- `customize.sh` — Install script
- `webroot/` — Web UI

## Troubleshooting

### Path redirection tidak work
- Cek `dmesg | grep nomount` untuk error messages
- Pastikan keyring key sudah di-create
- Verify rules di keyring

### Kernel panic
- Pastikan `nomount.c` di-compile dengan benar
- Cek `CONFIG_NOMOUNT=y` di defconfig
- Verify VFS hook placement

### SELinux denials
NoMount butuh SELinux policy untuk keyring access. Cek `dmesg | grep avc`.
