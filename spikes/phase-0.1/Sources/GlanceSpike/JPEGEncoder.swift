// GlanceSpike — JPEG Encoder
// Converts MTLTexture to JPEG data via ImageIO, measuring encode time and output size.

import Metal
import ImageIO
import UniformTypeIdentifiers
import CoreGraphics

/// JPEG encoding from Metal textures.
final class JPEGEncoder {
    
    /// Compression quality ([0.0, 1.0]). 0.75, 0.80, 0.85 recommended for screen content.
    let quality: CGFloat
    
    /// Encode result with timing and size data.
    struct EncodeResult {
        let jpegData: Data
        let sizeBytes: Int
        let encodeTimeMs: Double
        let width: Int
        let height: Int
    }
    
    init(quality: CGFloat = 0.75) {
        self.quality = max(0.0, min(1.0, quality))
    }
    
    /// Encode a Metal texture to JPEG.
    /// - Note: This involves a GPU→CPU readback (MTLTexture → CGImage → JPEG).
    func encode(texture: MTLTexture) throws -> EncodeResult {
        
        let encodeStart = DispatchTime.now()
        
        let width = texture.width
        let height = texture.height
        
        // Readback: MTLTexture → raw bytes
        let bytesPerRow = width * 4  // RGBA8 = 4 bytes/pixel
        let totalBytes = bytesPerRow * height
        var pixelData = [UInt8](repeating: 0, count: totalBytes)
        
        let region = MTLRegionMake2D(0, 0, width, height)
        texture.getBytes(
            &pixelData,
            bytesPerRow: bytesPerRow,
            from: region,
            mipmapLevel: 0
        )
        
        // Create CGImage from raw RGBA bytes
        guard let dataProvider = CGDataProvider(data: NSData(bytes: &pixelData, length: totalBytes)) else {
            throw JPEGError.dataProviderFailed
        }
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue)
        
        guard let cgImage = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo,
            provider: dataProvider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ) else {
            throw JPEGError.cgImageCreationFailed
        }
        
        // JPEG encode via ImageIO
        guard let mutableData = CFDataCreateMutable(nil, 0) else {
            throw JPEGError.destinationCreationFailed
        }
        
        guard let destination = CGImageDestinationCreateWithData(
            mutableData,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            throw JPEGError.destinationCreationFailed
        }
        
        let options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: quality
        ]
        
        CGImageDestinationAddImage(destination, cgImage, options as CFDictionary)
        
        guard CGImageDestinationFinalize(destination) else {
            throw JPEGError.encodeFailed
        }
        
        let jpegData = mutableData as Data
        
        let encodeEnd = DispatchTime.now()
        let encodeTimeMs = Double(encodeEnd.uptimeNanoseconds - encodeStart.uptimeNanoseconds) / 1_000_000.0
        
        return EncodeResult(
            jpegData: jpegData,
            sizeBytes: jpegData.count,
            encodeTimeMs: encodeTimeMs,
            width: width,
            height: height
        )
    }
}

// MARK: - Errors

enum JPEGError: LocalizedError {
    case dataProviderFailed
    case cgImageCreationFailed
    case destinationCreationFailed
    case encodeFailed
    
    var errorDescription: String? {
        switch self {
        case .dataProviderFailed: return "Failed to create CGDataProvider from pixel data"
        case .cgImageCreationFailed: return "Failed to create CGImage from pixel buffer"
        case .destinationCreationFailed: return "Failed to create CGImageDestination for JPEG"
        case .encodeFailed: return "JPEG encoding failed"
        }
    }
}
