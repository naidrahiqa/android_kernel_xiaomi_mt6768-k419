---
id: 0017
title: Optimasi kernel batch — gate dprec_logger, buang cmdq_test, nyalakan ThinLTO
status: verified
severity: medium
area: kernel
opened: 2026-10-15
updated: 2026-10-16
fix_commit: "96d50715b424"
verified_on: "2026-10-16 (CI R04, commit b83b9b0b8d8a, Greenforce Clang 24.0.0)"
tags: [performance, lto, thinlto, display, cmdq, size, drain]
related: [0014, 0016]
---

## Issue

Permintaan "optimize code yang ada" di seluruh tree. Kernel 4.19.325 MT6768
(Config `LTO_NONE` default) punya beberapa pemborosan yang terukur. Semua
diubah lokal, tidak di-push.

## Evidence (hasil scan + verifikasi manual)

### 1. `dprec_logger_pr()` — 1.597 call site, tanpa gate

`drivers/misc/mediatek/video/mt6768/videox/disp_drv_log.h`. `DISPMSG` dan
`DISPCHECK` memanggil `dprec_logger_pr()` **unconditional**, sementara
`DISPINFO` di file yang sama sudah digate `g_mobilelog`. Tiap call =
1× `spin_lock_irqsave` global + matikan IRQ + 2× snprintf/vscnprintf
(`dispsys/display_recorder.c:1306`). Buffer aktif sejak boot
(`ddp_drv.c:652` `init_log_buffer()` di `disp_init()`), jadi tidak ada
window "logging mati".

Distribusi call site (objek yang ter-link):

| File | DISPMSG | DISPCHECK | Total |
|---|---|---|---|
| videox/primary_display.c | 95 | 120 | 367 |
| dispsys/ddp_disp_bdg.c | 205 | 2 | 230 |
| dispsys/ddp_dsi.c | 18 | 48 | 139 |
| videox/disp_lcm.c | 9 | 41 | 124 |
| videox/mtkfb.c | 32 | 29 | 109 |

**Fix:** gate `DISPMSG`/`DISPCHECK` dengan `g_mobilelog`, konsisten dengan
`DISPINFO` dan dengan pemakaian vendor lain (`extd_log.h`, `ddp_log.h`
mt6833/mt6885). `g_mobilelog` extern di `dispsys/ddp_debug.h:19`,
definisi `videox/debug.c:75` — keduanya dibuild, jadi linkage aman
(DISPINFO sudah memakainya di file yang sama).

### 2. `cmdq_test.o` — ~102 KB harness ENG tanpa gate

`drivers/misc/mediatek/cmdq/v3/Makefile:119` `obj-y += cmdq_test.o`
(tanpa syarat), plus `ccflags-y += -DCMDQ_TEST_PROC` di line 62 dan
`#define CMDQ_TEST` hardcoded di `cmdq_test.c:34`. `CONFIG_MTK_ENG_BUILD`
tidak di-set di `.config` — ini kode ENG di build user.

`llvm-size -A` → `.text` 11.640 + `.text.unlikely` **64.060** +
`.rodata.str1.1` **26.247** + `.rodata` 2.536 = **≈104.483 B (102 KB)**.
Ter-link ke vmlinux (`System.map` → `cmdq_test_init`). 8.189 baris source,
85 call `CMDQ_TEST_FAIL()` dengan `pr_notice` tak-gated. Hanya bikin
`/proc/cmdq_test/test`, tidak dipakai driver/HAL.

**Verifikasi simbol sebelum menghapus** (KRITIS — hapus buta = link error):

- `llvm-nm --defined-only` → 59 simbol global. Cross-check ke seluruh
  file `cmdq/v3/*.c` + `cmdq/v3/mt6768/*.c`: **nol simbol unik**, semua
  punya definisi di file lain.
- 3 simbol yang Initially terindikasi "dipakai": `testcase_clkmgr_impl`,
  `cmdq_sec_submit_to_secure_world_async_unlocked`, `cmdq_test_init_setting`
  — semuanya pemakaian di `cmdq/v2/` dan chip lain (mt6739/mt6761/mt6779/
  mt6833) yang **tidak dibuild**.
- `testcase_clkmgr_impl` dipanggil `mt6768/cmdq_mdp.c:1085` tapi di bawah
  `#if defined(CMDQ_PWR_AWARE)`, dan flag itu **tidak** ada di baris make →
  tidak ter-compile.
- `cmdq_sec_submit...` di `cmdq_test.c` hanya **prototipe** di bawah
  `#ifdef CMDQ_SECURE_PATH_SUPPORT`; definisi asli ada di `cmdq_sec.c:1148`.

**Fix:** `obj-y += cmdq_test.o` di-comment-out (file sumber tetap di tree).

### 3. ThinLTO mati total padahal toolchain mendukung

`out/.config`: `CONFIG_LTO_NONE=y`, `# CONFIG_LTO_CLANG is not set`,
padahal `CONFIG_ARCH_SUPPORTS_LTO_CLANG=y` dan
`CONFIG_ARCH_SUPPORTS_THINLTO=y`. Tidak ada `-flto` di baris make CI
(`kernel-ci-kit/scripts/build-kernel.sh`) maupun flag kompilasi — LTO
benar-benar tidak aktif, bukan di-inject manual.

**Precondition diverifikasi sebelum menyalakan:**

| Cek | Hasil |
|---|---|
| Prebuilt vendor `.o` (butuh bitcode LTO) | **tidak ada** — semua source |
| Custom `.ld` script yang fragile | tidak ada `*.ld` di `arch/arm64/boot/` |
| `naked`/inline-asm C di MTK | 0 (2 hit cuma `checkpatch.pl`, bukan C) |
| Custom section | 4 file, kompatibel |
| KSU mensyaratkan anti-LTO | tidak — `drivers/kernelsu/Makefile` kosong soal LTO |
| Makefile LTO block | standalone & benar (`Makefile:864-884`), pakai `-flto=thin` + `--thinlto-cache-dir` |
| CI pass `CC=clang LD=ld.lld` saat defconfig | **ya** (`build-kernel.sh:71-74`, dipakai `run_make "$DEFCONFIG"` line 125) |

**Fix:** `CONFIG_LTO_CLANG=y` + `CONFIG_THINLTO=y` di
`arch/arm64/configs/selene_defconfig`.

⚠️ **Gotcha PENTING:** `config LTO_CLANG` di `arch/Kconfig:530` punya
`depends on CC_IS_CLANG && LD_IS_LLD` — dievaluasi dari `make` arg. Kalau
`selene_defconfig` dijalankan **tanpa** `CC=clang LD=ld.lld`, ThinLTO
kembali `LTO_NONE` diam-diam. Selalu generate config dengan arg tersebut.

## Item yang DIABANDON (dengan alasan)

**Perpendek IRQ critical section `camera_isp.c`** — tidak dikerjakan:

- Subagent klaim "critical section 432 baris" benar hanya untuk lock
  ketiga (`spin_lock` 14494 → `spin_unlock` 14926). Dua lock sebelumnya
  cuma 3 dan 3 baris.
- Isi critical section tersebut = timestamp patching EIS
  (`ISP_PatchTimestamp` × 6), `IRQ_LOG_KEEPER`, dan update registry
  software — bukan MMIO read带的. Bagian itu justru **baru divalidasi**
  (lihat issue 0016: kamera 0.6X/1.0X/2.0X sudah hijau setelah fix MFB
  sisi aplikasi). Memindahkan lock di sini berisiko merusak timestamp
  EIS tanpa ada baseline latency yang menunjukkaniex是用
  masalahnya.
- Loop 32×32 yang diklaim "1024 iterasi" (`camera_isp.c:14896`) ternyata
  hampir tidak jalan: `while (tmp)` di dalam `if (MarkedFlag & Mask)` —
  hanya dieksekusi kalau HAL men-mark user interrupt, jarang di produksi.

Per skill tuning-guard: jangan mengubah perilaku di area yang baru
divalidasi tanpa baseline symptom yang terukur.

## Verification

- [x] build lokal: `MAKE_EXIT=0` + `Image.gz-dtb` (13.404.242 B lokal / 13.400.686 B CI)
- [x] `CONFIG_LTO_CLANG=y` + `CONFIG_THINLTO=y` bertahan di `out/.config`
- [x] `llvm-nm` vmlinux: `cmdq_test_init` **0 hit** di System.map, nol undefined symbol asli
- [x] flash → `dmesg` bersih: `DISPMSG`/`DISPCHECK`/`dprec_logger` **0 hit** (gate `g_mobilelog` bekerja)
- [x] smoke: display nyala, scroll responsif, kamera 0.6X/1.0X/2.0X ok (tanpa freeze/force-close)
- [x] rollback: `git revert96d50715b424` (3 file, terisolasi)

**Catatan verifikasi (2026-10-16):** Diverifikasi di HP pakai artifact **CI R04**
(build `b83b9b0b8d8a`, **Greenforce Clang 24.0.0**), bukan build lokal. Awalnya
HP sempat jalan build lokal yang tak sengaja memakai **system clang 22.1.8**
(karena `greenforce-clang/` tidak ada di mesin dan `make` mengambil `CC=clang`
dari `PATH`). Lihat `scripts/check-toolchain.sh` — guard yang ditambahkan agar
kesalahan toolchain tidak terjadi diam-diam lagi.

**Temuan baru saat verifikasi (di luar scope issue ini):** Subsistem **kamera/ISP**
masih membanjiri dmesg **±12.000 baris/menit** saat kamera dipakai — ~20.700 baris
dalam 113 detik (`[ISP][ISP_ioctl]` 9942, `[ISP][ISP_BH_Workqueue]` 5830, `CAMA`
3914). Ini **sama persis tipe masalahnya** dengan item 1 issue ini (`dprec_logger`
tak-gated), tapi di jalur kamera, bukan display. Log `P1_SOF`/`P1_DON` dicetak
**per-frame** (60+/detik @30fps). Belum ditangani — jadi kandidat issue terpisah.
Ada juga `[DDP/OVL]error: dim layer0 ahpha enable should be 1!` (79×, display).
