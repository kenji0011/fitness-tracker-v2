import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/animation_speed_service.dart';
import '../theme/app_colors.dart';
import 'liquid_glass_surface.dart';
import 'tempo_spring_physics.dart';

/// Tracks the currently detached popover's anchor button [Key] so
/// `TempoGlassCircleButton` suppresses its inner glyph while the floating
/// droplet swings out and docks back (zero double-icon ghosting).
final ValueNotifier<Key?> activeTempoPopoverAnchorKey =
    ValueNotifier<Key?>(null);

/// Tracks the active popover owner per anchor [Key] so rapid re-taps mid-close
/// take over seamlessly without stale closing droplets or premature key clears.
final Map<Key, Object> _activePopoverOwnerByKey = <Key, Object>{};

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
  double? anchorIconSize,
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

  // Exact sub-pixel size match with TempoGlassCircleButton header icons
  // (22dp for CupertinoIcons.add in Sleep/Weight/Water/Metric, 19dp for ⋮).
  final resolvedIconSize =
      anchorIconSize ?? (anchorIcon == CupertinoIcons.add ? 22.0 : 19.0);

  return Navigator.of(context).push<void>(
    _HyperOsLiquidPopoverRoute(
      anchorKey: anchorKey,
      anchorRect: anchorRect,
      actions: actions,
      width: width,
      anchorIcon: anchorIcon,
      anchorIconSize: resolvedIconSize,
    ),
  );
}

class _HyperOsLiquidPopoverRoute extends PopupRoute<void> {
  final GlobalKey anchorKey;
  final Rect anchorRect;
  final List<TempoPopoverAction> actions;
  final double width;
  final IconData anchorIcon;
  final double anchorIconSize;

  /// Constant BackdropFilter sigma avoids Impeller blur kernel churn at 120Hz.
  static final ImageFilter _glassBlurFilter = ImageFilter.blur(
    sigmaX: 24.0,
    sigmaY: 24.0,
  );

  bool _attachedStatusListener = false;

  _HyperOsLiquidPopoverRoute({
    required this.anchorKey,
    required this.anchorRect,
    required this.actions,
    required this.width,
    required this.anchorIcon,
    required this.anchorIconSize,
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
      TempoAnimationSpeedService.instance.scale(const Duration(milliseconds: 470));

  void _syncAnchorSuppression(bool hideIcon) {
    if (hideIcon) {
      _activePopoverOwnerByKey[anchorKey] = this;
      if (!identical(activeTempoPopoverAnchorKey.value, anchorKey)) {
        activeTempoPopoverAnchorKey.value = anchorKey;
      }
    } else if (identical(_activePopoverOwnerByKey[anchorKey], this)) {
      _activePopoverOwnerByKey.remove(anchorKey);
      if (identical(activeTempoPopoverAnchorKey.value, anchorKey)) {
        activeTempoPopoverAnchorKey.value = null;
      }
    }
  }

  bool get _supersededByNewerPopover {
    final owner = _activePopoverOwnerByKey[anchorKey];
    return owner != null && !identical(owner, this);
  }

  @override
  Widget buildModalBarrier() {
    final anim = animation;
    if (anim == null) return const SizedBox.shrink();
    return AnimatedBuilder(
      animation: anim,
      builder: (context, _) {
        // Drop the modal barrier immediately on close so the user can re-tap
        // the button or anything else on screen with 0 ms delay!
        if (anim.status == AnimationStatus.reverse ||
            anim.status == AnimationStatus.dismissed) {
          return const SizedBox.shrink();
        }
        return super.buildModalBarrier();
      },
    );
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

    final menuRows = RepaintBoundary(
      child: SizedBox(
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
      ),
    );

    return AnimatedBuilder(
      animation: animation,
      child: menuRows,
      builder: (context, child) {
        final rawT = animation.value.clamp(0.0, 1.0);
        final isClosing = animation.status == AnimationStatus.reverse ||
            animation.status == AnimationStatus.dismissed;

        // If user re-tapped the button mid-close, yield immediately to the new popover.
        if (isClosing && _supersededByNewerPopover) {
          return const SizedBox.shrink();
        }

        final double centerT;
        final double sizeT;
        final double contentAlpha;
        final double contentSigma;
        final double anchorIconAlpha;
        final double anchorIconSigma;
        double closeElasticScale = 1.0;

        if (isClosing) {
          final closeP = (1.0 - rawT).clamp(0.0, 1.0);
          // Inverted underdamped springs: size collapses faster than center into a
          // floating circular droplet, then lands in the button slot with a crisp
          // liquid squish-rebound + soft ~4.5px positional dock bounce!
          final sizeCollapse = TempoSpringCurves.popoverCloseSize.transform(closeP);
          final centerReturn = TempoSpringCurves.popoverCloseCenter.transform(closeP);

          sizeT = closeP < 0.48 ? (1.0 - sizeCollapse).clamp(0.0, 1.0) : 0.0;
          final dockDelta =
              closeP >= 0.48 ? (1.0 - sizeCollapse) : math.min(0.0, 1.0 - sizeCollapse);
          closeElasticScale = (1.0 + dockDelta * 1.10).clamp(0.88, 1.05);
          centerT = 1.0 - centerReturn; // allows natural subtle negative dock overshoot!

          // Menu text Gaussian-blurs and dissolves smoothly during first 34% of close.
          final outP = (closeP / 0.34).clamp(0.0, 1.0);
          contentAlpha = (1.0 - Curves.easeOutCubic.transform(outP)).clamp(0.0, 1.0);
          final rawContentSigma = 9.0 * Curves.easeOutQuad.transform(outP);
          contentSigma = (rawContentSigma * 2.0).round() / 2.0;

          // Anchor glyph reaches full 1.0 opacity & crispness BEFORE the droplet
          // hits the button slot (closeP = 0.14..0.34) so the + / ⋮ icon never
          // looks small or expands late once parked in place!
          final inP = ((closeP - 0.14) / 0.22).clamp(0.0, 1.0);
          anchorIconAlpha = Curves.easeOutCubic.transform(inP).clamp(0.0, 1.0);
          final rawAnchorSigma =
              5.5 * (1.0 - Curves.easeOutCubic.transform(inP)).clamp(0.0, 1.0);
          anchorIconSigma = (rawAnchorSigma * 2.0).round() / 2.0;
        } else {
          // Open springs: center shoots ahead of size -> detached droplet launch + elastic bloom!
          centerT = TempoSpringCurves.popoverOpenCenter.transform(rawT);
          sizeT = TempoSpringCurves.popoverOpenSize.transform(rawT);

          // Anchor glyph blurs & dissolves out of the launching circular droplet.
          final iconOutP = (rawT / 0.22).clamp(0.0, 1.0);
          anchorIconAlpha =
              (1.0 - Curves.easeOutCubic.transform(iconOutP)).clamp(0.0, 1.0);
          final rawAnchorSigma = 6.5 * Curves.easeInQuad.transform(iconOutP);
          anchorIconSigma = (rawAnchorSigma * 2.0).round() / 2.0;

          // Menu rows emerge heavily Gaussian-blurred and sharpen crisp by ~220ms.
          final contentInP = ((rawT - 0.12) / 0.32).clamp(0.0, 1.0);
          contentAlpha = Curves.easeOutCubic.transform(contentInP).clamp(0.0, 1.0);
          final rawContentSigma =
              9.5 * (1.0 - Curves.easeOutCubic.transform(contentInP)).clamp(0.0, 1.0);
          contentSigma = (rawContentSigma * 2.0).round() / 2.0;
        }

        // Detached center-driven geometry with smooth parabolic dock bounce on close:
        final detachDelta = (centerT.clamp(0.0, 1.04) - sizeT).clamp(-0.04, 0.38);
        final arcNudgeY = math.max(0.0, detachDelta) * 24.0;
        final Offset curCenter;
        if (isClosing && centerT < 0.0) {
          // Smooth parabolic overshoot (~4.5px max) past button slot along approach vector.
          final travel = endCenter - startCenter;
          final dist = travel.distance;
          final dir = dist > 0.1 ? travel / dist : Offset.zero;
          curCenter = startCenter + dir * (centerT * math.min(dist, 48.0));
        } else {
          curCenter = Offset.lerp(startCenter, endCenter, centerT)! +
              Offset(0.0, arcNudgeY);
        }

        final baseW = isClosing
            ? lerpDouble(startW, targetWidth, sizeT)! * closeElasticScale
            : math.max(startW * 0.94, lerpDouble(startW, targetWidth, sizeT)!);
        final baseH = isClosing
            ? lerpDouble(startH, targetHeight, sizeT)! * closeElasticScale
            : math.max(startH * 0.94, lerpDouble(startH, targetHeight, sizeT)!);
        final curW = math.max(startW * 0.85, baseW);
        final curH = math.max(startH * 0.85, baseH);
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

        // Option A: Tempo Liquid Glass frosted surface matched 1:1 with
        // TempoGlassCircleButton's resting gradient at sizeT = 0 (invisible handoff!).
        final topBgAlpha = lerpDouble(
          c.isDark ? 0.72 : 0.78,
          c.isDark ? 0.78 : 0.90,
          clampedSizeT,
        )!;
        final bottomBgAlpha = lerpDouble(
          c.isDark ? 0.76 : 0.68,
          c.isDark ? 0.84 : 0.81,
          clampedSizeT,
        )!;
        final rimIntensity = lerpDouble(0.98, 1.08, clampedSizeT)!;
        final shadowAlpha = lerpDouble(
          c.isDark ? 0.36 : 0.095,
          c.isDark ? 0.44 : 0.14,
          clampedSizeT,
        )!;

        // Proportional menu content scale following the container width smoothly.
        final contentScale = (curW / targetWidth).clamp(0.38, 1.03);
        // Keep anchor glyph near 1.0 full size during close so it never pops larger on handoff!
        final iconScale = lerpDouble(0.90, 1.0, anchorIconAlpha)! *
            (isClosing ? (1.0 + (closeElasticScale - 1.0) * 0.55) : 1.0);

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
        if (contentSigma >= 0.5) {
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
                    size: anchorIconSize,
                    color: c.textPrimary,
                  ),
                ),
              ),
            ),
          );
          if (anchorIconSigma >= 0.5) {
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

        return IgnorePointer(
          ignoring: isClosing,
          child: Stack(
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
                          blurRadius: 24.0,
                          spreadRadius: 0,
                          offset: Offset(0, lerpDouble(5.0, 10.0, clampedSizeT)!),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(curRadius),
                      child: BackdropFilter(
                        filter: _glassBlurFilter,
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
                                        const Color(0xFF363842)
                                            .withValues(alpha: topBgAlpha),
                                        const Color(0xFF17181E)
                                            .withValues(alpha: bottomBgAlpha),
                                      ]
                                    : [
                                        Colors.white
                                            .withValues(alpha: topBgAlpha),
                                        const Color(0xFFF3F5FA)
                                            .withValues(alpha: bottomBgAlpha),
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
          ),
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
