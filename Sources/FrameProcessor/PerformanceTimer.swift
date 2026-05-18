import Foundation

// MARK: - PerformanceTimer

/// High-resolution wall-clock timer for measuring pipeline stage latency.
///
/// Uses `CFAbsoluteTimeGetCurrent()` which has microsecond precision on macOS.
/// All times are in milliseconds.
@available(macOS 14.0, *)
struct PerformanceTimer {

    // MARK: - Properties

    /// The start timestamp.
    private let start: CFAbsoluteTime

    // MARK: - Initialization

    /// Starts a new timer.
    init() {
        self.start = CFAbsoluteTimeGetCurrent()
    }

    // MARK: - Reading

    /// Elapsed time since timer creation, in milliseconds.
    var elapsedMs: Double {
        return (CFAbsoluteTimeGetCurrent() - start) * 1000.0
    }

    /// Elapsed time in seconds.
    var elapsedSeconds: Double {
        return CFAbsoluteTimeGetCurrent() - start
    }

    // MARK: - Static Helpers

    /// Measures the wall-clock time of a synchronous block in milliseconds.
    static func measureMs(_ block: () -> Void) -> Double {
        let t = PerformanceTimer()
        block()
        return t.elapsedMs
    }

    /// Measures the wall-clock time of a throwing block in milliseconds.
    /// Rethrows any error from the block.
    static func measureMsThrowing(_ block: () throws -> Void) rethrows -> Double {
        let t = PerformanceTimer()
        try block()
        return t.elapsedMs
    }

    /// Returns a formatted string with milliseconds: "X.Xms"
    static func format(_ ms: Double) -> String {
        return String(format: "%.1fms", ms)
    }

    /// Lazily creates, times, and returns a result tuple.
    /// Useful for inline timing in pipelines.
    static func timed<T>(_ label: String, _ block: () throws -> T) rethrows -> (value: T, ms: Double) {
        let t = PerformanceTimer()
        let value = try block()
        return (value, t.elapsedMs)
    }
}

// MARK: - PipelineTimings

/// Aggregated timing measurements for the full preprocessing pipeline.
struct PipelineTimings {
    let preprocessMs: Double
    let encodeMs: Double
    let totalMs: Double

    /// Total pipeline time in milliseconds.
    var total: Double { totalMs }

    /// Preprocessing percentage of total time.
    var preprocessPercent: Double {
        guard totalMs > 0 else { return 0 }
        return (preprocessMs / totalMs) * 100.0
    }

    /// Encoding percentage of total time.
    var encodePercent: Double {
        guard totalMs > 0 else { return 0 }
        return (encodeMs / totalMs) * 100.0
    }
}
