---
id: 0018
title: Camera ISP nge-flood dmesg ±12.000 baris/menit (KERNEL_LOG + 56 call site IRQ_LOG_KEEPER tanpa gate + Virtual CQ/FDVT pr_info)
status: fixed
severity: medium
area: kernel
opened: 2026-10-16
updated: 2026-10-16
fix_commit: "61e5b261667c"
verified_on: ""
tags: [performance, camera, isp, logging, dmesg]
related: [0017, 0016]
---

## Issue

Saat kamera dipakai, dmesg dibanjiri **±12.000 baris/menit** (±20.700 baris /
113 detik saat sesi motret). Tiap `printk` = CPU + I/O, jadi ini overhead nyata
di momen paling sensitif performa. Ditemukan saat verifikasi issue #0017.

## Evidence (capture `/tmp/opencode/dmesg-r04.txt`, device, CI R04 / b83b9b0)

Breakdown persis dari capture (di-normalisasi per pesan):

| # | Pesan | Baris | Sumber |
|---|---|---:|---|
| 1 | `From hw_module:N Virtual CQ count from user land : N` | 4948 | `camera_isp.c` `ISP_SET_VIR_CQCNT`, `LOG_NOTICE` unconditional |
| 2 | `Update Virtual CQ cnt for hw_module:N` | 4948 | idem |
| 3 | `CAMA P1_DON_...` (via `ISP_BH_Workqueue`) | 3166 | `IRQ_LOG_KEEPER` `_LOG_INF`, **gated** `DebugMask & ISP_DBG_INT` |
| 4 | `CAMA PHY cqcnt:N VIR cqcnt:N` (+prefixed/continuation) | ~3141 | `camera_isp.c:14936` `_LOG_DBG`, **ungated** |
| 5 | `CAMSV1 P1_DON_...` | 1771 | gated (spt #3) |
| 6 | `CAMA P1_SOF_...` (prefix + continuation) | ~1868 | `camera_isp.c` SOF sites, **ungated** |
| 7 | `FDVT [FDVT_WaitIRQ] Receive IRQ : N` | 908 | `fdvt/4.0/camera_fdvt.c:1140` `LOG_INF` = `pr_info` unconditional |
| 8 | `CAMSV1 P1_SOF_...` | ~321 | **ungated** |
| 9 | `log str avalible=0, print log` (buffer overflow dump) | 132 | gejala dari #4/#6 membanjiri buffer `gSvLog` |

Waktu jendela: `[587.528]` → `[700.739]` = 113 detik (±12.000 baris/menit).

Sumber minor (di luar scope fix ini): `[DDP/OVL]error:dim layer0 ahpha...`
79× (display), `GT9764AF_DRV` pergerakan AF, `sensordrv ... dummy regulator`
boot-time.

## Root cause (tiga lapis)

### Lapis 1 — `KERNEL_LOG` mematikan default mask

`drivers/misc/mediatek/cameraisp/src/mt6768/inc/camera_isp.h:18-20`:

```c
/**
 * enforce kernel log enable
 */
#define KERNEL_LOG
#define ISR_LOG_ON
```

`KERNEL_LOG` didefinisikan **tanpa syarat** (komentar vendor: "enforce kernel
log enable") — kode ENG yang nyasar ke build user, **persis pola `cmdq_test.o`
di issue #0017 item 2**. Satu-satunya pemakaiannya di subtree mt6768 ada di
`camera_isp.c:9761-9763` (init): `IspInfo.DebugMask = (ISP_DBG_INT);`.

`ISP_DBG_INT` (0x1) sebagai default → situs log yang digate
`if (IspInfo.DebugMask & ISP_DBG_INT)` ikut nyala (termasuk `P1_DON` per-frame).

Catatan: `ISR_LOG_ON` juga didefinisikan tapi **0 pemakaian** di
`mt6768/camera_isp.c` (hanya dipakai mt6761/mt6779) — mati, bukan penyebab.

### Lapis 2 — mayoritas call site `IRQ_LOG_KEEPER` TANPA gate

Mekanisme log IRQ vendor: `IRQ_LOG_KEEPER()` (camera_isp.c:1014) **men-buffer**
string ke `gSvLog[][logT]` (bukan langsung print), lalu `IRQ_LOG_PRINTER()`
di `ISP_BH_Workqueue` (baris 15702) dan tasklet **menscroll buffer ke dmesg
tanpa syarat** tiap frame. Artinya yang menentukan "apa yang tercetak" adalah
gate di **call site** — dan audit 67 call site:

- **11 gated** `DebugMask & ISP_DBG_INT` (semua `P1_DON`, dst)
- **56 ungated** — semua `P1_SOF`, `CAMA/CAMB PHY cqcnt` (`:14930/:14935`),
  dst → tetap tercetak walau mask mati

Itu sebabnya mematikan `KERNEL_LOG` saja **tidak cukup**.

### Lapis 3 — log unconditional di jalur panas

- `ISP_SET_VIR_CQCNT` ioctl: 2× `LOG_NOTICE` (= `pr_notice`) tiap set →
  **9.896 baris** dalam 113 detik (pembanding terbesar, 48% flood)
- `fdvt/4.0/camera_fdvt.c:1140`: `LOG_INF("[FDVT] Receive IRQ")` =
  `pr_info` unconditional tiap IRQ FDVT → **908 baris**
- Efek samping: buffer `gSvLog` meluap → path overflow `IRQ_LOG_KEEPER`
  meneriakkan `log str avalible=0, print log` + dump isi buffer (132×)

### Catatan prefix & volume

`camera_isp.c:16` define `pr_fmt(fmt) MyTag "[%s] " fmt, __func__` dengan
`MyTag = "[ISP]"` → semua `pr_info`/`LOG_INF`/`LOG_NOTICE` di file ini dapet
prefix `[ISP][<fungsi>]` (makanya `[ISP][ISP_ioctl]` / `[ISP][ISP_BH_Workqueue]`).
Baris tanpa prefix = baris *lanjutan* (continuation) dari satu `pr_info` yang
berisi banyak entri buffer bergaris baru — kernel tidak memberi timestamp pada
lanjutannya.

Di `mt6768/camera_isp.c` (15.714 baris) total: `LOG_INF(` 5, `LOG_NOTICE(`
**296**, `pr_info(` mentah **425**, `LOG_DBG(` no-op/debug. Mayoritas tidak
per-frame (error path / init) — hanya yang per-frame yang di-fix.

## Fix (4 perubahan, semuanya keyed ke mask yang sama)

1. **`camera_isp.h`**: `#define KERNEL_LOG` dikomentari → default
   `DebugMask = 0`. Setter runtime tetap ada (`ISP_DEBUG_FLAG` ioctl,
   `camera_isp.c:7820`) → logging bisa diaktifkan lagi tanpa rebuild.
2. **`camera_isp.c` `IRQ_LOG_KEEPER`**: guard baru di posisi teratas makro —
   `if (logT != _LOG_ERR && !(IspInfo.DebugMask & ISP_DBG_INT)) break;`
   → **semua** `_LOG_INF`/`_LOG_DBG` (gated maupun ungated: `P1_SOF`,
   `cqcnt`, dst.) berhenti di-buffer saat mask mati; jalur overflow ikut
   mati sendiri (counter tidak pernah penuh). `_LOG_ERR` **tetap** di-buffer
   — konteks error harus tetap bisa diambil via `ISP_DUMP_ISR_LOG`.
   Satu guard di satu titik menutup 56 call site tanpa menyentuhnya.
3. **`camera_isp.c` `ISP_SET_VIR_CQCNT`**: 3 pesan success-path
   `LOG_NOTICE` → `LOG_DBG` (no-op/pr_debug). Jalur error
   (`copy_from_user failed`) **tetap** `LOG_NOTICE`.
4. **`fdvt/4.0/camera_fdvt.c:1140`**: `LOG_INF` → `LOG_DBG` (per-IRQ FDVT
   chatter).

Prinsipnya: **log per-frame = debug-level, aktif hanya saat
`ISP_DEBUG_FLAG` diset**; `pr_notice`/`pr_err` untuk hal yang benar-benar
perlu terlihat. Flag yang sama mengontrol semua jalur (konsisten dengan
desain vendor).

## Rollback

`git revert <commit>` (4 file). Atau aktifkan lagi lewat `ISP_DEBUG_FLAG`
ioctl tanpa rebuild (untuk #1 dan #2); #3/#4 butuh revert untuk kembali ke
level `pr_notice`/`pr_info`.

## Verification

- [ ] `scripts/check-toolchain.sh` exit 0 (Greenforce) sebelum build
- [ ] build lokal: `MAKE_EXIT=0` + `Image.gz-dtb`
- [ ] flash → buka kamera, ambil foto di 0.6X/1.0X/2.0X
- [ ] `dmesg` sesudah motret: **total baris camera/ISP turun dari ±20.700/113 dtk
      ke < 1.000** — khususnya `Virtual CQ`=0, `P1_SOF`/`P1_DON`=0,
      `cqcnt`=0, `FDVT Receive IRQ`=0, `log str avalible`=0
- [ ] kamera tetap berfungsi normal (tanpa freeze/force-close) — regresi DIP issue #0016 tidak kambuh
- [ ] rollback: `git revert <commit>` (4 file)
