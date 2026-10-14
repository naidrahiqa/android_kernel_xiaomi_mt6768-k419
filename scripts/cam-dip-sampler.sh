#!/usr/bin/env bash
# Reproduksi + capture sampler CQ DIP (eksperimen build ke-2, issue 0016).
#
# Pakai:  ./scripts/cam-dip-sampler.sh [serial]
# Defaults serial = device USB pertama yang terlihat.
#
# Alur:
#   1. bersihkan dmesg (marker waktu)
#   2. tekan shutter  : input tap 540 1992  (Foto + zoom 1.0X)
#   3. tunggu 15 detik setelah tap
#   4. dump dmesg ke log-dump/cam-dip-<label>/ + tampilkan hanya baris instrumen
#
# Tidak ada perubahan state HP selain satu ketukan shutter.

set -uo pipefail

SERIAL="${1:-}"
LABEL="$(date +%d%m%Y-%H%M%S)"
OUT_DIR="log-dump/cam-dip-${LABEL}"
SHUTTER_TAP="${SHUTTER_TAP:-540 1992}"
WAIT_AFTER="${WAIT_AFTER:-15}"

if [ -z "$SERIAL" ]; then
	SERIAL="$(adb devices | awk 'NR>1 && $2=="device" {print $1; exit}')"
fi
if [ -z "$SERIAL" ]; then
	echo "ERROR: tidak ada device adb. Jalankan 'adb devices' atau pass serial." >&2
	exit 1
fi
echo "== serial : $SERIAL"

adb -s "$SERIAL" wait-for-device
mkdir -p "$OUT_DIR"

# Sanity: device harus jalan kernel yang punya sampler.
KREL="$(adb -s "$SERIAL" shell uname -r | tr -d '\r')"
echo "== kernel : $KREL"

adb -s "$SERIAL" shell 'su -c "dmesg -c > /dev/null"' >/dev/null 2>&1

echo "== reproduce: shutter tap ($SHUTTER_TAP)"
adb -s "$SERIAL" shell input tap $SHUTTER_TAP
sleep "$WAIT_AFTER"

adb -s "$SERIAL" shell dmesg            > "$OUT_DIR/dmesg.txt"     2>/dev/null
adb -s "$SERIAL" shell 'su -c "cat /proc/interrupts"' > "$OUT_DIR/interrupts.txt" 2>/dev/null

echo "== dmesg barsis: $(wc -l < "$OUT_DIR/dmesg.txt")"

echo
echo "== DIPSMP (register signature per sampel)"
grep -c 'DIPSMP'  "$OUT_DIR/dmesg.txt" | sed 's/^/   count = /'
grep 'DIPSMP'  "$OUT_DIR/dmesg.txt" | head -40

echo
echo "== DIPCQSNAP (isi descriptor CQ0 saat base diprogram ulang)"
grep -c 'DIPCQSNAP' "$OUT_DIR/dmesg.txt" | sed 's/^/   count = /'
grep 'DIPCQSNAP' "$OUT_DIR/dmesg.txt" | head -40

echo
echo "== IRQ dip1"
grep -i 'dip1' "$OUT_DIR/interrupts.txt" || echo "   (tidak ada baris dip1)"

echo
echo "== jejak timeout / CQ"
grep -iE 'CMDQ|timeout|-110|EOF' "$OUT_DIR/dmesg.txt" | tail -20

echo
echo "Log lengkap: $OUT_DIR/dmesg.txt"
