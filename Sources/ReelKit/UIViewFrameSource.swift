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
//  Cost note: `drawHierarchy` rasterizes the hierarchy on the CPU each frame, so
//  cost scales with the output pixel count. Use `maxDimension` to cap resolution
//  (e.g. 1280) on large screens to cut CPU substantially.
//

#if os(iOS)
import UIKit
import CoreMedia
import CoreVideo

/// Records a `UIView` (or the key window) by rendering its hierarchy each frame.
public final class UIViewFrameSource: NSObject, FrameSource, @unchecked Sendable {
    public let nativeSize: CGSize

    private weak var view: UIView?
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
    ///   - afterScreenUpdates: `false` (default) snapshots already-rendered content
    ///     — fast, no frame loss, and usually still captures presented Metal/AR
    ///     layers. Use `true` only if `false` yields stale/blank frames; it forces a
    ///     synchronous re-render and is much slower (can halve the frame rate).
    ///   - maxDimension: optional cap on the longest output side (points × scale).
    ///     Downscales large screens to reduce CPU/encode cost. `nil` = no cap.
    @MainActor
    public init(
        _ view: UIView,
        scale: CGFloat = 2.0,
        fps: Int = 30,
        afterScreenUpdates: Bool = false,
        maxDimension: CGFloat? = nil
    ) {
        self.view = view
        self.fps = fps
        self.afterScreenUpdates = afterScreenUpdates
        self.nativeSize = Self.outputSize(bounds: view.bounds.size, scale: scale, maxDimension: maxDimension)
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

        guard let buffer = Self.render(view: view, size: nativeSize, pool: pool, afterScreenUpdates: afterScreenUpdates) else { return }
        continuation.yield(TimedFrame(pixelBuffer: buffer, time: time))
    }

    // MARK: - Sizing & rendering

    /// Output size = bounds × scale, optionally capped to `maxDimension` on the
    /// longest side, rounded to even dimensions (H.264 requirement).
    private static func outputSize(bounds: CGSize, scale: CGFloat, maxDimension: CGFloat?) -> CGSize {
        var w = bounds.width * scale
        var h = bounds.height * scale
        if let maxDimension {
            let longest = max(w, h)
            if longest > maxDimension {
                let f = maxDimension / longest
                w *= f
                h *= f
            }
        }
        return CGSize(width: (w / 2).rounded(.down) * 2, height: (h / 2).rounded(.down) * 2)
    }

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
    /// allocation per frame, and the buffer is recycled from a pool. One render,
    /// zero per-frame heap churn.
    @MainActor
    private static func render(view: UIView, size: CGSize, pool: CVPixelBufferPool, afterScreenUpdates: Bool) -> CVPixelBuffer? {
        let bounds = view.bounds
        guard bounds.width > 0, bounds.height > 0 else { return nil }

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

        // Map UIKit's top-left point space onto the bottom-left CG context,
        // scaling bounds → output size (aspect preserved) and flipping vertically.
        context.translateBy(x: 0, y: size.height)
        context.scaleBy(x: size.width / bounds.width, y: -(size.height / bounds.height))

        UIGraphicsPushContext(context)
        // No-permission capture: render only the app's own view hierarchy.
        _ = view.drawHierarchy(in: bounds, afterScreenUpdates: afterScreenUpdates)
        UIGraphicsPopContext()

        return buffer
    }
}
#endif
