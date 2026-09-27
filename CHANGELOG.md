# CHANGELOG — PawwwNunungggg Edition (MT6768 / Linux 4.19 CIP)

Daftar perubahan, porting, backport security, dan update komponen pada PawwwNunungggg Kernel.

## 2026-09-27 — CI: Hentikan Broadcast Zip Sebelum Tes + Config Batch Gaming/Perf

- **Notif disederhanakan jadi 4** (`.github/scripts/notify-telegram.sh`): (1) `start`, (2) `failed` = ringkasan **+ baris error pertama** (+ detail log ke `Nai Error Dump`), (3) `success` = teks singkat "✅ Build succeeded" ke CI topic, (4) file zip + changelog + SHA-256 pendek + tombol ⬇️ Download (link Actions run) ke channel private `Nai project update` — tanpa banner "belum diuji". Workflow two-phase `notify-tested.yml` + status `tested` **dihapus**. **Concurrency:** `build.yml` kini `cancel-in-progress` (push beruntun cuma build terakhir) & notif result di-guard `success() || failure()` biar run cancel tidak kirim notif.
- **Config batch** (`arch/arm64/configs/selene_defconfig` + `drivers/misc/mediatek/Kconfig.default`), build lokal hijau:
  - `CONFIG_CMDLINE_EXTEND=y` — sebelumnya `CMDLINE_FROM_BOOTLOADER` → string `vmalloc=496M slub_max_order=0 slub_debug=O` bisa terbuang saat LK sudah melewatkan cmdline sendiri (bug identik Phrolova v0.9.12).
  - Default I/O scheduler cfq → **deadline** (`CONFIG_DEFAULT_DEADLINE=y`) — optimal buat eMMC 5.1 legacy; `MQ_IOSCHED_KYBER` dimatikan (tak terpakai).
  - **BBR benar-benar default:** seed lama `DEFAULT_TCP_CONG="bbr"` ternyata inert (string promptless hasil hitungan choice) → set member `CONFIG_DEFAULT_BBR=y`; `TCP_CONG_BIC` dimatikan + hapus `select TCP_CONG_BIC` dari `MTK_ANDROID_DEFAULT_SETTING` — vendor `networksetting.rc` Huaqin yang menulis `bic` kini gagal senyap dan fallback ke bbr.
  - Qosc toolbox: `NET_SCH_NETEM`, `NET_SCH_FQ_CODEL`, `NET_SCH_CAKE` + `CGROUP_NET_CLASSID` — tool bufferbolt/QoS & klasifikasi traffic Android buat gaming sambil download.
- **QC/HVDCP (audit, tanpa perubahan kode):** alur deteksi dipetakan — BC1.2 jalan di SMB1351 (`primary_chg`, `qcom,bc12_supported`) dengan enable saat probe (`/*enable QC*/`), jalur BQ25890 gated `id_dis==3`; `charger_dev_check_hv_charging` tak dipanggil di kedua tree (reference pun sama). Kesimpulan sementara: `dhx--hvdcp:0` paling mungkin artinya charger tes memang non-QC — menunggu tes dengan adapter QC berlabel (mis. Xiaomi 18W) + `dmesg` live.
- **Offline charging (LK):** tetap terpisah dari kernel (jalur bootloader) — belum lulus tes.

## 2026-09-27 — Fast Charge: Bypass Thermal Mitigation Clamp + Backlight Clamp (Port Phrolova v0.9.3)

- **Masalah:** fast charge "stuck ~1W" padahal charger dinding terdeteksi & animasi jalan. Bukti live: cooling device `battery` diam di `system_temp_level=12` → tabel `thermal_mitigation_*` menjegal input current (QC3 level 12 = ~975mA, DCP = 1.6A) meski suhu cell aman. Akar masalah: thermal HAL userspace menulis `CHARGE_CONTROL_LIMIT` → `system_temp_level` naik.
- **Fix 1 (fast charge):** `drivers/power/supply/mediatek/charger/mtk_charger.c` — `charger_manager_set_prop_system_temp_level()` kini set `thermal_icl_ua = -1` permanen (clamp userspace di-bypass). Port dari reference `android_kernel_xiaomi_selene` **v0.9.3** ("Fast Charge Tanpa Module", live-verified di selene). Keamanan tetap: sw_jeita runtime (T4=45°C) + hardware JEITA bq2589x masih membatasi CC/CV berdasar suhu cell asli — yang dilepas hanya throttle policy-level.
- **Fix 2 (thermal layar):** `drivers/misc/mediatek/thermal/mtk_cooler_backlight_cus.c` — `mtk_cl_backlight_set_cur_state()` hanya menghormati reset path (`state == max`), write di bawah max diabaikan → thermal HAL tidak bisa mem-dim/mematikan panel sendiri (root cause "layar mati sendiri" pada reference). Mitigasi panas asli tetap lewat cpufreq/GPU cooler.
- **Hasil tes (flash lokal `fastcharge-v093`):** arus charge **1W → 10W** (DCP 5V×2A, cocok `ac_charger_current=2050000`); port laptop CDP 952mA (sebelumnya ~300mA kena clamp). Log verifikasi: `system_temp_level:12 thermal_icl_ua:-1`.
- **Sisa:** handshake QC/HVDCP belum menyala (`dhx--hvdcp:0` — charger tes kemungkinan polos 5V/2A, atau handshake perlu dibedah di `mtk_chg_type_det.c`) → target 18W belum tercapai. **Offline charging** (jalur LK bootloader, di luar kernel) terpisah dan masih dalam pengamatan — belum lulus tes 2 jam.
- **Commit:** `c77aa0a6941a` (charger clamp), `dbdb7d488598` (backlight clamp).

## 2026-09-26 — Fast Charge: Restock Config Charger ala Stock

- **Masalah:** fast charge tidak aktif di device (lama, bukan regresi sync — defconfig charger identik sebelum & sesudah sync).
- **Diff vs stock 4.14:** stock selene menyetel `CONFIG_USB_POWER_DELIVERY=y` (negosiasi PD 9V lewat TCPC) dan `CONFIG_MTK_DUAL_CHARGER_SUPPORT=y` (jalur charger IC master+slave) — keduanya hilang di `selene_defconfig` kita (symbol ada di tree, cuma gak diset).
- **Fix:** keduanya di-enable (2 baris defconfig), build lokal bersih, objek `mtk_pd_adapter.o` & `mtk_dual_switch_charging.o` masuk image. Pump Express tetap mati — memang mati juga di stock (fast charge stock lewat PD/dual-charger, bukan PE).
- **Status:** menunggu validasi hardware (flash nightly + cek `dmesg` charger & tegangan input).

## 2026-09-26 — Sync dengan Upstream lineage-24.0 (Force-Update)

- **Rebase ke Upstream Baru:** `PawwwNunungggg24.0` di-rebase ke `mt6768-S/lineage-24.0` yang di-rewrite upstream — dapat SUSFS 2.3.0 (runtime `fs/susfs.c`), sdcardfs, focaltech double-tap, perubahan Xiaomi eccci/imgsensor, fix watermark & blk-mq multi-queue.
- **Driver Ultrawide imx355 Dipulihkan:** rewrite upstream menghapus driver `imx355_sunny`/`imx355_aac` tapi `selene_defconfig` tetap mereferensikannya (build error `No rule to make target .../imx355_aac.../Makefile`) — 10 file driver dikembalikan dari state sebelum sync.
- **Tracing Fix:** upstream "Prepare for Product" menurunkan `KPROBE_EVENTS`/`UPROBE_EVENTS` dari `default y` ke `default n`; simbol `CONFIG_TRACING` (promptless) jadi tak ter-select → guard `trace_printk` di `kernel.h` mati → `cmdq_record.c` gagal compile (implicit declaration). Diset explicit di `selene_defconfig`.
- **CIP Ternyata Sudah Sinkron:** tip `linux-4.19.y-cip` = cip136 (4.19.325, 11 Sep 2026) = persis `localversion-cip` kita — tidak ada backport baru yang perlu ditarik.

## 2026-09-26 — Two-Phase Notifications, CI Hardening & Branch Restructure

- **Two-Phase Telegram Notifications:** `.github/scripts/notify-telegram.sh`, `.github/workflows/notify-tested.yml`
  - Notifikasi `success` ke topic Selene CI sekarang singkat: hanya hasil build, **tanpa link download, tanpa changelog, tanpa tombol** — zip tetap dikirim ke private channel untuk dites.
  - Status baru `tested` + workflow `Announce Tested Build` (`gh workflow run ... -f notes="booting aman"`): pengumuman lengkap dengan changelog, catatan testing, dan tombol ⬇️ Download, dikirim **hanya setelah build dites di device & booting aman**.
  - Download URL di-resolve otomatis: GitHub Release jika ada, selain itu halaman Actions run (artifact zip).
- **False-Success Notification Fix:** `.github/workflows/build.yml`
  - `Final check` kini menghormati `job.status` — kegagalan step verify/package tidak lagi mengirim notifikasi "sukses".
  - Klasifikasi `CI STEP ERROR` saat make sukses tapi step berikutnya gagal (bukan "compile error").
- **Branch Restructure:**
  - Default branch pindah ke `PawwwNunungggg24.0` (fokus development); `PawwwNunungggg23.2` di-freeze tanpa build CI.
- **Dead Makefile References Removed:** 13 file Makefile (mis. `SOLOMON/`, `mt8167/`) — memperbaiki `make mrproper`.
- **Zip Verification False Positive Fix:** `Image.gz-dtb` tidak lagi terdeteksi sebagai file `dtb` berbahaya di check verifikasi zip.
- **CI Reliability:** Perbaikan installer & caching fallback Greenforce Clang; nama file paket & notifikasi menyertakan branch dan target Android.
- **Unbrick (BROM) Skill:** `.opencode/skills/unbrick-brom/SKILL.md` — playbook recovery device mati total via mtkclient (restore LK dua slot, backup partisi, error DRAM/udev).

## 2026-09-26 — Fix Brick Risk: Remove LK & DTBO Flashing from AnyKernel3

- **AnyKernel3 Boot-Only Flashing Restored:** `scripts/anykernel.sh`
  - Completely removed Kaeru LK flashing logic (`dd if=lk_a.img of=/dev/block/by-name/lk*`).
  - Restored standard AnyKernel3 boot-only install (`dump_boot; write_boot;`), only modifying the boot image ramdisk.
  - Set `is_slot_device=auto;` for reliable automatic slot detection.
- **CI / Build Workflow Safety Fixes:** `.github/workflows/build.yml`
  - Removed bundling of `mt6768.dtb`, `selene.dtbo` (`dtbo.img`), and `kaeru_selene.bin` (`lk_a.img`) into the AnyKernel3 zip.
  - Hardened zip verification check to strictly reject `lk`, `dtbo`, and `dtb` files to prevent foreign partition overwriting.
  - Removed `CONFIG_KAERU_COMM` from required CI check.
- **Defconfig & Artifacts Cleanup:**
  - Disabled `CONFIG_KAERU_COMM` in `arch/arm64/configs/selene_defconfig`.
  - Deleted dangerous prebuilt `kaeru/kaeru_selene.bin` binary from repository.
  - Updated Telegram notifications and documentation to reflect stock LK and boot-only flashing.

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
- **PawwwNunungggg Feature Parity on Lineage 24.0:**
  - Enabled `CONFIG_TCP_CONG_BBR=y` (default TCP congestion control).
  - Enabled `CONFIG_CRYPTO_LZ4=y` and `CONFIG_CRYPTO_LZ4HC=y` (zRAM compression).
  - Enabled `CONFIG_WIREGUARD=y`.
  - Enabled `CONFIG_TOUCHSCREEN_COMMON=y` for double-tap wake support.
  - Enabled `CONFIG_TRACEPOINTS=y`, `CONFIG_MMC_FFU=y`, `CONFIG_INCREMENTAL_FS=y`.
  - Expanded log buffer to 2MB (`CONFIG_LOG_BUF_SHIFT=21`).
- **CI / Build Workflow Fix:**
  - Updated `.github/workflows/build.yml` config verification to support both `CONFIG_SND_SOC_AW87XXX` and `CONFIG_SND_SOC_AW87559` across branches.
  - Removed forced selection of `INIT_ON_ALLOC_DEFAULT_ON` and `BUG_ON_DATA_CORRUPTION` from `drivers/misc/mediatek/Kconfig.default`, resolving CI build failure on dangerous config check.
  - Hardcoded fallback Telegram channel IDs (`CHANNEL_ID=-1003752197403`) in `build.yml` and `notify-telegram.sh` to guarantee kernel zip delivery to Nai project update channel.

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

## 2026-09-27 — ReSukiSU v4.2.0-rc3 Upstream (KSU_VERSION 35184)

- **ReSukiSU v4.2.0-rc3 (`fa8311f6`, KSU_VERSION 35184):**
  - Synced driver with upstream ReSukiSU `v4.2.0-rc3` + latest commits from `main` (commit `fa8311f6`).
  - Total upstream commits: 4484.
  - Pinned version in Kbuild: `KSU_LOCAL_VERSION := 4484`, `KSU_TAG_NAME := v4.2.0-rc3`, `KSU_COMMIT_SHA := fa8311f6` (`30000 + 4484 + 700 = 35184`).
  - Required Manager: ReSukiSU Manager matching KSU_VERSION `35184` ([GitHub Release](https://github.com/ReSukiSU/ReSukiSU/releases/tag/v4.2.0-rc3)).
