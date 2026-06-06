# ReelKit

**Record your ARKit / RealityKit session — and any view — to video, with audio, without ReplayKit's permission prompt.**

A modern, Swift-concurrency-native successor to ARVideoKit, built for the RealityKit era. One recorder, swappable sources, audio that actually syncs.

> _(GIF placeholder: AR recording with a live FPS/CPU HUD overlay)_

```swift
import ReelKit

let recorder = ReelRecorder(
    source: RealityKitFrameSource(arView),   // or UIViewFrameSource(window), ARSCNViewFrameSource(...)
    audio: .microphone
)

try await recorder.start()
// ... user does stuff ...
let url = try await recorder.stop()          // MP4 in tmp, ready to share/save
```

## Why ReelKit

| | ReplayKit | ARVideoKit | **ReelKit** |
|---|:---:|:---:|:---:|
| No permission prompt (in-app capture) | ❌ | ✅ | ✅ |
| RealityKit `ARView` | ⚠️ | ❌ | ✅ |
| ARKit `ARSCNView` | ⚠️ | ✅ | ✅ (Phase 2) |
| Plain UIKit/SwiftUI screen capture | ❌ | ❌ | ✅ |
| Audio time-synced to video clock | ✅ | ⚠️ | ✅ |
| Swift 6 / async-native | ❌ | ❌ | ✅ |

## Install

Swift Package Manager:

```swift
.package(url: "https://github.com/NazarKozak/ReelKit.git", from: "0.1.0")
```

…and add `"ReelKit"` to your target's dependencies. Requires iOS 17+.

> Testing against a moving `main` instead of a release? Use
> `.package(url: "https://github.com/NazarKozak/ReelKit.git", branch: "main")`.

## Sources

ReelKit records whatever a `FrameSource` produces — same recorder, same writer:

```swift
// 1. RealityKit ARView camera feed (BGRA, optional 2D overlay) — high fidelity.
ReelRecorder(source: RealityKitFrameSource(arView), audio: .microphone)

// 2. Any UIView / the key window — screen capture, NO ReplayKit prompt.
ReelRecorder(source: UIViewFrameSource(window, scale: 2.0, fps: 30))

// 2b. Record AR camera + RealityKit 3D overlays + SwiftUI HUD, exactly as on
//     screen — capture the ARView's container with afterScreenUpdates: true.
ReelRecorder(source: UIViewFrameSource(arContainerView, afterScreenUpdates: true))

// 3. Bring-your-own frames.
ReelRecorder(source: myCustomFrameSource)
```

### No-permission screen capture

`UIViewFrameSource` renders **your app's own view hierarchy** with `drawHierarchy`, so it
never triggers the system screen-recording prompt. The trade-off vs ReplayKit: it captures
only your app (not other apps / system UI) — which is exactly what an in-app recorder wants.

## Performance

ReelKit is built to be cheap:

- **Single-pass capture** — `UIViewFrameSource` renders straight into the pixel buffer's
  backing `CGContext` (no intermediate `UIImage`/`CGImage` per frame).
- **Recycled buffers** — frames come from a `CVPixelBufferPool`, not fresh allocations.
- **Zero-copy AR** — `RealityKitFrameSource` writes the captured `ARFrame` buffer directly.
- **Serialized, lock-free** — the writer is driven by a single `actor`, no manual locking.

See it live: `ReelPerformanceMonitor` exposes `fps`, `cpu`, and `memoryMB`, and the demo
shows them in an on-screen HUD while recording — so you can watch the overhead in real time.

```swift
@State private var perf = ReelPerformanceMonitor()
// ...
.onAppear { perf.start() }
Text(perf.summary)   // "60 fps · 8% cpu · 124 MB"
```

## Demo

Open **`Demo/ReelKitDemo.xcodeproj`** in Xcode, pick an iOS Simulator (or your device), and run.
It records the screen with a live FPS/CPU/MEM overlay so you can watch the capture overhead.

The project depends on the local package and uses Xcode's file-system-synchronized groups —
drop any `.swift` file into `Demo/Sources/` and it's picked up automatically, no project edits.
(The demo isn't built by `swift build`, which only compiles the library.)

## Roadmap

- [x] RealityKit `ARView` recording (camera → BGRA via GPU converter)
- [x] No-permission `UIView` screen capture (single-pass, pooled buffers)
- [x] AR camera + 3D overlays via `UIViewFrameSource(afterScreenUpdates: true)`
- [x] 2D overlay compositing on the AR camera buffer
- [x] Mic audio with time-sync + `AVAudioSession`/ARKit coexistence
- [x] Live performance monitor
- [ ] Bespoke `ARSCNViewFrameSource` (SCNRenderer) + "migrate from ARVideoKit" guide
- [ ] Automatic interface-orientation rotation for portrait AR
- [ ] Photo / GIF / Live Photo capture
- [ ] visionOS, HEVC, pause/resume

## License

MIT
