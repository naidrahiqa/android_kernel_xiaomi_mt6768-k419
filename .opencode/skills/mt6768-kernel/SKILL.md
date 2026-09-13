---
name: mt6768-kernel
description: Use when working on the Xiaomi Selene (MT6768/Helio G85) Android kernel 4.19 porting project. Covers device tree, drivers (touchscreen, fingerprint, camera, audio, charger), defconfig, build system, and LineageOS/Mocchipyon integration. Trigger keywords: selene, mt6768, kernel, device tree, defconfig, DTS, drivers, build, compile, porting.
---

# MT6768 Kernel Development Skill (4.19 Porting)

## Project Overview

- **Device**: Xiaomi Selene (Redmi 9 / Redmi 9A family)
- **SoC**: MediaTek MT6768 (Helio G85), 8-core ARM Cortex-A75/A55
- **Kernel**: Linux 4.19.325 (CIP stable backport) — **STATUS: UNSTABLE, MASIH PORTING**
- **Branch**: `Mocchipyon23.2` (LineageOS 23.2 based)
- **Architecture**: arm64
- **Toolchain**: Clang/LLVM (clang-r383902)
- **GPU**: Mali Valhall r32p1
- **TEE**: Microtrust v400

## Reference Project (4.14 Stable)

**PENTING**: Project ini adalah porting dari kernel 4.14 yang sudah stabil. Untuk referensi kode, config, atau perbandingan driver, gunakan project 4.14:

- **Path**: `/home/naidra/Projects/Kernel/android_kernel_xiaomi_selene`
- **Branch**: `phrolova` (main stable branch)
- **Kernel**: Linux 4.14.357 (yuki-saisei base)
- **GitHub**: `naidrahiqa/android_kernel_xiaomi_selene`
- **Status**: Production-ready, semua driver work

### Kapan pakai reference 4.14
- Butuh tahu cara kerja driver tertentu di Selene
- Cek config/defconfig yang sudah proven work
- Perbandingan DTS antara 4.14 vs 4.19
- Debugging porting issues (API beda antara 4.14 vs 4.19)
- Cek Kconfig options yang sudah di-enable di 4.14

### Contoh pemakaian
```
"Touchscreen FocalTech di 4.19 tidak jalan, cek perbandingan dengan 4.14"
"Config fingerprint Goodix di 4.14 apa aja? Bandingkan dengan 4.19"
"DTS audio AW87559 di 4.14 beda apa dengan 4.19?"
```

## Key File Locations

### Defconfig
- `arch/arm64/configs/vendor/mt6768_defconfig` — Main SoC defconfig
- `arch/arm64/configs/vendor/selene.config` — Device-specific overlay
- `arch/arm64/configs/vendor/lancelot.config` — Redmi 9 Power / Note 9 4G
- `arch/arm64/configs/vendor/merlin.config` — Redmi 9T

### Device Tree
- `arch/arm64/boot/dts/mediatek/mt6768.dts` — Base SoC DTS (4320 lines)
- `arch/arm64/boot/dts/mediatek/selene.dts` — Device overlay DTS (766 lines)
- `arch/arm64/boot/dts/mediatek/selene/cust.dtsi` — Auto-generated peripheral config
- `arch/arm64/boot/dts/mediatek/cust_mt6768_touch_1080x2400.dtsi` — Touch panel
- `arch/arm64/boot/dts/mediatek/cust_mt6768_selene_camera.dtsi` — Camera config

### Drivers
- `drivers/input/touchscreen/mediatek/focaltech_touch_k19a/` — Primary touchscreen (FocalTech)
- `drivers/input/fingerprint/goodix/` — Goodix fingerprint (SPI)
- `drivers/input/fingerprint/fpc/` — FPC1022 fingerprint
- `sound/soc/mediatek/aw87xxx/` — AW87559 audio amplifier
- `sound/soc/mediatek/fs1815n/` — FS16XX audio amplifier
- `drivers/misc/mediatek/` — MediaTek platform drivers (117 subdirs)

### Build Config
- `build.config.mtk.aarch64` — Primary MTK build config
- `build.config.mtk.aarch64.kasan` — KASAN debug variant
- `build.config.mtk.aarch64.ubsan` — UBSAN debug variant

## Hardware Configuration (from selene.dts)

| Component | Details |
|-----------|---------|
| Display | NT36672C DSI VDO, 1080x2400, 60Hz, DSC |
| Touch | FocalTech FTS (SPI), double-tap support |
| Fingerprint | Goodix GF3208 (SPI2, GPIO8 IRQ, GPIO31 reset) |
| NFC | NXP PN553 (I2C3, addr 0x28) |
| Charger | BQ25890 + SMB1351, USB Type-C (FUSB302) |
| Audio PA | AW87559 (I2C6), FS16XX |
| Backlight | KTD3137 + LM3697 |
| LED | RGB (GPIO-based) |
| Camera | OV50C40, S5KJN1, OV8856, GC02M1B, IMX355 |
| GPS LNA | GPIO94 |
| IR TX | PWM (GPIO12) |

## Build Commands

```bash
# Full build
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- mt6768_defconfig selene.config
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j$(nproc)

# Using GKI build system
build/build.sh

# Build specific module
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- M=drivers/input/touchscreen/mediatek/focaltech_touch_k19a

# DTB only
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- dtbs
```

## Common Development Tasks

### Adding a new driver
1. Create directory in appropriate location (e.g., `drivers/input/touchscreen/mediatek/`)
2. Add Kconfig entry in parent `Kconfig` file
3. Add obj-$(CONFIG_XXX) line in parent `Makefile`
4. Add config to `mt6768_defconfig` or `selene.config`

### Modifying device tree
1. Edit `selene.dts` for device-specific changes
2. Edit `mt6768.dts` for SoC-level changes
3. Rebuild DTB: `make ARCH=arm64 dtbs`

### Modifying defconfig
```bash
# Edit config
make ARCH=arm64 mt6768_defconfig selene.config
make ARCH=arm64 menuconfig
# Save new defconfig
make ARCH=arm64 savedefconfig
cp defconfig arch/arm64/configs/vendor/mt6768_defconfig
```

## Git Conventions

- **Branch naming**: `Mocchipyon23.2` (main), `lineage-23.2-selene` (LineageOS)
- **Commit format**: `<subsystem>: <description>` (e.g., `sound: suppress logs`, `arm64: mt6768: Disable LTO_CLANG`)
- **Push**: `git push origin Mocchipyon23.2 --force-with-lease` (after amend)

## Known Issues & Technical Debt

1. **12,280 TODO/FIXME/HACK markers** — Concentrated in WLAN drivers (`gen2/`, `gen4m/`)
2. **Kernel 4.19 EOL** — CIP extends support, but evaluate for Android 15+ GKI 2.0
3. **Multiple charger ICs in DTS** — Both BQ25890 and SMB1351 defined, verify which is active
4. **Empty Android.mk** — Intentional from MTK, do not delete

## Troubleshooting

### Touch not working
- Check `selene.dts` touchscreen section
- Verify `CONFIG_TOUCHSCREEN_FTS_XIAOMI=y` in defconfig
- Check SPI bus and GPIO config in DTS

### Fingerprint not probing
- Check `selene.dts` fingerprint section (SPI2, GPIO8, GPIO31)
- Verify `CONFIG_GOODIX_FINGERPRINT=y` in defconfig
- Check TEE (Microtrust) integration

### Display issues
- Check panel DTS node in `selene.dts` (panel-nt36672c-dsc-vdo-video)
- Verify DSC settings (1080x2400, 4-lane MIPI)
- Check backlight config (KTD3137 + LM3697)

### Audio issues
- Check AW87559 PA DTS (I2C6, addr 0x28)
- Verify `CONFIG_SND_SOC_AW87XXX=y`
- Check codec DAI link config in `mt6768.dts`
