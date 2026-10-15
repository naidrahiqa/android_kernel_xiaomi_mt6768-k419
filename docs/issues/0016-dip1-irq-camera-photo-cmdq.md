---
id: 0016
title: Foto mode auto gagal save (CMDQ -110) — IRQ dip1 tidak pernah di-enable (regresi b291949aa61c) + DIP dump diinstrumentasi
status: fixed
severity: high
area: driver
opened: 2026-10-14
updated: 2026-10-14
fix_commit: "a621c84c448c"
verified_on: ""
tags: [camera, isp, dip, irq, cmdq, mt6768, instrumentation]
related: [0012]
---

## Issue

Foto mode auto (zoom 0.6x/1x) gagal ke-save karena CMDQ timeout -110.
Reproduksi 100%: kamera mode Foto, zoom 1.0X, `input tap 540 1992`
(5 dari 5 run, deterministik — pass ke-5 selalu hang).

Rantai bukti (riset agent 1, sudah terbukti — jangan diulang):

```
app setMfnr=true
 -> HAL jalankan TEPAT 5 pass "DpIsp: ISP Pass2 only" (libdp DpIspStream,
    scenario 8, via MDP)
 -> tiap pass menunggu GCE instruksi 0x80008001:0x20000101
    = Wait And Clear Event CMDQ_EVENT_DIP_CQ_THREAD0_EOF (eventID 0x101 = 257)
 -> pass 1-4 selesai 35-46ms, PASS KE-5 SELALU HANG
 -> token GCE event 257 saat hang = value:0 (tidak pernah ke-set);
    kontras token DISP_RDMA0_EOF = is 1 => GCE sendiri sehat
 -> register DIP saat hang:
      0x15022000 (CTL_START)     = 0x1        (CQ thread0 masih aktif)
      0x15022108 (CQ0 base)      = 0x4f790000 (terprogram)
      0x15022204 (tdriaddr)      = 0x57110000 (terprogram)
      0x15022044 (CQ_INT_STATUSX)= 0x0        <<< CQ tidak pernah raise EOF
      0x15022040 (INT_STATUSX)   = 0x40100000
 -> clock img_dip naik 0->7 saat capture (bukan masalah clock),
    SMI tidak hang, tidak ada IOMMU fault
```

Pertanyaan tersisa: MENGAPA CQ thread0 pass ke-5 tidak pernah EOF.

## Evidence

- `/proc/interrupts` baris `dip1` = **0 di semua capture**; dmesg hanya
  memperlihatkan `enable_irq cam 4..9` — tidak pernah `enable_irq dip`.
- Driver DIP buta total sebelum instrumentasi ini:
  - `ISP_DumpDIPReg()` tidak mencetak DIP+0x030/0x034/0x038 (padahal
    itu yang dibaca `ISP_Irq_DIP_A`)
  - `pr_info` di `ISP_Irq_DIP_A` sudah jadi `pr_debug` -> tidak muncul
  - salinan descriptor CQ/tpipe di dump RUSAK: offset
    `cmdqaddr-MemPa` (mis 0x90000) selalu melebihi
    `g_CmdqBaseAddrInfo.MemSizeDiff` (0x1000/0x10000) -> `cpy cmdq fail`
  - `/proc/driver/isp_reg` stub ("Not implement"), tidak ada `/dev/mem`,
    tidak ada debugfs kamera

## Root cause (REVISI 15 Okt 2026 — klaim awal TERBATAS BUKTI)

> ** Koreksi:** data hardware di bawah **membantah** bahwa IRQ yang mati
> adalah penyebab timeout. Fix `enable_irq dip1` tetap benar dan tetap
> perlu (regresi nyata vs referensi), tetapi **bukan** penyebab bug foto.
> Lihat "Temuan hardware" — akar masalah ada di level eksekusi CQ DIP,
> di bawah lapisan IRQ.

Regresi dari commit `b291949aa61c`: ia menambah
`disable_irq(isp_dev->irq)` untuk **SEMUA** device setelah `request_irq`
(`camera_isp.c` ~10363), tapi pasangan `enable_irq` hanya loop
`[ISP_CAM_A_IDX .. ISP_CAMSV4_IDX)`.

Di `ISP_DEV_NODE_ENUM` (`src/mt6768/inc/camera_isp.h:47`):

```
0=IMGSYS_CONFIG  1=DIP_A  2=CAMSYS_CONFIG  3=UNI_A  4=CAM_A ...
10=CAMSV4  11=CAMSV5
```

`ISP_DIP_A_IDX = 1` berada **di luar rentang** loop → IRQ dip1
(GIC 115) dibuat disabled di probe dan **tidak pernah di-enable** →
ISR `ISP_Irq_DIP_A` tidak pernah jalan → EOF event CQ tidak pernah
diproses/dilaporkan ke waiter HAL. (Catatan: wait-nya di GCE, tapi
tanpa IRQ DIP tidak ada jalur notifikasi/IRQ-driven handling DIP yang
hidup saat clock dibuka.)

## Fix

Satu file: `drivers/misc/mediatek/cameraisp/src/mt6768/camera_isp.c`
(1 fix + 3 instrumentasi, cabang CCF yang aktif — cabang
`EP_NO_CLKMGR`/`CONFIG_MTK_CLKMGR` TIDAK disentuh):

1. **FIX** — dua blok for-loop simetris (~4181 enable, ~4248 disable):

   ```c
   if (isp_devs[ISP_DIP_A_IDX].irq > 0) {
       enable_irq(isp_devs[ISP_DIP_A_IDX].irq);
       LOG_INF("enable_irq dip, irq=%d\n", isp_devs[ISP_DIP_A_IDX].irq);
   }
   ```

   (varian `disable_irq` di blok disable — refcount seimbang dengan
   `disable_irq` global di probe.)
2. **INSTRUMEN 1** — di `ISP_DumpDIPReg()` setelah print
   `isp: 15022010...`: `DIP INT(_030/034/038)`, `DIP CQ0 ctl/size
   (0x104..0x114)`, `DIP tdri(0x204)/imgi(0x400)`.
3. **INSTRUMEN 2** — baca descriptor CQ/tpipe **langsung dari DRAM**
   via `memremap(MEMREMAP_WB)` (64 grup x 4 word per alamat, label
   `DIPCQ0[..]` / `DRIPTP[..]`), menggantikan jalur `copy_from_user`
   yang selalu gagal karena offset > `MemSizeDiff`. Guard `!= 0` dan
   `!= 0xffffffff` (nilai awal sentinel variabel).
4. **INSTRUMEN 3** — nyalakan lagi log ISR: `pr_info("dip1 irq #%lu
   st=%08x cq=%08x ld=%08x\n", ...)` + counter statis `dip1_cnt`
   (bukan `pr_debug`).

Juga: `#include <linux/io.h>` (deklarasi `memremap`/`MEMREMAP_WB`).

**Patch/pesan yang TIDAK boleh disentuh** (kondisi eksplisit owner):
- blok `#if 0` di `cmdq_core_save_first_dump()` (sudah disengaja)
- commit log-silencing `c041feaa256f`

## Verification

- [x] build lokal: `MAKE_EXIT=0` + `Image.gz-dtb` (lihat commit)
- [ ] flash → `adb -s 192.168.127.57:5555 shell "su -c 'cat
      /proc/interrupts | grep dip1'"` → kolom hitungan dip1 **> 0**
      setelah buka/tutup kamera (sebelumnya selalu 0); muncul log
      `enable_irq dip, irq=...` saat kamera dibuka
- [ ] reproduksi: kamera mode Foto, zoom 1.0X, `input tap 540 1992` →
      `dmesg` berisi `DIP INT(_030/034/038)`, `DIP CQ0 ctl/size`,
      `dip1 irq #`, `DIPCQ0[..]`
- [ ] foto tersimpan (bug utama tutup)

### Cara membaca hasil (decision table)

- `DIPCQ0[..]` semuanya `0x00000000` => descriptor tak pernah ditulis
  untuk pass 5 => DIP tidak pernah di-kick; telusuri jalur kick
  (ioctl/HAL).
- `DIPCQ0[..]` valid tapi `CQ_INT_STATUSX` tetap 0 => descriptor
  menyuruh DIP menunggu sesuatu yang tak datang (kandidat: MFB done).
  Cek nilai `0x15022F60` (mfb) & `0x1502265C` (mfbo).
- `0x030/0x034` non-zero & berubah antar run => DIP sebenarnya sudah
  IRQ, tinggal decode bit-nya.
- count `dip1` tetap 0 meski sudah di-enable => masalah di
  konfigurasi DTS interrupt (`arch/arm64/boot/dts/mediatek`).

### Eksperimen 2 (build ke-2, commit `960e261283d2`) — sampler periodik

Masalah dump sebelumnya: yang terekam hanya kondisi **saat timeout** (pass 5).
Sisi pass yang **sehat** (1-2) tidak pernah terlihat, jadi tidak ada baseline
yang bisa dibandingkan. Eksperimen ini menambah sampler periodik supaya satu
capture gagal juga memperlihatkan transisi pass sukses → pass nangkit.

`drivers/misc/mediatek/cameraisp/src/mt6768/camera_isp.c` (+133 baris, 0
hapus, tanpa perubahan fungsional — hanya `pr_info`):

- `DIPSMP #N start= cq0=ctl/base/size cq1base= cqint= int= tdri= imgi=` —
  sampel tiap 10 ms selama clock ISP hidup, dicetak **hanya saat ada
  perubahan** dari sampel sebelumnya.
- `DIPCQSNAP #N [xx] w0 w1 w2 w3` — 16 entri pertama descriptor CQ0
  (via `memremap(MEMREMAP_WB)`), diambil tepat saat `cq0base` diprogram ulang
  atau status CQ berubah, sebelum buffer dipakai ulang. Maks 64 snapshot.
- Nyalakan di `ISP_EnableClock()` saat count 0→1, matikan saat 1→0
  **sebelum** `Disable_Unprepare_ccf_clock()` supaya sampel terakhir masih
  punya clock hidup. Semua baca register dijaga `G_u4EnableClockCount != 0`.

Cara baca:

| Pola di dmesg | Arti |
|---|---|
| pass sukses: `cq0base` berubah + `cqint` sempat bukan-0; pass nangkit: `cq0base` tidak berubah sama sekali | **H1 terbukti** — CQ0 tidak pernah di-kick ulang |
| `cq0base` selalu sama dan `cqint` selalu 0 sejak awal | descriptor hanya ditulis sekali per capture |
| `DIPCQSNAP` semua `0x00000000` | descriptor tidak pernah ditulis HAL |
| `DIPCQSNAP` valid | descriptor ada; masalahnya di eksekusi CQ |
| `cq0ctl` **tidak pernah** berbeda dari `0x11` | `0x11` = CQ aktif → **H1 gugur**, ganti hipotesis "CQ jalan tapi tidak pernah EOF" |

Hapus blok sampler (dan 2 call-nya) setelah hipotesis selesai dibedah.

### Temuan hardware (15 Okt 2026, setelah flash `9d0884012e69`)

Diperoleh dari satu capture gagal (`Foto`, zoom 1.0X, `input tap 540 1992`):

**Yang TERBUKTI benar:**

| Fakta | Bukti |
|---|---|
| Fix IRQ terpasang | dmesg: `enable_irq dip, irq=115` |
| IRQ dip1 tetap **tidak pernah fire** | `/proc/interrupts` = 0; `/proc/irq/115/` → `count 0`, `unhandled 0` |
| ISR tak pernah jalan | `dmesg \| grep -c 'dip1 irq #'` = **0** |
| IRQ lain sehat | `cam2` = 2685+ hitungan |
| GCE sehat | `CMDQ_EVENT_DISP_RDMA0_EOF is 1` saat timeout |
| **CQ DIP di-program & ARMED** saat gagal | `DIP CQ0 ctl/base/size = 0x11 / 0x4843c000 / 0x2d8` |
| **CQ1 juga aktif** saat capture | `0x110 = 0x11`, `0x114 = 0x48508000` (preview tidak pakai CQ1) |
| **Descriptor CQ0 diisi HAL** | `DIPCQ0[00..27]` = pointer valid (`02c17088`, `70a57770`, `726769f0`, …), bukan semua nol |
| Semua status register nol saat gagal | `DIP INT(_030/034/038) = 0x0/0x0/0x0` |

**Hipotesis yang gugur:**

- ~~H1 "CQ0 tidak pernah di-kick ulang"~~ → **GUGUR**. `cq0ctl` naik
  `0x10 → 0x11` dan `cq0base` berubah berulang (`48406000 → 4840c000 →
  4841e000 → …`), baik di preview maupun capture. Descriptor ada, CQ
  armed. Yang tidak terjadi adalah **CQ selesai (EOF)**.
- ~~"CQ jalan tapi tidak pernah EOF"~~ → **INI YANG BENAR**. `cq0ctl=0x11`
  = CQ aktif; CQ tidak pernah raise status → tidak ada EOF.

**Rantai yang terbukti (`ISP_WaitIrq`):**

```
HAL ioctl ISP_WAIT_IRQ  ->  baca array software
                           IspInfo.IrqInfo.Status[TYPE][ST][KEY]
                      ^  satu-satunya penulis = ISP_Irq_DIP_A (line 13204)
                      |  butuh IRQ hardware dip1
                      |  tapi count = 0  ->  ISR tidak pernah jalan
                      '-> array tetap 0  ->  Timeout(256)  ->  capture gagal
```

**Perbandingan dengan referensi 4.14 stock (`android_kernel_xiaomi_selene`):**

| Aspek | Ref (stock, known-good) | Tree kita |
|---|---|---|
| `request_irq` lalu… | **langsung enabled**, tanpa `disable_irq` | `disable_irq` → masked (regresi `b291949aa61c`) |
| `ISP_EnableClock()` | **tidak ada** `enable_irq`/`disable_irq` | ada loop `enable_irq`/`disable_irq` (4..9 + dip1) |
| `ISP_Irq_DIP_A` register | `0x030`/`0x034`/`0x038` | **identik** |
| DTS `dip1@15022000` | `GIC_SPI 270 IRQ_TYPE_LEVEL_LOW`, reg `0x3000` | **identik** |
| Tabel ioctl | 46 ioctl | 46 ioctl (selisih nol) |

Jadi porting driver tidak berubah di jalur ISR/DTS/ioctl; yang berbeda
hanya ada di proteksi IRQ tambahan.

**Kesimpulan sementara:** regresi IRQ itu **nyata dan harus diperbaiki**
(enable permanen ala referensi lebih bersih daripada sandaran
enable/disable saat clock), tapi itu **bukan** penyebab timeout foto.
Titik kegagalan ada satu level lebih bawah: CQ DIP ter-arm dan berisi
descriptor, tetapi tidak pernah mengeksekusi sampai EOF.

**Langkah berikutnya (usulan):** baca sweep register DIP `0x020`–`0x050`
di sampler (murni reads, tanpa write) untuk memetakan mana yang
`INT_ENA` dan mana `INT_STATUS/CQ_INT_STATUS` — sekarang baru kita
tahu apakah HW-side interrupt benar-benar dinonaktifkan, atau CQ memang
terlalu bergantung pada sesuatu (mis. CQ1 / MFB / pass-by signal).

## Catatan MFB MT6768 (jangan salah simpul)

`mt6768-gce.h` TIDAK punya `CMDQ_EVENT_MFB_DONE` (mt6779 punya =278),
`cameraisp/mfb/Makefile` tidak punya blok `ifeq CONFIG_MACH_MT6768`
(hanya `camera_mfb_dummy.o`), tidak ada clock `img_mfb` dan tidak ada
node `mfb@` di DTS — **TAPI** register mfb/mfbo ada DI DALAM alamat DIP
(`0x15022F60`, `0x15022350`, `0x1502265C`) sehingga tetap ikut
di-dump dan terisi. Jangan simpulkan "MT6768 tidak punya MFB" dari
Makefile saja.

## Regression test

Kalau ada dampak negatif dari IRQ dip1 yang kembali hidup (mis. spam
ISR), opsi teraman: pertahankan FIX, kurangi instrumentasi (hapus
`pr_info` ISR / `DIPCQ0[]` dump) — jangan nonaktifkan lagi IRQ-nya.
