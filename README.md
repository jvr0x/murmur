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

- Apple Silicon Mac, **macOS 14+** (developed targeting an M2 Pro, 32 GB).
- A Swift toolchain (full Xcode, or Command Line Tools — see build note below).
- macOS permissions: Microphone, Accessibility, Input Monitoring.
- [Ollama](https://ollama.com) installed if you want the LLM cleanup pass.

## Setup

```sh
# 1. One-time: build the whisper.cpp server + download the model
#    (installs cmake via Homebrew if missing; model is ~547 MB)
./Scripts/setup.sh

# 2. (optional) LLM cleanup backend
ollama pull qwen2.5:7b

# 3. Build the app bundle and launch
./Scripts/run.sh                # builds Murmur.app and opens it
```

The individual steps (`build-whisper.sh`, `fetch-model.sh`) can also be run directly;
`fetch-model.sh` accepts `MODEL_FILE`/`MODEL_URL` overrides to use a different model.

`Scripts/make-app.sh` produces a real `Murmur.app` with an `Info.plist` (so macOS will
grant the microphone permission — a bare `swift run` binary cannot request it). Grant the
three permissions when prompted (or in System Settings → Privacy & Security), then hold
**Right Option** and talk.

### Build note

The standard build is SwiftPM (`swift build`), used automatically by `make-app.sh`. If
your Command Line Tools install is affected by the known duplicate-`SwiftBridging`
modulemap bug (every Foundation import fails to compile), `Scripts/build-swiftc.sh`
builds without SwiftPM and auto-applies a VFS-overlay workaround — no system files are
modified. `make-app.sh` falls back to it automatically.

## Configuration

Settings (menu-bar icon → Settings) let you change the hotkey, STT/LLM endpoints, models,
and the cleanup prompt. To use a remote server, set the STT backend to
"OpenAI-compatible" with the server URL and/or point the LLM base URL at the remote host.

The LLM Cleanup section has a **Provider** picker that prefills the base URL for **Ollama**
(`http://localhost:11434/v1`) or **LM Studio** (`http://localhost:1234/v1`); choose
**Custom** to point anywhere else (e.g. a model server on your Spark). The URL stays the
source of truth, so editing it just flips the picker to the matching provider.

## License

TBD.
