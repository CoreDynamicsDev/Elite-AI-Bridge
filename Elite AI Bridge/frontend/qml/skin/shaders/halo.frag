#version 440
// Shield halo: a flat ring around the ship. Drawn twice: the back half behind the ship
// art (front = 0, also draws the faint dome) and the front half over it (front = 1).
// mode 0 = UP (glass bubble: equator, latitude rings, rim glow, glint, energy band rising every 2.5 s),
// 1 = DOWN (red, broken, flickering ring), 2 = UNKNOWN (dim, dashed ring).
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec4 color;
    vec2 size;      // item size in px
    vec2 center;    // ring centre, 0..1 of the item
    vec2 radii;     // ring radii, 0..1 of the item
    float domeRy;   // dome height, 0..1 of the item
    float lineW;    // line half-width in px
    float time;
    float mode;
    float front;
};

float hash(float n) { return fract(sin(n * 12.9898) * 43758.5453); }

float ring(vec2 p, vec2 r, float w, out float ang) {
    float e = length(p / r);
    float d = (e - 1.0) / max(fwidth(e), 1e-4);      // distance from the line in px
    ang = atan(p.y / r.y, p.x / r.x);
    return exp(-(d * d) / (w * w)) + 0.35 * exp(-abs(d) / (w * 5.0));
}

void main() {
    vec2 p = (qt_TexCoord0 - center) * size;
    vec2 r = radii * size;
    float ang;
    float line = ring(p, r, lineW, ang);
    float t = ang / 6.2831853 + 0.5;                   // 0..1 around the ring

    // which half this pass draws (smooth seam at the sides)
    float frontMask = smoothstep(-2.0, 2.0, p.y);
    float half_ = mix(1.0 - frontMask, frontMask, front);

    float I = 0.0;
    if (mode < 0.5) {
        // SHIELDS UP: a glass bubble around the ship (see overlay-activity-state.md).
        // Every motion completes whole cycles, so nothing ever jumps.
        float Rv = domeRy * size.y;                    // bubble half-height
        vec2 rb = vec2(r.x, Rv);
        float period = 2.5;                            // energy band, bottom to top
        float ph = fract(time / period);
        float breathe = 0.80 + 0.20 * cos(ph * 6.2831853);
        float lift = front > 0.5 ? 1.0 : 0.6;          // far side dimmer

        // equator: dashed ring with a highlight running round once every 5 s (two band cycles)
        float dash = smoothstep(0.0, 0.08, fract(t * 48.0)) * (1.0 - smoothstep(0.62, 0.70, fract(t * 48.0)));
        float hl = pow(0.5 + 0.5 * cos((t - fract(time * 0.2)) * 6.2831853), 8.0);
        I += line * (0.45 + 0.30 * dash + 1.0 * hl) * half_ * lift * breathe;

        // latitude rings above and below the equator
        for (int k = 0; k < 2; k++) {
            float h = k == 0 ? -0.5 : 0.5;
            vec2 c2 = vec2(0.0, -h * Rv);
            vec2 r2 = r * sqrt(1.0 - h * h);
            float a2;
            float l2 = ring(p - c2, r2, lineW * 0.7, a2);
            float fm = smoothstep(-2.0, 2.0, (p - c2).y);
            I += l2 * mix(1.0 - fm, fm, front) * 0.30 * lift;
        }

        // energy band rising through the bubble, fading in at the bottom and out at the top
        float hb = -0.92 + 1.84 * ph;
        float amp = sin(3.14159265 * ph);
        vec2 cb = vec2(0.0, -hb * Rv);
        vec2 rr = r * sqrt(max(1.0 - hb * hb, 0.0004));
        float ab;
        float lb = ring(p - cb, rr, lineW * 1.1, ab);
        float fmb = smoothstep(-2.0, 2.0, (p - cb).y);
        I += lb * mix(1.0 - fmb, fmb, front) * 1.15 * amp;

        if (front < 0.5) {
            // faint dashed outline and a soft rim glow (clear in the middle)
            float sa;
            float sil = ring(p, rb, lineW * 0.75, sa);
            float st = sa / 6.2831853;
            float sdash = step(0.42, fract(st * 90.0));
            float e = length(p / rb);
            float inside = 1.0 - smoothstep(0.985, 1.0, e);
            I += sil * 0.26 * (0.35 + 0.65 * sdash) * breathe;
            I += inside * smoothstep(0.55, 1.0, e) * 0.10 * breathe;
            // the band's plane, very faint, behind the ship
            I += (1.0 - smoothstep(0.96, 1.0, length((p - cb) / rr))) * 0.045 * amp;
        } else {
            // small glint on the glass, upper left
            vec2 gp = (p - vec2(-0.56 * r.x, -0.62 * Rv)) / (0.035 * r.x);
            I += exp(-dot(gp, gp) * 0.5) * 0.55 * breathe;
            vec2 gp2 = (p - vec2(-0.47 * r.x, -0.70 * Rv)) / (0.016 * r.x);
            I += exp(-dot(gp2, gp2) * 0.5) * 0.35;
        }
    } else if (mode < 1.5) {
        float seg = floor(t * 36.0);
        float on = step(0.42, hash(seg + floor(time * 5.0) * 7.0));
        float flick = 0.55 + 0.45 * hash(floor(time * 17.0));
        I = line * on * flick * 1.1 * half_;
    } else {
        float dash = step(0.5, fract(t * 64.0));
        I = line * dash * 0.28 * half_;
    }
    // fade the glow tails out before the item's edge, so the halo never shows a hard box
    vec2 px = qt_TexCoord0 * size;
    float edge = min(min(px.x, size.x - px.x), min(px.y, size.y - px.y));
    I *= smoothstep(0.0, 0.10 * min(size.x, size.y), edge);
    vec3 col = color.rgb * I;
    fragColor = vec4(col, clamp(I * 0.85, 0.0, 1.0)) * qt_Opacity;
}
