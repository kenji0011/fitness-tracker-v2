import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';
import 'ios_stretch_sheet.dart';

/// Displays an Apple iOS-style Liquid Glass 4-digit PIN verification modal.
/// Returns the entered 4-digit PIN string (after optional validation) or null if cancelled.
Future<String?> showApplePinPadSheet({
  required BuildContext context,
  required String title,
  String subtitle = 'Enter your 4-digit PIN',
  Future<bool> Function(String pin)? onVerify,
}) {
  return showTempoSheet<String>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _ApplePinPadSheet(
      title: title,
      subtitle: subtitle,
      onVerify: onVerify,
    ),
  );
}

class _ApplePinPadSheet extends StatefulWidget {
  final String title;
  final String subtitle;
  final Future<bool> Function(String pin)? onVerify;

  const _ApplePinPadSheet({
    required this.title,
    required this.subtitle,
    this.onVerify,
  });

  @override
  State<_ApplePinPadSheet> createState() => _ApplePinPadSheetState();
}

class _ApplePinPadSheetState extends State<_ApplePinPadSheet>
    with SingleTickerProviderStateMixin {
  String _pin = '';
  String? _error;
  bool _isBusy = false;
  late final AnimationController _shakeController;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 360),
    );
  }

  @override
  void dispose() {
    _shakeController.dispose();
    super.dispose();
  }

  Future<void> _onDigit(String digit) async {
    if (_isBusy || _pin.length >= 4) return;
    HapticFeedback.lightImpact();
    setState(() {
      _error = null;
      _pin += digit;
    });

    if (_pin.length == 4) {
      if (widget.onVerify != null) {
        setState(() => _isBusy = true);
        final ok = await widget.onVerify!(_pin);
        if (!mounted) return;
        if (ok) {
          HapticFeedback.mediumImpact();
          Navigator.of(context).pop(_pin);
        } else {
          HapticFeedback.heavyImpact();
          setState(() {
            _isBusy = false;
            _pin = '';
            _error = 'Incorrect PIN. Please try again.';
          });
          _shakeController.forward(from: 0);
        }
      } else {
        Navigator.of(context).pop(_pin);
      }
    }
  }

  void _onBackspace() {
    if (_isBusy || _pin.isEmpty) return;
    HapticFeedback.selectionClick();
    setState(() {
      _error = null;
      _pin = _pin.substring(0, _pin.length - 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
        child: Container(
          padding: EdgeInsets.fromLTRB(24, 14, 24, bottomPad + 24),
          decoration: BoxDecoration(
            color: c.isDark
                ? const Color(0xFF1C1C1E).withValues(alpha: 0.90)
                : Colors.white.withValues(alpha: 0.92),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
            border: Border(top: BorderSide(color: c.glassBorder, width: 1)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 38,
                  height: 5,
                  decoration: BoxDecoration(
                    color: c.textTertiary.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                const SizedBox(height: 18),
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: c.accentSoft,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(CupertinoIcons.lock_fill, color: c.accent, size: 22),
                ),
                const SizedBox(height: 12),
                Text(
                  widget.title,
                  style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _error ?? widget.subtitle,
                  style: TextStyle(
                    color: _error != null ? c.moveRed : c.textSecondary,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 22),

                // 4 animated PIN dots
                AnimatedBuilder(
                  animation: _shakeController,
                  builder: (context, child) {
                    final offset = (_shakeController.value < 1 &&
                            _shakeController.value > 0)
                        ? ((_shakeController.value * 8).round().isEven ? 10.0 : -10.0) *
                            (1 - _shakeController.value)
                        : 0.0;
                    return Transform.translate(
                      offset: Offset(offset, 0),
                      child: child,
                    );
                  },
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(4, (i) {
                      final filled = i < _pin.length;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        margin: const EdgeInsets.symmetric(horizontal: 10),
                        width: filled ? 16 : 14,
                        height: filled ? 16 : 14,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: filled ? c.accent : Colors.transparent,
                          border: Border.all(
                            color: filled ? c.accent : c.textTertiary,
                            width: 1.8,
                          ),
                        ),
                      );
                    }),
                  ),
                ),
                const SizedBox(height: 26),

                // iOS-style circular numeric keypad
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 280),
                  child: Column(
                    children: [
                      _buildRow(['1', '2', '3'], c),
                      const SizedBox(height: 14),
                      _buildRow(['4', '5', '6'], c),
                      const SizedBox(height: 14),
                      _buildRow(['7', '8', '9'], c),
                      const SizedBox(height: 14),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          SizedBox(
                            width: 72,
                            height: 72,
                            child: TextButton(
                              onPressed: () => Navigator.of(context).pop(null),
                              child: Text(
                                'Cancel',
                                style: TextStyle(
                                  color: c.textSecondary,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ),
                          _buildKey('0', c),
                          SizedBox(
                            width: 72,
                            height: 72,
                            child: IconButton(
                              onPressed: _onBackspace,
                              icon: Icon(
                                CupertinoIcons.delete_left,
                                color: c.textPrimary,
                                size: 24,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRow(List<String> digits, AppColors c) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: digits.map((d) => _buildKey(d, c)).toList(),
    );
  }

  Widget _buildKey(String digit, AppColors c) {
    return Material(
      color: c.isDark
          ? Colors.white.withValues(alpha: 0.11)
          : Colors.black.withValues(alpha: 0.055),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _onDigit(digit),
        child: SizedBox(
          width: 72,
          height: 72,
          child: Center(
            child: Text(
              digit,
              style: TextStyle(
                color: c.textPrimary,
                fontSize: 28,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
