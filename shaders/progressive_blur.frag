#version 460 core
#include <flutter/runtime_effect.glsl>

// Single-pass continuous progressive Gaussian-disk backdrop blur + smooth
// scaffold scrim blend for pinned top sliver headers (TempoSliverHeader).
//
// Eliminates hard horizontal band seams completely: both the blur radius
// (`smoothT^2`) and the translucent scaffold scrim (`smoothT`) decay with zero
// C1 derivative to exact 0.0 before reaching `u_bottomPx`, returning unaltered
// crisp pixels cleanly above the clip edge.
//
// Uniform layout (10 floats):
// - 0, 1: u_size        (auto-populated by Impeller: physical backdrop px)
// - 2:    u_topPx       (physical Y of header top)
// - 3:    u_bottomPx    (physical Y where blur & scrim hit exact 0.0)
// - 4:    u_maxBlurPx   (peak blur disk radius in physical px at top)
// - 5..7: u_scrimR/G/B  (scaffold tint color channels, 0.0..1.0)
// - 8:    u_scrimAlpha  (peak scaffold tint opacity at top, 0.0..1.0)
// - 9:    u_softKnee    (normalized height 0..0.7 where smooth decay begins)
uniform vec2 u_size;
uniform float u_topPx;
uniform float u_bottomPx;
uniform float u_maxBlurPx;
uniform float u_scrimR;
uniform float u_scrimG;
uniform float u_scrimB;
uniform float u_scrimAlpha;
uniform float u_softKnee;

uniform sampler2D u_texture_input;

out vec4 frag_color;

vec2 toTexUv(vec2 px) {
    vec2 uv = clamp(px / max(u_size, vec2(1.0)), vec2(0.001), vec2(0.999));
#ifdef IMPELLER_TARGET_OPENGLES
    uv.y = 1.0 - uv.y;
#endif
    return uv;
}

void main() {
    vec2 coord = FlutterFragCoord().xy;
    vec4 base = texture(u_texture_input, toTexUv(coord));

    float span = max(u_bottomPx - u_topPx, 1.0);
    float u = clamp((coord.y - u_topPx) / span, 0.0, 1.0);
    if (u >= 0.999 || (u_maxBlurPx <= 0.05 && u_scrimAlpha <= 0.002)) {
        frag_color = base;
        return;
    }

    float knee = clamp(u_softKnee, 0.0, 0.75);
    float progress = clamp((u - knee) / max(1.0 - knee, 0.001), 0.0, 1.0);
    // Smooth cubic falloff (1.0 at top -> exact 0.0 with zero slope at bottom)
    float smoothT = 1.0 - (progress * progress * (3.0 - 2.0 * progress));
    float radius = u_maxBlurPx * smoothT * smoothT;

    vec4 blurred = base;
    if (radius >= 0.35) {
        // 17-tap dual-ring concentric Gaussian disk (center + 6 inner + 10 outer)
        // with staggered angles to prevent ghosting on high-contrast typography.
        vec4 acc = base * 0.140;

        // Inner ring (6 taps at 0.44 * radius, 60-degree spacing)
        float r1 = radius * 0.44;
        const float w1 = 0.072; // 6 * 0.072 = 0.432
        acc += texture(u_texture_input, toTexUv(coord + vec2( 1.000000,  0.000000) * r1)) * w1;
        acc += texture(u_texture_input, toTexUv(coord + vec2( 0.500000,  0.866025) * r1)) * w1;
        acc += texture(u_texture_input, toTexUv(coord + vec2(-0.500000,  0.866025) * r1)) * w1;
        acc += texture(u_texture_input, toTexUv(coord + vec2(-1.000000,  0.000000) * r1)) * w1;
        acc += texture(u_texture_input, toTexUv(coord + vec2(-0.500000, -0.866025) * r1)) * w1;
        acc += texture(u_texture_input, toTexUv(coord + vec2( 0.500000, -0.866025) * r1)) * w1;

        // Outer ring (10 taps at 1.00 * radius, 36-degree spacing offset by 18 deg)
        float r2 = radius;
        const float w2 = 0.0428; // 10 * 0.0428 = 0.428 (total = 1.000)
        acc += texture(u_texture_input, toTexUv(coord + vec2( 0.951057,  0.309017) * r2)) * w2;
        acc += texture(u_texture_input, toTexUv(coord + vec2( 0.587785,  0.809017) * r2)) * w2;
        acc += texture(u_texture_input, toTexUv(coord + vec2( 0.000000,  1.000000) * r2)) * w2;
        acc += texture(u_texture_input, toTexUv(coord + vec2(-0.587785,  0.809017) * r2)) * w2;
        acc += texture(u_texture_input, toTexUv(coord + vec2(-0.951057,  0.309017) * r2)) * w2;
        acc += texture(u_texture_input, toTexUv(coord + vec2(-0.951057, -0.309017) * r2)) * w2;
        acc += texture(u_texture_input, toTexUv(coord + vec2(-0.587785, -0.809017) * r2)) * w2;
        acc += texture(u_texture_input, toTexUv(coord + vec2( 0.000000, -1.000000) * r2)) * w2;
        acc += texture(u_texture_input, toTexUv(coord + vec2( 0.587785, -0.809017) * r2)) * w2;
        acc += texture(u_texture_input, toTexUv(coord + vec2( 0.951057, -0.309017) * r2)) * w2;

        blurred = acc;
    }

    float scrimMix = clamp(u_scrimAlpha * smoothT, 0.0, 1.0);
    vec3 scrimColor = vec3(u_scrimR, u_scrimG, u_scrimB);
    vec3 rgb = mix(blurred.rgb, scrimColor * max(blurred.a, 1.0), scrimMix);
    frag_color = vec4(rgb, blurred.a);
}
