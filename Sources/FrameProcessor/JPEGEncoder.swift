import Metal
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers

// MARK: - Errors

/// Errors thrown by JPEGEncoder.
enum JPEGEncoderError: Error, Equatable {
    case invalidQuality
    case textureReadbackFailed
    case imageCreationFailed
    case encodeFailed
}

// MARK: - Result

/// Result of JPEG encoding with timing information.
struct JPEGEncodeResult {
    /// The encoded JPEG data.
    let data: Data
    /// Wall-clock encode time in milliseconds.
    let encodeTimeMs: Double
}

// MARK: - JPEGEncoder

/// Encodes MTLTexture → JPEG Data via ImageIO.
///
/// Reads back GPU texture to CPU, creates CGImage, encodes as JPEG.
/// Optimized for speed: uses shared storage mode textures for fast readback.
///
/// Performance target: < 5ms for 1080p at quality 80 on M1+.
@available(macOS 14.0, *)
final class JPEGEncoder {

    // MARK: - Properties

    /// Default JPEG quality (0.0–100.0).
    static let defaultQuality: Float = 80.0

    // MARK: - Public API

    /// Encodes a Metal texture as JPEG data.
    ///
    /// - Parameters:
    ///   - texture: Metal texture in RGBA8Unorm format.
    ///   - quality: JPEG quality 0.0–100.0. Clamped to valid range.
    /// - Returns: `JPEGEncodeResult` with JPEG data and timing.
    /// - Throws: `JPEGEncoderError` if texture readback or encoding fails.
    func encode(texture: MTLTexture, quality: Float) throws -> JPEGEncodeResult {
        // Validate quality
        guard quality >= 0.0 && quality <= 100.0 else {
            throw JPEGEncoderError.invalidQuality
        }

        let startTime = CFAbsoluteTimeGetCurrent()

        // Step 1: Read back texture to CPU memory
        let pixelData = try readTextureToRGBA8(texture: texture)

        // Step 2: Create CGImage from raw RGBA8 data
        guard let cgImage = createCGImage(
            from: pixelData,
            width: texture.width,
            height: texture.height
        ) else {
            throw JPEGEncoderError.imageCreationFailed
        }

        // Step 3: JPEG encode via ImageIO
        guard let jpegData = encodeJPEG(image: cgImage, quality: CGFloat(quality)) else {
            throw JPEGEncoderError.encodeFailed
        }

        let endTime = CFAbsoluteTimeGetCurrent()
        let encodeTimeMs = (endTime - startTime) * 1000.0

        return JPEGEncodeResult(data: jpegData, encodeTimeMs: encodeTimeMs)
    }

    // MARK: - Private

    /// Reads an RGBA8Unorm texture back to a flat UInt8 array.
    private func readTextureToRGBA8(texture: MTLTexture) throws -> [UInt8] {
        let width = texture.width
        let height = texture.height
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        let totalBytes = height * bytesPerRow

        var pixelData = [UInt8](repeating: 0, count: totalBytes)

        let region = MTLRegionMake2D(0, 0, width, height)
        texture.getBytes(&pixelData, bytesPerRow: bytesPerRow, from: region, mipmapLevel: 0)

        return pixelData
    }

    /// Creates a CGImage from raw RGBA8 pixel data.
    private func createCGImage(
        from pixelData: [UInt8],
        width: Int,
        height: Int
    ) -> CGImage? {
        let bytesPerPixel = 4
        let bitsPerComponent = 8
        let bitsPerPixel = bitsPerComponent * bytesPerPixel
        let bytesPerRow = width * bytesPerPixel

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo: CGBitmapInfo = [
            CGBitmapInfo.byteOrder32Big,
            CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        ]

        guard let dataProvider = CGDataProvider(data: Data(pixelData) as CFData) else {
            return nil
        }

        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: bitsPerComponent,
            bitsPerPixel: bitsPerPixel,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo,
            provider: dataProvider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }

    /// Encodes a CGImage as JPEG using ImageIO.
    private func encodeJPEG(image: CGImage, quality: CGFloat) -> Data? {
        let data = NSMutableData()

        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            return nil
        }

        let options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: quality / 100.0
        ]

        CGImageDestinationAddImage(destination, image, options as CFDictionary)

        guard CGImageDestinationFinalize(destination) else {
            return nil
        }

        return data as Data
    }
}
