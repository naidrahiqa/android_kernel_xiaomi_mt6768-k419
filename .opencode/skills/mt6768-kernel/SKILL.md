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
- **Toolchain**: [Greenforce Clang](https://github.com/greenforce-project/greenforce_clang) (LLVM/Clang, built with PGO+ThinLTO+O3+Polly)
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

### KernelSU (ReSukiSU)
- `resukisu/` — ReSukiSU kernel driver (latest from GitHub)
- **Source**: https://github.com/ReSukiSU/ReSukiSU
- **Driver path**: `resukisu/kernel/` (copied from ReSukiSU repo)
- **Kconfig**: `CONFIG_KSU=y`, `CONFIG_KSU_MANUAL_HOOK=y` (non-GKI 4.19)
- **Compat layer**: `resukisu/kernel/compat/` — auto-detect API differences
- **Build checks**: `resukisu/kernel/tools/kernel_compat.mk` — 30+ API checks

### NoMount
- `fs/nomount.c` + `fs/nomount.h` — Kernel module (systemless path redirection)
- `tools/nomount/` — Userspace binary (arm64 static) + Magisk module
- **Source**: https://github.com/maxsteeel/nomount
- **Status**: v20, needs 4.19 API adaptation (iterate_shared, getattr 4-arg)

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

### Setup Greenforce Clang (one-time)
```bash
# Install Greenforce Clang
bash <(wget -qO- https://raw.githubusercontent.com/greenforce-project/greenforce_clang/refs/heads/main/get_clang.sh)
export PATH="$(pwd)/greenforce-clang/bin:$PATH"

# Install cross-compilers (Ubuntu/Debian)
sudo apt-get install -y gcc-aarch64-linux-gnu binutils-aarch64-linux-gnu \
                        gcc-arm-linux-gnueabi binutils-arm-linux-gnueabi
```

### Full build
```bash
make O=out ARCH=arm64 \
  CC=clang HOSTCC=gcc \
  CROSS_COMPILE=aarch64-linux-gnu- \
  CROSS_COMPILE_ARM32=arm-linux-gnueabi- \
  LD=ld.lld AR=llvm-ar NM=llvm-nm \
  OBJCOPY=llvm-objcopy OBJDUMP=llvm-objdump \
  STRIP=llvm-strip READELF=llvm-readelf \
  LLVM=1 LLVM_IAS=1 \
  mt6768_defconfig

cat arch/arm64/configs/vendor/selene.config >> out/.config
make O=out ARCH=arm64 olddefconfig

make O=out ARCH=arm64 \
  CC=clang HOSTCC=gcc \
  CROSS_COMPILE=aarch64-linux-gnu- \
  CROSS_COMPILE_ARM32=arm-linux-gnueabi- \
  LD=ld.lld AR=llvm-ar NM=llvm-nm \
  OBJCOPY=llvm-objcopy OBJDUMP=llvm-objdump \
  STRIP=llvm-strip READELF=llvm-readelf \
  LLVM=1 LLVM_IAS=1 \
  -j$(nproc)
```

> **PENTING untuk kernel 4.19:**
> - `CROSS_COMPILE_ARM32=arm-linux-gnueabi-` wajib untuk vDSO32 (32-bit compat)
> - `LLVM_IAS=1` harus di-pass explicit (belum default di kernel < 5.15)
> - Greenforce Clang gak butuh `CLANG_TRIPLE` atau `LD_LIBRARY_PATH`
> - Kalau error `.pad` atau `mov` di assembly, vdso32 sudah di-patch pakai `-fno-integrated-as`

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

### ReSukiSU Integration
```bash
# Symlink driver ke kernel source
ln -sf "$(realpath resukisu/kernel)" drivers/kernelsu

# Enable di defconfig
CONFIG_KSU=y
CONFIG_KSU_MANUAL_HOOK=y  # non-GKI 4.19 wajib

# Verify hooks exist di build time
make -C resukisu/kernel/tools manual_hook_check.mk
```

### NoMount Integration
```bash
# Copy ke fs/
cp /path/to/nomount/kernel/src/nomount.c fs/
cp /path/to/nomount/kernel/src/nomount.h fs/

# Add ke Kconfig + Makefile di fs/
# userspace binary
aarch64-linux-gnu-gcc -static -O2 -nostdlib -nostartfiles \
  -Itools/nomount -o nm tools/nomount/src/nm.c
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

## Porting Gotchas (dari 4.14 experience)

### Clang IAS Issues
- **`.weak` → `.globl`**: Clang IAS reject changing binding from STB_WEAK to STB_GLOBAL. Fix: ganti `.weak memcpy` → `.globl memcpy` di `arch/arm64/lib/{memcpy,memmove,memset}.S`
- **`stpcpy` undefined**: Clang 23+ optimize `strcpy` + pointer arithmetic jadi `stpcpy()`. Fix: tambah generic implementation di `lib/string.c` + declaration di `include/linux/string.h`
- **Named macro args**: VDSO `gettimeofday.S` — `clock_gettime_return, shift=1` harus `clock_gettime_return 1` (positional args)
- **68-bit literal**: `arch/arm64/crypto/aes-modes.S` — `0x30000000200000001` exceeds IAS range. Fix: explicit lane construction dengan `mov/dup`

### LTO & Linker
- **LTO mismatch**: `CONFIG_LTO_CLANG=y` — LLVM 23 bitcode gagal di-link oleh LLVM 16 system linker. Disable LTO atau gunakan LLVM yang match
- **`GCC_TOOLCHAIN_DIR`**: Pakai `$(CROSS_COMPILE)as` bukan `$(CROSS_COMPILE)elfedit`

### ZSTD
- **`ZSTD_STATIC_ASSERT`**: `lib/zstd/zstd_internal.h` — enum pembagian nol ditolak Clang 23. Fix: ganti dengan C11 `_Static_assert((c), "ZSTD_STATIC_ASSERT")`

### GCC
- **GCC 13 `-Werror`**: Vendor driver warnings di-promote ke error. Fix: tambah `-Wno-error` di `scripts/Makefile.lib` `orig_c_flags`

### UAPI Headers
- **Missing headers**: `xt_connmark.h`, `xt_mark.h` harus dibuat manual di `include/uapi/linux/netfilter/`
- **`xt_hl.c` deleted**: Diperlukan karena `IP_NF_MATCH_TTL` select `NETFILTER_XT_MATCH_HL`. Restore dari parent commit

### FPSGO
- **`CONFIG_TRACEPOINTS=y`**: FPSGO GPU driver butuh tracepoints. Tanpa ini, 60+ undefined reference errors

### Security Hardening — JANGAN ENABLE
| Config | Masalah |
|--------|---------|
| `BUG_ON_DATA_CORRUPTION` | Bootloop dari benign list corruption |
| `INIT_ON_ALLOC_DEFAULT_ON` | Bootloop dari uninitialized memory dependencies |
| `SHADOW_CALL_STACK` | Kernel panic ~2 jam (TrustZone clobber x18) |
| `SLAB_FREELIST_HARDENED` | Kernel panic ~81 menit (use-after-free di CCCI/CLDMA) |

### Fingerprint Prebuilt
- **GOODIX**: Prebuilt `gf_spi_tee.o_shipped` depends on `__stack_chk_guard` → disable atau provide stubs
- **FPC**: Depends on `spi_fingerprint` + `goodix_fp_exist` dari Goodix

### /proc/config.gz Stale
- `kernel/Makefile` line 125 — hardcoded `stock_defconfig`. Fix: ganti ke `$(KCONFIG_CONFIG)`

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
