//
//  AuroraShader.metal
//  对齐 WebGL Soft Aurora：Perlin 噪声 + exp 锐化带 + 沿 x 的 cosine 渐变双色层。
//

#include <metal_stdlib>
using namespace metal;

constant float TAU = 6.28318530718f;

struct AuroraUniforms {
    float2 resolution;
    float time;
    float speed;
    float scale;
    float brightness;
    float4 color1;
    float4 color2;
    float noiseFreq;
    float noiseAmp;
    float bandHeight;
    float bandSpread;
    float octaveDecay;
    float layerOffset;
    float colorSpeed;
    float pulseBoost;
    float4 backgroundRGB; // .xyz 为背景色
};

struct AuroraVertexOut {
    float4 position [[position]];
    float2 uv;
};

float3 gradientHash(float3 p) {
    p = float3(
        dot(p, float3(127.1f, 311.7f, 234.6f)),
        dot(p, float3(269.5f, 183.3f, 198.3f)),
        dot(p, float3(169.5f, 283.3f, 156.9f))
    );
    float3 h = fract(sin(p) * 43758.5453123f);
    float phi = acos(2.0f * h.x - 1.0f);
    float theta = TAU * h.y;
    return float3(cos(theta) * sin(phi), sin(theta) * cos(phi), cos(phi));
}

float quinticSmooth(float t) {
    float t2 = t * t;
    float t3 = t * t2;
    return 6.0f * t3 * t2 - 15.0f * t2 * t2 + 10.0f * t3;
}

float3 cosineGradient(float t, float3 a, float3 b, float3 c, float3 d) {
    return a + b * cos(TAU * (c * t + d));
}

float perlin3D(float amplitude, float frequency, float px, float py, float pz) {
    float x = px * frequency;
    float y = py * frequency;

    float fx = floor(x);
    float fy = floor(y);
    float fz = floor(pz);
    float cx = ceil(x);
    float cy = ceil(y);
    float cz = ceil(pz);

    float3 g000 = gradientHash(float3(fx, fy, fz));
    float3 g100 = gradientHash(float3(cx, fy, fz));
    float3 g010 = gradientHash(float3(fx, cy, fz));
    float3 g110 = gradientHash(float3(cx, cy, fz));
    float3 g001 = gradientHash(float3(fx, fy, cz));
    float3 g101 = gradientHash(float3(cx, fy, cz));
    float3 g011 = gradientHash(float3(fx, cy, cz));
    float3 g111 = gradientHash(float3(cx, cy, cz));

    float d000 = dot(g000, float3(x - fx, y - fy, pz - fz));
    float d100 = dot(g100, float3(x - cx, y - fy, pz - fz));
    float d010 = dot(g010, float3(x - fx, y - cy, pz - fz));
    float d110 = dot(g110, float3(x - cx, y - cy, pz - fz));
    float d001 = dot(g001, float3(x - fx, y - fy, pz - cz));
    float d101 = dot(g101, float3(x - cx, y - fy, pz - cz));
    float d011 = dot(g011, float3(x - fx, y - cy, pz - cz));
    float d111 = dot(g111, float3(x - cx, y - cy, pz - cz));

    float sx = quinticSmooth(x - fx);
    float sy = quinticSmooth(y - fy);
    float sz = quinticSmooth(pz - fz);

    float lx00 = mix(d000, d100, sx);
    float lx10 = mix(d010, d110, sx);
    float lx01 = mix(d001, d101, sx);
    float lx11 = mix(d011, d111, sx);

    float ly0 = mix(lx00, lx10, sy);
    float ly1 = mix(lx01, lx11, sy);

    return amplitude * mix(ly0, ly1, sz);
}

/// 与 WebGL 一致：uv = fragCoord.xy / resolution.y + shift
float auroraGlow(float t, float2 shift, float2 fragCoord, float2 resolution, constant AuroraUniforms &u) {
    float2 uv = fragCoord / max(resolution.y, 1.0f);
    uv += shift;

    float noiseVal = 0.0f;
    float freq = u.noiseFreq;
    float amp = u.noiseAmp;
    float2 samplePos = uv * u.scale;

    for (int i = 0; i < 3; i++) {
        noiseVal += perlin3D(amp, freq, samplePos.x, samplePos.y, t);
        amp *= u.octaveDecay;
        freq *= 2.0f;
    }

    float yBand = uv.y * 10.0f - u.bandHeight * 10.0f;
    float spread = u.bandSpread * (1.0f + u.pulseBoost * 0.35f);
    return 0.3f * max(exp(spread * (1.0f - 1.1f * abs(noiseVal + yBand))), 0.0f);
}

vertex AuroraVertexOut auroraVertex(uint vid [[vertex_id]]) {
    float2 p = float2((vid << 1u) & 2u, vid & 2u);
    AuroraVertexOut o;
    o.position = float4(p * float2(2.0f, -2.0f) + float2(-1.0f, 1.0f), 0.0f, 1.0f);
    o.uv = float2(p.x, 1.0f - p.y);
    return o;
}

fragment float4 auroraFragment(AuroraVertexOut vertIn [[stage_in]],
                               constant AuroraUniforms &u [[buffer(0)]]) {
    float2 iResolution = u.resolution;
    float2 fragCoord = vertIn.uv * iResolution;

    float2 uvNorm = fragCoord / max(iResolution, float2(1.0f));

    float t = u.speed * 0.4f * u.time;
    float2 shift = float2(0.0f);

    float g1 = auroraGlow(t, shift, fragCoord, iResolution, u);
    float g2 = auroraGlow(t + u.layerOffset, shift, fragCoord, iResolution, u);

    // c 的 R 分量略低：减少沿 x 摆动时偏品红/红的条纹；b 的 R 略低：压低 R 通道起伏幅度
    float3 cg1 = cosineGradient(
        uvNorm.x + u.time * u.speed * 0.2f * u.colorSpeed,
        float3(0.5f),
        float3(0.36f, 0.5f, 0.48f),
        float3(0.65f, 1.0f, 1.0f),
        float3(0.26f, 0.20f, 0.20f)
    );
    float3 cg2 = cosineGradient(
        uvNorm.x + u.time * u.speed * 0.1f * u.colorSpeed,
        float3(0.5f),
        float3(0.32f, 0.42f, 0.42f),
        float3(0.55f, 1.0f, 0.95f),
        float3(0.28f, 0.22f, 0.18f)
    );

    float3 col = float3(0.0f);
    col += 0.99f * g1 * cg1 * u.color1.xyz;
    // 第二层略弱，避免与主带抢色，更贴「暗酸黄」层次
    col += 0.55f * g2 * cg2 * u.color2.xyz;

    float bright = u.brightness * (1.0f + u.pulseBoost * 0.45f);
    col *= bright;
    // 与酸性黄主色一致：再收一点红、略抬绿
    col.r *= 0.74f;
    col.g *= 1.04f;

    float alpha = saturate(length(col));
    float3 bg = u.backgroundRGB.xyz;
    float3 outRgb = mix(bg, col, alpha);
    return float4(outRgb, 1.0f);
}
