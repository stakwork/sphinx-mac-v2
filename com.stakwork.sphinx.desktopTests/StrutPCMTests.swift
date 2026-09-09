//
//  StrutPCMTests.swift
//  com.stakwork.sphinx.desktopTests
//

import AVFoundation
import XCTest
@testable import com_stakwork_sphinx_desktop

final class StrutPCMTests: XCTestCase {

    func testMonoPassthrough() {
        let buffer = makeBuffer(channels: 1, samples: [[0.0, 0.5, -0.5]])
        let data = StrutPCM.pcm16LE(from: buffer)
        XCTAssertEqual(data.count, 6)
        XCTAssertEqual(int16LE(data, at: 0), 0)
        XCTAssertEqual(int16LE(data, at: 2), 16384)
        XCTAssertEqual(int16LE(data, at: 4), -16384)
    }

    func testStereoTakesChannel0Only() {
        let buffer = makeBuffer(
            channels: 2,
            samples: [
                [0.25, -0.25],
                [0.9, -0.9]
            ]
        )
        let data = StrutPCM.pcm16LE(from: buffer)
        XCTAssertEqual(data.count, 4)
        XCTAssertEqual(int16LE(data, at: 0), 8192)
        XCTAssertEqual(int16LE(data, at: 2), -8192)
    }

    func testClampingAtPlusMinusOne() {
        let buffer = makeBuffer(channels: 1, samples: [[1.5, -2.0, 1.0, -1.0]])
        let data = StrutPCM.pcm16LE(from: buffer)
        XCTAssertEqual(int16LE(data, at: 0), 32767)
        XCTAssertEqual(int16LE(data, at: 2), -32767)
        XCTAssertEqual(int16LE(data, at: 4), 32767)
        XCTAssertEqual(int16LE(data, at: 6), -32767)
    }

    func testLittleEndianByteOrderForKnownValues() {
        let buffer = makeBuffer(channels: 1, samples: [[1.0, -1.0, 0.0]])
        let data = StrutPCM.pcm16LE(from: buffer)
        // 32767 = 0x7FFF → FF 7F; -32767 = 0x8001 → 01 80; 0 → 00 00
        XCTAssertEqual(Array(data), [0xFF, 0x7F, 0x01, 0x80, 0x00, 0x00])
    }

    func testRawPointerAPIMatchesBufferAPI() {
        let samples: [Float] = [0.0, 1.0, -1.0]
        let fromPointer = samples.withUnsafeBufferPointer { ptr in
            StrutPCM.pcm16LE(fromChannel0: ptr.baseAddress!, frameCount: ptr.count)
        }
        let buffer = makeBuffer(channels: 1, samples: [samples])
        XCTAssertEqual(fromPointer, StrutPCM.pcm16LE(from: buffer))
    }

    // MARK: - Helpers

    private func makeBuffer(channels: AVAudioChannelCount, samples: [[Float]]) -> AVAudioPCMBuffer {
        let frames = AVAudioFrameCount(samples[0].count)
        let format = AVAudioFormat(
            standardFormatWithSampleRate: 48_000,
            channels: channels
        )!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        for channel in 0..<Int(channels) {
            let dest = buffer.floatChannelData![channel]
            for i in 0..<Int(frames) {
                dest[i] = samples[channel][i]
            }
        }
        return buffer
    }

    private func int16LE(_ data: Data, at offset: Int) -> Int16 {
        let low = Int16(data[offset])
        let high = Int16(data[offset + 1])
        return Int16(bitPattern: UInt16(bitPattern: low) | (UInt16(bitPattern: high) << 8))
    }
}
