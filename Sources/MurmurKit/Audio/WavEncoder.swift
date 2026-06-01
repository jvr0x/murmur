import Foundation

/// Encodes Float32 PCM samples into a canonical 16-bit mono WAV container.
public enum WavEncoder {
    /// Encodes mono Float32 samples (range -1...1) into 16-bit little-endian PCM WAV data.
    ///
    /// Out-of-range samples are clamped to [-1, 1]. A zero-length input still produces a
    /// valid 44-byte header with an empty data chunk.
    ///
    /// - Parameters:
    ///   - samples: Mono audio samples.
    ///   - sampleRate: Sample rate in Hz (e.g. 16000).
    /// - Returns: A complete WAV file as `Data`.
    public static func encode(samples: [Float], sampleRate: Int) -> Data {
        let numChannels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let blockAlign = UInt16(Int(numChannels) * Int(bitsPerSample) / 8)
        let byteRate = UInt32(sampleRate * Int(blockAlign))
        let dataSize = UInt32(samples.count * 2)
        let chunkSize = UInt32(36) + dataSize

        var data = Data()
        data.reserveCapacity(44 + samples.count * 2)

        func appendASCII(_ s: String) { data.append(contentsOf: s.utf8) }
        func appendU32(_ v: UInt32) { var le = v.littleEndian; withUnsafeBytes(of: &le) { data.append(contentsOf: $0) } }
        func appendU16(_ v: UInt16) { var le = v.littleEndian; withUnsafeBytes(of: &le) { data.append(contentsOf: $0) } }

        // RIFF header
        appendASCII("RIFF"); appendU32(chunkSize); appendASCII("WAVE")
        // fmt chunk
        appendASCII("fmt "); appendU32(16); appendU16(1) // PCM
        appendU16(numChannels); appendU32(UInt32(sampleRate))
        appendU32(byteRate); appendU16(blockAlign); appendU16(bitsPerSample)
        // data chunk
        appendASCII("data"); appendU32(dataSize)

        for sample in samples {
            let clamped = max(-1.0, min(1.0, sample))
            // Use the full negative range (-32768) and full positive range (32767).
            let scaled = clamped < 0 ? Int16(clamped * 32768.0) : Int16(clamped * 32767.0)
            var le = scaled.littleEndian
            withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
        }
        return data
    }
}
