# PawwwNunungggg Kernel (Xiaomi Selene / MT6768)

[![Build & Release](https://github.com/naidrahiqa/android_kernel_xiaomi_mt6768-k419/actions/workflows/build.yml/badge.svg)](https://github.com/naidrahiqa/android_kernel_xiaomi_mt6768-k419/actions/workflows/build.yml)
[![Kernel Version](https://img.shields.io/badge/Kernel-4.19.325--CIP-blue.svg)](https://git.kernel.org/pub/scm/linux/kernel/git/cip/linux-cip.git)
[![Root](https://img.shields.io/badge/Root-ReSukiSU-green.svg)](https://github.com/ReSukiSU/ReSukiSU)
[![Systemless](https://img.shields.io/badge/Systemless-NoMount%20v20-orange.svg)](https://github.com/maxsteeel/nomount)

Custom Linux 4.19 CIP kernel for **Xiaomi Redmi 10 / Redmi 10 2022 / Redmi 10 Prime** (`selene`), powered by the MediaTek Helio G88 (MT6768 / MT6769).

---

## 📱 Device Specifications

| Parameter | Value |
|---|---|
| **Device Model** | Xiaomi Redmi 10 / Redmi 10 2022 / Redmi 10 Prime (`selene`) |
| **SoC** | MediaTek MT6768 / MT6769 (Helio G88), Octa-core (2x Cortex-A75 + 6x Cortex-A55) |
| **Architecture** | ARM64 (`aarch64`) |
| **Kernel Base** | Linux 4.19.325 (Civil Infrastructure Platform LTS) |
| **Target ROMs** | AOSP / LineageOS 20+ (Android 13, 14, 15, 16, 17) |
| **Toolchain** | [Greenforce Clang](https://github.com/greenforce-project/greenforce_clang) (LLVM 18+ with PGO, ThinLTO, O3, Polly) |

> ⚠️ **Stock MIUI Note**: Stock MIUI 12.5 / 13 / 14 official ROMs for Selene run on kernel 4.14. Flashing this 4.19 kernel to stock MIUI may cause bootloops or broken cameras due to proprietary vendor HAL ABI mismatches. For official MIUI 12.5/13/14, use the 4.14 stable reference tree (`android_kernel_xiaomi_selene`).

---

## ⚡ Key Features

* **Dynamic Fsync 2.0 (`CONFIG_DYNAMIC_FSYNC=y`)**
  * Automatically disables `fsync` syscall overhead while the screen is on to eliminate I/O stuttering in competitive games (Mobile Legends, Genshin Impact).
  * Automatically issues a full filesystem sync when the screen turns off to guarantee data integrity.
  * Node: `/sys/kernel/dyn_fsync/dyn_fsync_active` (1 = active, 0 = disabled).

* **MediaTek Hardware-Accelerated KCAL**
  * Native RGB color multiplier directly driving MediaTek CCORR hardware registers with live display refresh and **0 CPU overhead**.
  * Fully compatible with Franco Kernel Manager (FKM), SmartPack-Kernel Manager, and KCAL apps.
  * Node: `/sys/devices/platform/kcal_ctrl.0/kcal`.

* **Boeffla Wakelock Blocker (`CONFIG_BOEFFLA_WL_BLOCKER=y`)**
  * Prevents aggressive background wakelocks from draining battery during idle deep sleep.
  * Pre-populated with default battery-saving filters: `wlan_ipa`, `wlan_pno_wl`, `NETLINK`.
  * Node: `/sys/devices/virtual/misc/boeffla_wakelock_blocker/`.

* **Aggressive ZRAM Offloading (`vm.swappiness` up to 200)**
  * Sysctl maximum boundary elevated from 100 to 200 in `kernel/sysctl.c`.
  * Allows memory-heavy workloads and multitasking on 6GB RAM configurations to swap anonymous pages proactively to ZRAM.

* **ReSukiSU & NoMount Integration**
  * Root solution via **ReSukiSU** (`CONFIG_KSU_MANUAL_HOOK=y`).
  * Systemless path redirection via **NoMount v20** (`fs/nomount.c`).

* **Enhanced Networking & Tethering**
  * **TCP Westwood+ & BBR**: Westwood+ for lossy cellular connections; BBR enabled as default congestion algorithm.
  * **Netfilter TTL / HL Mangling**: `CONFIG_NETFILTER_XT_TARGET_HL=y` (`iptables -t mangle -A POSTROUTING -j TTL --ttl-set 64`).

* **Charging & Display Protection**
  * Permanent thermal limitation clamp bypass (`thermal_icl_ua = -1` in `mtk_charger.c`) to maintain 10W-18W charging rates.
  * Panel blanking prevention: ignores thermal daemon brightness drops below maximum in `mtk_cooler_backlight_cus.c`.

---

## ⚙️ Sysfs Tunables & Control Reference

| Feature | Sysfs Path | Values / Usage |
|---|---|---|
| **Dynamic Fsync** | `/sys/kernel/dyn_fsync/dyn_fsync_active` | `1` (enabled, default), `0` (disabled) |
| **Fsync Status** | `/sys/kernel/dyn_fsync/dyn_fsync_suspended` | `0` (screen on), `1` (screen off / flushing) |
| **KCAL RGB** | `/sys/devices/platform/kcal_ctrl.0/kcal` | `r g b` (`0-256`, default `256 256 256`) |
| **KCAL Enable** | `/sys/devices/platform/kcal_ctrl.0/kcal_enable` | `1` (active), `0` (disabled) |
| **Wakelock Blocker** | `/sys/devices/virtual/misc/boeffla_wakelock_blocker/wakelock_blocker` | Semicolon-delimited list of wakelocks |
| **Swappiness** | `/proc/sys/vm/swappiness` | `0` to `200` (default: `100` / `160` recommended with ZRAM) |
| **TTL Mangling** | `iptables -t mangle -A POSTROUTING -j TTL --ttl-set 64` | Tethering hotspot carrier bypass |

---

## ⚠️ Critical Flashing & Hardware Safety Rules

1. **DO NOT FLASH LK OR DTBO VIA ANYKERNEL3**
   * AnyKernel3 must **ONLY** flash the `boot` partition (`write_boot;`).
   * Never bundle `lk_a.img`, `kaeru_selene.bin`, or `dtbo.img` into AnyKernel3 zip files. Doing so risks a hard BROM brick.
2. **DO NOT MODIFY CHARGER DTS VOLTAGES**
   * `battery_cv` is strictly hardware-rated at `4350000` (4.35V). Overriding this will trigger PMIC overvoltage protection and hardware failure.
   * `enable_sw_jeita` and `pd_vbus_upper_bound > 5000000` are strictly disallowed.

---

## 🛠️ Building from Source

### Prerequisites

Install build essentials and cross-compilers:
```bash
sudo apt-get update
sudo apt-get install -y gcc-aarch64-linux-gnu binutils-aarch64-linux-gnu \
                        gcc-arm-linux-gnueabi binutils-arm-linux-gnueabi \
                        bc bison flex libssl-dev libelf-dev zstd
```

Setup Greenforce Clang:
```bash
bash <(wget -qO- https://raw.githubusercontent.com/greenforce-project/greenforce_clang/refs/heads/main/get_clang.sh)
export PATH="$(pwd)/greenforce-clang/bin:$PATH"
```

### Build Commands

```bash
# 1. Defconfig
make O=out ARCH=arm64 \
  CC=clang HOSTCC=gcc \
  CROSS_COMPILE=aarch64-linux-gnu- \
  CROSS_COMPILE_ARM32=arm-linux-gnueabi- \
  LD=ld.lld AR=llvm-ar NM=llvm-nm \
  LLVM=1 LLVM_IAS=1 \
  selene_defconfig

# 2. Compile Kernel Image
make O=out ARCH=arm64 \
  CC=clang HOSTCC=gcc \
  CROSS_COMPILE=aarch64-linux-gnu- \
  CROSS_COMPILE_ARM32=arm-linux-gnueabi- \
  LD=ld.lld AR=llvm-ar NM=llvm-nm \
  LLVM=1 LLVM_IAS=1 \
  -j$(nproc)
```

The resulting kernel image will be generated at `out/arch/arm64/boot/Image.gz`.

---

## 📄 License & Credits

* Base kernel: [Linux Kernel](https://kernel.org) licensed under **GPLv2**.
* Porting & Maintainer: [@naidrahiqa](https://github.com/naidrahiqa).
* Upstream MediaTek unified base: [mt6768-S team](https://github.com/mt6768-S).
* ReSukiSU root driver: [ReSukiSU](https://github.com/ReSukiSU/ReSukiSU).
* NoMount: [maxsteeel](https://github.com/maxsteeel/nomount).
* KCAL color control: savoca (adapted for MediaTek CCORR).
* Boeffla wakelock blocker: Lord Boeffla.
