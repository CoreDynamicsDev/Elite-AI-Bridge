#version 440
// Soft light spill around a lit rectangle (warning tiles, lit pushbuttons).
// Item = the rectangle grown by 'spread' on every side; only the outside is drawn.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec4 color;
    vec2 size;       // item size in px
    float spread;    // px
    float radius;    // corner radius of the lit shape, px
    float intensity;
};

void main() {
    vec2 q = qt_TexCoord0 * size - size * 0.5;
    vec2 hs = size * 0.5 - vec2(spread);
    vec2 dq = abs(q) - (hs - vec2(radius));
    float dist = length(max(dq, 0.0)) + min(max(dq.x, dq.y), 0.0) - radius;    // signed distance to the shape
    float outside = smoothstep(-1.0, 1.0, dist);
    float g = intensity * (0.6 * exp(-dist / (spread * 0.28)) + 0.4 * exp(-dist / (spread * 0.8))) * outside;
    g *= smoothstep(spread, spread * 0.6, dist);                                 // fade before the item edge
    fragColor = vec4(color.rgb * g, g * 0.5) * qt_Opacity;
}
