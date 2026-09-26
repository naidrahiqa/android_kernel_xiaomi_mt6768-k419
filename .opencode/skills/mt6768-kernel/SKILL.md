---
name: mt6768-kernel
description: Master skill untuk Xiaomi Selene MT6768 kernel 4.19 porting project. Covers device tree, drivers, build system, defconfig, LineageOS/Mocchipyon integration. Trigger: selene, mt6768, kernel, device tree, defconfig, DTS, drivers, build, compile, porting.
---

# MT6768 Kernel Development Skill (4.19 Porting)

## Project Overview

- **Device**: Xiaomi Selene (Redmi 10 / Redmi 10 2022 / Redmi 10 Prime)
- **SoC**: MediaTek MT6768 / MT6769 (Helio G88), 8-core ARM Cortex-A75/A55
- **Kernel**: Linux 4.19.325 (CIP stable backport) — **STATUS: UNSTABLE, MASIH PORTING**
- **Branches**:
  - `Mocchipyon23.2`: Primary development branch (LineageOS 23.2 / Android 15 & CIP 4.19.325 porting)
  - `Mocchipyon24.0`: Development branch untuk LineageOS 24.0
  - `lineage-24.0`: Clean tracking branch dari upstream `mt6768-S`
- **Remotes**:
  - `origin`: `https://github.com/naidrahiqa/android_kernel_xiaomi_mt6768-k419` (fork)
  - `upstream`: `https://github.com/mt6768-S/android_kernel_xiaomi_mt6768` (MT6768 unified base)
  - `cip`: `https://git.kernel.org/pub/scm/linux/kernel/git/cip/linux-cip.git` (CIP upstream)
- **Architecture**: arm64
- **Toolchain**: [Greenforce Clang](https://github.com/greenforce-project/greenforce_clang) (LLVM/Clang, built with PGO+ThinLTO+O3+Polly)
- **GPU**: Mali Valhall r32p1
- **TEE**: Microtrust v400
- **Root**: ReSukiSU (manual hook mode)
- **Systemless**: NoMount v20
- **Bootloader**: Stock Little Kernel (LK) — flashing LK / DTBO dilarang karena risiko brick

## ROM & Android Compatibility

- **AOSP / Custom ROM (Android 13+ up to 17)**:
  - **LineageOS 20**: Android 13
  - **LineageOS 21**: Android 14
  - **LineageOS 22**: Android 15
  - **LineageOS 23 / 23.2**: Android 16 (aktif di device test via ADB)
  - **LineageOS 24 / 24.0**: Android 17 (target pengembangan branch `Mocchipyon24.0`)
  - Seluruh varian Custom ROM MT6768 di atas menggunakan unified device/vendor tree berbasis kernel 4.19.
- **Stock MIUI 13 (Android 12) & MIUI 14 (Android 13)**:
  - ⚠️ **Stock Xiaomi ROM untuk Selene berjalan di atas Kernel 4.14**. Stock proprietary vendor blobs (Camera ISP, Mali DDK, Display, Audio) di-compile terhadap ABI kernel 4.14.
  - Flashing kernel 4.19 ini ke Stock MIUI resmi berpotensi **bootloop** atau kamera/sensor mati karena ketidakcocokan HAL blob 4.14 dengan kernel 4.19.
  - **Untuk Stock MIUI 12.5/13/14**, gunakan kernel **4.14** (lihat Reference Project di bawah).

## Reference Project (4.14 Stable for Stock MIUI)

- **Path**: `/home/naidra/Projects/Kernel/android_kernel_xiaomi_selene`
- **Branch**: `phrolova`
- **Kernel**: Linux 4.14.357
- **GitHub**: `naidrahiqa/android_kernel_xiaomi_selene`
- **Status**: Production-ready untuk Stock MIUI 12.5 / 13 / 14 dan ROM berbasis kernel 4.14

## Skill Index

| Skill | File | Trigger |
|---|---|---|
| **MT6768 Kernel** | `.opencode/skills/mt6768-kernel/SKILL.md` | Master — overview, hardware, build commands |
| Build System Fixes | `.opencode/skills/build-system-fixes/SKILL.md` | Clang IAS, stpcpy, LTO, ZSTD, UAPI, gotchas |
| ReSukiSU Integration | `.opencode/skills/resukisu-integration/SKILL.md` | KernelSU driver, manual hooks, KSU_VERSION |
| NoMount | `.opencode/skills/nomount/SKILL.md` | Systemless path redirection, VFS hooks |
| CI/CD (GitHub Actions) | `.opencode/skills/ci-cd-github-actions/SKILL.md` | Workflow, Telegram notif, release automation |
| Defconfig Management | `.opencode/skills/defconfig-management/SKILL.md` | Config dependency chains, gotchas |
| Kaeru Integration | `.opencode/skills/kaeru-integration/SKILL.md` | Bootloader spoofer, lock state, cert bypass |
| Versioning & Releases | `.opencode/skills/versioning-releases/SKILL.md` | Version scheme, channels (nightly/beta/stable), localversion, tag conventions |

**Cara pakai:** Saat dapat task, baca skill yang sesuai. Untuk task umum, mulai dari skill ini.

## Key File Locations

### Defconfig
- `arch/arm64/configs/selene_defconfig` — Single unified device defconfig (recommended)
- `arch/arm64/configs/vendor/mt6768_defconfig` — Base MTK SoC defconfig
- `arch/arm64/configs/vendor/selene.config` — Device-specific overlay (legacy)
- `arch/arm64/configs/vendor/lancelot.config` — Redmi 9 (Helio G80)
- `arch/arm64/configs/vendor/merlin.config` — Redmi Note 9 (Helio G85)

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
- `resukisu/` — ReSukiSU kernel driver
- **Source**: https://github.com/ReSukiSU/ReSukiSU
- **Driver path**: `resukisu/kernel/`

### NoMount
- `fs/nomount.c` + `fs/nomount.h` — Kernel module
- `tools/nomount/` — Userspace binary + Magisk module
- **Source**: https://github.com/maxsteeel/nomount

### Build Config
- `build.config.mtk.aarch64` — Primary MTK build config
- `scripts/anykernel.sh` — AnyKernel3 packaging
- `scripts/build-kaeru.sh` — Kaeru LK build/package script

### Kaeru (Bootloader Spoofer)
- `drivers/misc/kaeru_comm.c` — Kernel-side DRAM communication
- `include/linux/kaeru_comm.h` — Header with inline fallbacks
- `kaeru/kaeru_selene.bin` — Pre-built Kaeru LK binary
- **Kaeru source**: `/home/naidra/Projects/kaeru-src/`
- **Board file**: `kaeru-src/board/xiaomi/board-selene.c`
- **Config**: `kaeru-src/configs/xiaomi/selene_defconfig`

## Hardware Configuration (from selene.dts)

| Component | Details |
|-----------|---------|
| Display | NT36672C DSI VDO, 1080x2400, 60Hz, DSC |
| Touch | FocalTech FTS (SPI), double-tap support |
| Fingerprint | Goodix GF3208 (SPI2, GPIO8 IRQ, GPIO31 reset) |
| NFC | NXP PN553 (I2C3, addr 0x28) |
| Charger | BQ25890 + SMB1351, USB Type-C (FUSB302), 18W QC |
| Audio PA | AW87559 (I2C6), FS16XX |
| Backlight | KTD3137 + LM3697 |
| LED | RGB (GPIO-based) |
| Camera | OV50C40, S5KJN1, OV8856, GC02M1B, IMX355 |
| GPS LNA | GPIO94 |
| IR TX | PWM (GPIO12) |

## CRITICAL: Charger DTS — BRICK WARNING (19 Sep 2026)

> **PHONE BRICKED** gara-gara charger DTS + Kconfig fix. JANGAN ULANGI.

### What Happened
```
CONFIG_MTK_CHARGER depends on MEDIATEK_SOLUTION (UNDEFINED)
→ Charger driver SILENTLY DISABLED (ga compile)
→ DTS values ga dibaca → Phone AMAN

Kconfig fix (hapus dependency) → Charger driver ENABLED
→ Baca DTS: battery_cv=4460000 (OVERVOLTAGE!)
→ PMIC hardware protection → BRICK
```

### Safe Charger DTS Values for Selene (HARDWARE-RATED)
```dts
/* mt6768.dts — charger node */
battery_cv = <4350000>;           /* 4.35V — JANGAN UBAH */
max_charger_voltage = <15000000>;
min_charger_voltage = <4600000>;
non_std_ac_charger_current = <500000>;
pd_vbus_upper_bound = <5000000>;         /* 5V max — JANGAN UBAH ke 9V */
/* enable_sw_jeita; */             /* JANGAN ENABLE tanpa HW test */
/* hvdcp_charger_current = <3000000>; */ /* JANGAN TAMBAH tanpa validasi */

/* JEITA CV values — original hardware-rated */
jeita_temp_above_t4_cv = <4240000>;
jeita_temp_t3_to_t4_cv = <4240000>;
jeita_temp_t2_to_t3_cv = <4340000>;
jeita_temp_t1_to_t2_cv = <4240000>;
jeita_temp_t0_to_t1_cv = <4040000>;
jeita_temp_below_t0_cv = <4040000>;

/* lk_charger node */
temp_t4_threshold = <50>;          /* JANGAN UBAH ke 60 */
```

### Rules (WAJIB)
1. **JANGAN ubah `battery_cv`** — 4.35V adalah hardware-rated
2. **JANGAN enable `enable_sw_jeita`** tanpa flash + test 24 jam
3. **JANGAN tambah `hvdcp_charger_current`** tanpa validasi charger IC
4. **JANGAN asumsi LineageOS values aman** — device kita beda charger IC
5. **Kalau mau ubah charger config**, flash dulu ke hardware, test, baru commit

## Build Commands

### Setup Greenforce Clang (one-time)
```bash
bash <(wget -qO- https://raw.githubusercontent.com/greenforce-project/greenforce_clang/refs/heads/main/get_clang.sh)
export PATH="$(pwd)/greenforce-clang/bin:$PATH"

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
  selene_defconfig

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
> - `CROSS_COMPILE_ARM32=arm-linux-gnueabi-` wajib untuk vDSO32
> - `LLVM_IAS=1` harus di-pass explicit (belum default di kernel < 5.15)
> - Greenforce Clang gak butuh `CLANG_TRIPLE` atau `LD_LIBRARY_PATH`

## Common Development Tasks

### Adding a new driver
1. Create directory in appropriate location
2. Add Kconfig entry in parent `Kconfig` file
3. Add obj-$(CONFIG_XXX) line in parent `Makefile`
4. Add config to `selene_defconfig`

### Modifying device tree
1. Edit `selene.dts` for device-specific changes
2. Edit `mt6768.dts` for SoC-level changes
3. Rebuild DTB: `make ARCH=arm64 dtbs`

### Modifying defconfig
```bash
make ARCH=arm64 selene_defconfig
make ARCH=arm64 menuconfig
make ARCH=arm64 savedefconfig
cp defconfig arch/arm64/configs/selene_defconfig
```

## Git Conventions & Branch Workflow

### Remotes
- `origin`: `https://github.com/naidrahiqa/android_kernel_xiaomi_mt6768-k419`
- `upstream`: `https://github.com/mt6768-S/android_kernel_xiaomi_mt6768`
- `cip`: `https://git.kernel.org/pub/scm/linux/kernel/git/cip/linux-cip.git`

### Active Branches
- `Mocchipyon23.2`: Primary development branch (Lineage 23.2 & 4.19 CIP porting)
- `Mocchipyon24.0`: Development branch untuk Lineage 24.0
- `lineage-24.0`: Pristine tracking branch dari upstream `mt6768-S`

### Syncing Upstream Branches
```bash
# Sync branch lineage-24.0 dari upstream
git checkout lineage-24.0
git pull upstream lineage-24.0
git push origin lineage-24.0

# Rebase / update branch dev Mocchipyon24.0 dari upstream lineage-24.0
git checkout Mocchipyon24.0
git rebase lineage-24.0
git push origin Mocchipyon24.0 --force-with-lease
```

- **Commit format**: `<subsystem>: <description>`
- **Push**: `git push origin <branch> --force-with-lease`
