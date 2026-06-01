# PLANNING — Murmur

> Source of truth for the full design is
> [`docs/superpowers/specs/2026-06-01-murmur-design.md`](docs/superpowers/specs/2026-06-01-murmur-design.md).
> This file is the quick-reference digest of architecture, goals, style, and constraints.

## Goal

Native Swift macOS menu-bar app for hold-to-talk dictation: hold the hotkey, speak,
release, and transcribed (optionally LLM-cleaned) text is inserted at the cursor in any
app. Local-first, with STT and LLM endpoints configurable so processing can move to a
remote server (NVIDIA DGX Spark) via a settings change.

## Architecture (Approach A)

- Swift menu-bar app orchestrates: hotkey → audio capture → transcription → optional
  cleanup → text insertion.
- STT and LLM are HTTP backends behind a configurable base URL.
  - STT: `TranscriptionBackend` protocol — `WhisperCppBackend` (local, bundled
    whisper.cpp server) and `OpenAIAudioBackend` (`/v1/audio/transcriptions`, remote).
  - LLM cleanup: OpenAI-compatible `/v1/chat/completions` (Ollama locally).
- `ServerSupervisor` manages the bundled whisper.cpp child process in local mode.

## Models

- STT: `whisper-large-v3-turbo` via whisper.cpp (Metal). Multilingual.
- LLM cleanup: `Qwen2.5-7B-Instruct` via Ollama (optional, configurable).
- Spark migration: `faster-whisper`/NeMo + a larger LLM at the same endpoints.

## Key decisions

- Interaction: dictate anywhere (cursor insertion via Accessibility).
- Capture: hold-to-talk (batch). Default hotkey: hold Right Option (⌥).
- Multilingual transcription. LLM cleanup optional, in scope for v1.
- Distribution: personal dev build (no notarization in v1).

## Constraints & conventions

- Modular Swift, every file < 1000 lines, grouped by responsibility.
- Tests for every unit: expected / edge / failure cases.
- macOS permissions required: Microphone, Accessibility, Input Monitoring.
- Never block the core dictation path on the optional LLM step (timeout → raw text).

## Milestones

1. M1 — core loop, local, raw text.
2. M2 — backend abstraction + Settings + supervisor + onboarding (Spark works from here).
3. M3 — optional LLM cleanup.
4. M4 — polish (HUD, status states, error toasts, in-app model download).
