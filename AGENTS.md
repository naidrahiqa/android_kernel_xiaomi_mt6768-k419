# AGENTS.md — MT6768 Kernel (Mocchipyon Edition)

Baca file ini dulu sebelum kerja di repo ini. **File ini orchestrator** — untuk detail task, load skill terkait dari `.opencode/skills/*/SKILL.md`.

## Daftar Skill

| Skill | File | Trigger |
|---|---|---|
| **MT6768 Kernel** | `.opencode/skills/mt6768-kernel/SKILL.md` | **Master skill** — overview, hardware, build commands, file locations |
| Build System Fixes | `.opencode/skills/build-system-fixes/SKILL.md` | Clang IAS, stpcpy, LTO, ZSTD, UAPI headers, vDSO32, assembly errors |
| ReSukiSU Integration | `.opencode/skills/resukisu-integration/SKILL.md` | KernelSU driver, manual hooks, KSU_VERSION, manager APK |
| NoMount | `.opencode/skills/nomount/SKILL.md` | Systemless path redirection, VFS hooks, keyring control |
| CI/CD (GitHub Actions) | `.opencode/skills/ci-cd-github-actions/SKILL.md` | Workflow, Telegram notif, release automation, build debugging |
| Defconfig Management | `.opencode/skills/defconfig-management/SKILL.md` | Config dependency chains, gotchas, debug workflow |

**Cara pakai:** Saat dapat task, load skill yang sesuai dari tabel di atas.

## Konteks Project

- **Device:** Xiaomi Selene (Redmi 9 / Redmi 9A), codename **selene**, MediaTek MT6768 (Helio G85).
- **Kernel:** Linux 4.19.325 (CIP stable backport), **non-GKI**, **STATUS: UNSTABLE/PORTING**.
- **Branch:** `Mocchipyon23.2`
- **Toolchain:** Greenforce Clang (LLVM/Clang, PGO+ThinLTO+O3+Polly)
- **Root solution:** ReSukiSU (`ReSukiSU/ReSukiSU`, manual hook mode `CONFIG_KSU_MANUAL_HOOK=y`).
- **Systemless:** NoMount v20 (`maxsteeel/nomount`, keyring-based control).
- **Build variants:** Single universal kernel — works on MIUI/HyperOS and AOSP-based ROMs.
- **Reference:** `/home/naidra/Projects/Kernel/android_kernel_xiaomi_selene` (4.14 stable, branch `phrolova`)

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
