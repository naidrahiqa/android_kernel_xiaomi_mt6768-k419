# CHANGELOG — Mocchipyon Edition (MT6768 / Linux 4.19 CIP)

Daftar perubahan, porting, backport security, dan update komponen pada Mocchipyon Kernel.

## 2026-09-22 — ReSukiSU v4.2.0-rc2 Upstream (KSU_VERSION 35160)

- **ReSukiSU v4.2.0-rc2 (`5cfdd725`, KSU_VERSION 35160):** `resukisu/`
  - Synced driver with upstream ReSukiSU `v4.2.0-rc2` + latest commits from `main` (commit `5cfdd725`).
  - Total upstream commit count: 4460.
  - **Critical Version Pin Fix:** Pinned fallback version in `resukisu/Kbuild` (`KSU_LOCAL_VERSION := 4460`, `KSU_TAG_NAME := v4.2.0-rc2`, `KSU_COMMIT_SHA := 5cfdd725`). Memperbaiki issue di mana dynamic `git rev-list --count HEAD` sebelumnya menghitung total commit kernel Linux (834.314 commit) sehingga KSU_VERSION melonjak ke 865.014. Formula benar: `30000 + 4460 + 700 = 35160`.
  - Updated notification script `.github/scripts/notify-telegram.sh` to extract and display both tag and version code (`v4.2.0-rc2 (35160)`).
  - Added `.github/scripts/generate-ksu-notes.sh` and skill `.opencode/skills/ksu-version-management/SKILL.md`.

## 2026-09-22 — CI & Telegram Notifications Rework

- **Dual-target Telegram notifications:**
  - Build alerts, status, and changelog sent to CI topic in supergroup (`TOPIC_CI=32`).
  - Kernel zip (`.zip`) exclusively dispatched as document to private release channel (`TELEGRAM_CHANNEL_ID`).
  - Replaced markdown formatting with HTML parse mode to eliminate unescaped character parsing failures.
  - Hardcoded topics directly in workflow script to bypass GitHub secrets restrictions.

## 2026-09-19 — NoMount v20 & ReSukiSU Manual Hook Integration

- **Systemless Path Redirection:** Integrated NoMount v20 (`maxsteeel/nomount`) with keyring-based control.
- **Root Solution:** Integrated ReSukiSU with non-GKI manual hook mode (`CONFIG_KSU_MANUAL_HOOK=y`).
