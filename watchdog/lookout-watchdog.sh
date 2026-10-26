#!/bin/bash
# Keeps Lookout running: a root LaunchDaemon that checks every minute and
# reopens Lookout for whoever is at the screen if it was quit or killed.
#
#   sudo ./lookout-watchdog.sh install   install and start the watchdog
#   sudo ./lookout-watchdog.sh remove    stop and remove it (do this before uninstalling Lookout)
#   ./lookout-watchdog.sh check          report only, changes nothing
#
# Every relaunch is written to /var/log/lookout-watchdog.log, and Lookout's
# own log records it as "relaunched by watchdog". Turning Lookout off from its
# menu doesn't quit it, so the watchdog leaves that alone; quitting it does.
# The watchdog lives in /usr/local/lookout-watchdog, owned by root, so
# removing it takes the admin password.

set -uo pipefail
LABEL=io.github.jjlinucb.lookout.watchdog
BUNDLE=io.github.jjlinucb.lookout
APP=/Applications/Lookout.app
DEST=/usr/local/lookout-watchdog
PLIST=/Library/LaunchDaemons/$LABEL.plist
LOG=${LOOKOUT_WATCHDOG_LOG:-/var/log/lookout-watchdog.log}
# Test mode: LOOKOUT_WATCHDOG_TEST=1 prints the relaunch instead of doing it,
# and TEST_UID / TEST_RUNNING / TEST_APP stand in for the Mac.
TEST=${LOOKOUT_WATCHDOG_TEST:-}

log() { echo "$(date '+%F %T') $*" >> "$LOG"; }
console_uid() { [[ -n ${TEST_UID:-} ]] && echo "$TEST_UID" || stat -f %u /dev/console; }
app_present() { [[ -n ${TEST_APP:-} ]] && { [[ $TEST_APP == yes ]]; return; }; [[ -x $APP/Contents/MacOS/Lookout ]]; }
running_for() {
    [[ -n ${TEST_RUNNING:-} ]] && { [[ $TEST_RUNNING == yes ]]; return; }
    pgrep -u "$1" -f "$APP/Contents/MacOS/Lookout" >/dev/null
}

# One pass, run by launchd every minute.
pass() {
    local uid user
    uid=$(console_uid)
    [[ $uid -ne 0 ]] || return 0          # nobody logged in at the screen
    running_for "$uid" && return 0
    if ! app_present; then
        # Log once, not every minute.
        grep -q "Lookout.app is missing" <(tail -1 "$LOG" 2>/dev/null) || log "Lookout.app is missing from /Applications; nothing to relaunch"
        return 0
    fi
    user=$(id -un "$uid" 2>/dev/null || echo "uid $uid")
    if [[ -n $TEST ]]; then
        echo "WOULD RELAUNCH for $user"
    else
        launchctl asuser "$uid" sudo -u "$user" /usr/bin/open -g -b "$BUNDLE" --args --relaunched
    fi
    log "Lookout was not running for $user; relaunched"
}

case "${1:-run}" in
run) pass ;;
install)
    [[ $EUID -eq 0 ]] || { echo "Run with sudo: sudo $0 install"; exit 1; }
    mkdir -p "$DEST"
    [[ "$(cd "$(dirname "$0")" && pwd)" == "$DEST" ]] || install -m 755 "$0" "$DEST/lookout-watchdog.sh"
    chown -R root:wheel "$DEST"; chmod 755 "$DEST"
    cat > "$PLIST" <<XML
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key><array><string>$DEST/lookout-watchdog.sh</string><string>run</string></array>
  <key>StartInterval</key><integer>60</integer>
  <key>RunAtLoad</key><true/>
  <key>StandardErrorPath</key><string>$LOG</string>
</dict>
</plist>
XML
    chown root:wheel "$PLIST"; chmod 644 "$PLIST"
    launchctl bootout "system/$LABEL" 2>/dev/null || true
    for _ in 1 2 3 4 5; do launchctl bootstrap system "$PLIST" 2>/dev/null && break; sleep 2; done
    launchctl print "system/$LABEL" >/dev/null 2>&1 || { echo "The watchdog didn't start."; exit 1; }
    log "watchdog installed"
    echo "Watchdog installed. If Lookout is quit, it's reopened within a minute. Log: $LOG"
    ;;
remove)
    [[ $EUID -eq 0 ]] || { echo "Run with sudo: sudo $0 remove"; exit 1; }
    launchctl bootout "system/$LABEL" 2>/dev/null || true
    rm -f "$PLIST"
    rm -rf "$DEST"
    log "watchdog removed"
    echo "Watchdog removed. Lookout can now be quit and stays quit."
    ;;
check)
    echo "Watchdog loaded: $(launchctl print "system/$LABEL" >/dev/null 2>&1 && echo yes || echo no)"
    uid=$(console_uid)
    echo "Lookout running for the user at the screen: $(running_for "$uid" && echo yes || echo no)"
    [[ -f $LOG ]] && { echo "Last log lines:"; tail -3 "$LOG"; }
    ;;
*) sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'; exit 1 ;;
esac
