//
//  VideoWriter.swift
//  ReelKit
//
//  Created by Nazar Kozak on 05.06.2026.
//
//  Wraps AVAssetWriter + a pixel-buffer adaptor. Ported and generalized from
//  Sidequest's `VideoSaver` / `ARVideoRecordingService` writer path.
//

import AVFoundation

/// Encodes incoming pixel buffers to an MP4 file on disk.
///
/// Marked `@unchecked Sendable`: all access is serialized by the owning
/// ``ReelRecorder`` actor, so the underlying `AVAssetWriter` is never touched
/// concurrently.
final class VideoWriter: @unchecked Sendable {
    private let writer: AVAssetWriter
    private let videoInput: AVAssetWriterInput
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    private(set) var audioInput: AVAssetWriterInput?

    let outputURL: URL
    private var started = false

    init(size: CGSize, config: RecordingConfig, audio: AudioMode) throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("reelkit-\(UUID().uuidString).mp4")
        self.outputURL = url

        guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mp4) else {
            throw ReelError.writerSetupFailed
        }
        self.writer = writer

        let bitrate = config.quality.bitrate(for: size, fps: config.fps)
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: config.codec.avCodec,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: bitrate,
                AVVideoExpectedSourceFrameRateKey: config.fps
            ]
        ]
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = true
        self.videoInput = videoInput

        let attrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(size.width),
            kCVPixelBufferHeightKey as String: Int(size.height)
        ]
        self.adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput,
            sourcePixelBufferAttributes: attrs
        )
        guard writer.canAdd(videoInput) else { throw ReelError.writerSetupFailed }
        writer.add(videoInput)

        if audio != .none {
            let audioSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVNumberOfChannelsKey: 1,
                AVSampleRateKey: 44_100,
                AVEncoderBitRateKey: 64_000
            ]
            let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            audioInput.expectsMediaDataInRealTime = true
            if writer.canAdd(audioInput) {
                writer.add(audioInput)
                self.audioInput = audioInput
            }
        }
    }

    func start(at time: CMTime) {
        guard !started else { return }
        writer.startWriting()
        writer.startSession(atSourceTime: time)
        started = true
    }

    func append(_ frame: TimedFrame) {
        guard started, videoInput.isReadyForMoreMediaData else { return }
        adaptor.append(frame.pixelBuffer, withPresentationTime: frame.time)
    }

    /// Appends an audio sample buffer. The caller is responsible for time-correcting
    /// the buffer against the video clock (see `AudioCapture`).
    func appendAudio(_ sample: CMSampleBuffer) {
        guard started, let audioInput, audioInput.isReadyForMoreMediaData else { return }
        audioInput.append(sample)
    }

    func finish() async throws -> URL {
        guard started else { throw ReelError.notRecording }
        videoInput.markAsFinished()
        audioInput?.markAsFinished()
        await writer.finishWriting()
        if writer.status == .failed {
            throw writer.error ?? ReelError.writerSetupFailed
        }
        return outputURL
    }
}
