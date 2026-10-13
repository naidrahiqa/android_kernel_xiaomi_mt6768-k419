---
id: 0011
title: Port batch fitur dari Fire inferno-new (changelog 13-09-2026) — MGLRU, CPQ, copy_page, lz4 1.10, RCU_BOOST, logspam, defconfig hygiene
status: open
severity: medium
area: kernel
opened: 2026-10-13
updated: 2026-10-13
fix_commit: ""
verified_on: ""
tags: [port, fire, mglru, cpq, lz4, rcu, logspam, defconfig]
related: []
---

## Issue

User minta update kernel dengan item menarik dari changelog Fire
(`https://telegra.ph/Changelog-13-09-2026-09-13`, referensi repo
`deryardi73/android_kernel_xiaomi_fire@inferno-new` dan
`mt6768-dev/android_kernel_xiaomi_mt6768`).

Hasil cross-check Fire vs tree kita — item yang **belum ada** dan dipilih
untuk di-port (6 batch, commit terpisah per item, urut dari aman):

1. **Quick wins**: `copy_page` opt (zsmalloc, f2fs checkpoint/node/segment, zram) + defconfig hygiene (off `NL80211_TESTMODE`, `CFG80211_DEVELOPER_WARNINGS`, dsb)
2. **lz4 → 1.10.0** backport
3. **RCU_BOOST + RCU_EXPERT** + RCU tree perf fixes
4. **Logspam silencing** (binder/drm/clk/sound/pmic/teei — jauhi fix `teei_log_thread` yang sudah verified)
5. **CPQ I/O scheduler** (backport + default, benchmark dulu vs ADIOS/Kyber — tuning-guard)
6. **MGLRU** (`CONFIG_LRU_GEN`) — headline, wajib A/B test drain + perf

Item yang **diputuskan TIDAK diambil** (terverifikasi di repo referensi):
- BBRv3/PLB — ada di changelog tapi **tidak ada** di tip `inferno-new`
- Fix backlight ktd3137 — code beda 520 baris, panel-specific (M19a)
- Thermal gradual cpufreq cooling — di-revert oleh Fire sendiri
- step_wise thermal — file identik dengan kita (0 diff), sudah ada
- CFI (mt6768dev) — kita pernah kena CFI callback trap

## Evidence

- Cross-check dilakukan dengan clone shallow kedua repo referensi ke `/tmp/opencode/`.
- `diff fire/mm/... vs ours` per item — lihat baris Fix untuk masing-masing commit.
- Fire `fire_defconfig`: `CONFIG_LRU_GEN=y`, `CONFIG_LRU_GEN_ENABLED=y`, `CONFIG_MQ_IOSCHED_CPQ=y`, `CONFIG_MQ_IOSCHED_ADIOS=y`, `CONFIG_RCU_BOOST=y`, `CONFIG_RCU_EXPERT=y`.
- Kita: `grep LRU_GEN mm/Kconfig` → kosong; `block/cpq*` → tidak ada; `lib/lz4` masih format 4.19 lama.

## Root cause

Bukan bug — ini porting fitur baru dari referensi device lain.

## Fix

Semua 6 batch sudah di-port sebagai commit lokal (urut):

| Batch | Commit | Isi |
|---|---|---|
| 1 | `9f4f9dd9362c` + `fbfa39fcdcd8` | copy_page (zram/zsmalloc/f2fs/swap) + defconfig hygiene |
| 2 | `2cbadcef9565` | lz4 upstream 1.10.0 |
| 3 | `0a008d0795ef` | RCU_BOOST + RCU_EXPERT, gp workers WQ_UNBOUND |
| 4 | `c041feaa256f` | logspam silencing (28 commit fire; teei/m4u di-skip) |
| 5 | `5334a3fc420b` + `929538d6480e` | CPQ I/O scheduler + default di selene_defconfig (kyber off) |
| 6 | `71b0d6fbc9f8` | MGLRU (LRU_GEN + LRU_GEN_ENABLED) |

Catatan adaptasi: logspam `focaltech_FT8720` dipetakan ke
`focaltech_touch_k19a` (driver panel selene); binder ioctl print ikut
state akhir Fire (`pr_debug`, condition tetap `-ERESTARTSYS`); MGLRU
konflik di `fuse/dev.c` (dump_page kita dipertahankan + mask MGLRU),
`workingset.c` (token rework Fire), `vmscan.c` (blok LRU_GEN diambil
verbatim, GMO `scan_anon_priority` ikut).

## Verification

- Build lokal batch 1–3 + cmdq: lulus (`MAKE_EXIT=0`).
- Build lokal final batch 1–6 + cmdq: LULUS (`MAKE_EXIT=0`, Image.gz-dtb 13.4MB, defconfig regen `CC_IS_CLANG`, KP: KSU+NoMount 4/4, LRU_GEN+ENABLED, MQ_IOSCHED_CPQ+CPQ_DEFAULT, kyber off, RCU_BOOST+EXPERT).
- **Boot pertama di hardware** (build `g1951bbc122b3`, 14 Okt): uname benar, MGLRU aktif (`/sys/kernel/mm/lru_gen/enabled` = `0x0003`), CPQ registered + terbukti jadi default kernel (log `io-sched.log`: `was: mq-deadline [cpq] …`) — lalu di-flip ke mq-deadline oleh guard `io-guardd` punya user; user memilih mempertahankan mq-deadline (CPQ tetap tersedia manual).
- CI `build.yml` hijau, artifact AK3 ter-flash — **belum** (belum push).
- MGLRU: A/B test harian (drain/perf) sebelum boleh `verified`.

## Regression test

- Boot normal, `/proc/config.gz` cocok dengan yang di-port.
- MGLRU: `/sys/kernel/mm/lru_gen/` ada dan enabled.
- CPQ: scheduler aktif di `/sys/block/sda/queue/scheduler` (atau boot arg), I/O bench vs baseline.
- RCU: tidak ada stall warning di dmesg selama pemakaian harian.
