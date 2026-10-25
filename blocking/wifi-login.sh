#!/bin/bash
# Lets hotel, airport and coffee-shop Wi-Fi login pages work with the filter on.
#
#   wifi-login.sh          one pass (launchd runs it every 10 s and on network changes)
#   wifi-login.sh probe    print success, login or offline for this Wi-Fi; changes nothing
#   wifi-login.sh status   print the helper's state; changes nothing
#
# A login page needs the network's own DNS, and AdGuard Home sends lookups to
# Cloudflare, which the network blocks until you log in. So when Apple's Wi-Fi
# check shows a login page, this switches Wi-Fi to the network's DNS for at
# most 5 minutes, then back to the filter as soon as you're logged in. Every
# window is logged, and there are at most 3 an hour.
#
# It only acts while the filter is on (Wi-Fi DNS is 127.0.0.1). After
# `lookout-blocking.sh off` it does nothing.

set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/common.sh"
DIR=${WIFI_LOGIN_DIR:-/usr/local/lookout}
STATE=$DIR/wifi-login.state
LOG=${WIFI_LOGIN_LOG:-/var/log/lookout-blocking.log}
WINDOW_SECONDS=300
MAX_WINDOWS_PER_HOUR=3
# Test mode: WIFI_LOGIN_TEST=1 prints the changes instead of making them, and
# TEST_PROBE / TEST_FILTER_ON / TEST_ROUTER / TEST_ADGUARD_OK / TEST_HEALTHY / TEST_NOW
# stand in for the network.
TEST=${WIFI_LOGIN_TEST:-}

log() { echo "$(date '+%F %T') wifi-login: $*" >> "$LOG"; }
change() { if [[ -n $TEST ]]; then echo "WOULD: $*"; else "$@"; fi; }
now() { echo "${TEST_NOW:-$(date +%s)}"; }

wifi_device() { networksetup -listallhardwareports | awk '/Hardware Port: Wi-Fi/{getline; print $2; exit}'; }
wifi_service() {
    networksetup -listnetworkserviceorder | grep -B1 "Device: $1)" | head -1 | sed -E 's/^\([0-9*]+\) //'
}

# Apple's Wi-Fi check, asked through the network's own DNS (never the filter).
probe() {
    [[ -n ${TEST_PROBE:-} ]] && { echo "$TEST_PROBE"; return; }
    local dns ip body
    dns=$(ipconfig getoption "$DEV" domain_name_server 2>/dev/null)
    [[ -n $dns ]] || { echo offline; return; }
    ip=$(dig +short +time=2 +tries=1 @"$dns" captive.apple.com A 2>/dev/null | grep -E '^[0-9.]+$' | head -1)
    [[ -n $ip ]] || { echo offline; return; }
    body=$(curl -s -m 5 --resolve "captive.apple.com:80:$ip" http://captive.apple.com/hotspot-detect.html) ||
        { echo offline; return; }
    [[ $body == *Success* ]] && echo success || echo login
}

filter_on() {
    [[ -n ${TEST_FILTER_ON:-} ]] && { [[ $TEST_FILTER_ON == yes ]]; return; }
    [[ "$(networksetup -getdnsservers "$SVC")" == 127.0.0.1 ]]
}

router() { [[ -n ${TEST_ROUTER:-} ]] && echo "$TEST_ROUTER" || ipconfig getoption "$DEV" router 2>/dev/null; }

# Can the filter answer right now? It can't when the network blocks Cloudflare.
adguard_ok() {
    [[ -n ${TEST_ADGUARD_OK:-} ]] && { [[ $TEST_ADGUARD_OK == yes ]]; return; }
    is_ip "$(dig_short 127.0.0.1 53 apple.com)"
}

filtered() {
    [[ -n ${TEST_HEALTHY:-} ]] && { [[ $TEST_HEALTHY == yes ]]; return; }
    healthy >/dev/null
}

flush() { if [[ -n $TEST ]]; then echo "WOULD: flush DNS"; else flush_dns; fi; }

notify() {
    [[ -n $TEST ]] && { echo "WOULD NOTIFY: $1"; return; }
    notify_user "$@"
}

# State: opened (epoch of the open window, or empty), checked (router last seen
# logged in), windows (epochs of recent windows).
opened=""; checked=""; windows=""
load() { [[ -f $STATE ]] && source "$STATE"; return 0; }
save() {
    [[ -n $TEST ]] && echo "STATE: opened=$opened checked=$checked windows=$windows"
    printf 'opened=%q\nchecked=%q\nwindows=%q\n' "$opened" "$checked" "$windows" > "$STATE"
}

open_window() {
    local t recent="" n=0
    t=$(now)
    for w in $windows; do (( t - w < 3600 )) && { recent+="$w "; n=$((n + 1)); }; done
    if (( n >= MAX_WINDOWS_PER_HOUR )); then
        log "login page on router $1, but $n windows this hour already; filter stays on"
        windows=$recent; save
        return
    fi
    change networksetup -setdnsservers "$SVC" empty
    flush
    opened=$t; windows="$recent$t"; save
    log "OPENED: login page on router $1; Wi-Fi on the network's DNS for up to $((WINDOW_SECONDS / 60)) min"
    notify "Log in to this Wi-Fi now. The website filter is paused up to 5 minutes." open
}

close_window() {
    change networksetup -setdnsservers "$SVC" 127.0.0.1
    flush
    [[ -z $TEST ]] && sleep 2
    if filtered; then
        log "CLOSED ($1): back on the filter"
        [[ $1 == "logged in" ]] && checked=$(router)
        opened=""; save
        notify "Website filter back on."
    elif [[ $1 == "logged in" ]]; then
        # Logged in, yet the filter isn't answering: don't cut the internet.
        # Stay on the network's DNS; the health check switches back later.
        change networksetup -setdnsservers "$SVC" empty
        flush
        log "filter isn't answering after login; left Wi-Fi on the network's DNS"
        opened=""; save
        notify "Website filter could not come back on yet."
    else
        # Time ran out and the network still wants a login: back on the filter
        # (no internet until login anyway); a later pass may open one more window.
        log "CLOSED ($1): 5 minutes up, still not logged in; filter back on"
        opened=""; save
    fi
}

DEV=${TEST_DEV:-$(wifi_device)}
[[ -n $DEV ]] || exit 0
SVC=${TEST_SVC:-$(wifi_service "$DEV")}
[[ -n $SVC ]] || exit 0
mkdir -p "$DIR"
load

case "${1:-run}" in
probe) probe; exit 0 ;;
status) echo "Wi-Fi: $SVC ($DEV)  router: $(router)  window open since: ${opened:-no}  last logged-in router: ${checked:-none}"; exit 0 ;;
esac

if [[ -n $opened ]]; then
    result=$(probe)
    if [[ $result == success ]]; then
        close_window "logged in"
    elif (( $(now) - opened >= WINDOW_SECONDS )); then
        close_window "timed out"
    fi
    exit 0
fi

filter_on || exit 0
rt=$(router)
[[ -n $rt ]] || exit 0
# Look only when the network changed, or when the filter can't answer (a
# login that expired on the same network).
[[ $rt != "$checked" ]] || ! adguard_ok || exit 0
case "$(probe)" in
success) checked=$rt; save ;;
login) open_window "$rt" ;;
esac
exit 0
