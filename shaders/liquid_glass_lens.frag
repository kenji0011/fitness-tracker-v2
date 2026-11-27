#version 460 core
#include <flutter/runtime_effect.glsl>

// Flutter Impeller ImageFilter.shader port of BitChord / Kyant0's
// RoundedRectRefractionWithDispersion + 45-degree Highlight.Default lens shader.
//
// Features:
// - Exact hemispherical circular dome lens (`circleMap(x) = 1 - sqrt(1 - x^2)`):
//   100% razor-sharp flat optical center + steep curved 12dp magnifying rim.
// - Full 7-band physical prism chromatic dispersion (Red, Orange, Yellow,
//   Green, Cyan, Blue, Purple) weighted by corner quadrant `(x*y)/(halfW*halfH)`
//   so icons/labels split into vivid rainbow caustics cleanly at curved corners.
// - 45-degree directional `Highlight.Default` specular glass rim + Light Mode
//   hairline contour + soft unified SDF contact shadow.
//
// Uniform layout (15 floats):
// - 0, 1: u_size           (auto-populated by Impeller: backdrop size in physical px)
// - 2..6: u_centerX, u_centerY, u_halfW, u_halfH, u_radius (physical px)
// - 7:    u_refractHeight  (12 dp * glassPresence * dpr)
// - 8:    u_refractAmount  (14 dp * material * dpr)
// - 9:    u_depthEffect    (0.0..1.0 subtle 3D radial dome curvature)
// - 10:   u_aberration     (0.0..1.5 7-band chromatic dispersion intensity)
// - 11:   u_rimAlpha       (0.0..1.0 specular rim opacity, sheds during first 55% landing)
// - 12:   u_shadowAlpha    (0.0..1.0 contact shadow opacity)
// - 13:   u_isDark         (0.0 = Light Mode, 1.0 = Dark Mode)
// - 14:   u_material       (0.0..1.0 glass clarity & subtle vibrancy)
uniform vec2 u_size;
uniform float u_centerX;
uniform float u_centerY;
uniform float u_halfW;
uniform float u_halfH;
uniform float u_radius;
uniform float u_refractHeight;
uniform float u_refractAmount;
uniform float u_depthEffect;
uniform float u_aberration;
uniform float u_rimAlpha;
uniform float u_shadowAlpha;
uniform float u_isDark;
uniform float u_material;

uniform sampler2D u_texture_input;

out vec4 frag_color;

float sdRoundedRect(vec2 p, vec2 halfSize, float radius) {
    vec2 cornerCoord = abs(p) - (halfSize - vec2(radius));
    float outside = length(max(cornerCoord, vec2(0.0))) - radius;
    float inside = min(max(cornerCoord.x, cornerCoord.y), 0.0);
    return outside + inside;
}

vec2 gradSdRoundedRect(vec2 p, vec2 halfSize, float radius) {
    vec2 cornerCoord = abs(p) - (halfSize - vec2(radius));
    if (cornerCoord.x >= 0.0 || cornerCoord.y >= 0.0) {
        vec2 clamped = max(cornerCoord, vec2(0.0));
        float len = length(clamped);
        vec2 dir = (len > 0.0001) ? (clamped / len) : vec2(0.70710678, 0.70710678);
        return sign(p) * dir;
    } else {
        float gradX = step(cornerCoord.y, cornerCoord.x);
        return sign(p) * vec2(gradX, 1.0 - gradX);
    }
}

float circleMap(float x) {
    float cx = clamp(x, 0.0, 0.9995);
    return 1.0 - sqrt(max(1.0 - cx * cx, 0.0));
}

vec2 toTexUv(vec2 px) {
    vec2 uv = clamp(px / max(u_size, vec2(1.0)), vec2(0.001), vec2(0.999));
#ifdef IMPELLER_TARGET_OPENGLES
    uv.y = 1.0 - uv.y;
#endif
    return uv;
}

vec3 sampleRgb(vec2 px) {
    vec4 s = texture(u_texture_input, toTexUv(px));
    return s.a > 0.001 ? (s.rgb / s.a) : s.rgb;
}

void main() {
    vec2 coord = FlutterFragCoord().xy;
    vec4 baseSample = texture(u_texture_input, toTexUv(coord));

    if (u_halfW <= 0.5 || u_halfH <= 0.5 ||
        (u_refractHeight <= 0.05 && u_rimAlpha <= 0.004 && u_shadowAlpha <= 0.004)) {
        frag_color = baseSample;
        return;
    }

    vec2 halfSize = vec2(u_halfW, u_halfH);
    float radius = min(u_radius, min(halfSize.x, halfSize.y));
    vec2 p = coord - vec2(u_centerX, u_centerY);
    float sd = sdRoundedRect(p, halfSize, radius);

    // Contact shadow margin scaled gracefully for pills, sliders, and lifted cards
    float shadowSpread = min(max(halfSize.y * 0.42, 12.0), max(u_refractHeight * 1.65, 16.0));
    float shadowOffsetY = min(max(halfSize.y * 0.07, 2.0), max(u_refractHeight * 0.30, 3.0));
    if (sd > shadowSpread + shadowOffsetY + 2.0) {
        frag_color = baseSample;
        return;
    }

    // Crisp 1.4px anti-aliased edge coverage
    float cov = clamp(0.5 - sd / 1.4, 0.0, 1.0);

    // Soft contact shadow directly under the lifted crystal lens
    vec4 shadowedBase = baseSample;
    if (cov < 0.999 && u_shadowAlpha > 0.004) {
        float sdShadow = sdRoundedRect(p - vec2(0.0, shadowOffsetY), halfSize, radius);
        float shadowMask = 1.0 - smoothstep(-2.0, shadowSpread, sdShadow);
        float alpha = (u_isDark > 0.5 ? 0.34 : 0.115) * u_shadowAlpha;
        shadowedBase = vec4(baseSample.rgb * (1.0 - shadowMask * alpha), baseSample.a);
    }

    if (cov <= 0.004) {
        frag_color = shadowedBase;
        return;
    }

    // Analytical SDF gradient matching Kyant0/backdrop (gradRadius = min(r*1.5, minDim/2))
    float gradRadius = min(radius * 1.5, min(halfSize.x, halfSize.y));
    vec2 rawGrad = gradSdRoundedRect(p, halfSize, gradRadius);
    float cLen = length(p);
    vec2 radial = (cLen > 0.001) ? (p / cLen) : vec2(0.0);
    vec2 combinedGrad = rawGrad + u_depthEffect * radial;
    float gLen = length(combinedGrad);
    vec2 grad = (gLen > 0.0001) ? (combinedGrad / gLen) : vec2(0.0, -1.0);

    // Inside the crystal-clear flat center (-sd >= u_refractHeight), pass sharp pixels;
    // within the curved optical rim (-sd < u_refractHeight), apply BitChord's circular
    // dome refraction + 7-band full-spectrum corner dispersion!
    vec3 col;
    float clampedSd = min(sd, 0.0);
    if (u_refractHeight > 0.5 && u_refractAmount > 0.1 && (-clampedSd) < u_refractHeight) {
        float rimT = clamp(1.0 - (-clampedSd) / u_refractHeight, 0.0, 1.0);
        // Negative amount pulls outer pixels inward, magnifying/bending around rim
        float d = circleMap(rimT) * (-u_refractAmount);
        vec2 refractedCoord = coord + d * grad;

        if (u_aberration > 0.01) {
            float dispIntensity = u_aberration *
                ((p.x * p.y) / max(halfSize.x * halfSize.y, 1.0));
            vec2 dispCoord = d * grad * dispIntensity;

            vec3 cRed    = sampleRgb(refractedCoord + dispCoord);
            vec3 cOrange = sampleRgb(refractedCoord + dispCoord * (2.0 / 3.0));
            vec3 cYellow = sampleRgb(refractedCoord + dispCoord * (1.0 / 3.0));
            vec3 cGreen  = sampleRgb(refractedCoord);
            vec3 cCyan   = sampleRgb(refractedCoord - dispCoord * (1.0 / 3.0));
            vec3 cBlue   = sampleRgb(refractedCoord - dispCoord * (2.0 / 3.0));
            vec3 cPurple = sampleRgb(refractedCoord - dispCoord);

            col = vec3(
                (cRed.r + cOrange.r + cYellow.r) / 3.5 + cPurple.r / 7.0,
                cOrange.g / 7.0 + (cYellow.g + cGreen.g + cCyan.g) / 3.5,
                (cCyan.b + cBlue.b + cPurple.b) / 3.0
            );
        } else {
            col = sampleRgb(refractedCoord);
        }
    } else {
        col = baseSample.a > 0.001 ? (baseSample.rgb / baseSample.a) : baseSample.rgb;
    }

    // Gentle vibrancy boost matching BitChord's optical glass saturation polish
    float lum = dot(col, vec3(0.2126, 0.7152, 0.0722));
    float satNow = max(col.r, max(col.g, col.b)) - min(col.r, min(col.g, col.b));
    float satRoom = 1.0 - smoothstep(0.20, 0.85, satNow);
    float hlGuard = 1.0 - smoothstep(0.78, 0.98, lum);
    float satFactor = 1.0 + 0.22 * u_material * mix(0.25, 1.0, satRoom * hlGuard);
    col = clamp(mix(vec3(lum), col, satFactor), 0.0, 1.0);

    // BitChord 45-degree Highlight.Default directional specular rim
    if (u_rimAlpha > 0.004) {
        float hair = clamp(1.0 - abs(sd + 1.1) / 2.2, 0.0, 1.0);
        float innerGlow = clamp((-sd - 0.5) / 2.5, 0.0, 1.0) *
                          pow(clamp(1.0 - (-sd - 1.5) / max(u_refractHeight * 0.48, 3.0), 0.0, 1.0), 1.6);
        vec2 hlDir = vec2(0.70710678, 0.70710678);
        float hlIntensity = pow(abs(dot(rawGrad, hlDir)), 1.15);

        float specGain = (u_isDark > 0.5 ? 0.86 : 0.78) * u_rimAlpha;
        float spec = (hair * (0.24 + 0.76 * hlIntensity) + innerGlow * 0.14 * hlIntensity) * specGain;

        // Subtle outer dark contour in Light Mode keeps the crystal lens edge crisp on white cards
        float brightBg = smoothstep(0.68, 0.96, lum) * (1.0 - u_isDark);
        float contour = hair * (0.115 * brightBg + (u_isDark > 0.5 ? 0.0 : 0.035)) * u_rimAlpha;
        col = col * (1.0 - contour) + vec3(spec);
    }

    col = clamp(col, 0.0, 1.0);
    frag_color = mix(shadowedBase, vec4(col, 1.0), cov);
}
