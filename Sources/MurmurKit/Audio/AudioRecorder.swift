import AVFoundation

/// Captures microphone audio while active and returns it as a 16 kHz mono WAV.
///
/// The input hardware format (typically 44.1/48 kHz, possibly multi-channel) is converted
/// to 16 kHz mono Float32 via `AVAudioConverter` as buffers arrive on the audio thread.
/// `start()`/`stop()` are expected to be called from the main thread; the captured sample
/// buffer is guarded by a lock because the tap callback runs on a separate audio thread.
public final class AudioRecorder {
    /// The capture engine.
    private let engine = AVAudioEngine()
    /// Converts the input format to the 16 kHz mono target format.
    private var converter: AVAudioConverter?
    /// The target output format.
    private let outputFormat: AVAudioFormat
    /// Accumulated 16 kHz mono samples (guarded by `lock`).
    private var samples: [Float] = []
    /// Protects `samples` across the main and audio threads.
    private let lock = NSLock()
    /// Whether a capture session is active.
    private var isRecording = false
    /// Target sample rate in Hz.
    private let targetSampleRate: Double = 16_000

    /// Creates a recorder with a fixed 16 kHz mono target format.
    public init() {
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: targetSampleRate,
            channels: 1,
            interleaved: false
        ) else {
            fatalError("Failed to create 16 kHz mono audio format")
        }
        self.outputFormat = format
    }

    /// Starts capturing microphone audio.
    /// - Throws: ``MurmurError/audioEngineFailed(_:)`` if the engine cannot start (often a
    ///   missing microphone permission).
    public func start() throws {
        guard !isRecording else { return }
        lock.lock(); samples.removeAll(keepingCapacity: true); lock.unlock()

        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0 else {
            throw MurmurError.audioEngineFailed("input format unavailable — check Microphone permission")
        }
        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            throw MurmurError.audioEngineFailed("could not create audio converter")
        }
        self.converter = converter

        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            self?.append(buffer)
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw MurmurError.audioEngineFailed(error.localizedDescription)
        }
        isRecording = true
        Log.audio.info("recording started (input \(inputFormat.sampleRate, privacy: .public) Hz)")
    }

    /// Stops capturing and returns the recorded audio as WAV data.
    /// - Returns: WAV data, or empty `Data` if the capture was too short (< ~300 ms).
    public func stop() -> Data {
        guard isRecording else { return Data() }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRecording = false

        lock.lock(); let captured = samples; lock.unlock()
        let minSamples = Int(targetSampleRate * 0.3)
        guard captured.count >= minSamples else {
            Log.audio.info("capture too short (\(captured.count, privacy: .public) samples); discarding")
            return Data()
        }
        return WavEncoder.encode(samples: captured, sampleRate: Int(targetSampleRate))
    }

    /// Converts and appends an incoming input buffer (audio thread).
    /// - Parameter buffer: The raw input buffer in the hardware format.
    private func append(_ buffer: AVAudioPCMBuffer) {
        guard let converter else { return }
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
