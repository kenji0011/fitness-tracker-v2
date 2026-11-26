import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

import '../services/animation_speed_service.dart';
import '../theme/app_colors.dart';
import 'liquid_glass_surface.dart';

/// Tracks the currently detached popover's anchor button [Key] so
/// `TempoGlassCircleButton` suppresses its inner glyph while the floating
/// droplet swings out and docks back (zero double-icon ghosting).
final ValueNotifier<Key?> activeTempoPopoverAnchorKey =
    ValueNotifier<Key?>(null);

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

/// Displays a Liquid Glass popover menu driven by HyperOS 4's decoupled
/// 2-spring physics (Center spring vs. Size spring):
/// - **Open (520 ms):** Fast center spring detaches a floating frosted droplet
///   down-and-left off [anchorKey], blurs the anchor glyph out while Gaussian-
///   unblurring and proportionally scaling the menu rows in, then blooms softly
///   past the corner (`~+1.3%` elastic overshoot) before settling.
/// - **Close (290 ms):** Springs invert—size collapses fast into a floating
///   circular droplet while menu text blurs out and the anchor glyph sharpens
///   inside, then the droplet glides 1:1 back into the top-right button.
Future<void> showTempoPopoverMenu({
  required BuildContext context,
  required GlobalKey anchorKey,
  required List<TempoPopoverAction> actions,
  double width = 196,
  IconData anchorIcon = CupertinoIcons.ellipsis_vertical,
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
    _HyperOsLiquidPopoverRoute(
      anchorKey: anchorKey,
      anchorRect: anchorRect,
      actions: actions,
      width: width,
      anchorIcon: anchorIcon,
    ),
  );
}

/// Real `SpringSimulation`-backed curve calibrated to HyperOS 4's measured
/// 60fps open/close trajectories, with a C1-smooth tail blend to exact `1.0`.
class _HyperOsSpringCurve extends Curve {
  final SpringSimulation _sim;
  final double _durationSec;
  final double _maxClamp;

  _HyperOsSpringCurve({
    required double stiffness,
    required double damping,
    required double durationSec,
    double maxClamp = 1.04,
  })  : _durationSec = durationSec,
        _maxClamp = maxClamp,
        _sim = SpringSimulation(
          SpringDescription(mass: 1.0, stiffness: stiffness, damping: damping),
          0.0,
          1.0,
          0.0,
        );

  @override
  double transformInternal(double t) {
    if (t <= 0.0) return 0.0;
    if (t >= 1.0) return 1.0;
    final raw = _sim.x(t * _durationSec).clamp(0.0, _maxClamp);
    // Feather the final 8% smoothly into exact 1.0 so resting layout never snaps.
    if (t > 0.92) {
      final tail = ((t - 0.92) / 0.08).clamp(0.0, 1.0);
      return lerpDouble(raw, 1.0, Curves.easeOutCubic.transform(tail))!;
    }
    return raw;
  }
}

class _HyperOsLiquidPopoverRoute extends PopupRoute<void> {
  final GlobalKey anchorKey;
  final Rect anchorRect;
  final List<TempoPopoverAction> actions;
  final double width;
  final IconData anchorIcon;

  // Calmer HyperOS 4 Open springs (580ms):
  // Same decoupled detached arc & ~1.2% elastic bloom, gently unhurried for the eye.
  static final _openCenterSpring = _HyperOsSpringCurve(
    stiffness: 460.0,
    damping: 33.4,
    durationSec: 0.58,
    maxClamp: 1.03,
  );
  static final _openSizeSpring = _HyperOsSpringCurve(
    stiffness: 220.0,
    damping: 24.6,
    durationSec: 0.58,
    maxClamp: 1.025,
  );

  // Calmer HyperOS 4 Close springs (360ms):
  // Smooth floating droplet collapse + graceful 1:1 dock back into the button.
  static final _closeSizeSpring = _HyperOsSpringCurve(
    stiffness: 360.0,
    damping: 32.3,
    durationSec: 0.36,
    maxClamp: 1.015,
  );
  static final _closeCenterSpring = _HyperOsSpringCurve(
    stiffness: 190.0,
    damping: 27.2,
    durationSec: 0.36,
    maxClamp: 1.0,
  );

  bool _attachedStatusListener = false;

  _HyperOsLiquidPopoverRoute({
    required this.anchorKey,
    required this.anchorRect,
    required this.actions,
    required this.width,
    required this.anchorIcon,
  });

  // Airy HyperOS 4 clear barrier (elevation comes from wide soft shadow, zero dark dim).
  @override
  Color? get barrierColor => Colors.transparent;

  @override
  bool get barrierDismissible => true;

  @override
  String? get barrierLabel => 'Dismiss menu';

  @override
  Duration get transitionDuration =>
      TempoAnimationSpeedService.instance.scale(const Duration(milliseconds: 460));

  @override
  Duration get reverseTransitionDuration =>
      TempoAnimationSpeedService.instance.scale(const Duration(milliseconds: 300));

  void _syncAnchorSuppression(bool hideIcon) {
    if (hideIcon) {
      if (!identical(activeTempoPopoverAnchorKey.value, anchorKey)) {
        activeTempoPopoverAnchorKey.value = anchorKey;
      }
    } else if (identical(activeTempoPopoverAnchorKey.value, anchorKey)) {
      activeTempoPopoverAnchorKey.value = null;
    }
  }

  void _handleStatus(AnimationStatus status) {
    _syncAnchorSuppression(status != AnimationStatus.dismissed);
  }

  @override
  void install() {
    super.install();
    if (!_attachedStatusListener && animation != null) {
      _attachedStatusListener = true;
      animation!.addStatusListener(_handleStatus);
    }
    _syncAnchorSuppression(true);
  }

  @override
  void dispose() {
    if (_attachedStatusListener) {
      animation?.removeStatusListener(_handleStatus);
      _attachedStatusListener = false;
    }
    _syncAnchorSuppression(false);
    super.dispose();
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
    final textScale = MediaQuery.textScalerOf(context).scale(16.0) / 16.0;

    final rowHeight = (46.0 * textScale.clamp(1.0, 1.35)).ceilToDouble();
    final dividerCount = math.max(0, actions.length - 1);
    const verticalPad = 12.0; // 6 top + 6 bottom
    final targetHeight =
        verticalPad + actions.length * (rowHeight + 4.0) + dividerCount * 0.6;
    final targetWidth = width.clamp(160.0, screen.width - 28.0);

    final startW = anchorRect.width.clamp(36.0, 56.0);
    final startH = anchorRect.height.clamp(36.0, 56.0);
    const endRadius = 24.0;

    final startRight =
        (screen.width - anchorRect.right).clamp(6.0, screen.width - startW);
    final endRight =
        startRight.clamp(8.0, math.max(8.0, screen.width - targetWidth - 8.0));

    final startTop = anchorRect.top;
    final maxAllowedTop =
        math.max(pad.top + 8.0, screen.height - targetHeight - pad.bottom - 14.0);
    final endTop = startTop.clamp(pad.top + 8.0, maxAllowedTop);

    final startCenter = anchorRect.center;
    final endRect = Rect.fromLTWH(
      screen.width - endRight - targetWidth,
      endTop,
      targetWidth,
      targetHeight,
    );
    final endCenter = endRect.center;

    final menuRows = SizedBox(
      width: targetWidth,
      height: targetHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
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
                  height: rowHeight,
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
        ),
      ),
    );

    return AnimatedBuilder(
      animation: animation,
      child: menuRows,
      builder: (context, child) {
        final rawT = animation.value.clamp(0.0, 1.0);
        final isClosing = animation.status == AnimationStatus.reverse ||
            animation.status == AnimationStatus.dismissed;

        final double centerT;
        final double sizeT;
        final double contentAlpha;
        final double contentSigma;
        final double anchorIconAlpha;
        final double anchorIconSigma;

        if (isClosing) {
          final closeP = (1.0 - rawT).clamp(0.0, 1.0);
          // Inverted springs: size collapses faster than center -> detached droplet!
          final sizeCollapse = _closeSizeSpring.transform(closeP);
          final centerReturn = _closeCenterSpring.transform(closeP);
          sizeT = (1.0 - sizeCollapse).clamp(-0.02, 1.0);
          centerT = (1.0 - centerReturn).clamp(0.0, 1.0);

          // Menu text Gaussian-blurs and dissolves smoothly during first 42% of close.
          final outP = (closeP / 0.42).clamp(0.0, 1.0);
          contentAlpha = (1.0 - Curves.easeOutCubic.transform(outP)).clamp(0.0, 1.0);
          contentSigma = 10.5 * Curves.easeOutQuad.transform(outP);

          // Anchor glyph materializes blurred -> razor-sharp inside the floating droplet.
          final inP = ((closeP - 0.36) / 0.36).clamp(0.0, 1.0);
          anchorIconAlpha = Curves.easeOutCubic.transform(inP).clamp(0.0, 1.0);
          anchorIconSigma =
              7.5 * (1.0 - Curves.easeOutCubic.transform(inP)).clamp(0.0, 1.0);
        } else {
          // Open springs: center shoots ahead of size -> detached droplet launch + elastic bloom!
          centerT = _openCenterSpring.transform(rawT);
          sizeT = _openSizeSpring.transform(rawT);

          // Anchor glyph blurs & dissolves out of the launching circular droplet.
          final iconOutP = (rawT / 0.22).clamp(0.0, 1.0);
          anchorIconAlpha =
              (1.0 - Curves.easeOutCubic.transform(iconOutP)).clamp(0.0, 1.0);
          anchorIconSigma = 7.5 * Curves.easeInQuad.transform(iconOutP);

          // Menu rows emerge heavily Gaussian-blurred and sharpen crisp by ~220ms.
          final contentInP = ((rawT - 0.12) / 0.32).clamp(0.0, 1.0);
          contentAlpha = Curves.easeOutCubic.transform(contentInP).clamp(0.0, 1.0);
          contentSigma =
              11.0 * (1.0 - Curves.easeOutCubic.transform(contentInP)).clamp(0.0, 1.0);
        }

        // Detached center-driven geometry:
        // Small positive detachment delta adds a gentle downward arc even on compact 2-row menus.
        final detachDelta = (centerT - sizeT).clamp(-0.04, 0.38);
        final arcNudgeY = math.max(0.0, detachDelta) * 24.0;
        final curCenter = Offset.lerp(startCenter, endCenter, centerT)! +
            Offset(0.0, arcNudgeY);

        final curW =
            math.max(startW * 0.94, lerpDouble(startW, targetWidth, sizeT)!);
        final curH =
            math.max(startH * 0.94, lerpDouble(startH, targetHeight, sizeT)!);
        final curRect = Rect.fromCenter(
          center: curCenter,
          width: curW,
          height: curH,
        );

        final circleRadius = math.min(curW, curH) / 2.0;
        final clampedSizeT = sizeT.clamp(0.0, 1.0);
        final radiusBlend = Curves.easeInOutCubic.transform(clampedSizeT);
        final curRadius =
            lerpDouble(circleRadius, endRadius, radiusBlend)!.clamp(0.0, circleRadius);

        // Option A: Tempo Liquid Glass frosted surface (BackdropFilter stays outside any Opacity/ImageFiltered).
        final blurSigma = lerpDouble(18.0, 28.0, clampedSizeT)!;
        final bgAlpha = lerpDouble(
          c.isDark ? 0.64 : 0.72,
          c.isDark ? 0.76 : 0.84,
          clampedSizeT,
        )!;
        final rimIntensity = lerpDouble(0.95, 1.08, clampedSizeT)!;
        final shadowAlpha = lerpDouble(
          c.isDark ? 0.24 : 0.08,
          c.isDark ? 0.44 : 0.14,
          clampedSizeT,
        )!;

        // Proportional menu content scale following the container width smoothly.
        final contentScale = (curW / targetWidth).clamp(0.38, 1.03);
        final iconScale = lerpDouble(0.76, 1.0, anchorIconAlpha)!;

        Widget menuLayer = OverflowBox(
          alignment: Alignment.center,
          minWidth: targetWidth,
          maxWidth: targetWidth,
          minHeight: targetHeight,
          maxHeight: targetHeight,
          child: Transform.scale(
            alignment: Alignment.center,
            scale: contentScale,
            child: Opacity(
              opacity: contentAlpha,
              child: child,
            ),
          ),
        );
        if (contentSigma > 0.25) {
          menuLayer = ImageFiltered(
            imageFilter: ImageFilter.blur(
              sigmaX: contentSigma,
              sigmaY: contentSigma,
            ),
            child: menuLayer,
          );
        }

        Widget? anchorIconLayer;
        if (anchorIconAlpha > 0.01) {
          Widget glyph = IgnorePointer(
            child: Opacity(
              opacity: anchorIconAlpha,
              child: Transform.scale(
                scale: iconScale,
                child: Center(
                  child: Icon(
                    anchorIcon,
                    size: 20,
                    color: c.textPrimary,
                  ),
                ),
              ),
            ),
          );
          if (anchorIconSigma > 0.25) {
            glyph = ImageFiltered(
              imageFilter: ImageFilter.blur(
                sigmaX: anchorIconSigma,
                sigmaY: anchorIconSigma,
              ),
              child: glyph,
            );
          }
          anchorIconLayer = glyph;
        }

        return Stack(
          children: [
            Positioned.fromRect(
              rect: curRect,
              child: Material(
                type: MaterialType.transparency,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(curRadius),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: shadowAlpha),
                        blurRadius: lerpDouble(12.0, 32.0, clampedSizeT)!,
                        spreadRadius: 0,
                        offset: Offset(0, lerpDouble(4.0, 12.0, clampedSizeT)!),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(curRadius),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(
                        sigmaX: blurSigma,
                        sigmaY: blurSigma,
                      ),
                      child: CustomPaint(
                        foregroundPainter: LiquidGlassRimPainter(
                          borderRadius: curRadius,
                          isDark: c.isDark,
                          intensity: rimIntensity,
                          strokeWidth: 1.2,
                        ),
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(curRadius),
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: c.isDark
                                  ? [
                                      const Color(0xFF3A3C45)
                                          .withValues(alpha: bgAlpha),
                                      const Color(0xFF1A1B20).withValues(
                                        alpha: (bgAlpha + 0.06).clamp(0.0, 1.0),
                                      ),
                                    ]
                                  : [
                                      Colors.white.withValues(
                                        alpha: (bgAlpha + 0.08).clamp(0.0, 1.0),
                                      ),
                                      const Color(0xFFF3F5FA).withValues(
                                        alpha: (bgAlpha - 0.03).clamp(0.0, 1.0),
                                      ),
                                    ],
                            ),
                          ),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              if (contentAlpha > 0.01) menuLayer,
                              if (anchorIconLayer != null) anchorIconLayer,
                            ],
                          ),
                        ),
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
}

class _LiquidMenuRow extends StatefulWidget {
  final String label;
  final double height;
  final Color textColor;
  final VoidCallback onTap;

  const _LiquidMenuRow({
    required this.label,
    required this.height,
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
        height: widget.height,
        margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.centerLeft,
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
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
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
