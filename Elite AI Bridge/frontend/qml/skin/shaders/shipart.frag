#version 440
// Ship art on the glass. Class art (useAlpha = 1) has a real transparent background, so its own
// alpha is used as-is. Older art without alpha (useAlpha = 0): luminance becomes alpha and a soft
// oval hides the square edge. alarmAmt pulls it toward red. A soft glint band can sweep the hull.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec4 tint;
    vec4 alarm;
    float alarmAmt;
    float lo;
    float hi;
    float gain;
    float useAlpha;
    float glintPos;
    float glintAmt;
};
layout(binding = 1) uniform sampler2D src;

void main() {
    vec2 uv = qt_TexCoord0;
    vec4 t = texture(src, uv);
    vec3 c = t.a > 0.001 ? t.rgb / t.a : vec3(0.0);           // straight colour
    float l = max(c.g, dot(c, vec3(0.30, 0.59, 0.11)));
    float a;
    if (useAlpha > 0.5) {
        a = t.a;
    } else {
        a = smoothstep(lo, hi, l);
        vec2 q = (uv - 0.5) * 2.0;
        a *= 1.0 - smoothstep(0.78, 1.0, length(q * vec2(0.92, 0.80)));
    }
    vec3 col = mix(tint.rgb * l * 1.25, c, 0.45) * gain;
    // glint: a soft diagonal band (runs nose-ward along the hull)
    float band = exp(-pow((uv.x + uv.y * 0.6 - glintPos) / 0.06, 2.0)) * glintAmt;
    col *= 1.0 + band;
    col = mix(col, alarm.rgb * (0.35 + l), alarmAmt);
    fragColor = vec4(col * a, a) * qt_Opacity;
}
