# Lookout

A free, open-source accountability app for your own Mac. Think of it as a
private Covenant Eyes: it checks what's on your screen and covers explicit
images, and it can also block adult websites. Everything runs on your Mac.
No screenshots are uploaded, there's no account, and nothing is sent to us
or anyone else.

**For adults, on their own computer.** Lookout is a tool you choose for
yourself. Don't install it on someone else's Mac, and don't use it to
monitor children.

## What it does

**Screen check.** About once a second, Lookout looks at the parts of your
screen that changed and runs a nudity detector on them
([NudeNet](https://github.com/notAI-tech/NudeNet), converted to run on the
Mac's Neural Engine). When it finds explicit nudity, it covers every display
with a black screen and closes the browser tab, or hides the app if it isn't
a browser. Revealing images (lingerie, swimsuits) only count when they stay
on screen for two checks in a row, so one misread doesn't close your tab.

The cover lifts by itself after 3 seconds, and it has two buttons:

- **Continue**, or the white **X** in the corner, takes the cover away.
- **Wrong flag: pause 10 min** stops checking for ten minutes, in case it
  keeps flagging something harmless. Each pause is written to the log.

The eye in the menu bar shows that Lookout is on. Its menu has **Turn Off**
and **Turn On**, and each switch is logged too.

**Website blocking (optional).** Choose **Set Up Website Blocking…** in the
menu. Lookout installs [AdGuard Home](https://github.com/AdguardTeam/AdGuardHome),
a free DNS filter, on your Mac, loads about a million adult sites from public
block lists, and points your Mac's DNS at it. Behind it sits
[Cloudflare for Families](https://one.one.one.one/family/), which blocks
malware and adult content too. Setup asks for your password once.

## Privacy

- Screens are checked in memory and thrown away. Lookout never saves or
  sends a screenshot.
- The log lives only on your Mac, in `~/Library/Application Support/Lookout/`:
  `events.jsonl` (what was flagged, when, in which app, and what happened) and
  `flagged-domains.txt`. It records a site's name (`example.com`), never the
  full address, because addresses can carry account numbers or login tokens.
- Lookout reads the address of the browser tab in front only to skip pages
  you chose and to log the site's name.
- The website filter runs on your Mac. Your lookups go to Cloudflare for
  Families, the same as any DNS service. AdGuard Home keeps its own query log
  on your Mac, which you can see in its dashboard.

## Install

You need a Mac with Apple silicon (M1 or newer) and macOS 14 Sonoma or later.

1. Download `Lookout.zip` from the
   [Releases page](https://github.com/jjlinucb/lookout/releases), unzip it, and
   drag **Lookout** into your Applications folder.
2. **Open it the first time past Apple's warning.** Lookout isn't notarized
   by Apple, because that needs a paid developer account, so the first
   double-click says Apple can't check it. Click **Done** (not Move to Trash),
   then go to System Settings → Privacy & Security, scroll down, click
   **Open Anyway** next to the line about Lookout, and confirm with your
   password. On macOS 14 you can instead right-click Lookout → **Open** →
   **Open**. You only do this once.
3. **Allow screen recording.** macOS asks the first time. If you missed it:
   System Settings → Privacy & Security → Screen & System Audio Recording →
   turn on **Lookout**, then choose Quit & Reopen. Every few weeks macOS may
   ask again whether Lookout can keep recording. Choose to allow it.
4. The first time Lookout closes a tab, macOS asks whether Lookout can
   control Chrome or Safari. Click **Allow**. Firefox has no way to close a
   tab from outside, so on Firefox Lookout presses ⌘W instead, which needs
   System Settings → Privacy & Security → Accessibility → **Lookout** on.
5. Lookout starts by itself when you log in. You can see it under System
   Settings → General → Login Items.
6. **Optional: keep it running.** Menu → **Keep Lookout Running…** installs a
   small background helper (asks for your password once). If Lookout is
   quit or force-quit, the helper reopens it within a minute, and both
   Lookout's log and `/var/log/lookout-watchdog.log` record it.

To try the cover without anything on screen, run
`/Applications/Lookout.app/Contents/MacOS/Lookout --test-cover` from Terminal
(quit the running Lookout first).

## Settings

Lookout works without any settings. To change something, create
`~/Library/Application Support/Lookout/settings.json` with only the keys you
want to change, then quit and reopen Lookout. For example:

```json
{
  "pause_minutes": 5,
  "close_tab": false,
  "skip_apps": ["com.microsoft.Word", "com.apple.Photos"],
  "skip_pages": ["docs.google.com/spreadsheets"]
}
```

| Key | Default | What it does |
|---|---|---|
| `interval_seconds` | 1 | Time between checks |
| `exposed_threshold` | 0.40 | How sure the detector must be about explicit nudity |
| `revealing_threshold` | 0.55 | The same for revealing images |
| `revealing_frames_needed` | 2 | Checks in a row before a revealing image counts |
| `cover_seconds` | 3 | How long the cover stays up if you don't press a button |
| `close_tab` | true | Close the tab (or hide the app) after covering |
| `pause_minutes` | 10 | Length of a "Wrong flag" pause |
| `skip_apps` | Word | Apps that are never checked, by bundle ID |
| `skip_pages` | Google Sheets | Pages that are never checked, by the start of the address |
| `redirect_pages` | none | Pages to leave for another, like `{"linkedin.com/feed": "https://www.linkedin.com/messaging/"}`. Catches sites that change pages without a reload, which a browser's URL block misses. Chrome-like browsers and Safari; a "Wrong flag" pause doesn't stop it |

## Website blocking in detail

What **Set Up Website Blocking…** installs:

- AdGuard Home v0.107.79, downloaded from AdGuard's GitHub and checked
  against its published checksum, in `/usr/local/lookout/`. It answers DNS on
  127.0.0.1 only, so it filters this Mac and nothing else on your network.
- Public adult block lists: StevenBlack, HaGeZi NSFW, Sinfonietta,
  4skinSkywalker, OISD NSFW, blocklistproject and chadmayfield. They're
  rebuilt every night at 4:00. A HaGeZi gambling list is included but turned
  off; you can turn it on in the dashboard.
- SafeSearch on Google, Bing, DuckDuckGo and YouTube.
- **A Wi-Fi login helper.** Hotel, airport and café Wi-Fi login pages don't
  load through a DNS filter. When macOS detects one, Lookout puts Wi-Fi back
  on the network's own DNS for up to 5 minutes, opens the login page, and
  turns the filter back on once you're logged in. It does this at most 3
  times an hour, and logs each time.
- **A health check every minute.** If AdGuard Home stops answering, Lookout
  restarts it. If it still doesn't answer, Lookout switches your Mac back to
  the network's own DNS so your internet keeps working, tells you, and turns
  the filter back on once AdGuard Home answers again.

It won't replace another DNS filter that's already running on your Mac. It
also checks every switch: if lookups fail after pointing your Mac at the
filter, it switches back by itself.

**The dashboard** is at http://127.0.0.1:3010 (user `admin`). Get the
password with `sudo cat /usr/local/lookout/admin-password.txt`. If something
you need is blocked, find it under **Query log** and click **Unblock**. If you
have an accountability partner, let them change this password.

**Your browser can go around the filter** if it uses its own encrypted DNS
("Secure DNS" in Chrome, Edge and Brave; "DNS over HTTPS" in Firefox). Turn
that off in the browser's settings. Private and incognito windows aren't
blocked either.

From Terminal, `/usr/local/lookout/lookout-blocking.sh check` reports what's
working. Its log is `/var/log/lookout-blocking.log`.

## Turn it off or uninstall

- **Pause the screen check:** menu bar eye → **Turn Off**. It stays off until
  you choose **Turn On** or restart the Mac.
- **Turn off website blocking:** menu → **Turn Website Blocking Off…**.
- **If the internet stops working** and the menu isn't helping, run this in
  Terminal. It puts DNS straight back to your network's servers:
  ```bash
  sudo /usr/local/lookout/lookout-blocking.sh off
  ```
- **Uninstall everything:**
  1. Menu → **Remove Website Blocking…** (or
     `sudo /usr/local/lookout/lookout-blocking.sh uninstall`).
  2. If you set up **Keep Lookout Running**, remove that helper first, or it
     reopens Lookout:
     `sudo /usr/local/lookout-watchdog/lookout-watchdog.sh remove`
  3. Quit Lookout: `osascript -e 'quit app "Lookout"'` (there's no Quit item
     in the menu, on purpose), or use Activity Monitor.
  4. Remove it from System Settings → General → Login Items, and drag
     `/Applications/Lookout.app` to the Trash.
  5. To delete the log too: `rm -r ~/Library/Application\ Support/Lookout`.

## What it can't do (yet)

- **It's tamper-evident, not tamper-proof.** Anyone with your Mac's admin
  password can turn it off or remove it. Turning it off, pausing it and
  relaunches by the helper are all logged. Without
  device management, no Mac app can truly lock itself in.
- **There are no partner reports yet.** The log stays on your Mac. A daily
  encrypted summary for an accountability partner is the next big piece.
- **The detector makes mistakes.** It misses some things and flags some
  harmless ones, like skin-coloured art or swimsuit photos. That's what the
  pause button is for.
- **Only Apple silicon Macs, for now.** A Windows version is planned.

## How light it is

Lookout skips any part of the screen that hasn't changed, ignores tiny
changes like a blinking cursor or a clock, and checks only the changed part
up close. The detector runs on the Neural Engine. On a MacBook Pro (M1 Pro)
over two minutes of normal use, Lookout itself used **0.5% of one CPU core**
and 41 MB of memory. macOS's screen-capture service (`replayd`) used another
1.8% on its behalf, so the total is **about 2.3% of one core**. Measure it on
your own Mac with `tools/measure_cpu.sh`.

## Build from source

You need Apple's Command Line Tools (`xcode-select --install`). Xcode isn't
required.

```bash
git clone https://github.com/jjlinucb/lookout.git
cd lookout/mac
./build_app.sh --test      # run the tests, then build dist/Lookout.app
./build_app.sh --install   # build, copy to /Applications and open
```

Screen Recording permission is tied to the app's signature. With the default
ad-hoc signature, macOS may ask again after every rebuild. To keep the
permission across rebuilds, create a self-signed code-signing certificate
named **Lookout** in Keychain Access (Certificate Assistant → Create a
Certificate, type Code Signing), or set `LOOKOUT_SIGN_IDENTITY` to the name of
one you already have.

The pieces:

| Path | What it is |
|---|---|
| `mac/Sources/LookoutCore/` | The rules: what counts, what changed, the log. No UI, fully tested. |
| `mac/Sources/Lookout/` | The app: screen capture (ScreenCaptureKit), the Core ML detector, the cover and the menu. |
| `mac/assets/NudeNet320n.mlpackage` | NudeNet's 320n detector converted to Core ML by `tools/convert_model.py`. |
| `blocking/` | The website-blocking scripts the app runs. `blocking/test.sh` tests them without changing anything. |
| `watchdog/` | The helper that reopens Lookout if it's quit, and its tests. |
| `tools/measure_cpu.sh` | Measures the running app's CPU use. |

To try the website blocking without touching your Mac's DNS or using sudo:
`blocking/lookout-blocking.sh install --test` runs AdGuard Home on port 5355
in your user folder. Stop it with `blocking/lookout-blocking.sh test-stop`.

## License and credits

Lookout is free software under the [GNU AGPL-3.0](LICENSE).

- The detector is [NudeNet](https://github.com/notAI-tech/NudeNet) by
  notAI-tech (AGPL-3.0), converted to Core ML.
- Website blocking uses [AdGuard Home](https://github.com/AdguardTeam/AdGuardHome)
  (GPL-3.0), downloaded from AdGuard's own releases at setup, and
  [Cloudflare for Families](https://one.one.one.one/family/).
- Block lists by [StevenBlack](https://github.com/StevenBlack/hosts),
  [HaGeZi](https://github.com/hagezi/dns-blocklists),
  [Sinfonietta](https://github.com/Sinfonietta/hostfiles),
  [4skinSkywalker](https://github.com/4skinSkywalker/Anti-Porn-HOSTS-File),
  [OISD](https://oisd.nl), [The Block List Project](https://github.com/blocklistproject/Lists)
  and [chadmayfield](https://github.com/chadmayfield/my-pihole-blocklists).
