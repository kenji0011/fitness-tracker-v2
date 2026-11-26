import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Tempo's signature Midnight Obsidian splash backdrop, matching
/// `@color/ic_launcher_background` and `@color/tempo_splash_bg` on Android
/// for a zero-flash handoff from the native OS splash screen.
const Color kTempoSplashBackground = Color(0xFF0B101A);

/// Optical outer diameter of the centered Tempo Dual-Ring logo on Frame 0,
/// matching `android/app/src/main/res/drawable/ic_tempo_splash.xml`.
const double kTempoSplashLogoSize = 116.0;

/// Pure vector renderer of Tempo's iconic Dual-Ring logo:
/// - Outer luminous electric-blue to sky-cyan gradient ring with top sheen
/// - Inner vibrant Tempo Orange open progress arc (~308°) with rounded endcaps
///   and a warm dark-amber track gap at 12:00–1:36.
///
/// Rendered purely with vector GPU primitives so it stays mathematically
/// razor-sharp from 1x up to full-screen magnification with <0.5ms first-frame
/// paint time.
class TempoDualRingLogo extends StatelessWidget {
  final double size;
  final double innerArcRotation;
  final double glowIntensity;

  const TempoDualRingLogo({
    super.key,
    this.size = kTempoSplashLogoSize,
    this.innerArcRotation = 0.0,
    this.glowIntensity = 0.0,
  });

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        size: Size.square(size),
        painter: _TempoDualRingLogoPainter(
          innerArcRotation: innerArcRotation,
          glowIntensity: glowIntensity,
        ),
      ),
    );
  }
}

class _TempoDualRingLogoPainter extends CustomPainter {
  final double innerArcRotation;
  final double glowIntensity;

  const _TempoDualRingLogoPainter({
    this.innerArcRotation = 0.0,
    this.glowIntensity = 0.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final diameter = math.min(size.width, size.height);
    _paintTempoDualRing(
      canvas: canvas,
      center: center,
      diameter: diameter,
      opacity: 1.0,
      innerArcRotation: innerArcRotation,
      glowIntensity: glowIntensity,
    );
  }

  @override
  bool shouldRepaint(covariant _TempoDualRingLogoPainter oldDelegate) {
    return oldDelegate.innerArcRotation != innerArcRotation ||
        oldDelegate.glowIntensity != glowIntensity;
  }
}

/// Shared vector painting routine used by both [TempoDualRingLogo] and the
/// full-screen zoom-through [_TempoPortalSplashPainter].
///
/// When [maxVisibleRadius] is provided, any ring whose inner edge has already
/// expanded past the viewport corners is culled immediately so the GPU never
/// tessellates massive off-screen strokes during the final frames of zoom.
void _paintTempoDualRing({
  required Canvas canvas,
  required Offset center,
  required double diameter,
  required double opacity,
  double innerArcRotation = 0.0,
  double glowIntensity = 0.0,
  double? maxVisibleRadius,
}) {
  if (opacity <= 0.001 || diameter <= 0.0) return;

  final outerRadius = diameter * (50.1 / 116.0);
  final outerStroke = diameter * (15.8 / 116.0);
  final innerRadius = diameter * (30.6 / 116.0);
  final innerStroke = diameter * (10.0 / 116.0);

  final cullLimit = maxVisibleRadius != null ? maxVisibleRadius + 8.0 : null;
  final drawOuterRing =
      cullLimit == null || (outerRadius - outerStroke * 0.5) <= cullLimit;
  final drawInnerRing =
      cullLimit == null || (innerRadius - innerStroke * 0.5) <= cullLimit;

  // Subtle radial anticipation bloom behind the rings (kept lightweight without
  // MaskFilter/saveLayer so 120Hz stays completely stutter-free).
  if (glowIntensity > 0.01 && drawInnerRing) {
    final glowRadius = diameter * 0.78;
    final glowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFF28D7FF).withValues(alpha: 0.14 * glowIntensity * opacity),
          const Color(0xFFFF6A24).withValues(alpha: 0.09 * glowIntensity * opacity),
          Colors.transparent,
        ],
        stops: const [0.0, 0.45, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: glowRadius));
    canvas.drawCircle(center, glowRadius, glowPaint);
  }

  // 1. Outer luminous Blue -> Azure -> Cyan ring
  if (drawOuterRing) {
    final outerRect = Rect.fromCircle(center: center, radius: outerRadius);
    final outerPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = outerStroke
      ..isAntiAlias = true
      ..shader = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          const Color(0xFF1677FF).withValues(alpha: opacity),
          const Color(0xFF2EA7FF).withValues(alpha: opacity),
          const Color(0xFF28D7FF).withValues(alpha: opacity),
        ],
        stops: const [0.0, 0.50, 1.0],
      ).createShader(outerRect);
    canvas.drawCircle(center, outerRadius, outerPaint);

    // Subtle top specular highlight rim along the outer ring for optical depth
    final highlightRadius = outerRadius + outerStroke * 0.14;
    if (cullLimit == null || (highlightRadius - outerStroke * 0.25) <= cullLimit) {
      final highlightPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = outerStroke * 0.42
        ..strokeCap = StrokeCap.round
        ..isAntiAlias = true
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withValues(alpha: 0.24 * opacity),
            Colors.white.withValues(alpha: 0.0),
          ],
        ).createShader(outerRect);
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: highlightRadius),
        -math.pi * 0.82,
        math.pi * 0.64,
        false,
        highlightPaint,
      );
    }
  }

  // 2 & 3. Inner warm dark-amber track + vibrant Tempo Orange open progress arc
  if (drawInnerRing) {
    final innerTrackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = innerStroke
      ..isAntiAlias = true
      ..color = const Color(0xFF452319).withValues(alpha: opacity);
    canvas.drawCircle(center, innerRadius, innerTrackPaint);

    const double startAngle = -42.0 * math.pi / 180.0;
    const double sweepAngle = 308.0 * math.pi / 180.0;
    final innerRect = Rect.fromCircle(center: center, radius: innerRadius);
    final innerArcPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = innerStroke
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          const Color(0xFFFF5630).withValues(alpha: opacity),
          const Color(0xFFFF6A24).withValues(alpha: opacity),
          const Color(0xFFFF7A33).withValues(alpha: opacity),
        ],
      ).createShader(innerRect);
    canvas.drawArc(
      innerRect,
      startAngle + innerArcRotation,
      sweepAngle,
      false,
      innerArcPaint,
    );
  }
}

/// X (formerly Twitter)-inspired 120Hz Startup Splash Screen for Tempo:
/// 1. Beat 0 (`0–100ms`): Seamless Frame-0 lock on Midnight Obsidian (`#0B101A`)
///    with centered 116dp Tempo Dual-Ring matching Android's native splash.
/// 2. Beat 1 (`100–270ms`): Signature coiled anticipation dip (`1.0x → 0.82x`).
/// 3. Beat 2 (`270–840ms`): Optical logarithmic zoom (`0.82x → screen clear`)
///    where the hollow center of the Tempo Dual-Ring expands as a single-pass
///    `evenOdd` lens portal revealing the live app gliding smoothly underneath.
/// 4. Beat 3 (`840ms`): Removes only the overlay slot from the persistent
///    `Stack` so [child] is NEVER reparented, unmounted, or re-initialized.
class TempoStartupSplash extends StatefulWidget {
  final Widget child;
  final bool enabled;
  final Duration duration;
  final VoidCallback? onCompleted;

  const TempoStartupSplash({
    super.key,
    required this.child,
    this.enabled = true,
    this.duration = const Duration(milliseconds: 840),
    this.onCompleted,
  });

  static Completer<void>? _activeCompleter;

  /// Resolves immediately if no startup splash is active, or waits until the
  /// active startup splash finishes (used by `TempoSpotlightTour` so first-time
  /// coach marks never appear behind the splash).
  static Future<void> waitForCompletion() {
    final completer = _activeCompleter;
    if (completer == null || completer.isCompleted) {
      return Future<void>.value();
    }
    return completer.future;
  }

  /// Key used in widget tests to locate the active splash overlay.
  static const Key overlayKey = ValueKey<String>('tempo_startup_splash_overlay');

  @override
  State<TempoStartupSplash> createState() => _TempoStartupSplashState();
}

class _TempoStartupSplashState extends State<TempoStartupSplash>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _contentScaleAnimation;
  Completer<void>? _ownCompleter;
  bool _completed = false;
  bool _started = false;
  bool _reducedMotion = false;

  static const Duration _reducedMotionDuration = Duration(milliseconds: 220);

  @override
  void initState() {
    super.initState();
    _completed = !widget.enabled;
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
      value: widget.enabled ? 0.0 : 1.0,
    );
    _contentScaleAnimation = Tween<double>(begin: 0.955, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.40, 0.92, curve: Curves.easeOutQuart),
      ),
    );
    _controller.addStatusListener(_handleStatusChanged);

    if (widget.enabled) {
      final completer = Completer<void>();
      _ownCompleter = completer;
      TempoStartupSplash._activeCompleter = completer;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started && !_completed) {
      _started = true;
      _reducedMotion = MediaQuery.disableAnimationsOf(context);
      _controller.duration =
          _reducedMotion ? _reducedMotionDuration : widget.duration;
      _controller.forward();
    }
  }

  void _handleStatusChanged(AnimationStatus status) {
    if (status == AnimationStatus.completed && !_completed) {
      _finishSplash();
    }
  }

  void _finishSplash() {
    _completeGate();
    if (!mounted) {
      _completed = true;
      return;
    }
    setState(() {
      _completed = true;
    });
    widget.onCompleted?.call();
  }

  void _completeGate() {
    final completer = _ownCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
    if (identical(TempoStartupSplash._activeCompleter, completer)) {
      TempoStartupSplash._activeCompleter = null;
    }
  }

  @override
  void dispose() {
    _completeGate();
    _controller.removeStatusListener(_handleStatusChanged);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // IMPORTANT: Keep `widget.child` in the exact same widget slot (`Stack` ->
    // `ScaleTransition`) before, during, AND after splash completion. Removing
    // or conditionally swapping wrappers around `widget.child` would unmount
    // and re-initialize the entire app tree (`TempoShellScreen` / SQLite /
    // shaders) on the final frame and cause a visible end-of-animation stutter!
    return Stack(
      fit: StackFit.expand,
      children: [
        ScaleTransition(
          scale: _reducedMotion
              ? const AlwaysStoppedAnimation<double>(1.0)
              : _contentScaleAnimation,
          alignment: Alignment.center,
          child: widget.child,
        ),
        if (!_completed)
          Positioned.fill(
            key: TempoStartupSplash.overlayKey,
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                final t = _controller.value;
                final overlay = RepaintBoundary(
                  child: CustomPaint(
                    painter: _TempoPortalSplashPainter(
                      progress: t,
                      reducedMotion: _reducedMotion,
                    ),
                  ),
                );
                // Hand back adaptive status-bar styling once the live screen
                // dominates the viewport (t >= 0.68) so there is no abrupt
                // platform-chrome repaint hitch on the final frame.
                final content = t < 0.68
                    ? AnnotatedRegion<SystemUiOverlayStyle>(
                        value: SystemUiOverlayStyle.light.copyWith(
                          statusBarColor: Colors.transparent,
                          systemNavigationBarColor: Colors.transparent,
                          statusBarIconBrightness: Brightness.light,
                          statusBarBrightness: Brightness.dark,
                        ),
                        child: overlay,
                      )
                    : overlay;
                return AbsorbPointer(
                  absorbing: t < 0.82,
                  child: content,
                );
              },
            ),
          ),
      ],
    );
  }
}

/// Single-pass 120Hz vector painter executing the signature Tempo X-style
/// Dual-Ring Portal Zoom-Through animation with optical logarithmic scaling,
/// per-ring off-screen culling, and zero `saveLayer` overhead.
class _TempoPortalSplashPainter extends CustomPainter {
  final double progress;
  final bool reducedMotion;

  const _TempoPortalSplashPainter({
    required this.progress,
    required this.reducedMotion,
  });

  // Normalized timeline boundaries for the 840ms choreography:
  // Beat 0 (0.00 -> 0.12): Steady Frame-0 sync hold (~100ms)
  // Beat 1 (0.12 -> 0.32): Coiled anticipation dip 1.0x -> 0.82x (~168ms)
  // Beat 2 (0.32 -> 1.00): Optical logarithmic zoom-through (~572ms)
  static const double _holdEnd = 0.12;
  static const double _dipEnd = 0.32;
  static const double _dipScale = 0.82;

  // Punchy X/Twitter release that cushions smoothly past the viewport corners
  // (eliminates high-velocity stepping/judder in the final 100ms).
  static const Curve _zoomCurve = Cubic(0.68, 0.0, 0.24, 1.0);

  // Hollow interior radius of the inner Tempo Orange ring at 1.0x (116dp)
  static const double _baseInnerHoleRadius =
      kTempoSplashLogoSize * (25.5 / 116.0);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final viewport = Offset.zero & size;

    if (reducedMotion) {
      final fade = 1.0 - Curves.easeOut.transform(progress.clamp(0.0, 1.0));
      if (fade <= 0.001) return;
      canvas.drawRect(
        viewport,
        Paint()..color = kTempoSplashBackground.withValues(alpha: fade),
      );
      _paintTempoDualRing(
        canvas: canvas,
        center: center,
        diameter: kTempoSplashLogoSize,
        opacity: fade,
      );
      return;
    }

    final t = progress.clamp(0.0, 1.0);
    final maxHalfDiagonal = math.sqrt(
      center.dx * center.dx + center.dy * center.dy,
    );

    // Fit targetScale cleanly just past the viewport corners (+8% margin) so
    // the ring clears all 4 corners smoothly without wasting GPU cycles on
    // massive off-screen geometry.
    final targetScale = math.max(
      18.0,
      (maxHalfDiagonal * 1.08) / _baseInnerHoleRadius,
    );

    double scale = 1.0;
    double innerArcRotation = 0.0;
    double glowIntensity = 0.0;
    double portalRadius = 0.0;
    double backdropAlpha = 1.0;
    double ringAlpha = 1.0;

    if (t <= _holdEnd) {
      // Beat 0: Rock-steady native handoff hold
      scale = 1.0;
    } else if (t <= _dipEnd) {
      // Beat 1: Signature X/Twitter coiled anticipation compression
      final dipT = Curves.easeInOutCubic.transform(
        (t - _holdEnd) / (_dipEnd - _holdEnd),
      );
      scale = lerpDouble(1.0, _dipScale, dipT)!;
      innerArcRotation = -0.10 * dipT;
      glowIntensity = dipT;
    } else {
      // Beat 2: Optical logarithmic zoom (constant perceived camera velocity
      // through the ring with a silky cushioned exit past the corners).
      final u = ((t - _dipEnd) / (1.0 - _dipEnd)).clamp(0.0, 1.0);
      final eased = _zoomCurve.transform(u);
      scale = _dipScale * math.pow(targetScale / _dipScale, eased).toDouble();

      // Uncoil the subtle orange arc rotation back to neutral as it launches
      final uncoil = Curves.easeOutCubic.transform((u / 0.35).clamp(0.0, 1.0));
      innerArcRotation = lerpDouble(-0.10, 0.0, uncoil)!;

      // Anticipation glow peaks right at release and fades smoothly away
      glowIntensity = 1.0 - (u / 0.40).clamp(0.0, 1.0);

      // Bloom the circular lens portal inside the hollow Tempo ring as it
      // launches past ~1.0x, then lock it 1:1 to the inner edge (+0.6px tucked
      // cleanly beneath the orange stroke for zero anti-aliasing seam).
      if (u > 0.14) {
        final portalBloom = Curves.easeInOutCubic.transform(
          ((u - 0.14) / 0.20).clamp(0.0, 1.0),
        );
        final liveHoleRadius = _baseInnerHoleRadius * scale;
        portalRadius = (liveHoleRadius + 0.6) * portalBloom;
      }

      // Gently feather remaining edge alpha as the ring clears the corners
      if (u > 0.72) {
        final tail = Curves.easeOut.transform(((u - 0.72) / 0.26).clamp(0.0, 1.0));
        backdropAlpha = 1.0 - tail;
        ringAlpha = 1.0 - tail;
      }
    }

    // 1. Paint Midnight Obsidian backdrop with evenOdd circular portal cutout
    if (backdropAlpha > 0.001 && portalRadius < maxHalfDiagonal + 4.0) {
      final bgPaint = Paint()
        ..color = kTempoSplashBackground.withValues(alpha: backdropAlpha)
        ..isAntiAlias = true;
      if (portalRadius <= 0.5) {
        canvas.drawRect(viewport, bgPaint);
      } else {
        final portalPath = Path()
          ..fillType = PathFillType.evenOdd
          ..addRect(viewport)
          ..addOval(Rect.fromCircle(center: center, radius: portalRadius));
        canvas.drawPath(portalPath, bgPaint);
      }
    }

    // 2. Paint scaled Tempo Dual-Ring around the portal rim (culling each ring
    //    the instant its inner edge expands past the viewport corners).
    if (ringAlpha > 0.001) {
      _paintTempoDualRing(
        canvas: canvas,
        center: center,
        diameter: kTempoSplashLogoSize * scale,
        opacity: ringAlpha,
        innerArcRotation: innerArcRotation,
        glowIntensity: glowIntensity,
        maxVisibleRadius: maxHalfDiagonal,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _TempoPortalSplashPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.reducedMotion != reducedMotion;
  }
}
