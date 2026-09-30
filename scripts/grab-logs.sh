#!/usr/bin/env bash
# grab-logs.sh — tarik semua log error dari device selene ke log-dump/<label>/
#
# Usage:
#   scripts/grab-logs.sh                      # label = timestamp
#   scripts/grab-logs.sh <label>              # label manual (mis. after-flash-xyz)
#   ADB="adb -s 192.168.230.217:5555" scripts/grab-logs.sh <label>
#
# Isi capture:
#   env.txt        uname, versi ROM, uptime, battery, partisi (f2fs/ext4)
#   dmesg.txt      log kernel runtime
#   errors.txt     saringan panic/oops/trace/abort/fail dari dmesg
#   pstore/        crash/panic log sebelum reboot (ramoops — selamat walau reboot)
#   logcat.txt     logcat -b crash,main,system,events
#   battery.txt    dumpsys battery + batterystats + suspend_stats
#   wake.txt       wake_lock, wakeup_count, resume reasons, wakeup sources
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DUMP="$ROOT/log-dump"
ADB="${ADB:-adb}"
USE_ROOT=0
FAILED=()

die() { echo "ERROR: $*" >&2; exit 1; }

check_device() {
	local state
	state="$($ADB get-state 2>/dev/null || true)"
	[ "$state" = "device" ] ||
		die "no device (adb get-state: '${state:-none}'). Colok HP / adb connect dulu."
}

detect_root() {
	if $ADB shell "su -c id" 2>/dev/null | tr -d '\r' | grep -q "uid=0"; then
		USE_ROOT=1
	fi
}

# Jalankan perintah sh di device via stdin (tanpa masalah quoting).
sh_run() {
	if [ "$USE_ROOT" = 1 ]; then
		printf '%s\n' "$1" | $ADB shell "su -c sh" 2>/dev/null | tr -d '\r'
	else
		printf '%s\n' "$1" | $ADB shell "sh" 2>/dev/null | tr -d '\r'
	fi
}

# grab <outfile-relatif> <deskripsi> <shell-cmd>
grab() {
	local out="$OUT/$1" desc="$2" cmd="$3"
	if sh_run "$cmd" > "$out" 2>/dev/null && [ -s "$out" ]; then
		printf '  ok    %-40s (%s bytes)\n' "$desc" "$(wc -c < "$out")"
	else
		rm -f "$out"
		FAILED+=("$desc")
		printf '  FAIL  %s\n' "$desc"
	fi
}

main() {
	local label="${1:-$(date +%Y%m%d-%H%M%S)}"
	OUT="$DUMP/$label"
	check_device
	detect_root
	mkdir -p "$OUT/pstore"

	echo "=== grab-logs -> $OUT (root=$USE_ROOT) ==="

	grab "env.txt" "env/uname/battery/partisi" "echo '# uname'; uname -a; \
		echo; echo '# rom'; getprop ro.build.display.id; getprop ro.build.version.release; \
		echo; echo '# uptime'; cat /proc/uptime; \
		echo; echo '# battery'; dumpsys battery; \
		echo; echo '# partisi'; mount | grep -E ' /data | / ' ; \
		echo; echo '# zram/swapon'; cat /proc/swaps 2>/dev/null"

	grab "dmesg.txt" "dmesg (kernel runtime)" "dmesg -t 2>/dev/null || dmesg"

	grab "errors.txt" "saringan error dmesg" "dmesg 2>/dev/null | grep -iE \
'panic|oops|BUG:|Call trace|refusing to freeze|Failed to|fail:|abort|WARN|hung task|rcu_sched|suspend_stats' | tail -300"

	mkdir -p "$OUT/pstore"
	local pfiles pcount=0
	pfiles="$(sh_run 'ls /sys/fs/pstore/ 2>/dev/null')"
	for f in $pfiles; do
		if sh_run "cat /sys/fs/pstore/$f" > "$OUT/pstore/$f" 2>/dev/null && [ -s "$OUT/pstore/$f" ]; then
			pcount=$((pcount + 1))
			printf '  ok    pstore/%-34s (%s bytes)\n' "$f" "$(wc -c < "$OUT/pstore/$f")"
		else
			rm -f "$OUT/pstore/$f"
		fi
	done
	[ "$pcount" -eq 0 ] && rmdir "$OUT/pstore" 2>/dev/null

	grab "battery.txt" "battery/suspend_stats" "echo '# battery'; dumpsys battery; \
		echo; echo '# suspend_stats'; for f in /sys/power/suspend_stats/*; do echo \"\$f: \$(cat \$f)\"; done; \
		echo; echo '# batterystats'; dumpsys batterystats"

	grab "wake.txt" "wake locks/reasons/sources" "echo '# wake_lock'; cat /sys/power/wake_lock; \
		echo; echo '# wake_unlock'; cat /sys/power/wake_unlock; \
		echo; echo '# wakeup_count'; timeout 3 cat /sys/power/wakeup_count 2>/dev/null || echo '(blocked: active wakeup source)'; \
		echo; echo '# last_resume_reason'; cat /sys/kernel/wakeup_reasons/last_resume_reason 2>/dev/null; \
		echo; echo '# wakeup sources (active_count desc)'; \
		for d in /sys/class/wakeup/wakeup*; do \
			echo \"\$(cat \$d/active_count 2>/dev/null) \$(cat \$d/name 2>/dev/null)\"; \
		done | sort -rn | head -40"

	if $ADB logcat -b crash,main,system,events -d -v threadtime > "$OUT/logcat.txt" 2>/dev/null \
		&& [ -s "$OUT/logcat.txt" ]; then
		printf '  ok    %-40s (%s bytes)\n' "logcat crash,main,system,events" "$(wc -c < "$OUT/logcat.txt")"
	else
		if $ADB logcat -b crash -d -v threadtime > "$OUT/logcat.txt" 2>/dev/null \
			&& [ -s "$OUT/logcat.txt" ]; then
			printf '  ok    %-40s (%s bytes)\n' "logcat crash (fallback)" "$(wc -c < "$OUT/logcat.txt")"
		else
			rm -f "$OUT/logcat.txt"
			FAILED+=("logcat")
			printf '  FAIL  logcat\n'
		fi
	fi

	# MTK AEE (native exception db) kalau ada
	local aee
	aee="$(sh_run 'ls /data/vendor/aee/ /data/aee/ 2>/dev/null | grep -E "\.db|_exp|DB_"')"
	if [ -n "$aee" ]; then
		echo "  note  AEE db ditemukan (tarik manual butuh MtkLogger): $aee"
	fi

	echo
	echo "=== selesai: $OUT ==="
	ls -la "$OUT" | tail -n +2
	if [ "${#FAILED[@]}" -gt 0 ]; then
		echo "GAGAL: ${FAILED[*]}"
		exit 1
	fi
}

main "$@"
