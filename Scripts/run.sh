#!/usr/bin/env bash
# Convenience: build the app bundle and launch it.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
"$ROOT/Scripts/make-app.sh"
echo "==> Launching Murmur.app"
open "$ROOT/Murmur.app"
