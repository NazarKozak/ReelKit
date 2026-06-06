//
//  FrameConverter.swift
//  ReelKit
//
//  Created by Nazar Kozak on 05.06.2026.
//
//  GPU-backed conversion of arbitrary capture buffers (e.g. the ARFrame YCbCr
//  camera buffer) into writer-ready BGRA, with optional overlay compositing.
//  Output buffers are recycled from a pool. iOS-only.
//

#if os(iOS)
import CoreImage
import CoreVideo
import CoreGraphics

/// Converts source pixel buffers to 32BGRA at a fixed output size, optionally
/// compositing an overlay image on top. Backed by a single reused `CIContext`
/// (Metal) and a `CVPixelBufferPool`.
final class FrameConverter: @unchecked Sendable {
    private let context: CIContext
    private var pool: CVPixelBufferPool?
    private var poolSize: CGSize = .zero

    init() {
        self.context = CIContext(options: [
            .useSoftwareRenderer: false,
            .cacheIntermediates: false
        ])
    }

    /// Renders `source` (any CoreImage-readable format) into a pooled BGRA buffer
    /// scaled to `size`, compositing `overlay` (already in the output space) on top.
    func bgra(from source: CVPixelBuffer, size: CGSize, overlay: CGImage? = nil) -> CVPixelBuffer? {
        guard size.width > 0, size.height > 0 else { return nil }
        ensurePool(size: size)
        guard let pool else { return nil }

        var out: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &out) == kCVReturnSuccess,
              let dst = out else { return nil }

        var image = CIImage(cvPixelBuffer: source)
        let extent = image.extent
        if extent.width > 0, extent.height > 0 {
            let sx = size.width / extent.width
            let sy = size.height / extent.height
            if sx != 1 || sy != 1 {
                image = image.transformed(by: CGAffineTransform(scaleX: sx, y: sy))
            }
        }
        if let overlay {
            image = CIImage(cgImage: overlay).composited(over: image)
        }
        context.render(image, to: dst)
        return dst
    }

    private func ensurePool(size: CGSize) {
        if pool != nil, poolSize == size { return }
        let attrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(size.width),
            kCVPixelBufferHeightKey as String: Int(size.height),
            kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any]()
        ]
        var created: CVPixelBufferPool?
        CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, attrs as CFDictionary, &created)
        pool = created
        poolSize = size
    }
}
#endif
