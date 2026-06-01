#!/usr/bin/env bash
# Builds Murmur without SwiftPM, invoking swiftc directly.
#
# Use this when `swift build` is unavailable or broken (e.g. a Command Line Tools install
# whose PackageDescription dylib/interface are mismatched). Produces a standalone binary;
# Scripts/make-app.sh wraps it into Murmur.app.
#
# It also auto-detects the known Command Line Tools "duplicate SwiftBridging modulemap"
# bug (a stale usr/include/swift/module.modulemap alongside bridging.modulemap, both
# defining module SwiftBridging) and works around it with a VFS overlay — touching no
# system files. On a healthy toolchain the workaround is skipped.
#
# Usage: ./Scripts/build-swiftc.sh [output-binary-path]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

SDK="$(xcrun --show-sdk-path)"
TARGET="arm64-apple-macosx14.0"
BUILD="$ROOT/.build/swiftc"
OUT="${1:-$BUILD/Murmur}"
mkdir -p "$BUILD" "$(dirname "$OUT")"

# --- Work around the duplicate-SwiftBridging-modulemap Command Line Tools bug ----------
VFS_FLAGS=()
SWIFT_BIN="$(xcrun -f swiftc)"
INC_DIR="$(cd "$(dirname "$SWIFT_BIN")/../include/swift" 2>/dev/null && pwd || true)"
if [ -n "${INC_DIR:-}" ] && [ -f "$INC_DIR/module.modulemap" ] && [ -f "$INC_DIR/bridging.modulemap" ] \
   && grep -q "module SwiftBridging" "$INC_DIR/module.modulemap" 2>/dev/null \
   && grep -q "module SwiftBridging" "$INC_DIR/bridging.modulemap" 2>/dev/null; then
  echo "==> Detected duplicate SwiftBridging modulemap (known CLT bug); applying VFS overlay"
  WORK="$BUILD/mm-fix"; mkdir -p "$WORK"; : > "$WORK/empty.modulemap"
  cat > "$WORK/overlay.yaml" <<EOF
{ "version": 0, "case-sensitive": false,
  "roots": [ { "type": "file", "name": "$INC_DIR/module.modulemap", "external-contents": "$WORK/empty.modulemap" } ] }
EOF
  OV="$WORK/overlay.yaml"
  VFS_FLAGS=(-vfsoverlay "$OV" -Xcc -ivfsoverlay -Xcc "$OV" -Xcc -Xclang -Xcc -ivfsoverlay -Xcc -Xclang -Xcc "$OV")
fi
# ---------------------------------------------------------------------------------------

echo "==> Compiling MurmurKit module"
# shellcheck disable=SC2046
swiftc -swift-version 5 -sdk "$SDK" -target "$TARGET" "${VFS_FLAGS[@]}" \
  -module-name MurmurKit \
  -emit-module -emit-module-path "$BUILD/MurmurKit.swiftmodule" \
  -emit-library -static -o "$BUILD/libMurmurKit.a" \
  $(find Sources/MurmurKit -name '*.swift')

echo "==> Linking Murmur executable"
swiftc -swift-version 5 -sdk "$SDK" -target "$TARGET" "${VFS_FLAGS[@]}" \
  -I "$BUILD" -L "$BUILD" -lMurmurKit \
  -o "$OUT" \
  Sources/Murmur/main.swift

echo "==> Built $OUT"
