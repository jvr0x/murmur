#!/usr/bin/env bash
# Builds the whisper.cpp server (Metal-accelerated) and copies the binary into Resources/.
#
# Prefers cmake; falls back to make. Run once during setup (and again to update).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENDOR="$ROOT/vendor/whisper.cpp"
DEST="$ROOT/Resources/whisper-server"
REPO="https://github.com/ggerganov/whisper.cpp.git"

mkdir -p "$ROOT/vendor"

if [ ! -d "$VENDOR/.git" ]; then
  echo "==> Cloning whisper.cpp into vendor/"
  git clone --depth 1 "$REPO" "$VENDOR"
else
  echo "==> Updating whisper.cpp"
  git -C "$VENDOR" pull --ff-only || true
fi

cd "$VENDOR"

if command -v cmake >/dev/null 2>&1; then
  echo "==> Building with cmake (Metal enabled)"
  cmake -B build -DCMAKE_BUILD_TYPE=Release -DGGML_METAL=ON >/dev/null
  cmake --build build --config Release -j --target whisper-server
elif command -v make >/dev/null 2>&1; then
  echo "==> cmake not found; falling back to make"
  make -j whisper-server || make -j server
else
  echo "ERROR: neither cmake nor make found. Install cmake:  brew install cmake" >&2
  exit 1
fi

# Locate the built server binary (name/location varies across versions).
BIN="$(find "$VENDOR/build" "$VENDOR" -maxdepth 3 -type f \( -name 'whisper-server' -o -name 'server' \) 2>/dev/null | head -1 || true)"
if [ -z "$BIN" ]; then
  echo "ERROR: could not find the built whisper-server binary." >&2
  exit 1
fi

cp "$BIN" "$DEST"
chmod +x "$DEST"
echo "==> Installed whisper-server -> $DEST"
