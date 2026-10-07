#!/usr/bin/env bash
# pick-safe.sh — pipeline cherry-pick aman untuk repo SHALLOW
#
# Repo ini `.git/shallow` (28 boundary). Karena itu:
#   - `git cherry`, `git rev-list --not HEAD`, `A..B --not HEAD` MENGHASILKAN
#     ANGKA PALSU (ribuan "belum ada" padahal sudah masuk).
#   - Satu-satunya cara seleksi yang bisa dipercaya = tes per-hunk.
#
# Pipeline (4 tahap, urutannya penting):
#   1. kandidat   : git log --no-merges --format=%H <range> --not HEAD -- <paths>
#   2. gap test   : git diff --quiet HEAD <upstream> -- <files>
#                   quiet = tree kita sudah sama dengan upstream = IN-SYNC (lewat)
#   3. forward    : git show --binary <h> | git apply --check -
#                   OK = benar-benar belum ada DAN bisa diaplikasi bersih
#   4. urut       : git rev-list --reverse --topo-order <range> (agar hunk lama
#                   keambil sebelum hunk baru yang bergantung padanya)
#
# Usage:
#   scripts/pick-safe.sh <range> <upstream-ref> -- <path...>
#   scripts/pick-safe.sh <range> <upstream-ref> --apply -- <path...>
#   WL="block fs" scripts/pick-safe.sh <range> <upstream-ref>
#   scripts/pick-safe.sh --resume          # lanjut dari keadaan terakhir
#
#   --apply    jalankan cherry-pick beneran (default: dry-run / laporan saja)
#   --limit N  hanya proses N kandidat pertama (debug pipeline kecil dulu)
#
# Output: laporan ke stdout + artefak ke .pick-safe/<ts>/
#   candidates.txt  in-sync.txt  gap.txt  take.txt  conflict.txt
#
# Exit: 0 = bersih (tak ada kandidat, atau semua sukses)
#       1 = ada conflict yang harus ditangani manual
#       2 = usage / precondition gagal
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 2

APPLY=0
LIMIT=0
RESUME=""
RANGE="" UPSTREAM="" WLPATHS=()

usage() { sed -n '2,26p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage 0 ;;
    --apply)   APPLY=1; shift ;;
    --limit)   LIMIT="${2:?}"; shift 2 ;;
    --resume)  RESUME=1; shift ;;
    --)        shift; break ;;
    -*)        echo "unknown option: $1" >&2; usage 2 ;;
    *)
      if [ -z "$RANGE" ]; then RANGE="$1"
      elif [ -z "$UPSTREAM" ]; then UPSTREAM="$1"
      else echo "unexpected arg: $1" >&2; usage 2
      fi
      shift ;;
  esac
done
[ $# -gt 0 ] && WLPATHS=("$@")

# Whitelist default. Bisa dioverride lewat env WL (spasi-separated) supaya
# bisa jalan tanpa argumen path.
if [ ${#WLPATHS[@]} -eq 0 ]; then
  if [ -n "${WL:-}" ]; then
    read -r -a WLPATHS <<<"$WL"
  else
    WLPATHS=(arch/arm64 block crypto fs include ipc kernel lib mm net security sound usr)
  fi
fi

if [ -n "$RESUME" ]; then
  LAST="$(ls -1dt .pick-safe/*/ 2>/dev/null | head -1 || true)"
  [ -n "$LAST" ] || { echo "ERROR: belum ada run untuk --resume" >&2; exit 2; }
  RUN="${LAST%/}"
  RANGE="$(cat "$RUN/range")" UPSTREAM="$(cat "$RUN/upstream")"
  read -r -a WLPATHS <"$RUN/paths"
  echo "resume: $RUN (range=$RANGE upstream=$UPSTREAM)"
else
  [ -n "$RANGE" ] || { echo "ERROR: <range> wajib" >&2; usage 2; }
  # upstream opsional: kalau cuma satu argumen, gap-test bandingkan ke ujung
  # range itu sendiri (bentuk paling umum "boundary..cip/tip").
  [ -n "$UPSTREAM" ] || UPSTREAM="${RANGE#*..}"
  RUN=".pick-safe/$(date +%Y%m%d-%H%M%S)"
  mkdir -p "$RUN" || exit 2
  printf '%s' "$RANGE"  >"$RUN/range"
  printf '%s' "$UPSTREAM" >"$RUN/upstream"
  printf '%s\n' "${WLPATHS[*]}" >"$RUN/paths"
fi

log() { printf '[pick-safe] %s\n' "$*"; }

# -- 0. precondition ----------------------------------------------------------
git rev-parse --verify -q "$UPSTREAM" >/dev/null || { echo "ERROR: upstream ref '$UPSTREAM' tak dikenal" >&2; exit 2; }
# RANGE boleh bentuk "A..B". `git rev-parse --verify` hanya menerima SATU object
# name, jadi "--verify A..B" selalu gagal — validate kedua ujungnya terpisah.
RANGE_A="${RANGE%%..*}"
RANGE_B="${RANGE#*..}"
[ "$RANGE_B" = "$RANGE" ] && RANGE_B="HEAD"
for _r in "$RANGE_A" "$RANGE_B"; do
  git rev-parse --verify -q "$_r" >/dev/null \
    || { echo "ERROR: ref '$_r' (dari range '$RANGE') tak dikenal" >&2; exit 2; }
done
if ! git rev-parse --is-shallow-repository 2>/dev/null | grep -q true; then
  log "catatan: repo bukan shallow — pipeline tetap jalan, tapi tes gap tetap dipakai"
fi
git diff --quiet || log "PERINGATAN: working tree kotor — cherry-pick bisa gagal"

# -- 1. kandidat --------------------------------------------------------------
log "1/4 kandidat: $RANGE --not HEAD -- ${WLPATHS[*]}"
git log --no-merges --format=%H "$RANGE" --not HEAD -- "${WLPATHS[@]}" \
  >"$RUN/candidates.txt" 2>"$RUN/candidates.err"
CAND=$(wc -l <"$RUN/candidates.txt" | tr -d ' ')
[ -s "$RUN/candidates.err" ] && sed 's/^/  ! /' "$RUN/candidates.err"

# urut topologis maju (lama dulu) — kandidat difilter dari daftar ini
git rev-list --reverse --topo-order "$RANGE" 2>/dev/null \
  | grep -F -x -f "$RUN/candidates.txt" >"$RUN/ordered.txt" || true
[ -s "$RUN/ordered.txt" ] || cp "$RUN/candidates.txt" "$RUN/ordered.txt"
ORDERED=$(wc -l <"$RUN/ordered.txt" | tr -d ' ')
log "kandidat=$CAND  urut-topo=$ORDERED"

# -- tahap 2 + 3 --------------------------------------------------------------
: >"$RUN/in-sync.txt"; : >"$RUN/gap.txt"
: >"$RUN/take.txt";    : >"$RUN/conflict.txt"; : >"$RUN/skip.txt"
n=0 taken=0 sync=0 conflict=0 skipped=0

while read -r h; do
  [ -n "$h" ] || continue
  n=$((n + 1))
  if [ "$LIMIT" -gt 0 ] && [ "$n" -gt "$LIMIT" ]; then
    log "--limit $LIMIT tercapai, sisa $(($ORDERED - n + 1)) kandidat tidak diproses"
    break
  fi
  subj="$(git log -1 --format=%s "$h" 2>/dev/null)"
  files="$(git show --name-only --format= "$h" 2>/dev/null | sed '/^$/d')"
  if [ -z "$files" ]; then
    echo "$h" >>"$RUN/skip.txt"; skipped=$((skipped + 1)); continue
  fi
  # hanya file yang masuk whitelist — diff harus dibatasi agar gap test valid
  # shellcheck disable=SC2086
  wl_files="$(printf '%s\n' $files | grep -x -f <(printf '%s\n' "${WLPATHS[@]}" \
    | sed 's|$|.*|') 2>/dev/null || true)"
  if [ -z "$wl_files" ]; then
    echo "$h" >>"$RUN/skip.txt"; skipped=$((skipped + 1)); continue
  fi

  # 2. gap test — tree kita vs upstream tree untuk file-file commit ini
  # shellcheck disable=SC2086
  if git diff --quiet HEAD "$UPSTREAM" -- $wl_files 2>/dev/null; then
    echo "$h" >>"$RUN/in-sync.txt"; sync=$((sync + 1))
    printf '  [%d/%s] IN-SYNC  %s %s\n' "$n" "$ORDERED" "${h:0:10}" "$subj"
    continue
  fi
  echo "$h" >>"$RUN/gap.txt"; gap=$(( ${gap:-0} + 1 ))

  # 3. forward test — apakah patch-nya sendiri bisa diaplikasi bersih?
  if ! git show --binary --format= "$h" 2>/dev/null | git apply --check - >/dev/null 2>&1; then
    echo "$h" >>"$RUN/conflict.txt"
    conflict=$((conflict + 1))
    printf '  [%d/%s] CONFLICT %s %s\n' "$n" "$ORDERED" "${h:0:10}" "$subj"
    continue
  fi

  echo "$h" >>"$RUN/take.txt"; taken=$((taken + 1))
  printf '  [%d/%s] TAKE     %s %s\n' "$n" "$ORDERED" "${h:0:10}" "$subj"

  if [ "$APPLY" = 1 ]; then
    if git cherry-pick -x "$h" >"$RUN/cherry-pick.log" 2>&1; then
      printf '            cherry-pick OK\n'
    else
      git cherry-pick --abort >/dev/null 2>&1 || true
      echo "$h" >>"$RUN/failed.txt"
      printf '            cherry-pick GAGAL (diaburkan) — lihat %s/cherry-pick.log\n' "$RUN"
    fi
  fi
done <"$RUN/ordered.txt"

# -- ringkasan ----------------------------------------------------------------
gap=${gap:-0}
{
  echo "range=$RANGE"
  echo "upstream=$UPSTREAM"
  echo "paths=${WLPATHS[*]}"
  echo "apply=$APPLY"
  echo "candidates=$CAND"
  echo "ordered=$ORDERED"
  echo "in_sync=$sync"
  echo "gap=$gap"
  echo "take=$taken"
  echo "conflict=$conflict"
  echo "skip=$skipped"
} >"$RUN/summary.txt"

echo
log "===== ringkasan ($RUN) ====="
log "kandidat   : $CAND"
log "in-sync    : $sync   (tree sudah sama dengan upstream — lewat)"
log "gap        : $gap    (beda dari upstream)"
log "  take     : $taken  (forward-apply bersih)"
log "  conflict : $conflict (perlu resolusi manual)"
log "  skip     : $skipped (file di luar whitelist / tanpa perubahan)"
[ "$APPLY" = 1 ] && log "mode       : APPLY (cherry-pick dieksekusi)"

if [ "$APPLY" = 1 ] && [ -s "$RUN/failed.txt" ]; then
  log "gagal apply: $(wc -l <"$RUN/failed.txt") — $(cat "$RUN/failed.txt" | tr '\n' ' ')"
  exit 1
fi
[ "$conflict" -gt 0 ] && { log "ada conflict — resolve manual, JANGAN pakai --theirs di seluruh tree"; exit 1; }
exit 0
