import XCTest
import Metal
import CoreVideo

/// Performance benchmarks for the Metal preprocessing pipeline.
///
/// Produces a benchmark report that can be compared against the targets
/// defined in RESEARCH.md section 2.2:
///   - Metal preprocessing: < 5ms for 4K→1080p
///   - JPEG encode: < 5ms at quality 80
///   - Total preproc → JPEG: < 15ms

@available(macOS 14.0, *)
final class PerformanceBenchmark: XCTestCase {

    var processor: FrameProcessor!
    var device: MTLDevice!
    let iterations = 20  // statistically meaningful sample

    override func setUp() {
        super.setUp()
        device = MTLCreateSystemDefaultDevice()
        guard let device else {
            XCTFail("Metal device required — run on Apple Silicon Mac")
            return
        }
        processor = FrameProcessor(device: device)
    }

    // MARK: - Comprehensive Benchmark

    func test_benchmark_fullPipeline_allResolutions() throws {
        let resolutions: [(String, Int, Int)] = [
            ("4K",    3840, 2160),
            ("1440p", 2560, 1440),
            ("1080p", 1920, 1080),
            ("720p",  1280, 720),
        ]
        let targetSizes: [(String, Int, Int)] = [
            ("→1080p", 1920, 1080),
            ("→1024",  1024, 768),
            ("→768",   768,  576),
        ]
        let qualities: [Float] = [75.0, 80.0, 85.0]

        var report = "\n========== Glance FrameProcessor Benchmark ==========\n"
        report += "Device: \(device.name)\n"
        report += "Iterations per measurement: \(iterations)\n"
        report += "========================================================\n\n"

        for (srcName, srcW, srcH) in resolutions {
            let source = TestHelpers.createTestBuffer(width: srcW, height: srcH)

            for (tgtName, tgtW, tgtH) in targetSizes {
                let targetSize = CGSize(width: tgtW, height: tgtH)

                for quality in qualities {
                    // Warm-up
                    _ = try processor.process(frame: source, targetSize: targetSize, quality: quality)

                    // Measure
                    var preprocTimes: [Double] = []
                    var encodeTimes: [Double] = []
                    var totalTimes: [Double] = []

                    for _ in 0..<iterations {
                        let result = try processor.process(
                            frame: source,
                            targetSize: targetSize,
                            quality: quality
                        )
                        preprocTimes.append(result.preprocessTimeMs)
                        encodeTimes.append(result.encodeTimeMs)
                        totalTimes.append(result.totalTimeMs)
                    }

                    let pMedian = median(preprocTimes)
                    let eMedian = median(encodeTimes)
                    let tMedian = median(totalTimes)

                    let pMin = preprocTimes.min()!
                    let pMax = preprocTimes.max()!
                    let eMin = encodeTimes.min()!
                    let eMax = encodeTimes.max()!
                    let tMin = totalTimes.min()!
                    let tMax = totalTimes.max()!

                    report += "\(srcName) \(tgtName) Q=\(Int(quality)):\n"
                    report += String(format: "  Preproc: median=%5.1fms  min=%5.1fms  max=%5.1fms\n", pMedian, pMin, pMax)
                    report += String(format: "  Encode:  median=%5.1fms  min=%5.1fms  max=%5.1fms\n", eMedian, eMin, eMax)
                    report += String(format: "  Total:   median=%5.1fms  min=%5.1fms  max=%5.1fms\n", tMedian, tMin, tMax)

                    // Performance assertions
                    if srcW >= 3840 && tgtW >= 1920 {
                        // 4K→1080p: < 5ms preprocess, < 5ms encode, < 15ms total
                        if pMedian >= 5.0 || eMedian >= 5.0 || tMedian >= 15.0 {
                            report += "  ⚠️  PERFORMANCE TARGET MISSED\n"
                        } else {
                            report += "  ✅ Performance target met\n"
                        }
                    }
                    report += "\n"
                }
            }
        }

        report += "========================================================\n"

        // Print report to stdout so it's captured in test logs
        print(report)

        // Also assert key performance targets
        let source4K = TestHelpers.create4KTestBuffer()
        let target1080p = CGSize(width: 1920, height: 1080)

        _ = try processor.process(frame: source4K, targetSize: target1080p, quality: 80.0)

        var totalTimes4Kto1080p: [Double] = []
        for _ in 0..<iterations {
            let r = try processor.process(frame: source4K, targetSize: target1080p, quality: 80.0)
            totalTimes4Kto1080p.append(r.totalTimeMs)
        }
        let medianTotal = median(totalTimes4Kto1080p)
        XCTAssertLessThan(medianTotal, 15.0,
                          "4K→1080p end-to-end must be under 15ms")
    }

    // MARK: - Stress Tests

    func test_benchmark_sustainedThroughput_1000frames() throws {
        // Verify no memory leaks or performance degradation over many frames
        let source = TestHelpers.createTestBuffer(width: 1920, height: 1080)
        let targetSize = CGSize(width: 1024, height: 768)
        let quality: Float = 80.0

        // Warm-up
        _ = try processor.process(frame: source, targetSize: targetSize, quality: quality)

        let batchSize = 100
        var batchMedians: [Double] = []

        for batch in 0..<10 {
            var times: [Double] = []
            for _ in 0..<batchSize {
                let result = try processor.process(
                    frame: source, targetSize: targetSize, quality: quality
                )
                times.append(result.totalTimeMs)
            }
            let m = median(times)
            batchMedians.append(m)

            if batch > 0 {
                // No more than 3x degradation from first batch median
                XCTAssertLessThan(
                    m, batchMedians[0] * 3.0,
                    "Batch \(batch): performance should not degrade >3x over 1000 frames"
                )
            }
        }

        print("Sustained throughput: batch medians: \(batchMedians.map { String(format: "%.1f", $0) }.joined(separator: ", "))ms")
    }

    // MARK: - Helpers

    private func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        let count = sorted.count
        if count % 2 == 0 {
            return (sorted[count / 2 - 1] + sorted[count / 2]) / 2.0
        } else {
            return sorted[count / 2]
        }
    }
}
