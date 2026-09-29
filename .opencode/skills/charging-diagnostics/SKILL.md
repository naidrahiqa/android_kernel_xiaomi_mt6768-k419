---
name: charging-diagnostics
description: Diagnosa charging Xiaomi selene (MT6768) via adb — live capture sysfs power_supply, interpretasi dmesg bq2589x/mtk_charger (VChr/ibus/CT/pe40), konvensi tanda arus baterai, isolasi kabel vs adapter vs HP. Trigger: charger, charging, fast charge, rapid charge, isi daya lambat, baterai, VChr, ibus, real_type, bq2589x, PD, PE, QC, adb tcpip, ngisi pelan, charging animasi tapi gak naik-naik.
---

# Charging Diagnostics (MT6768 / Selene)

Diagnosa **read-only** — cara nangkep bukti live dari kernel charger stack
(`bq2589x` + `mtk_charger` + RT PD-manager) buat mastiin ini masalah hardware
(kabel/adapter) vs kernel vs thermal. **Mengubah config charger = lihat
AGENTS.md "Charger DTS" (BRICK RISK)** — skill ini cuma baca.

## Persiapan

- **Wajib root**: `su -c cat ...` — baca sebagai shell user biasa = kosong/`Permission denied`.
- **Paths (semua di bawah `/sys/class/power_supply/`)**:

| Node | Field penting | Arti |
|---|---|---|
| `usb/` | `real_type`, `online`, `present`, `voltage_now`, `voltage_max`, `current_max` | Deteksi adapter (BC1.2/PD); `voltage_max=500000`+`current_max=500000` = cuma SDP 500mA |
| `charger/` | `online`, `type` | Apakah jalur charger aktif |
| `main/` | `current_now`, `constant_charge_current_max`, `vindpm` | IC charger utama (bq2589x) — `constant_charge_current_max` = input current limit (mis. 960000 = 960mA) |
| `battery/` | `current_now`, `voltage_now`, `temp`, `status` | Arus baterai & suhu (temp: 446 = 44.6°C) |

- `dumpsys battery` → `AC/USB powered`, `Max charging voltage/current`, level, voltage, temperature.
- Supplies yang ada: `ac battery bms charger main usb` (layout MTK — bukan layout AOSP standar).

### Gotcha baca sysfs
- Loop `for ...; do cat ...; done` di dalam `adb shell su -c '...'` **rusak karena quoting** → tulis eksplisit per-file (`adb shell su -c "cat /sys/.../real_type"`).
- Output kosong ≠ file kosong: biasanya salah path atau belum root.

## Live capture saat charger dicolok (port USB-C cuma 1 — gak bisa adb + charger bareng)

1. Selagi masih di PC: `adb tcpip 5555`
2. Catat IP: `adb shell ip -f inet addr show wlan0` (harus sama LAN dengan PC)
3. Cabut USB PC → colok charger → tunggu ~15s
4. `adb connect <ip>:5555` → dump semua field di atas **selagi charger masih nyangkut**
5. Selesai: colok balik PC (dmesg ring buffer **persist** — baris sesi charger tadi masih kebaca walaupun kabel udah pindah; tapi baca dulu SEBELUM reboot)

## Konvensi tanda arus (MTK fuel gauge — SERING SALAH TAHU)

`battery/current_now`: **negatif = mengisi (arus masuk baterai)**, positif = discharge.

| Nilai | Arti |
|---|---|
| `-270200` | isi **270mA** (sangat lambat / trickle) |
| `-2542300` | isi **2.54A** (fast charge normal) |
| `+xxx` (positif) | baterai NGELUARIN arus — HP jalan dari baterai |

## Signature dmesg (grep: `VChr=|pe40|bq2589x|charger_dev_get_charger_type|pd_tcp`)

```
Vbat=4214,Ibat=23716,I=0,VChr=8685,T=46,Soc=59:37,CT:4:4 hv:1 pd:0:0
pe40_ready:0 hv:1 thermal:-1,-1 tmp:44,39,16 pps:0 en:0 ibus:0 80
[bq2589x]:bq2589x_set_icl: indpm curr = 2000000
[bq2589x]:bq2589x_set_ichg: charge curr = 2944000
[bq2589x]:bq2589x_charging: enable charger successfully
charger_dev_get_charger_type = 3        (berulang = polling aktif)
pd_tcp_notifier_call USB Plug in / Charger plug in
```

- **`VChr`** = tegangan VBUS (mV). Sehat: ~5000 (SDP) atau ~9000 (HV aktif). **< 4750 = sag** = adapter/kabel gak kuat.
- **`CT:x:x`** / `charger_dev_get_charger_type` = tipe charger terdeteksi (3/4 = non-standard/HV path).
- **`hv:1`** = mode high-voltage diizinkan; **`pd:0`/`pe40_ready:0`** = PD/PE4 gak jalan.
- **`ibus`** = arus input dari adapter (0 = adapter gak ngasih daya sama sekali).
- **`set_icl/set_ichg/set_vchg` + `enable charger successfully`** = IC charger SEHAT, driver mau isi — kalau ini muncul tapi `VChr`/`ibus` jelek → hardware di luar IC.

## Diagnosis matrix

| Gejala | Verdict |
|---|---|
| `real_type=USB`/`Unknown` + `voltage_max=500000` + `current_max=500000` + `AC powered:false` | Lagi colok **PC/port USB** — bukan charger dinding, bacaannya normal |
| `real_type=Unknown` + `VChr` sag ~4.5V + `ibus:0` + PD/PE gak pernah nyala, padahal `bq2589x enable` muncul | **Adapter/kabel mati** (identifikasi gagal / gak kuat load). Driver kernel sehat |
| `VChr≈8700-9000` + `set_icl=2000000` + `set_ichg≈2.9A` + `battery current ≈ -2.5A` | Fast charge **normal** |
| Adapter ke-deteksi bener tapi arus kecil + `battery/temp` naik | **Thermal/jeita clamp** → lihat gotcha `Fast charge stuck ~1W` di AGENTS.md / defconfig-management (`thermal_icl_ua = -1` di `mtk_charger.c`) |
| `usb/online=0` padahal `charger/online=1` | Jalur data USB gak aktif — normal buat charge-only detection |

## Isolasi hardware (urutan, cheapest first)

1. **Tukar kabel** — penyebab #1. (Sesi 29 Sep 2026: VChr 4.49V/ibus 0 → kabel dicek ulang → VChr 8.7V/2.5A langsung sehat.)
2. Colok **device lain** dengan adapter yang sama → sama-sama lambat = adapter rusak.
3. Colok **adapter lain** dengan kabel sama → tetep jelek = kabel.
4. Punya charger bagus (mis. 67W temen) colok ke HP: max = **HP sehat** → sisa kabel/adapter.

## Catatan

- `dumpsys battery` `Max charging voltage: 5000000` = framework cuma lihat 5V (negosiasi HV belum/ketahuan dari sisi framework) — angka definitif ada di `VChr` dmesg.
- Tanda adapter sekarat: open-circuit voltage turun + gak kuat load (VChr sag padahal arus kecil) — umur/panas.
- `avc: denied ... com.franco.kernel` di dmesg = app prober, bukan masalah charging.

## Cross-reference

- **UBAH config charger / DTS** → AGENTS.md "CRITICAL: Charger DTS" + defconfig-management (battery_cv/JEITA/hvdcp — BRICK RISK).
- **Thermal clamp runtime fix** (`thermal_icl_ua = -1`) → defconfig-management gotcha "Fast charge stuck ~1W".
- **Log persistensi / MTK log store** → mt6768-kernel skill.
