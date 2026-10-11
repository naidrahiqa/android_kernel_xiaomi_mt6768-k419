# PawwwNunungggg Kernel

Custom **Linux 4.19** kernel for the **Xiaomi Redmi 10 2022** (codename **selene**,
MediaTek MT6769Z / Helio G88) <!-- TODO: verify exact SoC variant (MT6769Z vs MT6768) -->,
targeting **LineageOS 24.0 (Android 17)** and other 4.19-based AOSP ROMs
(LineageOS 20+, Android 13+) <!-- TODO: verify tested ROM matrix -->.
Non-GKI, single universal build for all selene variants, with an in-tree
KernelSU-based root driver (xxKSU) and systemless modification support (NoMount).

## Status & version

| | |
|---|---|
| Base | Linux **4.19.325** + CIP LTS (`-cip136`, `-st20`) |
| Version | **v0.1.0** ("Kucing") — **UNSTABLE / porting** |
| Active branch | `PawwwNunungggg24.0` |
| `uname -r` | `4.19.325-PawwwNunungggg-cip136-st20` |
| Root driver | xxKSU (backslashxx/KernelSU) **v3.3.0-70**, in-tree |
| License | GPL-2.0 only (see `COPYING`) |

## Features

### Root & systemless

- **xxKSU root driver** in-tree at `drivers/kernelsu/` (`CONFIG_KSU=y`) —
  backslashxx/KernelSU `v3.3.0-70`, manual hook mode.
- **Hosts redirect** (`CONFIG_KSU_HOSTSREDIRECT=y`) — in-kernel systemless
  `/system/etc/hosts` → `/data/adb/hosts` redirection (bindhosts mode 3 / AdAway).
- **NoMount** (`CONFIG_NOMOUNT=y`) — systemless path redirection and virtual
  file injection without mounting, keyring-based control.

### I/O & memory

- **ADIOS** I/O scheduler (adaptive deadline, ported from Linux 6.12),
  hardened against request loss; **mq-deadline** is the default elevator
  for eMMC 5.1 (`CONFIG_MQ_DEADLINE_DEFAULT=y`).
- **ZRAM** default `disksize` at boot = `min(75% RAM, 4GB)` — vendor fstab
  `zramsize` write hits `EBUSY` and the kernel value wins.
- **`vm.swappiness` up to 200** for aggressive ZRAM swapping.
- **Dynamic Fsync 2.0** (`CONFIG_DYNAMIC_FSYNC=y`) — bypasses fsync while the
  screen is on to reduce I/O lag, flushes on screen off.
- `KSM`, `zram` writeback, `zsmalloc`, F2FS compression (LZO/LZ4/ZSTD)
  (`CONFIG_KSM=y`, `CONFIG_ZRAM_WRITEBACK=y`).

### Networking

- **BBR** as default TCP congestion control (`CONFIG_DEFAULT_BBR=y`);
  Westwood+ and others compiled in (`CONFIG_TCP_CONG_WESTWOOD=y`).
- QoS qdiscs: **CAKE**, **FQ_CODEL** (default), **NETEM**, FQ
  (`CONFIG_NET_SCH_*`, `CONFIG_DEFAULT_FQ_CODEL=y`).
- **TTL/HL mangling** (`CONFIG_NETFILTER_XT_TARGET_HL=y`) for tethering TTL bypass.
- **WireGuard** (`CONFIG_WIREGUARD=y`), nftables, TPROXY, socket match, mangle tables.
- WoWLAN keepalive, Bluetooth audio transport (`CONFIG_MTK_WLAN_WOWLAN_KEEPALIVE`,
  `CONFIG_MTK_BT_AUDIO_TRANSPORT`).

### Power & charging

- **Fast charge** — bypasses the thermal HAL `charge_control_limit` clamp
  (`thermal_icl_ua = -1`) so charging can reach the charger's real capability.
- **USB Power Delivery + dual-charger support** (`CONFIG_USB_POWER_DELIVERY=y`,
  `CONFIG_MTK_DUAL_CHARGER_SUPPORT=y`), charger drivers: MTK, SMB1351, BQ2589X.
- **Boeffla wakelock blocker** (`CONFIG_BOEFFLA_WL_BLOCKER=y`) with defaults
  blocking `wlan_ipa`, `wlan_pno_wl`, `NETLINK`.
- Backlight thermal cooler no longer dims/turns off the LCD via thermal HAL.

### Display

- **Hardware KCAL color control** — RGB gain via
  `/sys/devices/platform/kcal_ctrl.0/kcal` (MediaTek CCORR path).
- Display status exposed at `/proc/disp_state`; DSI ESD check enabled.
- GPU: **Mali Valhall r56p0** DDK (`CONFIG_MTK_GPU_VERSION="mali valhall r56p0"`).

### Compatibility

- **32-bit apps / legacy vendor HALs** — `CONFIG_COMPAT=y`.
- **clone3** syscall for Android 14–17 Bionic compatibility.
- Gamepad / HID support: Xbox (`xpad`), Sony, Steam, Microsoft, `hidraw`,
  `uinput`, joystick.
- BPF JIT always-on (`CONFIG_BPF_JIT=y`), NFC, FM radio, exFAT/NTFS/F2FS,
  incremental FS, pstore (console/pmsg/ram).

## Supported device / ROM

- **Device:** Xiaomi Redmi 10 2022 / Redmi 10 / Redmi 10 Prime — codename
  **selene** (AK3 device check accepts `selene`, `selenes`, `selene_global`,
  `selenes_global`).
- **ROM:** built for **LineageOS 24.0 (Android 17)**; single universal kernel
  targeting AOSP/LineageOS 20+ (Android 13+) and 4.19-based HyperOS/MIUI ports.
  <!-- TODO: verify which ROM versions have actually been booted/tested -->

Nothing beyond the above is claimed or supported.

## Installation

1. **Back up your boot partition first** (e.g. `dd if=/dev/block/by-name/boot_a of=/sdcard/boot-backup.img`).
2. Flash the **AnyKernel3 zip** from the [releases page](https://github.com/naidrahiqa/android_kernel_xiaomi_mt6768-k419/releases)
   in a custom recovery.
3. Reboot.

The zip replaces **only the kernel inside the boot image** — the ramdisk, DTB,
and boot header are preserved. LK and DTBO flashing logic has been completely
removed from the AnyKernel3 config (2026-09-26), and vbmeta is never patched.

> **Warning:** flashing a custom kernel carries brick risk. Never flash LK or
> DTBO from a kernel zip. If the kernel doesn't boot, restore your boot-partition
> backup from recovery.

## Building

Requirements: Clang/LLVM toolchain, `gcc` for host tools, AArch64/ARM32
cross binutils (GNU or LLVM), `bc`, `bison`, `flex`, `libelf`, `openssl`.

```bash
make O=out ARCH=arm64 \
  CC=clang HOSTCC=gcc \
  CROSS_COMPILE=aarch64-linux-gnu- \
  CROSS_COMPILE_ARM32=arm-linux-gnueabi- \
  LD=ld.lld AR=llvm-ar NM=llvm-nm \
  LLVM=1 LLVM_IAS=1 \
  selene_defconfig

make O=out ARCH=arm64 \
  CC=clang HOSTCC=gcc \
  CROSS_COMPILE=aarch64-linux-gnu- \
  CROSS_COMPILE_ARM32=arm-linux-gnueabi- \
  LD=ld.lld AR=llvm-ar NM=llvm-nm \
  LLVM=1 LLVM_IAS=1 \
  -j$(nproc)
```

Project toolchain: [Greenforce Clang](https://github.com/greenforce-project/greenforce_clang)
(PGO + ThinLTO + O3 + Polly).

**CI:** every push to `PawwwNunungggg24.0` triggers `.github/workflows/build.yml`,
a thin wrapper that delegates to [`naidrahiqa/kernel-ci-kit`](https://github.com/naidrahiqa/kernel-ci-kit)
(`example-build.yml`) with the `greenforce-clang` toolchain. The workflow
produces an AnyKernel3 zip named `PawwwNunungggg-{toolchain}-{hash}-{date}-{version}.zip`,
uploads it as an artifact (90 days), and sends a Telegram notification. Manual
runs are available via `workflow_dispatch`.

## Known issues

- **SUSFS inline mode (`CONFIG_KSU_SUSFS`) was permanently removed** — it
  caused a bootloop (logo → reboot); manual hook mode is used instead.
- **Camera image quality regression** vs. pre-bringup builds — open,
  see [`docs/issues/0002-kamera-burik.md`](docs/issues/0002-kamera-burik.md).
- **Root driver migration** to backslashxx/KernelSU is build-verified but not
  yet verified on hardware, see
  [`docs/issues/0009-xxksu-driver-migration.md`](docs/issues/0009-xxksu-driver-migration.md).

Issue history with evidence and fixes: [`docs/issues/`](docs/issues/README.md).

## Credits

- **Linux kernel** & **Linux CIP** project — base 4.19.325 LTS tree
- **mt6768-S** — upstream Xiaomi MT6768 kernel tree
- **backslashxx/KernelSU (xxKSU)** — root driver; earlier iterations:
  **ReSukiSU**, **LyraVoid/FolkSU**
- **NoMount** — systemless path redirection
- **ADIOS** — adaptive deadline I/O scheduler (ported from Linux 6.12)
- **Boeffla** — generic wakelock blocker
- **osm0sis** — AnyKernel3
- **Greenforce Project** — Clang/LLVM toolchain
- **[@naidrahiqa](https://github.com/naidrahiqa)** — kernel maintainer

## Links

- [Releases](https://github.com/naidrahiqa/android_kernel_xiaomi_mt6768-k419/releases)
- [Changelog](CHANGELOG.md)
- [Issue tracker](docs/issues/README.md)
- [kernel-ci-kit](https://github.com/naidrahiqa/kernel-ci-kit)
# trigger

