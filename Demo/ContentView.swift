//
//  ContentView.swift
//  ReelKitDemo
//
//  Created by Nazar Kozak on 05.06.2026.
//

import SwiftUI
import ReelKit

struct ContentView: View {
    @State private var perf = ReelPerformanceMonitor()
    @State private var recorder: ReelRecorder?
    @State private var isRecording = false
    @State private var savedURL: URL?
    @State private var spin = false

    var body: some View {
        ZStack {
            animatedBackground
                .ignoresSafeArea()

            VStack {
                PerformanceOverlay(perf: perf, isRecording: isRecording)
                    .padding(.top, 8)
                Spacer()
                if let savedURL {
                    Text("Saved: \(savedURL.lastPathComponent)")
                        .font(.caption).foregroundStyle(.white.opacity(0.8))
                }
                recordButton
                    .padding(.bottom, 24)
            }
        }
        .onAppear {
            perf.start()
            spin = true
        }
    }

    // Busy animated content so CPU/FPS actually move.
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

    private var recordButton: some View {
        Button {
            Task { await toggleRecording() }
        } label: {
            Image(systemName: isRecording ? "stop.circle.fill" : "record.circle")
                .font(.system(size: 68))
                .foregroundStyle(isRecording ? .red : .white)
                .shadow(radius: 6)
        }
        .accessibilityLabel(isRecording ? "Stop recording" : "Start recording")
    }

    @MainActor
    private func toggleRecording() async {
        if isRecording {
            guard let recorder else { return }
            isRecording = false
            savedURL = try? await recorder.stop()
            self.recorder = nil
        } else {
            guard let window = keyWindow else { return }
            // No-permission screen capture: records this app's own view hierarchy.
            let source = UIViewFrameSource(window, scale: 2.0, fps: 30)
            let recorder = ReelRecorder(source: source, audio: .microphone)
            self.recorder = recorder
            do {
                try await recorder.start()
                isRecording = true
            } catch {
                self.recorder = nil
            }
        }
    }

    private var keyWindow: UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
    }
}

#Preview {
    ContentView()
}
