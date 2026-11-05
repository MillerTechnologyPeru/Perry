// Anvil's shaders, built into the app's default.metallib.

#include <metal_stdlib>
using namespace metal;

struct Vertex {
    float3 position [[attribute(0)]];
    float4 color [[attribute(1)]];
};

struct Varyings {
    float4 position [[position]];
    float4 color;
    float2 uv;
};

vertex Varyings solid_vertex(Vertex in [[stage_in]]) {
    Varyings out;
    out.position = float4(in.position, 1.0);
    out.color = in.color;
    out.uv = in.position.xy * 0.5 + 0.5;
    return out;
}

fragment float4 solid_fragment(Varyings in [[stage_in]]) {
    return in.color;
}

// A quad from the vertex ID, sampling a texture.
vertex Varyings quad_vertex(uint id [[vertex_id]], constant float4 &rect [[buffer(0)]]) {
    float2 corner = float2(id & 1, id >> 1);
    Varyings out;
    out.position = float4(mix(rect.xy, rect.zw, corner), 0.0, 1.0);
    out.color = float4(1.0);
    out.uv = float2(corner.x, 1.0 - corner.y);
    return out;
}

fragment float4 quad_fragment(Varyings in [[stage_in]], texture2d<float> image [[texture(0)]],
                              sampler nearest [[sampler(0)]]) {
    return image.sample(nearest, in.uv);
}
