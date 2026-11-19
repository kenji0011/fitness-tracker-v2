import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';

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

/// Displays an iOS-style spring popover menu anchored cleanly below [anchorKey].
Future<void> showTempoPopoverMenu({
  required BuildContext context,
  required GlobalKey anchorKey,
  required List<TempoPopoverAction> actions,
  double width = 186,
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
    anchorRect = Rect.fromLTWH(size.width - 56, 56, 44, 44);
  }

  return Navigator.of(context).push<void>(
    _IosPopoverMenuRoute(
      anchorRect: anchorRect,
      actions: actions,
      width: width,
    ),
  );
}

class _IosPopoverSpringCurve extends Curve {
  static final _sim = SpringSimulation(
    const SpringDescription(mass: 1.0, stiffness: 460.0, damping: 28.0),
    0.0,
    1.0,
    0.0,
  );

  const _IosPopoverSpringCurve();

  @override
  double transformInternal(double t) {
    if (t <= 0.0) return 0.0;
    if (t >= 1.0) return 1.0;
    return _sim.x(t * 0.36);
  }
}

class _IosPopoverMenuRoute extends PopupRoute<void> {
  final Rect anchorRect;
  final List<TempoPopoverAction> actions;
  final double width;

  static const _springCurve = _IosPopoverSpringCurve();

  _IosPopoverMenuRoute({
    required this.anchorRect,
    required this.actions,
    required this.width,
  });

  @override
  Color? get barrierColor => Colors.black.withValues(alpha: 0.16);

  @override
  bool get barrierDismissible => true;

  @override
  String? get barrierLabel => 'Dismiss menu';

  @override
  Duration get transitionDuration => const Duration(milliseconds: 300);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 180);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    final c = AppColors.of(context);
    final screen = MediaQuery.sizeOf(context);
    final rightEdge = (screen.width - anchorRect.right).clamp(14.0, screen.width);
    final topEdge = (anchorRect.bottom + 6).clamp(16.0, screen.height - 220);

    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final rawT = animation.value;
        final isClosing = animation.status == AnimationStatus.reverse;
        final curved = isClosing
            ? Curves.easeInCubic.transform(rawT)
            : _springCurve.transform(rawT);
        final scale = 0.42 + 0.58 * curved;
        final opacity = (rawT * 1.8).clamp(0.0, 1.0);

        return Stack(
          children: [
            Positioned(
              top: topEdge,
              right: rightEdge,
              width: width,
              child: Opacity(
                opacity: opacity,
                child: Transform.scale(
                  scale: scale,
                  alignment: Alignment.topRight,
                  child: child,
                ),
              ),
            ),
          ],
        );
      },
      child: Material(
        type: MaterialType.transparency,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: c.isDark ? 0.48 : 0.14),
                blurRadius: 28,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: c.isDark
                      ? const Color(0xFF28292E).withValues(alpha: 0.94)
                      : Colors.white.withValues(alpha: 0.94),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: c.isDark
                        ? Colors.white.withValues(alpha: 0.10)
                        : Colors.black.withValues(alpha: 0.06),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: List.generate(actions.length, (i) {
                    final action = actions[i];
                    return InkWell(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        Navigator.of(context).pop();
                        action.onTap();
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 14,
                        ),
                        child: Text(
                          action.label,
                          style: TextStyle(
                            color: action.textColor ?? c.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            letterSpacing: -0.1,
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
