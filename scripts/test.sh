#!/bin/bash
# Runs the unit tests. The Command Line Tools ship Swift Testing outside the default
# search paths (macro plugin, framework and its interop library), so point at them explicitly.
set -euo pipefail
ROOT="$(dirname "$(dirname "$(realpath "$0")")")"
TOOLS="$(dirname "$(dirname "$(dirname "$(xcrun --find swift)")")")"
PLUGINS="$TOOLS/usr/lib/swift/host/plugins/testing"
FRAMEWORKS="$TOOLS/Library/Developer/Frameworks"
LIBRARIES="$TOOLS/Library/Developer/usr/lib"
if [ -d "$PLUGINS" ] && [ -d "$FRAMEWORKS/Testing.framework" ]; then
    exec swift test --package-path "$ROOT" -Xswiftc -plugin-path -Xswiftc "$PLUGINS" \
        -Xswiftc -F -Xswiftc "$FRAMEWORKS" -Xlinker -F -Xlinker "$FRAMEWORKS" \
        -Xlinker -rpath -Xlinker "$FRAMEWORKS" -Xlinker -rpath -Xlinker "$LIBRARIES" "$@"
fi
exec swift test --package-path "$ROOT" "$@"
