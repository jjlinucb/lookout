#!/bin/bash
# Fast checks for the watchdog's decisions. Changes nothing on the Mac.
#   watchdog/test.sh
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
T=$(mktemp -d); fails=0
check() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; fails=$((fails + 1)); fi; }
wd() { LOOKOUT_WATCHDOG_TEST=1 LOOKOUT_WATCHDOG_LOG="$T/w.log" "$HERE/lookout-watchdog.sh" run; }

out=$(TEST_UID=501 TEST_RUNNING=no TEST_APP=yes wd)
check "watchdog: relaunches Lookout when it isn't running" '[[ $out == "WOULD RELAUNCH"* ]] && grep -q relaunched "$T/w.log"'
out=$(TEST_UID=501 TEST_RUNNING=yes TEST_APP=yes wd)
check "watchdog: leaves a running Lookout alone" '[[ -z $out ]]'
out=$(TEST_UID=0 TEST_RUNNING=no TEST_APP=yes wd)
check "watchdog: does nothing at the login window" '[[ -z $out ]]'
: > "$T/w.log"
TEST_UID=501 TEST_RUNNING=no TEST_APP=no wd; TEST_UID=501 TEST_RUNNING=no TEST_APP=no wd
check "watchdog: a missing app is logged once, not every minute" '[[ $(grep -c missing "$T/w.log") -eq 1 ]]'

rm -rf "$T"
echo; [[ $fails -eq 0 ]] && echo "All passed." || { echo "$fails failed."; exit 1; }
