# ReelKit

**Record anything on iOS to video — an AR scene, the camera, or any view — with synced audio, without ReplayKit's permission prompt.**

ReelKit is a small, Swift-concurrency-native recording SDK. You give it a *source* (RealityKit AR, the device camera, or a UIKit/SwiftUI view) and it writes an MP4 — frames recycled from a pool, audio time-synced to the video clock, the whole pipeline driven by a single `actor`.

> _(GIF placeholder: recording an AR scene with a live FPS / CPU / MEM HUD)_

```swift
import ReelKit

let recorder = ReelRecorder(
    source: ARViewFrameSource(arView),   // or CameraFrameSource(), UIViewFrameSource(window), …
    audio: .microphone                   // or .none (default — no permission prompt)
)

try await recorder.start()
// … user does stuff …
let url = try await recorder.stop()      // MP4 in the temp dir, ready to share or save
```

## Features

- 🎥 **Four sources, one recorder** — AR (camera + 3D), AR camera-only, the device camera, or any view.
- 🚫 **No ReplayKit prompt** — in-app capture of your own content; nothing to authorize.
- ⚡ **GPU-fast AR** — `ARViewFrameSource` taps `postProcess` and never touches the CPU rasterizer.
- 🎙 **Audio that lines up** — microphone capture with `CMSampleBuffer` time-correction and `AVAudioSession`/`ARSession` coexistence. **Off by default** — no mic prompt unless you ask.
- 📐 **Resolution cap** — downscale large screens to keep capture cheap.
- 📊 **Live perf readout** — `ReelPerformanceMonitor` (FPS / CPU / memory) you can show on screen.
- 🧱 **Swift 6, async-native** — actors, `AsyncSequence`, strict concurrency.

## Install

Swift Package Manager:

```swift
.package(url: "https://github.com/NazarKozak/ReelKit.git", from: "0.1.0")
```

…and add `"ReelKit"` to your target's dependencies. Requires **iOS 17+**.

> Tracking the latest instead of a release? Use `branch: "main"`.

## Sources

Everything records through a `FrameSource`. Pick the one that matches what you want on tape:

| Source | Captures | How | Cost |
|---|---|---|:---:|
| **`ARViewFrameSource`** | RealityKit AR: **camera + 3D content** | `ARView.renderCallbacks.postProcess` → Metal blit | 🟢 GPU |
| **`RealityKitFrameSource`** | AR **camera feed only** (no 3D/UI) | zero-copy `ARFrame` buffer, GPU rotate/convert | 🟢 GPU |
| **`CameraFrameSource`** | a plain **device camera** (back/front), with preview | `AVCaptureSession` video output | 🟢 GPU |
| **`UIViewFrameSource`** | **any UIView / the whole screen** (UIKit + SwiftUI) | single-pass `drawHierarchy`, pooled buffers | 🟡 CPU |

```swift
// AR scene — camera + 3D, recommended for ARKit/RealityKit.
ReelRecorder(source: ARViewFrameSource(arView), audio: .microphone)

// AR camera feed only (clean), with rotation control.
ReelRecorder(source: RealityKitFrameSource(arView, orientation: .portrait))

// The device camera (like a camera app). Expose `.session` to show a preview.
let camera = CameraFrameSource(position: .back, fps: 60)
camera.startRunning()                       // drives the preview
ReelRecorder(source: camera)

// Any view or the key window — screen capture, NO ReplayKit prompt.
ReelRecorder(source: UIViewFrameSource(window, maxDimension: 1080))
```

### No-permission screen capture

`UIViewFrameSource` renders **your app's own view hierarchy** with `drawHierarchy`, so it never
triggers the system screen-recording prompt. Trade-off vs ReplayKit: it captures only your app
(not other apps or system UI) — exactly what an in-app recorder wants.

`drawHierarchy` runs on the main thread and its cost scales with output pixels, so use
`maxDimension:` to cap resolution on large screens. To also capture Metal-backed content
(an `ARView`) in the same pass, pass `afterScreenUpdates: true` (heavier).

## Audio

Audio is opt-in — the recorder defaults to `.none`, so nothing prompts the user:

```swift
ReelRecorder(source: …, audio: .microphone)   // mic, time-synced to the video clock
ReelRecorder(source: …, audio: .none)          // silent (default)
```

The microphone path manages `AVAudioSession` (interruptions, route changes) and re-times each
sample buffer to the video session clock, so audio and video stay in lockstep even alongside ARKit.

## Output & sharing

`stop()` returns the MP4 `URL` in the temp directory. Move it where you like, or hand it straight
to a `ShareLink`:

```swift
let url = try await recorder.stop()
ShareLink(item: url)                // AirDrop / Save Video / Files
```

## Performance

ReelKit is built to be cheap:

- **GPU AR path** — `ARViewFrameSource` blits the composited render texture into a pixel buffer; no CPU rasterization.
- **Zero-copy AR camera** — `RealityKitFrameSource` hands the `ARFrame` buffer straight to a GPU convert/rotate.
- **Single-pass UI capture** — `UIViewFrameSource` renders into the pixel buffer's backing `CGContext`, no intermediate `UIImage`.
- **Recycled buffers** — every source pulls from a `CVPixelBufferPool`.
- **Serialized, lock-free** — one `actor` owns the writer; no manual locking.

Watch it live with `ReelPerformanceMonitor`:

```swift
@State private var perf = ReelPerformanceMonitor()
// …
.onAppear { perf.start() }
Text(perf.summary)   // "60 fps · 8% cpu · 124 MB"
```

## Demo

Open **`Demo/ReelKitDemo.xcodeproj`** in Xcode, pick a simulator or your device, and run. The demo has:

- three tabs — **Screen**, **ARKit**, **Camera**;
- an **FPS selector** (30 / 60 / Max) and a microphone toggle;
- a **gallery** that saves recordings to Documents and plays them back;
- a live **FPS / CPU / MEM** overlay.

> AR and camera capture need a real device (the simulator has no camera).

The project depends on the local package and uses Xcode's file-system-synchronized groups —
drop a `.swift` file into `Demo/Sources/` and it's picked up automatically. (`swift build` only
compiles the library, not the iOS demo.)

## Why ReelKit

| | ReplayKit | ARVideoKit | **ReelKit** |
|---|:---:|:---:|:---:|
| No permission prompt (in-app capture) | ❌ | ✅ | ✅ |
| RealityKit `ARView` (camera + 3D) | ⚠️ | ❌ | ✅ |
| Plain device camera + preview | — | — | ✅ |
| Any UIKit/SwiftUI view / screen | ❌ | ❌ | ✅ |
| Audio time-synced to the video clock | ✅ | ⚠️ | ✅ |
| Swift 6 / async-native | ❌ | ❌ | ✅ |
| Maintained for the RealityKit era | ✅ | ⚠️ | ✅ |

## Requirements

- iOS 17+
- Swift 6 / Xcode 16+
- For AR/camera capture: a real device. Add `NSCameraUsageDescription` (and
  `NSMicrophoneUsageDescription` if you record audio) to your Info.plist.

## Roadmap

- [x] GPU AR recording — camera + 3D (`ARViewFrameSource`)
- [x] AR camera-only, zero-copy with orientation control (`RealityKitFrameSource`)
- [x] Device camera with preview (`CameraFrameSource`)
- [x] No-permission screen/UI capture, single-pass + resolution cap (`UIViewFrameSource`)
- [x] Mic audio with time-sync + `AVAudioSession`/ARKit coexistence
- [x] Live performance monitor
- [x] GPU overlay compositing — UI/HUD over AR at full frame rate (`ARViewFrameSource.setOverlay`)
- [ ] GPU overlay for `CameraFrameSource` too
- [ ] `ARSCNViewFrameSource` (SceneKit) + "migrate from ARVideoKit" guide
- [ ] Photo / GIF / Live Photo capture
- [ ] visionOS, HEVC, pause/resume

## License

MIT — see [LICENSE](LICENSE).
