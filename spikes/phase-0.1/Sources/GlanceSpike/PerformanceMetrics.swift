// GlanceSpike — Performance Metrics
// High-precision timing for pipeline stage latency measurement.

import Foundation

/// Records timing for pipeline stages and reports statistics.
final class PerformanceMetrics {
    
    /// A single measurement for a pipeline stage.
    struct StageTiming {
        let stage: String
        let durationMs: Double
        let timestamp: Date
    }
    
    /// Collected timings for one frame.
    struct FrameMetrics {
        let frameIndex: Int
        let stages: [StageTiming]
        
        var totalMs: Double {
            stages.reduce(0) { $0 + $1.durationMs }
        }
        
        var stageMap: [String: Double] {
            Dictionary(uniqueKeysWithValues: stages.map { ($0.stage, $0.durationMs) })
        }
    }
    
    private var frameMetrics: [FrameMetrics] = []
    private let lock = NSLock()
    
    // Per-stage accumulators for summary stats
    private var stageAccumulators: [String: [Double]] = [:]
    
    /// Start timing a stage. Returns a token; call .stop() to record.
    func startTiming(stage: String) -> TimingToken {
        TimingToken(stage: stage, startTime: DispatchTime.now(), metrics: self)
    }
    
    /// Record a completed timing.
    fileprivate func record(token: TimingToken) {
        let elapsed = token.elapsedMs
        lock.lock()
        stageAccumulators[token.stage, default: []].append(elapsed)
        lock.unlock()
    }
    
    /// Record a full frame's metrics.
    func recordFrame(_ metrics: FrameMetrics) {
        lock.lock()
        frameMetrics.append(metrics)
        for stage in metrics.stages {
            stageAccumulators[stage.stage, default: []].append(stage.durationMs)
        }
        lock.unlock()
    }
    
    /// Print summary statistics for all stages.
    func printSummary() {
        lock.lock()
        defer { lock.unlock() }
        
        guard !frameMetrics.isEmpty else {
            print("\n⚠️  No metrics collected.\n")
            return
        }
        
        let frameCount = frameMetrics.count
        let totalFrames = Double(frameCount)
        
        print("\n" + String(repeating: "=", count: 72))
        print("  PIPELINE PERFORMANCE SUMMARY — \(frameCount) frames")
        print(String(repeating: "=", count: 72))
        
        // Per-stage stats
        print(String(format: "\n  %-30s %8s %8s %8s %8s", "STAGE", "AVG(ms)", "MIN(ms)", "MAX(ms)", "P95(ms)"))
        print(String(repeating: "  -", count: 36))
        
        let orderedStages = ["capture", "metal_preproc", "jpeg_encode"]
        for stageName in orderedStages {
            guard let values = stageAccumulators[stageName], !values.isEmpty else { continue }
            let sorted = values.sorted()
            let avg = sorted.reduce(0, +) / totalFrames
            let min = sorted.first!
            let max = sorted.last!
            let p95Index = Int(Double(sorted.count) * 0.95)
            let p95 = sorted[min(p95Index, sorted.count - 1)]
            
            print(String(format: "  %-30s %8.2f %8.2f %8.2f %8.2f",
                        stageName, avg, min, max, p95))
        }
        
        // End-to-end (sum of all stages per frame)
        let e2eValues = frameMetrics.map { $0.totalMs }.sorted()
        let e2eAvg = e2eValues.reduce(0, +) / totalFrames
        let e2eMin = e2eValues.first!
        let e2eMax = e2eValues.last!
        let e2eP95Idx = Int(Double(e2eValues.count) * 0.95)
        let e2eP95 = e2eValues[min(e2eP95Idx, e2eValues.count - 1)]
        
        print(String(repeating: "  -", count: 36))
        print(String(format: "  %-30s %8.2f %8.2f %8.2f %8.2f",
                    "END-TO-END", e2eAvg, e2eMin, e2eMax, e2eP95))
        
        // Frame drops
        let totalElapsed = e2eValues.last ?? 0
        let expectedFrames = Double(frameCount)
        let actualFps = expectedFrames / (totalElapsed / 1000.0)
        let dropRate = max(0, 1.0 - (actualFps / 10.0)) * 100.0  // vs 10fps target
        
        print("\n  Frame Stats:")
        print(String(format: "    Target FPS:      10.0"))
        print(String(format: "    Achieved FPS:    %.1f", actualFps))
        print(String(format: "    Frame drop rate: %.1f%%", dropRate))
        
        // Pass/fail against success criteria
        print("\n  Success Criteria:")
        let passE2E = e2eAvg < 50.0 ? "✅" : "❌"
        print(String(format: "    %@ E2E latency < 50ms:         %.2f ms avg", passE2E, e2eAvg))
        let passDrops = dropRate < 5.0 ? "✅" : "❌"
        print(String(format: "    %@ Frame drop rate < 5%%:       %.1f%%", passDrops, dropRate))
        
        print()
    }
    
    /// Return raw data for report generation.
    func rawData() -> (frames: [FrameMetrics], stageData: [String: [Double]]) {
        lock.lock()
        defer { lock.unlock() }
        return (frameMetrics, stageAccumulators)
    }
    
    func frameCount() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return frameMetrics.count
    }
}

/// Token returned by startTiming; measures elapsed on stop().
struct TimingToken {
    let stage: String
    let startTime: DispatchTime
    let metrics: PerformanceMetrics
    
    var elapsedMs: Double {
        let end = DispatchTime.now()
        let nanos = end.uptimeNanoseconds - startTime.uptimeNanoseconds
        return Double(nanos) / 1_000_000.0
    }
    
    func stop() {
        metrics.record(token: self)
    }
}
