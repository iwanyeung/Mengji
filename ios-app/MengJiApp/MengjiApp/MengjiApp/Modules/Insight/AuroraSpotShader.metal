#include <metal_stdlib>
using namespace metal;

struct SpotAuroraUniforms {
    float2 resolution;
    float time;
    float amplitude;
    float blend;
    float speed;
    float4 colorStop0;
    float4 colorStop1;
    float4 colorStop2;
    float4 backgroundRGB;
};

struct SpotAuroraVertexOut {
    float4 position [[position]];
    float2 uv;
};

float3 permute(float3 x) {
    return fmod(((x * 34.0f) + 1.0f) * x, 289.0f);
}

float snoise(float2 v) {
    const float4 C = float4(
        0.211324865405187f, 0.366025403784439f,
        -0.577350269189626f, 0.024390243902439f
    );

    float2 i = floor(v + dot(v, C.yy));
    float2 x0 = v - i + dot(i, C.xx);
    float2 i1 = (x0.x > x0.y) ? float2(1.0f, 0.0f) : float2(0.0f, 1.0f);

    float4 x12 = x0.xyxy + C.xxzz;
    x12.xy -= i1;
    i = fmod(i, 289.0f);

    float3 p = permute(
        permute(i.y + float3(0.0f, i1.y, 1.0f))
        + i.x + float3(0.0f, i1.x, 1.0f)
    );

    float3 m = max(
        0.5f - float3(
            dot(x0, x0),
            dot(x12.xy, x12.xy),
            dot(x12.zw, x12.zw)
        ),
        0.0f
    );
    m = m * m;
    m = m * m;

    float3 x = 2.0f * fract(p * C.www) - 1.0f;
    float3 h = abs(x) - 0.5f;
    float3 ox = floor(x + 0.5f);
    float3 a0 = x - ox;
    m *= 1.79284291400159f - 0.85373472095314f * (a0 * a0 + h * h);

    float3 g;
    g.x = a0.x * x0.x + h.x * x0.y;
    g.yz = a0.yz * x12.xz + h.yz * x12.yw;
    return 130.0f * dot(m, g);
}

float3 colorRamp(float factor, float3 c0, float3 c1, float3 c2) {
    float f = clamp(factor, 0.0f, 1.0f);
    if (f <= 0.5f) {
        return mix(c0, c1, f / 0.5f);
    }
    return mix(c1, c2, (f - 0.5f) / 0.5f);
}

vertex SpotAuroraVertexOut spotAuroraVertex(uint vid [[vertex_id]]) {
    float2 p = float2((vid << 1u) & 2u, vid & 2u);
    SpotAuroraVertexOut o;
    o.position = float4(p * float2(2.0f, -2.0f) + float2(-1.0f, 1.0f), 0.0f, 1.0f);
    o.uv = float2(p.x, 1.0f - p.y);
    return o;
}

fragment float4 spotAuroraFragment(SpotAuroraVertexOut vertIn [[stage_in]],
                                   constant SpotAuroraUniforms &u [[buffer(0)]]) {
    float2 res = max(u.resolution, float2(1.0f));
    float2 fragCoord = vertIn.uv * res;
    float2 uv = fragCoord / res;

    float t = u.time * u.speed * 0.1f;
    float n = snoise(float2(uv.x * 2.0f + t * 0.1f, t * 0.25f));
    float height = exp(n * 0.5f * u.amplitude);
    height = (uv.y * 2.0f - height + 0.2f);
    float intensity = 0.6f * height;

    // 强化顶部两侧光斑：边缘权重 + 顶部权重，中心与下部保持克制。
    float sideWeight = pow(saturate(abs(uv.x - 0.5f) * 2.0f), 1.25f);
    float topWeight = smoothstep(0.45f, 1.0f, uv.y);
    intensity *= (1.0f + 0.55f * sideWeight * topWeight);

    float midPoint = 0.20f;
    float auroraAlpha = smoothstep(midPoint - u.blend * 0.5f, midPoint + u.blend * 0.5f, intensity);

    float3 ramp = colorRamp(uv.x, u.colorStop0.xyz, u.colorStop1.xyz, u.colorStop2.xyz);
    float3 auroraColor = intensity * ramp;
    float3 premul = auroraColor * auroraAlpha;

    float3 outRgb = mix(u.backgroundRGB.xyz, premul, saturate(auroraAlpha));
    return float4(outRgb, 1.0f);
}
