# CHANGELOG — PawwwNunungggg Edition (Xiaomi Selene / MT6768)

Kernel by [@naidrahiqa](https://github.com/naidrahiqa)

---

## 2026-10-03 — Dynamic Fsync, Boeffla WL Blocker, TCP Westwood+ & TTL Mangling

+ fs: implement Dynamic Fsync 2.0 (bypass fsync while screen on to eliminate I/O lag in MLBB/gaming)
+ power: add Boeffla generic wakelock blocker for MTK modem & Wi-Fi idle sleep drain
+ netfilter: enable xt_HL target (TTL/HL mangling support for tethering bypass)
+ tcp: enable TCP Westwood+ congestion control for unstable mobile connections
+ resukisu: sync upstream to v4.2.0-rc3 (commit 80c0e19, KSU_VERSION 35199)
+ drivers: expose display status via /proc/disp_state & enable DSI ESD check
Note: Dynamic Fsync can be toggled via /sys/kernel/dyn_fsync/dyn_fsync_active. Recommended Zygisk module: Rezygisk/Brezygisk.

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
