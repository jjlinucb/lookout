#!/bin/bash
# Build Lookout into mac/dist/Lookout.app.
#
#   mac/build_app.sh            build
#   mac/build_app.sh --test     run the tests first
#   mac/build_app.sh --install  also copy it to /Applications and open it
#   mac/build_app.sh --zip      also make dist/Lookout.zip for a GitHub Release
#
# Needs only Apple's Command Line Tools (xcode-select --install), no Xcode and
# no Apple Developer account.
set -euo pipefail
cd "$(dirname "$0")"

INSTALL=0; ZIP=0; TEST=0
for arg in "$@"; do
    case "$arg" in
        --install) INSTALL=1 ;;
        --zip) ZIP=1 ;;
        --test) TEST=1 ;;
        *) echo "unknown option: $arg" >&2; exit 2 ;;
    esac
done

# Without Xcode.app, Command Line Tools 27 needs a macOS 26 SDK and the legacy build system.
BUILD_FLAGS=()
XCODE_DEV=/Applications/Xcode.app/Contents/Developer
if [ -d "$XCODE_DEV" ] && DEVELOPER_DIR="$XCODE_DEV" xcrun swift --version >/dev/null 2>&1; then
    export DEVELOPER_DIR="$XCODE_DEV"
else
    for candidate in MacOSX26.5.sdk MacOSX26.sdk; do
        SDK_PATH="/Library/Developer/CommandLineTools/SDKs/$candidate"
        if [ -d "$SDK_PATH" ]; then
            BUILD_FLAGS=(--build-system native -Xswiftc -sdk -Xswiftc "$SDK_PATH")
            break
        fi
    done
fi

if [ "$TEST" = 1 ]; then
    # The Command Line Tools keep Swift Testing outside the default search path.
    FW=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
    TEST_FLAGS=()
    [ -d "$FW" ] && TEST_FLAGS=(-Xswiftc -F -Xswiftc "$FW" -Xlinker -F -Xlinker "$FW" -Xlinker -rpath -Xlinker "$FW")
    swift test ${BUILD_FLAGS[@]+"${BUILD_FLAGS[@]}"} ${TEST_FLAGS[@]+"${TEST_FLAGS[@]}"}
    ../blocking/test.sh
fi

swift build ${BUILD_FLAGS[@]+"${BUILD_FLAGS[@]}"} -c release
BIN=.build/release/Lookout
[ -x "$BIN" ] || { echo "build produced no binary at $BIN" >&2; exit 1; }

APP=dist/Lookout.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/blocking"
cp "$BIN" "$APP/Contents/MacOS/Lookout"
cp assets/Info.plist "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(date +%Y%m%d.%H%M)" "$APP/Contents/Info.plist"
"$BIN" --compile-model assets/NudeNet320n.mlpackage "$APP/Contents/Resources/NudeNet320n.mlmodelc"
cp ../blocking/lookout-blocking.sh ../blocking/common.sh ../blocking/wifi-login.sh ../blocking/build-filters.sh \
    ../blocking/AdGuardHome.template.yaml "$APP/Contents/Resources/blocking/"
cp ../LICENSE "$APP/Contents/Resources/LICENSE.txt"

ICONSET=.build/AppIcon.iconset
rm -rf "$ICONSET" && mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
    sips -z $size $size assets/icon-1024.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    sips -z $((size * 2)) $((size * 2)) assets/icon-1024.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

# Screen Recording permission is tied to the app's signature. A lasting
# self-signed identity keeps the grant across rebuilds: one named "Lookout" in
# the keychain, or another set in LOOKOUT_SIGN_IDENTITY (see README). Without
# one, the app is signed ad hoc and macOS may ask again after each build.
IDENTITY="${LOOKOUT_SIGN_IDENTITY:-Lookout}"
if [ "$IDENTITY" != "-" ] && ! security find-identity -v -p codesigning 2>/dev/null | grep -q "\"$IDENTITY\""; then
    [ -n "${LOOKOUT_SIGN_IDENTITY:-}" ] && echo "No signing identity named \"$IDENTITY\"; signing ad hoc." >&2
    IDENTITY="-"
fi
codesign --force --deep --sign "$IDENTITY" --identifier io.github.jjlinucb.lookout "$APP"
echo "Built $APP (signed: $IDENTITY)"

if [ "$ZIP" = 1 ]; then
    rm -f dist/Lookout.zip
    ditto -c -k --keepParent "$APP" dist/Lookout.zip
    echo "Zipped dist/Lookout.zip"
fi

if [ "$INSTALL" = 1 ]; then
    DEST=/Applications/Lookout.app
    osascript -e 'quit app id "io.github.jjlinucb.lookout"' 2>/dev/null || true
    sleep 1
    rm -rf "$DEST"
    cp -R "$APP" "$DEST"
    open "$DEST"
    echo "Installed and opened $DEST"
fi
