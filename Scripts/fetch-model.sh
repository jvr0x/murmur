#!/usr/bin/env bash
# Downloads the whisper.cpp GGML model into Resources/.
#
# Defaults to the quantized large-v3-turbo model (~547 MB, multilingual). Override with:
#   MODEL_URL=... MODEL_FILE=... ./Scripts/fetch-model.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODEL_FILE="${MODEL_FILE:-ggml-large-v3-turbo-q5_0.bin}"
MODEL_URL="${MODEL_URL:-https://huggingface.co/ggerganov/whisper.cpp/resolve/main/${MODEL_FILE}}"
DEST="$ROOT/Resources/$MODEL_FILE"

if [ -f "$DEST" ]; then
  echo "==> Model already present: $DEST"
  exit 0
fi

echo "==> Downloading $MODEL_FILE"
echo "    from $MODEL_URL"
curl -L --fail --progress-bar -o "$DEST.partial" "$MODEL_URL"
mv "$DEST.partial" "$DEST"
echo "==> Installed model -> $DEST"
