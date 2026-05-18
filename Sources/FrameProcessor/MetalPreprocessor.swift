import Metal
import CoreVideo

// MARK: - Errors

/// Errors thrown by MetalPreprocessor.
enum MetalPreprocessorError: Error, Equatable {
    case invalidTargetSize
    case pipelineCreationFailed(String)
    case commandBufferFailed
}

// MARK: - Filter Mode

/// Quality/speed trade-off for downscale filtering.
enum PreprocessFilterMode {
    /// Hardware bilinear — fastest, good quality. ~1-2ms for 4K→1080p.
    case bilinear
    /// Nearest neighbor — fastest possible. Slightly lower quality.
    case nearest
    /// Lanczos-3 — highest quality (sharp text). ~4-8ms for 4K→1080p.
    case lanczos3
}

// MARK: - MetalPreprocessor

/// GPU-accelerated frame preprocessing using Metal compute shaders.
///
/// Performs BGRA→RGBA color swizzle + downscale in a single compute pass.
/// Input: MTLTexture from IOSurface-backed CVPixelBuffer (BGRA8Unorm)
/// Output: MTLTexture (RGBA8Unorm) at target resolution
///
/// Performance target: < 5ms for 4K→1080p on M1+ (using bilinear filter).
@available(macOS 14.0, *)
final class MetalPreprocessor {

    // MARK: - Properties

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let bilinearPipeline: MTLComputePipelineState
    private let nearestPipeline: MTLComputePipelineState?
    private let lanczosPipeline: MTLComputePipelineState?

    /// Default filter mode.
    var filterMode: PreprocessFilterMode = .bilinear

    // MARK: - Initialization

    /// Creates a MetalPreprocessor using the system default Metal device.
    convenience init() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal is not available on this device")
        }
        self.init(device: device)
    }

    /// Creates a MetalPreprocessor with a specific Metal device.
    init(device: MTLDevice) {
        self.device = device

        guard let queue = device.makeCommandQueue() else {
            fatalError("Failed to create Metal command queue")
        }
        self.commandQueue = queue

        // Load Metal library — tries default library first (Xcode),
        // falls back to compiling from bundled source (SPM).
        let library: MTLLibrary
        if let defaultLib = device.makeDefaultLibrary() {
            library = defaultLib
        } else if let bundledLib = MetalPreprocessor.loadLibraryFromBundle(device: device) {
            library = bundledLib
        } else {
            fatalError("""
                Failed to load Metal library.
                Ensure PreprocessShader.metal is included in the target's resources
                (SPM: .process("PreprocessShader.metal")) or compile sources (Xcode).
                """)
        }

        // Compile compute pipelines
        do {
            self.bilinearPipeline = try MetalPreprocessor.compilePipeline(
                device: device,
                library: library,
                functionName: "preprocess_bgra_to_rgba_bilinear"
            )
        } catch {
            fatalError("Failed to compile bilinear pipeline: \(error)")
        }

        self.nearestPipeline = try? MetalPreprocessor.compilePipeline(
            device: device,
            library: library,
            functionName: "preprocess_bgra_to_rgba_nearest"
        )

        self.lanczosPipeline = try? MetalPreprocessor.compilePipeline(
            device: device,
            library: library,
            functionName: "preprocess_bgra_to_rgba_lanczos3"
        )
    }

    // MARK: - Public API

    /// Preprocesses a source texture: BGRA→RGBA swizzle + downscale to target size.
    ///
    /// - Parameters:
    ///   - source: Input MTLTexture in BGRA8Unorm format (from CVPixelBuffer)
    ///   - targetSize: Desired output dimensions. Must be positive.
    ///                 Aspect ratio is preserved; output fits within targetSize.
    /// - Returns: Output MTLTexture in RGBA8Unorm format at computed dimensions.
    /// - Throws: `MetalPreprocessorError` on invalid parameters or GPU errors.
    func preprocess(source: MTLTexture, targetSize: CGSize) throws -> MTLTexture {
        // Validate input
        guard targetSize.width > 0, targetSize.height > 0 else {
            throw MetalPreprocessorError.invalidTargetSize
        }

        // Compute output dimensions preserving aspect ratio
        let (outWidth, outHeight) = MetalPreprocessor.computeOutputSize(
            sourceWidth: source.width,
            sourceHeight: source.height,
            targetWidth: Int(targetSize.width),
            targetHeight: Int(targetSize.height)
        )

        // Select pipeline
        let pipeline: MTLComputePipelineState
        switch filterMode {
        case .bilinear:
            pipeline = bilinearPipeline
        case .nearest:
            guard let np = nearestPipeline else {
                throw MetalPreprocessorError.pipelineCreationFailed("Nearest pipeline not available")
            }
            pipeline = np
        case .lanczos3:
            guard let lp = lanczosPipeline else {
                throw MetalPreprocessorError.pipelineCreationFailed("Lanczos pipeline not available")
            }
            pipeline = lp
        }

        // Create output texture
        let outputDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: outWidth,
            height: outHeight,
            mipmapped: false
        )
        outputDescriptor.usage = [.shaderWrite, .shaderRead]
        outputDescriptor.storageMode = .shared  // CPU-readable for JPEG encode

        guard let outputTexture = device.makeTexture(descriptor: outputDescriptor) else {
            throw MetalPreprocessorError.pipelineCreationFailed("Failed to create output texture")
        }

        // Compute scale factor (source pixels per output pixel)
        let scaleX = Float(source.width) / Float(outWidth)
        let scaleY = Float(source.height) / Float(outHeight)
        var scaleFactor = SIMD2<Float>(scaleX, scaleY)

        // Dispatch compute kernel
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else {
            throw MetalPreprocessorError.commandBufferFailed
        }

        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(source, index: 0)
        encoder.setTexture(outputTexture, index: 1)
        encoder.setBytes(&scaleFactor, length: MemoryLayout<SIMD2<Float>>.size, index: 0)

        // Compute thread group size
        let threadGroupSize = MTLSize(width: 16, height: 16, depth: 1)
        let threadGroups = MTLSize(
            width: (outWidth + 15) / 16,
            height: (outHeight + 15) / 16,
            depth: 1
        )

        encoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupSize)
        encoder.endEncoding()

        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        if let error = commandBuffer.error {
            throw MetalPreprocessorError.pipelineCreationFailed(
                "GPU error: \(error.localizedDescription)"
            )
        }

        return outputTexture
    }

    // MARK: - Private Helpers

    /// Compiles a Metal library from the bundled PreprocessShader.metal source file.
    /// Used as a fallback when makeDefaultLibrary() is unavailable (e.g. SPM builds).
    private static func loadLibraryFromBundle(device: MTLDevice) -> MTLLibrary? {
        // Locate the shader source in the module bundle
        guard let shaderURL = Bundle.module.url(
            forResource: "PreprocessShader",
            withExtension: "metal"
        ) else {
            return nil
        }

        guard let source = try? String(contentsOf: shaderURL, encoding: .utf8) else {
            return nil
        }

        let compileOptions = MTLCompileOptions()
        compileOptions.languageVersion = .version3_1

        return try? device.makeLibrary(source: source, options: compileOptions)
    }

    /// Compiles a compute pipeline from a named Metal function.
    private static func compilePipeline(
        device: MTLDevice,
        library: MTLLibrary,
        functionName: String
    ) throws -> MTLComputePipelineState {
        guard let function = library.makeFunction(name: functionName) else {
            throw MetalPreprocessorError.pipelineCreationFailed(
                "Function '\(functionName)' not found in Metal library"
            )
        }
        return try device.makeComputePipelineState(function: function)
    }

    /// Computes output dimensions preserving aspect ratio (fit within bounds).
    /// Never upscales — if source is smaller than target, output matches source.
    static func computeOutputSize(
        sourceWidth: Int,
        sourceHeight: Int,
        targetWidth: Int,
        targetHeight: Int
    ) -> (width: Int, height: Int) {
        // Don't upscale
        if sourceWidth <= targetWidth && sourceHeight <= targetHeight {
            return (sourceWidth, sourceHeight)
        }

        let srcRatio = Float(sourceWidth) / Float(sourceHeight)
        let tgtRatio = Float(targetWidth) / Float(targetHeight)

        let outWidth: Int
        let outHeight: Int

        if srcRatio > tgtRatio {
            // Source is wider — constrained by width
            outWidth = targetWidth
            outHeight = max(1, Int(Float(targetWidth) / srcRatio))
        } else {
            // Source is taller — constrained by height
            outHeight = targetHeight
            outWidth = max(1, Int(Float(targetHeight) * srcRatio))
        }

        return (outWidth, outHeight)
    }
}
