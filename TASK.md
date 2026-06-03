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
- [x] App icon (2026-06-02): Solana-gradient soundwave→wave mark. `AppIcon.icns`
      (16→1024 incl. @2x) in `Resources/`, `CFBundleIconFile` in `Info.plist.template`,
      bundled by `make-app.sh`; 1024 master kept at `Resources/AppIcon.png`.
- [x] Menu-bar wave glyph (2026-06-02): monochrome template (`StatusWave.png`, traced
      from the app-icon wave, `isTemplate` so it adapts to light/dark) + per-state colored
      status dot (red/blue/purple/green), replacing the emoji glyphs. `DictationState.hudLabel`
      centralizes the status wording (tested in `DictationStateTests`).
- [x] Status HUD redesign (2026-06-02): SwiftUI-hosted panel (`HUDView.swift`) with the
      app logo + an animated Solana-gradient waveform per state — reactive bars while
      Listening, a flowing sine while Transcribing, a gently pulsing sine while Polishing,
      a flat line while Inserting — plus the status label. `RecordingHUD` now takes
      `DictationState` instead of a text string.

### Setup / verification (2026-06-01)
- [x] Brainstorm + design spec approved.
- [x] Compiles via `swiftc` (lib + executable); 19 core-logic checks pass.
- [x] `Murmur.app` bundles and launches into the NSApp run loop (no startup crash).
- [x] `build-whisper.sh` builds a working Metal whisper-server.
- [x] End-to-end STT round-trip: real `WhisperCppBackend` -> whisper.cpp server ->
      correct transcription of synthesized speech.
- [x] `ServerSupervisor` auto-launches the bundled whisper-server on app start.
- [x] `setup.sh` one-command local setup.
- [ ] Not testable headless (need interactive session + TCC + hardware): mic capture,
      text insertion, global hotkey, live Ollama cleanup.

## Fixes
- **Hotkey never fired (icon never changed)** — modifier detection relied on device-
  dependent flag bits (`0x40`) that `CGEvent.flags` doesn't reliably expose, so `onPress`
  never triggered. Now detects via the high-level `.maskAlternate` flag (reliable), which
  also makes **either** Option key work. Regression covered by `HotkeyDetectionTests`.
  Also: auto-request permissions + show onboarding on first launch; ad-hoc code-sign the
  bundle so TCC grants survive rebuilds; re-enable the tap if macOS disables it.
- **Menu header hardcoded to "Right Option" (2026-06-02)** — the menu-bar header always
  read "Murmur — hold Right Option to talk" regardless of the configured hotkey. It now
  derives from `KeyName.display(for:)` via `StatusItemController.menuHeaderTitle(for:)`
  (e.g. "hold Space to talk"), and refreshes on menu open (`NSMenuDelegate.menuNeedsUpdate`)
  so a live hotkey change is reflected. Regression covered by `MenuHeaderTests`.
- **Hotkey leaked into the focused app (2026-06-02)** — a non-modifier hotkey (e.g. F20)
  reached the frontmost app through the listen-only tap, so the key also triggered actions
  there (Claude Code walked back through prompt history; earlier, a Shift+\ macro typed `|`
  into focused fields and corrupted `sttBaseURL`). The tap is now active (`.defaultTap`) and
  swallows the hotkey's own `keyDown`/`keyUp` via `HotkeyManager.shouldSwallow`; modifier
  hotkeys still pass through (a modifier flag can't be discarded cleanly). The active tap
  relies on Accessibility (already requested for text insertion). Covered by
  `HotkeyDetectionTests`.
- **Granted permission did nothing until restart (2026-06-02)** — the CGEvent tap was created
  once at launch and only rebuilt on a hotkey-code change, never on a permission change; the
  onboarding window also only re-read state on appear / manual "Refresh". Now a
  `PermissionsModel` polls and refreshes on app reactivation, `AppDelegate` rebuilds the tap
  the moment Input Monitoring + Accessibility are granted (`PermissionSnapshot.warrantsHotkeyRebuild`),
  and `OnboardingView` observes it for live status. Logic covered by `PermissionMonitorTests`
  (run via a one-off verifier since `swift test` is blocked by the CLT toolchain bug).
  Secondary: ad-hoc re-signing on each rebuild can still stale a TCC grant — see Discovered.

## Discovered During Work
- `OnboardingView.swift:20` has the same hardcoded "hold Right Option and speak" string as
  the menu header bug above; out of scope for the reported fix. Decide whether to derive it
  from `KeyName.display(for: config.hotkeyKeyCode)` too.
- The Command Line Tools toolchain in the dev sandbox is broken two ways: a
  `PackageDescription` dylib/interface mismatch (breaks `swift build`) and a duplicate
  `SwiftBridging` modulemap (breaks all Foundation imports). `Scripts/build-swiftc.sh`
  auto-detects the modulemap bug and applies a VFS-overlay workaround (no system files
  touched). A healthy Xcode/toolchain builds normally via `swift build`.
- Entry point uses `MainActor.assumeIsolated` (requires macOS 14) because `main.swift`
  top-level code is nonisolated but `AppDelegate` is `@MainActor`.
- **Stable signing identity for TCC**: the app is ad-hoc signed and re-signed on every
  `make-app.sh` build, so macOS can stale a previously-granted permission (its cdhash no
  longer matches the System Settings entry), forcing a remove/re-add. A stable self-signed
  identity (consistent designated requirement) would keep grants across rebuilds. Out of
  scope for the live re-check fix; tracked here.
