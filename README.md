# Mocchipyon Kernel

Custom kernel for **Xiaomi Redmi 9 / Redmi 9A (Selene)** — MediaTek MT6768 (Helio G85)

> ⚠️ **Status: Unstable / Porting** — Not yet ready for daily use.

| | |
|---|---|
| **Kernel** | Linux 4.19.325 (CIP stable backport) |
| **Base** | LineageOS 23.2 (Mocchipyon23.2) |
| **Root** | [ReSukiSU](https://github.com/ReSukiSU/ReSukiSU) (manual hook mode) |
| **Systemless** | [NoMount v20](https://github.com/maxsteeel/nomount) |
| **Bootloader** | [Kaeru LK](https://github.com/R0rt1z2/kaeru) (lock state spoofing) |
| **Toolchain** | [Greenforce Clang](https://github.com/greenforce-project/greenforce_clang) (PGO+ThinLTO+O3+Polly) |

## Download

📦 **[GitHub Releases](../../releases)** — Stable and beta builds

Nightly builds are available as GitHub Actions artifacts (expires after 90 days).

## Features

- 🚀 **BBR** TCP congestion control (default)
- 🔐 **WireGuard** VPN built-in
- ⚡ **LZ4/LZ4HC** zRAM compression
- 📦 **DroidSpaces** container support
- 🔓 **Kaeru** bootloader lock state spoofing + cert bypass
- 🛡️ **NoMount** systemless path redirection (keyring-based)
- 👑 **ReSukiSU** KernelSU root (manual hook mode)

## Install

1. Download the latest `.zip` from [Releases](../../releases)
2. Boot into custom recovery (TWRP / OrangeFox)
3. Flash the AnyKernel3 zip
4. Reboot

> **Note:** The zip includes Kaeru LK when available. It will auto-flash to the `lk` partition on A/B devices.

## Supported Devices

| Codename | Device | Status |
|----------|--------|--------|
| `selene` | Xiaomi Redmi 9 | Primary |
| `merlin` | Xiaomi Redmi 9T | Untested |
| `lancelot` | Xiaomi Redmi 9 Power / Note 9 4G | Untested |

## Build from Source

### Prerequisites

```bash
# Install Greenforce Clang
bash <(wget -qO- https://raw.githubusercontent.com/greenforce-project/greenforce_clang/refs/heads/main/get_clang.sh)
export PATH="$(pwd)/greenforce-clang/bin:$PATH"

# Install cross-compilers
sudo apt-get install -y gcc-aarch64-linux-gnu binutils-aarch64-linux-gnu \
                        gcc-arm-linux-gnueabi binutils-arm-linux-gnueabi
```

### Build

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

## Release Channels

| Channel | Trigger | Stability |
|---------|---------|-----------|
| **Nightly** | Every push to `Mocchipyon23.2` | Untested — may not boot |
| **Beta** | Manual workflow dispatch | Partially tested |
| **Stable** | Git tag `v*` | Hardware tested ✅ |

## Credits

- **MediaTek** — MT6768 BSP kernel source
- **CIP** — Linux 4.19 stable backports
- **Greenforce Project** — Clang toolchain
- **ReSukiSU** — KernelSU fork
- **maxsteeel** — NoMount
- **R0rt1z2** — Kaeru bootloader
- **osm0sis** — AnyKernel3

## License

This kernel is licensed under the [GNU General Public License v2.0](COPYING).
