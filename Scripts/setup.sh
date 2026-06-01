#!/usr/bin/env bash
# One-time setup for local mode: build the whisper.cpp server and download the model.
# Installs cmake via Homebrew if it is missing.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! command -v cmake >/dev/null 2>&1; then
  if command -v brew >/dev/null 2>&1; then
    echo "==> cmake not found; installing via Homebrew"
    brew install cmake
  else
    echo "ERROR: cmake is required to build whisper.cpp, and Homebrew was not found." >&2
    echo "       Install cmake (https://cmake.org/download/) and re-run." >&2
    exit 1
  fi
fi

"$ROOT/Scripts/build-whisper.sh"
"$ROOT/Scripts/fetch-model.sh"

echo
echo "Setup complete."
echo "  • Optional LLM cleanup:  install Ollama, then  ollama pull qwen2.5:7b"
echo "  • Launch Murmur:         ./Scripts/run.sh"
