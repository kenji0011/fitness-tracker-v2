import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../services/animation_speed_service.dart';
import '../services/appearance_service.dart';
import '../services/local_media_service.dart';
import '../theme/app_colors.dart';

/// Shared singleton loader for Tempo's GPU Liquid Glass & Frosted Fade Blur
/// fragment shaders (`shaders/liquid_glass_lens.frag` &
/// `shaders/frosted_fade_blur.frag`), prewarmed in `main()` so the floating
/// navbar capsule, active droplet, circular header buttons, difficulty sliders,
/// dragged summary cards, and faded frosted headers render live from Frame 0.
class TempoLiquidShaderCache {
  TempoLiquidShaderCache._();

  static ui.FragmentProgram? _program;
  static Future<ui.FragmentProgram?>? _loading;

  static ui.FragmentProgram? _frostedFadeProgram;
  static Future<ui.FragmentProgram?>? _loadingFrostedFade;

  static ui.FragmentProgram? get program => _program;
  static ui.FragmentProgram? get frostedFadeBlurProgram => _frostedFadeProgram;

  static Future<ui.FragmentProgram?> load() {
    if (_program != null) return Future<ui.FragmentProgram?>.value(_program);
    if (!ui.ImageFilter.isShaderFilterSupported) {
      return Future<ui.FragmentProgram?>.value(null);
    }
    return _loading ??= ui.FragmentProgram.fromAsset(
      'shaders/liquid_glass_lens.frag',
    ).then<ui.FragmentProgram?>((prog) {
      _program = prog;
      return prog;
    }).catchError((Object e) {
      debugPrint('TempoLiquidShaderCache fallback active: $e');
      _loading = null;
      return null;
    });
  }

  static Future<ui.FragmentProgram?> loadFrostedFadeBlur() {
    if (_frostedFadeProgram != null) {
      return Future<ui.FragmentProgram?>.value(_frostedFadeProgram);
    }
    if (!ui.ImageFilter.isShaderFilterSupported) {
      return Future<ui.FragmentProgram?>.value(null);
    }
    return _loadingFrostedFade ??= ui.FragmentProgram.fromAsset(
      'shaders/frosted_fade_blur.frag',
    ).then<ui.FragmentProgram?>((prog) {
      _frostedFadeProgram = prog;
      return prog;
    }).catchError((Object e) {
      debugPrint('TempoLiquidShaderCache frosted fade fallback active: $e');
      _loadingFrostedFade = null;
      return null;
    });
  }
}

/// Shared iOS 26/27 optical Liquid Glass gradient & specular rim painter
/// aligned with `shaders/liquid_glass_lens.frag` (`lightDir = (0.62, 0.78)`).
///
/// Renders:
/// 1. Subtle outer hairline edge contour (keeps crystal-clear glass crisp even
///    over bright white Light Mode cards).
/// 2. Dual-lobe directional specular highlight rim (bright top-left catch-light
///    + softer bottom-right counter-refraction) using a single GPU `SweepGradient`.
/// 3. Optional curved top inner meniscus sheen for unmistakable 3D domed glass.
class LiquidGlassRimPainter extends CustomPainter {
  final double borderRadius;
  final bool isDark;
  final double intensity;
  final double strokeWidth;
  final bool showTopMeniscus;
  final Color? tintColor;

  const LiquidGlassRimPainter({
    required this.borderRadius,
    required this.isDark,
    this.intensity = 1.0,
    this.strokeWidth = 1.2,
    this.showTopMeniscus = true,
    this.tintColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (intensity <= 0.005 || size.isEmpty) return;

    final rect = Offset.zero & size;
    final clampedRadius = math.min(
      borderRadius,
      math.min(size.width, size.height) * 0.5,
    );
    final outerRRect = RRect.fromRectAndRadius(
      rect.deflate(0.35),
      Radius.circular(clampedRadius),
    );
    final innerRRect = RRect.fromRectAndRadius(
      rect.deflate(strokeWidth * 0.6 + 0.35),
      Radius.circular((clampedRadius - strokeWidth * 0.5).clamp(0.0, clampedRadius)),
    );

    // 1. Subtle curved top inner meniscus reflection (simulates convex dome)
    if (showTopMeniscus) {
      canvas.save();
      canvas.clipRRect(outerRRect);
      final meniscusRect = Rect.fromLTWH(
        0,
        0,
        size.width,
        math.min(size.height * 0.46, 28.0),
      );
      final meniscusAlpha = (isDark ? 0.13 : 0.58) * intensity.clamp(0.0, 1.3);
      final meniscusPaint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withValues(alpha: meniscusAlpha.clamp(0.0, 0.78)),
            Colors.white.withValues(alpha: (meniscusAlpha * 0.18).clamp(0.0, 0.2)),
            Colors.white.withValues(alpha: 0.0),
          ],
          stops: const [0.0, 0.52, 1.0],
        ).createShader(meniscusRect);
      canvas.drawRect(meniscusRect, meniscusPaint);
      canvas.restore();
    }

    // 2. Crisp outer hairline contour (prevents clear glass fading into white cards)
    final contourAlpha = tintColor != null
        ? (isDark ? 0.22 : 0.12) * intensity
        : (isDark ? 0.24 : 0.085) * intensity;
    final contourPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.7
      ..isAntiAlias = true
      ..color = Colors.black.withValues(alpha: contourAlpha.clamp(0.0, 0.45));
    canvas.drawRRect(outerRRect, contourPaint);

    // 3. Directional dual-lobe specular bevel rim (top-left bright + bottom-right reflection)
    final peakAlpha = (tintColor != null
            ? 0.58
            : (isDark ? 0.46 : 0.96)) *
        intensity;
    final counterAlpha = (tintColor != null
            ? 0.34
            : (isDark ? 0.26 : 0.76)) *
        intensity;
    final valleyAlpha = (tintColor != null
            ? 0.10
            : (isDark ? 0.07 : 0.18)) *
        intensity;

    final rimColor = tintColor != null
        ? Color.lerp(Colors.white, tintColor!, 0.15)!
        : Colors.white;

    // Sweep starts at 3:00 (0 rad) and travels clockwise:
    // ~0.12 (43° bottom-right counter lobe), ~0.62 (223° top-left primary lobe)
    final rimPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..isAntiAlias = true
      ..shader = SweepGradient(
        center: Alignment.center,
        colors: [
          rimColor.withValues(alpha: valleyAlpha.clamp(0.0, 1.0)),
          rimColor.withValues(alpha: counterAlpha.clamp(0.0, 1.0)),
          rimColor.withValues(alpha: valleyAlpha.clamp(0.0, 1.0)),
          rimColor.withValues(alpha: peakAlpha.clamp(0.0, 1.0)),
          rimColor.withValues(alpha: (peakAlpha * 0.72).clamp(0.0, 1.0)),
          rimColor.withValues(alpha: valleyAlpha.clamp(0.0, 1.0)),
        ],
        stops: const [0.0, 0.13, 0.36, 0.62, 0.74, 1.0],
      ).createShader(rect);

    canvas.drawRRect(innerRRect, rimPaint);
  }

  @override
  bool shouldRepaint(covariant LiquidGlassRimPainter oldDelegate) =>
      oldDelegate.borderRadius != borderRadius ||
      oldDelegate.isDark != isDark ||
      oldDelegate.intensity != intensity ||
      oldDelegate.strokeWidth != strokeWidth ||
      oldDelegate.showTopMeniscus != showTopMeniscus ||
      oldDelegate.tintColor != tintColor;
}

/// Shared crystal-clear iOS 26/27 neutral glass fill gradients (Option A).
class LiquidGlassPalette {
  LiquidGlassPalette._();

  static LinearGradient surfaceGradient({
    required bool isDark,
    double alphaMultiplier = 1.0,
    bool pressed = false,
  }) {
    final boost = pressed ? 1.16 : 1.0;
    final a = (alphaMultiplier * boost).clamp(0.0, 1.35);
    if (isDark) {
      return LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          const Color(0xFF3E4049).withValues(alpha: (0.48 * a).clamp(0.0, 0.86)),
          const Color(0xFF1A1B20).withValues(alpha: (0.54 * a).clamp(0.0, 0.88)),
          const Color(0xFF282A32).withValues(alpha: (0.46 * a).clamp(0.0, 0.84)),
        ],
        stops: const [0.0, 0.55, 1.0],
      );
    }
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Colors.white.withValues(alpha: (0.64 * a).clamp(0.0, 0.94)),
        const Color(0xFFF6F7FB).withValues(alpha: (0.48 * a).clamp(0.0, 0.86)),
        Colors.white.withValues(alpha: (0.58 * a).clamp(0.0, 0.90)),
      ],
      stops: const [0.0, 0.52, 1.0],
    );
  }

  /// Soft recessed neutral frosted pill gradient for the active navbar tab
  /// (iOS 26/27 frosted UITabBar capsule), contrasting cleanly against the
  /// bright milky frosted dock in Light Mode and charcoal frost in Dark Mode.
  static LinearGradient activeLensGradient({
    required bool isDark,
  }) {
    if (isDark) {
      return LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.white.withValues(alpha: 0.17),
          Colors.white.withValues(alpha: 0.13),
          Colors.white.withValues(alpha: 0.15),
        ],
        stops: const [0.0, 0.52, 1.0],
      );
    }
    return LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        const Color(0xFF1C1C1E).withValues(alpha: 0.135),
        const Color(0xFF1C1C1E).withValues(alpha: 0.105),
        const Color(0xFF1C1C1E).withValues(alpha: 0.120),
      ],
      stops: const [0.0, 0.52, 1.0],
    );
  }
}

/// Clean Apple Health-style grouped card compatible with Light & Dark Mode,
/// with subtle tactile press-scale feedback when interactive.
class AppleCard extends StatefulWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final VoidCallback? onDoubleTap;
  final double borderRadius;
  final Color? color;

  const AppleCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.onTap,
    this.onDoubleTap,
    this.borderRadius = 22,
    this.color,
  });

  @override
  State<AppleCard> createState() => _AppleCardState();
}

class _AppleCardState extends State<AppleCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final box = Container(
      decoration: BoxDecoration(
        color: widget.color ?? c.card,
        borderRadius: BorderRadius.circular(widget.borderRadius),
        border: Border.all(color: c.cardBorder, width: 1),
        boxShadow: c.isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.045),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
      ),
      child: Padding(padding: widget.padding, child: widget.child),
    );

    if (widget.onTap == null && widget.onDoubleTap == null) return box;

    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      onDoubleTap: widget.onDoubleTap,
      child: AnimatedScale(
        scale: _pressed ? 0.978 : 1.0,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOutCubic,
        child: TempoTouchLightEffect(
          borderRadius: widget.borderRadius,
          intensity: 0.58,
          cancelOnScroll: true,
          receiveScatter: false,
          child: box,
        ),
      ),
    );
  }
}

/// Frosted soft-glass surface for floating headers, badges, and buttons,
/// with specular top-left rim sheen and optional liquid press physics.
class LiquidGlassSurface extends StatefulWidget {
  final Widget child;
  final double borderRadius;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final VoidCallback? onDoubleTap;
  final Color? tintColor;

  /// Set `false` for cards inside long scrolling feeds or `FadeTransition`s to
  /// preserve 120Hz Impeller frame pacing with optical glass rims + touch-light
  /// scatter and zero per-row `BackdropFilter` overhead.
  final bool blurEnabled;

  const LiquidGlassSurface({
    super.key,
    required this.child,
    this.borderRadius = 24,
    this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    this.onTap,
    this.onDoubleTap,
    this.tintColor,
    this.blurEnabled = true,
  });

  @override
  State<LiquidGlassSurface> createState() => _LiquidGlassSurfaceState();
}

class _LiquidGlassSurfaceState extends State<LiquidGlassSurface> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final appearance = TempoAppearanceService.instance.value;
    final useBlur = widget.blurEnabled && appearance.allowDynamicBlur;
    final useGlassStyle = appearance.useLiquidGlass ||
        (!widget.blurEnabled && appearance.liquidGlass);
    final isInteractive = widget.onTap != null || widget.onDoubleTap != null;
    final inner = CustomPaint(
      foregroundPainter: useGlassStyle
          ? LiquidGlassRimPainter(
              borderRadius: widget.borderRadius,
              isDark: c.isDark,
              intensity: _pressed ? 1.2 : 0.95,
              tintColor: widget.tintColor,
            )
          : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOutCubic,
        padding: widget.padding,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.borderRadius),
          color: (!useBlur && !useGlassStyle)
              ? (widget.tintColor ?? c.card)
              : null,
          border: !useGlassStyle
              ? Border.all(color: c.cardBorder, width: 0.8)
              : null,
          gradient: (!useBlur && !useGlassStyle)
              ? null
              : (widget.tintColor != null
                  ? LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        widget.tintColor!
                            .withValues(alpha: _pressed ? 0.90 : 0.80),
                        widget.tintColor!
                            .withValues(alpha: _pressed ? 0.80 : 0.68),
                      ],
                    )
                  : LiquidGlassPalette.surfaceGradient(
                      isDark: c.isDark,
                      alphaMultiplier: useBlur ? 1.0 : (c.isDark ? 1.25 : 1.32),
                      pressed: _pressed,
                    )),
        ),
        child: widget.child,
      ),
    );
    final surface = Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(widget.borderRadius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: c.isDark ? 0.34 : 0.08),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(widget.borderRadius),
        child: useBlur
            ? BackdropFilter(
                filter: ui.ImageFilter.blur(
                  sigmaX: appearance.betterGlassPerformance ? 16 : 24,
                  sigmaY: appearance.betterGlassPerformance ? 16 : 24,
                ),
                child: inner,
              )
            : inner,
      ),
    );

    final litSurface = TempoTouchLightEffect(
      borderRadius: widget.borderRadius,
      isAccentSurface: widget.tintColor != null,
      emitLight: isInteractive,
      receiveScatter: true,
      intensity: 0.95,
      scatterGain: 1.05,
      child: surface,
    );

    if (!isInteractive) return litSurface;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      onDoubleTap: widget.onDoubleTap,
      child: AnimatedScale(
        scale: _pressed ? 0.96 : 1.0,
        duration: const Duration(milliseconds: 130),
        curve: Curves.easeOutCubic,
        child: litSurface,
      ),
    );
  }
}

/// Interactive Liquid Glass pill button with BitChord-inspired volume-preserving
/// droplet squish (`scaleX: 1.04, scaleY: 0.94`) and specular glass rim.
class TempoLiquidButton extends StatefulWidget {
  final Widget child;
  final VoidCallback? onPressed;
  final bool primary;
  final double borderRadius;
  final EdgeInsetsGeometry padding;
  final double? height;

  const TempoLiquidButton({
    super.key,
    required this.child,
    required this.onPressed,
    this.primary = true,
    this.borderRadius = 999,
    this.padding = const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
    this.height,
  });

  @override
  State<TempoLiquidButton> createState() => _TempoLiquidButtonState();
}

class _TempoLiquidButtonState extends State<TempoLiquidButton>
    with SingleTickerProviderStateMixin {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final enabled = widget.onPressed != null;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
      onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
      onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
      onTap: widget.onPressed,
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0.0, end: _pressed ? 1.0 : 0.0),
        duration: Duration(milliseconds: _pressed ? 110 : 280),
        curve: _pressed ? Curves.easeOutCubic : Curves.easeOutBack,
        builder: (context, p, child) {
          final sx = 1.0 + 0.045 * p;
          final sy = 1.0 - 0.055 * p;
          return Transform(
            alignment: Alignment.center,
            transform: Matrix4.diagonal3Values(sx, sy, 1.0),
            child: child,
          );
        },
        child: Opacity(
          opacity: enabled ? 1.0 : 0.45,
          child: TempoTouchLightEffect(
            borderRadius: widget.borderRadius,
            isAccentSurface: widget.primary,
            enabled: enabled,
            intensity: 1.0,
            child: Container(
              height: widget.height,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(widget.borderRadius),
                boxShadow: [
                  BoxShadow(
                    color: widget.primary
                        ? c.accent.withValues(alpha: _pressed ? 0.36 : 0.24)
                        : Colors.black.withValues(alpha: c.isDark ? 0.32 : 0.08),
                    blurRadius: _pressed ? 18 : 14,
                    offset: Offset(0, _pressed ? 3 : 6),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(widget.borderRadius),
                child: TempoAppearanceService.instance.value.allowDynamicBlur
                    ? BackdropFilter(
                        filter: ui.ImageFilter.blur(
                          sigmaX: TempoAppearanceService
                                  .instance.value.betterGlassPerformance
                              ? 14
                              : 22,
                          sigmaY: TempoAppearanceService
                                  .instance.value.betterGlassPerformance
                              ? 14
                              : 22,
                        ),
                        child: CustomPaint(
                          foregroundPainter:
                              TempoAppearanceService.instance.value.useLiquidGlass
                                  ? LiquidGlassRimPainter(
                                      borderRadius: widget.borderRadius,
                                      isDark: c.isDark,
                                      intensity: _pressed ? 1.25 : 0.98,
                                      tintColor:
                                          widget.primary ? c.accent : null,
                                    )
                                  : null,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 140),
                            padding: widget.padding,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              borderRadius:
                                  BorderRadius.circular(widget.borderRadius),
                              gradient: widget.primary
                                  ? LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [
                                        Color.lerp(
                                          c.accent,
                                          Colors.white,
                                          _pressed ? 0.24 : 0.14,
                                        )!
                                            .withValues(alpha: 0.90),
                                        c.accent.withValues(alpha: 0.86),
                                      ],
                                    )
                                  : LiquidGlassPalette.surfaceGradient(
                                      isDark: c.isDark,
                                      pressed: _pressed,
                                    ),
                            ),
                            child: DefaultTextStyle.merge(
                              style: TextStyle(
                                color: widget.primary
                                    ? Colors.white
                                    : c.textPrimary,
                                fontWeight: FontWeight.w700,
                              ),
                              child: widget.child,
                            ),
                          ),
                        ),
                      )
                    : Container(
                        padding: widget.padding,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          borderRadius:
                              BorderRadius.circular(widget.borderRadius),
                          color: widget.primary ? c.accent : c.card,
                          border: widget.primary
                              ? null
                              : Border.all(color: c.cardBorder, width: 0.9),
                        ),
                        child: DefaultTextStyle.merge(
                          style: TextStyle(
                            color:
                                widget.primary ? Colors.white : c.textPrimary,
                            fontWeight: FontWeight.w700,
                          ),
                          child: widget.child,
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Tactile pill CTA button without optical glass refraction: compresses smoothly
/// on press (`0.945`) and springs back with a gentle elastic overshoot bounce on
/// release (`Curves.easeOutBack`) for crisp, smooth physical feedback.
class TempoBouncyButton extends StatefulWidget {
  final Widget child;
  final VoidCallback? onPressed;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final double height;
  final double borderRadius;
  final EdgeInsetsGeometry padding;

  const TempoBouncyButton({
    super.key,
    required this.child,
    required this.onPressed,
    this.backgroundColor,
    this.foregroundColor,
    this.height = 52,
    this.borderRadius = 999,
    this.padding = const EdgeInsets.symmetric(horizontal: 20),
  });

  @override
  State<TempoBouncyButton> createState() => _TempoBouncyButtonState();
}

class _TempoBouncyButtonState extends State<TempoBouncyButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final enabled = widget.onPressed != null;
    final bg = widget.backgroundColor ?? c.accent;
    final fg = widget.foregroundColor ?? Colors.white;
    final reduced = TempoAppearanceService.instance.reduceAnimation ||
        MediaQuery.disableAnimationsOf(context);
    final speed = TempoAnimationSpeedService.instance;
    final pressDur = reduced
        ? Duration.zero
        : speed.scale(const Duration(milliseconds: 95));
    final releaseDur = reduced
        ? Duration.zero
        : speed.scale(const Duration(milliseconds: 380));

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
      onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
      onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
      onTap: widget.onPressed,
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0.0, end: _pressed ? 1.0 : 0.0),
        duration: _pressed ? pressDur : releaseDur,
        curve: _pressed ? Curves.easeOutCubic : Curves.easeOutBack,
        builder: (context, p, child) {
          final scale = 1.0 - 0.055 * p;
          return Transform.scale(scale: scale, child: child);
        },
        child: Opacity(
          opacity: enabled ? 1.0 : 0.45,
          child: TempoTouchLightEffect(
            borderRadius: widget.borderRadius,
            isAccentSurface: true,
            enabled: enabled,
            intensity: 1.0,
            child: AnimatedContainer(
              duration: pressDur,
              curve: Curves.easeOutCubic,
              height: widget.height,
              padding: widget.padding,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Color.lerp(bg, Colors.black, _pressed ? 0.08 : 0.0),
                borderRadius: BorderRadius.circular(widget.borderRadius),
                boxShadow: [
                  BoxShadow(
                    color: bg.withValues(alpha: _pressed ? 0.18 : 0.28),
                    blurRadius: _pressed ? 10 : 18,
                    spreadRadius: -2,
                    offset: Offset(0, _pressed ? 2 : 7),
                  ),
                ],
              ),
              child: DefaultTextStyle.merge(
                style: TextStyle(
                  color: fg,
                  fontSize: 15.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.15,
                ),
                child: widget.child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Shared screen-space HyperOS 3 optical light field.
///
/// Whenever any button or glass surface is pressed, it emits a 3D point light
/// at the finger's global screen coordinates (`globalPosition`). All nearby
/// Liquid Glass buttons and glass cards within [scatterRadius] (`~195 dp`) on
/// the same active route subscribe via `CustomPaint`'s `repaint` listenable —
/// zero widget rebuilds, instant AABB spatial culling, and 0% GPU cost at rest.
class TempoGlobalTouchLight extends ChangeNotifier {
  TempoGlobalTouchLight._();

  static final TempoGlobalTouchLight instance = TempoGlobalTouchLight._();

  _TempoGlobalTouchLightHostState? _host;
  Offset _globalPosition = Offset.zero;
  double _intensity = 0.0;
  int? _activeSourceId;
  int? _activeRouteHash;
  double _scatterRadius = 195.0;

  bool get hasHost => _host != null;
  Offset get globalPosition => _globalPosition;
  double get intensity => _intensity;
  int? get activeSourceId => _activeSourceId;
  int? get activeRouteHash => _activeRouteHash;
  double get scatterRadius => _scatterRadius;

  void _attachHost(_TempoGlobalTouchLightHostState host) {
    _host = host;
  }

  void _detachHost(_TempoGlobalTouchLightHostState host) {
    if (identical(_host, host)) {
      _host = null;
      _intensity = 0.0;
      _activeSourceId = null;
      _activeRouteHash = null;
    }
  }

  void _updateFromHost(double nextIntensity, {bool clearSource = false}) {
    _intensity = nextIntensity;
    if (clearSource) {
      _activeSourceId = null;
      _activeRouteHash = null;
    }
    notifyListeners();
  }

  void emitDown({
    required int sourceId,
    required Offset globalPosition,
    int? routeHash,
    double scatterRadius = 195.0,
  }) {
    if (TempoAppearanceService.instance.reduceAnimation) return;
    _activeSourceId = sourceId;
    _activeRouteHash = routeHash;
    _globalPosition = globalPosition;
    _scatterRadius = scatterRadius;
    if (_host != null) {
      _host!._bloomIn();
    } else {
      _intensity = 1.0;
      notifyListeners();
    }
  }

  void emitMove(int sourceId, Offset globalPosition) {
    if (_activeSourceId != sourceId) return;
    _globalPosition = globalPosition;
    notifyListeners();
  }

  void emitUp(int sourceId) {
    if (_activeSourceId != sourceId) return;
    if (_host != null) {
      _host!._finishAndFade();
    } else {
      _intensity = 0.0;
      _activeSourceId = null;
      _activeRouteHash = null;
      notifyListeners();
    }
  }

  void emitCancel(int sourceId) {
    if (_activeSourceId != sourceId) return;
    if (_host != null) {
      _host!._fadeOutNow();
    } else {
      _intensity = 0.0;
      _activeSourceId = null;
      _activeRouteHash = null;
      notifyListeners();
    }
  }

  void resetForTest() {
    _host?._stopImmediately();
    _intensity = 0.0;
    _activeSourceId = null;
    _activeRouteHash = null;
    _globalPosition = Offset.zero;
    notifyListeners();
  }
}

/// Root single-ticker host for [TempoGlobalTouchLight] mounted once in
/// `MaterialApp.builder` so cross-button scatter light runs on a single
/// synchronized 120Hz `AnimationController` with zero per-button ticker churn.
class TempoGlobalTouchLightHost extends StatefulWidget {
  final Widget child;

  const TempoGlobalTouchLightHost({super.key, required this.child});

  @override
  State<TempoGlobalTouchLightHost> createState() =>
      _TempoGlobalTouchLightHostState();
}

class _TempoGlobalTouchLightHostState extends State<TempoGlobalTouchLightHost>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  bool _pendingFadeOut = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, value: 0.0)
      ..addListener(_onTick)
      ..addStatusListener(_onStatus);
    TempoGlobalTouchLight.instance._attachHost(this);
  }

  @override
  void dispose() {
    TempoGlobalTouchLight.instance._detachHost(this);
    _ctrl.removeListener(_onTick);
    _ctrl.removeStatusListener(_onStatus);
    _ctrl.dispose();
    super.dispose();
  }

  Duration get _bloomDur => TempoAnimationSpeedService.instance.scale(
        const Duration(milliseconds: 105),
      );

  Duration get _peakFinishDur => TempoAnimationSpeedService.instance.scale(
        const Duration(milliseconds: 65),
      );

  Duration get _fadeDur => TempoAnimationSpeedService.instance.scale(
        const Duration(milliseconds: 340),
      );

  void _onTick() {
    TempoGlobalTouchLight.instance._updateFromHost(_ctrl.value);
  }

  void _onStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && _pendingFadeOut) {
      _pendingFadeOut = false;
      _ctrl.animateBack(
        0.0,
        duration: _fadeDur,
        curve: Curves.easeOutCubic,
      );
    } else if (status == AnimationStatus.dismissed ||
        (status == AnimationStatus.completed && _ctrl.value <= 0.001)) {
      _pendingFadeOut = false;
      TempoGlobalTouchLight.instance._updateFromHost(0.0, clearSource: true);
    }
  }

  void _bloomIn() {
    if (!mounted) return;
    _pendingFadeOut = false;
    // Zero-frame-latency initial contact glint so even Frame 0 responds instantly
    if (_ctrl.value < 0.18) {
      _ctrl.value = 0.18;
    }
    _ctrl.animateTo(
      1.0,
      duration: _bloomDur,
      curve: Curves.easeOutCubic,
    );
  }

  void _finishAndFade() {
    if (!mounted) return;
    if (_ctrl.value < 0.78) {
      _pendingFadeOut = true;
      _ctrl.animateTo(
        1.0,
        duration: _peakFinishDur,
        curve: Curves.easeOutCubic,
      );
    } else {
      _fadeOutNow();
    }
  }

  void _fadeOutNow() {
    if (!mounted) return;
    _pendingFadeOut = false;
    _ctrl.animateBack(
      0.0,
      duration: _fadeDur,
      curve: Curves.easeOutCubic,
    );
  }

  void _stopImmediately() {
    _pendingFadeOut = false;
    _ctrl.stop();
    _ctrl.value = 0.0;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// HyperOS 3-inspired luminous touch-light feedback & proximity scatter overlay:
/// - **Direct Touch:** Blooms a soft radial spotlight directly from the finger's
///   exact contact point (`localPosition`) + ignites the button's rounded rim.
/// - **Proximity Scatter (`receiveScatter: true`):** When a nearby button or
///   glass tile is touched within `~195 dp`, catches its real-time screen-space
///   light along the facing glass border & inner corner (matching HyperOS 3's
///   Control Center cross-tile light scatter in `h#100` / `h#188`).
/// - Zero widget rebuilds per frame, instant AABB cull, 0% GPU cost at rest.
class TempoTouchLightEffect extends StatefulWidget {
  final Widget child;
  final double borderRadius;
  final double intensity;
  final bool isAccentSurface;
  final bool enabled;
  final bool cancelOnScroll;
  final bool emitLight;
  final bool receiveScatter;
  final double scatterGain;

  const TempoTouchLightEffect({
    super.key,
    required this.child,
    this.borderRadius = 999,
    this.intensity = 1.0,
    this.isAccentSurface = false,
    this.enabled = true,
    this.cancelOnScroll = false,
    this.emitLight = true,
    this.receiveScatter = true,
    this.scatterGain = 1.0,
  });

  @override
  State<TempoTouchLightEffect> createState() => _TempoTouchLightEffectState();
}

class _TempoTouchLightEffectState extends State<TempoTouchLightEffect>
    with SingleTickerProviderStateMixin {
  late final AnimationController _glowCtrl;
  final ValueNotifier<Offset> _touchLocal = ValueNotifier<Offset>(Offset.zero);
  late final Listenable _repaint;

  int? _activePointerId;
  Offset _downPos = Offset.zero;
  bool _pendingFadeOut = false;
  int? _routeHash;

  int get _sourceId => identityHashCode(this);

  @override
  void initState() {
    super.initState();
    _glowCtrl = AnimationController(vsync: this, value: 0.0)
      ..addStatusListener(_handleStatus);
    _repaint = Listenable.merge([
      _glowCtrl,
      _touchLocal,
      TempoGlobalTouchLight.instance,
    ]);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    _routeHash = route != null ? identityHashCode(route) : null;
  }

  @override
  void dispose() {
    TempoGlobalTouchLight.instance.emitCancel(_sourceId);
    _glowCtrl.removeStatusListener(_handleStatus);
    _glowCtrl.dispose();
    _touchLocal.dispose();
    super.dispose();
  }

  Duration get _bloomDur => TempoAnimationSpeedService.instance.scale(
        const Duration(milliseconds: 105),
      );

  Duration get _fadeDur => TempoAnimationSpeedService.instance.scale(
        const Duration(milliseconds: 340),
      );

  void _handleStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && _pendingFadeOut) {
      _pendingFadeOut = false;
      _glowCtrl.animateTo(
        0.0,
        duration: _fadeDur,
        curve: Curves.easeOutCubic,
      );
    }
  }

  bool get _reduceMotion =>
      TempoAppearanceService.instance.reduceAnimation ||
      MediaQuery.disableAnimationsOf(context);

  RenderBox? _getRenderBox() {
    if (!mounted) return null;
    final obj = context.findRenderObject();
    if (obj is RenderBox && obj.attached && obj.hasSize) return obj;
    return null;
  }

  void _onPointerDown(PointerDownEvent e) {
    if (!widget.enabled || !widget.emitLight || _reduceMotion) return;
    _activePointerId = e.pointer;
    _downPos = e.localPosition;
    _touchLocal.value = e.localPosition;
    _pendingFadeOut = false;

    final globalLight = TempoGlobalTouchLight.instance;
    if (globalLight.hasHost) {
      globalLight.emitDown(
        sourceId: _sourceId,
        globalPosition: e.position,
        routeHash: _routeHash,
      );
    } else {
      _glowCtrl.animateTo(
        1.0,
        duration: _bloomDur,
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _onPointerMove(PointerMoveEvent e) {
    if (e.pointer != _activePointerId) return;
    _touchLocal.value = e.localPosition;
    final globalLight = TempoGlobalTouchLight.instance;

    if (widget.cancelOnScroll && (e.localPosition - _downPos).distance > 16.0) {
      _activePointerId = null;
      _pendingFadeOut = false;
      if (globalLight.hasHost) {
        globalLight.emitCancel(_sourceId);
      } else {
        _glowCtrl.animateTo(
          0.0,
          duration: _fadeDur,
          curve: Curves.easeOutCubic,
        );
      }
      return;
    }

    if (globalLight.hasHost) {
      globalLight.emitMove(_sourceId, e.position);
    }
  }

  void _onPointerUp(PointerUpEvent e) {
    if (e.pointer != _activePointerId) return;
    _activePointerId = null;
    final globalLight = TempoGlobalTouchLight.instance;
    if (globalLight.hasHost) {
      globalLight.emitUp(_sourceId);
      return;
    }
    if (_glowCtrl.value < 0.78) {
      _pendingFadeOut = true;
      _glowCtrl.animateTo(
        1.0,
        duration: TempoAnimationSpeedService.instance.scale(
          const Duration(milliseconds: 65),
        ),
        curve: Curves.easeOutCubic,
      );
    } else {
      _pendingFadeOut = false;
      _glowCtrl.animateTo(
        0.0,
        duration: _fadeDur,
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _onPointerCancel(PointerCancelEvent e) {
    if (e.pointer != _activePointerId) return;
    _activePointerId = null;
    _pendingFadeOut = false;
    final globalLight = TempoGlobalTouchLight.instance;
    if (globalLight.hasHost) {
      globalLight.emitCancel(_sourceId);
      return;
    }
    _glowCtrl.animateTo(
      0.0,
      duration: _fadeDur,
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled && !widget.receiveScatter) return widget.child;
    final isDark = AppColors.of(context).isDark;

    final painted = CustomPaint(
      foregroundPainter: _TempoTouchLightPainter(
        repaint: _repaint,
        localGlowCtrl: _glowCtrl,
        touchLocal: _touchLocal,
        sourceId: _sourceId,
        routeHash: _routeHash,
        getRenderBox: _getRenderBox,
        borderRadius: widget.borderRadius,
        isDark: isDark,
        isAccentSurface: widget.isAccentSurface,
        intensity: widget.intensity,
        receiveScatter: widget.receiveScatter,
        scatterGain: widget.scatterGain,
      ),
      child: widget.child,
    );

    if (!widget.enabled || !widget.emitLight) return painted;

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerUp,
      onPointerCancel: _onPointerCancel,
      child: painted,
    );
  }
}

void _paintTempoTouchLight({
  required Canvas canvas,
  required Rect rect,
  required Offset touchLocal,
  required double rawGlow,
  required double intensity,
  required bool brightSurface,
  RRect? rrect,
  Path? path,
}) {
  final g = rawGlow * intensity;
  if (g <= 0.004 || rect.isEmpty) return;

  final size = rect.size;
  final touch = Offset(
    touchLocal.dx.clamp(rect.left, rect.right),
    touchLocal.dy.clamp(rect.top, rect.bottom),
  );

  final isCircular = (size.width - size.height).abs() < 12.0 &&
      size.shortestSide <= 72.0;
  final baseRadius = isCircular
      ? size.longestSide * 1.18
      : math.max(size.height * 2.0, size.width * 0.48).clamp(64.0, 210.0);
  final liveRadius = baseRadius * (0.80 + 0.28 * rawGlow);
  final spotRect = Rect.fromCircle(center: touch, radius: liveRadius);

  // 1. Clipped interior radial light bloom centered right at finger contact
  canvas.save();
  if (path != null) {
    canvas.clipPath(path);
  } else if (rrect != null) {
    canvas.clipRRect(rrect);
  } else {
    canvas.clipRect(rect);
  }

  if (brightSurface) {
    final contrastPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFF94A3B8).withValues(alpha: (0.14 * g).clamp(0.0, 0.28)),
          const Color(0xFF94A3B8).withValues(alpha: 0.0),
        ],
        stops: const [0.0, 1.0],
      ).createShader(spotRect);
    canvas.drawRect(rect, contrastPaint);

    final lightPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          Colors.white.withValues(alpha: (0.76 * g).clamp(0.0, 0.92)),
          Colors.white.withValues(alpha: (0.28 * g).clamp(0.0, 0.50)),
          Colors.white.withValues(alpha: 0.0),
        ],
        stops: const [0.0, 0.45, 1.0],
      ).createShader(Rect.fromCircle(center: touch, radius: liveRadius * 0.85));
    canvas.drawRect(rect, lightPaint);
  } else {
    final lightPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          Colors.white.withValues(alpha: (0.44 * g).clamp(0.0, 0.72)),
          Colors.white.withValues(alpha: (0.20 * g).clamp(0.0, 0.42)),
          Colors.white.withValues(alpha: (0.05 * g).clamp(0.0, 0.16)),
          Colors.white.withValues(alpha: 0.0),
        ],
        stops: const [0.0, 0.38, 0.72, 1.0],
      ).createShader(spotRect);
    canvas.drawRect(rect, lightPaint);
  }
  canvas.restore();

  // 2. Energized directional border / specular rim illumination closest to touch
  final rimRect = Rect.fromCircle(center: touch, radius: liveRadius * 0.94);

  void strokeShape(Paint paint, {bool inner = false}) {
    if (path != null) {
      canvas.drawPath(path, paint);
    } else if (rrect != null) {
      final target = inner ? rrect.deflate(0.75) : rrect;
      canvas.drawRRect(target, paint);
    } else {
      canvas.drawRect(inner ? rect.deflate(0.75) : rect, paint);
    }
  }

  if (brightSurface) {
    final outerContrast = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..isAntiAlias = true
      ..shader = RadialGradient(
        colors: [
          const Color(0xFF475569).withValues(alpha: (0.22 * g).clamp(0.0, 0.36)),
          const Color(0xFF475569).withValues(alpha: 0.0),
        ],
        stops: const [0.0, 1.0],
      ).createShader(rimRect);
    strokeShape(outerContrast);
  }

  final haloPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 3.2
    ..isAntiAlias = true
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.8)
    ..shader = RadialGradient(
      colors: [
        Colors.white.withValues(alpha: (0.58 * g).clamp(0.0, 0.85)),
        Colors.white.withValues(alpha: (0.18 * g).clamp(0.0, 0.40)),
        Colors.white.withValues(alpha: 0.0),
      ],
      stops: const [0.0, 0.55, 1.0],
    ).createShader(rimRect);
  strokeShape(haloPaint, inner: true);

  final rimPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.55
    ..isAntiAlias = true
    ..shader = RadialGradient(
      colors: [
        Colors.white.withValues(alpha: (0.98 * g).clamp(0.0, 1.0)),
        Colors.white.withValues(alpha: (0.52 * g).clamp(0.0, 0.82)),
        Colors.white.withValues(alpha: (0.12 * g).clamp(0.0, 0.28)),
        Colors.white.withValues(alpha: 0.0),
      ],
      stops: const [0.0, 0.42, 0.80, 1.0],
    ).createShader(rimRect);
  strokeShape(rimPaint, inner: true);
}

/// Paints HyperOS 3 cross-button proximity light scatter onto a neighboring
/// glass surface: illuminates the exact facing border arc + soft inward corner
/// glow centered at the external [localLight] coordinates of the touched button.
void _paintTempoScatterLight({
  required Canvas canvas,
  required Rect rect,
  required RRect rrect,
  required Offset localLight,
  required double distanceToEdge,
  required double scatter,
  required bool brightSurface,
}) {
  if (scatter <= 0.008 || rect.isEmpty) return;

  final spillR = distanceToEdge + 96.0;
  final spillEdge = (distanceToEdge / spillR).clamp(0.0, 0.90);
  final spillMid = spillEdge + (1.0 - spillEdge) * 0.40;
  final spillRect = Rect.fromCircle(center: localLight, radius: spillR);

  // 1. Soft inward corner/edge light bleed clipped to the neighbor glass shape
  canvas.save();
  canvas.clipRRect(rrect);
  if (brightSurface) {
    final spillPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          Colors.white.withValues(alpha: (0.48 * scatter).clamp(0.0, 0.65)),
          Colors.white.withValues(alpha: (0.18 * scatter).clamp(0.0, 0.30)),
          Colors.white.withValues(alpha: 0.0),
        ],
        stops: [spillEdge, spillMid, 1.0],
      ).createShader(spillRect);
    canvas.drawRect(rect, spillPaint);
  } else {
    final spillPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          Colors.white.withValues(alpha: (0.28 * scatter).clamp(0.0, 0.44)),
          Colors.white.withValues(alpha: (0.10 * scatter).clamp(0.0, 0.20)),
          Colors.white.withValues(alpha: 0.0),
        ],
        stops: [spillEdge, spillMid, 1.0],
      ).createShader(spillRect);
    canvas.drawRect(rect, spillPaint);
  }
  canvas.restore();

  // 2. Facing specular rim ignition (brightest on border arc nearest finger)
  final rimR = distanceToEdge + 84.0;
  final rimEdge = (distanceToEdge / rimR).clamp(0.0, 0.90);
  final rimMid = rimEdge + (1.0 - rimEdge) * 0.42;
  final rimRect = Rect.fromCircle(center: localLight, radius: rimR);
  final innerRRect = rrect.deflate(0.75);

  if (brightSurface) {
    final contrastRim = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..isAntiAlias = true
      ..shader = RadialGradient(
        colors: [
          const Color(0xFF475569).withValues(alpha: (0.18 * scatter).clamp(0.0, 0.28)),
          const Color(0xFF475569).withValues(alpha: 0.0),
        ],
        stops: [rimEdge, 1.0],
      ).createShader(rimRect);
    canvas.drawRRect(rrect, contrastRim);
  }

  final haloPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 3.0
    ..isAntiAlias = true
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.6)
    ..shader = RadialGradient(
      colors: [
        Colors.white.withValues(alpha: (0.56 * scatter).clamp(0.0, 0.80)),
        Colors.white.withValues(alpha: (0.18 * scatter).clamp(0.0, 0.34)),
        Colors.white.withValues(alpha: 0.0),
      ],
      stops: [rimEdge, rimMid, 1.0],
    ).createShader(rimRect);
  canvas.drawRRect(innerRRect, haloPaint);

  final crispRim = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.55
    ..isAntiAlias = true
    ..shader = RadialGradient(
      colors: [
        Colors.white.withValues(alpha: (0.96 * scatter).clamp(0.0, 1.0)),
        Colors.white.withValues(alpha: (0.48 * scatter).clamp(0.0, 0.72)),
        Colors.white.withValues(alpha: 0.0),
      ],
      stops: [rimEdge, rimMid, 1.0],
    ).createShader(rimRect);
  canvas.drawRRect(innerRRect, crispRim);
}

class _TempoTouchLightPainter extends CustomPainter {
  final AnimationController localGlowCtrl;
  final ValueNotifier<Offset> touchLocal;
  final int sourceId;
  final int? routeHash;
  final RenderBox? Function() getRenderBox;
  final double borderRadius;
  final bool isDark;
  final bool isAccentSurface;
  final double intensity;
  final bool receiveScatter;
  final double scatterGain;

  _TempoTouchLightPainter({
    required super.repaint,
    required this.localGlowCtrl,
    required this.touchLocal,
    required this.sourceId,
    required this.routeHash,
    required this.getRenderBox,
    required this.borderRadius,
    required this.isDark,
    required this.isAccentSurface,
    required this.intensity,
    required this.receiveScatter,
    required this.scatterGain,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final globalLight = TempoGlobalTouchLight.instance;
    final globalGlow = globalLight.intensity;
    final localGlow = localGlowCtrl.value;
    if (globalGlow <= 0.004 && localGlow <= 0.004) return;

    final rect = Offset.zero & size;
    final clampedR = math.min(borderRadius, size.shortestSide * 0.5);
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(clampedR));
    final brightSurface = !isDark && !isAccentSurface;

    // Case 1: Direct touch on THIS widget
    final isDirectGlobal =
        globalLight.hasHost && globalLight.activeSourceId == sourceId;
    if (isDirectGlobal && globalGlow > 0.004) {
      final box = getRenderBox();
      final localPos = box != null
          ? box.globalToLocal(globalLight.globalPosition)
          : touchLocal.value;
      _paintTempoTouchLight(
        canvas: canvas,
        rect: rect,
        touchLocal: localPos,
        rawGlow: globalGlow,
        intensity: intensity,
        brightSurface: brightSurface,
        rrect: rrect,
      );
      return;
    }

    if (localGlow > 0.004) {
      _paintTempoTouchLight(
        canvas: canvas,
        rect: rect,
        touchLocal: touchLocal.value,
        rawGlow: localGlow,
        intensity: intensity,
        brightSurface: brightSurface,
        rrect: rrect,
      );
      return;
    }

    // Case 2: Cross-button HyperOS 3 proximity scatter onto nearby glass surfaces
    if (!receiveScatter ||
        globalGlow <= 0.004 ||
        !TempoAppearanceService.instance.value.useLiquidGlass) {
      return;
    }
    if (globalLight.activeRouteHash != null &&
        routeHash != null &&
        globalLight.activeRouteHash != routeHash) {
      return;
    }

    final box = getRenderBox();
    if (box == null) return;

    final localLight = box.globalToLocal(globalLight.globalPosition);
    final maxR = globalLight.scatterRadius;
    if (localLight.dx < -maxR ||
        localLight.dx > size.width + maxR ||
        localLight.dy < -maxR ||
        localLight.dy > size.height + maxR) {
      return;
    }

    final cx = localLight.dx.clamp(0.0, size.width);
    final cy = localLight.dy.clamp(0.0, size.height);
    final dist = (localLight - Offset(cx, cy)).distance;
    if (dist >= maxR) return;

    final prox = (1.0 - dist / maxR).clamp(0.0, 1.0);
    final scatter = prox * prox * globalGlow * scatterGain;
    if (scatter <= 0.008) return;

    _paintTempoScatterLight(
      canvas: canvas,
      rect: rect,
      rrect: rrect,
      localLight: localLight,
      distanceToEdge: dist,
      scatter: scatter,
      brightSurface: brightSurface,
    );
  }

  @override
  bool shouldRepaint(covariant _TempoTouchLightPainter oldDelegate) =>
      oldDelegate.borderRadius != borderRadius ||
      oldDelegate.isDark != isDark ||
      oldDelegate.isAccentSurface != isAccentSurface ||
      oldDelegate.intensity != intensity ||
      oldDelegate.receiveScatter != receiveScatter ||
      oldDelegate.scatterGain != scatterGain ||
      oldDelegate.routeHash != routeHash;
}

/// Global Material [InteractiveInkFeatureFactory] that replaces Android's
/// default circle ripple on `FilledButton`, `OutlinedButton`, `ElevatedButton`,
/// `TextButton`, `IconButton`, `InkWell`, and `ListTile` with Tempo's HyperOS 3
/// radial touch-light spotlight, directional specular rim illumination, and
/// live proximity light scatter onto nearby Liquid Glass surfaces.
class TempoTouchLightSplashFactory extends InteractiveInkFeatureFactory {
  final bool isDark;

  const TempoTouchLightSplashFactory({required this.isDark});

  @override
  InteractiveInkFeature create({
    required MaterialInkController controller,
    required RenderBox referenceBox,
    required Offset position,
    required Color color,
    required TextDirection textDirection,
    bool containedInkWell = false,
    RectCallback? rectCallback,
    BorderRadius? borderRadius,
    ShapeBorder? customBorder,
    double? radius,
    VoidCallback? onRemoved,
  }) {
    return _TempoTouchLightSplash(
      controller: controller,
      referenceBox: referenceBox,
      position: position,
      color: color,
      textDirection: textDirection,
      containedInkWell: containedInkWell,
      rectCallback: rectCallback,
      borderRadius: borderRadius,
      customBorder: customBorder,
      isDark: isDark,
      onRemoved: onRemoved,
    );
  }
}

class _TempoTouchLightSplash extends InteractiveInkFeature {
  final Offset _position;
  final TextDirection _textDirection;
  final bool _containedInkWell;
  final RectCallback? _rectCallback;
  final BorderRadius? _borderRadius;
  final ShapeBorder? _customBorder;
  final bool _isDark;

  late final AnimationController _glowCtrl;
  bool _pendingFadeOut = false;
  bool _fadingOut = false;
  bool _disposed = false;
  final bool _reduced;

  int get _sourceId => identityHashCode(this);

  _TempoTouchLightSplash({
    required super.controller,
    required super.referenceBox,
    required Offset position,
    required super.color,
    required TextDirection textDirection,
    required bool containedInkWell,
    RectCallback? rectCallback,
    BorderRadius? borderRadius,
    ShapeBorder? customBorder,
    required bool isDark,
    super.onRemoved,
  })  : _position = position,
        _textDirection = textDirection,
        _containedInkWell = containedInkWell,
        _rectCallback = rectCallback,
        _borderRadius = borderRadius,
        _customBorder = customBorder,
        _isDark = isDark,
        _reduced = TempoAppearanceService.instance.reduceAnimation {
    _glowCtrl = AnimationController(vsync: controller.vsync, value: 0.0);
    if (!_reduced) {
      _glowCtrl
        ..addListener(controller.markNeedsPaint)
        ..addStatusListener(_handleStatus);
      _glowCtrl.animateTo(
        1.0,
        duration: TempoAnimationSpeedService.instance.scale(
          const Duration(milliseconds: 105),
        ),
        curve: Curves.easeOutCubic,
      );
      if (referenceBox.attached && referenceBox.hasSize) {
        final globalPos = referenceBox.localToGlobal(position);
        TempoGlobalTouchLight.instance.emitDown(
          sourceId: _sourceId,
          globalPosition: globalPos,
        );
      }
    }
  }

  void _handleStatus(AnimationStatus status) {
    if (_disposed) return;
    if (status == AnimationStatus.completed && _pendingFadeOut) {
      _pendingFadeOut = false;
      _startFadeOut();
    } else if (status == AnimationStatus.dismissed && _fadingOut) {
      dispose();
    }
  }

  void _startFadeOut() {
    if (_disposed || _fadingOut) return;
    _fadingOut = true;
    if (_glowCtrl.value <= 0.004) {
      dispose();
      return;
    }
    _glowCtrl.animateBack(
      0.0,
      duration: TempoAnimationSpeedService.instance.scale(
        const Duration(milliseconds: 340),
      ),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void confirm() {
    if (_disposed) return;
    TempoGlobalTouchLight.instance.emitUp(_sourceId);
    if (_reduced) {
      dispose();
      return;
    }
    if (_glowCtrl.value < 0.78 && !_fadingOut) {
      _pendingFadeOut = true;
      _glowCtrl.animateTo(
        1.0,
        duration: TempoAnimationSpeedService.instance.scale(
          const Duration(milliseconds: 65),
        ),
        curve: Curves.easeOutCubic,
      );
    } else {
      _startFadeOut();
    }
  }

  @override
  void cancel() {
    if (_disposed) return;
    TempoGlobalTouchLight.instance.emitCancel(_sourceId);
    if (_reduced) {
      dispose();
      return;
    }
    _pendingFadeOut = false;
    _startFadeOut();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    TempoGlobalTouchLight.instance.emitCancel(_sourceId);
    _glowCtrl.removeListener(controller.markNeedsPaint);
    _glowCtrl.removeStatusListener(_handleStatus);
    _glowCtrl.dispose();
    super.dispose();
  }

  @override
  void paintFeature(Canvas canvas, Matrix4 transform) {
    if (_disposed || _reduced) return;
    final rawGlow = _glowCtrl.value;
    if (rawGlow <= 0.004) return;

    final rect = _rectCallback?.call() ?? (Offset.zero & referenceBox.size);
    if (rect.isEmpty) return;

    final originOffset = MatrixUtils.getAsTranslation(transform);
    canvas.save();
    if (originOffset == null) {
      canvas.transform(transform.storage);
    } else {
      canvas.translate(originOffset.dx, originOffset.dy);
    }

    Path? clipPath;
    RRect? rrect;
    if (_customBorder != null) {
      clipPath = _customBorder.getOuterPath(rect, textDirection: _textDirection);
    } else if (_borderRadius != null) {
      rrect = _borderRadius.resolve(_textDirection).toRRect(rect);
    } else if (!_containedInkWell) {
      rrect = RRect.fromRectAndRadius(
        rect,
        Radius.circular(rect.shortestSide * 0.5),
      );
    } else {
      rrect = RRect.fromRectAndRadius(rect, const Radius.circular(14.0));
    }

    final isAccentOrDark = _isDark || color.computeLuminance() > 0.55;

    _paintTempoTouchLight(
      canvas: canvas,
      rect: rect,
      touchLocal: _position,
      rawGlow: rawGlow,
      intensity: 0.96,
      brightSurface: !isAccentOrDark,
      rrect: rrect,
      path: clipPath,
    );

    canvas.restore();
  }
}

/// Renders a local profile avatar (local file path or initials fallback).
class LocalProfileAvatar extends StatelessWidget {
  final String name;
  final String avatarPath;
  final double size;
  final bool showBorder;
  final Color? borderColor;
  final double borderWidth;
  final bool showShadow;

  const LocalProfileAvatar({
    super.key,
    required this.name,
    required this.avatarPath,
    this.size = 44,
    this.showBorder = true,
    this.borderColor,
    this.borderWidth = 2,
    this.showShadow = true,
  });

  String get _initials {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return 'T';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final hasFile = LocalMediaService.fileExistsCached(avatarPath);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final decodePx = (size * dpr).round().clamp(32, 512);
    final resolvedBorderColor = borderColor ??
        (c.isDark ? Colors.white.withValues(alpha: 0.22) : Colors.white);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: hasFile
            ? null
            : LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  c.accent,
                  c.bodyCyan,
                ],
              ),
        border: showBorder
            ? Border.all(
                color: resolvedBorderColor,
                width: borderWidth,
              )
            : null,
        boxShadow: showShadow
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: c.isDark ? 0.26 : 0.10),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: ClipOval(
        child: hasFile
            ? Image.file(
                File(avatarPath),
                width: size,
                height: size,
                cacheWidth: decodePx,
                gaplessPlayback: true,
                filterQuality: FilterQuality.medium,
                fit: BoxFit.cover,
              )
            : Center(
                child: Text(
                  _initials,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: size * 0.38,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
      ),
    );
  }
}
