import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/animation_speed_service.dart';
import '../theme/app_colors.dart';
import 'liquid_glass_surface.dart';
import 'tempo_spring_physics.dart';

/// Descriptor for an option inside [showHyperOsDropdownMenu].
class HyperOsDropdownOption<T> {
  final T value;
  final String label;

  const HyperOsDropdownOption({
    required this.value,
    required this.label,
  });
}

/// Displays a HyperOS-style right-anchored vertical-unfold preference dropdown
/// (matching HyperOS's "Animation speed: Relaxed / Balanced / Fast" selector):
/// - Unfolds downward (or flips upward near screen bottom) from the tapped row's
///   right edge on an elastic spring with subtle overshoot (`~+1.4%`).
/// - Selected row highlights in Tempo's accent color (`c.accent`) with a crisp
///   trailing checkmark.
/// - Folds smoothly back into the row on selection or outside tap with zero
///   `Opacity` around `BackdropFilter` for locked 120Hz Impeller smoothness.
Future<T?> showHyperOsDropdownMenu<T>({
  required BuildContext context,
  required GlobalKey rowKey,
  required List<HyperOsDropdownOption<T>> options,
  required T selectedValue,
  double width = 192,
}) {
  final box = rowKey.currentContext?.findRenderObject() as RenderBox?;
  final overlay =
      Overlay.of(context).context.findRenderObject() as RenderBox?;

  Rect rowRect;
  if (box != null && overlay != null && box.hasSize) {
    final topLeft = box.localToGlobal(Offset.zero, ancestor: overlay);
    rowRect = topLeft & box.size;
  } else {
    final size = MediaQuery.sizeOf(context);
    rowRect = Rect.fromLTWH(16, size.height * 0.42, size.width - 32, 54);
  }

  return Navigator.of(context).push<T>(
    _HyperOsDropdownRoute<T>(
      rowRect: rowRect,
      options: options,
      selectedValue: selectedValue,
      width: width,
    ),
  );
}

class _HyperOsDropdownRoute<T> extends PopupRoute<T> {
  final Rect rowRect;
  final List<HyperOsDropdownOption<T>> options;
  final T selectedValue;
  final double width;

  /// Constant BackdropFilter sigma avoids Impeller blur kernel churn at 120Hz.
  static final ImageFilter _glassBlurFilter = ImageFilter.blur(
    sigmaX: 22.0,
    sigmaY: 22.0,
  );

  _HyperOsDropdownRoute({
    required this.rowRect,
    required this.options,
    required this.selectedValue,
    required this.width,
  });

  @override
  Color? get barrierColor => Colors.transparent;

  @override
  bool get barrierDismissible => true;

  @override
  String? get barrierLabel => 'Dismiss preference menu';

  @override
  Duration get transitionDuration =>
      TempoAnimationSpeedService.instance.scale(const Duration(milliseconds: 340));

  @override
  Duration get reverseTransitionDuration =>
      TempoAnimationSpeedService.instance.scale(const Duration(milliseconds: 340));

  @override
  Widget buildModalBarrier() {
    final anim = animation;
    if (anim == null) return const SizedBox.shrink();
    return AnimatedBuilder(
      animation: anim,
      builder: (context, _) {
        if (anim.status == AnimationStatus.reverse ||
            anim.status == AnimationStatus.dismissed) {
          return const SizedBox.shrink();
        }
        return super.buildModalBarrier();
      },
    );
  }

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    final c = AppColors.of(context);
    final screen = MediaQuery.sizeOf(context);
    final pad = MediaQuery.paddingOf(context);
    final textScale = MediaQuery.textScalerOf(context).scale(15.5) / 15.5;

    final rowHeight = (50.0 * textScale.clamp(1.0, 1.32)).ceilToDouble();
    const verticalPad = 12.0; // 6 top + 6 bottom
    final targetHeight = verticalPad + options.length * rowHeight;
    final targetWidth = width.clamp(164.0, screen.width - 32.0);
    const radius = 22.0;

    // Anchor right-aligned inside the tapped preference card, unfolding downward
    // by default (or flipping upward cleanly if close to the bottom edge).
    final double rightInset = (screen.width - rowRect.right + 12.0)
        .clamp(14.0, math.max(14.0, screen.width - targetWidth - 14.0))
        .toDouble();
    final spaceBelow = screen.height - rowRect.top - pad.bottom - 18.0;
    final openUpward = spaceBelow < targetHeight &&
        (rowRect.bottom - pad.top - 18.0) > spaceBelow;

    final double anchorTop;
    if (openUpward) {
      anchorTop = (rowRect.bottom - targetHeight)
          .clamp(pad.top + 12.0, screen.height - targetHeight - pad.bottom - 14.0);
    } else {
      // Align first menu row directly over the tapped preference row (matching HyperOS).
      anchorTop = (rowRect.top + 4.0)
          .clamp(pad.top + 12.0, screen.height - targetHeight - pad.bottom - 14.0);
    }

    final listContent = RepaintBoundary(
      child: SizedBox(
        width: targetWidth,
        height: targetHeight,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: options.map((opt) {
              final isSelected = opt.value == selectedValue;
              return _HyperOsDropdownRow(
                label: opt.label,
                height: rowHeight,
                selected: isSelected,
                onTap: () {
                  HapticFeedback.selectionClick();
                  Navigator.of(context).pop<T>(opt.value);
                },
              );
            }).toList(),
          ),
        ),
      ),
    );

    return AnimatedBuilder(
      animation: animation,
      child: listContent,
      builder: (context, child) {
        final rawT = animation.value.clamp(0.0, 1.0);
        final isClosing = animation.status == AnimationStatus.reverse ||
            animation.status == AnimationStatus.dismissed;

        final double heightT;
        final double scaleT;
        final double surfaceT;
        final double contentAlpha;

        if (isClosing) {
          final closeP = (1.0 - rawT).clamp(0.0, 1.0);
          final fold = TempoSpringCurves.dropdownFoldClose.transform(closeP);
          heightT = (1.0 - fold).clamp(0.0, 1.0);
          scaleT = (1.0 - fold).clamp(0.0, 1.0);
          surfaceT = (1.0 - Curves.easeInQuad.transform(closeP)).clamp(0.0, 1.0);
          contentAlpha =
              (1.0 - Curves.easeOutCubic.transform((closeP * 1.65).clamp(0.0, 1.0)))
                  .clamp(0.0, 1.0);
        } else {
          final springVal = TempoSpringCurves.dropdownUnfold.transform(rawT);
          heightT = springVal;
          scaleT = springVal;
          surfaceT = Curves.easeOutCubic.transform((rawT / 0.42).clamp(0.0, 1.0));
          contentAlpha =
              Curves.easeOutCubic.transform(((rawT - 0.08) / 0.44).clamp(0.0, 1.0));
        }

        // Start from a sleek pill roughly one row tall (~44dp) and unfold smoothly
        // revealing Relaxed -> Balanced -> Fast cleanly top-to-bottom.
        final startH = math.min(targetHeight, 44.0);
        final curH =
            math.max(startH, lerpDouble(startH, targetHeight, heightT)!);
        final scaleX = lerpDouble(0.84, 1.0, scaleT)!.clamp(0.80, 1.02);
        final scaleY = lerpDouble(0.90, 1.0, scaleT)!.clamp(0.86, 1.02);

        final curTop = openUpward
            ? anchorTop + (targetHeight - curH)
            : anchorTop;

        // Impeller-safe 120Hz glass fade: constant blur sigma + animated fill/rim
        // without wrapping BackdropFilter inside Opacity or thrashing blur kernels.
        final enableBlur = surfaceT > 0.10;
        final bgAlpha = (c.isDark ? 0.86 : 0.90) * surfaceT;
        final shadowAlpha = (c.isDark ? 0.46 : 0.16) * surfaceT;
        final rimIntensity = 0.95 * surfaceT;

        final innerSurface = CustomPaint(
          foregroundPainter: rimIntensity > 0.02
              ? LiquidGlassRimPainter(
                  borderRadius: radius,
                  isDark: c.isDark,
                  intensity: rimIntensity,
                  strokeWidth: 1.1,
                )
              : null,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(radius),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: c.isDark
                    ? [
                        const Color(0xFF34363E).withValues(alpha: bgAlpha),
                        const Color(0xFF1F2026).withValues(
                          alpha: (bgAlpha + 0.04).clamp(0.0, 1.0),
                        ),
                      ]
                    : [
                        Colors.white.withValues(
                          alpha: (bgAlpha + 0.05).clamp(0.0, 1.0),
                        ),
                        const Color(0xFFF6F7FB).withValues(alpha: bgAlpha),
                      ],
              ),
            ),
            child: OverflowBox(
              alignment:
                  openUpward ? Alignment.bottomCenter : Alignment.topCenter,
              minWidth: targetWidth,
              maxWidth: targetWidth,
              minHeight: targetHeight,
              maxHeight: targetHeight,
              child: Opacity(
                opacity: contentAlpha,
                child: child,
              ),
            ),
          ),
        );

        return IgnorePointer(
          ignoring: isClosing,
          child: Stack(
            children: [
              Positioned(
                top: curTop,
                right: rightInset,
                child: Transform(
                  alignment:
                      openUpward ? Alignment.bottomRight : Alignment.topRight,
                  transform: Matrix4.diagonal3Values(scaleX, scaleY, 1.0),
                  child: Material(
                    type: MaterialType.transparency,
                    child: Container(
                      width: targetWidth,
                      height: curH,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(radius),
                        boxShadow: shadowAlpha > 0.005
                            ? [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: shadowAlpha),
                                  blurRadius: 24.0,
                                  offset: const Offset(0, 8),
                                ),
                              ]
                            : const [],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(radius),
                        child: enableBlur
                            ? BackdropFilter(
                                filter: _glassBlurFilter,
                                child: innerSurface,
                              )
                            : innerSurface,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _HyperOsDropdownRow extends StatefulWidget {
  final String label;
  final double height;
  final bool selected;
  final VoidCallback onTap;

  const _HyperOsDropdownRow({
    required this.label,
    required this.height,
    required this.selected,
    required this.onTap,
  });

  @override
  State<_HyperOsDropdownRow> createState() => _HyperOsDropdownRowState();
}

class _HyperOsDropdownRowState extends State<_HyperOsDropdownRow> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        height: widget.height,
        margin: const EdgeInsets.symmetric(horizontal: 6),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: _pressed
              ? (c.isDark
                  ? Colors.white.withValues(alpha: 0.10)
                  : Colors.black.withValues(alpha: 0.06))
              : Colors.transparent,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                widget.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: widget.selected ? c.accent : c.textPrimary,
                  fontSize: 15.5,
                  fontWeight:
                      widget.selected ? FontWeight.w600 : FontWeight.w500,
                  letterSpacing: -0.15,
                ),
              ),
            ),
            if (widget.selected)
              Icon(
                CupertinoIcons.checkmark_alt,
                size: 18,
                color: c.accent,
              ),
          ],
        ),
      ),
    );
  }
}
