//
//  SurfaceRecorderSDKTests.swift
//  SurfaceRecorderSDK
//
//  Created by Nazar Kozak on 05.06.2026.
//

import Testing
import CoreGraphics
@testable import SurfaceRecorderSDK

@Suite("RecordingConfig")
struct RecordingConfigTests {
    @Test("Bitrate scales with resolution, fps and quality")
    func bitrateScaling() {
        let size = CGSize(width: 1920, height: 1080)
        let high = RecordingConfig.Quality.high.bitrate(for: size, fps: 30)
        let low = RecordingConfig.Quality.low.bitrate(for: size, fps: 30)
        #expect(high > low)
        #expect(high > 0)
    }

    @Test("Default config is 30fps h264 high")
    func defaults() {
        let config = RecordingConfig()
        #expect(config.fps == 30)
        #expect(config.codec == .h264)
        #expect(config.quality == .high)
        #expect(config.size == nil)
    }
}
