//
//  AudioCapture.swift
//  SurfaceRecorderSDK
//
//  Created by Nazar Kozak on 05.06.2026.
//
//  Microphone capture with CMSampleBuffer time-correction against the video
//  clock — the part most AR recorders get wrong. Ported from Sidequest's audio
//  handling. iOS-only (AVAudioSession / AVCaptureSession audio path).
//

#if os(iOS)
@preconcurrency import AVFoundation

/// Captures microphone audio and re-times each sample buffer so it lines up with
/// the video presentation clock established by the first recorded frame.
final class AudioCapture: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let session = AVCaptureSession()
    private let output = AVCaptureAudioDataOutput()
    private let queue = DispatchQueue(label: "surfacerec.audio")
    private let onSample: @Sendable (CMSampleBuffer) -> Void

    /// Offset between the audio device clock and the video session clock.
    private var anchorTime: CMTime?
    private var firstAudioPTS: CMTime?

    init(onSample: @escaping @Sendable (CMSampleBuffer) -> Void) throws {
        self.onSample = onSample
        super.init()

        // Coexist with an active ARSession: use a category that does not steal
        // the AR audio route, and tolerate mixing.
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.playAndRecord, mode: .videoRecording, options: [.mixWithOthers, .defaultToSpeaker])

        session.beginConfiguration()
        guard
            let mic = AVCaptureDevice.default(for: .audio),
            let input = try? AVCaptureDeviceInput(device: mic),
            session.canAddInput(input),
            session.canAddOutput(output)
        else {
            session.commitConfiguration()
            throw RecorderError.sourceUnavailable
        }
        session.addInput(input)
        output.setSampleBufferDelegate(self, queue: queue)
        session.addOutput(output)
        session.commitConfiguration()
    }

    func start() throws {
        queue.async { [weak self] in
            guard let self, !self.session.isRunning else { return }
            self.session.startRunning()
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    /// Anchors audio timing to the video clock's session start time.
    func anchor(to time: CMTime) {
        queue.async { [weak self] in self?.anchorTime = time }
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let anchorTime else { return } // drop audio until the video session starts

        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        if firstAudioPTS == nil { firstAudioPTS = pts }
        guard let firstAudioPTS else { return }

        // Re-time: elapsed-since-first-audio, offset by the video session start.
        let elapsed = CMTimeSubtract(pts, firstAudioPTS)
        let corrected = CMTimeAdd(anchorTime, elapsed)

        if let retimed = sampleBuffer.retimed(to: corrected) {
            onSample(retimed)
        }
    }
}

private extension CMSampleBuffer {
    /// Returns a copy of the sample buffer with its presentation timestamp replaced.
    func retimed(to time: CMTime) -> CMSampleBuffer? {
        var timing = CMSampleTimingInfo(
            duration: CMSampleBufferGetDuration(self),
            presentationTimeStamp: time,
            decodeTimeStamp: .invalid
        )
        var out: CMSampleBuffer?
        let status = CMSampleBufferCreateCopyWithNewTiming(
            allocator: kCFAllocatorDefault,
            sampleBuffer: self,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleBufferOut: &out
        )
        return status == noErr ? out : nil
    }
}
#endif
