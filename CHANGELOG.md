# CHANGELOG — Mocchipyon Edition (MT6768 / Linux 4.19 CIP)

Daftar perubahan, porting, backport security, dan update komponen pada Mocchipyon Kernel.

## 2026-09-26 — ReSukiSU v4.2.0-rc3, NoMount & DroidSpaces Container Support

- **ReSukiSU v4.2.0-rc3 (`0e469895`, KSU_VERSION 35179):** `resukisu/`
  - Upgraded kernel driver to upstream ReSukiSU `v4.2.0-rc3` (`0e4698951b8e`, 4479 commits).
  - Version calculation: `30000 + 4479 + 700 = 35179`.
  - Pinned version metadata in `resukisu/Kbuild` (`KSU_LOCAL_VERSION := 4479`, `KSU_TAG_NAME := v4.2.0-rc3`, `KSU_COMMIT_SHA := 0e469895`).
  - Corrected `resukisu/include/uapi` symlink to point to local `../uapi`.
  - Fixed credential handling during manager discovery (`override_creds(ksu_cred)`) and cleaned throne tracking.
- **NoMount v20 Systemless Redirection:**
  - Verified and enabled `CONFIG_NOMOUNT=y` in `arch/arm64/configs/selene_defconfig`.
- **DroidSpaces Container Support:**
  - Added required container runtime configs to `arch/arm64/configs/selene_defconfig`:
    - Namespaces (`CONFIG_NAMESPACES=y`, `PID_NS`, `UTS_NS`, `IPC_NS`, `NET_NS`, `USER_NS`).
    - Cgroups (`CONFIG_CGROUPS=y`, device, pids, memcg, sched, fair group sched, freezer, net_prio).
    - Networking (`CONFIG_VETH=y`, `BRIDGE`, `NETFILTER`, `BRIDGE_NETFILTER`, `NF_CONNTRACK`, iptables, NAT, tables, masquerade).
    - Filesystem (`CONFIG_DEVTMPFS=y`, `OVERLAY_FS`, `TMPFS_POSIX_ACL`, `TMPFS_XATTR`).
    - Security & IPC (`CONFIG_SECCOMP=y`, `SECCOMP_FILTER`, `SYSVIPC`, `POSIX_MQUEUE`).
- **Mocchipyon Feature Parity on Lineage 24.0:**
  - Enabled `CONFIG_TCP_CONG_BBR=y` (default TCP congestion control).
  - Enabled `CONFIG_CRYPTO_LZ4=y` and `CONFIG_CRYPTO_LZ4HC=y` (zRAM compression).
  - Enabled `CONFIG_WIREGUARD=y`.
  - Enabled `CONFIG_TOUCHSCREEN_COMMON=y` for double-tap wake support.
  - Enabled `CONFIG_TRACEPOINTS=y`, `CONFIG_MMC_FFU=y`, `CONFIG_INCREMENTAL_FS=y`.
  - Expanded log buffer to 2MB (`CONFIG_LOG_BUF_SHIFT=21`).
- **CI / Build Workflow Fix:**
  - Updated `.github/workflows/build.yml` config verification to support both `CONFIG_SND_SOC_AW87XXX` and `CONFIG_SND_SOC_AW87559` across branches.

## 2026-09-23 — Boot Stability, Panic Guards & Subsystem Hardening

- **MTCMOS Infinite Spin Prevention:** `drivers/clk/mediatek/clk-mt6768-pg.c`
  - Replaced 73 unbounded `while` loops waiting for MTCMOS ACKs with bounded `spm_wait_ack()` macro (`SPM_ACK_MAX_SPINS = 1000000u`).
  - Prevents silent freeze during early boot before `timer_probe()` without crashing or hanging the processor.
- **Early Probe NULL Pointer & Panic Guards:**
  - `drivers/misc/mediatek/base/power/upower_v2/mtk_unified_power.c`: Guarded `upower_get_tbl_ref()` against missing SSPM reserved memory to prevent zero-address write crash.
  - `drivers/misc/mediatek/cmdq/v3/cmdq_helper_ext.c`: Guarded `mdp_pool_alloc_impl()` against uninitialized DMA pools.
  - `drivers/misc/mediatek/pmic/mt6358/v1/pmic_irq.c`: Added NULL check on `pmic_dev` before accessing parent virq in `pmic_enable_interrupt()`.
  - `drivers/misc/mediatek/spi_slave_drv/spi_slave.c`: Added NULL check on `slv_data.spi` in `spislv_init()` returning `-ENODEV`.
  - `drivers/misc/mediatek/video/mt6768/dispsys/ddp_disp_bdg.c`: Checked return value of `spislv_init()` in `bdg_is_bdg_connected()` to prevent calling `spi_sync(NULL)`.
  - `drivers/misc/mediatek/leds/mt6768/ktd3136_bl.c`: Propagated `ktd3137_class` errors and prevented NULL dereference in `sysfs_create_group()`.
- **SCP IPI Deadlock Prevention:** `drivers/misc/mediatek/scp/cm4/v01/scp_ipi.c`
  - Bounded wait loop in `scp_ipi_send()` using `SCP_IPI_WAIT_MAX_SPINS` and released `scp_ipi_mutex` on timeout to avoid whole-system deadlock.
- **Clone3 & Modern Syscall ABI Support:**
  - Implemented `copy_thread_tls` for ARM64 process cloning.
  - Validated stack direction and arguments in `clone3()`.
  - Switched `clone3()` to `copy_struct_from_user()` to ensure compatibility with modern Android Bionic.
- **Clang CFI Hardening:**
  - Fixed backlight callback pointer signature mismatch in `mtk_leds`.
  - Fixed `rdma_ioctl` function pointer signature mismatch in DDP video dispatch.
- **Defconfig & Architecture Hardening:**
  - Added `CONFIG_COMPAT=y` in `arch/arm64/configs/selene_defconfig` to enable 32-bit EL0 userspace support (required for 32-bit Android applications and proprietary 32-bit vendor HALs).
  - Explicitly set `CONFIG_KSU_MULTI_MANAGER_SUPPORT=y` to support alternate KernelSU managers.
  - Explicitly set `CONFIG_TOUCHSCREEN_COMMON=y` for userspace double-tap node exposure.
- **Charger DTS Hardware Safety:** `arch/arm64/boot/dts/mediatek/selene.dts`
  - Restored `pd_vbus_upper_bound` to `<5000000>` (5V) and `non_std_ac_charger_current` to `<500000>` (500mA) to eliminate overvoltage brick risks identified during hardware safety audit.

## 2026-09-22 — ReSukiSU v4.2.0-rc2 Upstream (KSU_VERSION 35160)

- **ReSukiSU v4.2.0-rc2 (`5cfdd725`, KSU_VERSION 35160):** `resukisu/`
  - Synced driver with upstream ReSukiSU `v4.2.0-rc2` + latest commits from `main` (commit `5cfdd725`).
  - Total upstream commit count: 4460.
  - **Critical Version Pin Fix:** Pinned fallback version in `resukisu/Kbuild` (`KSU_LOCAL_VERSION := 4460`, `KSU_TAG_NAME := v4.2.0-rc2`, `KSU_COMMIT_SHA := 5cfdd725`). Memperbaiki issue di mana dynamic `git rev-list --count HEAD` sebelumnya menghitung total commit kernel Linux (834.314 commit) sehingga KSU_VERSION melonjak ke 865.014. Formula benar: `30000 + 4460 + 700 = 35160`.
  - Updated notification script `.github/scripts/notify-telegram.sh` to extract and display both tag and version code (`v4.2.0-rc2 (35160)`).
  - Added `.github/scripts/generate-ksu-notes.sh` and skill `.opencode/skills/ksu-version-management/SKILL.md`.

## 2026-09-22 — CI & Telegram Notifications Rework

- **Dual-target Telegram notifications:**
  - Build alerts, status, and changelog sent to CI topic in supergroup (`TOPIC_CI=32`).
  - Kernel zip (`.zip`) exclusively dispatched as document to private release channel (`TELEGRAM_CHANNEL_ID`).
  - Replaced markdown formatting with HTML parse mode to eliminate unescaped character parsing failures.
  - Hardcoded topics directly in workflow script to bypass GitHub secrets restrictions.

## 2026-09-19 — NoMount v20 & ReSukiSU Manual Hook Integration

- **Systemless Path Redirection:** Integrated NoMount v20 (`maxsteeel/nomount`) with keyring-based control.
- **Root Solution:** Integrated ReSukiSU with non-GKI manual hook mode (`CONFIG_KSU_MANUAL_HOOK=y`).
