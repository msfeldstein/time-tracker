#!/bin/sh
# Regenerates TimeTracker.xcodeproj from project.yml without Homebrew.
# Downloads a pinned XcodeGen release into .build/xcodegen (git-ignored) the first time.
set -eu

XCODEGEN_VERSION="2.47.0"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TOOLS="$ROOT/.build/xcodegen-$XCODEGEN_VERSION"
BIN="$TOOLS/xcodegen/bin/xcodegen"

if [ ! -x "$BIN" ]; then
    echo "Downloading XcodeGen $XCODEGEN_VERSION..."
    mkdir -p "$TOOLS"
    curl -fsSL -o "$TOOLS/xcodegen.zip" \
        "https://github.com/yonaskolb/XcodeGen/releases/download/$XCODEGEN_VERSION/xcodegen.zip"
    unzip -q -o "$TOOLS/xcodegen.zip" -d "$TOOLS"
    rm "$TOOLS/xcodegen.zip"
fi

cd "$ROOT"
"$BIN" generate "$@"
python3 "$ROOT/scripts/check_xcodeproj.py" "$ROOT/TimeTracker.xcodeproj"
