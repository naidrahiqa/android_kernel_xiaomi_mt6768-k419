# 🗺️ PawwwNunungggg Kernel — Roadmap

> Dokumen hidup. Versi, status, dan milestone dikelola di sini + file `VERSION`.
> Terakhir diperbarui: 2026-09-27.

## Milestone Overview

```
v0.1.0 (sekarang)          v0.1.x              v0.2.0              v1.0.0
UNSTABLE/PORTING  ──────►  TESTING  ────────►  FEATURE  ────────►  STABLE
 stabilisasi + soak         daily-driver        fitur + multi-      release publik
 validated                 gate                device
```

`VERSION` saat ini: `PAWWWNUNUNGGG_VERSION=0.1.0` · codename **Kucing** · status **unstable**

---

## ✅ Done (basis v0.1.0)

- Linux 4.19.325 CIP (`-cip136` / `-st20`), Greenforce Clang 24.0.0 (PGO+ThinLTO+O3+Polly)
- Boot stabil di selene (Redmi 10), AOSP/Lineage 13+ (Android 16 teruji)
- Root: ReSukiSU `KSU_VERSION 35184` (manual hook) + NoMount v20 + Zygisk stack
- CI/CD: nightly auto on push (artifact 90 hari), beta `workflow_dispatch`, stable tag `v*`, notif Telegram
- USB tethering fix (netdev `rndis\d` match regex Tethering) — end-to-end teruji
- Fast charge parity (PD 9V, non-std 1A), charger guardrails sesuai AGENTS.md
- Thermal standar (vendor `mi_thermald` + `/proc/driver/thermal`), LickingT di-uninstall
- Branding `PawwwNunungggg` (uname, tag, branch, CI) — rename bersih 0 sisa

## 🔬 Fase 1 — v0.1.x Stabilisasi (target: minggu ini)

**Goal: buktiin "Unstable" boleh jadi `testing`. Semua acceptance wajib tercapai.**

- [ ] **Soak test 48 jam** daily driver:
  - [ ] Thermal: gaming + charge 24-48h, zone nggak overheat, `mi_thermald` jalan normal
  - [ ] Charging 18W: PD 9V aktif, suhu baterai aman, ga ada reboot pas charge
  - [ ] USB tethering long-session (PC harian) — tanpa `IpServer` error
  - [ ] WiFi/BT, VoLTE/telepon, fingerprint, kamera (foto+video), GPS, sensor (gyro/accel)
- [ ] Beta release `PawwwNunungggg-24.0-v0.1.0-beta.202609xx` (workflow_dispatch)
- [ ] CI: run success di branding baru, build time ≤ 16 menit (ccache warm)
- [ ] Checklist hardware diisi di `mt6768-kernel` skill (apa work / apa belum)
- [ ] Lolos semua → bump `PAWWWNUNUNGGG_STATUS=testing` (commit `build:`)

## 🚀 Fase 2 — v0.2.0 Fitur (target: bulan depan)

**Goal: value-add custom kernel, tanpa sentuh charger guardrails.**

- [ ] Performance: evaluasi FPSGO tunables / uclamp / schedutil hispeed (config & benchmark dulu)
- [ ] Jaringan: set `DEFAULT_BBR` (udah `CONFIG_TCP_CONG_BBR=y`), sysctl sinyal/artemis default
- [ ] Memory: ZRAM zstd/lz4 policy + vm tunables (udah `ZRAM_WRITEBACK=y`)
- [ ] Fast-charge userspace toggle **tanpa ubah DTS** (mengikuti aturan brick AGENTS.md)
- [ ] Sinkronisasi upstream rutin: ReSukiSU (skill `ksu-version-management`), NoMount, CIP `linux-4.19.y-cip` security merge
- [ ] Enable issue tracker GitHub buat laporan bug (sekarang disabled)
- [ ] Cut minor → tag beta/stable `v0.2.0`

## 🌍 Fase 3 — v0.3.0 Multi-device & kompat (setelah v0.2.0)

- [ ] Bring-up `lancelot` (Redmi 9) & `merlin` (Redmi Note 9): defconfig/DTB variant, CI matrix
- [ ] Kompatibilitas ROM: Lineage 20-24, ROM 4.19-based HyperOS/MIUI port
- [ ] Dokumentasi flashing (AnyKernel3 + TWRP sideload) buat tester

## 🎯 Fase 4 — v1.0.0 Stable (definisi "selesai")

**Acceptance v1.0.0:**

- [ ] Semua subsystem setara stock (checklist Fase 1 lulus di 2+ ROM berbeda)
- [ ] `PAWWWNUNUNGGG_STATUS=stable`, README badge hijau
- [ ] Tag `v1.0.0` → GitHub Release penuh + changelog auto
- [ ] 30 hari tanpa critical bug (bootloop/brick/radio death)

---

## Aturan Jalan (dari AGENTS.md — ringkas)

1. **Cuma flash `boot`** via AnyKernel3 — jangan pernah flash LK/DTBO (brick).
2. Charger DTS = zona bahaya (`battery_cv`, JEITA, `hvdcp`, `temp_t4`) — wajib validasi hardware.
3. Test dulu, commit kemudian; conventional commits; build lokal pakai Greenforce (`greenforce-clang/bin`).
4. Kconfig terlarang: `SHADOW_CALL_STACK`, `SLAB_FREELIST_HARDENED`, `INIT_ON_*_DEFAULT_ON`, `BUG_ON_DATA_CORRUPTION`.
