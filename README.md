# Murmur

Local-first, hold-to-talk voice dictation for macOS. Hold a hotkey, speak, release —
your speech is transcribed and inserted at the cursor in any app. Similar in spirit to
Wispr Flow, but open and self-hosted: the speech-to-text and optional LLM cleanup run
locally by default, and both endpoints are configurable so you can move processing to
another machine (e.g. an NVIDIA DGX Spark) by changing a URL.

## Status

Early development. See [`PLANNING.md`](PLANNING.md) and
[`docs/superpowers/specs/2026-06-01-murmur-design.md`](docs/superpowers/specs/2026-06-01-murmur-design.md).

## How it works

1. Hold the hotkey (default: **Right Option ⌥**) and speak.
2. Release — Murmur records the audio, sends it to the speech-to-text engine, and
   (optionally) runs an LLM cleanup pass.
3. The text is inserted at your cursor in the frontmost app.

## Models

- **Speech-to-text:** `whisper-large-v3-turbo` via [whisper.cpp](https://github.com/ggerganov/whisper.cpp)
  (Metal-accelerated, multilingual).
- **Optional LLM cleanup:** `Qwen2.5-7B-Instruct` via [Ollama](https://ollama.com)
  (OpenAI-compatible API).

## Requirements

- Apple Silicon Mac (developed on M2 Pro, 32 GB).
- macOS permissions: Microphone, Accessibility, Input Monitoring.
- [Ollama](https://ollama.com) installed if you want the LLM cleanup pass.

## Setup

```sh
# 1. Build the bundled whisper.cpp server and fetch the model
./Scripts/build-whisper.sh
./Scripts/fetch-model.sh

# 2. (optional) LLM cleanup
ollama pull qwen2.5:7b

# 3. Build & run Murmur
swift build
swift run Murmur
```

Grant the three permissions when prompted (or in System Settings → Privacy & Security),
then hold Right Option and talk.

## Configuration

Settings (menu-bar icon → Settings) let you change the hotkey, STT/LLM endpoints, models,
and the cleanup prompt. To use a remote server, set the STT backend to
"OpenAI-compatible" with the server URL and/or point the LLM base URL at the remote host.

## License

TBD.
