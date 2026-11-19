import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Clean Apple Health-style grouped card compatible with Light & Dark Mode.
class AppleCard extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final box = Container(
      decoration: BoxDecoration(
        color: color ?? c.card,
        borderRadius: BorderRadius.circular(borderRadius),
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
      child: Padding(padding: padding, child: child),
    );

    if (onTap == null && onDoubleTap == null) return box;

    return GestureDetector(
      onTap: onTap,
      onDoubleTap: onDoubleTap,
      child: box,
    );
  }
}

/// Frosted soft-glass surface for floating headers, badges, and buttons.
class LiquidGlassSurface extends StatelessWidget {
  final Widget child;
  final double borderRadius;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final VoidCallback? onDoubleTap;

  const LiquidGlassSurface({
    super.key,
    required this.child,
    this.borderRadius = 24,
    this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    this.onTap,
    this.onDoubleTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final widget = ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(borderRadius),
            color: c.glassBg,
            border: Border.all(color: c.glassBorder, width: 1),
          ),
          child: child,
        ),
      ),
    );

    if (onTap == null && onDoubleTap == null) return widget;

    return GestureDetector(
      onTap: onTap,
      onDoubleTap: onDoubleTap,
      child: widget,
    );
  }
}

/// Renders a local profile avatar (local file path or initials fallback).
class LocalProfileAvatar extends StatelessWidget {
  final String name;
  final String avatarPath;
  final double size;

  const LocalProfileAvatar({
    super.key,
    required this.name,
    required this.avatarPath,
    this.size = 44,
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
    final hasFile = !kIsWeb &&
        avatarPath.trim().isNotEmpty &&
        File(avatarPath).existsSync();

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            c.accent,
            c.bodyCyan,
          ],
        ),
        border: Border.all(
          color: c.isDark
              ? Colors.white.withValues(alpha: 0.22)
              : Colors.white,
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: c.accent.withValues(alpha: 0.22),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipOval(
        child: hasFile
            ? Image.file(
                File(avatarPath),
                width: size,
                height: size,
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
