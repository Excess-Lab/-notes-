#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// Зона «перетащи» в видео: тихие коралловые волны текут слева направо; когда над зоной держат файл,
// волны ярче и сходятся к центру — зона «тянет» файл к себе. on — 0…1, плавно.
[[stitchable]] half4 dropzone(float2 position, half4 color, float4 bounds, float t, float on) {
    float2 uv = (position - bounds.xy) / bounds.zw;
    float2 c = uv - 0.5;
    c.x *= bounds.z / bounds.w;
    float d = length(c);
    float drift = sin(uv.x * 9.0 - t * 1.2 + sin(uv.y * 4.0 + t * 0.6) * 1.5) * 0.5 + 0.5;
    float pull = sin(d * 18.0 + t * 4.0) * 0.5 + 0.5;
    float wave = mix(drift, pull, on);
    float fade = smoothstep(0.0, 0.25, uv.y) * smoothstep(1.0, 0.75, uv.y);
    float alpha = wave * fade * mix(0.06, 0.22, on);
    half3 coral = half3(229.0 / 255.0, 77.0 / 255.0, 51.0 / 255.0);
    return half4(coral * alpha, alpha) * color.a;
}
