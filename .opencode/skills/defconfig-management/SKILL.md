---
name: defconfig-management
description: Defconfig management untuk MT6768 kernel. Config dependency chains, known gotchas, debug workflow. Trigger: defconfig, config, menuconfig, kernel config.
---

# Defconfig Management — MT6768 Kernel 4.19

## Config Files

| File | Purpose |
|------|---------|
| `arch/arm64/configs/selene_defconfig` | Unified device defconfig for Xiaomi Selene (Redmi 10 / Redmi 10 2022) |
| `arch/arm64/configs/vendor/mt6768_defconfig` | Base MTK SoC defconfig |
| `arch/arm64/configs/vendor/selene.config` | Device overlay for Selene (legacy merged format) |
| `arch/arm64/configs/vendor/lancelot.config` | Redmi 9 overlay |
| `arch/arm64/configs/vendor/merlin.config` | Redmi Note 9 overlay |

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
| `CONFIG_COMPAT` | `y` | 32-bit EL0 userspace (apps & proprietary 32-bit vendor HALs) |
| `CONFIG_TOUCHSCREEN_FTS_XIAOMI` | `y` | FocalTech touch |
| `CONFIG_TOUCHSCREEN_COMMON` | `y` | Exposing double-tap sysfs node (`/sys/touchpanel`) |
| `CONFIG_FPC_FINGERPRINT` | `y` | FPC fingerprint |
| `CONFIG_GOODIX_FINGERPRINT` | `y` | Goodix fingerprint |
| `CONFIG_SND_SOC_AW87XXX` | `y` | Audio amplifier |
| `CONFIG_BATTERY_BQ2589X` | `y` | Charger |
| `CONFIG_TRACEPOINTS` | `y` | FPSGO tracepoints |
| `CONFIG_KSU` | `y` | KernelSU |
| `CONFIG_KSU_MANUAL_HOOK` | `y` | Manual hook (non-GKI) |
| `CONFIG_KSU_MULTI_MANAGER_SUPPORT` | `y` | Multi-manager support (MKSU, RKSU, ReSukiSU) |

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

CONFIG_MTK_CHARGER
  ├── depends on MTK_CHARGER (self)
  ├── CHARGER_BQ2589X_CHARGER
  ├── CHARGER_RT9458
  ├── CHARGER_RT9466
  └── CHARGER_RT9471
```

## CRITICAL: Charger Config Gotchas (BRICK RISK)

### The Hidden Dependency Trap (19 Sep 2026)
```
CONFIG_MTK_CHARGER depends on MEDIATEK_SOLUTION
→ MEDIATEK_SOLUTION ga ada di Kconfig manapun
→ Config SILENTLY DROPPED saat make defconfig
→ Charger driver ga compile → DTS values ga dibaca
→ Phone AMAN (charger handled by LK bootloader)

FIX: Remove depends on MEDIATEK_SOLUTION
→ Charger driver ENABLED + compiles
→ Baca DTS values →如果值 salah → BRICK
```

### Safe Charger Configs
| Config | Status | Catatan |
|---|---|---|
| `CONFIG_MTK_CHARGER` | ✅ enabled | Legitimate fix — driver seharusnya jalan |
| `CONFIG_CHARGER_BQ2589X_CHARGER` | ✅ enabled | Charger IC selene |
| `CONFIG_SMB1351_USB_CHARGER` | ✅ enabled | Charger IC alt |

### Dangerous Charger Configs (JANGAN UBAH)
| Config | Masalah |
|---|---|
| `CONFIG_BATTERY_OCV_CAPACITY` | Salah capacity reading |
| Custom charger algo tanpa HW test | Overcharge risk |

### Charger DTS Values — Hardware-Rated
```
battery_cv = 4350000           → JANGAN UBAH (4.35V rated)
enable_sw_jeita = disabled     → JANGAN ENABLE tanpa HW test
hvdcp_charger_current = N/A    → JANGAN TAMBAH tanpa validasi
pd_vbus_upper_bound = 5000000  → JANGAN UBAH ke 9000000
temp_t4_threshold = 50         → JANGAN UBAH ke 60
non_std_ac_charger_current = 500000 → JANGAN UBAH ke 1000000
```

### How to Safely Test Charger Changes
```bash
# 1. Build with changes
# 2. Flash to hardware
# 3. Monitor charging for 24 hours
# 4. Check battery temp: cat /sys/class/power_supply/battery/temp
# 5. Check charger current: cat /sys/class/power_supply/battery/current_now
# 6. If stable → commit. If not → revert immediately
```
