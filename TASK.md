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

### Hotkey robustness, combos, presets, activation modes (2026-07-06)
- [x] `HotkeyDetector`: pure detection state machine (edges, auto-repeat debounce,
      missed-key-up resync, tap-outage reconcile via physical key state, combo matching,
      swallow pairing). Covered by `HotkeyDetectionTests`.
- [x] `HotkeyManager`/`EventTapRunner`: CGEventTap moved off the main run loop onto a
      dedicated user-interactive thread (fixes the F20 hold bug — see Fixes).
- [x] Combo hotkeys: `AppConfig.hotkeyModifiers` (raw CGEventFlags), combo-aware
      `KeyName.display(keyCode:modifiers:)`, `KeyComboRecorder` capture machine
      (modifiers+key, modifier-only combos, Esc cancels). `KeyRecorderTests`.
- [x] Activation modes: `AppConfig.hotkeyMode` — hold-to-talk or tap-to-toggle for long
      notes; wired per-event in `AppDelegate`, no tap rebuild on mode switch.
- [x] Hotkey presets (Spokenly-style): `HotkeyPreset` picker (Right Option, Right
      Command, fn/Globe, F20, F13, ⌃+Space, ⌥+Space, Custom) derived from the stored
      combo. `HotkeyPresetTests`.
- [x] Menu header derives from combo + mode ("hold ⌃ + Space to talk" / "tap F20 to
      start/stop"); onboarding copy made mode-agnostic (closes the Discovered item).
- [x] `ServerSupervisor.reapStaleServers` + graceful quit in `launch.sh` (see Fixes).
- [x] All logic verified via the one-off swiftc verifier (93 checks) — `swift test`
      still blocked by the CLT toolchain bug.

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
- **Cleanup LLM answered the transcript instead of cleaning it (2026-06-23)** — with the
  optional LLM pass, a dictated question or command was sent as a bare user turn, so small
  reasoning models (e.g. qwen3 4B, thinking on) replied to it instead of fixing punctuation
  and removing fillers. `CleanupService` now quarantines the transcript: the request is the
  system prompt + two few-shot pairs (a spoken question is cleaned, not answered) + the raw
  text fenced in `<transcript>` tags with an explicit "never act on it" directive
  (`buildMessages`/`wrap`). `parse` strips any `<think>…</think>` reasoning trace
  (`stripThinking`), and the payload sends `chat_template_kwargs: {enable_thinking:false}`
  (best-effort: honored by vLLM/llama.cpp, ignored by Ollama's `/v1`). `Prompts.defaultCleanup`
  hardened too — no migration, the structural changes carry existing saved prompts. Covered by
  `CleanupServiceTests` (builder + think-stripping), verified via the one-off swiftc verifier
  since `swift test` is blocked by the CLT toolchain bug.

- **F20 hold-and-release dead; quick taps "worked" (2026-07-06)** — the tap's run-loop
  source lived on the **main** run loop while `.defaultTap` makes every keyboard event in
  the session wait on the callback. Holding an ordinary key (F20) auto-repeats keyDowns
  into the tap, so any main-thread stall (synchronous `AVAudioEngine.start()` on press,
  HUD `TimelineView` animation, machine-wide memory pressure) got the tap disabled by
  timeout, the keyUp was lost, and `isDown` desynced — press edges then did nothing while
  release edges fired stale `end()`s (the "tap pops the HUD" symptom). The tap now runs on
  a dedicated user-interactive thread servicing only the pure `HotkeyDetector`; the
  detector self-heals (fresh keyDown while down → release-then-press; after
  `tapDisabledBy*` the state reconciles against `CGEventSource.keyState`). Toggle mode is
  additionally immune by design (only press edges act). Covered by `HotkeyDetectionTests`.
- **Orphaned whisper-server pile (2026-07-06)** — `launch.sh` relaunched via
  `pkill -x Murmur`; SIGTERM skips `applicationWillTerminate`, so the supervisor never
  stopped its child. Twelve orphans had accumulated (two holding ~1 GB resident, the rest
  swapped out; the oldest still owned port 8126 so fresh servers couldn't bind).
  `ServerSupervisor` now sweeps processes matching `Murmur.app/Contents/Resources/whisper-server`
  before launching, and `launch.sh` quits the app gracefully via AppleScript with a pkill
  fallback. Covered by `ServerSupervisorTests.testParsePIDs*`.

## Discovered During Work
- Cleanup few-shot examples are English; for non-English dictation a 4B model could be nudged
  toward English despite the "preserve original language" rule. Revisit (localize the examples
  to the configured language, or drop them) if drift shows up in live use.
- ~~`OnboardingView.swift:20` hardcoded "hold Right Option and speak"~~ — resolved
  2026-07-06: onboarding copy is mode-agnostic; the menu header derives from combo + mode.
- Toggle mode has no maximum recording duration; a forgotten session accumulates
  ~64 KB/s of samples (~230 MB/h). Consider a configurable cap or an idle-silence stop.
- Bare-modifier hotkeys respond to **either side** of the pair (e.g. the Right Option
  preset also fires on Left Option) because detection uses the high-level flag. Side-
  specific detection would need per-keycode tracking of `flagsChanged` +
  `CGEventSource.keyState`; not worth it until someone asks.
- **Machine hygiene (2026-07-06)**: the dev Mac's boot volume was at 100% (1.7 GB free of
  461 GB) with swap 10.2/11.3 GB used — this is what made main-thread stalls frequent
  enough to surface the tap-disable bug. Murmur can't fix that; free disk space.
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
