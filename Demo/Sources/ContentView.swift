//
//  ContentView.swift
//  SurfaceRecorderSDKDemo
//
//  Created by Nazar Kozak on 05.06.2026.
//

import SwiftUI
import SurfaceRecorderSDK
import ARKit
import RealityKit

struct ContentView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case screen = "Screen"
        case arkit = "ARKit"
        case camera = "Camera"
        var id: String { rawValue }
    }

    enum FPSOption: String, CaseIterable, Identifiable {
        case fps30 = "30"
        case fps60 = "60"
        case max = "Max"
        var id: String { rawValue }
        /// CADisplayLink preferred frame rate (0 = device max).
        var displayLink: Int { self == .max ? 0 : Int(rawValue) ?? 30 }
        /// Camera frame cap (nil = device default).
        var camera: Int? { self == .max ? nil : Int(rawValue) }
    }

    @State private var mode: Mode = .screen
    @State private var fps: FPSOption = .fps30
    @State private var audioEnabled = false
    @State private var arIncludeUI = false
    @State private var perf = SurfacePerformanceMonitor()
    @State private var recorder: SurfaceRecorder?
    @State private var isRecording = false
    @State private var savedURL: URL?
    @State private var arView: ARView?
    @State private var cameraSource: CameraFrameSource?
    @State private var arOverlaySource: ARViewFrameSource?
    @State private var recordStart = Date()
    @State private var showGallery = false
    @State private var spin = false

    // Drives GPU overlay refreshes (the HUD changes slowly, so a few times/sec is plenty).
    private let overlayTick = Timer.publish(every: 0.2, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            content.ignoresSafeArea()

            VStack(spacing: 12) {
                PerformanceOverlay(perf: perf, isRecording: isRecording)
                    .padding(.top, 8)

                Picker("Mode", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .disabled(isRecording)

                Spacer()
                controls.padding(.bottom, 24)
            }
        }
        .tint(.white)
        .onAppear { perf.start(); spin = true }
        .onChange(of: mode) { oldMode, newMode in
            teardown(oldMode)
            setup(newMode)
        }
        .onChange(of: fps) { _, _ in
            if mode == .camera { teardown(.camera); setup(.camera) }
        }
        .onReceive(overlayTick) { _ in updateOverlayIfNeeded() }
        .sheet(isPresented: $showGallery) { GalleryView() }
    }

    @ViewBuilder
    private var content: some View {
        switch mode {
        case .screen:
            animatedBackground
        case .arkit:
            ARViewContainer(arView: $arView)
        case .camera:
            if let cameraSource {
                CameraPreview(session: cameraSource.session)
            } else {
                Color.black
            }
        }
    }

    private var controls: some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                Picker("FPS", selection: $fps) {
                    ForEach(FPSOption.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 180)
                .disabled(isRecording)

                Toggle(isOn: $audioEnabled) {
                    Image(systemName: audioEnabled ? "mic.fill" : "mic.slash.fill")
                }
                .toggleStyle(.button)
                .tint(.white)
                .disabled(isRecording)

                if mode == .arkit {
                    Toggle(isOn: $arIncludeUI) {
                        Label("UI", systemImage: "square.stack.3d.up.fill")
                    }
                    .toggleStyle(.button)
                    .tint(.white)
                    .disabled(isRecording)
                }
            }

            HStack(spacing: 28) {
                Button { showGallery = true } label: {
                    Image(systemName: "photo.stack.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.white)
                        .shadow(radius: 6)
                }
                .accessibilityLabel("Open gallery")
                .disabled(isRecording)

                Button { Task { await toggleRecording() } } label: {
                    Image(systemName: isRecording ? "stop.circle.fill" : "record.circle")
                        .font(.system(size: 64))
                        .foregroundStyle(isRecording ? .red : .white)
                        .shadow(radius: 6)
                }
                .accessibilityLabel(isRecording ? "Stop recording" : "Start recording")

                if let savedURL, !isRecording {
                    ShareLink(item: savedURL) {
                        Image(systemName: "square.and.arrow.up.circle.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(.white)
                            .shadow(radius: 6)
                    }
                    .accessibilityLabel("Share recording")
                }
            }
        }
    }

    // MARK: - Mode lifecycle (release the camera before the next mode grabs it)

    @MainActor
    private func teardown(_ oldMode: Mode) {
        switch oldMode {
        case .arkit:
            arView?.renderCallbacks.postProcess = nil
            arView?.session.pause()
            arView = nil
        case .camera:
            cameraSource?.stopRunning()
            cameraSource = nil
        case .screen:
            break
        }
    }

    @MainActor
    private func setup(_ newMode: Mode) {
        guard newMode == .camera else { return }
        let source = CameraFrameSource(position: .back, fps: fps.camera)
        source.startRunning()
        cameraSource = source
    }

    // MARK: - Recording

    @MainActor
    private func toggleRecording() async {
        if isRecording {
            guard let recorder else { return }
            isRecording = false
            arOverlaySource?.setOverlay(nil)
            arOverlaySource = nil
            if let tmp = try? await recorder.stop() {
                savedURL = RecordingStore.save(tmp)
            }
            self.recorder = nil
            return
        }

        guard let source = makeSource() else { return }
        let recorder = SurfaceRecorder(source: source, audio: audioEnabled ? .microphone : .none)
        self.recorder = recorder
        do {
            savedURL = nil
            recordStart = Date()
            try await recorder.start()
            isRecording = true
        } catch {
            self.recorder = nil
        }
    }

    /// Renders the HUD to a CGImage and hands it to the AR source for GPU compositing.
    @MainActor
    private func updateOverlayIfNeeded() {
        guard isRecording, mode == .arkit, arIncludeUI, let arOverlaySource else { return }
        let size = UIScreen.main.bounds.size
        let renderer = ImageRenderer(content: OverlayHUD(elapsed: Date().timeIntervalSince(recordStart), size: size))
        renderer.scale = UIScreen.main.scale
        renderer.isOpaque = false
        arOverlaySource.setOverlay(renderer.cgImage)
    }

    @MainActor
    private func makeSource() -> (any FrameSource)? {
        switch mode {
        case .screen:
            guard let window = keyWindow else { return nil }
            return UIViewFrameSource(window, fps: fps.displayLink, maxDimension: 1080)
        case .arkit:
            // GPU path: camera + RealityKit 3D via postProcess. When "+ UI" is on we
            // also composite a HUD overlay on the GPU (no drawHierarchy) — see
            // updateOverlayIfNeeded(). Either way it runs at the AR session frame rate.
            guard let arView else { return nil }
            let source = ARViewFrameSource(arView)
            arOverlaySource = source
            return source
        case .camera:
            return cameraSource
        }
    }

    private var keyWindow: UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
    }

    // MARK: - Animated screen content (so CPU/FPS actually move)

    private var animatedBackground: some View {
        LinearGradient(colors: [.purple, .blue, .teal], startPoint: .topLeading, endPoint: .bottomTrailing)
            .overlay {
                ForEach(0..<12, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(.white.opacity(0.25), lineWidth: 2)
                        .frame(width: 60 + CGFloat(i) * 22, height: 60 + CGFloat(i) * 22)
                        .rotationEffect(.degrees(spin ? 360 : 0))
                        .animation(.linear(duration: Double(i + 4)).repeatForever(autoreverses: false), value: spin)
                }
            }
    }
}

/// The HUD that gets GPU-composited onto AR recordings (rendered to a CGImage).
private struct OverlayHUD: View {
    let elapsed: TimeInterval
    let size: CGSize

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            HStack(spacing: 8) {
                Image(systemName: "record.circle.fill").foregroundStyle(.red)
                Text("REC \(timeString)")
                    .font(.system(.headline, design: .monospaced).weight(.bold))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(.black.opacity(0.45), in: Capsule())
            .padding(.top, 60).padding(.leading, 20)
        }
        .frame(width: size.width, height: size.height)
    }

    private var timeString: String {
        let total = Int(elapsed)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

#Preview {
    ContentView()
}
