#version 440
// Mining page asteroid. The atlas holds data, not colour: R diffuse, G etched lines, B crack, A coverage.
// Rim and outer glow come from the coverage around each pixel. sweep: a scan band (0..1 across).
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec4 bodyColor;
    vec4 lineColor;
    vec4 rimColor;
    vec4 crackColor;
    float frame;
    float cols;
    float rows;
    float cell;
    float crackAmt;
    float sweepPos;
    float sweepAmt;
    float pulse;
};
layout(binding = 1) uniform sampler2D atlas;

vec2 cellOf(float f) {
    f = mod(f, cols * rows);
    return vec2(mod(f, cols), floor(f / cols));
}
vec2 cA; vec2 cB; float mixAmt;
// samples the current frame blended into the next, so the turn is continuous
vec4 tap(vec2 cellOrigin, vec2 uv) {
    vec2 q = clamp(uv, vec2(0.0), vec2(1.0));
    vec4 a = texture(atlas, (cA + q) / vec2(cols, rows));
    vec4 b = texture(atlas, (cB + q) / vec2(cols, rows));
    return mix(a, b, mixAmt);
}

void main() {
    float f0 = floor(frame);
    cA = cellOf(f0);
    cB = cellOf(f0 + 1.0);
    mixAmt = smoothstep(0.0, 1.0, frame - f0);
    vec2 origin = cA;
    vec2 uv = qt_TexCoord0;
    vec4 t = tap(origin, uv);
    float a = t.a;
    vec3 d = a > 0.001 ? t.rgb / a : vec3(0.0);       // Qt textures are premultiplied
    float px = 1.0 / cell;
    float mn = 1.0;
    float glow = 0.0;
    for (int i = 0; i < 8; i++) {
        float ang = 0.785398 * float(i);
        vec2 dir = vec2(cos(ang), sin(ang));
        mn = min(mn, tap(origin, uv + dir * px * 2.0).a);
        glow += tap(origin, uv + dir * px * 5.0).a + tap(origin, uv + dir * px * 10.0).a * 0.6;
    }
    glow = glow / 12.8;
    float rim = clamp(a - mn, 0.0, 1.0);
    float band = exp(-pow((uv.x * 0.85 + uv.y * 0.15 - sweepPos) / 0.035, 2.0)) * sweepAmt;
    vec3 col = bodyColor.rgb * d.r * 1.6
             + lineColor.rgb * d.g * (0.9 + 0.5 * pulse + band * 1.5)
             + crackColor.rgb * d.b * crackAmt * (0.8 + 0.6 * pulse)
             + rimColor.rgb * rim * 1.1
             + lineColor.rgb * band * 0.35;
    vec3 outC = col * a + rimColor.rgb * glow * (1.0 - a) * (0.55 + 0.25 * pulse);
    float outA = max(a, glow * (1.0 - a) * 0.8);
    fragColor = vec4(outC, outA) * qt_Opacity;
}
