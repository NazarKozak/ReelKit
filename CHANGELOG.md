# Changelog

All notable changes to ReelKit are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/); versions follow SemVer.

## [Unreleased]

### Added
- `ARViewFrameSource` — high-performance AR recording via
  `ARView.renderCallbacks.postProcess`: grabs the composited camera + RealityKit
  texture on the GPU and blits it into a pixel buffer through a Metal render pass
  (no `drawHierarchy`, no CPU rasterization). Captured already in view orientation.
- `UIViewFrameSource(maxDimension:)` — caps the longest output side and
  downscales large screens, cutting `drawHierarchy` CPU/encode cost.
- `RealityKitFrameSource(orientation:)` + `VideoOrientation` — rotates the
  always-landscape ARKit camera buffer to the correct device orientation
  (defaults to `.portrait`).
- Demo: ARKit recording mode, a Share button (`ShareLink`) to export the
  recording, a microphone toggle, and an "UI & 3D" toggle that records
  camera + RealityKit content + overlays (screen composite) vs camera-only.

### Fixed
- AR recordings were always written in the sensor's landscape orientation
  regardless of how the device was held — now rotated per `orientation`.

### Changed
- Demo records **without microphone by default** (no permission prompt); enable
  audio explicitly via the toggle. The SDK already defaulted to `audio: .none`.
- To capture an AR scene **with** the 3D content and UI, use
  `UIViewFrameSource(window, afterScreenUpdates: true)`; `RealityKitFrameSource`
  records the camera feed only.

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
