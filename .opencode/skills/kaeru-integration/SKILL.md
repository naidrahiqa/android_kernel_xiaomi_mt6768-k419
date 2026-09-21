---
name: kaeru-integration
description: Kaeru bootloader spoofer integration untuk kernel 4.19. Lock state spoofing, cert bypass, DRAM communication, fastboot commands. Trigger: kaeru, bootloader, lk, lock state, cert bypass, spoof, fastboot.
---

# Kaeru Integration Skill — MT6768 Kernel 4.19

## Overview

Kaeru adalah custom LK (Little Kernel) bootloader untuk MediaTek MT6768 yang memungkinkan:
- **Lock state spoofing** — Device melapor "locked" padahal unlocked
- **Certificate bypass** — Skip AVB signature verification
- **Custom fastboot commands** — `oem bldr_spoof` untuk toggle spoofing
- **DRAM communication** — Flags ditulis ke DRAM untuk dibaca kernel

## Architecture

```
┌──────────────┐    ┌──────────────┐    ┌──────────────┐
│  Kaeru LK    │───▶│  DRAM 0x4C5  │───▶│  Kernel      │
│  (bootloader)│    │  000000      │    │  kaeru_comm  │
└──────────────┘    └──────────────┘    └──────────────┘
        │ write_kaeru_comm()    │ read via ioremap
        │ board_late_init()     │
        ▼                       ▼
┌──────────────┐    ┌──────────────┐
│  Patches:    │    │  Exports:    │
│  - cert bypass│    │  is_active() │
│  - lock spoof│    │  is_overclock│
│  - AVB bypass│    │  is_spoofing │
│  - fastboot  │    │  is_recovery │
└──────────────┘    │  is_download │
                    └──────────────┘
```

## Key Files

### Kernel Side
- `drivers/misc/kaeru_comm.c` — DRAM communication module
- `include/linux/kaeru_comm.h` — Header with inline fallbacks
- `drivers/misc/Kconfig` — `CONFIG_KAERU_COMM` + `CONFIG_KAERU_COMM_BASE`
- `arch/arm64/configs/selene_defconfig` — `CONFIG_KAERU_COMM=y`

### Kaeru LK Side
- `/home/naidra/Projects/kaeru-src/board/xiaomi/board-selene.c` — Board file
- `/home/naidra/Projects/kaeru-src/configs/xiaomi/selene_defconfig` — Config
- `/home/naidra/Projects/kaeru/selene-kaeru.bin` — Pre-built binary

### Packaging
- `scripts/anykernel.sh` — Flash LK via `dd` in recovery
- `scripts/build-kaeru.sh` — Build/package script
- `kaeru/selene-kaeru.bin` — Binary in repo for CI bundling
- `.github/workflows/build.yml` — CI bundles LK in ZIP

## DRAM Communication Protocol

### Structure (64 bytes at 0x4C500000)
```c
struct kaeru_comm {
    u32 magic;      /* 0x4B414552 = "KAER" */
    u32 version;    /* 0x00020000 = v2.0.0 */
    u32 flags;      /* Feature flags */
    u32 reserved[13];
};
```

### Flags
| Flag | Bit | Value |
|------|-----|-------|
| `KAERU_FLAG_OVERCLOCK` | 0 | CPU/GPU OC mode |
| `KAERU_FLAG_SPOOF_LOCK` | 1 | Lock state spoofing active |
| `KAERU_FLAG_RECOVERY` | 2 | Recovery boot requested |
| `KAERU_FLAG_DOWNLOAD` | 3 | Download mode requested |

### Flow
1. Kaeru LK `board_late_init()` calls `write_kaeru_comm()`
2. Writes magic + version + flags to DRAM at `0x4C500000`
3. Kernel `kaeru_early_init()` via `subsys_initcall`
4. Reads DRAM via `ioremap`, validates magic
5. Sets `kaeru_active = true`, exports functions

## Build Commands

### Enable in defconfig
```bash
# Already enabled in selene_defconfig
CONFIG_KAERU_COMM=y
CONFIG_KAERU_COMM_BASE=0x4C500000
```

### Build Kaeru LK from source
```bash
cd /home/naidra/Projects/kaeru-src
./build.sh selene lk_stock.img
# Output: selene-kaeru.bin
```

### Package kernel + Kaeru
```bash
# Copy LK to AK3 directory
cp kaeru/selene-kaeru.bin ak3/lk_a.img
sed -i 's/do_kaeru=0/do_kaeru=1/' ak3/anykernel.sh
```

## Flashing

### Via Recovery (recommended)
```bash
# ZIP includes both kernel + Kaeru LK
# anykernel.sh automatically flashes LK to lk_a partition
adb push Mocchipyon-*.zip /sdcard/
# Flash via TWRP/LineageOS recovery
```

### Via Fastboot (manual)
```bash
fastboot flash boot_a Image.gz-dtb
fastboot flash lk_a selene-kaeru.bin
fastboot reboot
```

## Verification

```bash
# Check Kaeru LK version
fastboot oem kaeru-version

# Check kernel detection
dmesg | grep kaeru
# Should show:
# kaeru: detected v2.0.0 (flags=0x...)
# kaeru: lock state spoofing active
# kaeru: recovery mode requested

# Check spoofing status
fastboot oem get-spoof-state
```

## Known Issues

### Offset Verification
- Config offsets extracted from binary via `xxd` + pattern matching
- **CRITICAL**: Offsets must match actual LK binary
- If patterns don't match, patches silently don't apply
- Use Ghidra to verify offsets from stock LK dump

### DRAM Address Overlap
- `CONFIG_KAERU_COMM_BASE=0x4C500000` falls within LK region
- This is intentional — Kaeru writes to its own DRAM space
- Stock LK will have garbage at this address (magic check fails)

### Binary Pattern Staleness
- Patterns in `board-selene.c` extracted from current stock LK
- If Xiaomi releases new firmware with different LK, patterns may break
- Always verify patterns against latest stock LK dump

## Safe Flashing Rules

1. **Backup LK first**: `python3 mtk r lk_a lk_stock.bin`
2. **A/B safety**: Slot B stays stock if slot A fails
3. **Use recovery flashing**: Auto-handles A/B slots
4. **Keep stock LK**: Can recover via mtkclient BROM mode

## References

- **Kaeru source**: https://github.com/R0rt1z2/kaeru
- **LittleSpammyMailman**: https://github.com/mt6768-S/android_kernel_xiaomi_mt6768-k419/tree/full-patches
- **Telegram MT6768**: https://t.me/twrp_mt6768
- **mtkclient**: https://github.com/bkerler/mtkclient
