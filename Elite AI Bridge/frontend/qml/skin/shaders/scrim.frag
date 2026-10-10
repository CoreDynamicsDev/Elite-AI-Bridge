#version 440
// Setup wizard: darkens the cockpit except up to four "powered up" regions
// (x, y, w, h in 0..1; w <= 0 = unused), each with a soft edge.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec4 r0;
    vec4 r1;
    vec4 r2;
    vec4 r3;
    float dark;
    float soft;
    float aspect;
};
float lit(vec4 r, vec2 p) {
    if (r.z <= 0.0) return 0.0;
    vec2 d = max(max(r.xy - p, p - (r.xy + r.zw)), vec2(0.0));
    d.x *= aspect;
    return 1.0 - smoothstep(0.0, soft, length(d));
}
void main() {
    vec2 p = qt_TexCoord0;
    float l = max(max(lit(r0, p), lit(r1, p)), max(lit(r2, p), lit(r3, p)));
    float a = dark * (1.0 - l) * qt_Opacity;
    fragColor = vec4(0.0, 0.0, 0.0, a);
}
