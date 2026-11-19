import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';
import '../widgets/liquid_glass_surface.dart';
import '../widgets/oval_activity_rings.dart';

class _IntroSlideData {
  final String title;
  final String body;

  const _IntroSlideData({
    required this.title,
    required this.body,
  });
}

/// First-time user animated walkthrough introducing Tempo's core features.
/// Minimal iOS 27 aesthetic: no emojis, no dot/step indicators, smooth Next/Back transitions.
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
      title: 'Your daily rhythm',
      body:
          'Track calories, steps, and active minutes in one glance. Tap the plus button on Summary anytime to log sleep, weight, or measurements.',
    ),
    _IntroSlideData(
      title: 'Train with focus',
      body:
          'Start any guided workout from the top row, count in with the session timer, and check off sets as you go. Active sessions stay live in your status bar.',
    ),
    _IntroSlideData(
      title: 'See your momentum',
      body:
          'Follow your weekly streak, scrub across 7, 14, or 30 day trends, review personal lift records, and keep progress photos privately on your device.',
    ),
    _IntroSlideData(
      title: 'Built for privacy',
      body:
          'All data stays offline on your phone. Glide across the bottom glass bar to switch tabs, or double-tap Profile anytime to switch accounts with a PIN.',
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
    if (_currentPage < _slides.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
      );
    } else {
      _finishWithAnimation();
    }
  }

  void _goBack() {
    if (_isFinishing || _currentPage <= 0) return;
    HapticFeedback.selectionClick();
    _pageController.previousPage(
      duration: const Duration(milliseconds: 380),
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
      body: SafeArea(
        child: AnimatedBuilder(
          animation: _outroController,
          builder: (context, child) {
            final t = _outroController.value;
            // Phase 1 (0.0 -> 0.28): walkthrough content glides up and dissolves out
            final contentExitT = Curves.easeInCubic.transform(
              (t / 0.28).clamp(0.0, 1.0),
            );
            final contentOpacity = (1.0 - contentExitT).clamp(0.0, 1.0);
            final contentOffsetY = -22.0 * contentExitT;
            final contentScale = 1.0 - 0.04 * contentExitT;

            // Phase 2 (0.18 -> 0.78): minimal Tempo ring draws 0->360° & wordmark glides in
            // Phase 3 (0.78 -> 1.0): gentle zoom-out dissolve into the Main page
            final ringDrawT = Curves.easeOutCubic.transform(
              ((t - 0.16) / 0.44).clamp(0.0, 1.0),
            );
            final ringFadeIn = Curves.easeOutCubic.transform(
              ((t - 0.14) / 0.18).clamp(0.0, 1.0),
            );
            final outroFadeOut = Curves.easeInCubic.transform(
              ((t - 0.78) / 0.22).clamp(0.0, 1.0),
            );
            final welcomeOpacity =
                (ringFadeIn * (1.0 - outroFadeOut)).clamp(0.0, 1.0);
            final textSlideT = Curves.easeOutCubic.transform(
              ((t - 0.26) / 0.34).clamp(0.0, 1.0),
            );
            final rippleT = Curves.easeOutCubic.transform(
              ((t - 0.46) / 0.48).clamp(0.0, 1.0),
            );
            final finalZoom = 1.0 + 0.14 * outroFadeOut;

            return Stack(
              fit: StackFit.expand,
              children: [
                IgnorePointer(
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

                // Smooth Launch Flourish bridging Intro -> Main Page
                if (_isFinishing && welcomeOpacity > 0.005)
                  IgnorePointer(
                    child: Center(
                      child: Opacity(
                        opacity: welcomeOpacity,
                        child: Transform.scale(
                          scale: finalZoom,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 120,
                                height: 120,
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    if (rippleT > 0)
                                      Transform.scale(
                                        scale: 0.72 + 0.62 * rippleT,
                                        child: Opacity(
                                          opacity:
                                              (1.0 - rippleT).clamp(0.0, 0.45),
                                          child: Container(
                                            width: 96,
                                            height: 96,
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              border: Border.all(
                                                color: c.accent,
                                                width: 2,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    CustomPaint(
                                      size: const Size(76, 76),
                                      painter: _IntroRingPainter(
                                        progress: ringDrawT,
                                        trackColor: c.divider,
                                        activeColor: c.accent,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 14),
                              Transform.translate(
                                offset: Offset(0, 14 * (1.0 - textSlideT)),
                                child: Opacity(
                                  opacity: textSlideT,
                                  child: Column(
                                    children: [
                                      Text(
                                        'Welcome to Tempo',
                                        style: TextStyle(
                                          color: c.textPrimary,
                                          fontSize: 24,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: -0.6,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Let’s begin',
                                        style: TextStyle(
                                          color: c.textSecondary,
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
            // Clean minimal top bar (Tempo wordmark + subtle Skip)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 14, 16, 4),
              child: Row(
                children: [
                  Text(
                    'Tempo',
                    style: TextStyle(
                      color: c.textTertiary,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const Spacer(),
                  AnimatedOpacity(
                    opacity: isLast ? 0.0 : 1.0,
                    duration: const Duration(milliseconds: 220),
                    child: IgnorePointer(
                      ignoring: isLast,
                      child: TextButton(
                        onPressed: _skip,
                        child: Text(
                          widget.isReplay ? 'Close' : 'Skip',
                          style: TextStyle(
                            color: c.textSecondary,
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                          ),
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
                    padding: const EdgeInsets.symmetric(horizontal: 28),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Visual stage with subtle parallax & depth scale
                        Opacity(
                          opacity: (0.25 + 0.75 * visibility).clamp(0.0, 1.0),
                          child: Transform.translate(
                            offset: Offset(delta * 26, 0),
                            child: Transform.scale(
                              scale: 0.90 + 0.10 * visibility,
                              child: SizedBox(
                                height: 248,
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
                        const SizedBox(height: 36),
                        // Headline + description with gentle staggered horizontal offset
                        Opacity(
                          opacity: visibility,
                          child: Transform.translate(
                            offset: Offset(delta * 42, 0),
                            child: Column(
                              children: [
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
                                const SizedBox(height: 12),
                                Text(
                                  slide.body,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: c.textSecondary,
                                    fontSize: 15,
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

            // Bottom Back / Next controls (no pagination dots or indicators)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: Row(
                children: [
                  AnimatedSize(
                    duration: const Duration(milliseconds: 260),
                    curve: Curves.easeOutCubic,
                    child: isFirst
                        ? const SizedBox.shrink()
                        : Padding(
                            padding: const EdgeInsets.only(right: 12),
                            child: _WalkthroughButton(
                              label: 'Back',
                              isPrimary: false,
                              width: 108,
                              onTap: _goBack,
                            ),
                          ),
                  ),
                  Expanded(
                    child: _WalkthroughButton(
                      label: isLast
                          ? (widget.isReplay ? 'Done' : 'Get Started')
                          : 'Next',
                      isPrimary: true,
                      onTap: _goNext,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
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

class _WalkthroughButton extends StatefulWidget {
  final String label;
  final bool isPrimary;
  final double? width;
  final VoidCallback onTap;

  const _WalkthroughButton({
    required this.label,
    required this.isPrimary,
    this.width,
    required this.onTap,
  });

  @override
  State<_WalkthroughButton> createState() => _WalkthroughButtonState();
}

class _WalkthroughButtonState extends State<_WalkthroughButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final bg = widget.isPrimary ? c.accent : c.searchBg;
    final fg = widget.isPrimary ? Colors.white : c.textPrimary;

    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.96 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOutCubic,
        child: Container(
          width: widget.width,
          height: 52,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(16),
          ),
          alignment: Alignment.center,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: Text(
              widget.label,
              key: ValueKey(widget.label),
              style: TextStyle(
                color: fg,
                fontSize: 15.5,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.1,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Slide 1 visual: Live animated Tempo Oval Activity Rings.
class _SummaryRingsPreview extends StatelessWidget {
  final bool isActive;

  const _SummaryRingsPreview({required this.isActive});

  @override
  Widget build(BuildContext context) {
    return OvalActivityRings(
      caloriesProgress: isActive ? 0.78 : 0.15,
      stepsProgress: isActive ? 0.86 : 0.20,
      minutesProgress: isActive ? 0.64 : 0.10,
      size: 224,
    );
  }
}

/// Slide 2 visual: Minimal animated Workout timer sweep & exercise progress.
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
    return AppleCard(
      borderRadius: 28,
      padding: const EdgeInsets.all(22),
      child: SizedBox(
        width: 248,
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (_, __) {
            final t = _ctrl.value;
            final secs = 12 + (t * 24).floor();
            final checkedCount = (t * 4).floor().clamp(1, 3);
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 96,
                  height: 96,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CustomPaint(
                        size: const Size(96, 96),
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
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.5,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                ...List.generate(3, (i) {
                  final done = i < checkedCount;
                  return Padding(
                    padding: EdgeInsets.only(bottom: i == 2 ? 0 : 10),
                    child: Row(
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 240),
                          width: 18,
                          height: 18,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: done ? c.textPrimary : Colors.transparent,
                            border: Border.all(
                              color: done
                                  ? c.textPrimary
                                  : c.textTertiary.withValues(alpha: 0.5),
                              width: 1.5,
                            ),
                          ),
                          child: done
                              ? Icon(
                                  CupertinoIcons.checkmark_alt,
                                  size: 11,
                                  color: c.isDark ? Colors.black : Colors.white,
                                )
                              : null,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Container(
                            height: 8,
                            decoration: BoxDecoration(
                              color: done
                                  ? c.textPrimary.withValues(alpha: 0.16)
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

/// Slide 3 visual: Animated 7-bar activity trend card.
class _ProgressBarsPreview extends StatefulWidget {
  final bool isActive;

  const _ProgressBarsPreview({required this.isActive});

  @override
  State<_ProgressBarsPreview> createState() => _ProgressBarsPreviewState();
}

class _ProgressBarsPreviewState extends State<_ProgressBarsPreview>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  static const _heights = [0.38, 0.62, 0.48, 0.85, 0.72, 0.94, 0.66];

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
    return AppleCard(
      borderRadius: 28,
      padding: const EdgeInsets.all(22),
      child: SizedBox(
        width: 256,
        height: 176,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Weekly Activity',
              style: TextStyle(
                color: c.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
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
                        height: (92 * _heights[i] * barT).clamp(6.0, 96.0),
                        decoration: BoxDecoration(
                          color: isPeak
                              ? c.accent
                              : c.textPrimary.withValues(
                                  alpha: c.isDark ? 0.22 : 0.14,
                                ),
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(6),
                            bottom: Radius.circular(2),
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

/// Slide 4 visual: Miniature floating Liquid Glass navigation pill gliding smoothly.
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
        // Glide across 4 slots smoothly then pause gently on Profile (slot 3)
        final rawPos = t < 0.65
            ? Curves.easeInOutCubic.transform(t / 0.65) * 3.0
            : 3.0;
        final pulseT = t >= 0.65 ? ((t - 0.65) / 0.35).clamp(0.0, 1.0) : 0.0;

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Centered profile emblem with gentle double-tap ripple
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
                  Container(
                    width: 68,
                    height: 68,
                    decoration: BoxDecoration(
                      color: c.card,
                      shape: BoxShape.circle,
                      border: Border.all(color: c.cardBorder, width: 1.5),
                    ),
                    child: Icon(
                      CupertinoIcons.person_fill,
                      color: c.textPrimary,
                      size: 30,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            // Miniature floating glass bar
            Container(
              width: 260,
              height: 58,
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: c.card,
                borderRadius: BorderRadius.circular(29),
                border: Border.all(color: c.cardBorder),
              ),
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
                        child: Container(
                          decoration: BoxDecoration(
                            color: c.accent.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(
                              color: c.accent.withValues(alpha: 0.35),
                            ),
                          ),
                        ),
                      ),
                      Row(
                        children: [
                          _miniTab(CupertinoIcons.circle, rawPos.round() == 0, c),
                          _miniTab(Icons.directions_run_rounded, rawPos.round() == 1, c),
                          _miniTab(CupertinoIcons.chart_bar_square, rawPos.round() == 2, c),
                          _miniTab(CupertinoIcons.person_crop_circle, rawPos.round() == 3, c),
                        ],
                      ),
                    ],
                  );
                },
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
    const stroke = 6.0;
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
