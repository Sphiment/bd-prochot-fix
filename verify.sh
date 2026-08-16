#!/usr/bin/env bash

set -u

show_snapshot() {
  local mhz temp
  mhz=$(awk '/cpu MHz/{sum+=$4; count++} END {if(count) printf "%.0f",sum/count; else print "unknown"}' /proc/cpuinfo)
  temp=$(awk '{printf "%.1f\n",$1/1000}' /sys/class/thermal/thermal_zone*/temp 2>/dev/null | sort -nr | head -n1)
  printf 'average_MHz=%s hottest_thermal_zone_C=%s\n' "$mhz" "${temp:-unknown}"
}

if [[ ${1:-} != --load ]]; then
  show_snapshot
  printf 'Use %s --load for a ten-second CPU load test.\n' "$0"
  exit 0
fi

printf 'Running a ten-second CPU load. Stop with Ctrl+C if temperatures are unsafe.\n'
load_pids=()
cleanup() {
  for pid in "${load_pids[@]}"; do
    kill -TERM "$pid" 2>/dev/null || true
  done
}
trap cleanup EXIT INT TERM

for _ in $(seq 1 "$(nproc)"); do
  timeout 10s yes > /dev/null &
  load_pids+=("$!")
done

printf 'sec average_MHz hottest_zone_C\n'
for sec in $(seq 0 9); do
  printf '%02d ' "$sec"
  show_snapshot
  sleep 1
done

for pid in "${load_pids[@]}"; do
  wait "$pid" 2>/dev/null || true
done
