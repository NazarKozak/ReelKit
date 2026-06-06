# Changelog

All notable changes to ReelKit are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/); versions follow SemVer.

## [Unreleased]

### Added
- `UIViewFrameSource(maxDimension:)` — caps the longest output side and
  downscales large screens, cutting `drawHierarchy` CPU/encode cost.
- Demo: ARKit recording mode (RealityKit `ARView` via `RealityKitFrameSource`),
  a Share button (`ShareLink`) to export the recording, and a microphone toggle.

### Changed
- Demo records **without microphone by default** (no permission prompt); enable
  audio explicitly via the toggle. The SDK already defaulted to `audio: .none`.

## [0.1.0] - 2026-06-05

Initial public release.

### Added
- `ReelRecorder` — actor-driven recorder that writes a `FrameSource` (plus
  optional audio) to MP4 without ReplayKit.
- `RealityKitFrameSource` — records a RealityKit `ARView` camera feed; converts
  the `ARFrame` YCbCr buffer to BGRA via a GPU-backed `FrameConverter`, with
  optional per-frame 2D overlay compositing.
- `UIViewFrameSource` — no-permission screen/UI capture via single-pass
  `drawHierarchy`; `afterScreenUpdates` flag to capture Metal/AR content.
- `AudioCapture` — microphone capture with `CMSampleBuffer` time-correction to
  the video clock, and `AVAudioSession`/`ARSession` coexistence.
- `VideoWriter` — `AVAssetWriter` pipeline with pooled pixel buffers, bitrate
  derived from resolution/fps/quality.
- `ReelPerformanceMonitor` — live FPS / CPU / memory readout (mach-based).
- Reference SwiftUI demo with an on-screen load HUD.

### Known limitations
- Bespoke `ARSCNViewFrameSource` (SCNRenderer) and full 3D RealityKit overlay
  compositing are not yet shipped — capture AR camera + overlays today via
  `UIViewFrameSource(arView, afterScreenUpdates: true)`. Tracked for 0.2.0.
- Camera-buffer orientation handling for portrait AR is configurable via output
  size; automatic interface-orientation rotation is pending on-device tuning.
