#!/usr/bin/env bash
# ==============================================================================
# check-upstream.sh — Cek patch mana dari upstream (cip / sub-tree driver) yang
#                     belum masuk ke kernel selene.
# ==============================================================================
# Usage:
#   scripts/check-upstream.sh                       # semua remote, default path
#   scripts/check-upstream.sh --remote cip          # hanya satu remote
#   scripts/check-upstream.sh -- mm fs block        # batasi ke path
#   scripts/check-upstream.sh --json                # output JSON
#   scripts/check-upstream.sh --fetch               # fetch dulu (lambat, butuh internet)
#
# Exit : 0 = tidak ada patch kurang | 1 = ada patch yang belum masuk | 2 = error
#
# CATATAN PENTING — repo ini SHALLOW:
#   git cherry / git log A..B --not HEAD menghasilkan angka PALSA di sini.
#   Skrip ini sengaja TIDAK memakainya untuk menyimpulkan "sudah masuk / belum".
# Existence patch ditentukan oleh forward-test:
#       git show --binary <sha> | git apply --check -
#   Kalau apply sukses -> patch itu BELUM ada di tree kita (kandidat sync).
#   Kalau apply gagal -> sudah ada dalam bentuk lain / tidak berlaku -> lewati.
#   Cara yang sama dipakai skill patch-sync (scripts/pick-safe.sh).
# ==============================================================================
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 2

JSON=0
DO_FETCH=0
REMOTES=()
PATHS=()

while [ $# -gt 0 ]; do
  case "$1" in
    --json)   JSON=1; shift ;;
    --fetch)  DO_FETCH=1; shift ;;
    --remote) REMOTES+=("${2:?}"); shift 2 ;;
    -h|--help) sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    --)       shift; PATHS=("$@"); break ;;
    -*)       echo "unknown option: $1" >&2; exit 2 ;;
    *)        PATHS+=("$1"); shift ;;
  esac
done

# Default: subtree yang paling sering berubah di tree ini. drivers/ dan sound/
# paling sering tertinggal karena port manual + rename simbol (lihat AGENTS.md).
if [ ${#PATHS[@]} -eq 0 ]; then
  PATHS=(drivers/thermal drivers/misc/mediatek net fs block mm kernel sound arch/arm64)
fi

[ ${#REMOTES[@]} -eq 0 ] && REMOTES=(cip upstream)

die() { echo "ERROR: $*" >&2; exit 2; }

git rev-parse --git-dir >/dev/null 2>&1 || die "bukan git repo"

if git rev-parse --is-shallow-repository 2>/dev/null | grep -q true; then
  :
fi

# Bersihkan path kosong supaya `git log -- <path>` tidak error.
NEAT_PATHS=()
for p in "${PATHS[@]}"; do [ -n "$p" ] && NEAT_PATHS+=("$p"); done
[ ${#NEAT_PATHS[@]} -gt 0 ] || die "tidak ada path yang bisa diproses"

TOTAL_MISSING=0

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr '\n' ' '
}

if [ "$JSON" = "1" ]; then
  printf '{"shallow":%s,"remotes":[' \
    "$(git rev-parse --is-shallow-repository 2>/dev/null | grep -q true && echo true || echo false)"
  first_rs=1
fi

for REMOTE in "${REMOTES[@]}"; do
  if ! git remote get-url "$REMOTE" >/dev/null 2>&1; then
    echo "WARNING: remote '$REMOTE' tidak ada, dilewati" >&2
    continue
  fi

  if [ "$DO_FETCH" = "1" ]; then
    echo "[fetch] $REMOTE ..." >&2
    git fetch --quiet "$REMOTE" 2>/dev/null || \
      echo "WARNING: fetch $REMOTE gagal (internet?), pakai ref lama" >&2
  fi

  # Setiap remote bisa punya beberapa branch; ambil yang relevan saja.
  case "$REMOTE" in
    cip)      REFS=("cip/linux-4.19.y-cip" "cip/linux-4.19.y") ;;
    upstream) REFS=("upstream/lineage-20" "upstream/kernel-tree") ;;
    *)        REFS=("$REMOTE/HEAD") ;;
  esac

  for REF in "${REFS[@]}"; do
    git rev-parse --verify -q "$REF" >/dev/null || continue
    URL="$(git remote get-url "$REMOTE" 2>/dev/null)"

    echo ""
    echo "=============================================================================="
    echo " remote : $REMOTE   ref: $REF"
    echo " url    : $URL"
    echo " path   : ${NEAT_PATHS[*]}"
    echo "=============================================================================="

    # Kumpulkan kandidat commit yang menyentuh path whitelist.
    # Karena repo shallow, daftar ini BISA over-inclusive (sudah masuk tapi tetap
    # muncul) — maka tiap kandidat di-forward-test sebelum dilaporkan.
    CAND_FILE="$(mktemp)"
    git log --no-merges --format='%H' "$REF" -- "${NEAT_PATHS[@]}" >"$CAND_FILE" 2>/dev/null

    CAND_COUNT="$(wc -l <"$CAND_FILE" | tr -d ' ')"
    echo " kandidat menyentuh path tsb : $CAND_COUNT   (over-inclusive, lihat catatan)"

    MISSING=0
    CHECKED=0
    while read -r H; do
      [ -z "$H" ] && continue
      CHECKED=$((CHECKED + 1))

      # Batasi laporan supaya tidak menjejak ribuan baris; kandidat yang tidak
      # dilaporkan tetap dihitung supaya total akurat.
      # tetap dihitung supaya total akurat.
      SUBJ="$(git log -1 --format='%s' "$H" 2>/dev/null)"

      if git show --binary "$H" 2>/dev/null | git apply --check - >/dev/null 2>&1; then
        MISSING=$((MISSING + 1))
        TOTAL_MISSING=$((TOTAL_MISSING + 1))
        echo "  [BELUM-MASUK] ${H:0:12}  $SUBJ"
        if [ "$JSON" = "1" ]; then
          [ "$first_rs" = "1" ] || printf ','
          first_rs=0
          printf '{"remote":"%s","ref":"%s","sha":"%s","subject":"%s"}' \
            "$REMOTE" "$REF" "$H" "$(json_escape "$SUBJ")"
        fi
      fi
    done <"$CAND_FILE"
    rm -f "$CAND_FILE"

    echo " --------------------------------------------------------------------------"
    echo " dicek: $CHECKED   belum-masuk: $MISSING"
    [ "$MISSING" -eq 0 ] && echo " -> subtree ini dianggap sudah sinkron (untuk path tsb)"
  done
done

if [ "$JSON" = "1" ]; then
  printf '],"total_missing":%d}' "$TOTAL_MISSING"
  echo
  exit "$([ "$TOTAL_MISSING" -gt 0 ] && echo 1 || echo 0)"
fi

echo ""
echo "=============================================================================="
echo " RINGKASAN"
echo "=============================================================================="
echo " total patch yang belum masuk : $TOTAL_MISSING"
if [ "$TOTAL_MISSING" -gt 0 ]; then
  echo ""
  echo " Untuk menerapkan: skill patch-sync (scripts/pick-safe.sh)."
  echo "  Ingat: verify per-hunk, jangan pernah-and-theirs untuk satu file utuh."
else
  echo " (tidak ada kandidat bersih pada path yang diperiksa)"
fi

[ "$TOTAL_MISSING" -gt 0 ] && exit 1 || exit 0