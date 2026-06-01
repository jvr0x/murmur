# Murmur — Design Spec

- **Date:** 2026-06-01
- **Status:** Approved (brainstorming) → ready for implementation planning
- **Author:** Javier (with Claude)

## 1. Summary

Murmur is a native Swift macOS menu-bar app for **hold-to-talk dictation**. While a
global hotkey is held the app records the microphone; on release it transcribes the
utterance with a local speech-to-text (STT) engine and inserts the resulting text at
the cursor in whatever app is frontmost — the same interaction model as Wispr Flow.

Murmur is **local-first** but **endpoint-configurable**: both the STT engine and an
optional LLM cleanup pass are reached over HTTP behind a configurable base URL, so the
processing can be moved from this Mac to another machine (an NVIDIA DGX Spark) by
changing a setting rather than the code.

### Decisions locked during brainstorming

| Decision | Choice |
|---|---|
| Interaction model | Dictate anywhere — insert text at the cursor via Accessibility |
| Client tech | Native Swift (macOS menu-bar app) |
| Capture timing | Batch / hold-to-talk (record while held, transcribe on release) |
| Languages | Multilingual |
| LLM cleanup | In scope for v1, optional + configurable |
| Distribution | Personal dev build (no code-signing/notarization in v1) |
| Architecture | Approach A — Swift app + app-managed local HTTP sidecars |
| Default hotkey | Hold Right Option (⌥); changeable in Settings |
| App name | Murmur |

## 2. Goals & non-goals

### Goals
- Press-and-hold to dictate into any macOS app, text inserted at the cursor.
- Fully local default processing on an Apple Silicon Mac (M2 Pro, 32 GB).
- STT and LLM endpoints configurable so processing can target a remote server.
- Multilingual transcription.
- Optional LLM cleanup (de-filler, formatting, spoken commands like "new paragraph").
- Modular, tested Swift codebase (files < 1000 lines).

### Non-goals (v1)
- Code signing / notarization / distribution outside the developer's own Macs.
- Live streaming transcription (batch only).
- Windows / Linux clients.
- Custom vocabulary, speaker diarization, audio file import.
- Bundling/installing Ollama (the user installs it; Murmur detects it).

## 3. Recommended models

### Speech-to-text: `whisper-large-v3-turbo`
- 809M params, ~99 languages, transcription-optimized; ~8× faster than `large-v3`
  with nearly identical transcription accuracy. Good fit for hold-to-talk latency.
- Local runtime: **whisper.cpp** (Metal-accelerated). Model file
  `ggml-large-v3-turbo` (≈1.6 GB f16, or ≈0.55 GB quantized `q5_0`).
- On the DGX Spark later: `faster-whisper large-v3` (CUDA/CTranslate2) or NVIDIA NeMo
  Canary behind an OpenAI-compatible endpoint — same client, different URL.

### LLM cleanup: `Qwen2.5-7B-Instruct` via Ollama
- Strong multilingual instruction-following; fits comfortably in 32 GB.
- Ollama exposes an OpenAI-compatible API (`http://localhost:11434/v1`).
- Lower-latency alternatives: `Qwen2.5-3B` / `Llama-3.2-3B`. Spark: a larger model at
  the same endpoint.

## 4. Architecture (Approach A)

Swift app orchestrates everything and talks to two HTTP backends. In local mode the app
launches/supervises a bundled whisper.cpp server child process; the LLM backend is
Ollama (external). Either endpoint can be repointed at a remote server.

```
┌─────────────────────────────────────────────────────────────┐
│ Murmur.app (Swift, menu-bar, LSUIElement)                     │
│                                                               │
│  HotkeyManager ─► AudioRecorder ─► TranscriptionService       │
│                                        │                      │
│                                        ▼                      │
│                            TranscriptionBackend (protocol)    │
│                              ├─ WhisperCppBackend  ───────────┼──► local whisper.cpp server
│                              └─ OpenAIAudioBackend ───────────┼──► remote /v1/audio/transcriptions (Spark)
│                                        │                      │
│                                        ▼                      │
│                            CleanupService (optional) ─────────┼──► /v1/chat/completions (Ollama / remote)
│                                        │                      │
│                                        ▼                      │
│                            TextInserter ─► frontmost app       │
│                                                               │
│  ServerSupervisor   SettingsStore   UI (status/HUD/settings)  │
└─────────────────────────────────────────────────────────────┘
```

### Components
- **HotkeyManager** — global hold-to-talk using a `CGEventTap` on
  `flagsChanged`/`keyDown`/`keyUp`. Default: Right Option (keyCode 61) pressed = start,
  released = stop. Requires Input Monitoring (tap) + Accessibility (to post events).
- **AudioRecorder** — `AVAudioEngine` input tap; converts to 16 kHz mono Float32 via
  `AVAudioConverter`; accumulates while the key is held; finalizes to an in-memory
  16-bit PCM WAV on release.
- **TranscriptionService** — owns the capture→transcribe→cleanup→insert pipeline and the
  state machine; selects the active `TranscriptionBackend`.
- **`TranscriptionBackend`** (protocol, Strategy pattern):
  - `WhisperCppBackend` — multipart `POST /inference` (file=WAV) to the local
    whisper.cpp server; parses `{ "text": ... }`.
  - `OpenAIAudioBackend` — multipart `POST {baseURL}/v1/audio/transcriptions`
    (OpenAI-compatible) for remote/Spark or any compatible server.
- **CleanupService** (optional) — `POST {baseURL}/v1/chat/completions` with the
  transcript + an editable system prompt. Hard timeout; on timeout/error returns the raw
  transcript so the core path never blocks.
- **TextInserter** — writes text to `NSPasteboard`, synthesizes ⌘V via `CGEvent`, then
  restores the previous pasteboard contents (best-effort across all item types).
  Keystroke-synthesis fallback for apps where paste misbehaves.
- **ServerSupervisor** — launches the bundled whisper.cpp server (`Process`) on a
  localhost port in local mode, health-checks readiness (TCP connect to the port, then a
  probe request), restarts on crash, terminates on app quit. No-op when the STT backend
  is set to a remote endpoint.
- **SettingsStore** — `@AppStorage` for simple values + a JSON file at
  `~/Library/Application Support/Murmur/config.json` for advanced settings.
- **UI** — menu-bar `MenuBarExtra` with status states (idle/recording/transcribing/
  polishing/error), a minimal borderless recording HUD (`NSPanel`), a SwiftUI Settings
  window, and a first-run permissions onboarding flow.
- **Bundled whisper.cpp server** — Metal-built `whisper-server` binary + model file in
  the app bundle resources.
- **Ollama** — external, auto-detected at `localhost:11434`; optional.

## 5. Data flow (one dictation)

1. User holds Right Option → `HotkeyManager` emits `startCapture`.
2. `AudioRecorder` records 16 kHz mono PCM. HUD: "Listening…".
3. User releases → `stopCapture`; buffer finalized to WAV.
4. `TranscriptionService` → active `TranscriptionBackend` → raw text. HUD: "Transcribing…".
5. If cleanup enabled → `CleanupService` → polished text. HUD: "Polishing…".
   On timeout/error → fall back to raw text.
6. `TextInserter` pastes text at the cursor; previous clipboard restored.
7. HUD dismisses; menu-bar icon returns to idle.

State machine guards re-entry: `idle → recording → transcribing → (cleaning) → inserting → idle`.
A trigger received outside `idle` is ignored until the current cycle completes.

## 6. macOS permissions (TCC)

| Permission | Why |
|---|---|
| Microphone | `AVAudioEngine` capture |
| Accessibility | Post ⌘V / keystrokes into other apps (text insertion) |
| Input Monitoring | Global `CGEventTap` for the hold-to-talk hotkey |

First-run onboarding explains each permission and deep-links to the relevant System
Settings panes. The app degrades gracefully: missing Microphone aborts capture with a
prompt; missing Accessibility/Input Monitoring disables the hotkey/insertion with
guidance rather than crashing.

## 7. Configuration

Stored in `UserDefaults` (simple) and `config.json` (advanced). Surface:

- **STT:** backend `{Local whisper.cpp | OpenAI-compatible}`, base URL, model name,
  language (auto / forced code).
- **LLM cleanup:** enabled toggle, base URL (default `http://localhost:11434/v1`), model
  (default `qwen2.5:7b`), editable system prompt, timeout (default 8 s).
- **Hotkey:** key/modifier (default Right Option), mode = hold-to-talk.
- **Insertion:** method (paste / keystroke), restore-clipboard toggle.
- **Audio:** input device, optional silence trimming.

Pointing at the Spark = set the STT backend to "OpenAI-compatible" + its URL, and/or set
the LLM base URL to the remote host. No rebuild required.

## 8. Error handling & edge cases

- Microphone denied → prompt + abort cycle.
- Accessibility / Input Monitoring missing → feature disabled with guidance.
- STT server not ready / crashed → `ServerSupervisor` restart + one retry; surface error.
- Remote endpoint unreachable / timeout → error toast; optional fall back to local STT.
- LLM cleanup slow / unreachable → timeout → insert raw transcript.
- Empty or very short (<~300 ms) audio → no-op.
- Pasteboard restore → snapshot item types/data before paste, restore after a short delay.
- Concurrent triggers → ignored by the state machine until the cycle finishes.

## 9. Project structure

Modular Swift, every file < 1000 lines, grouped by responsibility.

```
murmur/
├─ PLANNING.md  TASK.md  README.md
├─ docs/superpowers/specs/2026-06-01-murmur-design.md
├─ Murmur.xcodeproj  (or Package.swift if SPM-app)
├─ Sources/Murmur/
│  ├─ App/            (MurmurApp.swift, AppDelegate, MenuBar)
│  ├─ Hotkey/         (HotkeyManager.swift, EventTap.swift)
│  ├─ Audio/          (AudioRecorder.swift, WavEncoder.swift, AudioConverter.swift)
│  ├─ Transcription/  (TranscriptionService, TranscriptionBackend, WhisperCppBackend, OpenAIAudioBackend)
│  ├─ Cleanup/        (CleanupService.swift, Prompts.swift)
│  ├─ Insertion/      (TextInserter.swift, PasteboardSnapshot.swift)
│  ├─ Server/         (ServerSupervisor.swift)
│  ├─ Settings/       (SettingsStore.swift, SettingsView.swift)
│  ├─ UI/             (StatusItem, RecordingHUD, OnboardingView)
│  └─ Core/           (StateMachine.swift, Logger.swift, MurmurError.swift)
├─ Resources/         (whisper-server binary + ggml-large-v3-turbo model)
├─ Scripts/           (build-whisper.sh, fetch-model.sh, run.sh)
└─ Tests/MurmurTests/
```

## 10. Testing

Per the repo conventions, each unit includes expected / edge / failure cases (XCTest or
Swift Testing).

- **Backends** (mock HTTP server): valid parse / malformed body / timeout.
- **CleanupService**: cleans text / falls back to raw on error / empty input.
- **WavEncoder**: header correctness / zero-length / wrong sample rate.
- **PasteboardSnapshot**: capture + restore round-trip / restore on failure path.
- **StateMachine**: legal transitions / illegal re-entry guarded / rapid toggle.
- **SettingsStore**: encode/decode round-trip / missing keys → defaults / corrupt JSON.

Real audio capture, Accessibility insertion, and the event tap are validated through
manual integration testing (TCC permission prompts cannot be unit-tested).

## 11. Phasing (milestones)

1. **M1 — Core loop, local, raw text.** Hardcoded config: hotkey → record → whisper.cpp
   → paste. Proves the end-to-end pipeline.
2. **M2 — Backend abstraction + Settings + supervisor + onboarding.** `TranscriptionBackend`
   protocol with both adapters, Settings window, `ServerSupervisor`, permissions flow.
   *Remote/Spark works from here — just set the endpoint.*
3. **M3 — Optional LLM cleanup.** Ollama pass, editable prompt, timeout/fallback.
4. **M4 — Polish.** Recording HUD, menu-bar status states, error toasts, in-app model
   download.

## 12. Risks & side effects

- Requires three TCC permissions; intrusive first-run experience (mitigated by onboarding).
- Pasteboard is briefly overwritten then restored; restoring all rich types is
  best-effort.
- ~0.55–1.6 GB model download on first run.
- A background child process runs while in local mode.
- Right Option is also a system modifier; holding it without typing is safe, but the tap
  must not swallow normal Option-key usage (tap observes, does not consume, modifier
  events).
