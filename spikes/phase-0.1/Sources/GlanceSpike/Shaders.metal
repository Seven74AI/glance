// GlanceSpike — Metal Shaders
// Preprocessing pipeline: BGRA→RGB conversion + downscale to 1080p
//
// All operations in a single compute pass to minimize GPU round-trips.

#include <metal_stdlib>
using namespace metal;

// Target output resolution (1080p height, width via aspect ratio)
constant uint kTargetHeight = 1080;

// MARK: - BGRA8 → RGB8 + Downscale (single pass)

kernel void bgra_to_rgb_downscale(
    texture2d<float, access::read>  input  [[texture(0)]],
    texture2d<float, access::write> output [[texture(1)]],
    uint2 gid [[thread_position_in_grid]])
{
    uint2 outputSize = uint2(output.get_width(), output.get_height());
    
    // Guard: skip threads outside output bounds
    if (gid.x >= outputSize.x || gid.y >= outputSize.y) {
        return;
    }
    
    uint2 inputSize = uint2(input.get_width(), input.get_height());
    
    // Bilinear sampling: map output pixel to input coordinate
    float2 uv = float2(
        (float(gid.x) + 0.5) / float(outputSize.x),
        (float(gid.y) + 0.5) / float(outputSize.y)
    );
    
    // Sample 4 nearest neighbors for bilinear interpolation
    float2 inputCoord = uv * float2(inputSize);
    int2 base = int2(floor(inputCoord - 0.5));
    float2 frac = fract(inputCoord - 0.5);
    
    int2 c00 = clamp(base, int2(0), int2(inputSize) - 1);
    int2 c10 = clamp(base + int2(1, 0), int2(0), int2(inputSize) - 1);
    int2 c01 = clamp(base + int2(0, 1), int2(0), int2(inputSize) - 1);
    int2 c11 = clamp(base + int2(1, 1), int2(0), int2(inputSize) - 1);
    
    float4 p00 = input.read(uint2(c00));
    float4 p10 = input.read(uint2(c10));
    float4 p01 = input.read(uint2(c01));
    float4 p11 = input.read(uint2(c11));
    
    // Bilinear blend
    float4 top    = mix(p00, p10, frac.x);
    float4 bottom = mix(p01, p11, frac.x);
    float4 pixel  = mix(top, bottom, frac.y);
    
    // BGRA → RGB swizzle (input is BGRA8, output is RGB)
    // Metal textures are normalized [0,1] regardless of source format
    float3 rgb = pixel.bgr;  // swizzle: .bgr on float4 gives (b, g, r)
    
    output.write(float4(rgb, 1.0), gid);
}

// MARK: - Frame differencing (simple pixel-level change detection)

kernel void frame_diff(
    texture2d<float, access::read>  current  [[texture(0)]],
    texture2d<float, access::read>  previous [[texture(1)]],
    device atomic_uint&             changedPixels [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]])
{
    uint2 size = uint2(current.get_width(), current.get_height());
    if (gid.x >= size.x || gid.y >= size.y) { return; }
    
    float4 cur = current.read(gid);
    float4 prev = previous.read(gid);
    
    // Simple luminance difference threshold
    float curLum = dot(cur.rgb, float3(0.299, 0.587, 0.114));
    float prevLum = dot(prev.rgb, float3(0.299, 0.587, 0.114));
    
    if (abs(curLum - prevLum) > 0.05) {
        atomic_fetch_add_explicit(&changedPixels, 1, memory_order_relaxed);
    }
}
