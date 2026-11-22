import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';

/// Optically centered thin `<` chevron matching the iOS 26 / HyperOS 3 back button.
class TempoBackChevron extends StatelessWidget {
  final Color color;
  final double size;

  const TempoBackChevron({
    super.key,
    required this.color,
    this.size = 20,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _ThinChevronPainter(color: color),
    );
  }
}

class _ThinChevronPainter extends CustomPainter {
  final Color color;

  const _ThinChevronPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // Optically centered left-pointing chevron inside circular glass button:
    // tip at 0.34w, open ends at 0.62w -> balanced visual center around 0.48w.
    final tipX = size.width * 0.34;
    final endX = size.width * 0.62;
    final cy = size.height * 0.50;
    final dy = size.height * 0.31;

    final path = Path()
      ..moveTo(endX, cy - dy)
      ..lineTo(tipX, cy)
      ..lineTo(endX, cy + dy);

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _ThinChevronPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// Action descriptor for [TempoSliverHeader].
class TempoHeaderAction {
  final Widget icon;
  final VoidCallback onPressed;
  final String? tooltip;

  const TempoHeaderAction({
    required this.icon,
    required this.onPressed,
    this.tooltip,
  });
}

/// Circular Liquid Glass icon button with specular glass rim and BitChord-style
/// droplet squish-and-spring press animation.
class TempoGlassCircleButton extends StatefulWidget {
  final Widget icon;
  final VoidCallback onPressed;
  final double glassOpacity;
  final double size;
  final String? tooltip;

  const TempoGlassCircleButton({
    super.key,
    required this.icon,
    required this.onPressed,
    required this.glassOpacity,
    this.size = 42,
    this.tooltip,
  });

  @override
  State<TempoGlassCircleButton> createState() => _TempoGlassCircleButtonState();
}

class _TempoGlassCircleButtonState extends State<TempoGlassCircleButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final isDark = c.isDark;
    // Always maintain a subtle translucent liquid glass pill (min 0.42),
    // deepening smoothly to 1.0 as content scrolls behind the header or on press.
    final g = (_pressed ? 1.0 : (0.42 + 0.58 * widget.glassOpacity.clamp(0.0, 1.0)))
        .clamp(0.0, 1.0);

    Widget btn = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: () {
        HapticFeedback.selectionClick();
        widget.onPressed();
      },
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0.0, end: _pressed ? 1.0 : 0.0),
        duration: Duration(milliseconds: _pressed ? 105 : 290),
        curve: _pressed ? Curves.easeOutCubic : Curves.easeOutBack,
        builder: (context, p, child) {
          // Liquid droplet squish on press, spring rebound on release
          final sx = 1.0 + 0.09 * p;
          final sy = 1.0 - 0.08 * p;
          return Transform(
            alignment: Alignment.center,
            transform: Matrix4.diagonal3Values(sx, sy, 1.0),
            child: child,
          );
        },
        child: SizedBox(
          width: widget.size,
          height: widget.size,
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(
                    alpha: (isDark ? 0.36 : 0.075) * g,
                  ),
                  blurRadius: 14 * g,
                  offset: Offset(0, 4 * g),
                ),
              ],
            ),
            child: ClipOval(
              child: BackdropFilter(
                filter: ImageFilter.blur(
                  sigmaX: 18 * g,
                  sigmaY: 18 * g,
                ),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 140),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: isDark
                          ? [
                              const Color(0xFF383940)
                                  .withValues(alpha: (_pressed ? 0.88 : 0.74) * g),
                              const Color(0xFF1A1B1F)
                                  .withValues(alpha: (_pressed ? 0.82 : 0.66) * g),
                            ]
                          : [
                              Colors.white
                                  .withValues(alpha: (_pressed ? 0.94 : 0.84) * g),
                              const Color(0xFFF1F2F7)
                                  .withValues(alpha: (_pressed ? 0.86 : 0.72) * g),
                            ],
                    ),
                    border: Border.all(
                      color: isDark
                          ? Colors.white.withValues(
                              alpha: (_pressed ? 0.32 : 0.18) * g,
                            )
                          : Colors.black.withValues(
                              alpha: (_pressed ? 0.12 : 0.075) * g,
                            ),
                      width: 1.0,
                    ),
                  ),
                  child: Center(child: widget.icon),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    if (widget.tooltip != null) {
      btn = Tooltip(message: widget.tooltip!, child: btn);
    }
    return btn;
  }
}

/// Pinned collapsing sliver header with iOS-style **fade-only** title transition:
/// - **Expanded (at top):** Large left-aligned title fades out smoothly as you scroll up.
/// - **Scrolled up (collapsed):** Compact centered title fades in cleanly inside the pinned
///   top bar while the leading back chevron & trailing action icons gain circular Liquid Glass bubbles.
class TempoSliverHeader extends StatelessWidget {
  final String title;
  final bool showBackButton;
  final VoidCallback? onBack;
  final List<TempoHeaderAction> actions;

  const TempoSliverHeader({
    super.key,
    required this.title,
    this.showBackButton = false,
    this.onBack,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.paddingOf(context).top;
    final c = AppColors.of(context);

    return SliverPersistentHeader(
      pinned: true,
      delegate: _TempoSliverHeaderDelegate(
        title: title,
        showBackButton: showBackButton,
        onBack: onBack ?? () => Navigator.of(context).maybePop(),
        actions: actions,
        topPadding: topPad,
        colors: c,
      ),
    );
  }
}

class _TempoSliverHeaderDelegate extends SliverPersistentHeaderDelegate {
  final String title;
  final bool showBackButton;
  final VoidCallback onBack;
  final List<TempoHeaderAction> actions;
  final double topPadding;
  final AppColors colors;

  static const double _toolbarHeight = 56.0;
  static const double _largeTitleExtra = 54.0;

  const _TempoSliverHeaderDelegate({
    required this.title,
    required this.showBackButton,
    required this.onBack,
    required this.actions,
    required this.topPadding,
    required this.colors,
  });

  @override
  double get minExtent => topPadding + _toolbarHeight;

  @override
  double get maxExtent => topPadding + _toolbarHeight + _largeTitleExtra;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final c = AppColors.of(context);
    final range = (maxExtent - minExtent).clamp(1.0, double.infinity);
    final rawT = (shrinkOffset / range).clamp(0.0, 1.0);

    // Pure cross-fade title transition (no morph/size-jump)
    final largeTitleOpacity = (1.0 - (rawT / 0.55)).clamp(0.0, 1.0);
    final compactTitleOpacity = ((rawT - 0.50) / 0.40).clamp(0.0, 1.0);

    // Circular glass bubbles fade in cleanly as user scrolls up
    final glassOpacity = ((rawT - 0.15) / 0.65).clamp(0.0, 1.0);
    final barScrimOpacity = ((rawT - 0.25) / 0.70).clamp(0.0, 1.0);

    final sideClearance = (actions.length * 48.0 + 20.0).clamp(68.0, 140.0);

    return SizedBox.expand(
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Soft translucent gradient backdrop as header collapses
          if (barScrimOpacity > 0.01)
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      c.scaffold.withValues(alpha: 0.94 * barScrimOpacity),
                      c.scaffold.withValues(alpha: 0.82 * barScrimOpacity),
                      c.scaffold.withValues(alpha: 0.0),
                    ],
                    stops: const [0.0, 0.78, 1.0],
                  ),
                ),
              ),
            ),

          // Expanded Large Title (fades out cleanly as content scrolls up)
          if (largeTitleOpacity > 0.01)
            Positioned(
              left: 20,
              right: 20,
              top: topPadding + _toolbarHeight + 4.0 - shrinkOffset * 0.45,
              child: IgnorePointer(
                child: Opacity(
                  opacity: largeTitleOpacity,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      title,
                      maxLines: 1,
                      style: TextStyle(
                        color: c.textPrimary,
                        fontSize: 34,
                        fontWeight: FontWeight.w500,
                        letterSpacing: -0.9,
                        height: 1.15,
                      ),
                    ),
                  ),
                ),
              ),
            ),

          // Collapsed Centered Title (fades in cleanly inside the pinned toolbar)
          if (compactTitleOpacity > 0.01)
            Positioned(
              top: topPadding,
              left: sideClearance,
              right: sideClearance,
              height: _toolbarHeight,
              child: IgnorePointer(
                child: Opacity(
                  opacity: compactTitleOpacity,
                  child: Center(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: c.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ),
                ),
              ),
            ),

          // Pinned top toolbar with Leading Back Chevron + Trailing Action Icons
          Positioned(
            top: topPadding,
            left: 14,
            right: 14,
            height: _toolbarHeight,
            child: Row(
              children: [
                if (showBackButton)
                  TempoGlassCircleButton(
                    glassOpacity: glassOpacity,
                    tooltip: 'Back',
                    onPressed: onBack,
                    icon: TempoBackChevron(color: c.textPrimary, size: 22),
                  ),
                const Spacer(),
                for (int i = 0; i < actions.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  TempoGlassCircleButton(
                    glassOpacity: glassOpacity,
                    tooltip: actions[i].tooltip,
                    onPressed: actions[i].onPressed,
                    icon: actions[i].icon,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _TempoSliverHeaderDelegate oldDelegate) =>
      oldDelegate.title != title ||
      oldDelegate.showBackButton != showBackButton ||
      oldDelegate.actions.length != actions.length ||
      oldDelegate.topPadding != topPadding ||
      oldDelegate.colors.isDark != colors.isDark;
}
