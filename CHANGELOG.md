# CHANGELOG — PawwwNunungggg Edition (Xiaomi Selene / MT6768)

Kernel by [@naidrahiqa](https://github.com/naidrahiqa)

---

## 2026-10-15 — xxKSU Dihapus, BakaSU Jadi Satu-Satunya Root Driver

+ drivers: hapus `drivers/kernelsu/` (93 file, 17.986 baris) + `scripts/check-xxksu.sh` — xxKSU `backslashxx/KernelSU` v3.3.1 ditarik permanen, satu root driver saja
+ drivers: Kconfig choice `ROOT_SOLUTION` (KSU_XXKSU / KSU_BAKASU) dihapus; `source drivers/bakasu/Kconfig` saja
+ drivers: `drivers/Makefile` dua baris obj-conditional jadi satu — `obj-$(CONFIG_KSU) += bakasu/`
+ defconfig: `CONFIG_KSU_XXKSU=y` → `CONFIG_KSU=y` + `CONFIG_KSU_MANUAL_HOOK=y`; buang `KSU_LSM_SECURITY_HOOKS` & `KSU_HEURISTIC_IN_TREE_BUILD` (symbol xxKSU-only, `olddefconfig` buang diam-diam)
+ ci: multibuild 4 varian → **2 varian** (`bakasu` NoMount off, `bakasu-nomount-droidspaces` NoMount on); DroidSpaces = default defconfig, jadi melekat di kedua varian
+ ci: `release.sh` guard zip `4` → `2` (**bug blocker** — dengan 2 varian guard lama bikin release gagal terbit), catatan Root Drivers jadi BakaSU `KSU_VERSION=35229`
+ ci: notif Telegram (`notify-release.sh` / `notify-failure.sh`) → "2 variants", label varian + env `RES_BAKASU_NMD` disamakan dengan workflow (sebelumnya mismatch → status varian ke-2 selalu tampil `skipped`)
+ ci: `.github/legacy/build.yml` blok `ln -sf resukisu drivers/kernelsu` dihapus (BakaSU in-tree, tanpa symlink)
+ bakasu: sync upstream 4523 → **4529** (`main@d7260ca1`) — `KSU_VERSION` **35223 → 35229** (rumus `30000 + rev-count + 700`)
+ bakasu: 3 commit kernel masuk — rewrite `selinux_hide.c` (time side-channel fix, port tiann/KernelSU#3877), guard sucompat saat ksud absen (#597), `context_add_hash` sidtab (#623); 3 commit userspace (ksud cargo deps, manager translations) sengaja tidak di-sync
+ docs: skill `xxksu-*` → `bakasu-{integration,version-management,latest-check}`; AGENTS.md + README ikut; tambah gotcha **"manager nolak kernel"**

> ⚠️ **Manager:** `KSU_VERSION=35229` harus ditutupi versionCode manager APK.
> Manager lama `me.weishu.kernelsu` v3.3.0-70 (`32671`) jauh di bawah itu →
> akan menolak dengan *"manager needs update"*. BakaSU manager sendiri hanya
> nightly/WIP (tidak ada GitHub Release). Detail: `docs/issues/0008`.

## 2026-10-11 — Multibuild 4 Varian (xxKSU/BakaSU × NoMount) + Release Otomatis

+ ci: multibuild 4 varian per push (xxksu-nomount, xxksu, bakasu-nomount, bakasu) — job terpisah berurutan (prepare → 4 build → release)
+ ci: release otomatis ke `naidrahiqa/selene-releases` dengan nama `R##` (urutan via API); tag dipakai di nama zip & release, sama semua varian
+ ci: Build Statistics per varian (durasi + md5) di step summary, release notes, dan Telegram notif; gagal 1 varian = release di-skip + notif status per job
+ ci: kit enhancement — `config_overrides` input untuk toggle Kconfig per varian
+ bakasu: import BakaSU v4.2.0-rc3 (KSU_VERSION 35223) ke `drivers/bakasu/`
+ bakasu: port hostsredirect (CONFIG_KSU_HOSTSREDIRECT) dari xxKSU/FolkSU
+ bakasu: Kconfig choice ROOT_SOLUTION (KSU_XXKSU / KSU_BAKASU) di `drivers/Kconfig`
+ bakasu: conditional build via `drivers/Makefile` (obj-$(CONFIG_KSU_XXKSU) / obj-$(CONFIG_KSU_BAKASU))
+ scripts: `check-bakasu.sh` — upstream version check mirror `check-xxksu.sh`
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
