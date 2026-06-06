//
//  ContentView.swift
//  ReelKitDemo
//
//  Created by Nazar Kozak on 05.06.2026.
//

import SwiftUI
import ReelKit
import RealityKit

struct ContentView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case screen = "Screen"
        case arkit = "ARKit"
        var id: String { rawValue }
    }

    @State private var mode: Mode = .screen
    @State private var audioEnabled = false   // default OFF → no mic permission prompt
    @State private var arIncludeUI = true     // AR: capture camera+3D+UI vs camera-only
    @State private var perf = ReelPerformanceMonitor()
    @State private var recorder: ReelRecorder?
    @State private var isRecording = false
    @State private var savedURL: URL?
    @State private var arView: ARView?
    @State private var spin = false

    var body: some View {
        ZStack {
            content
                .ignoresSafeArea()

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
    }

    @ViewBuilder
    private var content: some View {
        switch mode {
        case .screen: animatedBackground
        case .arkit:  ARViewContainer(arView: $arView)
        }
    }

    private var controls: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                Toggle(isOn: $audioEnabled) {
                    Label("Mic", systemImage: audioEnabled ? "mic.fill" : "mic.slash.fill")
                }
                .toggleStyle(.button)
                .tint(.white)
                .disabled(isRecording)

                if mode == .arkit {
                    Toggle(isOn: $arIncludeUI) {
                        Label("UI & 3D", systemImage: "square.stack.3d.up.fill")
                    }
                    .toggleStyle(.button)
                    .tint(.white)
                    .disabled(isRecording)
                }
            }

            HStack(spacing: 32) {
                Button {
                    Task { await toggleRecording() }
                } label: {
                    Image(systemName: isRecording ? "stop.circle.fill" : "record.circle")
                        .font(.system(size: 64))
                        .foregroundStyle(isRecording ? .red : .white)
                        .shadow(radius: 6)
                }
                .accessibilityLabel(isRecording ? "Stop recording" : "Start recording")

                if let savedURL, !isRecording {
                    ShareLink(item: savedURL) {
                        Image(systemName: "square.and.arrow.up.circle.fill")
                            .font(.system(size: 56))
                            .foregroundStyle(.white)
                            .shadow(radius: 6)
                    }
                    .accessibilityLabel("Share recording")
                }
            }

            if let savedURL, !isRecording {
                Text("Saved \(savedURL.lastPathComponent) — tap share to export")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
    }

    // MARK: - Recording

    @MainActor
    private func toggleRecording() async {
        if isRecording {
            guard let recorder else { return }
            isRecording = false
            savedURL = try? await recorder.stop()
            self.recorder = nil
            return
        }

        guard let source = makeSource() else { return }
        let recorder = ReelRecorder(source: source, audio: audioEnabled ? .microphone : .none)
        self.recorder = recorder
        do {
            savedURL = nil
            try await recorder.start()
            isRecording = true
        } catch {
            self.recorder = nil
        }
    }

    @MainActor
    private func makeSource() -> (any FrameSource)? {
        switch mode {
        case .screen:
            guard let window = keyWindow else { return nil }
            // Cap to 1280 on the long side → much lighter on large screens.
            return UIViewFrameSource(window, fps: 30, maxDimension: 1280)
        case .arkit:
            if arIncludeUI {
                // Capture camera + RealityKit 3D + SwiftUI overlays, as on screen,
                // in the correct device orientation (afterScreenUpdates: true).
                guard let window = keyWindow else { return nil }
                return UIViewFrameSource(window, fps: 30, afterScreenUpdates: true, maxDimension: 1440)
            } else {
                // Clean camera-only path; rotates the landscape sensor buffer to portrait.
                guard let arView else { return nil }
                return RealityKitFrameSource(arView, orientation: .portrait)
            }
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

#Preview {
    ContentView()
}
