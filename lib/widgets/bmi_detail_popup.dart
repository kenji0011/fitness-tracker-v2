import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../models/local_profile.dart';
import '../theme/app_colors.dart';
import 'ios_stretch_sheet.dart';

/// Displays the animated BMI breakdown & interactive BMI trend graph popup
/// using Tempo's iOS spring & rubber-band stretch sheet.
Future<void> showBmiDetailPopup({
  required BuildContext context,
  required double bmi,
  required double heightCm,
  required List<BodyMetricPoint> weightPoints,
}) {
  HapticFeedback.selectionClick();
  final c = AppColors.of(context, listen: false);
  return showTempoSheet<void>(
    context: context,
    backgroundColor: c.isDark ? const Color(0xFF141416) : c.card,
    borderRadius: 28,
    showDragHandle: true,
    builder: (_) => _BmiDetailPopupBody(
      bmi: bmi,
      heightCm: heightCm,
      weightPoints: weightPoints,
    ),
  );
}

class _BmiDetailPopupBody extends StatefulWidget {
  final double bmi;
  final double heightCm;
  final List<BodyMetricPoint> weightPoints;

  const _BmiDetailPopupBody({
    required this.bmi,
    required this.heightCm,
    required this.weightPoints,
  });

  @override
  State<_BmiDetailPopupBody> createState() => _BmiDetailPopupBodyState();
}

class _BmiDetailPopupBodyState extends State<_BmiDetailPopupBody> {
  static const Color _lowBlue = Color(0xFF67B7F7);
  static const Color _normalGreen = Color(0xFF5AD16C);
  static const Color _highYellow = Color(0xFFF7C648);
  static const Color _veryHighOrange = Color(0xFFF49342);

  // Band width proportions matching the 18.5 / 24 / 28 visual scale.
  static const int _flexLow = 25;
  static const int _flexNormal = 28;
  static const int _flexHigh = 22;
  static const int _flexVeryHigh = 25;
  static const double _split1 = 0.25; // 18.5
  static const double _split2 = 0.53; // 24
  static const double _split3 = 0.75; // 28

  static const List<String> _ranges = ['7D', '30D', 'All'];
  int _selectedRange = 2; // Default to 'All' so full BMI trend is visible

  String get _levelLabel {
    final bmi = widget.bmi;
    if (bmi <= 0) return '--';
    if (bmi < 18.5) return 'Low';
    if (bmi < 24.0) return 'Normal';
    if (bmi < 28.0) return 'High';
    return 'Very high';
  }

  Color get _levelColor {
    final bmi = widget.bmi;
    if (bmi <= 0) return _normalGreen;
    if (bmi < 18.5) return _lowBlue;
    if (bmi < 24.0) return _normalGreen;
    if (bmi < 28.0) return _highYellow;
    return _veryHighOrange;
  }

  String get _adviceText {
    final bmi = widget.bmi;
    if (bmi <= 0) {
      return 'Add your height in Profile and log a weight entry to calculate your BMI and track its trend.';
    }
    if (bmi < 18.5) {
      return 'Your BMI is below the normal range. Focus on balanced, nutrient-rich meals and consistent strength training.';
    }
    if (bmi < 24.0) {
      return "With a normal BMI, it's recommended to maintain healthy eating and exercise habits.";
    }
    if (bmi < 28.0) {
      return 'Your BMI is slightly above the normal range. Regular cardio and mindful nutrition can help bring it closer to normal.';
    }
    return 'Your BMI is above the recommended range. Consistent daily movement and balanced nutrition will steadily improve your trend.';
  }

  /// Maps BMI value onto `[0.03, 0.97]` aligned cleanly to the 18.5 / 24 / 28 dividers.
  double get _normalizedMarkerPosition {
    final bmi = widget.bmi;
    if (bmi <= 0) return _split1 + (_split2 - _split1) * 0.5;
    if (bmi < 18.5) {
      final t = ((bmi - 13.5) / 5.0).clamp(0.0, 1.0);
      return 0.03 + t * (_split1 - 0.03);
    }
    if (bmi < 24.0) {
      final t = ((bmi - 18.5) / 5.5).clamp(0.0, 1.0);
      return _split1 + t * (_split2 - _split1);
    }
    if (bmi < 28.0) {
      final t = ((bmi - 24.0) / 4.0).clamp(0.0, 1.0);
      return _split2 + t * (_split3 - _split2);
    }
    final t = ((bmi - 28.0) / 8.0).clamp(0.0, 1.0);
    return _split3 + t * (0.97 - _split3);
  }

  List<_BmiPoint> get _filteredBmiPoints {
    if (widget.heightCm <= 0) return const [];
    final hM = widget.heightCm / 100.0;
    final hSq = hM * hM;

    final sorted = [...widget.weightPoints]
      ..sort((a, b) => a.recordedAt.compareTo(b.recordedAt));

    List<BodyMetricPoint> filtered = sorted;
    if (_selectedRange != 2 && sorted.isNotEmpty) {
      final days = _selectedRange == 0 ? 7 : 30;
      final latest = sorted.last.recordedAt.toLocal();
      final cutoff = DateTime(latest.year, latest.month, latest.day)
          .subtract(Duration(days: days - 1));
      filtered = sorted
          .where((p) => !p.recordedAt.toLocal().isBefore(cutoff))
          .toList();
    }

    return filtered
        .where((p) => p.value > 0)
        .map(
          (p) => _BmiPoint(
            date: p.recordedAt.toLocal(),
            bmi: p.value / hSq,
          ),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final bmiPts = _filteredBmiPoints;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final maxH = MediaQuery.sizeOf(context).height * 0.84;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxH),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Flexible(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(22, 6, 22, 14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Top split metric row: BMI | Level
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            TweenAnimationBuilder<double>(
                              tween: Tween<double>(
                                begin: widget.bmi > 0 ? (widget.bmi * 0.85) : 0,
                                end: widget.bmi,
                              ),
                              duration: const Duration(milliseconds: 420),
                              curve: Curves.easeOutCubic,
                              builder: (_, val, __) => Text(
                                widget.bmi > 0 ? val.toStringAsFixed(1) : '--',
                                style: TextStyle(
                                  color: c.textPrimary,
                                  fontSize: 28,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -0.6,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'BMI',
                              style: TextStyle(
                                color: c.textTertiary,
                                fontSize: 13.5,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        width: 1,
                        height: 42,
                        margin: const EdgeInsets.symmetric(horizontal: 18),
                        color: c.divider,
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _levelLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: c.textPrimary,
                                fontSize: 26,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.5,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Level',
                              style: TextStyle(
                                color: c.textTertiary,
                                fontSize: 13.5,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 14),
                  Divider(height: 1, color: c.divider),
                  const SizedBox(height: 14),

                  // Animated 4-zone BMI spectrum bar with hollow downward pointer
                  LayoutBuilder(
                    builder: (_, constraints) {
                      final w = constraints.maxWidth;
                      return Column(
                        children: [
                          SizedBox(
                            height: 34,
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                // Animated hollow triangle pointer
                                TweenAnimationBuilder<double>(
                                  tween: Tween<double>(
                                    begin: 0.08,
                                    end: _normalizedMarkerPosition,
                                  ),
                                  duration: const Duration(milliseconds: 520),
                                  curve: Curves.easeOutCubic,
                                  builder: (_, pos, __) {
                                    final markerX =
                                        (w * pos).clamp(10.0, w - 10.0);
                                    return Positioned(
                                      left: markerX - 7,
                                      top: 0,
                                      child: CustomPaint(
                                        size: const Size(14, 10),
                                        painter: _HollowTrianglePainter(
                                          color: c.textPrimary,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                                // 4-zone pill bar
                                Positioned(
                                  left: 0,
                                  right: 0,
                                  bottom: 2,
                                  height: 15,
                                  child: Row(
                                    children: const [
                                      Expanded(
                                        flex: _flexLow,
                                        child: _SpectrumSegment(
                                          color: _lowBlue,
                                          roundLeft: true,
                                        ),
                                      ),
                                      SizedBox(width: 2.5),
                                      Expanded(
                                        flex: _flexNormal,
                                        child: _SpectrumSegment(
                                          color: _normalGreen,
                                        ),
                                      ),
                                      SizedBox(width: 2.5),
                                      Expanded(
                                        flex: _flexHigh,
                                        child: _SpectrumSegment(
                                          color: _highYellow,
                                        ),
                                      ),
                                      SizedBox(width: 2.5),
                                      Expanded(
                                        flex: _flexVeryHigh,
                                        child: _SpectrumSegment(
                                          color: _veryHighOrange,
                                          roundRight: true,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 5),
                          // Threshold labels aligned under each band boundary (18.5 | 24 | 28)
                          SizedBox(
                            height: 18,
                            child: Stack(
                              children: [
                                Positioned(
                                  left: (w * _split1 - 16).clamp(0.0, w - 36),
                                  child: Text(
                                    '18.5',
                                    style: TextStyle(
                                      color: c.textTertiary,
                                      fontSize: 12.5,
                                      fontFeatures: const [
                                        FontFeature.tabularFigures(),
                                      ],
                                    ),
                                  ),
                                ),
                                Positioned(
                                  left: (w * _split2 - 9).clamp(0.0, w - 24),
                                  child: Text(
                                    '24',
                                    style: TextStyle(
                                      color: c.textTertiary,
                                      fontSize: 12.5,
                                      fontFeatures: const [
                                        FontFeature.tabularFigures(),
                                      ],
                                    ),
                                  ),
                                ),
                                Positioned(
                                  left: (w * _split3 - 9).clamp(0.0, w - 24),
                                  child: Text(
                                    '28',
                                    style: TextStyle(
                                      color: c.textTertiary,
                                      fontSize: 12.5,
                                      fontFeatures: const [
                                        FontFeature.tabularFigures(),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  ),

                  const SizedBox(height: 10),

                  // Legend rows matching the screenshot
                  const Row(
                    children: [
                      Expanded(
                        child: _LegendItem(color: _lowBlue, label: 'Low'),
                      ),
                      Expanded(
                        child: _LegendItem(
                          color: _normalGreen,
                          label: 'Normal',
                        ),
                      ),
                      Expanded(
                        child: _LegendItem(color: _highYellow, label: 'High'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 7),
                  const Row(
                    children: [
                      Expanded(
                        child: _LegendItem(
                          color: _veryHighOrange,
                          label: 'Very high',
                        ),
                      ),
                      Expanded(child: SizedBox.shrink()),
                      Expanded(child: SizedBox.shrink()),
                    ],
                  ),

                  const SizedBox(height: 14),

                  // Contextual recommendation copy
                  Text(
                    _adviceText,
                    style: TextStyle(
                      color: c.textSecondary,
                      fontSize: 13.5,
                      height: 1.42,
                    ),
                  ),

                  const SizedBox(height: 14),

                  // Functional interactive BMI trend graph
                  Container(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
                    decoration: BoxDecoration(
                      color: c.isDark
                          ? Colors.white.withValues(alpha: 0.045)
                          : c.searchBg.withValues(alpha: 0.65),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: c.isDark
                            ? Colors.white.withValues(alpha: 0.06)
                            : Colors.black.withValues(alpha: 0.04),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Text(
                              'BMI trend',
                              style: TextStyle(
                                color: c.textPrimary,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.all(2.5),
                              decoration: BoxDecoration(
                                color: c.isDark
                                    ? Colors.white.withValues(alpha: 0.07)
                                    : Colors.black.withValues(alpha: 0.05),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: List.generate(_ranges.length, (i) {
                                  final active = i == _selectedRange;
                                  return GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: () {
                                      HapticFeedback.selectionClick();
                                      setState(() => _selectedRange = i);
                                    },
                                    child: AnimatedContainer(
                                      duration:
                                          const Duration(milliseconds: 180),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 9,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: active
                                            ? (c.isDark
                                                ? const Color(0xFF34353B)
                                                : c.card)
                                            : Colors.transparent,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        _ranges[i],
                                        style: TextStyle(
                                          color: active
                                              ? c.textPrimary
                                              : c.textSecondary,
                                          fontSize: 11.5,
                                          fontWeight: active
                                              ? FontWeight.w600
                                              : FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  );
                                }),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        _BmiTrendGraph(
                          points: bmiPts,
                          accentColor: _levelColor,
                          normalBandColor: _normalGreen,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Pinned full-width Collapse button matching the screenshot
          Padding(
            padding: EdgeInsets.fromLTRB(22, 4, 22, bottomInset + 16),
            child: SizedBox(
              height: 50,
              child: TextButton(
                style: TextButton.styleFrom(
                  backgroundColor:
                      c.isDark ? const Color(0xFF26272B) : c.searchBg,
                  foregroundColor: c.textPrimary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
                onPressed: () {
                  HapticFeedback.lightImpact();
                  Navigator.of(context).pop();
                },
                child: Text(
                  'Collapse',
                  style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BmiPoint {
  final DateTime date;
  final double bmi;

  const _BmiPoint({required this.date, required this.bmi});
}

class _BmiTrendGraph extends StatelessWidget {
  final List<_BmiPoint> points;
  final Color accentColor;
  final Color normalBandColor;

  const _BmiTrendGraph({
    required this.points,
    required this.accentColor,
    required this.normalBandColor,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    if (points.isEmpty) {
      return SizedBox(
        height: 112,
        child: Center(
          child: Text(
            'No BMI records in this timeframe yet',
            textAlign: TextAlign.center,
            style: TextStyle(color: c.textTertiary, fontSize: 12.5),
          ),
        ),
      );
    }

    final vals = points.map((p) => p.bmi).toList();
    final minRaw = vals.reduce((a, b) => a < b ? a : b);
    final maxRaw = vals.reduce((a, b) => a > b ? a : b);
    final minY = (minRaw < 18.0 ? minRaw - 1.5 : 17.0).clamp(12.0, 45.0);
    final maxY = (maxRaw > 25.0 ? maxRaw + 1.5 : 26.0).clamp(minY + 4.0, 50.0);

    final spots = points.length == 1
        ? [FlSpot(0, points.first.bmi), FlSpot(1, points.first.bmi)]
        : List.generate(
            points.length,
            (i) => FlSpot(i.toDouble(), points[i].bmi),
          );

    return Column(
      children: [
        SizedBox(
          height: 112,
          child: LineChart(
            LineChartData(
              minY: minY,
              maxY: maxY,
              rangeAnnotations: RangeAnnotations(
                horizontalRangeAnnotations: [
                  HorizontalRangeAnnotation(
                    y1: 18.5,
                    y2: 24.0,
                    color: normalBandColor.withValues(
                      alpha: c.isDark ? 0.11 : 0.10,
                    ),
                  ),
                ],
              ),
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: 4.0,
                getDrawingHorizontalLine: (_) => FlLine(
                  color: c.divider.withValues(alpha: 0.7),
                  strokeWidth: 0.8,
                ),
              ),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                bottomTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 32,
                    interval: ((maxY - minY) / 2).clamp(2.0, 10.0),
                    getTitlesWidget: (v, _) => Text(
                      v.toStringAsFixed(0),
                      style: TextStyle(
                        color: c.textTertiary,
                        fontSize: 10.5,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ),
              ),
              lineTouchData: LineTouchData(
                touchTooltipData: LineTouchTooltipData(
                  getTooltipColor: (_) =>
                      c.isDark ? const Color(0xFF2C2C2E) : c.textPrimary,
                  getTooltipItems: (touchedSpots) => touchedSpots.map((s) {
                    final idx = s.x.round().clamp(0, points.length - 1);
                    final pt = points[idx];
                    return LineTooltipItem(
                      'BMI ${pt.bmi.toStringAsFixed(1)}\n${DateFormat('MM/dd').format(pt.date)}',
                      const TextStyle(
                        color: Colors.white,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    );
                  }).toList(),
                ),
              ),
              lineBarsData: [
                LineChartBarData(
                  isCurved: points.length > 2,
                  color: accentColor,
                  barWidth: 2.5,
                  dotData: FlDotData(
                    show: points.length <= 16,
                    getDotPainter: (spot, _, __, index) => FlDotCirclePainter(
                      radius: points.length == 1 && index == 1 ? 0 : 3.2,
                      color: accentColor,
                      strokeWidth: 1.5,
                      strokeColor: c.isDark ? const Color(0xFF141416) : c.card,
                    ),
                  ),
                  belowBarData: BarAreaData(
                    show: true,
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        accentColor.withValues(alpha: 0.22),
                        accentColor.withValues(alpha: 0.0),
                      ],
                    ),
                  ),
                  spots: spots,
                ),
              ],
            ),
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              DateFormat('MM/dd').format(points.first.date),
              style: TextStyle(color: c.textTertiary, fontSize: 11),
            ),
            Text(
              points.length == 1
                  ? 'Normal band 18.5–24.0'
                  : 'Min ${minRaw.toStringAsFixed(1)} · Max ${maxRaw.toStringAsFixed(1)}',
              style: TextStyle(
                color: c.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w500,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            Text(
              DateFormat('MM/dd').format(points.last.date),
              style: TextStyle(color: c.textTertiary, fontSize: 11),
            ),
          ],
        ),
      ],
    );
  }
}

class _SpectrumSegment extends StatelessWidget {
  final Color color;
  final bool roundLeft;
  final bool roundRight;

  const _SpectrumSegment({
    required this.color,
    this.roundLeft = false,
    this.roundRight = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.horizontal(
          left: Radius.circular(roundLeft ? 8 : 1.5),
          right: Radius.circular(roundRight ? 8 : 1.5),
        ),
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendItem({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 7),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: c.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

class _HollowTrianglePainter extends CustomPainter {
  final Color color;

  const _HollowTrianglePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeJoin = StrokeJoin.round;

    final path = Path()
      ..moveTo(1.5, 1.5)
      ..lineTo(size.width - 1.5, 1.5)
      ..lineTo(size.width / 2, size.height - 1.5)
      ..close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _HollowTrianglePainter oldDelegate) =>
      oldDelegate.color != color;
}
