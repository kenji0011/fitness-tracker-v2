import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../services/local_media_service.dart';
import '../theme/app_colors.dart';

/// Shared singleton loader for Tempo's GPU Liquid Glass refraction fragment
/// shader (`shaders/liquid_glass_lens.frag`), prewarmed in `main()` so the
/// floating navbar capsule, active droplet, and circular header buttons render
/// live screen-space optical refraction from Frame 0.
class TempoLiquidShaderCache {
  TempoLiquidShaderCache._();

  static ui.FragmentProgram? _program;
  static Future<ui.FragmentProgram?>? _loading;

  static ui.FragmentProgram? get program => _program;

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

  /// Elevated 3D domed crystal lens gradient for the active navbar selection pill,
  /// tuned to lift crisply above the 75% frosted refractive dock.
  static LinearGradient activeLensGradient({
    required bool isDark,
  }) {
    if (isDark) {
      return LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.white.withValues(alpha: 0.26),
          Colors.white.withValues(alpha: 0.12),
          Colors.white.withValues(alpha: 0.18),
        ],
        stops: const [0.0, 0.54, 1.0],
      );
    }
    return LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        Colors.white.withValues(alpha: 0.94),
        Colors.white.withValues(alpha: 0.72),
        const Color(0xFFF3F4F9).withValues(alpha: 0.84),
      ],
      stops: const [0.0, 0.54, 1.0],
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
        child: box,
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

  const LiquidGlassSurface({
    super.key,
    required this.child,
    this.borderRadius = 24,
    this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    this.onTap,
    this.onDoubleTap,
    this.tintColor,
  });

  @override
  State<LiquidGlassSurface> createState() => _LiquidGlassSurfaceState();
}

class _LiquidGlassSurfaceState extends State<LiquidGlassSurface> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final isInteractive = widget.onTap != null || widget.onDoubleTap != null;
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
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: CustomPaint(
            foregroundPainter: LiquidGlassRimPainter(
              borderRadius: widget.borderRadius,
              isDark: c.isDark,
              intensity: _pressed ? 1.2 : 0.95,
              tintColor: widget.tintColor,
            ),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              curve: Curves.easeOutCubic,
              padding: widget.padding,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(widget.borderRadius),
                gradient: widget.tintColor != null
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
                        pressed: _pressed,
                      ),
              ),
              child: widget.child,
            ),
          ),
        ),
      ),
    );

    if (!isInteractive) return surface;

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
        child: surface,
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
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 22, sigmaY: 22),
                child: CustomPaint(
                  foregroundPainter: LiquidGlassRimPainter(
                    borderRadius: widget.borderRadius,
                    isDark: c.isDark,
                    intensity: _pressed ? 1.25 : 0.98,
                    tintColor: widget.primary ? c.accent : null,
                  ),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 140),
                    padding: widget.padding,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(widget.borderRadius),
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
                        color: widget.primary ? Colors.white : c.textPrimary,
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
      ),
    );
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
