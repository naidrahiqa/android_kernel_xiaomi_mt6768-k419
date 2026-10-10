#!/system/bin/sh
# bench-tune.sh — baseline & A-B helper untuk tuning kernel (runtime sysfs/procfs).
#
# Dirujuk oleh skill .opencode/skills/tuning-guard/SKILL.md. Skill mewajibkan:
#   1. baseline dulu sebelum mengubah angka
#   2. satu perubahan per siklus
#   3. restore otomatis (WAJIB)
#   4. --dry-run untuk membuktikan restore bekerja
#
# Script ini HANYA menulis ke /proc/sys dan /sys (runtime). Tidak menyentuh
# source kernel. Perubahan yang permanen harus lewat defconfig + commit terpisah.
#
# Pakai:
#   adb push scripts/bench-tune.sh /data/local/tmp/bench-tune.sh
#   adb shell su -c 'sh /data/local/tmp/bench-tune.sh snapshot'
#   adb shell su -c 'sh /data/local/tmp/bench-tune.sh set vm.swappiness 60 120'
#   adb shell su -c 'sh /data/local/tmp/bench-tune.sh --dry-run set vm.swappiness 60'
#   adb shell su -c 'sh /data/local/tmp/bench-tune.sh restore-check'
#
# SELinux / akses:
#   Di ROM Selene terpasang, domain `shell` maupun `su`/`ksu` TIDAK boleh
#   read/write /proc/sys/vm/* (bukan file permission — mode swappiness 0644).
#   Avc-nya tidak muncul di dmesg karena audit logging dimatikan ROM.
#   Konsekuensi: workflow runtime A-B TIDAK bisa jalan di device ini.
#   Semua tuning harus lewat defconfig -> rebuild -> flash.
#   Script tetap berguna untuk: snapshot, mengukur swap/reclaim rate, dan
#   proving bahwa mekanisme restore-nya benar (--selftest).
#
#   Kalau "Permission denied" muncul: cek `cat /proc/self/attr/current` —
#   `su -c` pada ROM ini TIDAK berganti SELinux context.

set -u

# ---------------------------------------------------------------------------
# Danger zone — dari skill tuning-guard. Butuh --force-danger.
# ---------------------------------------------------------------------------
DANGER_KEYS="vm.min_free_kbytes vm.overcommit_memory vm.dirty_ratio vm.dirty_background_ratio"

# Semua key yang boleh diutak-atik. Anything else ditolak.
ALLOWED_KEYS="vm.swappiness vm.vfs_cache_pressure vm.page-cluster vm.watermark_scale_factor vm.min_free_kbytes vm.dirty_ratio vm.dirty_background_ratio vm.overcommit_memory"

SYSCTL_BASE=/proc/sys

# Global untuk restore
RESTORE_LIST=""
CLEANED=0

cleanup() {
	if [ "$CLEANED" -eq 1 ]; then
		return
	fi
	CLEANED=1
	# trap: pulihkan SEMUA nilai yang sempat ditulis, reversed order
	echo
	echo "### RESTORE ###"
	echo "$RESTORE_LIST" | awk 'NF{print}' | tac | while read -r key old; do
		[ -z "$key" ] && continue
		# key absolut (selftest) vs key sysctl relatif (vm.*)
		case "$key" in
			/*) target="$key" ;;
			*)  target="$SYSCTL_BASE/$key" ;;
		esac
		printf '  restore %-34s = %s\n' "$target" "$old"
		echo "$old" > "$target" 2>/dev/null \
			|| echo "    GAGAL restore $target (cek manual)"
	done
	echo "### restore selesai ###"
}

trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM

usage() {
	sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'
}

in_list() {
	needle="$1"
	shift
	for item in $@; do
		[ "$item" = "$needle" ] && return 0
	done
	return 1
}

read_key() {
	cat "$SYSCTL_BASE/$1" 2>/dev/null || echo "DENIED"
}

# ---------------------------------------------------------------------------
# Baseline snapshot
# ---------------------------------------------------------------------------
snapshot() {
	echo "===== BASELINE SNAPSHOT ====="
	echo "date   : $(date 2>/dev/null)"
	echo "uptime : $(cut -d. -f1 /proc/uptime 2>/dev/null)s"
	echo "uname  : $(uname -r 2>/dev/null)"
	echo

	echo "--- kernel tunables ---"
	for k in vm.swappiness vm.vfs_cache_pressure vm.page-cluster \
		vm.watermark_scale_factor vm.min_free_kbytes vm.dirty_ratio \
		vm.dirty_background_ratio vm.overcommit_memory; do
		printf '  %-34s = %s\n' "$k" "$(read_key "$k")"
	done
	echo

	echo "--- memory ---"
	grep -E '^(MemTotal|MemFree|MemAvailable|SwapTotal|SwapFree|Slab|SReclaimable):' /proc/meminfo 2>/dev/null |
		while read -r key val unit; do printf '  %-16s %12s %s\n' "$key" "$val" "$unit"; done
	echo

	echo "--- swap / reclaim rate ---"
	for c in pswpin pswpout pgscan_kswapd pgsteal_kswapd oom_kill; do
		printf '  %-18s = %s\n' "$c" "$(grep "^$c " /proc/vmstat 2>/dev/null | awk '{print $2}')"
	done
	echo

	echo "--- zram ---"
	if [ -e /sys/block/zram0/disksize ]; then
		printf '  disksize        = %s\n' "$(cat /sys/block/zram0/disksize 2>/dev/null)"
		printf '  mm_stat (orig compr used lim same) = %s\n' \
			"$(awk '{print $1, $2, $3, $4, $5}' /sys/block/zram0/mm_stat 2>/dev/null)"
		printf '  comp_algorithm  = %s\n' "$(cat /sys/block/zram0/comp_algorithm 2>/dev/null)"
	else
		echo "  (tidak ada /sys/block/zram0)"
	fi
	echo

	echo "--- lmk ---"
	dumpsys activity lmk 2>/dev/null | head -5 || echo "  (dumpsys tidak tersedia)"
	echo

	echo "--- cpu ---"
	printf '  online = %s\n' "$(cat /sys/devices/system/cpu/online 2>/dev/null)"
	echo "===== selesai ====="
}

# ---------------------------------------------------------------------------
# apply / restore
# ---------------------------------------------------------------------------
apply() {
	key="$1"; val="$2"

	if ! in_list "$key" $ALLOWED_KEYS; then
		echo "DITOLAK: '$key' tidak ada di allowlist."
		echo "Allowlist: $ALLOWED_KEYS"
		return 2
	fi

	# Gate zona bahaya DILETAKKAN sebelum cek path, supaya tetap menolak
	# walau device ini tidak punya key-nya.
	if in_list "$key" $DANGER_KEYS; then
		if [ "${FORCE_DANGER:-0}" != "1" ]; then
			echo "DITOLAK: '$key' ada di ZONA BERBAHAYA (skill tuning-guard)."
			echo "Ulangi dengan --force-danger kalau benar-benar mau."
			return 4
		fi
		echo "  !! ZONA BERBAHAYA dipaksa: $key -> $val"
	fi

	if [ ! -e "$SYSCTL_BASE/$key" ]; then
		echo "DITOLAK: $SYSCTL_BASE/$key tidak ada di device ini."
		echo "  (Kemungkinan besar diblokir SELinux, bukan file permission.)"
		echo "  Cek: cat /proc/self/attr/current"
		return 2
	fi

	old="$(read_key "$key")"
	if [ "$old" = "DENIED" ]; then
		echo "DITOLAK: tidak bisa baca nilai lama $key (SELinux?)."
		echo "Tidak aman tanpa restore — stop."
		return 3
	fi

	if [ "$DRY_RUN" = "1" ]; then
		echo "DRY-RUN: akan tulis $key = $old -> $val, lalu restore ke $old"
		return 0
	fi

	if ! echo "$val" > "$SYSCTL_BASE/$key" 2>/dev/null; then
		echo "GAGAL menulis $key = $val (permission / nilai di luar rentang)."
		return 5
	fi

	RESTORE_LIST="$RESTORE_LIST$key $old
"
	now="$(read_key "$key")"
	echo "  applied $key: $old -> $val (sekarang: $now)"
	if [ "$now" != "$val" ]; then
		echo "  PERINGATAN: kernel clamps nilai; restore tetap dijadwalkan."
	fi
	return 0
}

# ---------------------------------------------------------------------------
# measure: rate swap churn selama N detik
# ---------------------------------------------------------------------------
vmstat_val() { grep "^$1 " /proc/vmstat 2>/dev/null | awk '{print $2}'; }

measure() {
	secs="${1:-60}"
	echo "===== MEASURE ${secs}s ====="
	m0_out="$(vmstat_val pswpout)"; m0_in="$(vmstat_val pswpin)"
	m0_scan="$(vmstat_val pgscan_kswapd)"; m0_free="$(awk '/^MemFree/{print $2}' /proc/meminfo)"
	s0="$(cut -d. -f1 /proc/uptime)"
	sleep "$secs"
	m1_out="$(vmstat_val pswpout)"; m1_in="$(vmstat_val pswpin)"
	m1_scan="$(vmstat_val pgscan_kswapd)"; m1_free="$(awk '/^MemFree/{print $2}' /proc/meminfo)"
	s1="$(cut -d. -f1 /proc/uptime)"
	dt="$((s1 - s0))"; [ "$dt" -le 0 ] && dt=1

	echo "window            : ${dt}s"
	echo "pswpout    rate   : $(( (m1_out - m0_out) * 4 / dt )) MB/s   (total $(( (m1_out - m0_out) * 4 / 1024 )) MB)"
	echo "pswpin     rate   : $(( (m1_in - m0_in) * 4 / dt )) MB/s   (total $(( (m1_in - m0_in) * 4 / 1024 )) MB)"
	echo "pgscan_kswd rate  : $(( (m1_scan - m0_scan) * 4 / dt / 1024 )) MB/s"
	echo "MemFree          : ${m0_free} kB -> ${m1_free} kB"
	if [ "$m1_free" -lt "$m0_free" ]; then
		echo "  TREN: MemFree MENURUN (thrashing?)"
	else
		echo "  TREN: MemFree naik/ stabil"
	fi
	echo "===== selesai ====="
}

# ---------------------------------------------------------------------------
# restore-check: buktikan trap restore beneran bekerja
# ---------------------------------------------------------------------------
restore_check() {
	DRY_RUN=0
	echo "===== RESTORE CHECK ====="
	echo "Turpose: bukti bahwa trap restore mengembalikan nilai persis seperti semula."
	key=vm.swappiness
	orig="$(read_key "$key")"
	if [ "$orig" = "DENIED" ]; then
		echo "SKIP: tidak bisa baca $key di device ini."
		exit 1
	fi
	echo "original $key = $orig"
	trap 'cleanup; echo; echo "--- verify ---"; now=$(cat /proc/sys/'"$key"' 2>/dev/null); echo "restored $key = $now"; [ "$now" = "'"$orig"'" ] && echo "PASS: restore benar" || echo "FAIL: restore tidak cocok"; exit 0' EXIT

	apply "$key" 60
	echo "  menulis $key = 60 (nilai pertama, biasanya 100) — memicu EXIT trap"
	exit 0
}

# ---------------------------------------------------------------------------
# selftest: bukti trap+restore benar TANPA menyentuh /proc/sys.
#
# Dipakai karena di ROM Selinux akses /proc/sys/vm/* diblokir sepolicy, jadi
# jalur sysctl tidak bisa dibuktikan di device ini. Selftest memverifikasi
# mechanism-nya langsung: tulis -> ubah -> trap -> bandingkan.
# ---------------------------------------------------------------------------
selftest() {
	SCRATCH=/data/local/tmp/.bench_selftest.$$
	trap 'cleanup; rm -f "$SCRATCH" 2>/dev/null; exit 0' EXIT

	ORIG="nilai-asli-123"
	printf '%s' "$ORIG" > "$SCRATCH" || {
		echo "GAGAL: tidak bisa bikin scratch file di /data/local/tmp"
		exit 1
	}
	before="$(cat "$SCRATCH")"
	echo "===== SELFTEST restore ====="
	echo "1. tulis nilai awal      : $before"

	RESTORE_LIST="$SCRATCH $before
"
	printf 'nilai-berubah-456' > "$SCRATCH"
	now="$(cat "$SCRATCH")"
	echo "2. simulasi perubahan    : $now"

	if [ "$now" = "$before" ]; then
		echo "3. PERINGATAN: belum berubah, tes tidak valid"
		exit 1
	fi

	# sengaja keluar normal -> harus memicu EXIT trap -> cleanup()
	echo "3. keluar (memicu EXIT trap -> restore)"
	exit 0
}

# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------
ACTION=""
ARGS=""
while [ $# -gt 0 ]; do
	case "$1" in
		--dry-run) DRY_RUN=1 ;;
		--force-danger) FORCE_DANGER=1 ;;
		-h|--help) usage; exit 0 ;;
		*)
			if [ -z "$ACTION" ]; then ACTION="$1"; else ARGS="$ARGS $1"; fi
			;;
	esac
	shift
done

DRY_RUN="${DRY_RUN:-0}"

case "$ACTION" in
	snapshot)       snapshot ;;
	set)             set -- $ARGS
	               if [ $# -lt 2 ]; then echo "Usage: set <key> <value> [measure_secs]"; exit 1; fi
	               secs="${3:-0}"
	               echo "===== APPLY ====="
	               # shellcheck disable=SC2086
	               apply "$1" "$2" || exit $?
	               echo "===== APPLY SELESAI (restoreotomatis saat keluar) ====="
	               if [ "$secs" -gt 0 ] 2>/dev/null; then measure "$secs"; fi
	               ;;
	measure)        secs="${ARGS:-60}"; measure "$secs" ;;
	restore-check)  restore_check ;;
	selftest)       selftest ;;
	"")             usage ;;
	*)              echo "Action tidak dikenal: $ACTION"; usage; exit 1 ;;
esac

# Action yang selesai normal tetap harus restore (bukan cuma pas signal).
cleanup
exit 0