# Mocchipyon Kernel

Custom kernel for **Xiaomi Redmi 10 / Redmi 10 2022 (Selene)** — MediaTek MT6768 (Helio G88)

> ⚠️ **Status: Unstable / Porting** — Not yet ready for daily use.

| | |
|---|---|
| **Kernel** | Linux 4.19.325 (CIP stable backport) |
| **Base** | LineageOS 23.2 (Android 16) / LineageOS 24.0 (Android 17) |
| **Branches** | `Mocchipyon24.0` (A17 base, **primary/default**) / `Mocchipyon23.2` (A16 base, frozen) |
| **Root** | [ReSukiSU](https://github.com/ReSukiSU/ReSukiSU) (manual hook mode) |
| **Systemless** | [NoMount v20](https://github.com/maxsteeel/nomount) |
| **Bootloader** | Stock Little Kernel (LK) |
| **Toolchain** | [Greenforce Clang](https://github.com/greenforce-project/greenforce_clang) (PGO+ThinLTO+O3+Polly) |

## Download

📦 **[GitHub Releases](../../releases)** — Stable and beta builds

Nightly builds are available as GitHub Actions artifacts (expires after 90 days).

## Features

- 🚀 **BBR** TCP congestion control (default)
- 🔐 **WireGuard** VPN built-in
- ⚡ **LZ4/LZ4HC** zRAM compression
- 📦 **DroidSpaces** container support
- 🛡️ **NoMount** systemless path redirection (keyring-based)
- 👑 **ReSukiSU** KernelSU root (manual hook mode)

## Install

1. Download the latest `.zip` from [Releases](../../releases)
2. Boot into custom recovery (TWRP / OrangeFox)
3. Flash the AnyKernel3 zip
4. Reboot

> **Note:** AnyKernel3 only flashes the kernel into the boot image ramdisk. It does not overwrite bootloader (LK) or DTBO partitions.

## Supported Devices

| Codename | Device | Status |
|----------|--------|--------|
| `selene` | Xiaomi Redmi 10 / Redmi 10 2022 / Redmi 10 Prime (Helio G88) | Primary |
| `lancelot` | Xiaomi Redmi 9 (Helio G80) | Untested |
| `merlin` | Xiaomi Redmi Note 9 (Helio G85) | Untested |

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
| **Nightly** | Every push to `Mocchipyon24.0` | Untested — may not boot |
| **Beta** | Manual workflow dispatch | Partially tested |
| **Stable** | Git tag `v*` | Hardware tested ✅ |

Notifikasi Telegram dua fase: build sukses hanya mengirim singkat **tanpa link
download**; pengumuman lengkap dengan tombol ⬇️ Download dikirim lewat
`gh workflow run "Announce Tested Build"` setelah build dites & booting aman.

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
