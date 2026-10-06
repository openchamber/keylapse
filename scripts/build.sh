#!/bin/bash
set -euo pipefail
ROOT="$(dirname "$(dirname "$(realpath "$0")")")"
IDENTITY="${SIGNING_IDENTITY:-}"
if [ -z "$IDENTITY" ]; then
    IDENTITIES="$(security find-identity -v -p codesigning)"
    while IFS= read -r line; do
        if [[ "$line" == *'"Keylapse Local Development"'* && "$line" =~ ([0-9A-Fa-f]{40}) ]]; then
            if [ -n "$IDENTITY" ]; then
                printf 'More than one local signing identity. Set SIGNING_IDENTITY to a certificate hash.\n' >&2
                exit 1
            fi
            IDENTITY="${BASH_REMATCH[1]}"
        fi
    done <<< "$IDENTITIES"
    if [ -z "$IDENTITY" ]; then
        printf 'Run bash scripts/setup-local-signing.sh once, or set SIGNING_IDENTITY.\n' >&2
        printf 'For an ad-hoc test build only, explicitly set SIGNING_IDENTITY=-.\n' >&2
        exit 1
    fi
fi
# UNIVERSAL=1 (the release workflow) builds for Apple silicon and Intel together.
ARCHS=()
[ "${UNIVERSAL:-}" = "1" ] && ARCHS=(--arch arm64 --arch x86_64)
swift build --package-path "$ROOT" -c release ${ARCHS[@]+"${ARCHS[@]}"}
BIN="$(swift build --package-path "$ROOT" -c release ${ARCHS[@]+"${ARCHS[@]}"} --show-bin-path)"
APP="$ROOT/dist/Keylapse.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/Keylapse" "$APP/Contents/MacOS/Keylapse"
# Sparkle, for in-app updates, is a binary framework from the package artifacts; the binary
# looks for it in Contents/Frameworks (rpath set in Package.swift).
SPARKLE="$(find "$ROOT/.build/artifacts" -type d -name Sparkle.framework -path '*macos*' | head -1)"
[ -n "$SPARKLE" ] || { printf 'Sparkle.framework not found under .build/artifacts; run swift package resolve.\n' >&2; exit 1; }
rm -rf "$APP/Contents/Frameworks"
mkdir -p "$APP/Contents/Frameworks"
ditto "$SPARKLE" "$APP/Contents/Frameworks/Sparkle.framework"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
cp "$ROOT/Resources/FlowerTemplate.png" "$ROOT/Resources/FlowerTemplate@2x.png" "$ROOT/Resources/FlowerGlyph.png" "$ROOT/Resources/FlowerGlyphSmall.png" "$APP/Contents/Resources/"
# Sparkle's nested pieces are signed first, inside out, then the framework, then the app.
FRAMEWORK="$APP/Contents/Frameworks/Sparkle.framework"
NESTED=("$FRAMEWORK/Versions/B/XPCServices/Installer.xpc" "$FRAMEWORK/Versions/B/XPCServices/Downloader.xpc"
        "$FRAMEWORK/Versions/B/Autoupdate" "$FRAMEWORK/Versions/B/Updater.app" "$FRAMEWORK")
if [ "$IDENTITY" = "-" ]; then
    for piece in "${NESTED[@]}"; do codesign --force --sign - "$piece"; done
    codesign --force --sign - "$APP"
elif [[ -z "${SIGNING_IDENTITY:-}" || "$IDENTITY" == "Keylapse Local Development" ]]; then
    for piece in "${NESTED[@]}"; do codesign --force --sign "$IDENTITY" --timestamp=none "$piece"; done
    codesign --force --sign "$IDENTITY" --timestamp=none "$APP"
else
    for piece in "${NESTED[@]}"; do codesign --force --options runtime --timestamp --sign "$IDENTITY" "$piece"; done
    codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
fi
codesign --verify --deep --strict "$APP"
ditto -c -k --keepParent "$APP" "$ROOT/dist/Keylapse.zip"
# Notarise with a keychain profile (xcrun notarytool store-credentials) or, as the release
# workflow does, with an Apple ID, an app-specific password and the team id from the environment.
if [ -n "${NOTARY_PROFILE:-}" ]; then
    xcrun notarytool submit "$ROOT/dist/Keylapse.zip" --keychain-profile "$NOTARY_PROFILE" --wait
elif [ -n "${APPLE_ID:-}" ] && [ -n "${APPLE_PASSWORD:-}" ] && [ -n "${APPLE_TEAM_ID:-}" ]; then
    xcrun notarytool submit "$ROOT/dist/Keylapse.zip" --apple-id "$APPLE_ID" --password "$APPLE_PASSWORD" --team-id "$APPLE_TEAM_ID" --wait
else
    printf 'Built: %s\n' "$APP"
    exit 0
fi
xcrun stapler staple "$APP"
ditto -c -k --keepParent "$APP" "$ROOT/dist/Keylapse.zip"
printf 'Built: %s\n' "$APP"
