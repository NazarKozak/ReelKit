//
//  RealityKitFrameSource.swift
//  ReelKit
//
//  Created by Nazar Kozak on 05.06.2026.
//
//  Headline source: records a RealityKit `ARView` — camera feed + rendered
//  overlays — by tapping ARSession frames. The modern path ARVideoKit never
//  covered. iOS-only.
//

#if os(iOS)
import ARKit
import RealityKit
import CoreMedia
import CoreVideo

/// Produces frames from an active RealityKit `ARView` session.
///
/// Taps `ARSessionDelegate`, converts the captured `ARFrame` camera buffer
/// (YCbCr) to writer-ready BGRA via ``FrameConverter``, and optionally
/// composites a 2D `overlay` image on top each frame.
///
/// > To capture RealityKit's full 3D-rendered content **and** SwiftUI/UIKit
/// > overlays composited exactly as on screen, record the `ARView`'s container
/// > with ``UIViewFrameSource`` (set `afterScreenUpdates: true`). This source is
/// > the high-fidelity camera-buffer path.
public final class RealityKitFrameSource: NSObject, FrameSource, ARSessionDelegate, @unchecked Sendable {
    public let nativeSize: CGSize

    private weak var arView: ARView?
    private let session: ARSession
    private let converter = FrameConverter()
    private let overlay: (@Sendable () -> CGImage?)?
    private var continuation: AsyncStream<TimedFrame>.Continuation?
    private var previousDelegate: ARSessionDelegate?

    /// - Parameters:
    ///   - arView: the live RealityKit view to record.
    ///   - size: output video size.
    ///   - overlay: optional per-frame 2D overlay (already in output space),
    ///     e.g. a pre-rendered HUD. Called on the AR delegate queue.
    @MainActor
    public init(
        _ arView: ARView,
        size: CGSize = CGSize(width: 1080, height: 1920),
        overlay: (@Sendable () -> CGImage?)? = nil
    ) {
        self.arView = arView
        self.session = arView.session
        self.nativeSize = size
        self.overlay = overlay
        super.init()
    }

    public func frames() -> AsyncStream<TimedFrame> {
        AsyncStream { continuation in
            self.continuation = continuation
            // Preserve any existing delegate so we don't break the host app.
            self.previousDelegate = session.delegate
            session.delegate = self
            continuation.onTermination = { [weak self] _ in
                self?.detach()
            }
        }
    }

    public func stop() {
        continuation?.finish()
        continuation = nil
        detach()
    }

    private func detach() {
        if session.delegate === self {
            session.delegate = previousDelegate
        }
    }

    // MARK: - ARSessionDelegate

    public func session(_ session: ARSession, didUpdate frame: ARFrame) {
        previousDelegate?.session?(session, didUpdate: frame)
        guard let continuation else { return }
        let time = CMTime(seconds: frame.timestamp, preferredTimescale: 600)
        guard let buffer = converter.bgra(from: frame.capturedImage, size: nativeSize, overlay: overlay?()) else { return }
        continuation.yield(TimedFrame(pixelBuffer: buffer, time: time))
    }
}
#endif
