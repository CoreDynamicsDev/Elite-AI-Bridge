#version 440
// Mining page, RHINO panel (2026-10-28). An endless drive across a moon, same look as the asteroid:
// dark phosphor body, bright etched lines, cyan rim, scan sweep. Ray-marched heightfield with a
// flat corridor where the Rhino drives, a wire grid and height contours draped on it, a jagged
// ridge on the horizon and a big ringed planet in the sky. All original, drawn live.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec4 bodyColor;
    vec4 lineColor;
    vec4 rimColor;
    vec4 accentColor;
    float t;          // distance driven (world units)
    float aspect;     // width / height
    float pulse;      // 0..1 glow pulse (rig collected)
    float sweepPos;   // 0..1 scan band, near to far
    float sweepAmt;
    float lit;        // 0.45 parked .. 1.0 driving
};

float hash(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}
float vnoise(vec2 p) {
    vec2 i = floor(p), f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    float a = hash(i), b = hash(i + vec2(1.0, 0.0)), c = hash(i + vec2(0.0, 1.0)), d = hash(i + vec2(1.0, 1.0));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}
float height(vec2 p) {
    float h = vnoise(p * 0.07) * 2.6 + vnoise(p * 0.19 + 7.0) * 0.9 + vnoise(p * 0.55 + 3.0) * 0.18;
    float side = smoothstep(2.3, 5.5, abs(p.x));          // flat track (y = 0) where the Rhino drives and the rigs sit
    // shallow craters
    vec2 cell = floor(p / 9.0);
    vec2 cc = (cell + vec2(hash(cell), hash(cell + 3.1))) * 9.0;
    float r = length(p - cc) / (1.4 + 1.6 * hash(cell + 7.7));
    float crater = r < 1.0 ? (r * r - 1.0) * 0.45 : exp(-pow((r - 1.05) / 0.12, 2.0)) * 0.18;
    return (h - 1.2) * side + crater * side;
}

void main() {
    vec2 uv = qt_TexCoord0;
    vec2 sp = vec2((uv.x - 0.5) * aspect, 0.5 - uv.y);
    vec3 ro = vec3(0.0, 0.95, t);
    vec3 rd = normalize(vec3(sp.x, sp.y - 0.10, 1.25));

    float d = 0.3;
    bool hit = false;
    vec3 p = ro;
    for (int i = 0; i < 72; i++) {
        p = ro + rd * d;
        float diff = p.y - height(p.xz);
        if (diff < 0.004 * d) { hit = true; break; }
        d += max(0.04, diff * 0.55);
        if (d > 70.0) break;
    }

    vec3 col;
    if (hit) {
        float e = 0.06;
        vec3 n = normalize(vec3(height(p.xz - vec2(e, 0.0)) - height(p.xz + vec2(e, 0.0)), 2.0 * e,
                                height(p.xz - vec2(0.0, e)) - height(p.xz + vec2(0.0, e))));
        float diffuse = clamp(dot(n, normalize(vec3(-0.45, 0.75, -0.45))), 0.0, 1.0);
        float fog = exp(-d * 0.05);
        vec2 gp = p.xz * vec2(0.6, 0.6);
        vec2 g = abs(fract(gp) - 0.5) / max(fwidth(gp), vec2(1e-4));
        float grid = 1.0 - clamp(min(g.x, g.y) * 0.9, 0.0, 1.0);
        float hy = p.y * 2.6;
        float cont = 1.0 - clamp(abs(fract(hy) - 0.5) / max(fwidth(hy), 1e-4), 0.0, 1.0);
        float track = exp(-pow(p.x / 1.6, 2.0));
        col = bodyColor.rgb * (0.35 + 1.1 * diffuse) * fog
            + lineColor.rgb * (grid * 0.85 + cont * 0.45) * fog * (0.85 + 0.45 * pulse)
            + lineColor.rgb * track * 0.07 * fog;
        // headlights on the ground just ahead
        col += rimColor.rgb * exp(-pow(p.x / 1.5, 2.0)) * exp(-max(d - 1.5, 0.0) * 0.35) * 0.35 * lit;
        // scan band rolling away from the Rhino
        float band = exp(-pow((d / 30.0 - sweepPos) / 0.035, 2.0)) * sweepAmt;
        col += lineColor.rgb * band * 0.9;
        col = mix(rimColor.rgb * 0.10, col, fog);
    } else {
        // sky: horizon ridge, ringed planet, stars
        vec2 q = rd.xy / rd.z;
        float ridge = 0.035 + 0.06 * vnoise(vec2(q.x * 4.0, 1.0)) + 0.025 * vnoise(vec2(q.x * 15.0, 2.0)) - 0.10;
        col = mix(rimColor.rgb * 0.10, vec3(0.0), clamp((q.y + 0.08) * 3.0, 0.0, 1.0));
        float star = step(0.9975, hash(floor(uv * vec2(260.0 * aspect, 260.0)))) * smoothstep(-0.02, 0.15, q.y);
        col += lineColor.rgb * star * 0.7;
        vec2 c = q - vec2(0.42, 0.20);
        float R = 0.13;
        float rr = length(c);
        if (rr < R) {
            float z = sqrt(max(R * R - rr * rr, 0.0)) / R;
            float bands = 1.0 - clamp(abs(fract(c.y * 34.0 + 0.3 * sin(c.x * 30.0)) - 0.5) / max(fwidth(c.y * 34.0), 1e-4), 0.0, 1.0);
            float lightP = clamp(dot(normalize(vec3(c / R, z)), normalize(vec3(-0.6, 0.5, 0.6))), 0.0, 1.0);
            col = bodyColor.rgb * (0.25 + 1.2 * lightP) + lineColor.rgb * bands * 0.35 * (0.4 + lightP);
            col += rimColor.rgb * pow(1.0 - z, 3.0) * 0.9;
        } else {
            col += rimColor.rgb * exp(-(rr - R) * 60.0) * 0.35;
        }
        // rings: tilted ellipses, the back half hidden behind the planet
        float ca = cos(-0.32), sa = sin(-0.32);
        vec2 rq = vec2(ca * c.x - sa * c.y, sa * c.x + ca * c.y);
        float re = length(rq * vec2(1.0, 4.2)) / R;
        float behind = (rr < R && rq.y > 0.0) ? 0.0 : 1.0;
        for (int k = 0; k < 3; k++) {
            float rad = 1.45 + 0.18 * float(k);
            float w = fwidth(re) * 1.2 + 0.004;
            col += accentColor.rgb * (1.0 - clamp(abs(re - rad) / w, 0.0, 1.0)) * 0.55 * behind;
        }
        // horizon ridge in front of everything
        if (q.y < ridge) {
            float edge = 1.0 - clamp((ridge - q.y) / max(fwidth(q.y) * 1.5, 1e-4), 0.0, 1.0);
            col = bodyColor.rgb * 0.45 + lineColor.rgb * edge * 0.9;
        }
    }
    col *= mix(0.55, 1.0, lit);
    // CRT scanlines, same as the rest of the Bridge glass
    col *= 0.9 + 0.1 * sin(uv.y * 700.0);
    fragColor = vec4(col, 1.0) * qt_Opacity;
}
