import XCTest
import CoreVideo
import CoreGraphics
import ImageIO
import Metal

/// Helpers for creating test fixtures (CVPixelBuffer, MTLTexture, etc.)
enum TestHelpers {

    // MARK: - CVPixelBuffer Fixtures

    /// Creates a synthetic 4K (3840×2160) BGRA8 CVPixelBuffer with a colored gradient pattern.
    /// Useful for verifying downscale + color conversion correctness.
    static func create4KTestBuffer() -> CVPixelBuffer {
        return createTestBuffer(width: 3840, height: 2160)
    }

    /// Creates a 1080p (1920×1080) BGRA8 CVPixelBuffer.
    static func create1080pTestBuffer() -> CVPixelBuffer {
        return createTestBuffer(width: 1920, height: 1080)
    }

    /// Creates a known-pattern BGRA8 CVPixelBuffer at any size.
    /// Pattern: horizontal gradient (R increases left→right, G increases top→bottom, B=128 constant)
    /// This makes visual verification of swizzle+scale straightforward.
    static func createTestBuffer(width: Int, height: Int) -> CVPixelBuffer {
        var pixelBuffer: CVPixelBuffer?
        let attrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferBytesPerRowAlignmentKey as String: 64,
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:],
        ]

        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width, height,
            kCVPixelFormatType_32BGRA,
            attrs as CFDictionary,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            fatalError("Failed to create CVPixelBuffer: \(status)")
        }

        // Fill with known pattern
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(buffer) else {
            fatalError("CVPixelBuffer has no base address")
        }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        let ptr = baseAddress.assumingMemoryBound(to: UInt8.self)

        for y in 0..<height {
            for x in 0..<width {
                let offset = y * bytesPerRow + x * 4
                // BGRA order
                ptr[offset + 0] = UInt8((x * 255) / max(width - 1, 1))   // B — horizontal ramp
                ptr[offset + 1] = UInt8((y * 255) / max(height - 1, 1))  // G — vertical ramp
                ptr[offset + 2] = 128                                      // R — constant
                ptr[offset + 3] = 255                                      // A — opaque
            }
        }

        return buffer
    }

    /// Creates a solid-color BGRA8 CVPixelBuffer for simple correctness checks.
    static func createSolidColorBuffer(
        width: Int,
        height: Int,
        red: UInt8,
        green: UInt8,
        blue: UInt8,
        alpha: UInt8 = 255
    ) -> CVPixelBuffer {
        var pixelBuffer: CVPixelBuffer?
        let attrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferBytesPerRowAlignmentKey as String: 64,
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:],
        ]

        CVPixelBufferCreate(
            kCFAllocatorDefault,
            width, height,
            kCVPixelFormatType_32BGRA,
            attrs as CFDictionary,
            &pixelBuffer
        )

        guard let buffer = pixelBuffer else {
            fatalError("Failed to create solid color CVPixelBuffer")
        }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(buffer) else {
            fatalError("CVPixelBuffer has no base address")
        }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        let ptr = baseAddress.assumingMemoryBound(to: UInt8.self)

        for y in 0..<height {
            for x in 0..<width {
                let offset = y * bytesPerRow + x * 4
                ptr[offset + 0] = blue   // B
                ptr[offset + 1] = green  // G
                ptr[offset + 2] = red    // R
                ptr[offset + 3] = alpha  // A
            }
        }

        return buffer
    }

    // MARK: - MTLTexture Helpers

    /// Creates a Metal texture from a CVPixelBuffer using a Metal device.
    /// Returns nil if Metal is unavailable.
    static func texture(from pixelBuffer: CVPixelBuffer, device: MTLDevice) -> MTLTexture? {
        var cvTexture: CVMetalTexture?
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        let status = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            sharedTextureCache(device: device),
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

    // MARK: - Pixel Sampling (for test assertions)

    /// Samples a single pixel from a CVPixelBuffer. Returns (R, G, B, A) as UInt8.
    static func samplePixel(from buffer: CVPixelBuffer, x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8)? {
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        guard x >= 0, x < width, y >= 0, y < height else { return nil }

        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        let offset = y * bytesPerRow + x * 4
        let ptr = baseAddress.assumingMemoryBound(to: UInt8.self)

        // BGRA → RGBA
        return (ptr[offset + 2], ptr[offset + 1], ptr[offset + 0], ptr[offset + 3])
    }

    /// Verifies two CVPixelBuffers have the same dimensions.
    static func assertSameDimensions(
        _ buffer1: CVPixelBuffer,
        _ buffer2: CVPixelBuffer,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        XCTAssertEqual(
            CVPixelBufferGetWidth(buffer1), CVPixelBufferGetWidth(buffer2),
            "Width mismatch", file: file, line: line
        )
        XCTAssertEqual(
            CVPixelBufferGetHeight(buffer1), CVPixelBufferGetHeight(buffer2),
            "Height mismatch", file: file, line: line
        )
    }

    // MARK: - Performance Measurement

    /// Measures the wall-clock time of a block in milliseconds.
    static func measureMs(_ block: () -> Void) -> Double {
        let start = CFAbsoluteTimeGetCurrent()
        block()
        let end = CFAbsoluteTimeGetCurrent()
        return (end - start) * 1000.0
    }

    /// Measures the wall-clock time of a throwing block in milliseconds.
    static func measureMsThrowing(_ block: () throws -> Void) rethrows -> Double {
        let start = CFAbsoluteTimeGetCurrent()
        try block()
        let end = CFAbsoluteTimeGetCurrent()
        return (end - start) * 1000.0
    }

    // MARK: - Private

    private static var _textureCache: CVMetalTextureCache?
    private static let textureCacheLock = NSLock()

    private static func sharedTextureCache(device: MTLDevice) -> CVMetalTextureCache {
        textureCacheLock.lock()
        defer { textureCacheLock.unlock() }

        if let existing = _textureCache { return existing }

        var cache: CVMetalTextureCache?
        CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &cache)
        _textureCache = cache!
        return cache!
    }
}
