# Shared by lookout-blocking.sh and wifi-login.sh. Every lookup here has a
# hard timeout, so a frozen DNS can never freeze a script.

# A site every filter blocks, used to prove filtering is on.
CANARY=pornhub.com

# Run a command, killing it after $1 seconds. Plain bash: no Python, no coreutils.
with_timeout() {
    local secs=$1; shift
    "$@" & local pid=$!
    ( sleep "$secs"; kill "$pid" 2>/dev/null ) & local watcher=$!
    wait "$pid" 2>/dev/null; local rc=$?
    kill "$watcher" 2>/dev/null; wait "$watcher" 2>/dev/null
    return $rc
}

# Ask the system resolver, as apps do. Prints the first address, none or TIMEOUT.
lookup() {
    local out
    out=$(with_timeout 3 dscacheutil -q host -a name "$1") || { echo TIMEOUT; return; }
    out=$(awk '/^ip_address/ {print $2; exit}' <<< "$out")
    echo "${out:-none}"
}

# Ask a DNS server directly: dig_short SERVER PORT NAME. Prints the last answer line.
dig_short() { dig +short +time=2 +tries=1 -p "$2" @"$1" "$3" A 2>/dev/null | tail -1; }

is_ip() { [[ $1 =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; }

# Through the system resolver: everyday sites work and the canary is blocked.
healthy() {
    local a b c
    a=$(lookup apple.com); b=$(lookup mail.google.com); c=$(lookup "$CANARY")
    echo "  apple.com=$a  mail.google.com=$b  $CANARY=$c"
    is_ip "$a" && [[ $a != 0.0.0.0 ]] && is_ip "$b" && [[ $b != 0.0.0.0 ]] && [[ $c == 0.0.0.0 ]]
}

flush_dns() { dscacheutil -flushcache; killall -HUP mDNSResponder 2>/dev/null; return 0; }

# Network services that carry real traffic: Wi-Fi and wired, not VPNs or bridges.
services() {
    networksetup -listallnetworkservices | tail -n +2 | grep -v '^\*' |
        grep -v -i -E 'tailscale|vpn|bridge|iphone|thunderbolt bridge'
}

# Show a notification to whoever is at the screen (works from a root daemon).
notify_user() {
    local uid user
    uid=$(stat -f %u /dev/console); user=$(stat -f %Su /dev/console)
    [[ $uid -ne 0 ]] || return 0
    launchctl asuser "$uid" sudo -u "$user" osascript -e "display notification \"$1\" with title \"Lookout\"" 2>/dev/null
    [[ ${2:-} == open ]] && launchctl asuser "$uid" sudo -u "$user" open http://captive.apple.com 2>/dev/null
    return 0
}
