# TASK — Murmur

## Active

### M4 — Polish (remaining)
- [ ] In-app model download (currently via `Scripts/fetch-model.sh`).
- [ ] Richer error toasts (currently a transient menu-bar ⚠️ glyph).
- [ ] Optional silence trimming / VAD for lower latency.

## Done

### M1 — Core loop, local, raw text (2026-06-01)
- [x] Project scaffold: SPM menu-bar app (kit/exe split, `LSUIElement` via Info.plist).
- [x] `Scripts/build-whisper.sh` + `Scripts/fetch-model.sh`.
- [x] `AudioRecorder`: AVAudioEngine capture → 16 kHz mono → WAV.
- [x] `HotkeyManager`: CGEventTap hold-to-talk on Right Option (device-flag detection).
- [x] `WhisperCppBackend`: POST /inference, parse text.
- [x] `ServerSupervisor`: launch/restart local whisper.cpp server.
- [x] `TextInserter`: pasteboard + ⌘V + clipboard restore (keystroke fallback).
- [x] `DictationController` + `AppDelegate` wiring end-to-end.

### M2 — Backend abstraction + Settings + onboarding (2026-06-01)
- [x] `TranscriptionBackend` protocol + `OpenAIAudioBackend` (remote/Spark).
- [x] `SettingsStore` (UserDefaults + config.json) + SwiftUI Settings window.
- [x] `ServerSupervisor`: restart, quit handling, remote no-op.
- [x] Permissions onboarding (Microphone, Accessibility, Input Monitoring).

### M3 — Optional LLM cleanup (2026-06-01)
- [x] `CleanupService`: /v1/chat/completions, editable prompt, timeout → raw fallback.
- [x] Settings: enable toggle, base URL, model, prompt.

### M4 — Polish (partial, 2026-06-01)
- [x] Recording HUD (borderless NSPanel) + menu-bar status glyphs.

### Setup / verification
- [x] Brainstorm + design spec approved (2026-06-01).
- [x] Compiles via `swiftc` (lib + executable); 19 logic checks pass.

## Discovered During Work
- The Command Line Tools toolchain in the dev sandbox is broken two ways: a
  `PackageDescription` dylib/interface mismatch (breaks `swift build`) and a duplicate
  `SwiftBridging` modulemap (breaks all Foundation imports). `Scripts/build-swiftc.sh`
  auto-detects the modulemap bug and applies a VFS-overlay workaround (no system files
  touched). A healthy Xcode/toolchain builds normally via `swift build`.
- Entry point uses `MainActor.assumeIsolated` (requires macOS 14) because `main.swift`
  top-level code is nonisolated but `AppDelegate` is `@MainActor`.
