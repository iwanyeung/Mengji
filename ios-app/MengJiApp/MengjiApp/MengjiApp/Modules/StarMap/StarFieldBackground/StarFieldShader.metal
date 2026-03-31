//
//  StarFieldShader.metal
//  Port of ShaderToy flight shader; iChannel0 replaced with procedural noise.
//

#include <metal_stdlib>
using namespace metal;

constant float FADEOUT_DISTANCE = 10.0f;
constant float FIELD_OF_VIEW = 1.05f;
constant float STAR_SIZE = 0.6f;
constant float STAR_CORE_SIZE = 0.14f;
constant float CLUSTER_SCALE = 0.02f;
constant float BLACK_HOLE_CORE_RADIUS = 0.2f;
constant float BLACK_HOLE_THRESHOLD = 0.9995f;
constant float BLACK_HOLE_DISTORTION = 0.03f;

constant int STARFIELD_MAX_STEPS_CAP = 96;

struct StarFieldUniforms {
    float2 resolution;
    float time;
    float flightSpeed;
    float4 primary;
    float4 background;
    float4 accent;
    int maxSteps;
    float drawDistance;
    float starThreshold;
    int nebulaLastIndex;
};

struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

float3 hsv2rgb(float3 c) {
    float4 K = float4(1.0f, 2.0f / 3.0f, 1.0f / 3.0f, 3.0f);
    float3 p = abs(fract(c.xxx + K.xyz) * 6.0f - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0f, 1.0f), c.y);
}

float rand2(float2 co) {
    return fract(sin(dot(co, float2(12.9898f, 78.233f))) * 43758.5453f);
}

float channel0(float2 uv) {
    float2 p = fract(uv);
    return fract(sin(dot(p, float2(127.1f, 311.7f))) * 43758.5453f);
}

float3 getRayDirection(float2 fragCoord, float2 iResolution, float3 cameraDirection) {
    float2 uv = fragCoord / iResolution;
    const float screenWidth = 1.0f;
    float originToScreen = screenWidth / 2.0f / tan(FIELD_OF_VIEW / 2.0f);
    float3 screenCenter = originToScreen * cameraDirection;
    float3 baseX = normalize(cross(screenCenter, float3(0.0f, -1.0f, 0.0f)));
    float3 baseY = normalize(cross(screenCenter, baseX));
    return normalize(screenCenter + (uv.x - 0.5f) * baseX + (uv.y - 0.5f) * iResolution.y / iResolution.x * baseY);
}

float getDistance(int3 chunkPath, float3 localStart, float3 localPosition) {
    return length(float3(chunkPath) + localPosition - localStart);
}

void move(thread float3 &localPosition, float3 rayDirection, float3 directionBound) {
    float3 directionSign = sign(rayDirection);
    float3 amountVector = (directionBound - directionSign * localPosition) / abs(rayDirection);
    float amount = min(amountVector.x, min(amountVector.y, amountVector.z));
    localPosition += amount * rayDirection;
}

void moveInsideBox(thread float3 &localPosition, thread int3 &chunk, float3 directionSign, float3 directionBound) {
    const float eps = 0.0000001f;
    if (localPosition.x * directionSign.x >= directionBound.x - eps) {
        localPosition.x -= directionSign.x;
        chunk.x += int(directionSign.x);
    } else if (localPosition.y * directionSign.y >= directionBound.y - eps) {
        localPosition.y -= directionSign.y;
        chunk.y += int(directionSign.y);
    } else if (localPosition.z * directionSign.z >= directionBound.z - eps) {
        localPosition.z -= directionSign.z;
        chunk.z += int(directionSign.z);
    }
}

bool hasStar(int3 chunk, float starThreshold) {
    float2 u1 = fmod(CLUSTER_SCALE * (float2(chunk.xy) + float2(chunk.z, chunk.x)) + float2(0.724f, 0.111f), 1.0f);
    float2 u2 = fmod(CLUSTER_SCALE * (float2(chunk.xz) + float2(chunk.z, chunk.y)) + float2(0.333f, 0.777f), 1.0f);
    return channel0(u1) > starThreshold && channel0(u2) > starThreshold;
}

bool hasBlackHole(int3 chunk) {
    float2 r = 0.0001f * float2(chunk.xy) + 0.002f * float2(chunk.y, chunk.z);
    return rand2(r) > BLACK_HOLE_THRESHOLD;
}

float3 getStarToRayVector(float3 rayBase, float3 rayDirection, float3 starPosition) {
    float r = (dot(rayDirection, starPosition) - dot(rayDirection, rayBase)) / dot(rayDirection, rayDirection);
    float3 pointOnRay = rayBase + r * rayDirection;
    return pointOnRay - starPosition;
}

float3 getStarPosition(int3 chunk, float starSize) {
    float3 position = abs(float3(
        rand2(float2(float(chunk.x) / float(chunk.y) + 0.24f, float(chunk.y) / float(chunk.z) + 0.66f)),
        rand2(float2(float(chunk.x) / float(chunk.z) + 0.73f, float(chunk.z) / float(chunk.y) + 0.45f)),
        rand2(float2(float(chunk.y) / float(chunk.x) + 0.12f, float(chunk.y) / float(chunk.z) + 0.76f))
    ));
    return starSize * float3(1.0f) + (1.0f - 2.0f * starSize) * position;
}

float4 getNebulaColor(float3 globalPosition, float3 rayDirection, float3 primary, float3 background, int nebulaLastIndex) {
    float3 color = float3(0.0f);
    float spaceLeft = 1.0f;
    const float layerDistance = 10.0f;
    for (int i = 0; i <= nebulaLastIndex; i++) {
        float3 noiseeval = globalPosition + rayDirection * ((1.0f - fract(globalPosition.z / layerDistance) + float(i)) * layerDistance / rayDirection.z);
        noiseeval.xy += noiseeval.z;
        float value = 0.06f * channel0(fract(noiseeval.xy / 60.0f));
        if (i == 0) {
            value *= 1.0f - fract(globalPosition.z / layerDistance);
        } else if (i == nebulaLastIndex) {
            value *= fract(globalPosition.z / layerDistance);
        }
        float hue = 0.12f + 0.06f * fract(noiseeval.z * 0.02f);
        float3 nebulaHue = hsv2rgb(float3(hue, 0.72f, 1.0f));
        float v = clamp(value * 8.0f, 0.0f, 1.0f);
        float3 tinted = mix(background, mix(nebulaHue, primary, 0.55f), v);
        color += spaceLeft * tinted * value * 3.0f;
        spaceLeft = max(0.0f, spaceLeft - value * 2.0f);
    }
    return float4(color, 1.0f);
}

float4 getStarGlowColor(float starDistance, float angle, float hue, float3 primary) {
    float progress = 1.0f - starDistance;
    float3 rgb = hsv2rgb(float3(hue, 0.35f, 1.0f));
    rgb = mix(rgb, primary, 0.4f);
    return float4(rgb, 0.4f * pow(progress, 2.0f) * mix(pow(abs(sin(angle * 2.5f)), 8.0f), 1.0f, progress));
}

float3 getStarColor(float3 starSurfaceLocation, float seed, float viewDistance, float4 primary, float3 cream) {
    const float DISTANCE_FAR = 20.0f;
    const float DISTANCE_NEAR = 15.0f;
    if (viewDistance > DISTANCE_FAR) {
        return float3(1.0f);
    }
    float fadeToWhite = max(0.0f, (viewDistance - DISTANCE_NEAR) / (DISTANCE_FAR - DISTANCE_NEAR));
    float2 coord = float2(acos(starSurfaceLocation.y), atan2(starSurfaceLocation.z, starSurfaceLocation.x));
    float progress = pow(channel0(fract(0.3f * coord + seed * 1.1f)), 4.0f);
    float3 warm = mix(cream, primary.xyz, progress);
    return mix(warm, float3(1.0f), fadeToWhite);
}

float4 blendColors(float4 front, float4 back) {
    float a = front.a + back.a - front.a * back.a;
    if (a < 1e-5f) {
        return float4(0.0f);
    }
    return float4(mix(back.rgb, front.rgb, front.a / (front.a + back.a)), a);
}

vertex VertexOut starFieldVertex(uint vid [[vertex_id]]) {
    float2 p = float2((vid << 1u) & 2u, vid & 2u);
    VertexOut o;
    o.position = float4(p * float2(2.0f, -2.0f) + float2(-1.0f, 1.0f), 0.0f, 1.0f);
    o.uv = float2(p.x, 1.0f - p.y);
    return o;
}

fragment float4 starFieldFragment(VertexOut vertIn [[stage_in]],
                                  constant StarFieldUniforms &u [[buffer(0)]]) {
    float2 iResolution = u.resolution;
    float iTime = u.time;
    float3 primary = u.primary.xyz;
    float3 background = u.background.xyz;
    float3 accent = u.accent.xyz;
    (void)accent;
    float3 cream = float3(0.96f, 0.94f, 0.92f);

    float2 fragCoord = vertIn.uv * iResolution;
    float3 movementDirection = normalize(float3(0.01f, 0.0f, 1.0f));
    float3 rayDirection = getRayDirection(fragCoord, iResolution, movementDirection);
    float3 directionSign = sign(rayDirection);
    float3 directionBound = float3(0.5f) + 0.5f * directionSign;

    float3 globalPosition = float3(3.14159f, 3.14159f, 0.0f) + (iTime + 1000.0f) * u.flightSpeed * movementDirection;
    int3 chunk = int3(floor(globalPosition));
    float3 localPosition = globalPosition - floor(globalPosition);
    moveInsideBox(localPosition, chunk, directionSign, directionBound);

    int3 startChunk = chunk;
    float3 localStart = localPosition;
    float4 fragColor = float4(0.0f);

    for (int i = 0; i < STARFIELD_MAX_STEPS_CAP; i++) {
        if (i >= u.maxSteps) {
            break;
        }
        move(localPosition, rayDirection, directionBound);
        moveInsideBox(localPosition, chunk, directionSign, directionBound);

        if (hasStar(chunk, u.starThreshold)) {
            float3 starPosition = getStarPosition(chunk, 0.5f * STAR_SIZE);
            float currentDistance = getDistance(chunk - startChunk, localStart, starPosition);

            float3 starToRayVector = getStarToRayVector(localPosition, rayDirection, starPosition);
            float distanceToStar = length(starToRayVector) * 2.0f;

            if (distanceToStar < STAR_SIZE) {
                float starMaxBrightness = clamp((u.drawDistance - currentDistance) / FADEOUT_DISTANCE, 0.001f, 1.0f);
                float starColorSeed = (float(chunk.x) + 13.0f * float(chunk.y) + 7.0f * float(chunk.z)) * 0.00453f;

                if (distanceToStar < STAR_SIZE * STAR_CORE_SIZE) {
                    float3 starSurfaceVector = normalize(starToRayVector + rayDirection * sqrt(pow(STAR_CORE_SIZE * STAR_SIZE, 2.0f) - pow(distanceToStar, 2.0f)));
                    float3 sc = getStarColor(starSurfaceVector, starColorSeed, currentDistance, u.primary, cream);
                    fragColor = blendColors(fragColor, float4(sc, starMaxBrightness));
                    break;
                } else {
                    float localStarDistance = ((distanceToStar / STAR_SIZE) - STAR_CORE_SIZE) / (1.0f - STAR_CORE_SIZE);
                    float angle = atan2(starToRayVector.y, starToRayVector.x);
                    float4 glowColor = getStarGlowColor(localStarDistance, angle, starColorSeed, primary);
                    glowColor.a *= starMaxBrightness;
                    fragColor = blendColors(fragColor, glowColor);
                }
            }
        } else if (hasBlackHole(chunk)) {
            const float3 blackHolePosition = float3(0.5f);
            float currentDistance = getDistance(chunk - startChunk, localStart, blackHolePosition);
            float fadeout = min(1.0f, (u.drawDistance - currentDistance) / FADEOUT_DISTANCE);
            float3 coreToRayVector = getStarToRayVector(localPosition, rayDirection, blackHolePosition);
            float distanceToCore = length(coreToRayVector);
            if (distanceToCore < BLACK_HOLE_CORE_RADIUS * 0.5f) {
                fragColor = blendColors(fragColor, float4(float3(0.0f), fadeout));
                break;
            } else if (distanceToCore < 0.5f) {
                rayDirection = normalize(rayDirection - fadeout * (BLACK_HOLE_DISTORTION / distanceToCore - BLACK_HOLE_DISTORTION / 0.5f) * coreToRayVector / distanceToCore);
            }
        }

        if (length(float3(chunk - startChunk)) > u.drawDistance) {
            break;
        }
    }

    if (fragColor.a < 1.0f) {
        float4 nebula = getNebulaColor(globalPosition, rayDirection, primary, background, u.nebulaLastIndex);
        nebula.rgb = mix(background, nebula.rgb, 0.85f);
        fragColor = blendColors(fragColor, nebula);
    }

    fragColor.rgb = mix(background, fragColor.rgb, saturate(fragColor.a));
    fragColor.a = 1.0f;
    return fragColor;
}
