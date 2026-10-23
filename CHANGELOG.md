# CHANGELOG — PawwwNunungggg Edition (Xiaomi Selene / MT6768)

Kernel by [@naidrahiqa](https://github.com/naidrahiqa)

---

## 2026-10-23 — CI Dihapus dari Repo Kernel (Overhaul)

+ **ci:** remove all in-tree CI — `.github/workflows/build-all.yml`, `.github/legacy/*`, `.gitlab-ci.yml` (CIP GitLab pipeline), and `scripts/ci/{build-stats,release,notify-release,notify-failure}.sh` (`cc8199384347`):
  + build/release/notification now run **exclusively** from [`naidrahiqa/kernel-ci-kit`](https://github.com/naidrahiqa/kernel-ci-kit) via `workflow_dispatch` (`example-build.yml`) — run + artifact live in the kit repo
  + push to this repository no longer triggers anything; start builds manually with `gh workflow run example-build.yml -R naidrahiqa/kernel-ci-kit`
  + rationale: the `build-all` wrapper burned ~30 min of Actions time per push (even docs-only commits) while the kit can produce the same AnyKernel3 zip on demand
+ **docs:** README CI section, AGENTS.md (context, CI Toolkit, skill table, gotchas) rewritten for the kit-only workflow
+ **reference:** local reference remotes trimmed to `origin` + `upstream` (`mt6768-S/android_kernel_xiaomi_mt6768`) + `creativchic` (`lineage-24.0`) + `cip` — half-configured mirrors (bbr, gale, shockwave, selene-U, ViP3R, android.googlesource common) and the local `fire` remote removed

## 2026-10-18 — FUSE Scoped Storage Fix, Vendor Bugfix & Upstream CIP Sync

+ **drivers/mmc/host/mtk-sd-dbg:** fix race condition and silent out-of-bounds memory corruption in MMC host debug log ring buffer (`__dbg_add_host_log`):
  + unconditional dedicated `msdc_dbg_lock` spinlock protecting ring buffer writes
  + strictly clamp `dbg_host_cnt` against underflow (`< 0`) and overflow (`>= 40000`)
  + sanitize reading bounds with `READ_ONCE()` in `mmc_cmd_dump` and fix `copy_from_user` in `msdc_debug_proc_write`
  + closes Issue `#0025` (root cause of silent panic / unexpected shutdown clusters)
+ **fs/pstore/pmsg:** switch `pmsg_lock` to `rt_mutex` to avoid priority inversion (upstream backport `f9e761541e87` by Google kernel-team) — eliminates UI frame drops/jank when logd and background tasks contend on `/dev/pmsg0`
+ **mm/shmem:** fix data race in `shmem_getattr()` by wrapping `generic_fillattr()` with `inode_lock_shared()` / `inode_unlock_shared()` (backport `9fb9703cd43e`)
+ **drivers/misc/mediatek/spi_slave:** fix invalid `kfree` on static `spislv_chip_info` struct in `spi_slave_remove` — prevents Bad SLAB free / Kernel Panic during device unbind/teardown
+ **net/wireless:** stop NAN and P2P in `__cfg80211_leave` (upstream backport `e1696c8bd005`) — prevents race / `__cfg80211_disconnected` WARN_ON when hotspot/Wi-Fi is toggled off
+ **net/bluetooth:** backport L2CAP concurrency and lifecycle fixes from CIP:
  + `e2b0b3461e9d`: hold connection reference to fix UAF in channel timeout (`l2cap_chan_timeout`)
  + `35e95dbb72e5`: serialize accept queue access and pin channel to eliminate UAF in `l2cap_sock_cleanup_listen` vs `l2cap_conn_del`
+ **net/ipv6:** use RCU-safe `ipv6_get_lladdr()` in `mcast` (fix `26394fc118d6`) — prevents General Protection Fault in `mld_ifc_work`
+ **net/netfilter:** CIP backport security and boundary hardening:
  + `d182744a2e54`: widen NAT rewrite delta to s32 in `sip_help_tcp()` to prevent buffer wrap and UAF in SIP header parser
  + `b652ba518f2f`: mark malformed IPv6 extension headers for hotdrop in ip6tables
  + `5ad5de1a1c59`: replace unsafe `sprintf` with `scnprintf` in conntrack SIP NAT helper to prevent stack OOB
  + `2ba8bebf745b`: restrict `xt_mac`, `xt_owner`, `xt_physdev`, `xt_realm` to inet family
+ **net/ipv4 & core:** bound `tcp_reordering` sysctl writes and compute `size_needed` as u64 in `tcp_mtu_probe()`; prevent refcount warning on dying rule in `fib_rules_dump()`; introduce `skb_pull_data` helper
+ **scripts/fix-fuse-storage.sh:** standalone & daemon script for Android 15/16 Scoped Storage bypass:
  + dynamic multi-user bind-mount `/data/media/<uid>/Android/{data,media,obb}` -> `/storage/emulated/<uid>/Android/{data,media,obb}` with `--make-shared`
  + eliminates `Rejected access to app-private dir on FUSE` (TikTok 0% download & photo save bug) caused by lack of `fuse_bpf.o` in custom ROM APEX
  + auto-heals media DAC permissions (775/664 `media_rw:media_rw` for DCIM, Pictures, Download, etc.) and app cache staging dirs
  + watchdog daemon recovers mounts automatically if MediaProvider or vold remounts storage
  + self-install option (`--install`) via root or ADB host push
+ **scripts/anykernel.sh & ak3:** auto-deploy storage-fix to `/data/adb/boot-completed.d/` and register `/data/adb/modules/storage-fix/` (v1.3) during kernel flash — eliminates need to manually download or flash a separate module zip
+ **defconfig:** remove duplicate `CONFIG_FW_LOADER_USER_HELPER=y` and `CONFIG_IP6_NF_MANGLE=y` overrides in `selene_defconfig` (100% warning-free build configuration)
+ **docs:** update issue `#0003` and skill `storage-scoped` with repository script and automated AnyKernel3 deployment details

## 2026-10-17 — Anti-Root Detection Hardening (Cmdline Spoofing, SELinux-Hide & /proc Hardening)

+ **fs/proc/task_mmu:** anti memory-inspection — filter sensitive VMAs from `/proc/<pid>/maps` and `/proc/<pid>/smaps` for untrusted UIDs (`uid >= 10000`):
  + hides injected libraries and binaries matching `zygisk`, `lsposed`, `shamiko`, `magisk`, `kernelsu`, `bakasu`, `frida`, `xposed`, `libriru`
  + hides mappings originating from `/data/adb/` and `/data/local/tmp/`
  + leaves system services (`uid < 10000`), root (`uid 0`), and ptrace/admin debuggers with full visibility
+ **kernel/module:** sanitize `/proc/modules` for untrusted apps (`uid >= 10000`) — returns empty list so the kernel appears monolithic without LKMs
+ **fs/proc/version:** sanitize `/proc/version` for untrusted apps — strips non-ASCII bytes (e.g. emoji) and replaces custom branding (`PawwwNunungggg`) with clean standard version string
+ **net/unix:** sanitize `/proc/net/unix` for untrusted apps — hides abstract and pathname sockets containing `zygisk`, `magisk`, `frida`, or `lsposed`
+ **fs/proc/cmdline:** sanitize security parameters in `/proc/cmdline` — stream-based zero-allocation filtering for userspace reads:
  + `androidboot.selinux=permissive` → `androidboot.selinux=enforcing` (aligns cmdline string with real Enforcing state)
  + `androidboot.veritymode=disabled` → `androidboot.veritymode=enforcing`
  + `androidboot.verifiedbootstate=orange` → `androidboot.verifiedbootstate=green`
  + `androidboot.vbmeta.device_state=unlocked` → `androidboot.vbmeta.device_state=locked`
+ **bakasu:** default `ksu_selinux_hide_enabled = true` and provide `ksu_selinux_hide_auto_enable()`:
  + auto-engage `selinux_hide` immediately after `apply_kernelsu_rules()` creates `backup_policydb` and during `on_post_fs_data()`
  + prevents `ksu_selinux_hide_drop_backup_if_unused()` from dropping the clean backup policydb at boot completion
  + app UIDs (`uid >= 10000`) evaluating SELinux types (e.g. `u:object_r:ksu_file:s0` probe by Wondr by BNI, issue #0019) get clean `-EINVAL` matching a stock untampered kernel
+ docs: issue `0019` created with evidence from device capture (`logcat.txt` bounded transition rejection & cmdline flags); issue `0018` fix_commit updated to `61e5b261667c`

## 2026-10-16 — Issue #0017 Verified on R04 + Local-Build Toolchain Guard

+ docs: issue `0017` (perf batch — gate `dprec_logger`, drop `cmdq_test.o`, enable ThinLTO) moved `fixed` → **`verified`** — all 6 checklist items passed on hardware, verified against the **CI R04** artifact (commit `b83b9b0b8d8a`, Greenforce Clang 24.0.0), not a local build
+ verify: `cmdq_test_init` **0 hits** in `System.map`, no real undefined symbols; `DISPMSG`/`DISPCHECK`/`dprec_logger` **0 hits** in dmesg (the `g_mobilelog` gate works); camera 0.6X/1.0X/2.0X + display scroll clean, no freeze/force-close
+ **find:** the local build had silently used **system clang 22.1.8** instead of Greenforce 24.0.0 — the `greenforce-clang/` checkout **is** on disk, but its `bin/` was not in `PATH`, so `make` picked up `CC=clang` from `/usr/bin`. No error, build was valid, but **PGO/Polly were silently lost**; the artifact ended up on the device while `uname` still printed the "Greenforce" name
+ scripts: **`check-toolchain.sh`** (new) — local-build guard: checks the `Cirrus` vendor marker in the clang banner, exits 1 when it is not Greenforce (and prints the `PATH` line to fix it). Wired into skill `build-local-test` step 1 & step 2
+ docs: new gotcha in AGENTS.md — "local build looks successful but uses the wrong toolchain"
+ **fix (issue `0018`):** camera/ISP no longer floods dmesg at **±12,000 lines/min** while the camera is in use — four changes, all keyed to the same `ISP_DBG_INT` mask:
  + `camera_isp.h`: drop `#define KERNEL_LOG` — the vendor's "enforce kernel log enable" left `IspInfo.DebugMask = ISP_DBG_INT` as the boot default (same ENG-code-in-user-build class as `cmdq_test.o` in #0017)
  + `camera_isp.c`: one guard at the top of `IRQ_LOG_KEEPER()` — `_LOG_INF`/`_LOG_DBG` entries are no longer buffered (hence never flushed by `ISP_BH_Workqueue`) unless `DebugMask & ISP_DBG_INT`; closes **all 56 ungated call sites** (`P1_SOF`, `CAMA/CAMB PHY cqcnt`, …) in one place. `_LOG_ERR` stays buffered for `ISP_DUMP_ISR_LOG`
  + `camera_isp.c` `ISP_SET_VIR_CQCNT`: success-path `LOG_NOTICE` → `LOG_DBG` — that ioctl alone produced **9,896 lines / 113 s** (48% of the flood); the `copy_from_user failed` error path stays `LOG_NOTICE`
  + `fdvt/4.0/camera_fdvt.c`: per-IRQ `[FDVT] Receive IRQ` `LOG_INF` → `LOG_DBG` (908 lines)
  + runtime behavior is preserved: `ISP_DEBUG_FLAG` ioctl still turns every layer back on for debugging, no rebuild needed
+ docs: issue `0018` created with the exact per-message breakdown from the R04 capture (20,700 lines / 113 s)

> ⚠️ **Local builds:** run `scripts/check-toolchain.sh` **before** `make`.
> An exit 1 means the build will silently fall back to system clang and the
> result is technically valid but without Greenforce optimizations — exactly
> what happened on Oct 15.

## 2026-10-15 — xxKSU Removed, BakaSU Becomes the Single Root Driver

+ drivers: drop `drivers/kernelsu/` (93 files, 17,986 lines) + `scripts/check-xxksu.sh` — xxKSU `backslashxx/KernelSU` v3.3.1 retired permanently, one root driver only
+ drivers: remove the Kconfig choice `ROOT_SOLUTION` (KSU_XXKSU / KSU_BAKASU); keep only `source drivers/bakasu/Kconfig`
+ drivers: `drivers/Makefile` two obj-conditional lines collapse to one — `obj-$(CONFIG_KSU) += bakasu/`
+ defconfig: `CONFIG_KSU_XXKSU=y` → `CONFIG_KSU=y` + `CONFIG_KSU_MANUAL_HOOK=y`; drop `KSU_LSM_SECURITY_HOOKS` & `KSU_HEURISTIC_IN_TREE_BUILD` (xxKSU-only symbols, silently discarded by `olddefconfig`)
+ ci: multibuild 4 variants → **2 variants** (`bakasu` NoMount off, `bakasu-nomount-droidspaces` NoMount on); DroidSpaces is the default defconfig, so it rides along in both variants
+ ci: `release.sh` zip guard `4` → `2` (**blocker bug** — with 2 variants the old guard would have made every release fail to publish), Root Driver note becomes BakaSU `KSU_VERSION=35229`
+ ci: Telegram notifications (`notify-release.sh` / `notify-failure.sh`) → "2 variants", variant labels + env `RES_BAKASU_NMD` aligned with the workflow (previously mismatched → the 2nd variant always showed as `skipped`)
+ ci: `.github/legacy/build.yml` `ln -sf resukisu drivers/kernelsu` block removed (BakaSU is in-tree, no symlink)
+ bakasu: sync upstream 4523 → **4529** (`main@d7260ca1`) — `KSU_VERSION` **35223 → 35229** (formula `30000 + rev-count + 700`)
+ bakasu: 3 kernel commits landed — rewrite `selinux_hide.c` (time side-channel fix, port tiann/KernelSU#3877), sucompat guard when ksud is absent (#597), `context_add_hash` sidtab (#623); 3 userspace commits (ksud cargo deps, manager translations) deliberately not synced
+ docs: skills `xxksu-*` → `bakasu-{integration,version-management,latest-check}`; AGENTS.md + README follow; add the **"manager rejects the kernel"** gotcha

> ⚠️ **Manager:** `KSU_VERSION=35229` must be covered by the manager APK's
> versionCode. The old manager `me.weishu.kernelsu` v3.3.0-70 (`32671`) sits far
> below that → it will be rejected with *"manager needs update"*. The BakaSU
> manager itself is nightly/WIP only (no GitHub Release). Details: `docs/issues/0008`.

## 2026-10-11 — Multibuild 4 Variants (xxKSU/BakaSU × NoMount) + Automatic Releases

+ ci: multibuild 4 variants per push (xxksu-nomount, xxksu, bakasu-nomount, bakasu) — separate sequential jobs (prepare → 4 builds → release)
+ ci: automatic release to `naidrahiqa/selene-releases` named `R##` (sequence via API); the same tag is used in the zip names and the release, shared across all variants
+ ci: Build Statistics per variant (duration + md5) in the step summary, release notes, and Telegram notifications; 1 variant failing = release skipped + per-job status notification
+ ci: kit enhancement — `config_overrides` input to toggle Kconfig per variant
+ bakasu: import BakaSU v4.2.0-rc3 (KSU_VERSION 35223) into `drivers/bakasu/`
+ bakasu: port hostsredirect (CONFIG_KSU_HOSTSREDIRECT) from xxKSU/FolkSU
+ bakasu: Kconfig choice ROOT_SOLUTION (KSU_XXKSU / KSU_BAKASU) in `drivers/Kconfig`
+ bakasu: conditional build via `drivers/Makefile` (obj-$(CONFIG_KSU_XXKSU) / obj-$(CONFIG_KSU_BAKASU))
+ scripts: `check-bakasu.sh` — upstream version check mirroring `check-xxksu.sh`
+ zip naming: `PawwwNunungggg-{variant}-{R##}-{sha7}-{YYYYMMDD}.zip`

## 2026-10-09 — FolkSU Integration & xxKSU Hosts Redirect

+ folksu: migrate root driver from ReSukiSU to FolkSU (LyraVoid/FolkSU@master, v0.1.0-pre6, KSU_VERSION 32742) in manual hook mode
+ xxksu: cherry-pick CONFIG_KSU_HOSTSREDIRECT — in-kernel systemless /system/etc/hosts redirection to /data/adb/hosts for bindhosts mode 3 / AdAway
+ folksu: add FolkSU release key and xxKSU manager key to multi-manager verification table
+ ci: update Telegram release notifications to provide FolkSU Manager APK, NoMount v20, and kernel zip download links
+ scripts: provide scripts/check-folksu.sh and update generate-ksu-notes.sh for FolkSU version management

## 2026-10-04 — ADIOS Hardening, ReSukiSU Sync & ZRAM Default

- mm/sched: revert schedutil rate limits and vm cache tweaks (vfs_cache_pressure, extra_free_kbytes) — caused lag in daily use, A/B verified
+ block: default zram disksize at boot to min(75% total RAM, 4GB) — 6GB unit gets 4GB, 4GB unit gets ~2.7GB; vendor fstab zramsize write now hits EBUSY and is ignored, kernel value wins
+ block: harden ADIOS against request loss — drain plug list when rd pool exhausted instead of requeue+break
+ block: fall back to priority queue when dl_group allocation fails during merge, no more orphaned requests
+ block: track in-flight ownership with rd->counted and add missing .requeue_request hook (fixes MMC requeue leak that stalls batch refill)
+ block: give each latency model its own aggregation buckets, reset under its own update_lock
+ block: clamp batch_limit, lat_target, and global_latency_window sysfs stores against truncation/overflow
+ resukisu: sync upstream to v4.2.0-rc3 (commit 4c5c8ce, KSU_VERSION 35202) — avtab removal length & xperms fix

## 2026-10-03 — Hardware KCAL, vm.swappiness 200, Dynamic Fsync & Boeffla WL Blocker

+ display: implement MediaTek hardware-accelerated KCAL color control (/sys/devices/platform/kcal_ctrl.0/kcal)
+ mm: allow vm.swappiness up to 200 for aggressive ZRAM swapping
+ power: pre-populate default blocked wakelocks (wlan_ipa, wlan_pno_wl, NETLINK) in Boeffla WL blocker
+ fs: implement Dynamic Fsync 2.0 (bypass fsync while screen on to eliminate I/O lag in MLBB/gaming)
+ power: add Boeffla generic wakelock blocker for MTK modem & Wi-Fi idle sleep drain
+ netfilter: enable xt_HL target (TTL/HL mangling support for tethering bypass)
+ tcp: enable TCP Westwood+ congestion control for unstable mobile connections
+ resukisu: sync upstream to v4.2.0-rc3 (commit 80c0e19, KSU_VERSION 35199)
+ drivers: expose display status via /proc/disp_state & enable DSI ESD check
Note: Hardware KCAL supports RGB gain via /sys/devices/platform/kcal_ctrl.0/kcal (compatible with Franco Kernel Manager). Recommended Zygisk module: Rezygisk/Brezygisk.

## 2026-09-27 — Fast Charge Bypass & Scheduler Tuning

+ mtk_charger: bypass thermal HAL limitation clamp (thermal_icl_ua = -1), boost charging to 10W+
- mtk_cooler_backlight: prevent thermal HAL from dimming or turning off LCD panel
+ block: switch default I/O elevator to mq-deadline for eMMC 5.1
+ net: set BBR as default TCP congestion control
+ net: enable QoS qdiscs (CAKE, FQ_CODEL, NETEM)
- ci: remove untested zip broadcast, streamline build notifications

## 2026-09-26 — Upstream lineage-24.0 Sync & Partition Safety

- anykernel: completely remove LK & DTBO flashing logic (strictly flash boot image only)
+ upstream: rebase to lineage-24.0 with CIP 4.19.325 sync
+ nomount: update to NoMount v20 with keyring-based redirection
+ power: enable USB Power Delivery & dual-charger support ala stock
+ camera: restore missing imx355 ultrawide sensor driver

## 2026-09-23 — Boot Stability, Panic Guards & Hardening

+ clk-mt6768: bounded loop for SPM ACK clock spins (fix MTCMOS boot hang)
+ scp: add bounded wait loop and release mutex on timeout (fix SCP IPI deadlock)
+ power/pmic/cmdq/leds: add NULL pointer checks and panic guards
+ arm64: implement clone3 syscall for Android 14-17 Bionic compatibility
+ defconfig: enable CONFIG_COMPAT=y for 32-bit apps and legacy vendor HALs
- dts: restore safe voltage/current limits in selene.dts to prevent brick risk

## 2026-09-19 — Initial Bringup

+ root: integrate ReSukiSU non-GKI manual hook mode
+ systemless: integrate NoMount path redirection
+ base: Linux 4.19.325 CIP LTS for MT6768 / MT6769 (Helio G88)
