import AVFoundation

/// Captures microphone audio while active and returns it as a 16 kHz mono WAV.
///
/// A fresh ``AVAudioEngine`` is created for each recording session and fully torn down when
/// the session ends (``stop()``, ``cancel()``, or a configuration-change interruption); the
/// engine is never reused across sessions. This guarantees the engine always reads the
/// *current* hardware configuration, avoiding the stale cached-format mismatch
/// (`format.sampleRate == hwFormat.sampleRate`) that raises an uncatchable AVFAudio
/// `NSException` from `installTap`/`engine.start()` when another process reconfigures the
/// input device (sample-rate change, AirPods HFP switch, default-device switch) between
/// sessions.
///
/// The input hardware format (typically 44.1/48 kHz, possibly multi-channel) is converted to
/// 16 kHz mono Float32 via a per-session `AVAudioConverter` as buffers arrive on the audio
/// thread.
///
/// Threading: ``start()``, ``stop()``, and ``cancel()`` must be called from the main thread.
/// The tap callback runs on a separate audio thread and touches only the (locked) sample
/// buffer, the immutable output format, and its own captured converter. The session engine,
/// recording flag, generation counter, and observer token are all main-thread-confined; the
/// configuration-change observer is delivered on the main queue, so ``onSessionInterrupted``
/// is always invoked on the main queue.
public final class AudioRecorder {
    /// Invoked on the main queue when an in-progress session is torn down because another app
    /// reconfigured or took over the input device; the caller should treat the recording as
    /// cancelled (no audio is returned). `nil` by default.
    public var onSessionInterrupted: (() -> Void)?

    /// The capture engine for the current session, or `nil` when idle; recreated per session.
    private var engine: AVAudioEngine?
    /// The target output format (fixed 16 kHz mono Float32).
    private let outputFormat: AVAudioFormat
    /// Accumulated 16 kHz mono samples (guarded by `lock`).
    private var samples: [Float] = []
    /// Protects `samples` across the main and audio threads.
    private let lock = NSLock()
    /// Whether a capture session is currently active (main-thread state).
    private var isRecording = false
    /// Monotonic session counter; distinguishes the live session from a torn-down one so a
    /// stale engine's late configuration-change notification is ignored (main-thread state).
    private var sessionGeneration = 0
    /// The current session's configuration-change observer token, removed on teardown.
    private var configObserver: NSObjectProtocol?
    /// Target sample rate in Hz.
    private let targetSampleRate: Double = 16_000
    /// Reads the current microphone authorization status (injected so tests can fake it).
    private let authorizationProbe: () -> AVAuthorizationStatus

    /// Creates a recorder with a fixed 16 kHz mono target format.
    /// - Parameter authorizationProbe: Returns the current microphone authorization status;
    ///   defaults to the live `AVCaptureDevice` status. Injectable so tests can exercise
    ///   ``start()`` without a live microphone or a TCC prompt.
    public init(
        authorizationProbe: @escaping () -> AVAuthorizationStatus = {
            AVCaptureDevice.authorizationStatus(for: .audio)
        }
    ) {
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: targetSampleRate,
            channels: 1,
            interleaved: false
        ) else {
            fatalError("Failed to create 16 kHz mono audio format")
        }
        self.outputFormat = format
        self.authorizationProbe = authorizationProbe
    }

    /// Removes any lingering configuration-change observer on deallocation.
    deinit {
        if let configObserver {
            NotificationCenter.default.removeObserver(configObserver)
        }
    }

    /// Starts capturing microphone audio for a new session.
    ///
    /// Preflights the microphone grant *before* creating any engine: if access is not
    /// `.authorized` (including `.notDetermined`), throws immediately without touching an
    /// engine, so no implicit TCC prompt can ever fire from here (onboarding owns requesting).
    /// Otherwise creates a fresh engine, validates the live input format, installs the tap,
    /// registers the configuration-change observer, and starts the engine.
    /// - Throws: ``MurmurError/permissionDenied(_:)`` if microphone access is not authorized;
    ///   ``MurmurError/audioEngineFailed(_:)`` if the input format is unusable or the engine
    ///   fails to start.
    public func start() throws {
        guard !isRecording else { return }

        // Reason: check the grant before creating any engine so a missing permission never
        // triggers an implicit TCC prompt from AVFoundation here — onboarding owns requesting.
        guard authorizationProbe() == .authorized else {
            throw MurmurError.permissionDenied("Microphone")
        }

        lock.lock(); samples.removeAll(keepingCapacity: true); lock.unlock()

        // Reason: a fresh engine reads the CURRENT hardware config, eliminating the stale
        // cached-format mismatch that crashes installTap/start after another app reconfigured
        // the input device.
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        // Reason: guard both dimensions — a degenerate 0 Hz / 0-channel format (device mid
        // reconfiguration) is what feeds the invalid-format NSException downstream.
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw MurmurError.audioEngineFailed("no usable microphone input")
        }
        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            throw MurmurError.audioEngineFailed("could not create audio converter")
        }

        sessionGeneration += 1
        let generation = sessionGeneration
        // Reason: scope the observer to this engine AND this generation so a late notification
        // from a torn-down session (already enqueued on the main queue) is ignored.
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            self?.handleConfigurationChange(generation: generation)
        }

        // Reason: capture the converter in the tap closure so it is owned by this session and
        // released with the tap — no shared mutable converter to race the audio thread.
        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            self?.append(buffer, using: converter)
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            removeConfigObserver()
            throw MurmurError.audioEngineFailed(error.localizedDescription)
        }
        self.engine = engine
        isRecording = true
        Log.audio.info("recording started (input \(inputFormat.sampleRate, privacy: .public) Hz, \(inputFormat.channelCount, privacy: .public) ch)")
    }

    /// Stops capturing and returns the recorded audio as WAV data, tearing down the session.
    ///
    /// Safe to call repeatedly and in any order relative to ``cancel()``; a call when no
    /// session is active is a no-op returning empty `Data`.
    /// - Returns: WAV data, or empty `Data` if no session was active or the capture was too
    ///   short (< ~300 ms).
    public func stop() -> Data {
        guard isRecording else { return Data() }
        teardownSession()

        lock.lock(); let captured = samples; samples.removeAll(keepingCapacity: false); lock.unlock()
        let minSamples = Int(targetSampleRate * 0.3)
        guard captured.count >= minSamples else {
            Log.audio.info("capture too short (\(captured.count, privacy: .public) samples); discarding")
            return Data()
        }
        return WavEncoder.encode(samples: captured, sampleRate: Int(targetSampleRate))
    }

    /// Cancels the current session and discards any captured audio, tearing down the engine.
    ///
    /// Safe to call repeatedly and in any order relative to ``stop()``; a call when no session
    /// is active is a no-op.
    public func cancel() {
        guard isRecording else { return }
        teardownSession()
        lock.lock(); samples.removeAll(keepingCapacity: false); lock.unlock()
        Log.audio.info("recording cancelled")
    }

    /// Decides whether a configuration-change notification should interrupt recording.
    ///
    /// Pure so the policy is unit-testable without a live engine: interrupts only when the
    /// notification is for the current session generation *and* a recording is in progress.
    /// - Parameters:
    ///   - notificationGeneration: The session generation the notification was registered for.
    ///   - currentGeneration: The recorder's current session generation.
    ///   - isRecording: Whether a session is currently active.
    /// - Returns: `true` if the session should be torn down and cancelled.
    static func shouldInterrupt(notificationGeneration: Int, currentGeneration: Int, isRecording: Bool) -> Bool {
        notificationGeneration == currentGeneration && isRecording
    }

    /// Handles a configuration-change notification on the main queue.
    ///
    /// If it belongs to the current live session (see ``shouldInterrupt(notificationGeneration:currentGeneration:isRecording:)``),
    /// tears the session down, discards captured audio, and invokes ``onSessionInterrupted``;
    /// a notification from a stale (already torn-down) session is ignored. Runs on the main
    /// queue — the observer's delivery queue.
    /// - Parameter generation: The session generation captured when the observer was registered.
    private func handleConfigurationChange(generation: Int) {
        guard Self.shouldInterrupt(
            notificationGeneration: generation,
            currentGeneration: sessionGeneration,
            isRecording: isRecording
        ) else { return }
        Log.audio.info("input configuration changed mid-recording; cancelling session")
        teardownSession()
        lock.lock(); samples.removeAll(keepingCapacity: false); lock.unlock()
        onSessionInterrupted?()
    }

    /// Tears down the active session: removes the observer, removes the tap, and stops and
    /// drops the engine. Idempotent; leaves captured samples untouched so the caller decides
    /// whether to keep (``stop()``) or discard (``cancel()``) them. Main-thread only.
    private func teardownSession() {
        // Reason: drop the observer first so any notification posted during teardown (e.g. from
        // stopping the engine) can't re-enter this path.
        removeConfigObserver()
        if let engine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        engine = nil
        isRecording = false
    }

    /// Removes the configuration-change observer if registered. Idempotent. Main-thread only.
    private func removeConfigObserver() {
        if let configObserver {
            NotificationCenter.default.removeObserver(configObserver)
            self.configObserver = nil
        }
    }

    /// Converts and appends an incoming input buffer to the sample store (audio thread).
    /// - Parameters:
    ///   - buffer: The raw input buffer in the hardware format.
    ///   - converter: The session's input→output format converter.
    private func append(_ buffer: AVAudioPCMBuffer, using converter: AVAudioConverter) {
        let ratio = outputFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
        guard let out = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else { return }

        var fed = false
        var convError: NSError?
        let status = converter.convert(to: out, error: &convError) { _, inStatus in
            if fed {
                inStatus.pointee = .noDataNow
                return nil
            }
            fed = true
            inStatus.pointee = .haveData
            return buffer
        }
        if status == .error {
            Log.audio.error("conversion failed: \(convError?.localizedDescription ?? "unknown", privacy: .public)")
            return
        }
        guard let channel = out.floatChannelData, out.frameLength > 0 else { return }
        let frames = Int(out.frameLength)
        lock.lock()
        samples.append(contentsOf: UnsafeBufferPointer(start: channel[0], count: frames))
        lock.unlock()
    }
}
