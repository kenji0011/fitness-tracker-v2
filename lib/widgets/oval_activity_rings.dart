import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';

/// Tilted concentric oval (45° stadium) activity rings with crisp vertical
/// pinstripe tracks, animated rounded progress arcs, and cap icons.
///
/// Uses pure geometric `PathFillType.evenOdd` ring-band clipping (no `saveLayer`
/// / `BlendMode.dstIn`), guaranteeing razor-sharp tilted concentric ovals on
/// Vulkan, Metal, OpenGL ES, Skia, and Web.
class OvalActivityRings extends StatefulWidget {
  final double caloriesProgress; // 0.0 .. 1.0+
  final double stepsProgress; // 0.0 .. 1.0+
  final double minutesProgress; // 0.0 .. 1.0+
  final double size;
  final int? highlightedRing; // 0 = calories, 1 = steps, 2 = minutes
  final ValueChanged<int>? onRingTap;

  const OvalActivityRings({
    super.key,
    required this.caloriesProgress,
    required this.stepsProgress,
    required this.minutesProgress,
    this.size = 252,
    this.highlightedRing,
    this.onRingTap,
  });

  @override
  State<OvalActivityRings> createState() => _OvalActivityRingsState();
}

class _OvalActivityRingsState extends State<OvalActivityRings>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late Animation<double> _calAnim;
  late Animation<double> _stepAnim;
  late Animation<double> _minAnim;

  double _prevCal = 0;
  double _prevStep = 0;
  double _prevMin = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
    );
    _setupAnimations();
    _controller.forward();
  }

  void _setupAnimations() {
    final curve = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
    _calAnim = Tween<double>(
      begin: _prevCal,
      end: widget.caloriesProgress.clamp(0.0, 1.0),
    ).animate(curve);
    _stepAnim = Tween<double>(
      begin: _prevStep,
      end: widget.stepsProgress.clamp(0.0, 1.0),
    ).animate(curve);
    _minAnim = Tween<double>(
      begin: _prevMin,
      end: widget.minutesProgress.clamp(0.0, 1.0),
    ).animate(curve);
  }

  @override
  void didUpdateWidget(covariant OvalActivityRings oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.caloriesProgress != widget.caloriesProgress ||
        oldWidget.stepsProgress != widget.stepsProgress ||
        oldWidget.minutesProgress != widget.minutesProgress) {
      _prevCal = _calAnim.value;
      _prevStep = _stepAnim.value;
      _prevMin = _minAnim.value;
      _setupAnimations();
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleTapDown(TapDownDetails details) {
    if (widget.onRingTap == null) return;
    final center = Offset(widget.size / 2, widget.size / 2);
    final dist = (details.localPosition - center).distance;
    final maxR = widget.size * 0.48;
    int ring;
    if (dist > maxR * 0.72) {
      ring = 0;
    } else if (dist > maxR * 0.48) {
      ring = 1;
    } else {
      ring = 2;
    }
    HapticFeedback.selectionClick();
    widget.onRingTap!(ring);
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return GestureDetector(
      onTapDown: _handleTapDown,
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            return CustomPaint(
              size: Size(widget.size, widget.size),
              painter: _OvalRingsPainter(
                calProgress: _calAnim.value,
                stepProgress: _stepAnim.value,
                minProgress: _minAnim.value,
                isDark: c.isDark,
                highlightedRing: widget.highlightedRing,
              ),
            );
          },
        ),
      ),
    );
  }
}

class _OvalRingsPainter extends CustomPainter {
  final double calProgress;
  final double stepProgress;
  final double minProgress;
  final bool isDark;
  final int? highlightedRing;

  static const Color calColor = Color(0xFFF36432); // Flame Orange
  static const Color stepColor = Color(0xFFA6EB3C); // Lime Green
  static const Color minColor = Color(0xFF56B7FF); // Sky Blue

  const _OvalRingsPainter({
    required this.calProgress,
    required this.stepProgress,
    required this.minProgress,
    required this.isDark,
    this.highlightedRing,
  });

  /// Builds a clockwise stadium path centered at (0, 0).
  /// Starts on the upper-left end of the straight top edge and sweeps clockwise
  /// around the right semicircle, bottom edge, and left semicircle.
  Path _buildStadiumPath(double straightLen, double radius) {
    final halfS = straightLen / 2;
    final r = radius.clamp(1.0, 500.0);
    final p = Path()
      ..moveTo(-halfS, -r)
      ..lineTo(halfS, -r)
      ..arcTo(
        Rect.fromCircle(center: Offset(halfS, 0), radius: r),
        -math.pi / 2,
        math.pi,
        false,
      )
      ..lineTo(-halfS, r)
      ..arcTo(
        Rect.fromCircle(center: Offset(-halfS, 0), radius: r),
        math.pi / 2,
        math.pi,
        false,
      )
      ..close();
    return p;
  }

  /// Transforms a local stadium by tilting -45° (bottom-left to top-right) at `center`.
  Path _tiltedStadium(Offset center, double straightLen, double radius) {
    final raw = _buildStadiumPath(straightLen, radius);
    final m = Matrix4.identity()
      ..translateByDouble(center.dx, center.dy, 0, 1)
      ..rotateZ(-math.pi / 4);
    return raw.transform(m.storage);
  }

  /// Builds an exact hollow annular tilted-oval band using `PathFillType.evenOdd`
  /// (outer stadium minus inner stadium — zero blend-mode artifacts on Impeller!).
  Path _tiltedRingBand(
    Offset center,
    double straightLen,
    double centerRadius,
    double strokeWidth,
  ) {
    final outerR = centerRadius + strokeWidth / 2;
    final innerR = (centerRadius - strokeWidth / 2).clamp(2.0, outerR - 1.0);
    final band = Path()
      ..fillType = PathFillType.evenOdd
      ..addPath(_tiltedStadium(center, straightLen, outerR), Offset.zero)
      ..addPath(_tiltedStadium(center, straightLen, innerR), Offset.zero);
    return band;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final unit = size.width / 252.0;

    // Refined Mi Fitness tilted stadium proportions:
    // Clear oval hollow center, crisp gap between rings, balanced 45° elongation
    final stroke = 20.0 * unit;
    final gap = 5.5 * unit;
    final straightLen = 44.0 * unit;

    final rOuter = 82.0 * unit;
    final rMid = rOuter - stroke - gap; // 56.5
    final rInner = rMid - stroke - gap; // 31.0 (leaves an ~21px inner oval hole!)

    final rings = [
      (
        radius: rOuter,
        progress: calProgress,
        color: calColor,
        icon: CupertinoIcons.flame_fill,
        index: 0,
      ),
      (
        radius: rMid,
        progress: stepProgress,
        color: stepColor,
        icon: Icons.directions_walk_rounded,
        index: 1,
      ),
      (
        radius: rInner,
        progress: minProgress,
        color: minColor,
        icon: CupertinoIcons.clock_fill,
        index: 2,
      ),
    ];

    for (final ring in rings) {
      final isHighlighted =
          highlightedRing == null || highlightedRing == ring.index;
      final dimFactor = isHighlighted ? 1.0 : 0.42;

      final centerline = _tiltedStadium(center, straightLen, ring.radius);
      final bandClip = _tiltedRingBand(center, straightLen, ring.radius, stroke);

      // 1. Subtle tinted base track behind pinstripes so the oval contour is super clean
      final trackBasePaint = Paint()
        ..color = ring.color.withValues(
          alpha: (isDark ? 0.08 : 0.08) * dimFactor,
        )
        ..style = PaintingStyle.fill;
      canvas.drawPath(bandClip, trackBasePaint);

      // 2. Crisp Vertical Pinstripes cleanly clipped to the exact tilted oval band!
      canvas.save();
      canvas.clipPath(bandClip);
      final stripePaint = Paint()
        ..color = ring.color.withValues(
          alpha: (isDark ? 0.36 : 0.28) * dimFactor,
        )
        ..strokeWidth = 1.65 * unit
        ..style = PaintingStyle.stroke;

      final spacing = 5.0 * unit;
      for (double x = 0; x <= size.width; x += spacing) {
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), stripePaint);
      }
      canvas.restore();

      // 3. Vibrant Filled Progress Arc following the exact tilted oval perimeter
      final metrics = centerline.computeMetrics().toList();
      if (metrics.isEmpty) continue;
      final metric = metrics.first;
      final totalLen = metric.length;

      final startTangent = metric.getTangentForOffset(0);
      final startPos = startTangent?.position ?? center;

      final clampedProg = ring.progress.clamp(0.0, 1.0);
      final activeColor = ring.color.withValues(alpha: dimFactor);

      if (clampedProg > 0.005) {
        final drawLen = (totalLen * clampedProg).clamp(1.0, totalLen);
        final activePath = metric.extractPath(0, drawLen);

        final glowPaint = Paint()
          ..color = activeColor.withValues(alpha: isDark ? 0.24 : 0.16)
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke + 3.5 * unit
          ..strokeCap = StrokeCap.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.5);
        canvas.drawPath(activePath, glowPaint);

        final activePaint = Paint()
          ..color = activeColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;
        canvas.drawPath(activePath, activePaint);
      } else {
        // Zero progress: neat circular starting cap dot for the icon
        canvas.drawCircle(
          startPos,
          stroke * 0.5,
          Paint()
            ..color = activeColor
            ..style = PaintingStyle.fill,
        );
      }

      // 4. Starting cap icon seated right at the arc origin
      _drawCapIcon(
        canvas: canvas,
        center: startPos,
        icon: ring.icon,
        iconSize: stroke * 0.56,
        color: isDark ? const Color(0xFF121214) : Colors.white,
      );
    }
  }

  void _drawCapIcon({
    required Canvas canvas,
    required Offset center,
    required IconData icon,
    required double iconSize,
    required Color color,
  }) {
    final tp = TextPainter(
      textDirection: TextDirection.ltr,
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontSize: iconSize,
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
          color: color,
        ),
      ),
    )..layout();

    tp.paint(
      canvas,
      Offset(center.dx - tp.width / 2, center.dy - tp.height / 2),
    );
  }

  @override
  bool shouldRepaint(covariant _OvalRingsPainter oldDelegate) =>
      oldDelegate.calProgress != calProgress ||
      oldDelegate.stepProgress != stepProgress ||
      oldDelegate.minProgress != minProgress ||
      oldDelegate.isDark != isDark ||
      oldDelegate.highlightedRing != highlightedRing;
}
