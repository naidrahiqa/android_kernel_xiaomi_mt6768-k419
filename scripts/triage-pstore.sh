#!/usr/bin/env bash
# ==============================================================================
# triage-pstore.sh — Baca /sys/fs/pstore dari device selene, klasifikasi tiap
#                     artefak, dan cek relevansinya terhadap build yang sekarang.
# ==============================================================================
# Usage:
#   scripts/triage-pstore.sh                  # ringkas + klasifikasi
#   scripts/triage-pstore.sh --full           # simpan artefak penuh ke pstore-dump/
#   scripts/triage-pstore.sh --save <dir>     # simpan ke dir tertentu
#   ADB="adb -s 192.168.58.17:5555" scripts/triage-pstore.sh
#
# Exit : 0 = tidak ada temuan kritis | 1 = ada Oops/BUG | 2 = gagal (device/root)
#
# Kenapa script ini ada:
#   pstore hanya berisi log boot SEBELUMNYA. Dmesg ikut hilang saat reboot, jadi
#   artefak crash hanya bisa dibaca dari sini. Tapi artefak itu bisa berumur
#   berhari-hari — jadi WAJIB cek versi kernel yang tertulis di dalam artefak
#   sebelum menyimpulkan crash terjadi di build yang sekarang.
#   Lihat docs/issues/0001: sempat salah baca karena build yang crash ternyata
#   belum memuat fix-nya sama sekali.
# ==============================================================================
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DUMP="$ROOT/pstore-dump"
ADB="${ADB:-adb}"

SAVE=0
SAVE_DIR=""
for a in "$@"; do
  case "$a" in
    --full)   SAVE=1 ;;
    --save)   SAVE=1 ;;
    --save=*) SAVE=1; SAVE_DIR="${a#--save=}" ;;
    -h|--help) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown arg: $a" >&2; exit 2 ;;
  esac
done
[ -n "$SAVE_DIR" ] || SAVE_DIR="$DUMP/$(date +%Y%m%d-%H%M%S)"

die() { echo "ERROR: $*" >&2; exit 2; }

state="$($ADB get-state 2>/dev/null || true)"
[ "$state" = "device" ] || die "no device (adb get-state: '${state:-none}')"

# pstore butuh root, jadi selalu lewat `su`.
AS_ROOT() {
  $ADB shell su -c "$1" 2>/dev/null
}

run_cmd() {
  AS_ROOT "$1" | tr -d '\r'
}

# Argumen harus dipisah jadi beberapa argv, bukan satu string: `adb shell "$1"`
# akan mengirim "uname -r" sebagai satu argumen sehingga flag-nya hilang.
run_cmd_noroot() {
  $ADB shell "$@" 2>/dev/null | tr -d '\r'
}

# Menarik artefak lewat `adb shell su -c "cat ..."` jauh lebih tahan terhadap
# quirk quoting shell Android daripada meny concatenate grep -A28 per pola,
# jadi artefak ditarik sekali lalu diproses di host.
TMPD="$(mktemp -d)"
trap 'rm -rf "$TMPD"' EXIT

pull_artifact() {
  local name="$1" dest="$TMPD/$1"
  if [ -s "$dest" ]; then
    return 0
  fi
  $ADB shell su -c "cat /sys/fs/pstore/$name" >"$dest" 2>/dev/null
  [ -s "$dest" ]
}

count_in_pstore() {
  local pat="$1" name="$2" n
  n="$(grep -a -c -- "$pat" "$TMPD/$name" 2>/dev/null)"
  n="$(printf '%s' "$n" | tail -1)"
  case "$n" in
    ''|*[!0-9]*) n=0 ;;
  esac
  printf '%s' "$n"
}

has_in_pstore() {
  grep -a -q -- "$1" "$TMPD/$2" 2>/dev/null
}

artifact_meta() {
  $ADB shell su -c "stat -c %y /sys/fs/pstore/$1" 2>/dev/null | tr -d '\r'
}

# --- build yang sedang berjalan ------------------------------------------------
CUR_UNAME="$(run_cmd_noroot uname -r)"
CUR_SHA="$(printf '%s' "$CUR_UNAME" | grep -o 'g[0-9a-f]\{12\}' | head -1)"
CUR_SHA="${CUR_SHA#g}"

[ "$SAVE" = "1" ] && { mkdir -p "$SAVE_DIR" || die "gagal mkdir $SAVE_DIR"; }

echo "=============================================================================="
echo " pstore triage"
echo "=============================================================================="
echo "device build sekarang : $CUR_UNAME"
[ -n "$CUR_SHA" ] && echo "sha sekarang          : $CUR_SHA"
echo "himpunan boundary     : $(wc -l < "$ROOT/.git/shallow" 2>/dev/null || echo '?') (shallow)"
echo

# --- daftar artefak ------------------------------------------------------------
FILES="$(run_cmd 'ls -1 /sys/fs/pstore 2>/dev/null')"
if [ -z "$FILES" ]; then
  echo "(tidak ada /sys/fs/pstore di device ini — pstore/ramoops belum aktif?)"
  exit 2
fi

CRITICAL=0
# `... | while read` jalan di subshell, jadi penanda kritis dikumpulkan di file,
# bukan variabel. Wajib di-reset supaya sisa run sebelumnya tidak ikut terbaca.
: > /tmp/.ps_critical

printf '%s\n' "$FILES" | while read -r f; do
  [ -z "$f" ] && continue

  pull_artifact "$f" || { echo "  (gagal dibaca, skip)"; continue; }
  if [ "$SAVE" = "1" ]; then
    cp "$TMPD/$f" "$SAVE_DIR/$f" 2>/dev/null
  fi

  echo "------------------------------------------------------------------------------"
  echo "artefak : $f"
  meta="$(artifact_meta "$f")"
  [ -n "$meta" ] && echo "  waktu : $meta"

  # versi kernel yang tertulis DI DALAM artefak
  art_sha="$(grep -ao 'g[0-9a-f]\{12\}' "$TMPD/$f" 2>/dev/null | head -1)"
  art_sha="${art_sha#g}"
  if [ -n "$art_sha" ]; then
    if [ "$art_sha" = "$CUR_SHA" ]; then
      echo "  build : g$art_sha  << SAMA dengan build sekarang"
    else
      echo "  build : g$art_sha  << BEDA dari build sekarang"
    fi
  else
    echo "  build : (tidak ada banner versi di artefak ini)"
  fi

  # --- klasifikasi ------------------------------------------------------------
  oops="$(count_in_pstore 'Internal error: Oops' "$f")"
  warn="$(count_in_pstore '^WARNING:' "$f")"
  bug="$(count_in_pstore 'kernel BUG at' "$f")"
  callt="$(count_in_pstore 'Call trace:' "$f")"
  frz="$(count_in_pstore 'Freezing of tasks failed' "$f")"
  panic="$(count_in_pstore 'Kernel panic' "$f")"

  echo "  oops=${oops:-0} panic=${panic:-0} BUG=${bug:-0} WARNING=${warn:-0} CallTrace=${callt:-0} freezeFail=${frz:-0}"

  if [ "$oops" -gt 0 ] || [ "$panic" -gt 0 ] || [ "$bug" -gt 0 ]; then
    echo "  >>> KRITIS: kernel crash di artefak ini"
    # `-e` per pola: toybox grep tidak bisa `\|` seperti GNU grep.
    grep -a -A28 -m1 -e 'Internal error: Oops' -e 'Kernel panic' -e 'kernel BUG at' "$TMPD/$f" 2>/dev/null \
      | sed 's/^/      /'
    echo "$f" >> /tmp/.ps_critical
  fi

  # signature yang sudah pernah kita jumpai (docs/issues/)
  if has_in_pstore 'remove_request' "$f"; then
    echo "  -> signature issue 0001 (adios remove_request+0x38)"
  fi
  if has_in_pstore 'irq_set_irq_wake' "$f"; then
    echo "  -> signature Goodix 'Unbalanced IRQ 141 wake disable'"
  fi
  if [ "$frz" -gt 0 ]; then
    echo "  -> signature issue 0004 (suspend dibatalkan, FUSE waiter)"
  fi
  if has_in_pstore 'CFS disabled for this arch' "$f"; then
    echo "  -> boot-up warning, biasanya tak fatal"
  fi
done

echo "------------------------------------------------------------------------------"
if [ -s /tmp/.ps_critical ]; then
  CRITICAL=1
  echo "ADA artefak dengan crash kritis:"
  sed 's/^/  - /' /tmp/.ps_critical
else
  echo "Tidak ada Oops/panic di pstore."
fi
[ "$SAVE" = "1" ] && echo "artefak penuh disimpan di: $SAVE_DIR"
exit "$CRITICAL"