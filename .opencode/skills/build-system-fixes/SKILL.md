---
name: build-system-fixes
description: Build error fixes untuk kernel 4.19 + Clang. Clang IAS, stpcpy, LTO, ZSTD, UAPI headers, assembly errors, vendor driver warnings. Trigger: build error, compile error, link error, clang error, undefined symbol.
---

# Build System Fixes — MT6768 Kernel 4.19

## Clang IAS Issues

### `.weak` → `.globl` binding
Clang IAS reject changing symbol binding from `STB_WEAK` ke `STB_GLOBAL`.
```
arch/arm64/lib/memcpy.S:   .weak memcpy   → .globl memcpy
arch/arm64/lib/memmove.S:  .weak memmove  → .globl memmove
arch/arm64/lib/memset.S:   .weak memset   → .globl memset
```

### `stpcpy` undefined
Clang 23+ optimize `strcpy` + pointer arithmetic jadi `stpcpy()`. Kernel 4.19 gak provide.
- **Fix**: Tambah generic `stpcpy` di `lib/string.c` + declaration di `include/linux/string.h`
- **Check**: `grep -r "stpcpy" lib/ include/` untuk verify

### Named macro args di assembly
VDSO `gettimeofday.S` — Clang IAS gak support named args:
```asm
# WRONG
clock_gettime_return, shift=1
# BENAR
clock_gettime_return 1
```

### 68-bit literal out of range
`arch/arm64/crypto/aes-modes.S` — `0x30000000200000001` exceeds Clang IAS range.
- **Fix**: Explicit lane construction dengan `mov/dup` instructions

## LTO & Linker Issues

### LTO bitcode mismatch
`CONFIG_LTO_CLANG=y` — LLVM 23 bitcode gagal di-link oleh LLVM 16 system linker.
- **Fix**: Disable `CONFIG_LTO_CLANG` atau pastikan compiler dan linker LLVM version match
- **Alternative**: Gunakan `LD=ld.lld` dari same LLVM installation

### `GCC_TOOLCHAIN_DIR` detection
Top-level Makefile — `$(CROSS_COMPILE)elfedit` mungkin gak exist.
- **Fix**: Pakai `$(CROSS_COMPILE)as` sebagai detection binary

## ZSTD Issues

### `ZSTD_STATIC_ASSERT` zero-division
`lib/zstd/zstd_internal.h` — enum pembagian nol ditolak Clang 23:
```c
// WRONG (Clang 23 rejects)
enum { ZSTD_STATIC_ASSERT CONDITION = 1 / (int)(!!(CONDITION)) - 1 };

// BENAR
_Static_assert((CONDITION), "ZSTD_STATIC_ASSERT");
```

## Clang CFI (Control Flow Integrity) Fixes

Forward-edge CFI checks indirect function pointer signatures at runtime. Signature mismatches cause instant kernel panics (CFI trap).

### Backlight callback signature mismatch
`drivers/misc/mediatek/leds/mt6768/ktd3136_bl.c`:
- Function pointer callback expected `(int, int)` signature: `int (*set_level)(int level, int div)`.
- Target function defined as `int (*set_level)(int level)`.
- **Fix**: Samakan signature parameter ke `(int brightness, int div)` atau `(int brightness)` di seluruh caller dan callee.

### RDMA ioctl callback mismatch
`drivers/misc/mediatek/video/mt6768/dispsys/ddp_rdma.c`:
- `rdma_ioctl` menggunakan tipe enum lokal/inkomplit yang tidak cocok dengan struct dispatch `.ioctl`.
- **Fix**: Gunakan tipe enum global `DDP_IOCTL_NAME` agar signature function pointer match saat didaftarkan ke tabel dispatch.

## Clone3 & Modern Bionic Compatibility

Modern Android Bionic libc menggunakan `clone3()` system call untuk thread creation.
1. **`copy_thread_tls` ARM64:** Diperlukan implementasi `copy_thread_tls` di `arch/arm64/kernel/process.c` karena TLS diteruskan melalui struct, bukan register `x3`.
2. **Stack Argument Validation:** Validasi arah pertumbuhan stack (`stack_size` dan `stack`) sebelum memanggil `_do_fork()`.
3. **`copy_struct_from_user`:** Menggunakan helper `copy_struct_from_user()` untuk menangani argumen `struct clone_args` yang extensible secara aman dari userspace.

## Early Boot Stability & Panic Guards

Sebelum driver probe atau `timer_probe()` selesai, timer dan scheduler belum sepenuhnya aktif.

### 1. MTCMOS Infinite Spin (CCF Clock)
`drivers/clk/mediatek/clk-mt6768-pg.c`:
- 73 loop `while ((spm_read(...) & MASK) != MASK) ram_console_update();` berjalan sebelum `timer_probe()`.
- Jika register ACK SPM tidak merespons, CPU terjebak dalam loop tanpa henti (silent boot hang tanpa output serial).
- **Fix**: Ganti ke makro bounded `spm_wait_ack()` dengan limit `SPM_ACK_MAX_SPINS = 1000000u`. Jika timeout tercapai, log error dan lanjutkan proses boot.

### 2. SSPM Reserved Memory Missing
`drivers/misc/mediatek/base/power/upower_v2/mtk_unified_power.c`:
- Jika reserved memory SSPM tidak dialokasikan, `upower_data_virt_addr` bernilai `0`. Loop `memset` menulis ke pointer `0` (NULL dereference panic).
- **Fix**: Guard `if (!upower_data_virt_addr || !upower_data_size) return 0;`.

### 3. Early CMDQ Slot Allocation
`drivers/misc/mediatek/cmdq/v3/cmdq_helper_ext.c`:
- Display probe (`disp_probe_1`) dapat memanggil `mdp_pool_alloc_impl()` sebelum `mdp_rb_pool` dibuat via `dma_pool_create()`.
- **Fix**: Check `if (!pool) return NULL;` agar caller fallback ke standard DMA allocation.

### 4. PMIC Interrupt Initialization Order
`drivers/misc/mediatek/pmic/mt6358/v1/pmic_irq.c`:
- Jika subsistem lain (misal accdet) memanggil `pmic_enable_interrupt()` sebelum probe PMIC selesai, `pmic_dev` masih NULL.
- **Fix**: Check `if (!pmic_dev) return;`.

### 5. SCP IPI Deadlock
`drivers/misc/mediatek/scp/cm4/v01/scp_ipi.c`:
- `scp_ipi_send()` memegang `scp_ipi_mutex` sembari menunggu ACK register SCP. Jika SCP firmware macet, loop berputar selamanya sambil menahan mutex (deadlock seluruh sistem).
- **Fix**: Tambahkan `SCP_IPI_WAIT_MAX_SPINS`, panggil `cpu_relax()`, dan lepaskan mutex `mutex_unlock(&scp_ipi_mutex[scp_id])` lalu return `SCP_IPI_BUSY` saat timeout.

### 6. SPI Slave / Display Bridge
`drivers/misc/mediatek/spi_slave_drv/spi_slave.c` & `ddp_disp_bdg.c`:
- Jika chip bridge SPI tidak terdeteksi, `slv_data.spi` adalah NULL. Memanggil `spi_sync(NULL)` memicu panic.
- **Fix**: Guard `if (!slv_data.spi) return -ENODEV;` dan cek return value di `bdg_is_bdg_connected()`.

### 7. Backlight Class Error & Sysfs Crash
`drivers/misc/mediatek/leds/mt6768/ktd3136_bl.c`:
- `ktd3137_device_create()` mengabaikan error class. Jika gagal, `ktd3137_probe()` mendereference pointer error di `sysfs_create_group()`.
- **Fix**: Return `ERR_CAST(ktd3137_class)` dan hanya buat sysfs group jika `!IS_ERR(ktd3137_dev)`.

## GCC Compatibility

### GCC 13 `-Werror` promotions
Vendor driver warnings di-promote ke error di GCC 13.
- **Fix**: Tambah `-Wno-error` di `scripts/Makefile.lib` `orig_c_flags`
- **Impact**: Tanpa ini, `CONFIG_CC_STACKPROTECTOR_STRONG` dan `CONFIG_BLK_INLINE_ENCRYPTION` gagal

## UAPI Headers

### Missing netfilter headers
Buat manual di `include/uapi/linux/netfilter/`:
- `xt_connmark.h`
- `xt_mark.h`

### `xt_hl.c` deleted
Diperlukan karena `IP_NF_MATCH_TTL` select `NETFILTER_XT_MATCH_HL`.
- **Fix**: Restore dari parent commit
- **Windows caveat**: `xt_hl.c` vs `xt_HL.c` collision di NTFS (case-insensitive)

## FPSGO Tracepoints

### 60+ undefined reference errors
FPSGO GPU driver butuh tracepoints:
```
__tracepoint_ipi_entry
__tracepoint_sched_switch
tracepoint_probe_register
```
- **Fix**: `CONFIG_TRACEPOINTS=y` di defconfig

## vDSO32 Issues (kernel 4.19)

### `__NR_compat_*` undeclared
`compat_gettimeofday.h` pakai `__NR_compat_*` dari ARM64 headers, tapi vdso32 compile pakai `--target=arm-linux-gnueabi`.
- **Fix**: Tambah fallback defines di `compat_gettimeofday.h`:
```c
#ifndef __NR_compat_gettimeofday
#define __NR_compat_gettimeofday    78
#endif
#ifndef __NR_compat_clock_gettime
#define __NR_compat_clock_gettime   263
#endif
#ifndef __NR_compat_clock_getres
#define __NR_compat_clock_getres    264
#endif
```

### `.pad` symbolic constants
Clang IAS gak support `.pad #SYMBOLIC_CONSTANT` di ARM mode. `-fno-integrated-as` juga tidak dihargai Clang.
- **Fix**: Force GAS untuk assembly files di vdso32 Makefile:
```makefile
# arch/arm64/kernel/vdso32/Makefile
ifeq ($(CONFIG_CC_IS_CLANG), y)
CC_COMPAT ?= $(CC)
CC_COMPAT += --target=arm-linux-gnueabi
CC_COMPAT_AS ?= $(CROSS_COMPILE_COMPAT)gcc
else
CC_COMPAT ?= $(CROSS_COMPILE_COMPAT)gcc
CC_COMPAT_AS ?= $(CC_COMPAT)
endif

# Ganti cmd_vdsoas:
cmd_vdsoas = $(CC_COMPAT_AS) -Wp,-MD,$(depfile) $(VDSO_AFLAGS) -c -o $@ $<
```

### `mov` immediate syntax
`mov r7, #__NR_compat_sigreturn` — Clang IAS gak support `:` syntax.
- **Fix**: Sama dengan `.pad` fix — force GAS untuk vdso32 assembly

### `sigreturn.S` undefined `__NR_compat_*`
vdso32 `sigreturn.S` pakai `__NR_compat_sigreturn` dan `__NR_compat_rt_sigreturn` dari `<asm/unistd.h>`, tapi preprocessor tidak expand saat compile dengan Clang IAS.
- **Fix**: Ganti `<asm/unistd.h>` ke `<asm/unistd32.h>` dan pakai `__NR_sigreturn`/`__NR_rt_sigreturn`:
```asm
#include <asm/unistd32.h>
mov r7, #__NR_sigreturn
mov r7, #__NR_rt_sigreturn
```

## Anti-Patterns (JANGAN LAKUKAN)

1. **Jangan enable `CONFIG_LTO_CLANG`** tanpa pastikan LLVM version match
2. **Jangan pakai `-no-integrated-as`** di top-level Makefile — hanya per-file
3. **Jangan pakai `HOSTCC=clang`** — host tools butuh real GCC
4. **Jangan apply GKI 5.10+ patches** tanpa cek API compatibility

## Charger Kconfig Gotcha (BRICK RISK — 19 Sep 2026)

### The Silent Failure
```kconfig
config MTK_CHARGER
    bool "MediaTek Charging Driver"
    depends on MEDIATEK_SOLUTION    # ← ga ada di Kconfig manapun
    default n
```
`MEDIATEK_SOLUTION` ga define → config SILENTLY DROPPED → charger driver ga compile.

### The Dangerous Fix
```kconfig
# Remove the dependency
config MTK_CHARGER
    bool "MediaTek Charging Driver"
    # depends on MEDIATEK_SOLUTION  ← REMOVED
    default n
```
Sekarang charger driver ENABLED → baca DTS values →如果值 salah → BRICK.

### Lesson
```
Kconfig fix benar, tapi TANPA hardware validation = brick.
Charger driver yang disabled ada SEBAB (ga stabil).
Enable tanpa verify = hardware damage.
```

### Safe Pattern
```bash
# 1. Fix Kconfig (remove bad dependency) — OK
# 2. Verify DTS values match hardware ratings — CRITICAL
# 3. Flash ke hardware — CRITICAL
# 4. Monitor 24 jam — CRITICAL
# 5. Kalau aman → commit
```
