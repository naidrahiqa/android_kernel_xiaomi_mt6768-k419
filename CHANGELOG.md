# CHANGELOG — PawwwNunungggg Edition (Xiaomi Selene / MT6768)

Catatan perubahan, fitur baru, optimasi performa, dan update upstream pada Kernel PawwwNunungggg.

---

## 2026-10-03 — Dynamic Fsync, Boeffla WL Blocker, TCP Westwood+ & TTL Mangling

- **Dynamic Fsync 2.0 (Flar2):** Bypass synchronous write saat layar aktif untuk performa I/O maksimal (mencegah lag loading screen di MLBB/game), auto-flush ke storage saat layar mati.
- **Boeffla Wakelock Blocker:** Kontrol via sysfs untuk memblokir wakelock modem/Wi-Fi MTK yang boros daya saat sleep.
- **TTL / Hop Limit Mangling (`xt_HL`):** Dukungan iptables/ip6tables untuk bypass kuota tethering/hotspot operator.
- **TCP Westwood+:** Alternatif algoritma TCP congestion control yang optimal untuk jaringan seluler tidak stabil.
- **ReSukiSU v4.2.0-rc3 Sync:** Pin upstream commit `80c0e19` (KSU 35199) dengan perbaikan `override_creds` pada pembacaan allowlist.
- **Display & Panel:** Expose status panel via `/proc/disp_state` dan DSI ESD check pada panel k19a.

## 2026-09-27 — Fast Charge Bypass & Scheduler Tuning

- **Fast Charge Fix:** Bypass thermal HAL limitation clamp (`thermal_icl_ua = -1`), charging naik dari 1W ke 10W+ tanpa merusak proteksi hardware JEITA.
- **Layar Mati Fix:** Cegah thermal HAL mematikan atau meredupkan panel LCD secara paksa.
- **I/O & Scheduler:** Default scheduler beralih ke `mq-deadline`, aktifkan BBR default, dan tambah tools QoS (`CAKE`, `FQ_CODEL`, `NETEM`).
- **CI Notifikasi:** Ringkasan build lebih ramping dengan link langsung ke log dan artifact.

## 2026-09-26 — Sync Upstream lineage-24.0 & Partisi Safety

- **Safety Critical:** Hapus total flash LK dan DTBO dari AnyKernel3 (hanya flash `boot.img` untuk mencegah brick).
- **Lineage 24.0 Rebase:** Penyesuaian driver display, pemulihan driver ultrawide `imx355`, dan sinkronisasi CIP 4.19.325.
- **NoMount v20:** Redirection path systemless berbasis keyring.
- **Dual Charger & PD:** Aktifkan USB PD dan dual-charger support ala stock kernel.

## 2026-09-23 — Stabilitas Boot & Kernel Hardening

- **Fix MTCMOS Boot Hang:** Bounded loop pada ACK SPM clock untuk mencegah silent freeze saat boot.
- **Fix SCP Deadlock:** Timeout guard dan pelepasan mutex pada komunikasi inter-processor SCP.
- **Crash & NULL Guards:** Proteksi pointer pada driver PMIC, CMDQ, UPower, dan backlight KTD3136.
- **Modern Android ABI:** Dukungan syscall `clone3()` modern untuk kompatibilitas Android 14–17.
- **32-bit Compat:** Aktifkan `CONFIG_COMPAT=y` untuk kompatibilitas app dan HAL vendor 32-bit.

## 2026-09-19 — Initial Bringup

- **ReSukiSU Integration:** Root kernel non-GKI dengan manual hook mode.
- **NoMount Integration:** Framework systemless file injection.
- **Base Kernel:** Linux 4.19.325 CIP LTS untuk platform MT6768 / MT6769 (Helio G88).
