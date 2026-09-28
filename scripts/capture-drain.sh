#!/usr/bin/env bash
# capture-drain.sh — tangkap data battery drain device selene (Redmi 10) via adb
#
# Usage:
#   scripts/capture-drain.sh snapshot <label>      # capture sekali -> drain-dump/<label>-<ts>/
#   scripts/capture-drain.sh compare <A> <B>       # delta dua snapshot -> report.md di folder B
#   scripts/capture-drain.sh watch <menit>         # snapshot, istirahat, snapshot, compare
#
# Rencana lengkap: .opencode/plans/drain-data-capture.md
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DUMP="$ROOT/drain-dump"
ADB="${ADB:-adb}"
USE_ROOT=0
FAILED=()
SNAP_DIR=""

die() { echo "ERROR: $*" >&2; exit 1; }

check_device() {
	local state
	state="$($ADB get-state 2>/dev/null || true)"
	[ "$state" = "device" ] ||
		die "no device (adb get-state: '${state:-none}'). Colok HP, aktifkan USB debugging, setujui RSA."
}

detect_root() {
	if $ADB shell "su -c id" 2>/dev/null | tr -d '\r' | grep -q "uid=0"; then
		USE_ROOT=1
	fi
}

# Jalankan perintah sh di device. Pakai stdin (tanpa masalah quoting).
sh_run() {
	if [ "$USE_ROOT" = 1 ]; then
		printf '%s\n' "$1" | $ADB shell "su -c sh" 2>/dev/null | tr -d '\r'
	else
		printf '%s\n' "$1" | $ADB shell "sh" 2>/dev/null | tr -d '\r'
	fi
}

# grab <nama-file> <butuh-root 0/1> <perintah sh device>
grab() {
	local name="$1" need_root="$2" cmd="$3" out="$SNAP_DIR/$1"
	if [ "$need_root" = 1 ] && [ "$USE_ROOT" != 1 ]; then
		echo "(skip: butuh root)" >"$out"
		FAILED+=("$name:no-root")
		return
	fi
	if sh_run "$cmd" >"$out" 2>/dev/null && [ -s "$out" ]; then
		:
	else
		echo "(gagal)" >"$out"
		FAILED+=("$name:err")
	fi
}

snapshot() {
	local label="$1" ts epoch
	check_device
	detect_root
	ts="$(date +%Y%m%d-%H%M%S)"
	epoch="$(date +%s)"
	SNAP_DIR="$DUMP/${label}-${ts}"
	mkdir -p "$SNAP_DIR" || die "gagal bikin $SNAP_DIR"
	echo "snapshot -> $SNAP_DIR (root=$USE_ROOT)"

	grab battery.txt 0 'for f in capacity current_now voltage_now temp status type online; do printf "%s=" "$f"; cat /sys/class/power_supply/battery/$f 2>/dev/null || echo "?"; done; echo; echo "--- dumpsys battery ---"; dumpsys battery'
	grab cpu_freq.txt 0 'for p in /sys/devices/system/cpu/cpufreq/policy*; do echo "== $p"; for f in scaling_cur_freq scaling_max_freq cpuinfo_cur_freq; do printf "%s=" "$f"; cat $p/$f 2>/dev/null || echo "?"; done; echo "-- time_in_state"; cat $p/stats/time_in_state 2>/dev/null; done'
	grab gpu_freq.txt 1 'echo "-- opp_freq"; cat /proc/gpufreq/gpufreq_opp_freq 2>/dev/null; echo "-- var_dump"; cat /proc/gpufreq/gpufreq_var_dump 2>/dev/null | head -80'
	grab ppm.txt 1 'echo "== enabled"; cat /proc/ppm/enabled 2>/dev/null; echo "== policy_status"; cat /proc/ppm/policy_status 2>/dev/null; echo "== dump_power_table"; cat /proc/ppm/dump_power_table 2>/dev/null | head -80'
	grab thermal.txt 1 'for d in /sys/class/thermal/cooling_device*; do printf "%s=" "$(cat $d/type 2>/dev/null)"; cat $d/cur_state 2>/dev/null; done; echo "== thermal_zone"; for z in /sys/class/thermal/thermal_zone*; do printf "%s=" "$(cat $z/type 2>/dev/null)"; cat $z/temp 2>/dev/null; done'
	grab wakelock.txt 1 'echo "== wake_lock"; cat /sys/power/wake_lock 2>/dev/null; echo "== wake_unlock"; cat /sys/power/wake_unlock 2>/dev/null; echo "== wakeup_reasons"; for f in /sys/kernel/wakeup_reasons/*; do echo "-- $f"; cat $f 2>/dev/null; done'
	grab batterystats.txt 0 'dumpsys batterystats --checkin'
	grab batterystats-full.txt 0 'dumpsys batterystats'
	grab alarm.txt 0 'dumpsys alarm'
	grab power.txt 0 'dumpsys power'
	grab procstat.txt 0 'echo "== /proc/stat"; cat /proc/stat; echo; echo "== /proc/interrupts"; head -80 /proc/interrupts; echo; echo "== top"; top -Hb -n1 2>/dev/null | head -60'
	grab dmesg.txt 1 'dmesg'

	# logcat: potong 2MB terakhir, gzip (dihitung di host)
	sh_run 'logcat -b all -d' 2>/dev/null | tail -c 2097152 | gzip >"$SNAP_DIR/logcat.txt.gz"
	[ -s "$SNAP_DIR/logcat.txt.gz" ] || { echo "(gagal)" >"$SNAP_DIR/logcat.txt.gz"; FAILED+=("logcat:err"); }

	local failed="(tidak ada)"
	[ "${#FAILED[@]}" -gt 0 ] && failed="${FAILED[*]}"
	cat >"$SNAP_DIR/meta.txt" <<EOF
label=$label
timestamp=$ts
epoch=$epoch
iso=$(date --iso-8601=seconds)
uname=$(sh_run 'uname -a' | head -1)
device=$($ADB get-serialno 2>/dev/null || echo "?")
root=$USE_ROOT
battery_capacity=$(sh_run 'cat /sys/class/power_supply/battery/capacity' | head -1)
failed=$failed
EOF
	echo "selesai: ${#FAILED[@]} item gagal/skip${FAILED[*]:+ (${FAILED[*]})}"
	echo "$SNAP_DIR"
}

resolve_dir() {
	local a="$1"
	if [ -d "$DUMP/$a" ]; then
		echo "$DUMP/$a"
	else
		ls -d "$DUMP/$a"* 2>/dev/null | sort | tail -1
	fi
}

meta_get() { grep -m1 "^$2=" "$1/meta.txt" 2>/dev/null | cut -d= -f2-; }

# ekstrak "policy freq usec" dari cpu_freq.txt
tis_pairs() {
	awk '/^== /{p=$NF; sub(".*/","",p); tis=0} /^-- time_in_state/{tis=1; next} tis && /^[0-9]+ [0-9]+/{print p,$1,$2}' "$1"
}

# selisih time_in_state dua snapshot per policy (baris: policy freq usec)
cpu_delta() {
	local tmp a b
	tmp="$(mktemp -d)"
	tis_pairs "$1/cpu_freq.txt" | sort >"$tmp/a" 2>/dev/null
	tis_pairs "$2/cpu_freq.txt" | sort >"$tmp/b" 2>/dev/null
	a="$tmp/a" b="$tmp/b"
	awk -v A="$a" -v B="$b" '
		FILENAME==A {base[$1" "$2]=$3+0; next}
		FILENAME==B {k=$1" "$2; d=$3-base[k]; if(d>0) printf "%-9s %-10s +%.1fs\n",$1,$2,d/1e6}
	' "$a" "$b"
	rm -rf "$tmp"
}

wl_diff() { comm -13 <(sort -u "$1" 2>/dev/null) <(sort -u "$2" 2>/dev/null) | head -30; }

# parse durasi "1h2m3s45ms" -> detik
to_sec() {
	echo "$1" | awk '{
		s=0; n="";
		for(i=1;i<=length($0);i++){c=substr($0,i,1);
			if(c>="0"&&c<="9"){n=n c}
			else{if(n!=""){if(c=="h")s+=n*3600; else if(c=="m")s+=n*60; else if(c=="s")s+=n; n=""}}}
		if(n!="")s+=n;
		print s}'
}

# ranking partial wake lock dari dumpsys batterystats (full)
wl_rank() {
	awk '
		/^ *Uid [0-9u]/ {uid=$2}
		/Wake lock .*PARTIAL_WAKE_LOCK/ {
			name=""; for(i=1;i<=NF;i++){if($i=="'"'"'"||$i=="REALTIME:"||$i=="realtime"){break}; name=name" "$i}
			if(match($0,/REALTIME:[^ ]+ +?[^ ]+/)){}
			# ambil token durasi setelah REALTIME:
			dur=""
			for(i=1;i<=NF;i++){if($i=="REALTIME:"){dur=$(i+1)}}
			if(dur!=""){print dur"\t"uid"\t"$0}
		}' "$1" 2>/dev/null |
		awk -F'\t' '{s=to_sec($1); print s"\t"$2"\t"substr($3,1,140)}' \
			-f <(cat <<'AWK'
function to_sec(x,   i,c,n,s){
	s=0;n=""
	for(i=1;i<=length(x);i++){c=substr(x,i,1)
		if(c>="0"&&c<="9"){n=n c}
		else{if(n!=""){if(c=="h")s+=n*3600; else if(c=="m")s+=n*60; else if(c=="s")s+=n; n=""}}}
	if(n!="")s+=n
	return s
}
AWK
		) 2>/dev/null |
		sort -rn | head -20
}

compare() {
	local A B ea eb hrs capA capB dcap curA curB
	A="$(resolve_dir "$1")" || true
	B="$(resolve_dir "$2")" || true
	[ -n "$A" ] && [ -d "$A" ] || die "snapshot A tidak ditemukan: $1"
	[ -n "$B" ] && [ -d "$B" ] || die "snapshot B tidak ditemukan: $2"
	local RB="$B/report.md"
	{
		echo "# Drain report: $(basename "$A") -> $(basename "$B")"
		echo
	} >"$RB"

	ea="$(meta_get "$A" epoch)"; eb="$(meta_get "$B" epoch)"
	hrs=$(awk -v a="$ea" -v b="$eb" 'BEGIN{h=(b-a)/3600; printf "%.3f", h}')
	capA="$(meta_get "$A" battery_capacity)"; capB="$(meta_get "$B" battery_capacity)"
	dcap=$(awk -v a="$capA" -v b="$capB" 'BEGIN{printf "%.1f", a-b}')

	{
		echo "## Ringkas"
		echo
		echo "- durasi: ${hrs} jam (epoch $ea -> $eb)"
		echo "- SoC: ${capA}% -> ${capB}% (**-${dcap}%**)"
		awk -v d="$dcap" -v h="$hrs" 'BEGIN{if(h>0) printf "- laju: **%.1f %%/jam**\n", d/h}'
		echo "- kernel: $(meta_get "$A" uname)"
	} | tee -a "$RB"

	curA="$(grep -m1 '^current_now=' "$A/battery.txt" | cut -d= -f2)"
	curB="$(grep -m1 '^current_now=' "$B/battery.txt" | cut -d= -f2)"
	echo "- current_now: $curA -> $curB (tanda/satuan tergantung driver)" | tee -a "$RB"

	{
		echo
		echo "## CPU residency (time_in_state delta)"
		echo '```'
		cpu_delta "$A" "$B"
		echo '```'
	} | tee -a "$RB"

	{
		echo
		echo "## PM wake_lock: baris baru di B (aktivitas sejak A)"
		echo '```'
		wl_diff "$A/wakelock.txt" "$B/wakelock.txt"
		echo '```'
	} | tee -a "$RB"

	if [ -f "$A/batterystats-full.txt" ] && [ -f "$B/batterystats-full.txt" ]; then
		{
			echo
			echo "## Top PARTIAL_WAKE_LOCK (batterystats B, urut durasi)"
			echo '```'
			wl_rank "$B/batterystats-full.txt"
			echo '```'
		} | tee -a "$RB"
	fi

	{
		echo
		echo "## GPU freq (opp_freq)"
		echo '```'
		diff "$A/gpu_freq.txt" "$B/gpu_freq.txt" | head -30
		echo '```'
		echo
		echo "## /proc/interrupts delta"
		echo '```'
		diff <(head -80 "$A/procstat.txt") <(head -80 "$B/procstat.txt") | grep -E '^[<>]' | head -40
		echo '```'
	} | tee -a "$RB"

	echo
	echo "report lengkap: $RB"
}

watch_now() {
	local mins="${1:?usage: watch <menit>}" sa sb
	[ "$mins" -ge 1 ] 2>/dev/null || die "watch <menit> harus angka >= 1 (disarankan >= 15)"
	check_device
	echo "=== snapshot AWAL (pemakaian normal mulai sekarang; jangan cas, jangan ngegame) ==="
	sa="$(snapshot "watch$mins-start" | tail -1)"
	echo "=== tidur $mins menit ==="
	sleep $((mins * 60))
	echo "=== snapshot AKHIR ==="
	sb="$(snapshot "watch$mins-end" | tail -1)"
	echo "=== compare ==="
	compare "$(basename "$sa")" "$(basename "$sb")"
}

cmd="${1:-}"
case "$cmd" in
snapshot)
	[ "${2:-}" ] || die "usage: $0 snapshot <label>"
	snapshot "$2"
	;;
compare)
	[ "${3:-}" ] || die "usage: $0 compare <A> <B>"
	compare "$2" "$3"
	;;
watch)
	watch_now "${2:-}"
	;;
*)
	die "usage: $0 {snapshot <label> | compare <A> <B> | watch <menit>}"
	;;
esac
