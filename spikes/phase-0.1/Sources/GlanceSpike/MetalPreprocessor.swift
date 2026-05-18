// GlanceSpike — Metal Preprocessor
// GPU-accelerated BGRA→RGB conversion + downscale to 1080p via compute shader.

import Metal
import CoreVideo

/// Wraps the Metal preprocessing pipeline: downscale + BGRA→RGB in one pass.
final class MetalPreprocessor {
    
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipeline: MTLComputePipelineState
    
    /// Output dimension constraints.
    struct OutputConfig {
        let maxHeight: Int
        let maintainAspectRatio: Bool
        
        static let default1080p = OutputConfig(maxHeight: 1080, maintainAspectRatio: true)
    }
    
    /// Timing result for a single preprocessing call.
    struct PreprocessResult {
        let outputTexture: MTLTexture
        let outputWidth: Int
        let outputHeight: Int
        let gpuTimeMs: Double
    }
    
    // MARK: - Init
    
    init?() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw MetalError.noGPU
        }
        self.device = device
        
        guard let queue = device.makeCommandQueue() else {
            throw MetalError.noCommandQueue
        }
        self.commandQueue = queue
        
        // Load the default Metal library (bundled shaders)
        guard let library = device.makeDefaultLibrary() else {
            throw MetalError.noShaderLibrary
        }
        
        guard let function = library.makeFunction(name: "bgra_to_rgb_downscale") else {
            throw MetalError.noShaderFunction("bgra_to_rgb_downscale")
        }
        
        self.pipeline = try device.makeComputePipelineState(function: function)
    }
    
    // MARK: - Preprocess
    
    /// Downscale + BGRA→RGB convert a CVPixelBuffer in a single Metal pass.
    /// - Parameters:
    ///   - pixelBuffer: Source BGRA8 CVPixelBuffer (IOSurface-backed from SCK)
    ///   - config: Output constraints
    /// - Returns: PreprocessResult with output texture and timing.
    func preprocess(pixelBuffer: CVPixelBuffer, config: OutputConfig = .default1080p) throws -> PreprocessResult {
        
        let gpuStart = DispatchTime.now()
        
        // Determine output dimensions preserving aspect ratio
        let inputWidth = CVPixelBufferGetWidth(pixelBuffer)
        let inputHeight = CVPixelBufferGetHeight(pixelBuffer)
        
        let outputHeight: Int
        let outputWidth: Int
        if config.maintainAspectRatio && inputHeight > config.maxHeight {
            let scale = Double(config.maxHeight) / Double(inputHeight)
            outputHeight = config.maxHeight
            outputWidth = Int(Double(inputWidth) * scale)
        } else {
            outputHeight = inputHeight
            outputWidth = inputWidth
        }
        
        // Create Metal texture from CVPixelBuffer (zero-copy via IOSurface)
        var cvTexture: CVMetalTexture?
        let result = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            textureCache,
            pixelBuffer,
            nil,
            .bgra8Unorm,
            inputWidth,
            inputHeight,
            0,
            &cvTexture
        )
        
        guard result == kCVReturnSuccess, let cvTex = cvTexture else {
            throw MetalError.textureCreationFailed
        }
        
        guard let inputTexture = CVMetalTextureGetTexture(cvTex) else {
            throw MetalError.textureCreationFailed
        }
        
        // Create output texture (RGBA8Unorm for RGB output)
        let outputDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: outputWidth,
            height: outputHeight,
            mipmapped: false
        )
        outputDesc.usage = [.shaderWrite, .shaderRead]
        outputDesc.storageMode = .shared
        
        guard let outputTexture = device.makeTexture(descriptor: outputDesc) else {
            throw MetalError.textureCreationFailed
        }
        
        // Dispatch compute shader
        guard let cmdBuffer = commandQueue.makeCommandBuffer(),
              let encoder = cmdBuffer.makeComputeCommandEncoder() else {
            throw MetalError.commandBufferFailed
        }
        
        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(inputTexture, index: 0)
        encoder.setTexture(outputTexture, index: 1)
        
        // Thread configuration
        let threadGroupSize = MTLSize(width: 16, height: 16, depth: 1)
        let threadGroups = MTLSize(
            width: (outputWidth + threadGroupSize.width - 1) / threadGroupSize.width,
            height: (outputHeight + threadGroupSize.height - 1) / threadGroupSize.height,
            depth: 1
        )
        
        encoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupSize)
        encoder.endEncoding()
        
        cmdBuffer.commit()
        cmdBuffer.waitUntilCompleted()
        
        let gpuEnd = DispatchTime.now()
        let gpuTimeMs = Double(gpuEnd.uptimeNanoseconds - gpuStart.uptimeNanoseconds) / 1_000_000.0
        
        return PreprocessResult(
            outputTexture: outputTexture,
            outputWidth: outputWidth,
            outputHeight: outputHeight,
            gpuTimeMs: gpuTimeMs
        )
    }
    
    // MARK: - Texture cache
    
    /// Lazily created texture cache for zero-copy CVPixelBuffer → MTLTexture.
    private lazy var textureCache: CVMetalTextureCache = {
        var cache: CVMetalTextureCache?
        CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &cache)
        return cache!
    }()
}

// MARK: - Errors

enum MetalError: LocalizedError {
    case noGPU
    case noCommandQueue
    case noShaderLibrary
    case noShaderFunction(String)
    case textureCreationFailed
    case commandBufferFailed
    
    var errorDescription: String? {
        switch self {
        case .noGPU: return "No Metal-capable GPU found"
        case .noCommandQueue: return "Failed to create Metal command queue"
        case .noShaderLibrary: return "Failed to load default Metal shader library"
        case .noShaderFunction(let name): return "Shader function '\(name)' not found"
        case .textureCreationFailed: return "Failed to create Metal texture from pixel buffer"
        case .commandBufferFailed: return "Failed to create Metal command buffer or encoder"
        }
    }
}
