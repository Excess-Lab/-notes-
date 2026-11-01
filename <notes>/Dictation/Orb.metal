#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// Сфера надиктовки: стеклянный шар, за ним — четыре полосы света, по одной на полосу частот голоса
// (низкие → высокие). Шар как линза: у края сильнее сжимает то, что за ним, поэтому полосы загибаются;
// каналы цвета преломляются чуть по-разному — радуга на концах. Верх стекла темнее низа, край светится.
// Думает — полосы сворачиваются в кольца, пульсируют и крутятся. Готово — шар заливается зелёным и испаряется вверх.
static float hash(float2 p) { return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453); }
static float noise(float2 p) {
    float2 i = floor(p), f = fract(p);
    float2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + float2(1, 0)), u.x), mix(hash(i + float2(0, 1)), hash(i + float2(1, 1)), u.x), u.y);
}

static float strip(float2 p, float k, float t, float level, float i, float think) {
    float r2 = dot(p, p);
    float2 q = p * (1.0 + k * (1.0 - sqrt(max(0.0, 1.0 - r2))));
    // Слушает — волна поперёк шара.
    float wave = (0.025 + level * 0.3) * sin(q.x * (2.2 + i * 0.7) + t * (1.2 + i * 0.45) + i * 1.7);
    float lineD = q.y - (i - 1.5) * 0.07 - wave;
    float lineW = 0.022 + level * 0.06;
    float lineB = (0.55 + level * 0.9) * smoothstep(1.15, 0.2, abs(q.x));
    // Думает — полосы сворачиваются в кольца: каждое пульсирует и крутится в свою сторону (01.11.2026).
    float ang = atan2(q.y, q.x);
    float dir = fmod(i, 2.0) < 0.5 ? 1.0 : -1.0;
    float radius = 0.36 + i * 0.075 + 0.03 * sin(t * 3.2 + i * 0.9);
    float ringD = length(q) - radius - 0.025 * sin(ang * (3.0 + i) + dir * t * (1.6 + i * 0.4));
    float ringB = 0.45 + 0.75 * pow(0.5 + 0.5 * sin(ang * 2.0 - dir * t * 2.4 + i), 2.0);
    float d = mix(lineD, ringD, think);
    float w = mix(lineW, 0.026, think);
    return mix(lineB, ringB, think) * exp(-d * d / (w * w));
}

static half4 orbAt(float2 position, float4 bounds, float t, float4 bands, float dark, float canvas, float think, float done) {
    float2 p = (position - bounds.xy - bounds.zw * 0.5) / (bounds.w * 0.5 / canvas);
    float fill = saturate(done / 0.3);           // зелёный поднимается снизу
    float vapor = saturate((done - 0.35) / 0.65); // потом шар испаряется
    float3 green = float3(0.2, 0.78, 0.38);
    // Испарение: точки уносит вверх, сильнее там, где шум больше, — получаются струйки.
    // Шум для испарения течёт вверх — струйки пара поднимаются.
    float2 flow = float2(0.0, t * 1.6);
    float n = 0.65 * noise(p * float2(6.0, 3.0) + flow) + 0.35 * noise(p * float2(14.0, 6.0) + flow * 1.8);
    float r = length(p);
    float voice = max(max(bands.x, bands.y), max(bands.z, bands.w));

    if (r > 1.0) {
        float halo = exp(-(r - 1.0) * 5.0) * (0.10 + voice * 0.15) * (1.0 - vapor * vapor);
        float3 c = mix(dark > 0.5 ? float3(1.0) : float3(0.0), green, fill);
        return half4(half3(c * halo), half(halo));
    }

    float y = p.y;
    float3 top = dark > 0.5 ? float3(0.02) : float3(0.18, 0.18, 0.2);
    float3 bottom = dark > 0.5 ? float3(0.16, 0.16, 0.18) : float3(0.78, 0.79, 0.82);
    float3 body = mix(top, bottom, smoothstep(-0.35, 0.55, y));
    float alpha = mix(dark > 0.5 ? 0.55 : 0.75, 0.95, smoothstep(0.6, 1.0, r));

    // Полосы — каждая своим цветом от коралла (низкие) к сиреневому (высокие), каналы — свой коэффициент преломления.
    float3 colors[4] = { float3(0.898, 0.302, 0.2), float3(0.96, 0.55, 0.28), float3(0.93, 0.36, 0.5), float3(0.62, 0.45, 0.95) };
    float3 light = 0.0;
    for (int i = 0; i < 4; i++) {
        float fi = float(i);
        float3 s3 = float3(strip(p, 0.45, t, bands[i], fi, think), strip(p, 0.62, t, bands[i], fi, think), strip(p, 0.85, t, bands[i], fi, think));
        float lum = dot(s3, float3(0.3, 0.5, 0.2));
        light += mix(s3, colors[i] * lum * 1.9 + lum * 0.2, 0.75);
    }

    float fresnel = pow(smoothstep(0.75, 1.0, r), 3.0);
    float rim = fresnel * (dark > 0.5 ? 0.45 : 0.6);
    float glint = exp(-pow((y - 0.8) * 4.0, 2.0)) * smoothstep(0.6, 0.95, r) * 0.25;
    float3 c = body + light * (1.1 + voice * 0.8) + rim + glint;
    float a = min(1.0, alpha + max(light.r, light.b) * 0.5 + rim);

    // Зелёная заливка: уровень жидкости с лёгкой волной идёт снизу вверх.
    float level = mix(1.1, -1.1, fill) + 0.04 * sin(p.x * 7.0 + t * 6.0);
    float wet = smoothstep(-0.03, 0.03, y - level);
    c = mix(c, green * (0.85 + 0.3 * smoothstep(-1.0, 1.0, y)) + rim * 0.6 + glint, wet * 0.95);
    a = mix(a, 1.0, wet);

    // Испарение: прозрачнеет кусками по шуму, края кусков — светлый пар.
    // Испарение: фронт идёт сверху вниз с рваным краем; что выше — уже пар: редкая светлая дымка,
    // которая тает. Без дыр посреди шара — он не «рвётся», а уходит паром (01.11.2026).
    float front = mix(-1.25, 1.25, vapor);
    float keep = smoothstep(front - 0.12, front + 0.12, y + (n - 0.5) * 0.6);
    float steam = (1.0 - keep) * smoothstep(0.45, 0.85, n) * (1.0 - vapor) * fill;
    c = mix(c, float3(0.75, 1.0, 0.82), (1.0 - keep) * fill);
    c += float3(0.6, 1.0, 0.7) * keep * (1.0 - keep) * 2.5 * fill;
    a = a * keep + steam * 0.55;
    a *= smoothstep(1.0, 0.985, r);
    return half4(half3(c * a), half(a));
}

// Для OrbLayer (MTKView): сфера рисуется своим слоем без пересчёта SwiftUI на каждом кадре —
// через .colorEffect в TimelineView она ела ~20 % процессора и подлагивала (31.10.2026).
struct OrbUniforms {
    float2 size;   // в пикселях
    float t;
    float dark;
    float canvas;
    float think;   // 0…1 — распознаёт
    float done;    // 0…1 — ход заливки и испарения
    float pad;
    float4 bands;  // громкость по полосам частот
};

struct OrbVertex { float4 position [[position]]; };

vertex OrbVertex orbVertex(uint id [[vertex_id]]) {
    // Один треугольник на весь экран.
    float2 uv = float2((id << 1) & 2, id & 2);
    OrbVertex out;
    out.position = float4(uv * 2.0 - 1.0, 0, 1);
    return out;
}

fragment half4 orbFragment(OrbVertex in [[stage_in]], constant OrbUniforms &u [[buffer(0)]]) {
    return orbAt(in.position.xy, float4(0, 0, u.size), u.t, u.bands, u.dark, u.canvas, u.think, u.done);
}
