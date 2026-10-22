#!/usr/bin/env bash
# Cold and warm start of a PROFILE or RELEASE Atlas build on a connected
# Android device, measured by the system (am start -W, TotalTime in ms).
#
#   flutter build apk --profile && adb install -r build/app/outputs/flutter-apk/app-profile.apk
#   tool/perf/android_startup.sh [runs=10] [device-serial]
#
# Cold: the process is force-stopped before each launch.
# Warm: the activity is backgrounded (HOME) and brought back; the process
#       stays alive.
# Output: build/perf/android_startup.csv plus a median summary. Record the
# device model, Android version, RAM and storage alongside the numbers.
set -euo pipefail
RUNS="${1:-10}"
SERIAL="${2:-}"
PKG="com.neuradix.atlas"
ACT="$PKG/.MainActivity"
ADB=(adb)
[ -n "$SERIAL" ] && ADB=(adb -s "$SERIAL")

mkdir -p build/perf
OUT=build/perf/android_startup.csv
echo "kind,run,total_ms" > "$OUT"

model=$("${ADB[@]}" shell getprop ro.product.model | tr -d '\r')
release=$("${ADB[@]}" shell getprop ro.build.version.release | tr -d '\r')
echo "Device: $model, Android $release" | tee build/perf/android_startup_device.txt

total() { grep -E '^TotalTime' | awk '{print $2}' | tr -d '\r'; }

# One unmeasured launch so the first-install work (DB creation) is excluded.
"${ADB[@]}" shell am force-stop "$PKG"
"${ADB[@]}" shell am start -W -n "$ACT" > /dev/null
sleep 5

for i in $(seq 1 "$RUNS"); do
  "${ADB[@]}" shell am force-stop "$PKG"
  sleep 2
  t=$("${ADB[@]}" shell am start -W -n "$ACT" | total)
  echo "cold,$i,$t" >> "$OUT"
  sleep 3
done

for i in $(seq 1 "$RUNS"); do
  "${ADB[@]}" shell input keyevent KEYCODE_HOME
  sleep 2
  t=$("${ADB[@]}" shell am start -W -n "$ACT" | total)
  echo "warm,$i,$t" >> "$OUT"
  sleep 2
done

median() { grep "^$1," "$OUT" | cut -d, -f3 | sort -n | awk '{a[NR]=$1} END {print a[int((NR+1)/2)]}'; }
echo "cold median: $(median cold) ms, warm median: $(median warm) ms ($RUNS runs each)"
echo "Note: TotalTime ends at the first Android frame (Flutter's launch"
echo "screen). Time to a usable Atlas screen is boot_to_ready_ms from the"
echo "device benchmark."
