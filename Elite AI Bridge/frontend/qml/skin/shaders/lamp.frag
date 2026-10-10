#version 440
// Panel lamp: domed glass lens in a metal bezel, with real light spill around it.
// The item is 3.2x the lamp diameter so the glow can fall onto the plate.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec4 core;      // lit colour
    vec4 deep;      // edge colour
    float lit;      // 0 off .. 1 on
    float px;       // one pixel in p units (for anti-aliasing)
};

void main() {
    vec2 p = (qt_TexCoord0 - 0.5) * 2.0;     // -1..1 across the whole item
    float R = 1.0 / 3.2;                     // lens radius
    float rb = R * 1.30;                     // bezel outer radius
    float r = length(p);
    float d = r / R;
    vec3 col = vec3(0.0);
    float a = 0.0;

    // light spill on the panel (premultiplied, so it adds light)
    float spill = lit * (0.75 * exp(-(r - R) / (R * 0.45)) + 0.30 * exp(-(r - R) / (R * 1.3)));
    spill *= smoothstep(R * 0.9, rb, r) * smoothstep(1.0, 0.55, r);   // reaches zero before the item edge
    col += core.rgb * spill;
    a += spill * 0.55;

    // metal bezel ring
    float ringMask = smoothstep(rb + px, rb - px, r) * smoothstep(R - px, R + px, r);
    if (ringMask > 0.0) {
        vec2 n = normalize(p);
        float shade = 0.30 + 0.30 * dot(n, normalize(vec2(-0.6, -0.8)));          // lit from upper left
        float inner = smoothstep(R, R * 1.08, r);                                   // dark lip next to the glass
        vec3 metal = vec3(shade * 0.95, shade * 0.93, shade * 0.86) * (0.35 + 0.65 * inner);
        metal += core.rgb * lit * 0.18 * (1.0 - inner);                             // lens light on the lip
        col = mix(col, metal, ringMask);
        a = mix(a, 1.0, ringMask);
    }

    // glass dome
    float lensMask = smoothstep(R + px, R - px, r);
    if (lensMask > 0.0) {
        float z = sqrt(max(0.0, 1.0 - d * d));                                      // dome height
        vec3 on = mix(deep.rgb, core.rgb, pow(z, 0.55));
        on = mix(on, vec3(1.0), smoothstep(0.55, 0.0, d) * 0.55);                   // hot centre
        vec3 off = mix(deep.rgb * 0.18, core.rgb * 0.22, z) + vec3(0.03);           // dark tinted glass
        vec3 glass = mix(off, on, lit);
        glass *= 0.72 + 0.28 * z;                                                   // edge falls off
        vec2 hp = p / R - vec2(-0.38, -0.42);
        float spec = pow(max(0.0, 1.0 - length(hp * vec2(1.0, 1.4)) / 0.42), 2.2);  // window reflection
        glass += vec3(spec) * (0.55 + 0.25 * (1.0 - lit));
        float rim = smoothstep(0.78, 1.0, d) * (1.0 - lit) * 0.25;                  // fresnel rim when off
        glass += vec3(rim);
        col = mix(col, glass, lensMask);
        a = mix(a, 1.0, lensMask);
    }
    fragColor = vec4(col, a) * qt_Opacity;
}
