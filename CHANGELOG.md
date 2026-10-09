# CHANGELOG — PawwwNunungggg Edition (Xiaomi Selene / MT6768)

Kernel by [@naidrahiqa](https://github.com/naidrahiqa)

---

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
