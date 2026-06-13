//
//  CameraFrameSource.swift
//  SurfaceRecorderSDK
//
//  Created by Nazar Kozak on 05.06.2026.
//
//  Records a plain AVCaptureSession camera feed (no ARKit). Exposes its `session`
//  so the app can show a preview layer, and yields frames from a video data
//  output while recording. iOS-only.
//

#if os(iOS)
@preconcurrency import AVFoundation
import CoreMedia
import CoreVideo

/// Captures a device camera and records it through SurfaceRecorderSDK.
public final class CameraFrameSource: NSObject, FrameSource, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    public enum Position: Sendable { case back, front }

    /// The live capture session — attach an `AVCaptureVideoPreviewLayer` to show a preview.
    public let session = AVCaptureSession()
    public let nativeSize: CGSize

    private let output = AVCaptureVideoDataOutput()
    private let queue = DispatchQueue(label: "surfacerec.camera")
    private var continuation: AsyncStream<TimedFrame>.Continuation?
    private var recording = false
    private var firstPTS: CMTime?

    /// - Parameters:
    ///   - position: back or front camera.
    ///   - fps: optional capped frame rate (e.g. 30 or 60). `nil` = device default.
    ///   - size: output video size (defaults to portrait 1080×1920).
    @MainActor
    public init(position: Position = .back, fps: Int? = nil, size: CGSize = CGSize(width: 1080, height: 1920)) {
        self.nativeSize = size
        super.init()
        configure(position: position, fps: fps)
    }

    private func configure(position: Position, fps: Int?) {
        session.beginConfiguration()
        session.sessionPreset = .hd1920x1080

        let avPosition: AVCaptureDevice.Position = position == .back ? .back : .front
        let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: avPosition)
        if let device, let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) {
            session.addInput(input)
        }

        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)
        if session.canAddOutput(output) { session.addOutput(output) }

        if let connection = output.connection(with: .video) {
            if connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 } // portrait
            if position == .front, connection.isVideoMirroringSupported { connection.isVideoMirrored = true }
        }

        if let fps, let device {
            try? device.lockForConfiguration()
            let duration = CMTime(value: 1, timescale: CMTimeScale(fps))
            device.activeVideoMinFrameDuration = duration
            device.activeVideoMaxFrameDuration = duration
            device.unlockForConfiguration()
        }

        session.commitConfiguration()
    }

    /// Starts the capture session (for preview and/or recording).
    public func startRunning() {
        queue.async { [weak self] in
            guard let self, !self.session.isRunning else { return }
            self.session.startRunning()
        }
    }

    /// Stops the capture session.
    public func stopRunning() {
        queue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    // MARK: - FrameSource

    public func frames() -> AsyncStream<TimedFrame> {
        AsyncStream { continuation in
            self.firstPTS = nil
            self.continuation = continuation
            self.recording = true
            continuation.onTermination = { [weak self] _ in self?.recording = false }
        }
    }

    public func stop() {
        recording = false
        continuation?.finish()
        continuation = nil
    }

    public func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard recording, let continuation,
              let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        if firstPTS == nil { firstPTS = pts }
        let time = CMTimeSubtract(pts, firstPTS ?? pts)
        continuation.yield(TimedFrame(pixelBuffer: buffer, time: time))
    }
}
#endif
