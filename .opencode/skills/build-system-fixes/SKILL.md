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
Clang IAS gak support `.pad #SYMBOLIC_CONSTANT` di ARM mode.
- **Fix**: Disable IAS untuk vdso32 assembly:
```makefile
# arch/arm64/kernel/vdso32/Makefile
ifeq ($(CONFIG_CC_IS_CLANG), y)
VDSO_AFLAGS += -fno-integrated-as
endif
```

### `mov` immediate syntax
`mov r7, #__NR_compat_sigreturn` — Clang IAS gak support `:` syntax.
- **Fix**: Sama dengan `.pad` fix — disable IAS untuk vdso32

### `sigreturn.S` undefined `__NR_compat_*`
vdso32 `sigreturn.S` pakai `__NR_compat_sigreturn` dan `__NR_compat_rt_sigreturn` dari `<asm/unistd.h>`, tapi preprocessor tidak expand saat compile dengan Clang IAS.
- **Fix**: Tambah fallback defines di `sigreturn.S`:
```asm
#ifndef __NR_compat_sigreturn
#define __NR_compat_sigreturn 119
#endif
#ifndef __NR_compat_rt_sigreturn
#define __NR_compat_rt_sigreturn 173
#endif
```

## Anti-Patterns (JANGAN LAKUKAN)

1. **Jangan enable `CONFIG_LTO_CLANG`** tanpa pastikan LLVM version match
2. **Jangan pakai `-no-integrated-as`** di top-level Makefile — hanya per-file
3. **Jangan pakai `HOSTCC=clang`** — host tools butuh real GCC
4. **Jangan apply GKI 5.10+ patches** tanpa cek API compatibility
