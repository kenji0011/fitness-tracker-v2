import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';
import 'ios_stretch_sheet.dart';
import 'liquid_glass_surface.dart';

/// User response from [showStepAccuracyWarningSheet].
class StepAccuracyWarningResult {
  final bool proceed;
  final bool suppressForToday;

  const StepAccuracyWarningResult({
    required this.proceed,
    this.suppressForToday = false,
  });
}

/// Floating bottom modal explaining step counter accuracy in plain,
/// non-technical language, padded cleanly above Android's bottom navbar.
Future<StepAccuracyWarningResult?> showStepAccuracyWarningSheet(
  BuildContext context,
) {
  return showTempoSheet<StepAccuracyWarningResult>(
    context: context,
    backgroundColor: null,
    skirtColor: Colors.transparent,
    showDragHandle: false,
    useRootNavigator: true,
    builder: (_) => const _StepAccuracyWarningModal(),
  );
}

class _StepAccuracyWarningModal extends StatefulWidget {
  const _StepAccuracyWarningModal();

  @override
  State<_StepAccuracyWarningModal> createState() =>
      _StepAccuracyWarningModalState();
}

class _StepAccuracyWarningModalState extends State<_StepAccuracyWarningModal> {
  static const Color _warnAmber = Color(0xFFFF9F0A);

  bool _dontShowAgainToday = false;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final bottomInset = math.max(MediaQuery.viewPaddingOf(context).bottom, 14.0);
    final floatingBottomMargin = bottomInset + 22.0;

    return Padding(
      padding: EdgeInsets.fromLTRB(14, 0, 14, floatingBottomMargin),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: c.isDark ? 0.56 : 0.16),
              blurRadius: 32,
              spreadRadius: -4,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: CustomPaint(
          foregroundPainter: LiquidGlassRimPainter(
            borderRadius: 28,
            isDark: c.isDark,
            intensity: 1.05,
            strokeWidth: 1.2,
          ),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: c.isDark
                    ? const [Color(0xFF23242A), Color(0xFF16171B)]
                    : const [Color(0xFFFFFFFF), Color(0xFFF5F6FA)],
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Subtle floating drag handle
                  Center(
                    child: Container(
                      width: 38,
                      height: 4.5,
                      decoration: BoxDecoration(
                        color: c.textTertiary.withValues(alpha: 0.34),
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),

                  // Centered Header (no close X button, no technical subtitle)
                  Column(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: _warnAmber
                              .withValues(alpha: c.isDark ? 0.22 : 0.14),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          CupertinoIcons.exclamationmark_triangle_fill,
                          color: _warnAmber,
                          size: 23,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Step Counter Accuracy',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: c.textPrimary,
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Simple, friendly, non-technical body (no em dashes, no icons)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Text(
                      'Step counts are an estimate and may vary depending on how you carry your phone. Driving, bumpy rides, or shaking your phone can add extra steps. You can also update your steps manually anytime.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: c.textSecondary,
                        fontSize: 14,
                        height: 1.48,
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),

                  // Circular toggle option above the two flat action buttons
                  Center(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() {
                          _dontShowAgainToday = !_dontShowAgainToday;
                        });
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 6,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              curve: Curves.easeOutCubic,
                              width: 21,
                              height: 21,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: _dontShowAgainToday
                                    ? c.accent
                                    : Colors.transparent,
                                border: Border.all(
                                  color: _dontShowAgainToday
                                      ? c.accent
                                      : c.textTertiary.withValues(alpha: 0.65),
                                  width: 1.8,
                                ),
                              ),
                              child: _dontShowAgainToday
                                  ? const Icon(
                                      CupertinoIcons.checkmark_alt,
                                      size: 13.5,
                                      color: Colors.white,
                                    )
                                  : null,
                            ),
                            const SizedBox(width: 9),
                            Text(
                              "Don't show again today",
                              style: TextStyle(
                                color: c.textPrimary,
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Side-by-side flat buttons: Cancel (left) | Enable (right)
                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 48,
                          child: TextButton(
                            style: TextButton.styleFrom(
                              backgroundColor: c.searchBg,
                              foregroundColor: c.textPrimary,
                              elevation: 0,
                              shadowColor: Colors.transparent,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            onPressed: () {
                              HapticFeedback.selectionClick();
                              Navigator.of(context).pop(null);
                            },
                            child: const Text(
                              'Cancel',
                              style: TextStyle(
                                fontSize: 15.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: SizedBox(
                          height: 48,
                          child: TextButton(
                            style: TextButton.styleFrom(
                              backgroundColor: c.accent,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shadowColor: Colors.transparent,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            onPressed: () {
                              HapticFeedback.selectionClick();
                              Navigator.of(context).pop(
                                StepAccuracyWarningResult(
                                  proceed: true,
                                  suppressForToday: _dontShowAgainToday,
                                ),
                              );
                            },
                            child: const Text(
                              'Enable',
                              style: TextStyle(
                                fontSize: 15.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
