#version 460 core
#include <flutter/runtime_effect.glsl>

// Flutter Impeller ImageFilter.shader uniforms:
// - Index 0, 1: u_size       (auto-filled by Impeller: full backdrop texture size in physical px)
// - Index 2:    u_rectLeft   (droplet global left in physical px)
// - Index 3:    u_rectTop    (droplet global top in physical px)
// - Index 4:    u_rectWidth  (droplet width in physical px)
// - Index 5:    u_rectHeight (droplet height in physical px)
// - Index 6:    u_expansion  (0.0 = off, 1.0 = full interactive Liquid Glass droplet)
// - Index 7:    u_bevel      (bevel width in physical px)
// - Index 8:    u_refract    (refraction offset in physical px)
// - Index 9:    u_dispersion (chromatic RGB dispersion factor)
// - Index 10:   u_isDark     (0.0 = Light Mode, 1.0 = Dark Mode)
// - Index 11:   u_press      (0.0..1.0 drag/press intensity)
uniform vec2 u_size;
uniform float u_rectLeft;
uniform float u_rectTop;
uniform float u_rectWidth;
uniform float u_rectHeight;
uniform float u_expansion;
uniform float u_bevel;
uniform float u_refract;
uniform float u_dispersion;
uniform float u_isDark;
uniform float u_press;

uniform sampler2D u_texture_input;

out vec4 frag_color;

float sdRoundedBox(vec2 p, vec2 b, float r) {
    vec2 q = abs(p) - b + r;
    return length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - r;
}

vec2 toTexUv(vec2 px) {
    vec2 uv = clamp(px / max(u_size, vec2(1.0)), vec2(0.001), vec2(0.999));
#ifdef IMPELLER_TARGET_OPENGLES
    uv.y = 1.0 - uv.y;
#endif
    return uv;
}

void main() {
    vec2 coord = FlutterFragCoord().xy;

    // Exact droplet rect in physical screen coordinates
    vec2 rectMin = vec2(u_rectLeft, u_rectTop);
    vec2 rectSize = max(vec2(u_rectWidth, u_rectHeight), vec2(2.0));
    vec2 halfSize = rectSize * 0.5;
    vec2 center = rectMin + halfSize;
    vec2 p = coord - center;
    float radius = min(halfSize.x, halfSize.y);

    float d = sdRoundedBox(p, halfSize, radius);

    // Anti-aliased SDF coverage; outside the droplet return untouched backdrop pixel
    float cov = clamp(0.5 - d / 1.5, 0.0, 1.0);
    if (cov <= 0.004 || u_expansion <= 0.004) {
        frag_color = texture(u_texture_input, toTexUv(coord));
        return;
    }

    // Screen-space outward normal via SDF gradient (GlassLensRenderer.kt)
    vec2 n = vec2(
        sdRoundedBox(p + vec2(1.0, 0.0), halfSize, radius) -
        sdRoundedBox(p - vec2(1.0, 0.0), halfSize, radius),
        sdRoundedBox(p + vec2(0.0, 1.0), halfSize, radius) -
        sdRoundedBox(p - vec2(0.0, 1.0), halfSize, radius)
    );
    float nLen = length(n);
    n = (nLen > 0.0001) ? (n / nLen) : vec2(0.0, -1.0);

    // Optical thickness profile: flat crystal-clear center (t=1), curved refractive bevel (t=0)
    float bevelW = max(u_bevel, 2.0);
    float t = clamp(-d / bevelW, 0.0, 1.0);
    float gB = pow(5.0, -2.0);
    float slope = (pow(1.0 + 4.0 * t, -2.0) - gB) / (1.0 - gB);

    // Subtle magnifying droplet center pull + inward bevel refraction along normal
    vec2 centerMagOffset = -p * (0.04 * u_expansion);
    float refr = u_refract * u_expansion * (1.0 + 0.5 * u_press);
    vec2 offset = centerMagOffset - n * (slope * refr);

    // Chromatic RGB dispersion along refraction bevel (blue bends more than red)
    float disp = u_dispersion * u_expansion;
    vec2 cR = coord + offset * (1.0 - disp * slope);
    vec2 cG = coord + offset;
    vec2 cB = coord + offset * (1.0 + disp * slope);

    vec4 sR = texture(u_texture_input, toTexUv(cR));
    vec4 sG = texture(u_texture_input, toTexUv(cG));
    vec4 sB = texture(u_texture_input, toTexUv(cB));

    vec3 col = vec3(
        sR.a > 0.001 ? sR.r / sR.a : sR.r,
        sG.a > 0.001 ? sG.g / sG.a : sG.g,
        sB.a > 0.001 ? sB.b / sB.a : sB.b
    );

    // Non-linear Apple Vibrancy saturation boost
    float satFactor = mix(1.0, 1.22, u_expansion);
    float lum = dot(col, vec3(0.2126, 0.7152, 0.0722));
    float satNow = max(col.r, max(col.g, col.b)) - min(col.r, min(col.g, col.b));
    float room = 1.0 - smoothstep(0.2, 0.85, satNow);
    float hl = 1.0 - smoothstep(0.75, 0.98, lum);
    float amount = 1.0 + (satFactor - 1.0) * mix(0.3, 1.0, room * hl);
    col = clamp(mix(vec3(lum), col, amount), 0.0, 1.0);

    // Pure crystal-clear transparent glass center; subtle neutral highlight only on curved bevel
    float bodyTintAlpha = (u_isDark > 0.5 ? 0.05 : 0.06) * u_expansion;
    vec3 bodyTintColor = vec3(1.0);
    col = mix(col, bodyTintColor, bodyTintAlpha * slope);

    // Two-lobe angle-dependent specular rim reflection (GlassLensRenderer.kt)
    vec2 lightDir = normalize(vec2(0.62, 0.78));
    float facing = dot(n, -lightDir);
    float lobeF = pow(max(facing, 0.0), 4.2);
    float lobeB = pow(max(-facing, 0.0), 4.2);

    float bandW = clamp(bevelW * 0.35, 2.5, 10.0);
    float glowIn = clamp((-d - 1.0) / 2.5, 0.0, 1.0);
    float glow = glowIn * pow(clamp(1.0 - (-d - 3.0) / bandW, 0.0, 1.0), 1.5);
    float hair = clamp(1.0 - abs(d + 1.2) / 2.2, 0.0, 1.0);

    float specStrength = (u_isDark > 0.5 ? 0.92 : 0.76) * u_expansion;
    float spec = (hair * 0.75 * (lobeF + lobeB) + glow * 0.15 * lobeF) * specStrength;

    // On bright light-mode surfaces, subtle dark contour on rim keeps droplet edge crisp
    float brightBg = smoothstep(0.76, 0.97, lum) * (1.0 - u_isDark);
    float rimContour = hair * 0.16 * brightBg * u_expansion;
    col = col * (1.0 - rimContour) + vec3(spec);

    col = clamp(col, 0.0, 1.0);

    // Smooth blend with underlying untouched pixel at the 1.5px anti-aliased edge
    vec4 baseSample = texture(u_texture_input, toTexUv(coord));
    vec4 glassOut = vec4(col, 1.0);
    frag_color = mix(baseSample, glassOut, cov);
}
