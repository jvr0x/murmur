#!/usr/bin/env bash
# Builds Murmur and assembles a Murmur.app bundle with a proper Info.plist
# (LSUIElement + NSMicrophoneUsageDescription) so macOS TCC permissions work.
#
# Tries `swift build` first; if SwiftPM is unavailable/broken, falls back to the direct
# swiftc build (Scripts/build-swiftc.sh). If the bundled whisper-server binary and a
# ggml-*.bin model are present in Resources/, they are copied in so local transcription
# works out of the box.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

APP="$ROOT/Murmur.app"
STAGE="$ROOT/.build/app-bin"
mkdir -p "$STAGE"

echo "==> Building release binary"
BIN=""
if swift build -c release >/dev/null 2>&1; then
  CAND="$(swift build -c release --show-bin-path 2>/dev/null)/Murmur"
  [ -f "$CAND" ] && BIN="$CAND"
fi
if [ -z "$BIN" ]; then
  echo "   swift build unavailable/failed; falling back to direct swiftc build"
  "$ROOT/Scripts/build-swiftc.sh" "$STAGE/Murmur"
  BIN="$STAGE/Murmur"
fi
[ -f "$BIN" ] || { echo "ERROR: no built binary at $BIN" >&2; exit 1; }

echo "==> Assembling $APP"
# Rebuild the bundle in place (clearContents-style) without deleting the directory.
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Murmur"
chmod +x "$APP/Contents/MacOS/Murmur"
cp "$ROOT/Resources/Info.plist.template" "$APP/Contents/Info.plist"

if [ -f "$ROOT/Resources/whisper-server" ]; then
  cp "$ROOT/Resources/whisper-server" "$APP/Contents/Resources/"
  echo "    bundled whisper-server"
else
  echo "    (no whisper-server yet — run Scripts/build-whisper.sh for local mode)"
fi

if compgen -G "$ROOT/Resources/ggml-*.bin" >/dev/null; then
  cp "$ROOT"/Resources/ggml-*.bin "$APP/Contents/Resources/"
  echo "    bundled model(s): $(ls "$ROOT"/Resources/ggml-*.bin | xargs -n1 basename | tr '\n' ' ')"
else
  echo "    (no model yet — run Scripts/fetch-model.sh for local mode)"
fi

echo "==> Ad-hoc code-signing (helps macOS keep TCC permissions across rebuilds)"
if codesign --force --sign - "$APP" 2>/dev/null; then
  echo "    signed (ad-hoc)"
else
  echo "    codesign unavailable; continuing unsigned"
fi

echo "==> Built $APP"
