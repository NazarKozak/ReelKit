//
//  SurfaceRecorder.swift
//  SurfaceRecorderSDK
//
//  Created by Nazar Kozak on 05.06.2026.
//

import AVFoundation

/// Records a ``FrameSource`` (and optional audio) to an MP4 file — without ReplayKit.
///
/// ```swift
/// let recorder = SurfaceRecorder(source: RealityKitFrameSource(arView), audio: .microphone)
/// try await recorder.start()
/// // ...
/// let url = try await recorder.stop()
/// ```
public actor SurfaceRecorder {
    private let source: FrameSource
    private let audioMode: AudioMode
    private let config: RecordingConfig

    private var writer: VideoWriter?
    private var pumpTask: Task<Void, Never>?
    private var isRecording = false
    private var sessionStarted = false

    #if os(iOS)
    private var audioCapture: AudioCapture?
    #endif

    public init(
        source: FrameSource,
        audio: AudioMode = .none,
        config: RecordingConfig = .init()
    ) {
        self.source = source
        self.audioMode = audio
        self.config = config
    }

    /// Starts recording. Throws ``RecorderError/alreadyRecording`` if already active.
    public func start() async throws {
        guard !isRecording else { throw RecorderError.alreadyRecording }

        let size = config.size ?? source.nativeSize
        guard size.width > 0, size.height > 0 else { throw RecorderError.sourceUnavailable }

        let writer = try VideoWriter(size: size, config: config, audio: audioMode)
        self.writer = writer
        isRecording = true
        sessionStarted = false // video clock anchors to the first frame's PTS

        #if os(iOS)
        if audioMode == .microphone {
            let capture = try AudioCapture { [weak self] sample in
                let box = UncheckedSendableBox(value: sample)
                Task { await self?.ingestAudio(box) }
            }
            self.audioCapture = capture
            try capture.start()
        }
        #endif

        pumpTask = Task { [source] in
            for await frame in source.frames() {
                self.ingestFrame(frame) // Task inherits actor isolation; no hop
            }
        }
    }

    /// Stops recording and returns the URL of the written MP4.
    public func stop() async throws -> URL {
        guard isRecording, let writer else { throw RecorderError.notRecording }
        isRecording = false

        source.stop()
        pumpTask?.cancel()
        pumpTask = nil

        #if os(iOS)
        audioCapture?.stop()
        audioCapture = nil
        #endif

        let url = try await writer.finish()
        self.writer = nil
        return url
    }

    // MARK: - Ingest

    private func ingestFrame(_ frame: TimedFrame) {
        guard isRecording, let writer else { return }
        if !sessionStarted {
            writer.start(at: frame.time)
            sessionStarted = true
            #if os(iOS)
            audioCapture?.anchor(to: frame.time)
            #endif
        }
        writer.append(frame)
    }

    #if os(iOS)
    private func ingestAudio(_ box: UncheckedSendableBox<CMSampleBuffer>) {
        guard isRecording, let writer else { return }
        writer.appendAudio(box.value)
    }
    #endif
}

#if os(iOS)
/// Carries a non-`Sendable` value across an isolation boundary. The audio sample
/// is produced, boxed, and consumed serially (capture queue → recorder actor),
/// so the transfer is race-free.
struct UncheckedSendableBox<Value>: @unchecked Sendable {
    let value: Value
}
#endif
