#!/bin/bash
# Fast checks for the blocking scripts. Changes nothing on the Mac: the Wi-Fi
# helper runs in its test mode, and the list builder runs on sample text.
#   blocking/test.sh
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
fails=0
check() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; fails=$((fails + 1)); fi; }

# --- list builder rules ---
T=$(mktemp -d)
sed -n '/^SAFE_ROOTS=/,/^}/p' "$HERE/build-filters.sh" > "$T/f.sh"
printf '0.0.0.0 www.Bad.example # note\n*.sub.bad.example\nok.google.com\nfoo.blogspot.com\nblogspot.com\nx.blogspot.de\n! comment\nseen.example\n' > "$T/in.txt"
printf '||seen.example^\n' > "$T/prev.txt"
out=$(bash -c "source '$T/f.sh'; collapse '$T/prev.txt' < '$T/in.txt'")
check "lists: hosts lines, case and www are cleaned" '[[ $out == *"||bad.example^"* ]]'
check "lists: a name under a listed parent is dropped" '[[ $out != *"sub.bad.example"* ]]'
check "lists: safe sites are never blocked" '[[ $out != *google* ]]'
check "lists: shared platforms keep only the subdomain" '[[ $out == *"||foo.blogspot.com^"* && $out != *"||blogspot.com^"* ]]'
check "lists: a name in an earlier file isn't repeated" '[[ $out != *seen.example* ]]'

# --- timeouts ---
source "$HERE/common.sh"
start=$SECONDS; with_timeout 1 sleep 5; rc=$?
check "a hung command is killed by its timeout" '[[ $rc -ne 0 && $((SECONDS - start)) -le 3 ]]'

# --- Wi-Fi login helper ---
wifi() {
    WIFI_LOGIN_TEST=1 WIFI_LOGIN_DIR="$T/w" WIFI_LOGIN_LOG="$T/w.log" TEST_DEV=en0 TEST_SVC=Wi-Fi \
        TEST_ROUTER=10.0.0.1 TEST_NOW=${NOW:-1000000} "$HERE/wifi-login.sh" "$@"
}
mkdir -p "$T/w"; rm -f "$T/w/wifi-login.state"
out=$(TEST_FILTER_ON=no TEST_PROBE=login wifi)
check "wifi: does nothing while the filter is off" '[[ -z $out ]]'
out=$(TEST_FILTER_ON=yes TEST_ADGUARD_OK=no TEST_PROBE=login wifi)
check "wifi: a login page opens a window on the network's DNS" '[[ $out == *"WOULD: networksetup -setdnsservers Wi-Fi empty"* ]]'
out=$(TEST_PROBE=success TEST_HEALTHY=yes NOW=1000030 wifi)
check "wifi: logging in switches back to the filter" '[[ $out == *"setdnsservers Wi-Fi 127.0.0.1"* && $out == *"opened= "* ]]'
printf 'opened=1000000\nchecked=\nwindows=1000000\n' > "$T/w/wifi-login.state"
out=$(TEST_PROBE=login TEST_HEALTHY=no NOW=1000301 wifi)
check "wifi: after 5 minutes the filter comes back even without a login" '[[ $out == *"setdnsservers Wi-Fi 127.0.0.1"* && $out == *"opened= "* ]]'
printf 'opened=\nchecked=\nwindows="999000 999500 999900"\n' > "$T/w/wifi-login.state"
out=$(TEST_FILTER_ON=yes TEST_ADGUARD_OK=no TEST_PROBE=login wifi)
check "wifi: at most 3 windows an hour" '[[ $out != *"setdnsservers Wi-Fi empty"* ]]'
printf 'opened=1000000\nchecked=\nwindows=1000000\n' > "$T/w/wifi-login.state"
out=$(TEST_PROBE=success TEST_HEALTHY=no NOW=1000030 wifi)
check "wifi: logged in but filter dead: stays on the network's DNS" '[[ $(grep -c "setdnsservers Wi-Fi empty" <<< "$out") -eq 1 ]]'

rm -rf "$T"
echo; [[ $fails -eq 0 ]] && echo "All passed." || { echo "$fails failed."; exit 1; }
