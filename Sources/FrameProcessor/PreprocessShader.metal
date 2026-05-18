#include <metal_stdlib>
using namespace metal;

// =============================================================================
// Glance — Frame Preprocessing Compute Shader
// =============================================================================
// Single-pass: BGRA→RGBA swizzle + bilinear downscale.
//
// Performance: Uses hardware bilinear sampler (free on GPU) for downscaling.
// The BGRA→RGBA swizzle is done in the same pass — no intermediate texture.
//
// Target: < 5ms for 4K→1080p on M1+ Apple Silicon.
//
// FUTURE: Add Lanczos option via 6x6 kernel convolution for higher quality
// when maximum sharpness is needed (e.g., text-heavy screenshots).
// =============================================================================

/// Compute kernel: swizzle BGRA→RGBA + bilinear downscale in one pass.
///
/// Input:  BGRA8Unorm texture (from IOSurface-backed CVPixelBuffer)
/// Output: RGBA8Unorm texture (suitable for JPEG encoding or CoreML)
///
/// Each thread processes one output pixel. The hardware bilinear sampler
/// handles the downscale filtering automatically.
kernel void preprocess_bgra_to_rgba_bilinear(
    texture2d<float, access::sample>  input  [[texture(0)]],
    texture2d<float, access::write>   output [[texture(1)]],
    constant float2& scale_factor      [[buffer(0)]],
    uint2 gid                          [[thread_position_in_grid]]
) {
    // Bounds check
    if (gid.x >= output.get_width() || gid.y >= output.get_height()) {
        return;
    }

    // Compute normalized source coordinate (center of output pixel)
    // Add 0.5 for center-sampling to avoid edge artifacts
    float2 src_coord = (float2(gid) + 0.5f) * scale_factor;

    // Configure sampler: bilinear filtering, clamp to edge
    constexpr sampler s(
        coord::normalized,
        address::clamp_to_edge,
        filter::linear
    );

    // Sample BGRA input with bilinear interpolation (hardware-accelerated)
    float4 bgra = input.sample(s, src_coord / float2(input.get_width(), input.get_height()));

    // Swizzle: BGRA → RGBA
    // Input:  [B, G, R, A]
    // Output: [R, G, B, A]
    float4 rgba = float4(bgra.z, bgra.y, bgra.x, bgra.w);

    // Write output
    output.write(rgba, gid);
}


/// Faster variant using nearest-neighbor sampling (lower quality, slightly faster).
/// Useful when speed is critical and quality loss is acceptable.
kernel void preprocess_bgra_to_rgba_nearest(
    texture2d<float, access::sample>  input  [[texture(0)]],
    texture2d<float, access::write>   output [[texture(1)]],
    constant float2& scale_factor      [[buffer(0)]],
    uint2 gid                          [[thread_position_in_grid]]
) {
    if (gid.x >= output.get_width() || gid.y >= output.get_height()) {
        return;
    }

    float2 src_coord = (float2(gid) + 0.5f) * scale_factor;

    // Nearest-neighbor sampler
    constexpr sampler s(
        coord::normalized,
        address::clamp_to_edge,
        filter::nearest
    );

    float4 bgra = input.sample(s, src_coord / float2(input.get_width(), input.get_height()));
    float4 rgba = float4(bgra.z, bgra.y, bgra.x, bgra.w);

    output.write(rgba, gid);
}


// =============================================================================
// Lanczos downscale (high quality, optional)
// =============================================================================
// Lanczos-3 kernel: sinc(x) * sinc(x/3) for |x| < 3, 0 otherwise.
// 6x6 sample window per output pixel. Significantly slower than bilinear
// but produces sharper results for text-heavy content.
//
// Use this when the AI needs to read small text in screenshots.

constant float LANCZOS_A = 3.0f;

/// Compute sinc(x) = sin(pi*x) / (pi*x), with x=0 → 1.
inline float sinc(float x) {
    if (abs(x) < 1e-6f) return 1.0f;
    float pix = M_PI_F * x;
    return sin(pix) / pix;
}

/// Lanczos-3 kernel weight.
inline float lanczos3_weight(float x) {
    if (abs(x) >= LANCZOS_A) return 0.0f;
    return sinc(x) * sinc(x / LANCZOS_A);
}

/// Lanczos-3 downscale: 6x6 tap per output pixel.
/// Much higher quality than bilinear, but ~6x more texture reads.
kernel void preprocess_bgra_to_rgba_lanczos3(
    texture2d<float, access::sample>  input  [[texture(0)]],
    texture2d<float, access::write>   output [[texture(1)]],
    constant float2& scale_factor      [[buffer(0)]],
    uint2 gid                          [[thread_position_in_grid]]
) {
    if (gid.x >= output.get_width() || gid.y >= output.get_height()) {
        return;
    }

    // Center of output pixel in source coordinates
    float2 src_center = (float2(gid) + 0.5f) * scale_factor;

    // Source pixel coordinates (integer center)
    float2 src_pixel = src_center - 0.5f;

    // Lanczos window: 3 pixels in each direction → 6x6 samples
    int2 base = int2(floor(src_pixel)) - 2; // base corner of 6x6 window

    float4 sum = float4(0.0f);
    float total_weight = 0.0f;

    constexpr sampler s(
        coord::pixel,
        address::clamp_to_edge,
        filter::nearest
    );

    for (int dy = 0; dy < 6; dy++) {
        for (int dx = 0; dx < 6; dx++) {
            int2 sample_coord = base + int2(dx, dy);
            float2 offset = float2(sample_coord) - src_pixel;

            float wx = lanczos3_weight(offset.x);
            float wy = lanczos3_weight(offset.y);
            float weight = wx * wy;

            if (weight > 0.0f) {
                float4 bgra = input.read(uint2(sample_coord));
                // Swizzle BGRA → RGBA inline
                float4 rgba = float4(bgra.z, bgra.y, bgra.x, bgra.w);
                sum += rgba * weight;
                total_weight += weight;
            }
        }
    }

    float4 result = (total_weight > 0.0f) ? (sum / total_weight) : float4(0.0f);
    output.write(result, gid);
}
