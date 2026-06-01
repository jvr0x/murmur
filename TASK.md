# TASK — Murmur

## Active

### M1 — Core loop, local, raw text (2026-06-01)
- [ ] Project scaffold: Xcode/SPM menu-bar app target (`LSUIElement`), folder structure.
- [ ] `Scripts/build-whisper.sh` + `Scripts/fetch-model.sh` (whisper.cpp Metal build + turbo model).
- [ ] `AudioRecorder`: AVAudioEngine capture → 16 kHz mono PCM → WAV.
- [ ] `HotkeyManager`: CGEventTap hold-to-talk on Right Option.
- [ ] `WhisperCppBackend`: POST /inference to local server, parse text.
- [ ] `ServerSupervisor` (minimal): launch local whisper.cpp server.
- [ ] `TextInserter`: pasteboard + ⌘V + restore.
- [ ] Wire end-to-end with hardcoded config; manual smoke test.

### M2 — Backend abstraction + Settings + onboarding
- [ ] `TranscriptionBackend` protocol + `OpenAIAudioBackend`.
- [ ] `SettingsStore` (UserDefaults + config.json) and SwiftUI Settings window.
- [ ] `ServerSupervisor`: health-check, restart, quit handling, remote no-op.
- [ ] Permissions onboarding (Microphone, Accessibility, Input Monitoring).

### M3 — Optional LLM cleanup
- [ ] `CleanupService`: /v1/chat/completions, editable prompt, timeout → raw fallback.
- [ ] Settings: enable toggle, base URL, model, prompt.

### M4 — Polish
- [ ] Recording HUD (borderless NSPanel) + menu-bar status states.
- [ ] Error toasts.
- [ ] In-app model download.

## Discovered During Work
- (none yet)

## Done
- [x] Brainstorm + design spec approved (2026-06-01).
