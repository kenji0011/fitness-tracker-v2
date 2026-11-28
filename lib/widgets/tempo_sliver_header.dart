import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/appearance_service.dart';
import '../theme/app_colors.dart';
import 'bitchord_glass_lens.dart';
import 'ios_popover_menu.dart';
import 'liquid_glass_surface.dart';
import 'tempo_morph_route.dart';

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
  final Key? buttonKey;

  const TempoHeaderAction({
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.buttonKey,
  });
}

/// Circular BitChord-calibrated Liquid Glass icon button with crystal-clear
/// translucent blur (`sigma = 8.5`), optional live circular dome refraction
/// (enabled on pinned header controls once route transitions settle), jewel-crisp
/// 45° specular glass rim, and droplet squish-and-spring press physics.
class TempoGlassCircleButton extends StatefulWidget {
  final Widget icon;
  final VoidCallback onPressed;
  final double glassOpacity;
  final double size;
  final String? tooltip;
  final Color? tintColor;
  final bool enableBlur;
  final bool enableRefraction;

  const TempoGlassCircleButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.glassOpacity = 1.0,
    this.size = 42,
    this.tooltip,
    this.tintColor,
    this.enableBlur = true,
    this.enableRefraction = false,
  });

  @override
  State<TempoGlassCircleButton> createState() => _TempoGlassCircleButtonState();
}

class _TempoGlassCircleButtonState extends State<TempoGlassCircleButton> {
  bool _pressed = false;
  Animation<double>? _routeAnim;
  bool _routeSettled = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final nextAnim = ModalRoute.of(context)?.animation;
    if (!identical(_routeAnim, nextAnim)) {
      _routeAnim?.removeStatusListener(_onRouteStatus);
      _routeAnim = nextAnim;
      _routeAnim?.addStatusListener(_onRouteStatus);
      _routeSettled = _routeAnim == null ||
          _routeAnim!.status == AnimationStatus.completed;
    }
  }

  void _onRouteStatus(AnimationStatus status) {
    final settled = status == AnimationStatus.completed;
    if (settled != _routeSettled && mounted) {
      setState(() => _routeSettled = settled);
    }
  }

  @override
  void dispose() {
    _routeAnim?.removeStatusListener(_onRouteStatus);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final isDark = c.isDark;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final appearance = TempoAppearanceService.instance.value;
    final useBlur = widget.enableBlur && appearance.allowDynamicBlur;
    final useRim = appearance.useLiquidGlass;
    final useLens = widget.enableRefraction &&
        useBlur &&
        appearance.useGlassRefraction &&
        _routeSettled;
    final scrollBoost = widget.glassOpacity.clamp(0.0, 1.0);
    final rimIntensity = _pressed ? 1.30 : (1.08 + 0.10 * scrollBoost);
    final shadowAlpha = (isDark ? 0.36 : 0.085) * (0.88 + 0.12 * scrollBoost);
    // BitChord LiquidGlass.kt calibration: transparent lively blur (8.5 dp)
    // so colors behind glow right through the circle; 14 dp under Better Perf.
    final blurSigma = _pressed
        ? 11.5
        : (appearance.betterGlassPerformance ? 14.0 : 8.5);

    final innerFill = AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: !useBlur
            ? c.card
            : (widget.tintColor != null
                ? widget.tintColor!.withValues(
                    alpha: isDark
                        ? (_pressed ? 0.34 : 0.24)
                        : (_pressed ? 0.24 : 0.16),
                  )
                : (isDark
                    ? const Color(0xFF121212)
                        .withValues(alpha: _pressed ? 0.40 : 0.28)
                    : const Color(0xFFFAFAFA)
                        .withValues(alpha: _pressed ? 0.44 : 0.34))),
        border: Border.all(
          color: useRim
              ? (widget.tintColor != null
                  ? widget.tintColor!.withValues(alpha: isDark ? 0.40 : 0.30)
                  : (isDark
                      ? Colors.white.withValues(alpha: 0.16)
                      : Colors.white.withValues(alpha: 0.68)))
              : c.cardBorder,
          width: useRim ? 0.6 : 0.8,
        ),
      ),
      child: Center(child: widget.icon),
    );

    final glassInner = useRim
        ? CustomPaint(
            foregroundPainter: LiquidGlassRimPainter(
              borderRadius: widget.size / 2,
              isDark: isDark,
              intensity: rimIntensity,
              strokeWidth: 1.25,
              showTopMeniscus: false,
              tintColor: widget.tintColor,
            ),
            child: innerFill,
          )
        : innerFill;

    final refractedChild = useLens
        ? BitChordGlassLensBox(
            program: TempoLiquidShaderCache.program,
            isDark: isDark,
            dpr: dpr,
            useRefractionShader: true,
            frameBuilder: (sz) {
              if (sz.isEmpty) return BitChordLensFrame.inactive;
              return BitChordLensFrame(
                active: true,
                rect: Offset.zero & sz,
                borderRadius: sz.shortestSide * 0.5,
                refractionHeightDp: 9.0,
                refractionAmountDp: 11.0,
                depthEffect: 0.45,
                aberration: 0.55,
                rimAlpha: 0.35,
                shadowAlpha: 0.0,
                material: 1.0,
              );
            },
            child: glassInner,
          )
        : glassInner;

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
          child: TempoTouchLightEffect(
            borderRadius: widget.size * 0.5,
            isAccentSurface: widget.tintColor != null,
            intensity: 1.08,
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: widget.tintColor != null
                        ? widget.tintColor!
                            .withValues(alpha: _pressed ? 0.28 : 0.18)
                        : Colors.black.withValues(alpha: shadowAlpha),
                    blurRadius: _pressed ? 18 : 14,
                    spreadRadius: -2,
                    offset: Offset(0, _pressed ? 3 : 5),
                  ),
                ],
              ),
              child: ClipOval(
                child: useBlur
                    ? BackdropFilter(
                        filter: ui.ImageFilter.blur(
                          sigmaX: blurSigma,
                          sigmaY: blurSigma,
                          tileMode: ui.TileMode.clamp,
                        ),
                        child: refractedChild,
                      )
                    : glassInner,
              ),
            ),
          ),
        ),
      ),
    );

    if (widget.tooltip != null) {
      btn = Tooltip(message: widget.tooltip!, child: btn);
    }

    // Wrap in RepaintBoundary for crisp circle-only morph snapshots, and replace
    // the entire button with an empty sized slot (zero ghost circle, zero
    // Opacity around BackdropFilter) while its detached HyperOS 4 popover OR
    // circular page morph droplet is active.
    if (widget.key != null) {
      return AnimatedBuilder(
        animation: Listenable.merge([
          activeTempoPopoverAnchorKey,
          activeTempoMorphAnchorKey,
        ]),
        builder: (_, __) {
          final isHidden =
              identical(activeTempoPopoverAnchorKey.value, widget.key) ||
                  identical(activeTempoMorphAnchorKey.value, widget.key);
          if (isHidden) {
            // Keep the slot clickable even mid-close bounce so rapid re-taps
            // launch immediately on the very first tap with zero delay!
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                HapticFeedback.selectionClick();
                widget.onPressed();
              },
              child: SizedBox.square(dimension: widget.size),
            );
          }
          return RepaintBoundary(child: btn);
        },
      );
    }
    return RepaintBoundary(child: btn);
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

    return ValueListenableBuilder<TempoAppearanceSettings>(
      valueListenable: TempoAppearanceService.instance.notifier,
      builder: (context, appearance, _) => SliverPersistentHeader(
        pinned: true,
        delegate: _TempoSliverHeaderDelegate(
          title: title,
          showBackButton: showBackButton,
          onBack: onBack ?? () => Navigator.of(context).maybePop(),
          actions: actions,
          topPadding: topPad,
          colors: c,
          progressiveBlur: appearance.useProgressiveBlur,
          betterGlassPerformance: appearance.betterGlassPerformance,
        ),
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
  final bool progressiveBlur;
  final bool betterGlassPerformance;

  static const double _toolbarHeight = 56.0;
  static const double _largeTitleExtra = 54.0;

  const _TempoSliverHeaderDelegate({
    required this.title,
    required this.showBackButton,
    required this.onBack,
    required this.actions,
    required this.topPadding,
    required this.colors,
    required this.progressiveBlur,
    required this.betterGlassPerformance,
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
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final range = (maxExtent - minExtent).clamp(1.0, double.infinity);
    final rawT = (shrinkOffset / range).clamp(0.0, 1.0);

    // Pure cross-fade title transition (no morph/size-jump)
    final largeTitleOpacity = (1.0 - (rawT / 0.55)).clamp(0.0, 1.0);
    final compactTitleOpacity = ((rawT - 0.50) / 0.40).clamp(0.0, 1.0);

    // Circular glass bubbles & borderless faded frosted blur ramp in smoothly
    final glassOpacity = ((rawT - 0.15) / 0.65).clamp(0.0, 1.0);
    final barScrimOpacity = ((rawT - 0.18) / 0.65).clamp(0.0, 1.0);
    final frostT = Curves.easeOutCubic.transform(barScrimOpacity);

    final sideClearance = (actions.length * 48.0 + 20.0).clamp(68.0, 140.0);

    return SizedBox.expand(
      child: Stack(
        fit: StackFit.expand,
        clipBehavior: Clip.none,
        children: [
          // Borderless 2-pass separable 625-tap Gaussian faded frosted blur
          // matching BitChord's TopFadeBlur (zero border line, melts invisibly
          // into crisp content 20 dp below the toolbar!).
          if (frostT > 0.01)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              bottom: -20,
              child: IgnorePointer(
                child: FrostedFadeBlurBackdrop(
                  program: TempoLiquidShaderCache.frostedFadeBlurProgram,
                  strength: frostT,
                  maxRadiusDp: betterGlassPerformance ? 9.5 : 15.0,
                  scrimColor: c.scaffold,
                  scrimAlpha: c.isDark ? 0.50 : 0.56,
                  softKnee: 0.34,
                  dpr: dpr,
                  enableFrostedBlur: progressiveBlur,
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
                    enableRefraction: true,
                    tooltip: 'Back',
                    onPressed: onBack,
                    icon: TempoBackChevron(color: c.textPrimary, size: 22),
                  ),
                const Spacer(),
                for (int i = 0; i < actions.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  TempoGlassCircleButton(
                    key: actions[i].buttonKey,
                    glassOpacity: glassOpacity,
                    enableRefraction: true,
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
      oldDelegate.colors.isDark != colors.isDark ||
      oldDelegate.progressiveBlur != progressiveBlur ||
      oldDelegate.betterGlassPerformance != betterGlassPerformance;
}
