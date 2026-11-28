import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/animation_speed_service.dart';
import '../services/appearance_service.dart';
import '../theme/app_colors.dart';
import '../widgets/liquid_glass_surface.dart';
import '../widgets/oval_activity_rings.dart';
import '../widgets/tempo_startup_splash.dart';

class _IntroSlideData {
  final String badge;
  final String title;
  final String body;

  const _IntroSlideData({
    required this.badge,
    required this.title,
    required this.body,
  });
}

/// Updated Tempo App Guide & first-time animated walkthrough unified with
/// Tempo's Liquid Glass design language and matching the Midnight Obsidian
/// Dual-Ring Startup Splash on "Welcome to Tempo".
class IntroWalkthroughScreen extends StatefulWidget {
  final VoidCallback onComplete;
  final bool isReplay;

  const IntroWalkthroughScreen({
    super.key,
    required this.onComplete,
    this.isReplay = false,
  });

  @override
  State<IntroWalkthroughScreen> createState() => _IntroWalkthroughScreenState();
}

class _IntroWalkthroughScreenState extends State<IntroWalkthroughScreen>
    with SingleTickerProviderStateMixin {
  final PageController _pageController = PageController();
  late final AnimationController _outroController;
  int _currentPage = 0;
  double _pageOffset = 0.0;
  bool _isFinishing = false;

  static const List<_IntroSlideData> _slides = [
    _IntroSlideData(
      badge: 'SUMMARY',
      title: 'Your daily rhythm',
      body:
          'Track calories, steps, active minutes, hydration, and sleep in one glance. Tap + anytime to log with the 3D wheel and celebrate every daily goal you hit.',
    ),
    _IntroSlideData(
      badge: 'WORKOUTS',
      title: 'Train with focus',
      body:
          'Start any muscle program or Fitness Journey, watch Liquid Glass form videos, log sets with pill steppers, and verify each exercise as you train.',
    ),
    _IntroSlideData(
      badge: 'PROGRESS',
      title: 'See your momentum',
      body:
          'Follow your streak, 12-week heatmap, and 7, 14, or 30 day energy trends alongside personal lift PRs, verified sessions, and private on-device photos.',
    ),
    _IntroSlideData(
      badge: 'PRIVACY & GLASS',
      title: 'Built for privacy',
      body:
          'Everything stays offline on your device in local storage. Glide across the Liquid Glass dock to switch tabs, or double-tap Profile to switch accounts with a PIN.',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _outroController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1220),
    );
    _pageController.addListener(() {
      if (_pageController.hasClients) {
        setState(() {
          _pageOffset = _pageController.page ?? _currentPage.toDouble();
        });
      }
    });
  }

  @override
  void dispose() {
    _outroController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _finishWithAnimation() async {
    if (_isFinishing) return;
    setState(() => _isFinishing = true);
    HapticFeedback.mediumImpact();
    await _outroController.forward(from: 0);
    if (mounted) {
      widget.onComplete();
    }
  }

  void _goNext() {
    if (_isFinishing) return;
    HapticFeedback.selectionClick();
    final reduced = TempoAppearanceService.instance.reduceAnimation;
    final dur = reduced
        ? const Duration(milliseconds: 1)
        : TempoAnimationSpeedService.instance.scale(
            const Duration(milliseconds: 420),
          );
    if (_currentPage < _slides.length - 1) {
      _pageController.nextPage(
        duration: dur,
        curve: Curves.easeOutCubic,
      );
    } else {
      _finishWithAnimation();
    }
  }

  void _goBack() {
    if (_isFinishing || _currentPage <= 0) return;
    HapticFeedback.selectionClick();
    final reduced = TempoAppearanceService.instance.reduceAnimation;
    final dur = reduced
        ? const Duration(milliseconds: 1)
        : TempoAnimationSpeedService.instance.scale(
            const Duration(milliseconds: 380),
          );
    _pageController.previousPage(
      duration: dur,
      curve: Curves.easeOutCubic,
    );
  }

  void _skip() {
    if (_isFinishing) return;
    HapticFeedback.selectionClick();
    _finishWithAnimation();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final isFirst = _currentPage == 0;
    final isLast = _currentPage == _slides.length - 1;

    return Scaffold(
      backgroundColor: c.scaffold,
      body: AnimatedBuilder(
        animation: _outroController,
        builder: (context, child) {
          final t = _outroController.value;
          // Phase 1 (0.0 -> 0.24): walkthrough glides up & fades into Midnight Obsidian splash
          final contentExitT = Curves.easeInCubic.transform(
            (t / 0.24).clamp(0.0, 1.0),
          );
          final contentOpacity = (1.0 - contentExitT).clamp(0.0, 1.0);
          final contentOffsetY = -20.0 * contentExitT;
          final contentScale = 1.0 - 0.04 * contentExitT;

          // Phase 2 (0.14 -> 0.74): exact Startup Splash Midnight Obsidian + Dual-Ring Logo
          // with X-style anticipation dip -> radiant glow -> zoom-through reveal
          final splashIn = Curves.easeOutCubic.transform(
            ((t - 0.10) / 0.18).clamp(0.0, 1.0),
          );
          final zoomOut = Curves.easeInExpo.transform(
            ((t - 0.74) / 0.26).clamp(0.0, 1.0),
          );
          final bgOpacity =
              (splashIn * (1.0 - zoomOut * 0.92)).clamp(0.0, 1.0);

          final dipPhase = ((t - 0.50) / 0.22).clamp(0.0, 1.0);
          final dipScale = 1.0 - 0.11 * math.sin(dipPhase * math.pi);
          final logoScale =
              (0.84 + 0.16 * splashIn) * dipScale * (1.0 + 3.6 * zoomOut);
          final logoGlow =
              (splashIn * (0.45 + 0.55 * math.sin(dipPhase * math.pi)))
                  .clamp(0.0, 1.0);
          final arcRotation =
              Curves.easeOutCubic.transform(((t - 0.14) / 0.56).clamp(0.0, 1.0)) *
                  (math.pi * 0.35);

          final textIn = Curves.easeOutCubic.transform(
            ((t - 0.22) / 0.28).clamp(0.0, 1.0),
          );
          final textOpacity =
              (textIn * (1.0 - Curves.easeInCubic.transform(zoomOut)))
                  .clamp(0.0, 1.0);

          return Stack(
            fit: StackFit.expand,
            children: [
              SafeArea(
                child: IgnorePointer(
                  ignoring: _isFinishing,
                  child: Opacity(
                    opacity: contentOpacity,
                    child: Transform.translate(
                      offset: Offset(0, contentOffsetY),
                      child: Transform.scale(
                        scale: contentScale,
                        child: child,
                      ),
                    ),
                  ),
                ),
              ),

              // Startup-Splash-Matched "Welcome to Tempo" Dual-Ring Launch
              if (_isFinishing && bgOpacity > 0.004)
                Positioned.fill(
                  child: IgnorePointer(
                    child: ColoredBox(
                      color: kTempoSplashBackground.withValues(alpha: bgOpacity),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Opacity(
                              opacity:
                                  (splashIn * (1.0 - zoomOut)).clamp(0.0, 1.0),
                              child: Transform.scale(
                                scale: logoScale,
                                child: TempoDualRingLogo(
                                  size: kTempoSplashLogoSize,
                                  innerArcRotation: arcRotation,
                                  glowIntensity: logoGlow,
                                ),
                              ),
                            ),
                            const SizedBox(height: 22),
                            Transform.translate(
                              offset: Offset(0, 14 * (1.0 - textIn)),
                              child: Opacity(
                                opacity: textOpacity,
                                child: const Column(
                                  children: [
                                    Text(
                                      'Welcome to Tempo',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 25,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: -0.6,
                                      ),
                                    ),
                                    SizedBox(height: 5),
                                    Text(
                                      'Let’s begin',
                                      style: TextStyle(
                                        color: Color(0xFF9EA6B8),
                                        fontSize: 14.5,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Top bar with Tempo Dual-Ring emblem + Liquid Glass Skip/Close pill
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 12, 18, 4),
              child: Row(
                children: [
                  const TempoDualRingLogo(size: 24, glowIntensity: 0.35),
                  const SizedBox(width: 9),
                  Text(
                    'Tempo',
                    style: TextStyle(
                      color: c.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const Spacer(),
                  AnimatedOpacity(
                    opacity: isLast ? 0.0 : 1.0,
                    duration: const Duration(milliseconds: 220),
                    child: IgnorePointer(
                      ignoring: isLast,
                      child: TempoLiquidButton(
                        primary: false,
                        height: 36,
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        onPressed: _skip,
                        child: Text(
                          widget.isReplay ? 'Close' : 'Skip',
                          style: const TextStyle(fontSize: 13.5),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Animated horizontal slides
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                physics: const BouncingScrollPhysics(),
                itemCount: _slides.length,
                onPageChanged: (index) {
                  if (index != _currentPage) {
                    HapticFeedback.selectionClick();
                    setState(() => _currentPage = index);
                  }
                },
                itemBuilder: (context, index) {
                  final delta = (index - _pageOffset).clamp(-1.0, 1.0);
                  final visibility = (1.0 - delta.abs()).clamp(0.0, 1.0);
                  final slide = _slides[index];

                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Visual stage with subtle parallax & depth scale
                        Opacity(
                          opacity: (0.28 + 0.72 * visibility).clamp(0.0, 1.0),
                          child: Transform.translate(
                            offset: Offset(delta * 26, 0),
                            child: Transform.scale(
                              scale: 0.90 + 0.10 * visibility,
                              child: SizedBox(
                                height: 256,
                                child: Center(
                                  child: _buildSlideVisual(
                                    index,
                                    isActive: index == _currentPage,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 30),
                        // Pill badge + Headline + Description
                        Opacity(
                          opacity: visibility,
                          child: Transform.translate(
                            offset: Offset(delta * 40, 0),
                            child: Column(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 11,
                                    vertical: 4.5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: c.accent.withValues(
                                      alpha: c.isDark ? 0.20 : 0.12,
                                    ),
                                    borderRadius: BorderRadius.circular(99),
                                  ),
                                  child: Text(
                                    slide.badge,
                                    style: TextStyle(
                                      color: c.accent,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.7,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  slide.title,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: c.textPrimary,
                                    fontSize: 28,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: -0.7,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  slide.body,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: c.textSecondary,
                                    fontSize: 14.8,
                                    height: 1.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),

            // Bottom Liquid Glass Back + Bouncy Next / Get Started controls
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 8, 22, 22),
              child: Row(
                children: [
                  AnimatedSize(
                    duration: const Duration(milliseconds: 260),
                    curve: Curves.easeOutCubic,
                    child: isFirst
                        ? const SizedBox.shrink()
                        : Padding(
                            padding: const EdgeInsets.only(right: 12),
                            child: SizedBox(
                              width: 108,
                              child: TempoLiquidButton(
                                primary: false,
                                height: 52,
                                onPressed: _goBack,
                                child: const Text(
                                  'Back',
                                  style: TextStyle(fontSize: 15.5),
                                ),
                              ),
                            ),
                          ),
                  ),
                  Expanded(
                    child: TempoBouncyButton(
                      height: 52,
                      onPressed: _goNext,
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        child: Text(
                          isLast
                              ? (widget.isReplay ? 'Done' : 'Get Started')
                              : 'Next',
                          key: ValueKey(
                            isLast
                                ? (widget.isReplay ? 'Done' : 'Get Started')
                                : 'Next',
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSlideVisual(int index, {required bool isActive}) {
    switch (index) {
      case 0:
        return _SummaryRingsPreview(isActive: isActive);
      case 1:
        return _WorkoutTimerPreview(isActive: isActive);
      case 2:
        return _ProgressBarsPreview(isActive: isActive);
      default:
        return _PrivacyGlassNavPreview(isActive: isActive);
    }
  }
}

/// Slide 1 visual: Live animated Tempo Oval Activity Rings inside Liquid Glass stage.
class _SummaryRingsPreview extends StatelessWidget {
  final bool isActive;

  const _SummaryRingsPreview({required this.isActive});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return LiquidGlassSurface(
      borderRadius: 32,
      blurEnabled: false,
      padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          OvalActivityRings(
            caloriesProgress: isActive ? 1.0 : 0.15,
            stepsProgress: isActive ? 0.86 : 0.20,
            minutesProgress: isActive ? 0.72 : 0.10,
            size: 186,
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: c.accent.withValues(alpha: c.isDark ? 0.22 : 0.13),
              borderRadius: BorderRadius.circular(99),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(CupertinoIcons.checkmark_alt, size: 12, color: c.accent),
                const SizedBox(width: 4),
                Text(
                  'Calories goal hit',
                  style: TextStyle(
                    color: c.accent,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Slide 2 visual: Liquid Glass Workout Command Deck with verified progress.
class _WorkoutTimerPreview extends StatefulWidget {
  final bool isActive;

  const _WorkoutTimerPreview({required this.isActive});

  @override
  State<_WorkoutTimerPreview> createState() => _WorkoutTimerPreviewState();
}

class _WorkoutTimerPreviewState extends State<_WorkoutTimerPreview>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return LiquidGlassSurface(
      borderRadius: 28,
      blurEnabled: false,
      padding: const EdgeInsets.all(20),
      child: SizedBox(
        width: 256,
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (_, __) {
            final t = _ctrl.value;
            final secs = 15 + (t * 30).floor();
            final checkedCount = (t * 4).floor().clamp(1, 3);
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    SizedBox(
                      width: 68,
                      height: 68,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          CustomPaint(
                            size: const Size(68, 68),
                            painter: _IntroRingPainter(
                              progress: 0.25 + 0.75 * t,
                              trackColor: c.divider,
                              activeColor: c.accent,
                            ),
                          ),
                          Text(
                            '00:${secs.toString().padLeft(2, '0')}',
                            style: TextStyle(
                              color: c.textPrimary,
                              fontSize: 14.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.3,
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: c.accent
                                  .withValues(alpha: c.isDark ? 0.22 : 0.13),
                              borderRadius: BorderRadius.circular(99),
                            ),
                            child: Text(
                              'IN PROGRESS',
                              style: TextStyle(
                                color: c.accent,
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.4,
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '$checkedCount of 3 verified',
                            style: TextStyle(
                              color: c.textPrimary,
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700,
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                ...List.generate(3, (i) {
                  final done = i < checkedCount;
                  return Padding(
                    padding: EdgeInsets.only(bottom: i == 2 ? 0 : 9),
                    child: Row(
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 240),
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: done ? c.accent : Colors.transparent,
                            border: Border.all(
                              color: done
                                  ? c.accent
                                  : c.textTertiary.withValues(alpha: 0.5),
                              width: 1.4,
                            ),
                          ),
                          child: done
                              ? const Icon(
                                  CupertinoIcons.checkmark_alt,
                                  size: 12,
                                  color: Colors.white,
                                )
                              : null,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Container(
                            height: 8,
                            decoration: BoxDecoration(
                              color: done
                                  ? c.accent.withValues(
                                      alpha: c.isDark ? 0.30 : 0.22,
                                    )
                                  : c.divider,
                              borderRadius: BorderRadius.circular(99),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Slide 3 visual: Liquid Glass Energy Trend + Top PR preview card.
class _ProgressBarsPreview extends StatefulWidget {
  final bool isActive;

  const _ProgressBarsPreview({required this.isActive});

  @override
  State<_ProgressBarsPreview> createState() => _ProgressBarsPreviewState();
}

class _ProgressBarsPreviewState extends State<_ProgressBarsPreview>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  static const _heights = [0.38, 0.62, 0.48, 0.85, 0.72, 0.96, 0.68];

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 950),
    )..forward();
  }

  @override
  void didUpdateWidget(covariant _ProgressBarsPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      _ctrl.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return LiquidGlassSurface(
      borderRadius: 28,
      blurEnabled: false,
      padding: const EdgeInsets.all(20),
      child: SizedBox(
        width: 262,
        height: 186,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Energy Burned',
                  style: TextStyle(
                    color: c.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: c.accent.withValues(alpha: c.isDark ? 0.22 : 0.13),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    'TOP PR',
                    style: TextStyle(
                      color: c.accent,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: AnimatedBuilder(
                animation: _ctrl,
                builder: (_, __) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: List.generate(_heights.length, (i) {
                      final start = (i * 0.08).clamp(0.0, 0.55);
                      final end = (start + 0.45).clamp(0.0, 1.0);
                      final barT = Curves.easeOutCubic.transform(
                        ((_ctrl.value - start) / (end - start)).clamp(0.0, 1.0),
                      );
                      final isPeak = i == 5;
                      return Container(
                        width: 22,
                        height: (98 * _heights[i] * barT).clamp(6.0, 102.0),
                        decoration: BoxDecoration(
                          color: isPeak
                              ? c.accent
                              : c.textPrimary.withValues(
                                  alpha: c.isDark ? 0.22 : 0.14,
                                ),
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(7),
                            bottom: Radius.circular(3),
                          ),
                        ),
                      );
                    }),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Slide 4 visual: Miniature Liquid Glass dock pill & offline PIN profile badge.
class _PrivacyGlassNavPreview extends StatefulWidget {
  final bool isActive;

  const _PrivacyGlassNavPreview({required this.isActive});

  @override
  State<_PrivacyGlassNavPreview> createState() =>
      _PrivacyGlassNavPreviewState();
}

class _PrivacyGlassNavPreviewState extends State<_PrivacyGlassNavPreview>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3600),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        final t = _ctrl.value;
        final rawPos = t < 0.65
            ? Curves.easeInOutCubic.transform(t / 0.65) * 3.0
            : 3.0;
        final pulseT = t >= 0.65 ? ((t - 0.65) / 0.35).clamp(0.0, 1.0) : 0.0;

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 112,
              height: 112,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  if (pulseT > 0)
                    Transform.scale(
                      scale: 0.72 + 0.48 * pulseT,
                      child: Opacity(
                        opacity: (1.0 - pulseT).clamp(0.0, 0.55),
                        child: Container(
                          width: 88,
                          height: 88,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: c.accent, width: 2),
                          ),
                        ),
                      ),
                    ),
                  LiquidGlassSurface(
                    borderRadius: 999,
                    blurEnabled: false,
                    padding: EdgeInsets.zero,
                    child: SizedBox(
                      width: 68,
                      height: 68,
                      child: Icon(
                        CupertinoIcons.lock_fill,
                        color: c.accent,
                        size: 26,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            LiquidGlassSurface(
              borderRadius: 999,
              blurEnabled: false,
              padding: const EdgeInsets.all(6),
              child: SizedBox(
                width: 256,
                height: 46,
                child: LayoutBuilder(
                  builder: (_, constraints) {
                    final slotW = constraints.maxWidth / 4;
                    return Stack(
                      children: [
                        Positioned(
                          left: rawPos * slotW,
                          top: 0,
                          bottom: 0,
                          width: slotW,
                          child: CustomPaint(
                            foregroundPainter: LiquidGlassRimPainter(
                              borderRadius: 999,
                              isDark: c.isDark,
                              intensity: 0.95,
                              strokeWidth: 1.0,
                              showTopMeniscus: false,
                              tintColor: c.accent,
                            ),
                            child: Container(
                              decoration: BoxDecoration(
                                color: c.accent.withValues(
                                  alpha: c.isDark ? 0.24 : 0.14,
                                ),
                                borderRadius: BorderRadius.circular(999),
                              ),
                            ),
                          ),
                        ),
                        Row(
                          children: [
                            _miniTab(
                              CupertinoIcons.heart_fill,
                              rawPos.round() == 0,
                              c,
                            ),
                            _miniTab(
                              Icons.fitness_center_rounded,
                              rawPos.round() == 1,
                              c,
                            ),
                            _miniTab(
                              CupertinoIcons.rosette,
                              rawPos.round() == 2,
                              c,
                            ),
                            _miniTab(
                              CupertinoIcons.person_fill,
                              rawPos.round() == 3,
                              c,
                            ),
                          ],
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _miniTab(IconData icon, bool active, AppColors c) {
    return Expanded(
      child: Center(
        child: Icon(
          icon,
          size: 20,
          color: active ? c.accent : c.textTertiary,
        ),
      ),
    );
  }
}

class _IntroRingPainter extends CustomPainter {
  final double progress;
  final Color trackColor;
  final Color activeColor;

  const _IntroRingPainter({
    required this.progress,
    required this.trackColor,
    required this.activeColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    const stroke = 5.5;
    final radius = (size.width - stroke) / 2;

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = trackColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke,
    );
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * progress.clamp(0.0, 1.0),
      false,
      Paint()
        ..color = activeColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _IntroRingPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.trackColor != trackColor ||
      oldDelegate.activeColor != activeColor;
}
