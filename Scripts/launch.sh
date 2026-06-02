#!/usr/bin/env bash
# Relaunch the already-built Murmur.app WITHOUT rebuilding.
#
# Rebuilding changes the app's code identity, which invalidates macOS TCC permission
# grants (Microphone / Accessibility / Input Monitoring). Use this to restart Murmur with
# the same identity so your grants keep working. Build first with run.sh / make-app.sh.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/Murmur.app"

if [ ! -d "$APP" ]; then
  echo "Murmur.app not found. Build it first:  ./Scripts/run.sh" >&2
  exit 1
fi

# Quit a running instance, then open the same bundle.
pkill -x Murmur 2>/dev/null || true
open "$APP"
echo "Launched $APP (no rebuild — TCC grants preserved)."
