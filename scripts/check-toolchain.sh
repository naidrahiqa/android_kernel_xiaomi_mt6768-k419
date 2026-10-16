#!/bin/bash
# ==============================================================================
# check-toolchain.sh — Guard: pastikan build lokal memakai Greenforce Clang,
#                      bukan system clang asal dari PATH.
# ==============================================================================
# Kenapa ada : 2026-10-15 HP sempat jalan build lokal yang tak sengaja memakai
#              system clang22.1.8, padahal AGENTS.md menyatakan build manual
#              memakai Greenforce Clang (PGO + ThinLTO + O3 + Polly). make
#              mengambil CC=clang dari PATH, jadi kalau greenforce-clang/ tidak
#              ada, build diam-diam jatuh ke clang bawaan sistem. Tidak ada
#              error, hasil build valid — hanya toolchain yang salah, dan
#              artefaknya nyangkut di perangkat. Guard ini menutup celah
#              "verifikasi vs kenyataan".
# Usage      : scripts/check-toolchain.sh [--quiet]
# Exit       : 0 = Greenforce terdeteksi | 1 = clang bukan Greenforce | 2 = clang tidak ada
# Deps       : clang (di PATH)
# Update     : kalau naik versi Greenforce, samakan GREENFORCE_MARKER / _MIN_MAJOR.
# ==============================================================================

set -u

# Root repo dihitung dari lokasi script, BUKAN dari $(pwd) — supaya saran PATH
# tetap benar walau dipanggil dari subdirektori mana pun.
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Vendor string khas Greenforce (banner /proc/version menulis "Cirrus clang").
# Kalau Greenforce ganti nama vendor, ubah di sini.
GREENFORCE_MARKER="Cirrus"
# Versi mayor minimum yang diharapkan (dari gf-clang-24.0.0).
GREENFORCE_MIN_MAJOR=24

QUIET=0
[ "${1:-}" = "--quiet" ] && QUIET=1

log() { [ "$QUIET" -eq 1 ] || printf '%s\n' "$*"; }
err() { printf '%s\n' "$*" >&2; }

# Saran PATH yang benar (berbasis repo root, bukan cwd).
LOCAL_CLANG="$REPO_ROOT/greenforce-clang/bin/clang"
SUGGEST_PATH="export PATH=\"$REPO_ROOT/greenforce-clang/bin:\$PATH\""

# ---1. clang ada di PATH? ----------------------------------------------------
if ! command -v clang > /dev/null 2>&1; then
	err "[check-toolchain] TIDAK ADA clang di PATH."
	if [ -x "$LOCAL_CLANG" ]; then
		err "  Toolchain repo-LOKAL ada di: $LOCAL_CLANG"
		err "  Tinggal export:  $SUGGEST_PATH"
	else
		err "  greenforce-clang/ juga tidak ada di repo. Install dulu."
	fi
	exit 2
fi

CLANG_BIN="$(command -v clang)"
BANNER="$(clang --version 2>/dev/null | head -1)"

# ---2. Apakah ini Greenforce? (cek vendor marker) ---------------------------
if ! printf '%s' "$BANNER" | grep -qi "$GREENFORCE_MARKER"; then
	err "[check-toolchain] GAGAL — clang ini BUKAN Greenforce:"
	err "  binary : $CLANG_BIN"
	err "  banner : $BANNER"
	err ""
	err "  Akibat: build LOLOS tanpa error, tapi PGO/Polly hilang diam-diam."
	err ""
	if [ -x "$LOCAL_CLANG" ]; then
		err "  Greenforce repo-LOKAL sudah ada, cuma belum masuk PATH. Fix:"
		err "    $SUGGEST_PATH"
	else
		err "  Perbaiki salah satu:"
		err "    a) $SUGGEST_PATH   # kalau greenforce-clang/ sudah ada"
		err "    b) install Greenforce dulu, lalu ulangi build."
	fi
	exit 1
fi

# ---3. (opsional) cek versi mayor minimum -----------------------------------
MAJOR="$(printf '%s' "$BANNER" | grep -oE 'version[[:space:]]+[0-9]+' | grep -oE '[0-9]+' | head -1)"
if [ -n "$MAJOR" ] && [ "$MAJOR" -lt "$GREENFORCE_MIN_MAJOR" ]; then
	err "[check-toolchain] PERINGATAN — banner Greenforce tapi versi lama:"
	err "  banner : $BANNER"
	err "  harap  : >= $GREENFORCE_MIN_MAJOR"
	err "  (lanjut build boleh, tapi cek apakah ini toolchain yang benar)"
fi

log "[check-toolchain] OK — Greenforce terdeteksi."
log "  binary : $CLANG_BIN"
log "  banner : $BANNER"
exit 0
