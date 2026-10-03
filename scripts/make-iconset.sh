#!/bin/bash
# Builds Resources/AppIcon.iconset and AppIcon.icns from Resources/AppIcon.png (1024 × 1024).
set -euo pipefail
ROOT="$(dirname "$(dirname "$(realpath "$0")")")"
PNG="$ROOT/Resources/AppIcon.png"
SET="$ROOT/Resources/AppIcon.iconset"
mkdir -p "$SET"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$PNG" --out "$SET/icon_${size}x${size}.png" > /dev/null
    double=$((size * 2))
    sips -z "$double" "$double" "$PNG" --out "$SET/icon_${size}x${size}@2x.png" > /dev/null
done
iconutil -c icns "$SET" -o "$ROOT/Resources/AppIcon.icns"
printf 'Built: %s\n' "$ROOT/Resources/AppIcon.icns"
