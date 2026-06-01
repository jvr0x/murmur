import Foundation
import XCTest
@testable import MurmurKit

/// Verifies the WAV encoder produces a correct 16-bit PCM container.
final class WavEncoderTests: XCTestCase {
    /// A normal buffer yields the right header fields and total length.
    func testHeaderAndLength() {
        let samples = [Float](repeating: 0, count: 16_000)
        let data = WavEncoder.encode(samples: samples, sampleRate: 16_000)

        XCTAssertEqual(data.count, 44 + 16_000 * 2)
        XCTAssertEqual(ascii(data, 0, 4), "RIFF")
        XCTAssertEqual(ascii(data, 8, 4), "WAVE")
        XCTAssertEqual(ascii(data, 12, 4), "fmt ")
        XCTAssertEqual(readU16(data, 20), 1)        // PCM format
        XCTAssertEqual(readU16(data, 22), 1)        // mono
        XCTAssertEqual(readU32(data, 24), 16_000)   // sample rate
        XCTAssertEqual(readU16(data, 34), 16)       // bits per sample
        XCTAssertEqual(ascii(data, 36, 4), "data")
        XCTAssertEqual(readU32(data, 40), UInt32(16_000 * 2)) // data size
    }

    /// Zero samples still produce a valid 44-byte header with an empty data chunk.
    func testZeroSamples() {
        let data = WavEncoder.encode(samples: [], sampleRate: 16_000)
        XCTAssertEqual(data.count, 44)
        XCTAssertEqual(readU32(data, 40), 0)
    }

    /// Out-of-range floats are clamped to the full Int16 range.
    func testClampsOutOfRange() {
        let data = WavEncoder.encode(samples: [2.0, -2.0], sampleRate: 16_000)
        XCTAssertEqual(readS16(data, 44), 32_767)
        XCTAssertEqual(readS16(data, 46), -32_768)
    }

    // MARK: - Byte readers

    private func ascii(_ d: Data, _ offset: Int, _ length: Int) -> String {
        String(data: d.subdata(in: offset..<(offset + length)), encoding: .ascii) ?? ""
    }
    private func readU16(_ d: Data, _ o: Int) -> UInt16 {
        UInt16(d[o]) | (UInt16(d[o + 1]) << 8)
    }
    private func readU32(_ d: Data, _ o: Int) -> UInt32 {
        UInt32(d[o]) | (UInt32(d[o + 1]) << 8) | (UInt32(d[o + 2]) << 16) | (UInt32(d[o + 3]) << 24)
    }
    private func readS16(_ d: Data, _ o: Int) -> Int16 {
        Int16(bitPattern: UInt16(d[o]) | (UInt16(d[o + 1]) << 8))
    }
}
