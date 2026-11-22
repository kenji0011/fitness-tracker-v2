import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/local_profile.dart';
import '../theme/app_colors.dart';
import 'ios_stretch_sheet.dart';

/// Displays the animated BMI breakdown popup using Tempo's iOS spring
/// & upward rubber-band stretch sheet.
Future<void> showBmiDetailPopup({
  required BuildContext context,
  required double bmi,
  required double heightCm,
  List<BodyMetricPoint> weightPoints = const [],
}) {
  HapticFeedback.selectionClick();
  final c = AppColors.of(context, listen: false);
  return showTempoSheet<void>(
    context: context,
    backgroundColor: c.isDark ? const Color(0xFF141416) : c.card,
    borderRadius: 28,
    showDragHandle: true,
    builder: (_) => _BmiDetailPopupBody(bmi: bmi),
  );
}

class _BmiDetailPopupBody extends StatelessWidget {
  final double bmi;

  const _BmiDetailPopupBody({required this.bmi});

  static const Color _lowBlue = Color(0xFF67B7F7);
  static const Color _normalGreen = Color(0xFF5AD16C);
  static const Color _highYellow = Color(0xFFF7C648);
  static const Color _veryHighOrange = Color(0xFFF49342);

  static const int _flexLow = 25;
  static const int _flexNormal = 28;
  static const int _flexHigh = 22;
  static const int _flexVeryHigh = 25;
  static const double _split1 = 0.25; // 18.5
  static const double _split2 = 0.53; // 24
  static const double _split3 = 0.75; // 28

  String get _levelLabel {
    if (bmi <= 0) return '--';
    if (bmi < 18.5) return 'Low';
    if (bmi < 24.0) return 'Normal';
    if (bmi < 28.0) return 'High';
    return 'Very high';
  }

  String get _adviceText {
    if (bmi <= 0) {
      return 'Add your height in Profile and log a weight entry to calculate your BMI.';
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

  double get _normalizedMarkerPosition {
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

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(22, 8, 22, bottomInset + 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Split metric header: BMI | Level
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TweenAnimationBuilder<double>(
                      tween: Tween<double>(
                        begin: bmi > 0 ? (bmi * 0.85) : 0,
                        end: bmi,
                      ),
                      duration: const Duration(milliseconds: 420),
                      curve: Curves.easeOutCubic,
                      builder: (_, val, __) => Text(
                        bmi > 0 ? val.toStringAsFixed(1) : '--',
                        style: TextStyle(
                          color: c.textPrimary,
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.6,
                          fontFeatures: const [FontFeature.tabularFigures()],
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
                height: 44,
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

          const SizedBox(height: 18),
          Divider(height: 1, color: c.divider),
          const SizedBox(height: 18),

          // Animated 4-zone BMI spectrum bar with hollow downward pointer
          LayoutBuilder(
            builder: (_, constraints) {
              final w = constraints.maxWidth;
              return Column(
                children: [
                  SizedBox(
                    height: 36,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        TweenAnimationBuilder<double>(
                          tween: Tween<double>(
                            begin: 0.08,
                            end: _normalizedMarkerPosition,
                          ),
                          duration: const Duration(milliseconds: 520),
                          curve: Curves.easeOutCubic,
                          builder: (_, pos, __) {
                            final markerX = (w * pos).clamp(10.0, w - 10.0);
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
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 2,
                          height: 16,
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
                                child: _SpectrumSegment(color: _normalGreen),
                              ),
                              SizedBox(width: 2.5),
                              Expanded(
                                flex: _flexHigh,
                                child: _SpectrumSegment(color: _highYellow),
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
                  const SizedBox(height: 6),
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

          const SizedBox(height: 12),

          // Legend rows
          const Row(
            children: [
              Expanded(child: _LegendItem(color: _lowBlue, label: 'Low')),
              Expanded(
                child: _LegendItem(color: _normalGreen, label: 'Normal'),
              ),
              Expanded(child: _LegendItem(color: _highYellow, label: 'High')),
            ],
          ),
          const SizedBox(height: 8),
          const Row(
            children: [
              Expanded(
                child: _LegendItem(color: _veryHighOrange, label: 'Very high'),
              ),
              Expanded(child: SizedBox.shrink()),
              Expanded(child: SizedBox.shrink()),
            ],
          ),

          const SizedBox(height: 18),

          Text(
            _adviceText,
            style: TextStyle(
              color: c.textSecondary,
              fontSize: 13.5,
              height: 1.45,
            ),
          ),

          const SizedBox(height: 22),

          SizedBox(
            height: 52,
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
        ],
      ),
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
