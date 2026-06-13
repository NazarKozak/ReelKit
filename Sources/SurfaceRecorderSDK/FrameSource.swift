//
//  FrameSource.swift
//  SurfaceRecorderSDK
//
//  Created by Nazar Kozak on 05.06.2026.
//

import CoreGraphics
import CoreMedia
import CoreVideo

/// A frame, paired with the presentation time it should be written at.
///
/// `CVPixelBuffer` is a CoreFoundation reference type with no `Sendable`
/// conformance, but pixel buffers are routinely handed off across the AV
/// capture/encode boundary. We vouch for safe transfer here.
public struct TimedFrame: @unchecked Sendable {
    public let pixelBuffer: CVPixelBuffer
    public let time: CMTime

    public init(pixelBuffer: CVPixelBuffer, time: CMTime) {
        self.pixelBuffer = pixelBuffer
        self.time = time
    }
}

/// Abstraction over *what* is being recorded.
///
/// Implementations decide how to produce a stream of `TimedFrame`s:
/// - ``RealityKitFrameSource`` — composites a RealityKit `ARView` (camera + overlays). *(headline)*
/// - `ARSCNViewFrameSource` — SceneKit AR (ARVideoKit parity / migration path). *(Phase 2)*
/// - `UIViewFrameSource` — `drawHierarchy` capture, no ReplayKit prompt. *(Phase 2)*
/// - `CustomFrameSource` — bring-your-own buffers.
public protocol FrameSource: Sendable {
    /// The native pixel size of the produced frames.
    var nativeSize: CGSize { get }

    /// Begins producing frames. The returned stream finishes when ``stop()`` is called.
    func frames() -> AsyncStream<TimedFrame>

    /// Stops frame production and finishes the stream.
    func stop()
}
