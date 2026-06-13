//
//  PerformanceOverlay.swift
//  SurfaceRecorderSDKDemo
//
//  Created by Nazar Kozak on 05.06.2026.
//
//  Live load HUD — proves the capture path is cheap. Reads FPS / CPU / memory
//  straight from SurfaceRecorderSDK's `SurfacePerformanceMonitor`.
//

import SwiftUI
import SurfaceRecorderSDK

struct PerformanceOverlay: View {
    let perf: SurfacePerformanceMonitor
    let isRecording: Bool

    var body: some View {
        HStack(spacing: 14) {
            metric("FPS", String(format: "%.0f", perf.fps), color: fpsColor)
            divider
            metric("CPU", String(format: "%.0f%%", perf.cpu * 100), color: cpuColor)
            divider
            metric("MEM", String(format: "%.0f MB", perf.memoryMB), color: .secondary)
            if isRecording {
                divider
                Label("REC", systemImage: "record.circle.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.red)
                    .labelStyle(.titleAndIcon)
            }
        }
        .font(.system(.caption, design: .monospaced).weight(.semibold))
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Performance: \(perf.summary)")
    }

    private func metric(_ title: String, _ value: String, color: Color) -> some View {
        VStack(spacing: 1) {
            Text(title).font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
            Text(value).foregroundStyle(color)
        }
    }

    private var divider: some View {
        Rectangle().fill(.secondary.opacity(0.3)).frame(width: 1, height: 22)
    }

    private var fpsColor: Color { perf.fps >= 55 ? .green : perf.fps >= 30 ? .yellow : .red }
    private var cpuColor: Color { perf.cpu < 0.5 ? .green : perf.cpu < 1.0 ? .yellow : .red }
}
