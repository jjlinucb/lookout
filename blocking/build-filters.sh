#!/bin/bash
# Builds Lookout's AdGuard Home filter files from big public adult lists.
#
#   build-filters.sh OUT_DIR
#
# Writes adult-1.txt, adult-2.txt and adult-3.txt. Each name becomes an
# AdGuard rule (||example.com^), which also blocks every subdomain, so a name
# whose parent is already listed (here or in an earlier file) is dropped. If
# every download for a file fails, that file keeps its last version.
# Plain bash, curl and awk: a fresh Mac has no Python.

set -uo pipefail
OUT=${1:?usage: build-filters.sh OUT_DIR}
mkdir -p "$OUT"

STAGE_1="https://raw.githubusercontent.com/StevenBlack/hosts/master/alternates/porn-only/hosts
https://raw.githubusercontent.com/hagezi/dns-blocklists/main/wildcard/nsfw-onlydomains.txt
https://raw.githubusercontent.com/Sinfonietta/hostfiles/master/pornography-hosts
https://raw.githubusercontent.com/4skinSkywalker/Anti-Porn-HOSTS-File/master/HOSTS.txt"
STAGE_2="https://nsfw.oisd.nl/domainswild2"
STAGE_3="https://raw.githubusercontent.com/blocklistproject/Lists/master/porn.txt
https://raw.githubusercontent.com/chadmayfield/my-pihole-blocklists/master/lists/pi_blocklist_porn_all.list"

# Never block these or anything under them: public lists sometimes catch a
# shared CDN or a big service, and blocking it would break the Mac.
SAFE_ROOTS="google.com googleapis.com gstatic.com googleusercontent.com apple.com icloud.com apple-dns.net
microsoft.com live.com office.com office365.com windows.net windowsupdate.com github.com githubusercontent.com
cloudflare.com cloudflare-dns.com akamaized.net akamaihd.net akamai.net amazonaws.com amazon.com wikipedia.org
wikimedia.org whatsapp.net whatsapp.com zoom.us dropbox.com gmail.com outlook.com bing.com duckduckgo.com
paypal.com venmo.com chase.com bankofamerica.com wellsfargo.com notion.so slack.com linkedin.com adguard.com
adtidy.org"
# Shared platforms: block the listed subdomain, never the platform itself.
SHARED="blogspot.com tumblr.com wordpress.com github.io vercel.app pages.dev netlify.app wixsite.com
neocities.org my.id herokuapp.com weebly.com webflow.io"

# Reads raw lists on stdin and earlier rule files as arguments; prints new rules.
collapse() {
    awk -v safe="${SAFE_ROOTS//$'\n'/ }" -v shared="${SHARED//$'\n'/ }" '
    BEGIN {
        n = split(safe, a, /[ \n]+/); for (i = 1; i <= n; i++) if (a[i] != "") SAFE[a[i]] = 1
        n = split(shared, a, /[ \n]+/); for (i = 1; i <= n; i++) if (a[i] != "") SHR[a[i]] = 1
        # Earlier stages, as ||name^ rules.
        for (i = 1; i < ARGC; i++) {
            while ((getline line < ARGV[i]) > 0) if (line ~ /^\|\|/) { gsub(/^\|\||\^$/, "", line); COV[line] = 1 }
            ARGV[i] = ""
        }
        ARGV[ARGC++] = "-"
    }
    {
        line = tolower($0); sub(/#.*/, "", line); gsub(/^[ \t\r]+|[ \t\r]+$/, "", line)
        if (line == "" || line ~ /^!/) next
        k = split(line, f, /[ \t]+/)
        d = (k >= 2 && (f[1] == "0.0.0.0" || f[1] == "127.0.0.1" || f[1] == "::" || f[1] == "::1")) ? f[2] : f[1]
        sub(/^[*.]+/, "", d); sub(/\.+$/, "", d)
        if (d ~ /^www\./ && gsub(/\./, ".", d) >= 2) d = substr(d, 5)
        if (d == "localhost" || length(d) > 253) next
        if (d !~ /^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$/) next
        if (d ~ /\.blogspot\.[a-z.]+$/ && d !~ /\.blogspot\.com$/) next
        if (d in SHR) next
        rest = d
        while (1) { if (rest in SAFE) next; p = index(rest, "."); if (!p) break; rest = substr(rest, p + 1) }
        NAMES[d] = 1
    }
    END {
        for (d in NAMES) {
            if (d in COV) continue
            rest = d; p = index(rest, "."); rest = substr(rest, p + 1); covered = 0
            while (index(rest, ".")) {
                if ((rest in NAMES) || (rest in COV)) { covered = 1; break }
                rest = substr(rest, index(rest, ".") + 1)
            }
            if (!covered) print "||" d "^"
        }
    }' "$@" | LC_ALL=C sort
}

earlier=()
for stage in 1 2 3; do
    var="STAGE_$stage"; urls=${!var}
    raw=$(mktemp); got=0; total=0
    while IFS= read -r url; do
        total=$((total + 1))
        if curl -fsSL -m 180 -A lookout-build-filters/1.0 "$url" >> "$raw"; then
            echo >> "$raw"; got=$((got + 1))
        else
            echo "  adult-$stage: skipped $url"
        fi
    done <<< "$urls"
    file="$OUT/adult-$stage.txt"
    if [[ $got -eq 0 ]]; then
        echo "adult-$stage: nothing downloaded; kept the previous file"
        [[ -f $file ]] || echo "! adult-$stage: no list could be downloaded yet." > "$file"
    else
        tmp="$file.tmp"
        { echo "! adult-$stage: $got of $total public lists. Built $(date +%F) by Lookout's build-filters.sh."
          collapse ${earlier[@]+"${earlier[@]}"} < "$raw"; } > "$tmp"
        mv -f "$tmp" "$file"  # never leave AdGuard a half-written file
        echo "adult-$stage.txt: $(($(wc -l < "$file") - 1)) rules"
    fi
    rm -f "$raw"
    earlier+=("$file")
done
