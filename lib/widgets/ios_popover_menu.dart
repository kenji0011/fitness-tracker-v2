import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';
import 'liquid_glass_surface.dart';

class TempoPopoverAction {
  final String label;
  final VoidCallback onTap;
  final Color? textColor;

  const TempoPopoverAction({
    required this.label,
    required this.onTap,
    this.textColor,
  });
}

/// Displays a BitChord / iOS 27-inspired Liquid Glass popover menu that smoothly
/// morphs outward from the circular 3-dots [anchorKey] button on a critically
/// damped spring (`stiffness: 600`) and retracts seamlessly back into the button.
Future<void> showTempoPopoverMenu({
  required BuildContext context,
  required GlobalKey anchorKey,
  required List<TempoPopoverAction> actions,
  double width = 196,
}) {
  final box = anchorKey.currentContext?.findRenderObject() as RenderBox?;
  final overlay =
      Overlay.of(context).context.findRenderObject() as RenderBox?;

  Rect anchorRect;
  if (box != null && overlay != null) {
    final topLeft = box.localToGlobal(Offset.zero, ancestor: overlay);
    anchorRect = topLeft & box.size;
  } else {
    final size = MediaQuery.sizeOf(context);
    anchorRect = Rect.fromLTWH(size.width - 56, 56, 42, 42);
  }

  return Navigator.of(context).push<void>(
    _IosPopoverMenuRoute(
      anchorRect: anchorRect,
      actions: actions,
      width: width,
    ),
  );
}

/// Critically damped spring (matching BitChord `IosMenuPopover` `stiffness = 600f`):
/// accelerates rapidly out of the circular button and settles cleanly with zero jitter.
class _CriticallyDampedLiquidCurve extends Curve {
  static final _sim = SpringSimulation(
    const SpringDescription(mass: 1.0, stiffness: 600.0, damping: 49.0),
    0.0,
    1.0,
    0.0,
  );

  const _CriticallyDampedLiquidCurve();

  @override
  double transformInternal(double t) {
    if (t <= 0.0) return 0.0;
    if (t >= 1.0) return 1.0;
    return _sim.x(t * 0.34).clamp(0.0, 1.0);
  }
}

class _IosPopoverMenuRoute extends PopupRoute<void> {
  final Rect anchorRect;
  final List<TempoPopoverAction> actions;
  final double width;

  static const _openCurve = _CriticallyDampedLiquidCurve();

  _IosPopoverMenuRoute({
    required this.anchorRect,
    required this.actions,
    required this.width,
  });

  @override
  Color? get barrierColor => Colors.black.withValues(alpha: 0.14);

  @override
  bool get barrierDismissible => true;

  @override
  String? get barrierLabel => 'Dismiss menu';

  @override
  Duration get transitionDuration => const Duration(milliseconds: 300);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 220);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    final c = AppColors.of(context);
    final screen = MediaQuery.sizeOf(context);
    final rightEdge =
        (screen.width - anchorRect.right).clamp(14.0, screen.width);
    // Anchor directly over the top-right 3-dots circle so the button appears to
    // liquid-morph into the menu panel and collapse seamlessly back into itself.
    final topEdge = (anchorRect.top).clamp(16.0, screen.height - 240);

    final menuRows = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: List.generate(actions.length, (i) {
        final action = actions[i];
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (i > 0)
              Divider(
                height: 0.6,
                thickness: 0.6,
                indent: 16,
                endIndent: 16,
                color: c.isDark
                    ? Colors.white.withValues(alpha: 0.09)
                    : Colors.black.withValues(alpha: 0.06),
              ),
            _LiquidMenuRow(
              label: action.label,
              textColor: action.textColor ?? c.textPrimary,
              onTap: () {
                HapticFeedback.selectionClick();
                Navigator.of(context).pop();
                action.onTap();
              },
            ),
          ],
        );
      }),
    );

    return AnimatedBuilder(
      animation: animation,
      child: menuRows,
      builder: (context, child) {
        final rawT = animation.value.clamp(0.0, 1.0);
        final isClosing = animation.status == AnimationStatus.reverse;

        // Open: critically damped liquid expansion from 3-dots circle (0.28 -> 1.0).
        // Close: BitChord-tuned smooth FastOutSlowIn liquid collapse back into button.
        final double morphT;
        final double contentAlpha;
        final double glassAlpha;
        if (isClosing) {
          final closeProgress = 1.0 - rawT;
          final easedClose = Curves.fastOutSlowIn.transform(closeProgress);
          morphT = (1.0 - easedClose).clamp(0.0, 1.0);
          // Fade rows slightly ahead of the glass shell so text never crunches
          contentAlpha =
              (1.0 - Curves.easeOutCubic.transform((closeProgress * 1.45).clamp(0.0, 1.0)))
                  .clamp(0.0, 1.0);
          glassAlpha = (1.0 - Curves.easeInCubic.transform(closeProgress))
              .clamp(0.0, 1.0);
        } else {
          morphT = _openCurve.transform(rawT);
          contentAlpha = Curves.easeOutCubic
              .transform(((rawT - 0.12) / 0.55).clamp(0.0, 1.0))
              .clamp(0.0, 1.0);
          glassAlpha = Curves.easeOutCubic
              .transform((rawT / 0.42).clamp(0.0, 1.0))
              .clamp(0.0, 1.0);
        }

        // Liquid morph: horizontal & vertical scale slightly staggered for droplet stretch
        final scaleX = lerpDouble(0.28, 1.0, morphT)!;
        final scaleY = lerpDouble(0.24, 1.0, Curves.easeOutCubic.transform(morphT))!;
        final cornerRadius = lerpDouble(30.0, 24.0, morphT)!;
        final blurSigma = (26.0 * glassAlpha).clamp(0.0, 26.0);

        final baseBgAlpha = c.isDark ? 0.68 : 0.74;
        final shadowAlpha = (c.isDark ? 0.48 : 0.14) * glassAlpha;

        return Stack(
          children: [
            Positioned(
              top: topEdge,
              right: rightEdge,
              width: width,
              child: Transform(
                alignment: Alignment.topRight,
                transform: Matrix4.diagonal3Values(scaleX, scaleY, 1.0),
                child: Material(
                  type: MaterialType.transparency,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(cornerRadius),
                      boxShadow: shadowAlpha > 0.005
                          ? [
                              BoxShadow(
                                color: Colors.black
                                    .withValues(alpha: shadowAlpha),
                                blurRadius: 28 * glassAlpha,
                                offset: Offset(0, 12 * glassAlpha),
                              ),
                            ]
                          : const [],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(cornerRadius),
                      child: blurSigma > 0.35
                          ? BackdropFilter(
                              filter: ImageFilter.blur(
                                sigmaX: blurSigma,
                                sigmaY: blurSigma,
                              ),
                              child: _glassBody(
                                c: c,
                                radius: cornerRadius,
                                baseBgAlpha: baseBgAlpha,
                                glassAlpha: glassAlpha,
                                contentAlpha: contentAlpha,
                                child: child!,
                              ),
                            )
                          : _glassBody(
                              c: c,
                              radius: cornerRadius,
                              baseBgAlpha: baseBgAlpha,
                              glassAlpha: glassAlpha,
                              contentAlpha: contentAlpha,
                              child: child!,
                            ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _glassBody({
    required AppColors c,
    required double radius,
    required double baseBgAlpha,
    required double glassAlpha,
    required double contentAlpha,
    required Widget child,
  }) {
    return CustomPaint(
      foregroundPainter: LiquidGlassRimPainter(
        borderRadius: radius,
        isDark: c.isDark,
        intensity: 1.05 * glassAlpha,
        strokeWidth: 1.2,
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: c.isDark
                ? [
                    const Color(0xFF3A3C45)
                        .withValues(alpha: baseBgAlpha * glassAlpha),
                    const Color(0xFF1A1B20)
                        .withValues(alpha: (baseBgAlpha + 0.06) * glassAlpha),
                  ]
                : [
                    Colors.white
                        .withValues(alpha: (baseBgAlpha + 0.08) * glassAlpha),
                    const Color(0xFFF3F5FA)
                        .withValues(alpha: (baseBgAlpha - 0.04) * glassAlpha),
                  ],
          ),
        ),
        child: Opacity(
          opacity: contentAlpha,
          child: child,
        ),
      ),
    );
  }
}

class _LiquidMenuRow extends StatefulWidget {
  final String label;
  final Color textColor;
  final VoidCallback onTap;

  const _LiquidMenuRow({
    required this.label,
    required this.textColor,
    required this.onTap,
  });

  @override
  State<_LiquidMenuRow> createState() => _LiquidMenuRowState();
}

class _LiquidMenuRowState extends State<_LiquidMenuRow> {
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
        margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: _pressed
              ? (c.isDark
                  ? Colors.white.withValues(alpha: 0.10)
                  : Colors.black.withValues(alpha: 0.06))
              : Colors.transparent,
        ),
        child: Text(
          widget.label,
          style: TextStyle(
            color: widget.textColor,
            fontSize: 16,
            fontWeight: FontWeight.w500,
            letterSpacing: -0.15,
          ),
        ),
      ),
    );
  }
}
