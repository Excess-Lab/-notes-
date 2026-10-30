#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// Сфера надиктовки: стеклянный шар, за ним — полоса света. Шар как линза: ближе к краю сильнее
// сжимает то, что за ним, поэтому полоса у края загибается; каналы цвета преломляются чуть по-разному —
// отсюда радуга на концах. Верх стекла темнее низа, край светится (Френель).
static float band(float2 p, float k, float t, float voice) {
    float r2 = dot(p, p);
    float lens = 1.0 + k * (1.0 - sqrt(max(0.0, 1.0 - r2)));
    float2 q = p * lens;
    float wave = (0.04 + voice * 0.2) * sin(q.x * 2.6 + t * 1.3) + 0.03 * sin(t * 0.7);
    float width = 0.035 + voice * 0.09;
    float d = q.y - wave;
    return exp(-d * d / (width * width)) * smoothstep(1.15, 0.2, abs(q.x));
}

[[ stitchable ]] half4 orb(float2 position, half4 color, float4 bounds, float t, float voice, float dark) {
    float2 p = (position - bounds.xy - bounds.zw * 0.5) / (bounds.w * 0.5 / 1.3);
    float r = length(p);

    // Ореол за пределами шара.
    if (r > 1.0) {
        float halo = exp(-(r - 1.0) * 5.0) * (0.10 + voice * 0.12);
        float3 c = dark > 0.5 ? float3(1.0) : float3(0.0);
        return half4(half3(c * halo), half(halo));
    }

    // Тело стекла: верх темнее, низ светлее; в тёмной теме всё глубже.
    float y = p.y;
    float3 top = dark > 0.5 ? float3(0.02) : float3(0.18, 0.18, 0.2);
    float3 bottom = dark > 0.5 ? float3(0.16, 0.16, 0.18) : float3(0.78, 0.79, 0.82);
    float3 body = mix(top, bottom, smoothstep(-0.35, 0.55, y));
    float alpha = mix(dark > 0.5 ? 0.55 : 0.75, 0.95, smoothstep(0.6, 1.0, r));

    // Полоса света, по каналу на свой коэффициент преломления.
    float3 light = float3(band(p, 0.45, t, voice), band(p, 0.62, t, voice), band(p, 0.85, t, voice));
    light += 0.35 * float3(band(p * float2(1.0, 0.5), 0.6, t, voice)); // мягкое свечение вокруг полосы

    // Край: светлый ободок и блик снизу.
    float fresnel = pow(smoothstep(0.75, 1.0, r), 3.0);
    float rim = fresnel * (dark > 0.5 ? 0.45 : 0.6);
    float glint = exp(-pow((y - 0.8) * 4.0, 2.0)) * smoothstep(0.6, 0.95, r) * 0.25;

    float3 c = body + light * (1.2 + voice * 1.2) + rim + glint;
    float edge = smoothstep(1.0, 0.985, r);
    float a = min(1.0, alpha + max(light.r, light.b) * 0.6 + rim) * edge;
    return half4(half3(c * a), half(a));
}
