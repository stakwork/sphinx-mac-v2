//
//  StrutPCM.swift
//  com.stakwork.sphinx.desktop
//
//  Sample-format conversion only: channel 0, clamp, PCM16LE.
//  Does not resample and must not inspect sample rate.
//

import AVFoundation
import Foundation

enum StrutPCM {

    /// Convert a non-interleaved float buffer's channel 0 to mono PCM16LE.
    static func pcm16LE(from buffer: AVAudioPCMBuffer) -> Data {
        guard let channels = buffer.floatChannelData else { return Data() }
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return Data() }
        return pcm16LE(fromChannel0: channels[0], frameCount: frames)
    }

    /// Convert `frameCount` float samples (channel 0) to mono PCM16LE `Data`.
    /// Each sample is clamped to `[-1, 1]`, scaled by 32767, and written as
    /// `Int16.littleEndian`.
    static func pcm16LE(
        fromChannel0 samples: UnsafePointer<Float>,
        frameCount: Int
    ) -> Data {
        guard frameCount > 0 else { return Data() }

        var data = Data(count: frameCount * MemoryLayout<Int16>.size)
        data.withUnsafeMutableBytes { rawBuffer in
            let dest = rawBuffer.bindMemory(to: Int16.self)
            for i in 0..<frameCount {
                let clamped = max(Float(-1.0), min(Float(1.0), samples[i]))
                let scaled = Int16((clamped * 32767.0).rounded())
                dest[i] = scaled.littleEndian
            }
        }
        return data
    }
}
