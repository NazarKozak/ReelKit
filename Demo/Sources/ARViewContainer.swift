//
//  ARViewContainer.swift
//  SurfaceRecorderSDKDemo
//
//  Created by Nazar Kozak on 05.06.2026.
//
//  A minimal RealityKit ARView with a floating box, exposed back to the demo so
//  it can be recorded via SurfaceRecorderSDK's RealityKitFrameSource. AR runs on device
//  only — the simulator shows an empty view.
//

import SwiftUI
import ARKit
import RealityKit

struct ARViewContainer: UIViewRepresentable {
    @Binding var arView: ARView?

    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero)

        #if !targetEnvironment(simulator)
        let config = ARWorldTrackingConfiguration()
        view.session.run(config)
        #endif

        // A spinning cyan box half a meter in front of the camera.
        let anchor = AnchorEntity(world: [0, 0, -0.5])
        let box = ModelEntity(
            mesh: .generateBox(size: 0.12, cornerRadius: 0.012),
            materials: [SimpleMaterial(color: .cyan, roughness: 0.2, isMetallic: true)]
        )
        anchor.addChild(box)
        view.scene.addAnchor(anchor)

        DispatchQueue.main.async { arView = view }
        return view
    }

    func updateUIView(_ uiView: ARView, context: Context) {}

    // Release the camera/session when SwiftUI removes the view, so the next mode
    // (e.g. the plain camera) can grab the camera without conflicting.
    static func dismantleUIView(_ uiView: ARView, coordinator: Void) {
        uiView.renderCallbacks.postProcess = nil
        uiView.session.pause()
    }
}
