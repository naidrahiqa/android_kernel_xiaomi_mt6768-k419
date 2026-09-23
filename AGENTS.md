# AGENTS.md — MT6768 Kernel (Mocchipyon Edition)

Baca file ini dulu sebelum kerja di repo ini. **File ini orchestrator** — untuk detail task, load skill terkait dari `.opencode/skills/*/SKILL.md`.

## Daftar Skill

| Skill | File | Trigger |
|---|---|---|
| **MT6768 Kernel** | `.opencode/skills/mt6768-kernel/SKILL.md` | **Master skill** — overview, hardware, build commands, file locations |
| Build System Fixes | `.opencode/skills/build-system-fixes/SKILL.md` | Clang IAS, stpcpy, LTO, ZSTD, UAPI headers, vDSO32, assembly errors |
| ReSukiSU Integration | `.opencode/skills/resukisu-integration/SKILL.md` | KernelSU driver, manual hooks, KSU_VERSION, manager APK |
| KSU Version Management | `.opencode/skills/ksu-version-management/SKILL.md` | Version pin, upstream sync, notes generator (generate-ksu-notes.sh) |
| NoMount | `.opencode/skills/nomount/SKILL.md` | Systemless path redirection, VFS hooks, keyring control |
| CI/CD (GitHub Actions) | `.opencode/skills/ci-cd-github-actions/SKILL.md` | Workflow, Telegram notif, release automation, build debugging |
| Defconfig Management | `.opencode/skills/defconfig-management/SKILL.md` | Config dependency chains, gotchas, debug workflow |
| Kaeru Integration | `.opencode/skills/kaeru-integration/SKILL.md` | Bootloader spoofer, lock state, cert bypass, DRAM comm |
| Versioning & Releases | `.opencode/skills/versioning-releases/SKILL.md` | Version scheme, channels (nightly/beta/stable), localversion, tag conventions |

**Cara pakai:** Saat dapat task, load skill yang sesuai dari tabel di atas.

## Konteks Project

- **Device:** Xiaomi Selene (Redmi 10 / Redmi 10 2022 / Redmi 10 Prime), codename **selene**, MediaTek MT6768 / MT6769 (Helio G88).
- **Kernel:** Linux 4.19.325 (CIP stable backport), **non-GKI**, **STATUS: UNSTABLE/PORTING**.
- **Branch:** `Mocchipyon23.2` (primary / 4.19 porting), `Mocchipyon24.0` (Lineage 24.0 dev), `lineage-24.0` (upstream tracking)
- **Remotes:** `origin` (naidrahiqa fork), `upstream` (`mt6768-S/android_kernel_xiaomi_mt6768`), `cip` (linux-cip)
- **Toolchain:** Greenforce Clang (LLVM/Clang, PGO+ThinLTO+O3+Polly)
- **Root solution:** ReSukiSU (`ReSukiSU/ReSukiSU`, manual hook mode `CONFIG_KSU_MANUAL_HOOK=y`).
- **Systemless:** NoMount v20 (`maxsteeel/nomount`, keyring-based control).
- **Bootloader:** Kaeru LK (`R0rt1z2/kaeru`, lock state spoofing + cert bypass).
- **Build variants:** Single universal kernel — targeted for AOSP/LineageOS 20+ (Android 13+ up to 16) and 4.19-based HyperOS/MIUI ports. (Catatan: Stock official MIUI 13/14 menggunakan kernel 4.14 di reference project).
- **Version:** `v0.1.0` (tracked in `VERSION`, codename "Kucing", uname -r: `4.19.325-Mocchipyon-cip136-st20`).
- **Release channels:** Nightly (auto push), Beta (workflow_dispatch pre-release), Stable (git tag `v*`).
- **Reference:** `/home/naidra/Projects/Kernel/android_kernel_xiaomi_selene` (4.14 stable, branch `phrolova`, untuk stock MIUI 12.5/13/14)

## Commit Style

Gunakan **conventional commits** untuk semua commit:

```
<scope>: <description>

scope:
  arm64    — arch/arm64 changes
  drivers  — driver changes
  sound    — audio changes
  ci       — CI/CD changes
  docs     — documentation
  build    — build system

description:
  Gunakan imperative mood, lowercase, tanpa period.
  Contoh: "fix vdso32 Clang IAS errors", "add ReSukiSU driver"
```

## Build Commands

```bash
# Full build
make O=out ARCH=arm64 \
  CC=clang HOSTCC=gcc \
  CROSS_COMPILE=aarch64-linux-gnu- \
  CROSS_COMPILE_ARM32=arm-linux-gnueabi- \
  LD=ld.lld AR=llvm-ar NM=llvm-nm \
  LLVM=1 LLVM_IAS=1 \
  selene_defconfig

make O=out ARCH=arm64 \
  CC=clang HOSTCC=gcc \
  CROSS_COMPILE=aarch64-linux-gnu- \
  CROSS_COMPILE_ARM32=arm-linux-gnueabi- \
  LD=ld.lld AR=llvm-ar NM=llvm-nm \
  LLVM=1 LLVM_IAS=1 \
  -j$(nproc)
```

## Known Gotchas (Quick Reference)

| Issue | Fix | Skill |
|-------|-----|-------|
| Clang IAS `.weak` error | `.weak` → `.globl` di `arch/arm64/lib/*.S` | build-system-fixes |
| `stpcpy` undefined | Tambah generic impl di `lib/string.c` | build-system-fixes |
| ZSTD_STATIC_ASSERT | Ganti ke C11 `_Static_assert` | build-system-fixes |
| vDSO32 `__NR_compat_*` | Tambah fallback defines | build-system-fixes |
| vDSO32 `.pad` symbolic | Force GAS untuk assembly | build-system-fixes |
| ReSukiSU symlink | Pakai relative path `../resukisu` | resukisu-integration |
| Telegram topic IDs | Hardcode di workflow (jangan pakai secrets) | ci-cd-github-actions |
| FPSGO 60+ undefined ref | `CONFIG_TRACEPOINTS=y` | defconfig-management |
| SHADOW_CALL_STACK panic | Jangan enable | defconfig-management |
| SLAB_FREELIST_HARDENED panic | Jangan enable | defconfig-management |
| /proc/config.gz stale | Fix `kernel/Makefile` line 125 | defconfig-management |
| Goodix prebuilt stack protector | Disable atau provide stubs | defconfig-management |
| Kaeru `flash_block` undefined | Ganti dengan `dd if= of=/dev/block/by-name/lk${SLOT}` | kaeru-integration |
| Kaeru DRAM comm tak terdeteksi | Pastikan `write_kaeru_comm()` di `board_late_init()` | kaeru-integration |
| Kaeru offset salah | Extract dari binary dengan Ghidra, jangan copy lancelot mentah | kaeru-integration |
| MTCMOS silent boot hang | Bounded `spm_wait_ack` di `clk-mt6768-pg.c` | build-system-fixes |
| Clang CFI callback trap | Match function pointer signatures (`ktd3136_bl` & `rdma_ioctl`) | build-system-fixes |
| 32-bit apps / HAL failure | `CONFIG_COMPAT=y` di `selene_defconfig` | defconfig-management |
| Touchscreen double-tap wake | `CONFIG_TOUCHSCREEN_COMMON=y` di `selene_defconfig` | defconfig-management |
| SCP IPI system deadlock | Bounded loop + mutex unlock saat timeout di `scp_ipi.c` | build-system-fixes |

## CRITICAL: Charger DTS — JANGAN UBAH TANPA HARDWARE VALIDATION

> **BRICK RISK** — Charger DTS changes menyebabkan phone brick (19 Sep 2026).

### Root Cause
```
CONFIG_MTK_CHARGER depends on MEDIATEK_SOLUTION → ga ada → config di-drop
→ Charger driver NEVER compiled → DTS values ga dibaca → Phone AMAN

Fix dependency → Charger driver ENABLED → Baca DTS values yang salah
→ PMIC overvoltage protection → HARDWARE BRICK
```

### Rules (WAJIB DIIKUTI)
1. **JANGAN ubah `battery_cv`** — value ini adalah hardware-rated voltage (4.35V untuk Selene)
2. **JANGAN enable `enable_sw_jeita`** tanpa testing di hardware nyata
3. **JANGAN tambah `hvdcp_charger_current`** tanpa validasi charger IC
4. **JANGAN ubah JEITA CV values** — sudah dioptimasi untuk hardware ini
5. **JANGAN asumsi LineageOS values aman** — device kita punya charger IC berbeda
6. **Kalau mau ubah charger config**, flash dulu ke hardware, test 24 jam, baru commit

### Safe Charger Configs (boleh di-enable)
| Config | Status | Catatan |
|---|---|---|
| `CONFIG_MTK_CHARGER` | ✅ enabled | Legitimate bug fix — charger driver seharusnya jalan |
| `CONFIG_SMB1351_USB_CHARGER` | ✅ enabled | Charger IC yang dipakai selene |
| `CONFIG_CHARGER_BQ2589X_CHARGER` | ✅ enabled | Charger IC alternatif |

### Dangerous Charger Changes (JANGAN LAKUKAN)
| Change | Bahaya | Brick Risk |
|---|---|---|
| `battery_cv > 4350000` | Overvoltage battery | 🔴 CRITICAL |
| `enable_sw_jeita` tanpa testing | JEITA protection interference | 🔴 HIGH |
| `hvdcp_charger_current > 2050000` | Overcurrent charging | 🟡 MEDIUM |
| `pd_vbus_upper_bound > 5000000` | PD voltage too high | 🟡 MEDIUM |
