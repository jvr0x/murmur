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

# Quit a running instance gracefully (SIGTERM would skip applicationWillTerminate and
# orphan the bundled whisper-server child; macOS may show a one-time Automation prompt).
osascript -e 'tell application "Murmur" to quit' >/dev/null 2>&1 || true
for _ in $(seq 1 10); do
  pgrep -x Murmur >/dev/null 2>&1 || break
  sleep 0.2
done
# Force-quit fallback; the app's supervisor reaps any orphaned server on next launch.
pkill -x Murmur 2>/dev/null || true
open "$APP"
echo "Launched $APP (no rebuild — TCC grants preserved)."
