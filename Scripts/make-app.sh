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

if [ -f "$ROOT/Resources/AppIcon.icns" ]; then
  cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/"
  echo "    bundled app icon"
fi

if [ -f "$ROOT/Resources/StatusWave.png" ]; then
  cp "$ROOT/Resources/StatusWave.png" "$APP/Contents/Resources/"
  echo "    bundled menu-bar wave glyph"
fi

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

echo "==> Code-signing (so macOS keeps TCC permissions across rebuilds)"
# Finder-info/quarantine xattrs make codesign fail with "resource fork ... detritus".
xattr -cr "$APP" 2>/dev/null || true

# Reason: TCC records the app's *designated requirement* (DR) when you grant a
# permission and re-checks it on every launch. A plain ad-hoc signature has an
# implicit DR of `cdhash H"..."`, which changes on every rebuild — so each new
# build looks like a different app and the grant goes stale. We pin a *stable*
# DR instead, so grants survive rebuilds. Two modes, auto-detected:
#   • A code-signing identity named "$IDENTITY" exists  -> sign with it; codesign
#     derives `identifier "..." and certificate leaf = H"..."`, which is stable
#     across rebuilds AND cryptographically anchored to that cert.
#   • No such identity -> ad-hoc, but with an explicit identifier-only DR.
#     Stable across rebuilds with zero setup. Tradeoff: an identifier-only DR is
#     satisfied by *any* local binary claiming this bundle identifier — there is
#     no cryptographic anchor. Acceptable for a personal dev build; run
#     Scripts/make-signing-cert.sh once for the cert-anchored variant above.
IDENTITY="${MURMUR_SIGN_IDENTITY:-Murmur Dev Signing}"

if security find-identity -v -p codesigning 2>/dev/null | grep -qF "\"$IDENTITY\""; then
  echo "    using code-signing identity: $IDENTITY"
  if SIGN_ERR="$(codesign --force --timestamp=none --sign "$IDENTITY" "$APP" 2>&1)"; then
    SIGNED=1
  fi
else
  BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist")"
  echo "    no '$IDENTITY' identity found; ad-hoc signing with a stable designated requirement"
  echo "    (run Scripts/make-signing-cert.sh once for a cryptographically anchored signature)"
  if SIGN_ERR="$(codesign --force --sign - --identifier "$BUNDLE_ID" \
      -r="designated => identifier \"$BUNDLE_ID\"" "$APP" 2>&1)"; then
    SIGNED=1
  fi
fi

if [ "${SIGNED:-0}" = 1 ]; then
  echo "    signed"
  if codesign --verify --strict "$APP" 2>/dev/null; then
    echo "    verify --strict OK"
  else
    echo "    WARNING: codesign --verify --strict failed" >&2
  fi
  echo "    designated requirement:"
  codesign -d -r- "$APP" 2>/dev/null | sed 's/^/      /'
else
  echo "    codesign failed; continuing with the linker's binary signature:" >&2
  echo "    $SIGN_ERR" >&2
fi

echo "==> Built $APP"
