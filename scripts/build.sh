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
swift build --package-path "$ROOT" -c release
BIN="$(swift build --package-path "$ROOT" -c release --show-bin-path)"
APP="$ROOT/dist/Keylapse.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/Keylapse" "$APP/Contents/MacOS/Keylapse"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
cp "$ROOT/Resources/FlowerTemplate.png" "$ROOT/Resources/FlowerTemplate@2x.png" "$ROOT/Resources/FlowerGlyph.png" "$ROOT/Resources/FlowerGlyphSmall.png" "$APP/Contents/Resources/"
if [ "$IDENTITY" = "-" ]; then
    codesign --force --sign - "$APP"
elif [[ -z "${SIGNING_IDENTITY:-}" || "$IDENTITY" == "Keylapse Local Development" ]]; then
    codesign --force --sign "$IDENTITY" --timestamp=none "$APP"
else
    codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
fi
codesign --verify --deep --strict "$APP"
ditto -c -k --keepParent "$APP" "$ROOT/dist/Keylapse.zip"
if [ -n "${NOTARY_PROFILE:-}" ]; then
    xcrun notarytool submit "$ROOT/dist/Keylapse.zip" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$APP"
    ditto -c -k --keepParent "$APP" "$ROOT/dist/Keylapse.zip"
fi
printf 'Built: %s\n' "$APP"
