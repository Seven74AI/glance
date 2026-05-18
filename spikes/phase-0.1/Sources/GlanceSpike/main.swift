// GlanceSpike — Main CLI
// Technical spike: validate ScreenCaptureKit → Metal → JPEG pipeline.
//
// Usage: glance-spike [--fps 1|5|10] [--duration 10|30|60] [--quality 0.75|0.80|0.85]
//
// Measurements:
//   1. Frame delivery latency at configurable fps
//   2. Metal preprocessing time (scale+convert)
//   3. JPEG encode time at various quality levels
//   4. JPEG output size
//   5. Frame drop rate
//   6. End-to-end pipeline latency

import Foundation
import CoreVideo
import Metal

// MARK: - Entry Point

@main
struct GlanceSpikeCLI {
    
    static func main() async {
        print("""
        
        ╔══════════════════════════════════════════════════════════════════╗
        ║  Glance Phase 0.1 — SCK Pipeline Validation Spike               ║
        ║  ScreenCaptureKit → Metal → JPEG pipeline                       ║
        ╚══════════════════════════════════════════════════════════════════╝
        
        """)
        
        // Parse arguments
        let args = CommandLine.arguments
        let fps = parseIntArg(args, flag: "--fps", default: 10)
        let duration = parseIntArg(args, flag: "--duration", default: 60)
        let qualities: [CGFloat] = parseQualitiesArg(args, flag: "--qualities", default: [0.75, 0.80, 0.85])
        
        print("Configuration:")
        print("  FPS:       \(fps)")
        print("  Duration:  \(duration)s")
        print("  Qualities: \(qualities.map { String(format: "%.0f", $0 * 100) }.joined(separator: ", "))")
        print("  Target:    1080p downscale\n")
        
        // Initialize pipeline components
        print("Initializing Metal preprocessor...")
        let preprocessor: MetalPreprocessor
        do {
            preprocessor = try MetalPreprocessor().require()
        } catch {
            print("❌ Metal init failed: \(error.localizedDescription)")
            print("   This spike requires a Metal-capable GPU (Apple Silicon or Intel Mac with Metal support).")
            exit(1)
        }
        print("  GPU: \(MTLCreateSystemDefaultDevice()?.name ?? "unknown")\n")
        
        // Run pipeline at each quality level
        let metrics = PerformanceMetrics()
        
        var allResults: [CGFloat: [PipelineResult]] = [:]
        
        for quality in qualities {
            print("--- Testing at JPEG quality \(Int(quality * 100))% ---")
            
            let encoder = JPEGEncoder(quality: quality)
            let config = CaptureEngine.CaptureConfig(
                fps: fps,
                captureDisplay: true,
                durationSeconds: duration
            )
            
            let capture = CaptureEngine(config: config, metrics: metrics)
            
            let frameQueue = DispatchQueue(label: "com.glance.spike.frameQueue")
            var results: [PipelineResult] = []
            
            // Set up frame handler
            capture.onFrame = { frame in
                frameQueue.async {
                    // Stage 2: Metal preprocessing
                    let metalToken = metrics.startTiming(stage: "metal_preproc")
                    let preprocessResult: MetalPreprocessor.PreprocessResult
                    do {
                        preprocessResult = try preprocessor.preprocess(pixelBuffer: frame.pixelBuffer)
                    } catch {
                        print("  ⚠️  Metal preproc failed on frame \(frame.frameIndex): \(error)")
                        return
                    }
                    metalToken.stop()
                    
                    // Stage 3: JPEG encoding
                    let jpegToken = metrics.startTiming(stage: "jpeg_encode")
                    let encodeResult: JPEGEncoder.EncodeResult
                    do {
                        encodeResult = try encoder.encode(texture: preprocessResult.outputTexture)
                    } catch {
                        print("  ⚠️  JPEG encode failed on frame \(frame.frameIndex): \(error)")
                        return
                    }
                    jpegToken.stop()
                    
                    let result = PipelineResult(
                        frameIndex: frame.frameIndex,
                        captureTimeMs: frame.captureTimeMs,
                        metalTimeMs: preprocessResult.gpuTimeMs,
                        jpegTimeMs: encodeResult.encodeTimeMs,
                        jpegSizeBytes: encodeResult.sizeBytes,
                        outputWidth: encodeResult.width,
                        outputHeight: encodeResult.height,
                        quality: quality
                    )
                    
                    metrics.recordFrame(PerformanceMetrics.FrameMetrics(
                        frameIndex: frame.frameIndex,
                        stages: [
                            PerformanceMetrics.StageTiming(stage: "capture", durationMs: frame.captureTimeMs, timestamp: Date()),
                            PerformanceMetrics.StageTiming(stage: "metal_preproc", durationMs: preprocessResult.gpuTimeMs, timestamp: Date()),
                            PerformanceMetrics.StageTiming(stage: "jpeg_encode", durationMs: encodeResult.encodeTimeMs, timestamp: Date()),
                        ]
                    ))
                    
                    results.append(result)
                    
                    // Progress indicator
                    if frame.frameIndex % 10 == 0 {
                        let totalMs = frame.captureTimeMs + preprocessResult.gpuTimeMs + encodeResult.encodeTimeMs
                        print(String(format: "  Frame %4d | capture: %5.1fms | metal: %5.1fms | jpeg: %5.1fms | total: %5.1fms | size: %6d bytes",
                                    frame.frameIndex, frame.captureTimeMs, preprocessResult.gpuTimeMs,
                                    encodeResult.encodeTimeMs, totalMs, encodeResult.sizeBytes))
                    }
                }
            }
            
            // Wait for capture to finish
            await withCheckedContinuation { continuation in
                capture.onComplete = {
                    continuation.resume()
                }
                Task {
                    do {
                        try await capture.startCapture()
                    } catch {
                        print("  ❌ Capture failed: \(error.localizedDescription)")
                        continuation.resume()
                    }
                }
            }
            
            // Drain the frame queue
            frameQueue.sync {}
            
            allResults[quality] = results
        }
        
        // Print summary
        metrics.printSummary()
        
        // Print JPEG size stats per quality
        print(String(repeating: "=", count: 72))
        print("  JPEG SIZE BY QUALITY LEVEL")
        print(String(repeating: "=", count: 72))
        print(String(format: "\n  %-12s %10s %10s %10s %10s\n", "QUALITY", "AVG(KB)", "MIN(KB)", "MAX(KB)", "P95(KB)"))
        for quality in qualities {
            guard let results = allResults[quality], !results.isEmpty else { continue }
            let sizes = results.map { Double($0.jpegSizeBytes) / 1024.0 }.sorted()
            let avg = sizes.reduce(0, +) / Double(sizes.count)
            print(String(format: "  %3.0f%%         %8.1f %8.1f %8.1f %8.1f",
                        quality * 100, avg, sizes.first!, sizes.last!, sizes[Int(Double(sizes.count) * 0.95)]))
        }
        
        // Go / No-Go recommendation
        print("\n" + String(repeating: "=", count: 72))
        print("  GO / NO-GO RECOMMENDATION")
        print(String(repeating: "=", count: 72))
        
        let (frames, stageData) = metrics.rawData()
        let e2eAvg = frames.map { $0.totalMs }.reduce(0, +) / Double(max(1, frames.count))
        let captureValues = stageData["capture"] ?? []
        let dropRate = captureValues.isEmpty ? 0 : max(0, 1.0 - Double(captureValues.count) / Double(fps * duration)) * 100
        
        let passE2E = e2eAvg < 50.0
        let passDrops = dropRate < 5.0
        let passSize = allResults.values.flatMap { $0 }.allSatisfy { $0.jpegSizeBytes < 500_000 }
        
        if passE2E && passDrops && passSize {
            print("\n  🟢 GO — All success criteria met. Proceed to Phase 1.\n")
        } else {
            print("\n  🟡 CONDITIONAL GO — Some criteria near threshold.\n")
            if !passE2E { print("     ⚠️  E2E latency: \(String(format: "%.1f", e2eAvg))ms (target: <50ms)") }
            if !passDrops { print("     ⚠️  Drop rate: \(String(format: "%.1f", dropRate))% (target: <5%)") }
            if !passSize { print("     ⚠️  JPEG size exceeds 500KB target for some frames") }
            print("\n  Mitigations:")
            print("     - Lower source resolution (capture at 1440p instead of 4K)")
            print("     - Increase SCStream queue depth to 8")
            print("     - Use VideoToolbox JPEG encoder for hardware acceleration")
        }
        
        print()
    }
}

// MARK: - Data Types

struct PipelineResult {
    let frameIndex: Int
    let captureTimeMs: Double
    let metalTimeMs: Double
    let jpegTimeMs: Double
    let jpegSizeBytes: Int
    let outputWidth: Int
    let outputHeight: Int
    let quality: CGFloat
    
    var totalMs: Double { captureTimeMs + metalTimeMs + jpegTimeMs }
}

// MARK: - CLI Helpers

func parseIntArg(_ args: [String], flag: String, default: Int) -> Int {
    if let idx = args.firstIndex(of: flag), idx + 1 < args.count {
        return Int(args[idx + 1]) ?? `default`
    }
    return `default`
}

func parseQualitiesArg(_ args: [String], flag: String, default: [CGFloat]) -> [CGFloat] {
    if let idx = args.firstIndex(of: flag), idx + 1 < args.count {
        return args[idx + 1].split(separator: ",").compactMap {
            let val = Double($0) ?? 0
            return val > 0 && val <= 1.0 ? CGFloat(val) : nil
        }
    }
    return `default`
}

// Error to optional bridge
extension Optional {
    func require() throws -> Wrapped {
        guard let value = self else {
            throw NSError(domain: "GlanceSpike", code: 1,
                         userInfo: [NSLocalizedDescriptionKey: "Unexpected nil"])
        }
        return value
    }
}
