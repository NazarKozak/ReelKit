//
//  RecordingConfig.swift
//  SurfaceRecorderSDK
//
//  Created by Nazar Kozak on 05.06.2026.
//

import AVFoundation
import CoreGraphics

/// Output configuration for a recording session.
public struct RecordingConfig: Sendable {
    /// Target frames per second for the written video.
    public var fps: Int32
    /// Video codec used by the writer.
    public var codec: Codec
    /// Output quality preset (maps to a target bitrate for the resolution).
    public var quality: Quality
    /// Optional explicit output size. When `nil`, the source's native size is used.
    public var size: CGSize?

    public init(
        fps: Int32 = 30,
        codec: Codec = .h264,
        quality: Quality = .high,
        size: CGSize? = nil
    ) {
        self.fps = fps
        self.codec = codec
        self.quality = quality
        self.size = size
    }

    public enum Codec: Sendable {
        case h264
        case hevc

        var avCodec: AVVideoCodecType {
            switch self {
            case .h264: .h264
            case .hevc: .hevc
            }
        }
    }

    public enum Quality: Sendable {
        case low
        case medium
        case high

        /// Bits-per-pixel-per-second heuristic used to derive a bitrate from resolution.
        var bppPerSecond: Double {
            switch self {
            case .low: 4.0
            case .medium: 8.0
            case .high: 12.0
            }
        }

        func bitrate(for size: CGSize, fps: Int32) -> Int {
            Int(size.width * size.height * Double(fps) * bppPerSecond / 8.0)
        }
    }
}

/// Where the recording audio comes from.
public enum AudioMode: Sendable {
    /// No audio track.
    case none
    /// Microphone, captured and time-synced to the video clock.
    case microphone
    /// Audio delivered by an active `ARSession` (`providesAudioData = true`).
    case arSessionAudio
}

/// Errors surfaced by SurfaceRecorderSDK.
public enum RecorderError: Error, Sendable {
    case writerSetupFailed
    case alreadyRecording
    case notRecording
    case sourceUnavailable
    case pixelBufferPoolUnavailable
}
