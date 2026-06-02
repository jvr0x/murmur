#!/usr/bin/env bash
# Convenience: build the app bundle and launch it.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
"$ROOT/Scripts/make-app.sh"
# Quit any running instance first so we don't end up with two event taps active.
pkill -x Murmur 2>/dev/null || true
echo "==> Launching Murmur.app"
open "$ROOT/Murmur.app"
