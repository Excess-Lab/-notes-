#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// Зона «перетащи» в видео — кадр 151:32745: ребристое стекло из планок по 20 px, как в шапке, а за ним
// вместо картинки живой фон — тёплые пятна медленно плывут, как размытое видео (Макар: «на фон какое-то
// видео… придумай, чтобы красиво было»). Над зоной держат файл (on → 1) — пятна ярче и быстрее.

// Фон «видео»: основа по теме и три пятна — коралл, янтарь, сирень.
static float3 footage(float2 p, float t, float on, float dark) {
    float speed = 0.25 + on * 0.35;
    float2 a = float2(0.25 + 0.2 * sin(t * speed * 0.9), 0.5 + 0.35 * cos(t * speed * 0.7));
    float2 b = float2(0.7 + 0.2 * cos(t * speed * 0.6 + 1.3), 0.45 + 0.4 * sin(t * speed * 0.8 + 0.4));
    float2 c = float2(0.5 + 0.35 * sin(t * speed * 0.5 + 2.1), 0.6 + 0.3 * cos(t * speed * 1.1 + 2.7));
    float ga = exp(-dot(p - a, p - a) * 9.0) * 0.9, gb = exp(-dot(p - b, p - b) * 11.0) * 0.55, gc = exp(-dot(p - c, p - c) * 14.0) * 0.35;
    float3 coral = float3(0.898, 0.302, 0.2), amber = float3(0.95, 0.62, 0.25), lilac = float3(0.55, 0.42, 0.9);
    // Тёмная тема — пятна светятся поверх чёрного.
    float3 night = float3(0.03, 0.03, 0.035) + coral * ga + amber * gb + lilac * gc;
    night *= 0.55 + on * 0.6;
    // Светлая — белый лист, пятна ложатся краской, а не светом (сложение на белом дало бы просто белое).
    float3 day = float3(0.96, 0.96, 0.965);
    float k = 0.35 + on * 0.3;
    day = mix(day, coral, saturate(ga * k));
    day = mix(day, amber, saturate(gb * k));
    day = mix(day, lilac, saturate(gc * k));
    return mix(day, night, dark);
}

[[stitchable]] half4 dropzone(float2 position, half4 color, float4 bounds, float t, float on, float dark) {
    float slat = 20.0;
    float local = fmod(position.x, slat);
    float center = position.x - local + slat * 0.5;
    // Планка — линза: увеличивает то, что под ней, в 1,8 раза по горизонтали.
    float x = center + (local - slat * 0.5) / 1.8;
    float2 uv = float2(x, position.y) / bounds.zw;
    // Матовость: среднее по нескольким точкам по вертикали.
    float3 col = 0.0;
    for (int i = -2; i <= 2; i++) {
        float2 q = uv + float2(0.0, float(i) * 0.02);
        col += footage(q, t, on, dark);
    }
    col /= 5.0;
    // Края планок: слева светлая грань, справа тень — как на кадре.
    float edge = local / slat;
    col += mix(0.03, 0.06, dark) * smoothstep(0.12, 0.0, edge);
    col *= 1.0 - mix(0.08, 0.25, dark) * smoothstep(0.7, 1.0, edge);
    // Чёрный 15 % поверх, как фон кадра; в светлой теме не темним.
    col *= mix(1.0, 0.85, dark);
    return half4(half3(col), 1.0) * color.a;
}
