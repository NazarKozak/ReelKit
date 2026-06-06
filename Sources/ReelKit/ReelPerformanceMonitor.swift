//
//  ReelPerformanceMonitor.swift
//  ReelKit
//
//  Created by Nazar Kozak on 05.06.2026.
//
//  Lightweight live FPS / CPU / memory probe so apps (and the demo) can SEE the
//  recording overhead in real time — proof that the capture path is cheap.
//

#if os(iOS)
import QuartzCore
import Darwin

/// Observable, main-actor live performance readout.
///
/// ```swift
/// @State private var perf = ReelPerformanceMonitor()
/// // ...
/// .onAppear { perf.start() }
/// Text(perf.summary)
/// ```
@MainActor
@Observable
public final class ReelPerformanceMonitor {
    /// Rendered frames per second (rolling, updated ~1×/sec).
    public private(set) var fps: Double = 0
    /// Process CPU load as a fraction of a single core (1.0 == one full core; can exceed 1.0).
    public private(set) var cpu: Double = 0
    /// Resident memory footprint in megabytes.
    public private(set) var memoryMB: Double = 0

    private var proxy: DisplayLinkProxy?
    private var frameCount = 0
    private var windowStart: CFTimeInterval = 0

    public init() {}

    public var summary: String {
        String(format: "%.0f fps · %.0f%% cpu · %.0f MB", fps, cpu * 100, memoryMB)
    }

    public func start() {
        guard proxy == nil else { return }
        windowStart = CACurrentMediaTime()
        frameCount = 0
        proxy = DisplayLinkProxy { [weak self] now in
            self?.tick(now)
        }
    }

    public func stop() {
        proxy?.invalidate()
        proxy = nil
    }

    private func tick(_ now: CFTimeInterval) {
        frameCount += 1
        let elapsed = now - windowStart
        guard elapsed >= 1.0 else { return }
        fps = Double(frameCount) / elapsed
        cpu = Self.cpuUsage()
        memoryMB = Self.memoryFootprintMB()
        frameCount = 0
        windowStart = now
    }

    // MARK: - Sampling (mach)

    /// Sum of per-thread CPU usage for this process, as a fraction of one core.
    static func cpuUsage() -> Double {
        var threads: thread_act_array_t?
        var count: mach_msg_type_number_t = 0
        guard task_threads(mach_task_self_, &threads, &count) == KERN_SUCCESS, let threads else { return 0 }
        defer {
            vm_deallocate(mach_task_self_,
                          vm_address_t(UInt(bitPattern: threads)),
                          vm_size_t(Int(count) * MemoryLayout<thread_t>.stride))
        }
        var total = 0.0
        for i in 0..<Int(count) {
            var info = thread_basic_info()
            // THREAD_BASIC_INFO_COUNT macro is unavailable in the iOS SDK; derive it.
            var infoCount = mach_msg_type_number_t(
                MemoryLayout<thread_basic_info>.size / MemoryLayout<natural_t>.size
            )
            let kr = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: integer_t.self, capacity: Int(infoCount)) {
                    thread_info(threads[i], thread_flavor_t(THREAD_BASIC_INFO), $0, &infoCount)
                }
            }
            if kr == KERN_SUCCESS, (info.flags & TH_FLAGS_IDLE) == 0 {
                total += Double(info.cpu_usage) / Double(TH_USAGE_SCALE)
            }
        }
        return total
    }

    /// Resident footprint in MB via `task_vm_info.phys_footprint`.
    static func memoryFootprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return 0 }
        return Double(info.phys_footprint) / (1024 * 1024)
    }
}

/// Minimal `NSObject` wrapper so the `@Observable` monitor can drive a `CADisplayLink`.
private final class DisplayLinkProxy: NSObject {
    private var link: CADisplayLink?
    private let onTick: (CFTimeInterval) -> Void

    init(onTick: @escaping (CFTimeInterval) -> Void) {
        self.onTick = onTick
        super.init()
        let link = CADisplayLink(target: self, selector: #selector(step))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    @objc private func step(_ link: CADisplayLink) {
        onTick(link.timestamp)
    }

    func invalidate() {
        link?.invalidate()
        link = nil
    }
}
#endif
