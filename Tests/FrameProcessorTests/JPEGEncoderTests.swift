import XCTest
import Metal
import CoreVideo
import ImageIO

/// Tests for JPEGEncoder — MTLTexture → JPEG Data encoding via ImageIO.
///
/// TDD RED: These tests define the contract BEFORE JPEGEncoder is implemented.

@available(macOS 14.0, *)
final class JPEGEncoderTests: XCTestCase {

    var encoder: JPEGEncoder!
    var device: MTLDevice!

    override func setUp() {
        super.setUp()
        device = MTLCreateSystemDefaultDevice()
        XCTAssertNotNil(device, "Metal device required — run on Apple Silicon Mac")
        encoder = JPEGEncoder()
    }

    override func tearDown() {
        encoder = nil
        device = nil
        super.tearDown()
    }

    // MARK: - Initialization

    func test_init_succeeds() {
        let enc = JPEGEncoder()
        XCTAssertNotNil(enc)
    }

    // MARK: - Basic Encoding

    func test_encode_producesValidJPEG() throws {
        let texture = try createTestTexture(width: 256, height: 256)

        let result = try encoder.encode(texture: texture, quality: 80.0)

        XCTAssertFalse(result.data.isEmpty, "JPEG data should not be empty")
        XCTAssertGreaterThan(result.data.count, 100, "JPEG data should be substantial")
        XCTAssertGreaterThan(result.encodeTimeMs, 0, "Encode time should be measured")

        // Verify it's a valid JPEG
        let header = result.data.prefix(2)
        XCTAssertEqual(header[0], 0xFF, "JPEG should start with FF")
        XCTAssertEqual(header[1], 0xD8, "JPEG should start with FF D8 SOI marker")
    }

    func test_encode_decodedImageMatchesTextureDimensions() throws {
        let width = 320
        let height = 240
        let texture = try createTestTexture(width: width, height: height)

        let result = try encoder.encode(texture: texture, quality: 80.0)

        guard let imageSource = CGImageSourceCreateWithData(result.data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
            XCTFail("Failed to decode output JPEG")
            return
        }

        XCTAssertEqual(image.width, width)
        XCTAssertEqual(image.height, height)
    }

    // MARK: - Quality Levels

    func test_encode_quality75_producesValidJPEG() throws {
        let texture = try createTestTexture(width: 128, height: 128)

        let result = try encoder.encode(texture: texture, quality: 75.0)

        XCTAssertFalse(result.data.isEmpty)
        XCTAssertEqual(result.data.prefix(2)[0], 0xFF)
        XCTAssertEqual(result.data.prefix(2)[1], 0xD8)
    }

    func test_encode_quality80_producesValidJPEG() throws {
        let texture = try createTestTexture(width: 128, height: 128)

        let result = try encoder.encode(texture: texture, quality: 80.0)

        XCTAssertFalse(result.data.isEmpty)
    }

    func test_encode_quality85_producesValidJPEG() throws {
        let texture = try createTestTexture(width: 128, height: 128)

        let result = try encoder.encode(texture: texture, quality: 85.0)

        XCTAssertFalse(result.data.isEmpty)
    }

    func test_encode_higherQuality_producesLargerOrEqualFile() throws {
        let texture = try createTestTexture(width: 512, height: 512)

        let result75 = try encoder.encode(texture: texture, quality: 75.0)
        let result85 = try encoder.encode(texture: texture, quality: 85.0)
        let result100 = try encoder.encode(texture: texture, quality: 100.0)

        // Higher quality should produce >= bytes (typically more, but not always for simple patterns)
        XCTAssertGreaterThanOrEqual(result100.data.count, result85.data.count,
                                    "Quality 100 should produce >= bytes than quality 85")
        XCTAssertGreaterThanOrEqual(result85.data.count, result75.data.count,
                                    "Quality 85 should produce >= bytes than quality 75")
    }

    func test_encode_quality100_producesLargerFile() throws {
        let texture = try createTestTexture(width: 256, height: 256)

        let result100 = try encoder.encode(texture: texture, quality: 100.0)
        let result50 = try encoder.encode(texture: texture, quality: 50.0)

        XCTAssertGreaterThan(result100.data.count, result50.data.count,
                             "Quality 100 should produce larger file than quality 50")
    }

    // MARK: - Error Handling

    func test_encode_invalidQuality_belowZero_throws() throws {
        let texture = try createTestTexture(width: 64, height: 64)

        XCTAssertThrowsError(
            try encoder.encode(texture: texture, quality: -1.0)
        ) { error in
            guard case JPEGEncoderError.invalidQuality = error else {
                XCTFail("Expected invalidQuality, got \(error)")
                return
            }
        }
    }

    func test_encode_invalidQuality_above100_throws() throws {
        let texture = try createTestTexture(width: 64, height: 64)

        XCTAssertThrowsError(
            try encoder.encode(texture: texture, quality: 101.0)
        ) { error in
            guard case JPEGEncoderError.invalidQuality = error else {
                XCTFail("Expected invalidQuality, got \(error)")
                return
            }
        }
    }

    // MARK: - Performance

    func test_performance_1080pEncode_under5ms() throws {
        let texture = try createTestTexture(width: 1920, height: 1080)

        // Warm-up
        _ = try encoder.encode(texture: texture, quality: 80.0)

        var times: [Double] = []
        for _ in 0..<5 {
            let result = try encoder.encode(texture: texture, quality: 80.0)
            times.append(result.encodeTimeMs)
        }
        times.sort()
        let median = times[2]

        XCTAssertLessThan(
            median, 5.0,
            "1080p JPEG encode should complete under 5ms at quality 80. Got \(String(format: "%.1f", median))ms"
        )
    }

    func test_performance_quality75_fasterThanQuality85() throws {
        let texture = try createTestTexture(width: 1920, height: 1080)

        // Warm up at both qualities
        _ = try encoder.encode(texture: texture, quality: 75.0)
        _ = try encoder.encode(texture: texture, quality: 85.0)

        var times75: [Double] = []
        for _ in 0..<5 {
            let result = try encoder.encode(texture: texture, quality: 75.0)
            times75.append(result.encodeTimeMs)
        }
        let median75 = times75.sorted()[2]

        var times85: [Double] = []
        for _ in 0..<5 {
            let result = try encoder.encode(texture: texture, quality: 85.0)
            times85.append(result.encodeTimeMs)
        }
        let median85 = times85.sorted()[2]

        // Quality 75 should generally be faster or equal to quality 85
        XCTAssertLessThanOrEqual(
            median75, median85 * 1.1, // 10% tolerance
            "Quality 75 should be ~similar or faster than quality 85"
        )
    }

    // MARK: - Different Texture Sizes

    func test_encode_4KTexture_producesValidJPEG() throws {
        let texture = try createTestTexture(width: 3840, height: 2160)

        let result = try encoder.encode(texture: texture, quality: 80.0)

        XCTAssertFalse(result.data.isEmpty)
        XCTAssertGreaterThan(result.data.count, 10_000, "4K JPEG should be substantial")
    }

    func test_encode_smallTexture_producesValidJPEG() throws {
        let texture = try createTestTexture(width: 16, height: 16)

        let result = try encoder.encode(texture: texture, quality: 80.0)

        XCTAssertFalse(result.data.isEmpty)
        XCTAssertGreaterThan(result.data.count, 20, "Even small textures produce some data")
    }

    // MARK: - Helpers

    private func createTestTexture(width: Int, height: Int) throws -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead, .shaderWrite]

        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw XCTSkip("Failed to create test texture")
        }

        // Fill with a gradient pattern
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
        for y in 0..<height {
            for x in 0..<width {
                let offset = y * bytesPerRow + x * 4
                pixels[offset + 0] = UInt8((x * 255) / max(width - 1, 1))
                pixels[offset + 1] = UInt8((y * 255) / max(height - 1, 1))
                pixels[offset + 2] = 128
                pixels[offset + 3] = 255
            }
        }

        let region = MTLRegionMake2D(0, 0, width, height)
        texture.replace(region: region, mipmapLevel: 0, withBytes: &pixels, bytesPerRow: bytesPerRow)

        return texture
    }
}
