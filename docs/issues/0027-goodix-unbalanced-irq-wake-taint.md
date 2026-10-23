---
id: 0027
title: Goodix — irq_wake_enabled diset tanpa cek hasil enable_irq_wake, picu "Unbalanced IRQ wake disable"
status: fixed
severity: low
area: drivers
opened: 2026-10-18
updated: 2026-10-18
fix_commit: "c1339f6e91fc"
verified_on: ""
tags: [fingerprint, goodix, irq, wake, taint, warning]
related: [0022]
---

## Issue

`gf_enable_irq()` di `drivers/input/fingerprint/goodix/gf_spi_tee.c`
memanggil `enable_irq_wake()` lalu **langsung** menyetel
`irq_wake_enabled = 1` tanpa memeriksa return value. Bila arming wake
gagal (atau state wake ter-reset oleh `free_irq()` + request ulang pada
`GF_IOC_INIT`), flag tetap `1` padahal IRQ tidak dalam keadaan armed.

Akibatnya `gf_disable_irq()` memanggil `disable_irq_wake()` untuk IRQ
yang tidak pernah armed → kernel memicu:

```
Unbalanced IRQ 141 wake disable
WARNING: CPU: 2 PID: 1962 at irq_set_irq_wake+0xf0/0x1a4
Comm: android.hardwar
```

Satu-satunya WARNING non-benign di pstore (console-ramoops sesi 30
Sep 2026, frame 35–71). Gak bikin crash, tapi **mengetaint kernel**
(`Tainted: G S W`) — oops berikutnya jadi kelihatan kotor dan
membingungkan triage.

## Evidence

- `log-dump/full-analysis/pstore/console-ramoops-0:35-71` — WARNING
  dari `gf_ioctl` → `gf_disable_irq` → `irq_set_irq_wake`.
- Kode lama (`gf_spi_tee.c`): return value `enable_irq_wake()` tidak
  dicek; `GF_IOC_INIT`/re-init path menyetel `irq_count = 1` secara
  manual tanpa sinkronisasi wake flag.
- `gf_ioctl` tidak memiliki lock global — `GF_IOC_ENABLE_IRQ` /
  `GF_IOC_DISABLE_IRQ` dari HAL bisa berjalan bersamaan (race `irq_count`
  non-atomic), tapi jalur gagal-arming adalah penjelasan paling langsung
  untuk flag-1-tapi-tidak-armed.

## Root cause

State tracking `irq_wake_enabled` meyakini arming wake sukses tanpa
bukti dari kernel — pasangan `enable_irq_wake`/`disable_irq_wake` jadi
tidak seimbang di sisi flag saat arming gagal.

## Fix

`drivers/input/fingerprint/goodix/gf_spi_tee.c` — `gf_enable_irq()`:

- Set `irq_wake_enabled = 1` **hanya** bila `enable_irq_wake()`
  mengembalikan 0 (sukses).
- Bila gagal, log `ERR_LOG` sekali — sinyal tetap terlihat tanpa
  menyetel flag yang salah.

Dengan flag yang jujur, `gf_disable_irq()` melewatkan `disable_irq_wake()`
saat tidak armed → WARNING tidak bisa terjadi dari jalur ini.

## Verification

- [ ] Build-only (belum diflash terpisah — masuk batch berikutnya).
- [ ] Pasca-boot: `dmesg | grep -c Unbalanced` = 0 setelah beberapa
      siklus sidik jari (unlock + screen off/on).
- [ ] `cat /proc/version` tidak memuat `W` taint flag baru.
