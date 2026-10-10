#version 440
// Elite AI Bridge: CRT look for one screen (proof of concept).
// staticAmt: film grain, flicker, rolling scan bar.  fxAmt: scanlines, glow, curve, colour edges.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float time;
    float staticAmt;
    float fxAmt;
    vec2 res;
};
layout(binding = 1) uniform sampler2D src;

float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }

void main() {
    vec2 uv = qt_TexCoord0;
    // static strength curve: gentle at the low end, much stronger near 100%
    float s = staticAmt * (0.35 + 0.85 * staticAmt);   // 50% = same as before, 100% = about twice as strong
    // barrel curvature, scaled down on short screens so text stays straight
    vec2 c = uv * 2.0 - 1.0;
    float k = 0.035 * fxAmt * min(1.0, res.y / 480.0);
    vec2 w = c * (1.0 + k * dot(c, c)) / (1.0 + k * 2.0);
    uv = w * 0.5 + 0.5;
    if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) { fragColor = vec4(0.0, 0.0, 0.0, qt_Opacity); return; }

    vec2 px = 1.0 / res;
    // interference: at high static, thin bands of lines jitter sideways for a moment
    float band = floor(uv.y * res.y / 3.0);
    float jit = hash(vec2(band, floor(time * 18.0))) - 0.5;
    float burst = step(0.985, hash(vec2(floor(uv.y * 14.0), floor(time * 6.0))));
    uv.x += jit * px.x * 6.0 * max(0.0, s - 0.5) * (0.35 + burst);

    // colour edges: red and blue split slightly toward the corners
    vec2 off = w * px * 1.2 * fxAmt;
    vec3 col;
    col.r = texture(src, uv + off).r;
    col.g = texture(src, uv).g;
    col.b = texture(src, uv - off).b;

    // phosphor glow: cheap 8-tap halo of the bright parts
    vec3 halo = vec3(0.0);
    float r = 2.5;
    halo += texture(src, uv + px * vec2( r, 0)).rgb;
    halo += texture(src, uv + px * vec2(-r, 0)).rgb;
    halo += texture(src, uv + px * vec2(0,  r)).rgb;
    halo += texture(src, uv + px * vec2(0, -r)).rgb;
    halo += texture(src, uv + px * vec2( r*1.8,  r*1.8)).rgb;
    halo += texture(src, uv + px * vec2(-r*1.8,  r*1.8)).rgb;
    halo += texture(src, uv + px * vec2( r*1.8, -r*1.8)).rgb;
    halo += texture(src, uv + px * vec2(-r*1.8, -r*1.8)).rgb;
    halo /= 8.0;
    col += max(halo - 0.25, 0.0) * 0.9 * fxAmt;

    // scanlines every 3 device pixels
    float line = 0.5 + 0.5 * cos(uv.y * res.y * 2.0944);
    col *= 1.0 - 0.28 * fxAmt * line;

    // static: grain, a little flicker, slow rolling scan bar
    float g = hash(floor(uv * res) + fract(time * 7.3) * 113.0) - 0.5;
    col += vec3(0.75, 1.0, 0.8) * g * 0.24 * s;          // grain, tinted like the phosphor
    col += vec3(0.45, 1.0, 0.55) * max(g, 0.0) * 0.10 * s; // 'snow' so grain also shows on dark glass
    col *= 1.0 - 0.03 * s * hash(vec2(floor(time * 24.0), 3.1));
    float bar = fract(time * 0.11);
    float d = abs(uv.y - bar);
    col += vec3(0.065, 0.145, 0.08) * s * smoothstep(0.07, 0.0, d);

    // vignette
    col *= 1.0 - 0.32 * dot(w, w) * 0.5;

    fragColor = vec4(clamp(col, 0.0, 1.0), 1.0) * qt_Opacity;
}
