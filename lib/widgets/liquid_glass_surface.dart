import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../services/local_media_service.dart';
import '../theme/app_colors.dart';

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
    final surface = ClipRRect(
      borderRadius: BorderRadius.circular(widget.borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          padding: widget.padding,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: widget.tintColor != null
                  ? [
                      widget.tintColor!
                          .withValues(alpha: _pressed ? 0.92 : 0.84),
                      widget.tintColor!
                          .withValues(alpha: _pressed ? 0.82 : 0.72),
                    ]
                  : (c.isDark
                      ? [
                          const Color(0xFF34353C)
                              .withValues(alpha: _pressed ? 0.84 : 0.72),
                          const Color(0xFF1D1E22)
                              .withValues(alpha: _pressed ? 0.82 : 0.68),
                        ]
                      : [
                          Colors.white
                              .withValues(alpha: _pressed ? 0.94 : 0.86),
                          const Color(0xFFF3F4F8)
                              .withValues(alpha: _pressed ? 0.86 : 0.74),
                        ]),
            ),
            border: Border.all(
              color: widget.tintColor != null
                  ? Colors.white.withValues(alpha: _pressed ? 0.42 : 0.28)
                  : (c.isDark
                      ? Colors.white.withValues(alpha: _pressed ? 0.26 : 0.16)
                      : Colors.black.withValues(alpha: _pressed ? 0.12 : 0.07)),
              width: 1,
            ),
          ),
          child: widget.child,
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
                filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 140),
                  padding: widget.padding,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(widget.borderRadius),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: widget.primary
                          ? [
                              Color.lerp(c.accent, Colors.white, _pressed ? 0.22 : 0.14)!
                                  .withValues(alpha: 0.92),
                              c.accent.withValues(alpha: 0.88),
                            ]
                          : (c.isDark
                              ? [
                                  const Color(0xFF34353C)
                                      .withValues(alpha: _pressed ? 0.86 : 0.74),
                                  const Color(0xFF1F2026)
                                      .withValues(alpha: _pressed ? 0.84 : 0.70),
                                ]
                              : [
                                  Colors.white
                                      .withValues(alpha: _pressed ? 0.95 : 0.86),
                                  const Color(0xFFF0F1F6)
                                      .withValues(alpha: _pressed ? 0.88 : 0.76),
                                ]),
                    ),
                    border: Border.all(
                      color: widget.primary
                          ? Colors.white.withValues(alpha: _pressed ? 0.48 : 0.32)
                          : (c.isDark
                              ? Colors.white.withValues(alpha: _pressed ? 0.26 : 0.16)
                              : Colors.black.withValues(alpha: _pressed ? 0.12 : 0.08)),
                      width: 1.0,
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
