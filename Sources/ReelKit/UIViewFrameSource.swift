//
//  UIViewFrameSource.swift
//  ReelKit
//
//  Created by Nazar Kozak on 05.06.2026.
//
//  Screen / UI capture WITHOUT ReplayKit (no permission prompt). Drives a
//  CADisplayLink and renders the view hierarchy with `drawHierarchy`, yielding
//  frames into the same writer as the AR sources. Ported from Sidequest's
//  `ARRecordingService`. iOS-only.
//
//  Trade-off vs ReplayKit: captures only YOUR app's view hierarchy (not other
//  apps / system UI) — which is exactly what an in-app recorder wants, and is
//  why no permission prompt is required.
//

#if os(iOS)
import UIKit
import CoreMedia
import CoreVideo

/// Records a `UIView` (or the key window) by rendering its hierarchy each frame.
public final class UIViewFrameSource: NSObject, FrameSource, @unchecked Sendable {
    public let nativeSize: CGSize

    private weak var view: UIView?
    private let scale: CGFloat
    private let fps: Int
    private let afterScreenUpdates: Bool
    private var displayLink: CADisplayLink?
    private var continuation: AsyncStream<TimedFrame>.Continuation?
    private var startTimestamp: CFTimeInterval?
    private var pool: CVPixelBufferPool?

    /// - Parameters:
    ///   - view: the view to capture. Pass the key window to record the whole screen of your app.
    ///   - scale: render scale (1 = points, 2 = retina). Higher = sharper, heavier.
    ///   - fps: capture cadence.
    ///   - afterScreenUpdates: pass `true` to capture Metal-backed content such as
    ///     an `ARView`/`ARSCNView` (camera + 3D overlays) — slower but complete.
    ///     Leave `false` (default) for plain UIKit/SwiftUI screen capture — fastest.
    @MainActor
    public init(_ view: UIView, scale: CGFloat = 2.0, fps: Int = 30, afterScreenUpdates: Bool = false) {
        self.view = view
        self.scale = scale
        self.fps = fps
        self.afterScreenUpdates = afterScreenUpdates
        self.nativeSize = CGSize(width: view.bounds.width * scale,
                                 height: view.bounds.height * scale)
        super.init()
    }

    public func frames() -> AsyncStream<TimedFrame> {
        AsyncStream { continuation in
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in self?.invalidate() }
            }
            Task { @MainActor in
                self.continuation = continuation
                self.pool = Self.makePool(size: self.nativeSize)
                let link = CADisplayLink(target: self, selector: #selector(self.tick))
                link.preferredFramesPerSecond = self.fps
                link.add(to: .main, forMode: .common)
                self.displayLink = link
            }
        }
    }

    public func stop() {
        continuation?.finish()
        continuation = nil
        Task { @MainActor in self.invalidate() }
    }

    @MainActor
    private func invalidate() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @MainActor
    @objc private func tick(_ link: CADisplayLink) {
        guard let view, let continuation, let pool else { return }
        if startTimestamp == nil { startTimestamp = link.timestamp }
        let elapsed = link.timestamp - (startTimestamp ?? link.timestamp)
        let time = CMTime(seconds: elapsed, preferredTimescale: 600)

        guard let buffer = Self.render(view: view, scale: scale, size: nativeSize, pool: pool, afterScreenUpdates: afterScreenUpdates) else { return }
        continuation.yield(TimedFrame(pixelBuffer: buffer, time: time))
    }

    // MARK: - Rendering

    private static func makePool(size: CGSize) -> CVPixelBufferPool? {
        let attrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(size.width),
            kCVPixelBufferHeightKey as String: Int(size.height),
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]
        var pool: CVPixelBufferPool?
        CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, attrs as CFDictionary, &pool)
        return pool
    }

    /// Single-pass render: `drawHierarchy` writes **directly** into the pixel
    /// buffer's backing `CGContext` — no intermediate `UIImage`/`CGImage`
    /// allocation per frame, and the buffer is recycled from a pool. This is the
    /// optimal path: one render, zero per-frame heap churn.
    @MainActor
    private static func render(view: UIView, scale: CGFloat, size: CGSize, pool: CVPixelBufferPool, afterScreenUpdates: Bool) -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pixelBuffer) == kCVReturnSuccess,
              let buffer = pixelBuffer else { return nil }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }

        // Map UIKit's top-left coordinate space onto the bottom-left CG context,
        // applying the render scale in the same transform.
        context.translateBy(x: 0, y: size.height)
        context.scaleBy(x: scale, y: -scale)

        UIGraphicsPushContext(context)
        // No-permission capture: render only the app's own view hierarchy.
        _ = view.drawHierarchy(in: view.bounds, afterScreenUpdates: afterScreenUpdates)
        UIGraphicsPopContext()

        return buffer
    }
}
#endif
