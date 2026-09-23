# CHANGELOG — Mocchipyon Edition (MT6768 / Linux 4.19 CIP)

Daftar perubahan, porting, backport security, dan update komponen pada Mocchipyon Kernel.

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
- **Defconfig:**
  - Explicitly set `CONFIG_TOUCHSCREEN_COMMON=y` in `arch/arm64/configs/selene_defconfig` for userspace double-tap node exposure.

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
