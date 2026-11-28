#version 460 core
#include <flutter/runtime_effect.glsl>

// 2-Pass Separable True Gaussian Progressive Faded Frosted Blur for Flutter Impeller.
//
// Pass 1 (`u_dir = (1, 0)`) applies a dense 25-tap 1D horizontal Gaussian blur;
// Pass 2 (`u_dir = (0, 1)`) applies a dense 25-tap 1D vertical Gaussian blur over
// Pass 1's output, mathematically yielding a true 25x25 = 625-tap silky 2D
// Gaussian frost with ZERO sparse-ring ghosting AND ZERO hard bottom border!
//
// Uses BitChord's quintic smootherStep (`6t^5 - 15t^4 + 10t^3`) so both slope
// and curvature hit exact 0.0 at top and bottom — melting invisibly into crisp
// page content underneath with zero visible seam.
//
// Uniform layout (12 floats):
// - 0, 1:  u_size        (auto-populated by Impeller: physical backdrop px)
// - 2:     u_topPx       (physical Y of header top)
// - 3:     u_bottomPx    (physical Y where blur & mist hit exact 0.0)
// - 4:     u_maxRadiusPx (peak Gaussian half-width in physical px at top)
// - 5:     u_dirX        (1.0 for horizontal pass, 0.0 for vertical pass)
// - 6:     u_dirY        (0.0 for horizontal pass, 1.0 for vertical pass)
// - 7..9:  u_scrimR/G/B  (scaffold mist tint RGB, 0.0..1.0)
// - 10:    u_scrimAlpha  (0.0 on Pass 1; peak soft mist opacity on Pass 2)
// - 11:    u_softKnee    (normalized height 0..0.65 where smooth fade begins)
uniform vec2 u_size;
uniform float u_topPx;
uniform float u_bottomPx;
uniform float u_maxRadiusPx;
uniform float u_dirX;
uniform float u_dirY;
uniform float u_scrimR;
uniform float u_scrimG;
uniform float u_scrimB;
uniform float u_scrimAlpha;
uniform float u_softKnee;

uniform sampler2D u_texture_input;

out vec4 frag_color;

float smootherStep(float x) {
    float t = clamp(x, 0.0, 1.0);
    return t * t * t * (t * (t * 6.0 - 15.0) + 10.0);
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
    vec4 base = texture(u_texture_input, toTexUv(coord));

    float span = max(u_bottomPx - u_topPx, 1.0);
    float u = clamp((coord.y - u_topPx) / span, 0.0, 1.0);
    if (u >= 0.999 || (u_maxRadiusPx <= 0.05 && u_scrimAlpha <= 0.002)) {
        frag_color = base;
        return;
    }

    float knee = clamp(u_softKnee, 0.0, 0.65);
    float progress = clamp((u - knee) / max(1.0 - knee, 0.001), 0.0, 1.0);
    // Quintic smootherStep (1.0 at top -> exact 0.0 with zero slope & curvature)
    float fade = 1.0 - smootherStep(progress);
    // Smooth progressive Gaussian radius tapering invisibly to 0.0 px
    float radius = u_maxRadiusPx * fade;

    vec4 blurred = base;
    if (radius >= 0.35) {
        vec2 stepVec = vec2(u_dirX, u_dirY) * (radius / 12.0);
        // Hardware bilinear-paired 13-tap Gaussian (equivalent to 25-tap sigma=4.4):
        // reuses `base` as center tap + 6 symmetric bilinear pairs = 12 texture fetches/pass
        // (~52% fewer GPU texture reads & zero inner-loop exp() calls per pixel).
        vec4 acc = base;
        acc += (texture(u_texture_input, toTexUv(coord + stepVec * 1.480639)) +
                texture(u_texture_input, toTexUv(coord - stepVec * 1.480639))) * 1.876355;
        acc += (texture(u_texture_input, toTexUv(coord + stepVec * 3.454925)) +
                texture(u_texture_input, toTexUv(coord - stepVec * 3.454925))) * 1.454117;
        acc += (texture(u_texture_input, toTexUv(coord + stepVec * 5.429450)) +
                texture(u_texture_input, toTexUv(coord - stepVec * 5.429450))) * 0.918968;
        acc += (texture(u_texture_input, toTexUv(coord + stepVec * 7.404341)) +
                texture(u_texture_input, toTexUv(coord - stepVec * 7.404341))) * 0.473595;
        acc += (texture(u_texture_input, toTexUv(coord + stepVec * 9.379726)) +
                texture(u_texture_input, toTexUv(coord - stepVec * 9.379726))) * 0.199020;
        acc += (texture(u_texture_input, toTexUv(coord + stepVec * 11.355715)) +
                texture(u_texture_input, toTexUv(coord - stepVec * 11.355715))) * 0.068195;
        blurred = acc * 0.09107053; // 1.0 / 10.980500
    }

    if (u_scrimAlpha > 0.002) {
        float mist = clamp(u_scrimAlpha * fade * fade, 0.0, 1.0);
        vec3 scrimCol = vec3(u_scrimR, u_scrimG, u_scrimB);
        vec3 rgb = mix(blurred.rgb, scrimCol * max(blurred.a, 1.0), mist);
        frag_color = vec4(rgb, blurred.a);
    } else {
        frag_color = blurred;
    }
}
