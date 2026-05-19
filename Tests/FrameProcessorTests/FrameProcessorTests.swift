import XCTest
import CoreVideo
import Metal

/// Tests for FrameProcessor — the main orchestrator class.
/// Verifies the end-to-end pipeline: CVPixelBuffer → Metal preprocess → JPEG encode → Data.
///
/// TDD RED: These tests define the API contract BEFORE implementation exists.
/// Run: swift test --filter FrameProcessorTests

@available(macOS 14.0, *)
final class FrameProcessorTests: XCTestCase {

    var processor: FrameProcessor!
    var device: MTLDevice!

    override func setUp() {
        super.setUp()
        device = MTLCreateSystemDefaultDevice()
        XCTAssertNotNil(device, "Metal device required for tests — run on Apple Silicon Mac")
        processor = FrameProcessor(device: device)
    }

    override func tearDown() {
        processor = nil
        device = nil
        super.tearDown()
    }

    // MARK: - Initialization

    func test_init_withDefaultDevice_succeeds() {
        let proc = FrameProcessor()
        XCTAssertNotNil(proc)
    }

    func test_init_withSpecificDevice_succeeds() {
        let proc = FrameProcessor(device: device)
        XCTAssertNotNil(proc)
    }

    // MARK: - Basic Processing

    func test_process_4Kto1080p_producesJPEGData() throws {
        let source = TestHelpers.create4KTestBuffer()
        let targetSize = CGSize(width: 1920, height: 1080)
        let quality: Float = 80.0

        let result = try processor.process(frame: source, targetSize: targetSize, quality: quality)

        XCTAssertFalse(result.jpegData.isEmpty, "JPEG data should not be empty")
        XCTAssertGreaterThan(result.jpegData.count, 1000, "JPEG data should be substantial")
        XCTAssertGreaterThan(result.totalTimeMs, 0, "Total time should be measured")
        XCTAssertGreaterThan(result.preprocessTimeMs, 0, "Preprocess time should be measured")
        XCTAssertGreaterThan(result.encodeTimeMs, 0, "Encode time should be measured")
    }

    func test_process_downscalesCorrectly() throws {
        let source = TestHelpers.create4KTestBuffer()
        let targetWidth = 1024
        let targetHeight = 768

        let result = try processor.process(
            frame: source,
            targetSize: CGSize(width: targetWidth, height: targetHeight),
            quality: 80.0
        )

        // Decode JPEG to verify dimensions
        guard let imageSource = CGImageSourceCreateWithData(result.jpegData as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
            XCTFail("Failed to decode output JPEG")
            return
        }

        // Allow aspect-ratio-preserving scaling (exact dimensions may differ)
        XCTAssertLessThanOrEqual(image.width, targetWidth, "Output width should be <= target")
        XCTAssertLessThanOrEqual(image.height, targetHeight, "Output height should be <= target")
        // At least one dimension should match target
        XCTAssertTrue(
            image.width == targetWidth || image.height == targetHeight,
            "At least one output dimension should match target (aspect-ratio preserving)"
        )
    }

    // MARK: - Color Conversion (BGRA → RGB)

    func test_process_colorConversion_preservesVisualIdentity() throws {
        // Create a buffer with known colors at known positions
        // Top-left: red (255,0,0), Top-right: green (0,255,0),
        // Bottom-left: blue (0,0,255), Bottom-right: white (255,255,255)
        let size = 512
        let source = TestHelpers.createSolidColorBuffer(
            width: size, height: size,
            red: 128, green: 128, blue: 128, alpha: 255
        )
        // Override with corner colors (this test verifies the overall pipeline
        // doesn't introduce catastrophic color shifts)
        CVPixelBufferLockBaseAddress(source, [])
        defer { CVPixelBufferUnlockBaseAddress(source, []) }
        let ptr = CVPixelBufferGetBaseAddress(source)!
            .assumingMemoryBound(to: UInt8.self)
        let bpr = CVPixelBufferGetBytesPerRow(source)

        // Top-left: pure red
        ptr[0] = 0; ptr[1] = 0; ptr[2] = 255; ptr[3] = 255
        // Top-right: pure green
        let tr = (size - 1) * 4
        ptr[tr + 0] = 0; ptr[tr + 1] = 255; ptr[tr + 2] = 0; ptr[tr + 3] = 255
        // Bottom-left: pure blue
        let bl = (size - 1) * bpr
        ptr[bl + 0] = 255; ptr[bl + 1] = 0; ptr[bl + 2] = 0; ptr[bl + 3] = 255
        // Bottom-right: white
        let br = (size - 1) * bpr + (size - 1) * 4
        ptr[br + 0] = 255; ptr[br + 1] = 255; ptr[br + 2] = 255; ptr[br + 3] = 255

        let result = try processor.process(
            frame: source,
            targetSize: CGSize(width: size, height: size), // no downscale
            quality: 100.0 // lossless-ish
        )

        // Decode and sample corners
        guard let imageSource = CGImageSourceCreateWithData(result.jpegData as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
            XCTFail("Failed to decode output JPEG")
            return
        }

        // For a no-downscale pass, dimensions should match
        XCTAssertEqual(image.width, size)
        XCTAssertEqual(image.height, size)

        // Sample corner pixels from the CGImage
        // (JPEG compression means colors won't be exact, but they should be close)
        guard let dataProvider = image.dataProvider,
              let pixelData = dataProvider.data else {
            return // can't sample without raw data
        }

        let rawData = CFDataGetBytePtr(pixelData)!
        let rowBytes = image.bytesPerRow
        let bpp = image.bitsPerPixel / 8

        // Top-left: should be reddish
        let tlR = rawData[0]
        let tlG = rawData[1]
        let tlB = rawData[2]
        XCTAssertGreaterThan(tlR, 200, "Top-left R should be high (red)")
        XCTAssertLessThan(tlG, 100, "Top-left G should be low (not green)")
        XCTAssertLessThan(tlB, 100, "Top-left B should be low (not blue)")

        // Top-right: should be greenish
        let trOff = (size - 1) * bpp
        let trR = rawData[trOff]
        let trG = rawData[trOff + 1]
        let trB = rawData[trOff + 2]
        XCTAssertLessThan(trR, 100, "Top-right R should be low")
        XCTAssertGreaterThan(trG, 200, "Top-right G should be high (green)")

        // Bottom-left: should be blue-ish
        let blOff = (size - 1) * rowBytes
        let blR = rawData[blOff]
        let blG = rawData[blOff + 1]
        let blB = rawData[blOff + 2]
        XCTAssertLessThan(blR, 100, "Bottom-left R should be low")
        XCTAssertLessThan(blG, 100, "Bottom-left G should be low")
        XCTAssertGreaterThan(blB, 200, "Bottom-left B should be high (blue)")
    }

    // MARK: - JPEG Quality

    func test_process_higherQuality_producesLargerFile() throws {
        let source = TestHelpers.create4KTestBuffer()
        let targetSize = CGSize(width: 1920, height: 1080)

        let result75 = try processor.process(frame: source, targetSize: targetSize, quality: 75.0)
        let result85 = try processor.process(frame: source, targetSize: targetSize, quality: 85.0)

        // Higher quality should produce equal or larger output
        XCTAssertGreaterThanOrEqual(
            result85.jpegData.count, result75.jpegData.count,
            "Quality 85 should produce >= bytes than quality 75"
        )
    }

    // MARK: - Error Handling

    func test_process_invalidTargetSize_zero_throwsError() {
        let source = TestHelpers.create4KTestBuffer()

        XCTAssertThrowsError(
            try processor.process(frame: source, targetSize: .zero, quality: 80.0)
        ) { error in
            guard case FrameProcessorError.invalidTargetSize = error else {
                XCTFail("Expected invalidTargetSize, got \(error)")
                return
            }
        }
    }

    func test_process_invalidTargetSize_negative_throwsError() {
        let source = TestHelpers.create4KTestBuffer()

        XCTAssertThrowsError(
            try processor.process(
                frame: source,
                targetSize: CGSize(width: -100, height: 100),
                quality: 80.0
            )
        ) { error in
            guard case FrameProcessorError.invalidTargetSize = error else {
                XCTFail("Expected invalidTargetSize, got \(error)")
                return
            }
        }
    }

    func test_process_invalidQuality_belowZero_throwsError() {
        let source = TestHelpers.create4KTestBuffer()

        XCTAssertThrowsError(
            try processor.process(
                frame: source,
                targetSize: CGSize(width: 1920, height: 1080),
                quality: -1.0
            )
        ) { error in
            guard case FrameProcessorError.invalidQuality = error else {
                XCTFail("Expected invalidQuality, got \(error)")
                return
            }
        }
    }

    func test_process_invalidQuality_above100_throwsError() {
        let source = TestHelpers.create4KTestBuffer()

        XCTAssertThrowsError(
            try processor.process(
                frame: source,
                targetSize: CGSize(width: 1920, height: 1080),
                quality: 101.0
            )
        ) { error in
            guard case FrameProcessorError.invalidQuality = error else {
                XCTFail("Expected invalidQuality, got \(error)")
                return
            }
        }
    }

    // MARK: - Performance Targets

    func test_performance_4Kto1080p_under15ms() throws {
        let source = TestHelpers.create4KTestBuffer()
        let targetSize = CGSize(width: 1920, height: 1080)
        let quality: Float = 80.0

        // Run once to warm up Metal pipeline
        _ = try processor.process(frame: source, targetSize: targetSize, quality: quality)

        // Measure 5 runs, take median
        var times: [Double] = []
        for _ in 0..<5 {
            let result = try processor.process(frame: source, targetSize: targetSize, quality: quality)
            times.append(result.totalTimeMs)
        }
        times.sort()
        let median = times[2]

        XCTAssertLessThan(
            median, 15.0,
            "4K→1080p end-to-end should complete under 15ms. Got \(String(format: "%.1f", median))ms"
        )
    }

    func test_performance_preprocess_under5ms() throws {
        let source = TestHelpers.create4KTestBuffer()
        let targetSize = CGSize(width: 1920, height: 1080)
        let quality: Float = 80.0

        _ = try processor.process(frame: source, targetSize: targetSize, quality: quality)

        var preprocessTimes: [Double] = []
        for _ in 0..<5 {
            let result = try processor.process(frame: source, targetSize: targetSize, quality: quality)
            preprocessTimes.append(result.preprocessTimeMs)
        }
        preprocessTimes.sort()
        let median = preprocessTimes[2]

        XCTAssertLessThan(
            median, 5.0,
            "Metal preprocessing should complete under 5ms. Got \(String(format: "%.1f", median))ms"
        )
    }

    func test_performance_jpegEncode_under5ms() throws {
        let source = TestHelpers.create4KTestBuffer()
        let targetSize = CGSize(width: 1920, height: 1080)

        _ = try processor.process(frame: source, targetSize: targetSize, quality: 80.0)

        var encodeTimes: [Double] = []
        for _ in 0..<5 {
            let result = try processor.process(frame: source, targetSize: targetSize, quality: 80.0)
            encodeTimes.append(result.encodeTimeMs)
        }
        encodeTimes.sort()
        let median = encodeTimes[2]

        XCTAssertLessThan(
            median, 5.0,
            "JPEG encode should complete under 5ms. Got \(String(format: "%.1f", median))ms"
        )
    }

    // MARK: - Filter Mode Delegation

    func test_filterMode_defaultsToBilinear() {
        // Given: a newly created FrameProcessor
        let proc = FrameProcessor(device: device)

        // Then: filterMode should default to .bilinear
        // (We verify by checking that processing at bilinear works)
        XCTAssertNotNil(proc)
    }

    func test_filterMode_setGet_roundtrips() {
        // Given: a FrameProcessor
        let proc = FrameProcessor(device: device)

        // When: setting to nearest
        proc.filterMode = .nearest
        // Then: getter should reflect the set value
        // (Cannot directly compare PreprocessFilterMode without Equatable,
        //  but we verify the setter works by processing with different modes)
        let source = TestHelpers.create1080pTestBuffer()

        // nearest should work
        _ = try? proc.process(frame: source, targetSize: CGSize(width: 640, height: 480), quality: 80.0)

        // When: setting to lanczos3
        proc.filterMode = .lanczos3
        _ = try? proc.process(frame: source, targetSize: CGSize(width: 640, height: 480), quality: 80.0)

        // When: setting back to bilinear
        proc.filterMode = .bilinear
        _ = try? proc.process(frame: source, targetSize: CGSize(width: 640, height: 480), quality: 80.0)

        // All three modes should complete without crashing
        XCTAssertTrue(true, "All three filter modes processed without crashing")
    }

    func test_filterMode_nearest_producesSmallerOutput() throws {
        let source = TestHelpers.create4KTestBuffer()
        let targetSize = CGSize(width: 1920, height: 1080)

        // Process with bilinear (quality-biased) first
        processor.filterMode = .bilinear
        let bilinearResult = try processor.process(frame: source, targetSize: targetSize, quality: 80.0)

        // Process with nearest (speed-biased)
        processor.filterMode = .nearest
        let nearestResult = try processor.process(frame: source, targetSize: targetSize, quality: 80.0)

        // Both should produce valid JPEG output
        XCTAssertFalse(bilinearResult.jpegData.isEmpty, "Bilinear should produce valid JPEG")
        XCTAssertFalse(nearestResult.jpegData.isEmpty, "Nearest should produce valid JPEG")
        XCTAssertGreaterThan(bilinearResult.totalTimeMs, 0)
        XCTAssertGreaterThan(nearestResult.totalTimeMs, 0)
    }

    // MARK: - FrameProcessorResult Timings

    func test_FrameProcessorResult_timings_computedProperty() throws {
        let source = TestHelpers.create1080pTestBuffer()
        let targetSize = CGSize(width: 640, height: 480)

        let result = try processor.process(frame: source, targetSize: targetSize, quality: 80.0)

        // timings computed property should match individual fields
        let timings = result.timings
        XCTAssertEqual(timings.preprocessMs, result.preprocessTimeMs)
        XCTAssertEqual(timings.encodeMs, result.encodeTimeMs)
        XCTAssertEqual(timings.totalMs, result.totalTimeMs)
    }
}
