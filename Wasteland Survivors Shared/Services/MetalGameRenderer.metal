#include <metal_stdlib>
using namespace metal;

struct MetalVertex {
    float2 position;
    float4 color;
};

struct MetalVertexOut {
    float4 position [[position]];
    float4 color;
};

vertex MetalVertexOut metalVertex(
    uint vertexID [[vertex_id]],
    const device MetalVertex *vertices [[buffer(0)]]
) {
    MetalVertexOut output;
    output.position = float4(vertices[vertexID].position, 0.0, 1.0);
    output.color = vertices[vertexID].color;
    return output;
}

fragment float4 metalFragment(MetalVertexOut input [[stage_in]]) {
    return input.color;
}
