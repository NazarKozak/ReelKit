//
//  ARViewFrameSource.swift
//  ReelKit
//
//  Created by Nazar Kozak on 05.06.2026.
//
//  High-performance AR recording: taps `ARView.renderCallbacks.postProcess` to
//  grab the already-composited camera + RealityKit color texture on the GPU each
//  frame, and blits it into a CVPixelBuffer via a Metal render pass — no
//  drawHierarchy, no CPU rasterization. The captured texture is already in the
//  view's orientation, so no rotation is needed. iOS-only.
//

#if os(iOS)
import ARKit
import RealityKit
import Metal
import CoreVideo
import CoreMedia
import QuartzCore

/// Records a RealityKit `ARView` (camera + 3D content) at GPU speed.
///
/// Captures the rendered scene, not the raw camera buffer — so the 3D content is
/// included. SwiftUI/UIKit overlays drawn *on top of* the `ARView` are not part
/// of the RealityKit render; to include those too, use ``UIViewFrameSource`` with
/// `afterScreenUpdates: true` (heavier).
public final class ARViewFrameSource: NSObject, FrameSource, @unchecked Sendable {
    public let nativeSize: CGSize

    private weak var arView: ARView?
    private var continuation: AsyncStream<TimedFrame>.Continuation?

    private var device: MTLDevice?
    private var pipeline: MTLRenderPipelineState?
    private var sampler: MTLSamplerState?
    private var textureCache: CVMetalTextureCache?
    private var pool: CVPixelBufferPool?
    private var startTime: CFTimeInterval?

    /// - Parameters:
    ///   - arView: the live RealityKit view to record.
    ///   - maxDimension: optional cap on the longest output side (the drawable can
    ///     be very large on Pro Max). `nil` records at native drawable resolution.
    @MainActor
    public init(_ arView: ARView, maxDimension: CGFloat? = 1920) {
        self.arView = arView

        let scale = arView.window?.screen.scale ?? UIScreen.main.scale
        var bounds = arView.bounds.size
        if bounds.width == 0 || bounds.height == 0 { bounds = UIScreen.main.bounds.size }
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
        self.nativeSize = CGSize(width: (w / 2).rounded(.down) * 2, height: (h / 2).rounded(.down) * 2)
        super.init()
    }

    public func frames() -> AsyncStream<TimedFrame> {
        AsyncStream { continuation in
            self.continuation = continuation
            continuation.onTermination = { [weak self] _ in self?.detach() }
            Task { @MainActor in
                self.arView?.renderCallbacks.postProcess = { [weak self] context in
                    self?.handle(context)
                }
            }
        }
    }

    public func stop() {
        continuation?.finish()
        continuation = nil
        detach()
    }

    private func detach() {
        Task { @MainActor in self.arView?.renderCallbacks.postProcess = nil }
    }

    // MARK: - Per-frame (render thread)

    private func handle(_ context: ARView.PostProcessContext) {
        // Required: pass the rendered scene through to the screen.
        if let blit = context.commandBuffer.makeBlitCommandEncoder() {
            blit.copy(from: context.sourceColorTexture, to: context.targetColorTexture)
            blit.endEncoding()
        }

        guard let continuation else { return }
        ensureResources(device: context.device)
        guard let pipeline, let sampler, let cache = textureCache, let pool else { return }

        var pb: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pb) == kCVReturnSuccess,
              let pixelBuffer = pb else { return }

        var cvTexture: CVMetalTexture?
        let w = Int(nativeSize.width), h = Int(nativeSize.height)
        guard CVMetalTextureCacheCreateTextureFromImage(
                kCFAllocatorDefault, cache, pixelBuffer, nil, .bgra8Unorm, w, h, 0, &cvTexture
              ) == kCVReturnSuccess,
              let cvTexture, let dst = CVMetalTextureGetTexture(cvTexture) else { return }

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = dst
        pass.colorAttachments[0].loadAction = .dontCare
        pass.colorAttachments[0].storeAction = .store
        guard let enc = context.commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        enc.setRenderPipelineState(pipeline)
        enc.setFragmentTexture(context.sourceColorTexture, index: 0)
        enc.setFragmentSamplerState(sampler, index: 0)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc.endEncoding()

        let now = CACurrentMediaTime()
        if startTime == nil { startTime = now }
        let time = CMTime(seconds: now - (startTime ?? now), preferredTimescale: 600)

        context.commandBuffer.addCompletedHandler { _ in
            _ = cvTexture // keep the texture (and its buffer) alive until the GPU is done
            continuation.yield(TimedFrame(pixelBuffer: pixelBuffer, time: time))
        }
    }

    // MARK: - Lazy Metal resources

    private func ensureResources(device: MTLDevice) {
        guard self.device == nil else { return }
        self.device = device
        CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &textureCache)

        let sd = MTLSamplerDescriptor()
        sd.minFilter = .linear
        sd.magFilter = .linear
        sampler = device.makeSamplerState(descriptor: sd)

        let source = """
        #include <metal_stdlib>
        using namespace metal;
        struct VOut { float4 pos [[position]]; float2 uv; };
        vertex VOut rk_vtx(uint vid [[vertex_id]]) {
            float2 p[3] = { float2(-1.0, -1.0), float2(3.0, -1.0), float2(-1.0, 3.0) };
            VOut o;
            o.pos = float4(p[vid], 0.0, 1.0);
            o.uv = p[vid] * float2(0.5, -0.5) + 0.5;
            return o;
        }
        fragment float4 rk_frag(VOut in [[stage_in]],
                                texture2d<float> src [[texture(0)]],
                                sampler s [[sampler(0)]]) {
            return src.sample(s, in.uv);
        }
        """
        guard let library = try? device.makeLibrary(source: source, options: nil) else { return }
        let pd = MTLRenderPipelineDescriptor()
        pd.vertexFunction = library.makeFunction(name: "rk_vtx")
        pd.fragmentFunction = library.makeFunction(name: "rk_frag")
        pd.colorAttachments[0].pixelFormat = .bgra8Unorm
        pipeline = try? device.makeRenderPipelineState(descriptor: pd)

        let attrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(nativeSize.width),
            kCVPixelBufferHeightKey as String: Int(nativeSize.height),
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any]()
        ]
        var created: CVPixelBufferPool?
        CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, attrs as CFDictionary, &created)
        pool = created
    }
}
#endif
