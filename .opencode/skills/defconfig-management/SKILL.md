---
name: defconfig-management
description: Defconfig management untuk MT6768 kernel. Config dependency chains, known gotchas, debug workflow. Trigger: defconfig, config, menuconfig, kernel config.
---

# Defconfig Management — MT6768 Kernel 4.19

## Config Files

| File | Purpose |
|------|---------|
| `arch/arm64/configs/selene_defconfig` | Unified device defconfig for Xiaomi Selene |
| `arch/arm64/configs/vendor/mt6768_defconfig` | Base MTK SoC defconfig |
| `arch/arm64/configs/vendor/selene.config` | Device overlay (legacy merged format) |
| `arch/arm64/configs/vendor/lancelot.config` | Redmi 9 Power overlay |
| `arch/arm64/configs/vendor/merlin.config` | Redmi 9T overlay |

## Build Workflow

```bash
# 1. Generate config from unified defconfig
make O=out ARCH=arm64 selene_defconfig

# 2. Edit (optional)
make O=out ARCH=arm64 menuconfig

# 3. Save new defconfig
make O=out ARCH=arm64 savedefconfig
cp out/defconfig arch/arm64/configs/selene_defconfig
```

## Critical Configs (wajib ada)

| Config | Value | Reason |
|--------|-------|--------|
| `CONFIG_ARCH_MTK_PROJECT` | `"selene"` | Device identification |
| `CONFIG_TOUCHSCREEN_FTS_XIAOMI` | `y` | FocalTech touch |
| `CONFIG_FPC_FINGERPRINT` | `y` | FPC fingerprint |
| `CONFIG_GOODIX_FINGERPRINT` | `y` | Goodix fingerprint |
| `CONFIG_SND_SOC_AW87XXX` | `y` | Audio amplifier |
| `CONFIG_BATTERY_BQ2589X` | `y` | Charger |
| `CONFIG_TRACEPOINTS` | `y` | FPSGO tracepoints |
| `CONFIG_KSU` | `y` | KernelSU |
| `CONFIG_KSU_MANUAL_HOOK` | `y` | Manual hook (non-GKI) |

## Security Configs — JANGAN ENABLE

| Config | Masalah |
|--------|---------|
| `BUG_ON_DATA_CORRUPTION` | Bootloop dari benign list corruption |
| `INIT_ON_ALLOC_DEFAULT_ON` | Bootloop dari uninitialized memory |
| `SHADOW_CALL_STACK` | Kernel panic ~2 jam (TrustZone clobber x18) |
| `SLAB_FREELIST_HARDENED` | Kernel panic ~81 menit (use-after-free CCCI) |
| `HARDEN_BRANCH_PREDICTOR` | 1-5% overhead (deferred) |

### Safe configs (boleh enable)
- `STRICT_KERNEL_RWX`
- `FORTIFY_SOURCE`
- `HARDENED_USERCOPY`
- `SECURITY_PERF_EVENTS_RESTRICT`
- `VMAP_STACK`
- `SECCOMP`

## Config Gotchas

### Fingerprint prebuilt dependency
- `GOODIX_FINGERPRINT` prebuilt `gf_spi_tee.o_shipped` depends on `__stack_chk_guard`
- **Fix**: Disable atau provide stubs untuk `__stack_chk_guard`

### FPSGO tracepoints
- `CONFIG_TRACEPOINTS=y` wajib untuk FPSGO GPU driver
- Tanpa ini: 60+ undefined reference errors

### LTO mismatch
- `CONFIG_LTO_CLANG=y` — LLVM version must match between compiler dan linker
- **Fix**: Disable LTO atau gunakan LLVM yang match

### /proc/config.gz stale
- `kernel/Makefile` line 125 — hardcoded `stock_defconfig`
- **Fix**: Ganti ke `$(KCONFIG_CONFIG)` untuk accurate config dump

## Debug Workflow

```bash
# 1. Check current config
grep -E "CONFIG_KSU|CONFIG_NOMOUNT|CONFIG_FINGERPRINT" out/.config

# 2. Check enabled configs
grep "=y" out/.config | wc -l

# 3. Check missing configs
diff <(grep "=y" arch/arm64/configs/vendor/mt6768_defconfig | sort) \
     <(grep "=y" out/.config | sort) | head -20

# 4. Check config dependencies
make O=out ARCH=arm64 listnewconfig
```

## Dependency Chains

```
CONFIG_KSU
  └── CONFIG_KSU_MANUAL_HOOK (non-GKI)
       └── Manual hook patches di fs/exec.c, fs/open.c, fs/stat.c

CONFIG_TOUCHSCREEN_FTS_XIAOMI
  └── CONFIG_TOUCHSCREEN_COMMON
       └── Sysfs interface ke userspace

CONFIG_GOODIX_FINGERPRINT
  └── CONFIG_MTK_FINGERPRINT_SUPPORT
       └── SPI bus config di DTS

CONFIG_BATTERY_BQ2589X
  └── CONFIG_CHARGER_BQ2589X
       └── I2C bus config di DTS
```
