#!/bin/bash
# Lookout's website blocking: AdGuard Home as this Mac's own DNS filter.
#
#   sudo ./lookout-blocking.sh install     install AdGuard Home, build the lists, switch the Mac to it
#   sudo ./lookout-blocking.sh off         back to the network's own DNS, at once (filter stays installed)
#   sudo ./lookout-blocking.sh on          switch to the filter again; rolls back by itself if lookups fail
#   sudo ./lookout-blocking.sh uninstall   switch off and remove everything
#   ./lookout-blocking.sh check            report only, changes nothing
#   ./lookout-blocking.sh install --test   try it without sudo: side port 5355, in your user folder,
#                                          DNS not changed. Stop it with: ./lookout-blocking.sh test-stop
#
# The Lookout app runs install, off, on and uninstall with one admin password
# prompt. Safety rules: it never replaces a DNS filter that's already running,
# every lookup check times out after 3 seconds, every switch rolls back by
# itself if lookups fail, and a health check every minute restarts AdGuard
# Home if it stops answering, or puts DNS back to the network's own servers so
# the internet keeps working.

set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/common.sh"

VERSION=v0.107.79
case "$(uname -m)" in
    arm64) ARCH=arm64; SHA256=916f50bcc16b452c63ab8289f523a3c637e84933460a0ae7525fec03e31de867 ;;
    *) ARCH=amd64; SHA256=a28e30605c306c9002a496e705cffbe8828ef300ba5e85121e9308e623335ffa ;;
esac

LABEL=io.github.jjlinucb.lookout
ROOT=/usr/local/lookout
DNS_PORT=53; HTTP_PORT=3010
TEST=""
[[ ${2:-} == --test ]] && TEST=1
if [[ -n $TEST || ${1:-} == test-stop ]]; then
    ROOT="$HOME/Library/Application Support/Lookout/blocking-test"
    DNS_PORT=5355; HTTP_PORT=3011
fi
AGH=$ROOT/adguardhome
WORK=$AGH/work
LISTS=$WORK/data/userfilters
BACKUP=$ROOT/dns-before.txt
STATE=$ROOT/health.state
LOG=${LOOKOUT_LOG:-/var/log/lookout-blocking.log}
[[ -n $TEST ]] && LOG="$ROOT/blocking.log"

say() { echo "$*"; mkdir -p "$(dirname "$LOG")" 2>/dev/null; echo "$(date '+%F %T') $*" >> "$LOG" 2>/dev/null; return 0; }
need_root() { [[ $EUID -eq 0 ]] || { echo "Run with sudo: sudo $0 $1"; exit 1; }; }
plist() { echo "/Library/LaunchDaemons/$LABEL.$1.plist"; }
answering() { local a; a=$(dig_short 127.0.0.1 "$DNS_PORT" apple.com); is_ip "$a" && [[ $a != 0.0.0.0 ]]; }
installed() { [[ -f $(plist adguardhome) ]]; }

# Is something other than Lookout already serving DNS on this Mac's port?
port_taken() {
    lsof -nP -iUDP:"$DNS_PORT" 2>/dev/null | grep -q -E " (\*|127\.0\.0\.1|\[::1\]|localhost):$DNS_PORT\$" && return 0
    lsof -nP -iTCP:"$DNS_PORT" -sTCP:LISTEN 2>/dev/null | grep -q LISTEN
}

filter_on() {
    local svc
    while IFS= read -r svc; do
        [[ "$(networksetup -getdnsservers "$svc")" == 127.0.0.1 ]] && return 0
    done < <(services)
    return 1
}

write_daemon() {  # name, then the plist's inner XML
    local f; f=$(plist "$1")
    cat > "$f" <<XML
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL.$1</string>
$2
</dict>
</plist>
XML
    chown root:wheel "$f"; chmod 644 "$f"
    launchctl bootout "system/$LABEL.$1" 2>/dev/null || true
    # Right after a bootout, macOS can refuse with "Input/output error" for a moment.
    for _ in 1 2 3 4 5; do launchctl bootstrap system "$f" 2>/dev/null && return 0; sleep 2; done
    say "could not start $LABEL.$1"; return 1
}

do_install() {
    [[ -n $TEST ]] || need_root install
    if [[ -z $TEST ]] && installed; then
        echo "Already installed. Updating the scripts and lists."
    elif port_taken || answering; then
        echo "Another DNS filter is already running on this Mac (127.0.0.1:$DNS_PORT)."
        echo "Lookout won't replace it. Nothing was changed."
        exit 1
    fi

    echo "1/5 Downloading AdGuard Home $VERSION and checking it..."
    mkdir -p "$AGH" "$LISTS"
    local tmp; tmp=$(mktemp -d)
    curl -fsSL -m 180 -o "$tmp/agh.zip" \
        "https://github.com/AdguardTeam/AdGuardHome/releases/download/$VERSION/AdGuardHome_darwin_$ARCH.zip" ||
        { echo "Download failed. Nothing was changed."; exit 1; }
    [[ "$(shasum -a 256 "$tmp/agh.zip" | awk '{print $1}')" == "$SHA256" ]] ||
        { echo "The download's checksum is wrong; stopping. Nothing was changed."; exit 1; }
    unzip -q -o "$tmp/agh.zip" -d "$tmp"
    install -m 755 "$tmp/AdGuardHome/AdGuardHome" "$AGH/AdGuardHome"
    rm -rf "$tmp"

    echo "2/5 Writing the settings..."
    # The daemons run the copies in $ROOT, owned by root.
    if [[ $HERE != "$ROOT" ]]; then
        install -m 755 "$HERE/lookout-blocking.sh" "$HERE/common.sh" "$HERE/wifi-login.sh" "$HERE/build-filters.sh" "$ROOT/"
        install -m 644 "$HERE/AdGuardHome.template.yaml" "$ROOT/"
    fi
    if [[ ! -f $WORK/AdGuardHome.yaml ]]; then
        local password hash
        password=$(openssl rand -hex 16)
        hash=$(htpasswd -nbBC 10 admin "$password" | cut -d: -f2)
        ( umask 077; printf '%s\n' "$password" > "$ROOT/admin-password.txt" )
        sed -e "s#__WORK__#$WORK#g" -e "s#__PASSWORD_HASH__#$hash#" -e "s#__DNS_PORT__#$DNS_PORT#" \
            -e "s#__HTTP_PORT__#$HTTP_PORT#" "$HERE/AdGuardHome.template.yaml" > "$WORK/AdGuardHome.yaml"
        chmod 600 "$WORK/AdGuardHome.yaml"
    fi

    echo "3/5 Downloading the public block lists (a minute or two)..."
    "$ROOT/build-filters.sh" "$LISTS"

    echo "4/5 Starting AdGuard Home..."
    if [[ -n $TEST ]]; then
        pkill -f "$WORK" 2>/dev/null
        nohup "$AGH/AdGuardHome" --work-dir "$WORK" --config "$WORK/AdGuardHome.yaml" --no-check-update \
            >> "$ROOT/adguardhome.log" 2>&1 &
    else
        chown -R root:wheel "$ROOT"; chmod 700 "$WORK"
        write_daemon adguardhome "  <key>ProgramArguments</key>
  <array><string>$AGH/AdGuardHome</string><string>--work-dir</string><string>$WORK</string>
    <string>--config</string><string>$WORK/AdGuardHome.yaml</string><string>--no-check-update</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>/var/log/lookout-adguardhome.log</string>
  <key>StandardErrorPath</key><string>/var/log/lookout-adguardhome.log</string>"
        # The lists again every night at 4:00; AdGuard re-reads them within a day.
        write_daemon lists "  <key>ProgramArguments</key><array><string>$ROOT/build-filters.sh</string><string>$LISTS</string></array>
  <key>StartCalendarInterval</key><dict><key>Hour</key><integer>4</integer><key>Minute</key><integer>0</integer></dict>
  <key>StandardOutPath</key><string>$LOG</string><key>StandardErrorPath</key><string>$LOG</string>"
        write_daemon wifi-login "  <key>ProgramArguments</key><array><string>$ROOT/wifi-login.sh</string></array>
  <key>StartInterval</key><integer>10</integer>
  <key>WatchPaths</key><array><string>/Library/Preferences/SystemConfiguration</string></array>
  <key>RunAtLoad</key><true/>
  <key>StandardErrorPath</key><string>$LOG</string>"
        write_daemon health "  <key>ProgramArguments</key><array><string>$ROOT/lookout-blocking.sh</string><string>health</string></array>
  <key>StartInterval</key><integer>60</integer>
  <key>StandardErrorPath</key><string>$LOG</string>"
    fi

    echo "   waiting for it to load the lists..."
    local ok=""
    for _ in $(seq 1 45); do answering && { ok=1; break; }; sleep 2; done
    [[ -n $ok ]] || { echo "AdGuard Home isn't answering on 127.0.0.1:$DNS_PORT. Your DNS was not changed."; exit 1; }
    echo "   apple.com -> $(dig_short 127.0.0.1 "$DNS_PORT" apple.com) (want a real address)"
    echo "   $CANARY -> $(dig_short 127.0.0.1 "$DNS_PORT" "$CANARY") (want 0.0.0.0)"

    if [[ -n $TEST ]]; then
        echo "5/5 Test mode: your Mac's DNS was not changed."
        echo "Try: dig -p $DNS_PORT @127.0.0.1 example.com    Stop: $0 test-stop"
        echo "Dashboard: http://127.0.0.1:$HTTP_PORT (admin / password in $ROOT/admin-password.txt)"
        return
    fi
    echo "5/5 Switching this Mac to it..."
    do_on || exit 1
    say "installed"
    echo
    echo "Done. Dashboard: http://127.0.0.1:$HTTP_PORT  (user admin; password: sudo cat $ROOT/admin-password.txt)"
}

do_on() {
    need_root on
    answering || { echo "AdGuard Home isn't answering. Nothing changed."; return 1; }
    filter_on || : > "$BACKUP"
    local svc cur
    while IFS= read -r svc; do
        cur=$(networksetup -getdnsservers "$svc" | grep -v "aren't any" | tr '\n' ' ')
        [[ $cur == "127.0.0.1 " ]] && continue
        echo "$svc|$cur" >> "$BACKUP"
        networksetup -setdnsservers "$svc" 127.0.0.1
        echo "  $svc -> 127.0.0.1 (was: ${cur:-network default})"
    done < <(services)
    rm -f "$STATE"
    flush_dns; sleep 3
    echo "Checking (3-second timeouts)..."
    if healthy; then
        say "on: this Mac's DNS goes through the filter"
        return 0
    fi
    say "on: lookups failed or weren't filtered; switched back"
    do_off quiet
    return 1
}

do_off() {
    need_root off
    local svc saved
    while IFS= read -r svc; do
        saved=""
        [[ -f $BACKUP ]] && saved=$(grep "^$svc|" "$BACKUP" | tail -1 | cut -d'|' -f2)
        # shellcheck disable=SC2086
        networksetup -setdnsservers "$svc" ${saved:-empty}
    done < <(services)
    flush_dns
    [[ ${1:-} == quiet ]] || say "off: DNS back to the network's own servers"
    return 0
}

# Run by launchd every minute.
do_health() {
    need_root health
    local fails=0 auto_off=""
    [[ -f $STATE ]] && source "$STATE"
    save() { printf 'fails=%q\nauto_off=%q\n' "$fails" "$auto_off" > "$STATE"; }
    if ! filter_on; then
        # Back on by itself once AdGuard answers again, but only if the health check turned it off.
        if [[ -n $auto_off ]] && answering; then
            say "health: AdGuard Home answers again; switching back on"
            do_on >/dev/null && notify_user "Website filter is back on."
        fi
        return 0
    fi
    if answering; then
        [[ $fails -eq 0 ]] || { fails=0; save; }
        return 0
    fi
    fails=$((fails + 1)); save
    [[ $fails -ge 2 ]] || return 0
    say "health: AdGuard Home isn't answering; restarting it"
    launchctl kickstart -k "system/$LABEL.adguardhome" 2>/dev/null
    for _ in $(seq 1 15); do answering && { say "health: restarted, answering again"; fails=0; save; return 0; }; sleep 2; done
    # A Wi-Fi login window is in charge of DNS right now; leave it alone.
    grep -q "^opened=[0-9]" "$ROOT/wifi-login.state" 2>/dev/null && return 0
    do_off quiet
    auto_off=1; fails=0; save
    say "health: still not answering; DNS put back to the network's own servers so the internet works"
    notify_user "Website filter stopped answering. Your internet uses the network's DNS until it recovers."
}

do_uninstall() {
    need_root uninstall
    filter_on && do_off
    local name
    for name in health wifi-login lists adguardhome; do
        launchctl bootout "system/$LABEL.$name" 2>/dev/null || true
        rm -f "$(plist "$name")"
    done
    rm -rf "$ROOT"
    say "uninstalled"
    echo "Removed. Your Mac uses the network's own DNS."
}

do_check() {
    echo "Installed: $(installed && echo yes || echo no)"
    echo "AdGuard Home on 127.0.0.1:$DNS_PORT: $(answering && echo answering || echo 'not answering')"
    echo "This Mac's DNS goes through it: $(filter_on && echo yes || echo no)"
    [[ -f $STATE ]] && grep -q "^auto_off=1" "$STATE" && echo "Health check: turned off automatically; it turns back on when AdGuard answers."
    echo "What the Mac actually gets:"; healthy && echo "  -> filtered." || echo "  -> not filtered."
}

case "${1:-}" in
install) do_install ;;
on) do_on ;;
off) do_off ;;
health) do_health ;;
uninstall) do_uninstall ;;
check) do_check ;;
test-stop) pkill -f "$WORK" 2>/dev/null; rm -rf "$ROOT"; echo "Test copy stopped and removed." ;;
*) sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 1 ;;
esac
