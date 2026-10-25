#!/bin/bash
# How much CPU the running Lookout uses, as a share of one core.
#   tools/measure_cpu.sh [seconds]     (default 120)
# Reads the process's total CPU time before and after; changes nothing.
set -euo pipefail
SECS=${1:-120}
pid=$(pgrep -f "Lookout.app/Contents/MacOS/Lookout" | head -1) || { echo "Lookout isn't running."; exit 1; }
cpu() { ps -o time= -p "$pid" | awk -F'[:.]' '{ if (NF == 4) print ($1 * 3600 + $2 * 60 + $3) * 100 + $4; else print ($1 * 60 + $2) * 100 + $3 }'; }
a=$(cpu); sleep "$SECS"; b=$(cpu)
awk -v d=$((b - a)) -v s="$SECS" 'BEGIN { printf "Lookout used %.2f%% of one core over %d seconds (%.2f s of CPU).\n", d / s, s, d / 100 }'
echo "Memory: $(ps -o rss= -p "$pid" | awk '{printf "%.0f MB", $1 / 1024}')"
