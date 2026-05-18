import CoreVideo
import Metal
import Foundation

// MARK: - Errors

/// Errors thrown by FrameProcessor.
enum FrameProcessorError: Error, Equatable {
    case invalidTargetSize
    case invalidQuality
    case metalDeviceNotFound
    case textureCreationFailed
    case preprocessingFailed(String)
    case encodingFailed(String)
}

// MARK: - Result

/// Result of frame processing: JPEG data + per-stage timing.
struct FrameProcessorResult {
    /// JPEG-encoded image data ready for AI API upload.
    let jpegData: Data

    /// Metal preprocessing time in milliseconds.
    let preprocessTimeMs: Double

    /// JPEG encoding time in milliseconds.
    let encodeTimeMs: Double

    /// Total wall-clock time in milliseconds (preprocess + encode + overhead).
    let totalTimeMs: Double

    /// Pipeline timing breakdown.
    var timings: PipelineTimings {
        PipelineTimings(
            preprocessMs: preprocessTimeMs,
            encodeMs: encodeTimeMs,
            totalMs: totalTimeMs
        )
    }
}

// MARK: - FrameProcessor

/// GPU-accelerated frame preprocessing pipeline.
///
/// Orchestrates: CVPixelBuffer → Metal (BGRA→RGBA + downscale) → JPEG encode.
/// Output is JPEG data ready for upload to AI vision APIs (Claude, GPT-4V, Gemini).
///
/// Performance targets (M1+):
///   - Metal preprocessing: < 5ms for 4K→1080p
///   - JPEG encoding: < 5ms at quality 80
///   - Total: < 15ms
///
/// ## Usage
/// ```swift
/// let processor = FrameProcessor()
/// let result = try processor.process(
///     frame: pixelBuffer,
///     targetSize: CGSize(width: 1920, height: 1080),
///     quality: 80.0
/// )
/// // result.jpegData — ready for API upload
/// ```
@available(macOS 14.0, *)
final class FrameProcessor {

    // MARK: - Properties

    private let device: MTLDevice
    private let preprocessor: MetalPreprocessor
    private let encoder: JPEGEncoder
    private var textureCache: CVMetalTextureCache?

    // MARK: - Initialization

    /// Creates a FrameProcessor using the system default Metal device.
    convenience init() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal is not available on this device")
        }
        self.init(device: device)
    }

    /// Creates a FrameProcessor with a specific Metal device.
    init(device: MTLDevice) {
        self.device = device
        self.preprocessor = MetalPreprocessor(device: device)
        self.encoder = JPEGEncoder()

        // Create texture cache for zero-copy CVPixelBuffer → MTLTexture
        var cache: CVMetalTextureCache?
        CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &cache)
        self.textureCache = cache
    }

    // MARK: - Public API

    /// Processes a CVPixelBuffer frame: downscale + color convert + JPEG encode.
    ///
    /// - Parameters:
    ///   - frame: Source CVPixelBuffer in BGRA8 format (from ScreenCaptureKit).
    ///   - targetSize: Maximum output dimensions. Aspect ratio preserved.
    ///                 Must have positive width and height.
    ///   - quality: JPEG quality 0.0–100.0.
    ///              Default 80.0; 75–85 recommended for AI vision APIs.
    /// - Returns: `FrameProcessorResult` with JPEG data and timing breakdown.
    /// - Throws: `FrameProcessorError` on invalid parameters or pipeline failures.
    func process(
        frame: CVPixelBuffer,
        targetSize: CGSize,
        quality: Float
    ) throws -> FrameProcessorResult {
        let totalStart = PerformanceTimer()

        // Validate parameters
        guard targetSize.width > 0, targetSize.height > 0 else {
            throw FrameProcessorError.invalidTargetSize
        }
        guard quality >= 0.0 && quality <= 100.0 else {
            throw FrameProcessorError.invalidQuality
        }

        // Step 1: Create Metal texture from CVPixelBuffer (zero-copy via IOSurface)
        guard let sourceTexture = createTexture(from: frame) else {
            throw FrameProcessorError.textureCreationFailed
        }

        // Step 2: Metal preprocessing (BGRA→RGBA + downscale)
        let preprocessTimer = PerformanceTimer()
        let processedTexture: MTLTexture
        do {
            processedTexture = try preprocessor.preprocess(
                source: sourceTexture,
                targetSize: targetSize
            )
        } catch let error as MetalPreprocessorError {
            throw FrameProcessorError.preprocessingFailed("\(error)")
        } catch {
            throw FrameProcessorError.preprocessingFailed("\(error)")
        }
        let preprocessMs = preprocessTimer.elapsedMs

        // Step 3: JPEG encoding
        let encodeTimer = PerformanceTimer()
        let jpegResult: JPEGEncodeResult
        do {
            jpegResult = try encoder.encode(texture: processedTexture, quality: quality)
        } catch let error as JPEGEncoderError {
            throw FrameProcessorError.encodingFailed("\(error)")
        } catch {
            throw FrameProcessorError.encodingFailed("\(error)")
        }
        let encodeMs = encodeTimer.elapsedMs

        // Note: jpegResult.encodeTimeMs is the internal encode measurement;
        // we use our own timer to also capture data marshalling overhead.
        let totalMs = totalStart.elapsedMs

        return FrameProcessorResult(
            jpegData: jpegResult.data,
            preprocessTimeMs: preprocessMs,
            encodeTimeMs: encodeMs,
            totalTimeMs: totalMs
        )
    }

    // MARK: - Filter Mode

    /// Sets the preprocessing filter mode.
    /// - `.bilinear` (default): fastest, good quality
    /// - `.nearest`: slightly faster, lower quality
    /// - `.lanczos3`: highest quality, slower (use for text-heavy content)
    var filterMode: PreprocessFilterMode {
        get { preprocessor.filterMode }
        set { preprocessor.filterMode = newValue }
    }

    // MARK: - Private

    /// Creates a Metal texture from a CVPixelBuffer via texture cache (zero-copy).
    private func createTexture(from pixelBuffer: CVPixelBuffer) -> MTLTexture? {
        guard let cache = textureCache else { return nil }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        var cvTexture: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            cache,
            pixelBuffer,
            nil,
            .bgra8Unorm,
            width, height, 0,
            &cvTexture
        )

        guard status == kCVReturnSuccess, let cvMetalTexture = cvTexture else {
            return nil
        }

        return CVMetalTextureGetTexture(cvMetalTexture)
    }
}
