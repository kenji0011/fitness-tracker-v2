import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/tempo_rust_db.dart';
import '../theme/app_colors.dart';
import 'tempo_startup_splash.dart';

class TempoSpotlightStep {
  final GlobalKey targetKey;
  final String title;
  final String description;
  final double borderRadius;
  final EdgeInsets padding;

  const TempoSpotlightStep({
    required this.targetKey,
    required this.title,
    required this.description,
    this.borderRadius = 22,
    this.padding = const EdgeInsets.all(6),
  });
}

/// First-time contextual spotlight coach-mark overlay engineered for locked
/// 120Hz fluidity:
/// - Zero `Opacity` / `FadeTransition` wrappers around `BackdropFilter`
/// - Isolated `RepaintBoundary` scrim that only repaints during morphs
/// - Persistent frosted glass tooltip card whose inner copy cross-fades cleanly
class TempoSpotlightTour {
  static const List<String> _allScreenIds = [
    'summary',
    'workout',
    'workout_detail',
    'progress',
    'profile',
  ];

  static bool _isShowing = false;

  static String _settingKey(String screenId, String profileId) =>
      'hint_tour_${screenId}_$profileId';

  static bool _isRunningInTest() {
    return WidgetsBinding.instance.runtimeType.toString().contains('Test');
  }

  /// Clears all seen spotlight flags for [profileId] so hints can be replayed.
  static Future<void> resetAllTours(String profileId) async {
    final db = TempoRustDb.instance;
    for (final id in _allScreenIds) {
      await db.setSetting(_settingKey(id, profileId), '');
    }
  }

  /// Shows the spotlight tour once per [screenId] per [profileId].
  static Future<void> showIfNeeded({
    required BuildContext context,
    required String profileId,
    required String screenId,
    required List<TempoSpotlightStep> steps,
    Duration delay = const Duration(milliseconds: 520),
    bool forceShow = false,
    bool ignoreTestGuard = false,
  }) async {
    if (steps.isEmpty || profileId.isEmpty) return;
    if (!ignoreTestGuard && !forceShow && _isRunningInTest()) return;
    if (_isShowing) return;

    if (!forceShow) {
      final seen = await TempoRustDb.instance
          .getSetting(_settingKey(screenId, profileId));
      if (seen == '1') return;
    }

    await TempoStartupSplash.waitForCompletion();
    if (!context.mounted) return;

    if (delay > Duration.zero) {
      await Future<void>.delayed(delay);
    }
    if (!context.mounted) return;
    // Never fire a spotlight from an inactive hidden tab in TempoShellScreen
    if (!TickerMode.of(context)) return;
    if (_isShowing) return;

    final hasAnyTarget = steps.any((s) => s.targetKey.currentContext != null);
    if (!hasAnyTarget) return;

    _isShowing = true;
    try {
      await TempoRustDb.instance
          .setSetting(_settingKey(screenId, profileId), '1');
      if (!context.mounted) return;
      await Navigator.of(context, rootNavigator: true).push<void>(
        _SpotlightOverlayRoute(steps: steps),
      );
    } finally {
      _isShowing = false;
    }
  }
}

class _SpotlightOverlayRoute extends PopupRoute<void> {
  final List<TempoSpotlightStep> steps;

  _SpotlightOverlayRoute({required this.steps});

  @override
  Color? get barrierColor => Colors.transparent;

  @override
  bool get barrierDismissible => false;

  @override
  String? get barrierLabel => 'Feature hint';

  @override
  Duration get transitionDuration => const Duration(milliseconds: 280);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 220);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return _SpotlightOverlayBody(
      steps: steps,
      routeAnimation: animation,
    );
  }
}

class _SpotlightOverlayBody extends StatefulWidget {
  final List<TempoSpotlightStep> steps;
  final Animation<double> routeAnimation;

  const _SpotlightOverlayBody({
    required this.steps,
    required this.routeAnimation,
  });

  @override
  State<_SpotlightOverlayBody> createState() => _SpotlightOverlayBodyState();
}

class _SpotlightOverlayBodyState extends State<_SpotlightOverlayBody>
    with SingleTickerProviderStateMixin {
  late final AnimationController _morphCtrl;
  late final Animation<double> _morphAnim;

  int _index = 0;
  Rect? _fromRect;
  Rect? _toRect;
  double _fromRadius = 22;
  double _toRadius = 22;
  bool _ready = false;

  List<TempoSpotlightStep> get _validSteps =>
      widget.steps.where((s) => s.targetKey.currentContext != null).toList();

  @override
  void initState() {
    super.initState();
    _morphCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 340),
    );
    _morphAnim = CurvedAnimation(
      parent: _morphCtrl,
      curve: Curves.easeOutCubic,
    );
    // Measure first step synchronously if already laid out so there is zero jump
    final initial = _measureStepImmediate(0);
    if (initial != null) {
      _fromRect = initial.$1;
      _toRect = initial.$1;
      _fromRadius = initial.$2;
      _toRadius = initial.$2;
      _morphCtrl.value = 1.0;
      _ready = true;
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => _focusStep(0));
    }
  }

  @override
  void dispose() {
    _morphCtrl.dispose();
    super.dispose();
  }

  (Rect, double)? _measureStepImmediate(int idx) {
    final steps = _validSteps;
    if (idx < 0 || idx >= steps.length) return null;
    final step = steps[idx];
    final box =
        step.targetKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize || !box.attached) return null;
    final topLeft = box.localToGlobal(Offset.zero);
    final padded = Rect.fromLTRB(
      topLeft.dx - step.padding.left,
      topLeft.dy - step.padding.top,
      topLeft.dx + box.size.width + step.padding.right,
      topLeft.dy + box.size.height + step.padding.bottom,
    );
    return (padded, step.borderRadius);
  }

  Rect get _currentRect {
    if (_fromRect == null || _toRect == null) return Rect.zero;
    return Rect.lerp(_fromRect, _toRect, _morphAnim.value) ?? _toRect!;
  }

  double get _currentRadius =>
      lerpDouble(_fromRadius, _toRadius, _morphAnim.value) ?? _toRadius;

  Future<void> _focusStep(int nextIndex) async {
    final steps = _validSteps;
    if (steps.isEmpty || nextIndex >= steps.length) {
      if (mounted) Navigator.of(context).pop();
      return;
    }

    final step = steps[nextIndex];
    final targetCtx = step.targetKey.currentContext;
    if (targetCtx != null) {
      try {
        await Scrollable.ensureVisible(
          targetCtx,
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
          alignment: 0.35,
        );
      } catch (_) {}
    }

    if (!mounted) return;
    final measured = _measureStepImmediate(nextIndex);
    if (measured == null) {
      if (nextIndex + 1 < steps.length) {
        _focusStep(nextIndex + 1);
      } else {
        Navigator.of(context).pop();
      }
      return;
    }

    final nextRect = measured.$1;
    final nextRadius = measured.$2;

    if (!_ready) {
      setState(() {
        _index = nextIndex;
        _fromRect = nextRect;
        _toRect = nextRect;
        _fromRadius = nextRadius;
        _toRadius = nextRadius;
        _morphCtrl.value = 1.0;
        _ready = true;
      });
    } else {
      final startRect = _currentRect;
      final startRadius = _currentRadius;
      setState(() {
        _index = nextIndex;
        _fromRect = startRect;
        _toRect = nextRect;
        _fromRadius = startRadius;
        _toRadius = nextRadius;
      });
      _morphCtrl.forward(from: 0.0);
    }
  }

  void _next() {
    HapticFeedback.selectionClick();
    final steps = _validSteps;
    if (_index + 1 >= steps.length) {
      Navigator.of(context).pop();
    } else {
      _focusStep(_index + 1);
    }
  }

  void _skip() {
    HapticFeedback.selectionClick();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final screen = MediaQuery.sizeOf(context);
    final pad = MediaQuery.paddingOf(context);
    final steps = _validSteps;
    if (steps.isEmpty || !_ready) return const SizedBox.shrink();

    final safeIdx = _index.clamp(0, steps.length - 1);
    final step = steps[safeIdx];
    final targetRect = _toRect ?? Rect.zero;
    final isLast = safeIdx >= steps.length - 1;

    final spaceBelow = screen.height - targetRect.bottom - pad.bottom;
    final showAbove = spaceBelow < 210 && targetRect.top > 210;
    final cardTop = showAbove
        ? (targetRect.top - 178).clamp(pad.top + 16, screen.height - pad.bottom - 185)
        : (targetRect.bottom + 16).clamp(pad.top + 16, screen.height - pad.bottom - 185);

    return Material(
      type: MaterialType.transparency,
      child: AnimatedBuilder(
        animation: widget.routeAnimation,
        builder: (context, _) {
          final rawRoute = widget.routeAnimation.value.clamp(0.0, 1.0);
          final isClosing =
              widget.routeAnimation.status == AnimationStatus.reverse;
          final routeT = isClosing
              ? (1.0 - Curves.easeOutCubic.transform(1.0 - rawRoute))
                  .clamp(0.0, 1.0)
              : Curves.easeOutCubic.transform(rawRoute).clamp(0.0, 1.0);
          final blurSigma = (22.0 * routeT).clamp(0.0, 22.0);
          final cardScale = lerpDouble(0.94, 1.0, routeT)!;

          return Stack(
            children: [
              // Layer 1: Isolated RepaintBoundary spotlight cutout scrim
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _next,
                  child: RepaintBoundary(
                    child: AnimatedBuilder(
                      animation: _morphAnim,
                      builder: (_, __) => CustomPaint(
                        painter: _SpotlightScrimPainter(
                          holeRect: _currentRect,
                          borderRadius: _currentRadius,
                          accentColor: c.accent,
                          opacity: routeT,
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // Layer 2: Single persistent frosted glass tooltip card
              // (never wrapped in Opacity around BackdropFilter -> locked 120Hz!)
              AnimatedPositioned(
                duration: const Duration(milliseconds: 320),
                curve: Curves.easeOutCubic,
                left: 20,
                right: 20,
                top: cardTop,
                child: Transform.scale(
                  scale: cardScale,
                  child: RepaintBoundary(
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: routeT > 0.02
                            ? [
                                BoxShadow(
                                  color: Colors.black
                                      .withValues(alpha: 0.26 * routeT),
                                  blurRadius: 28 * routeT,
                                  offset: Offset(0, 12 * routeT),
                                ),
                              ]
                            : const [],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child: blurSigma > 0.4
                            ? BackdropFilter(
                                filter: ImageFilter.blur(
                                  sigmaX: blurSigma,
                                  sigmaY: blurSigma,
                                ),
                                child: _buildCardSurface(
                                  c: c,
                                  routeT: routeT,
                                  safeIdx: safeIdx,
                                  total: steps.length,
                                  step: step,
                                  isLast: isLast,
                                ),
                              )
                            : _buildCardSurface(
                                c: c,
                                routeT: routeT,
                                safeIdx: safeIdx,
                                total: steps.length,
                                step: step,
                                isLast: isLast,
                              ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildCardSurface({
    required AppColors c,
    required double routeT,
    required int safeIdx,
    required int total,
    required TempoSpotlightStep step,
    required bool isLast,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: c.isDark
              ? [
                  const Color(0xFF2B2C32).withValues(alpha: 0.92 * routeT),
                  const Color(0xFF1D1E23).withValues(alpha: 0.94 * routeT),
                ]
              : [
                  Colors.white.withValues(alpha: 0.95 * routeT),
                  const Color(0xFFF5F6FA).withValues(alpha: 0.92 * routeT),
                ],
        ),
        border: Border.all(
          color: c.isDark
              ? Colors.white.withValues(alpha: 0.16 * routeT)
              : Colors.black.withValues(alpha: 0.07 * routeT),
        ),
      ),
      child: Opacity(
        opacity: routeT,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: c.accent.withValues(alpha: c.isDark ? 0.22 : 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    'Tip ${safeIdx + 1} of $total',
                    style: TextStyle(
                      color: c.accent,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const Spacer(),
                if (!isLast)
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _skip,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 4,
                      ),
                      child: Text(
                        'Skip',
                        style: TextStyle(
                          color: c.textSecondary,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              layoutBuilder: (currentChild, previousChildren) => Stack(
                alignment: Alignment.centerLeft,
                children: [
                  ...previousChildren,
                  if (currentChild != null) currentChild,
                ],
              ),
              child: Column(
                key: ValueKey('tip_copy_$safeIdx'),
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    step.title,
                    style: TextStyle(
                      color: c.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    step.description,
                    style: TextStyle(
                      color: c.textSecondary,
                      fontSize: 14,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Row(
                  children: List.generate(total, (i) {
                    final active = i == safeIdx;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      margin: const EdgeInsets.only(right: 5),
                      width: active ? 18 : 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: active
                            ? c.accent
                            : c.textTertiary.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(99),
                      ),
                    );
                  }),
                ),
                const Spacer(),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _next,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      color: c.accent,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      isLast ? 'Got it' : 'Next',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SpotlightScrimPainter extends CustomPainter {
  final Rect holeRect;
  final double borderRadius;
  final Color accentColor;
  final double opacity;

  const _SpotlightScrimPainter({
    required this.holeRect,
    required this.borderRadius,
    required this.accentColor,
    required this.opacity,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (opacity <= 0.005) return;

    final full = Path()..addRect(Offset.zero & size);
    final hole = RRect.fromRectAndRadius(
      holeRect,
      Radius.circular(borderRadius),
    );
    final cutout = Path()
      ..fillType = PathFillType.evenOdd
      ..addPath(full, Offset.zero)
      ..addRRect(hole);

    canvas.drawPath(
      cutout,
      Paint()..color = Colors.black.withValues(alpha: 0.62 * opacity),
    );

    // Soft outer Tempo Orange halo (static -> zero per-frame tessellation overhead)
    final haloRRect = RRect.fromRectAndRadius(
      holeRect.inflate(3.5),
      Radius.circular(borderRadius + 3.5),
    );
    canvas.drawRRect(
      haloRRect,
      Paint()
        ..color = accentColor.withValues(alpha: 0.24 * opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5,
    );

    // Crisp inner accent ring
    canvas.drawRRect(
      hole,
      Paint()
        ..color = accentColor.withValues(alpha: 0.90 * opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8,
    );
  }

  @override
  bool shouldRepaint(covariant _SpotlightScrimPainter oldDelegate) =>
      oldDelegate.holeRect != holeRect ||
      oldDelegate.borderRadius != borderRadius ||
      oldDelegate.opacity != opacity ||
      oldDelegate.accentColor != accentColor;
}
