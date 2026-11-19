import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';
import '../widgets/tempo_sliver_header.dart';

/// Weight unit selector screen (`kg` / `lb`) matching the Mi Fitness Unit page.
class WeightUnitScreen extends StatefulWidget {
  final String initialUnit; // 'kg' | 'lb'

  const WeightUnitScreen({super.key, required this.initialUnit});

  @override
  State<WeightUnitScreen> createState() => _WeightUnitScreenState();
}

class _WeightUnitScreenState extends State<WeightUnitScreen> {
  static const Color _checkAccent = Color(0xFFE07B39);
  late String _selected;
  bool _popping = false;

  @override
  void initState() {
    super.initState();
    _selected = widget.initialUnit == 'lb' ? 'lb' : 'kg';
  }

  void _pick(String unit) {
    if (_popping) return;
    _popping = true;
    HapticFeedback.selectionClick();
    setState(() => _selected = unit);
    Future.delayed(const Duration(milliseconds: 140), () {
      if (mounted) Navigator.of(context).pop(unit);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);

    return Scaffold(
      backgroundColor: c.scaffold,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Top bar: Back chevron + centered "Unit"
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 14),
              child: Row(
                children: [
                  TempoGlassCircleButton(
                    glassOpacity: 0.0,
                    icon: TempoBackChevron(color: c.textPrimary, size: 22),
                    onPressed: () => Navigator.of(context).pop(_selected),
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        'Unit',
                        style: TextStyle(
                          color: c.textPrimary,
                          fontSize: 19,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.3,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 44),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _UnitOptionRow(
                    label: 'kg',
                    selected: _selected == 'kg',
                    accent: _checkAccent,
                    onTap: () => _pick('kg'),
                  ),
                  const SizedBox(height: 6),
                  _UnitOptionRow(
                    label: 'lb',
                    selected: _selected == 'lb',
                    accent: _checkAccent,
                    onTap: () => _pick('lb'),
                  ),
                  const SizedBox(height: 20),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Text(
                      'After switching units, slight discrepancies may result from the rounding of decimal places.',
                      style: TextStyle(
                        color: c.textTertiary,
                        fontSize: 13.5,
                        height: 1.45,
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
}

class _UnitOptionRow extends StatelessWidget {
  final String label;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  const _UnitOptionRow({
    required this.label,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final selectedBg = c.isDark
        ? accent.withValues(alpha: 0.16)
        : accent.withValues(alpha: 0.11);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        height: 58,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        decoration: BoxDecoration(
          color: selected ? selectedBg : Colors.transparent,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 28,
              child: AnimatedOpacity(
                opacity: selected ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 180),
                child: Icon(
                  CupertinoIcons.checkmark_alt,
                  color: accent,
                  size: 20,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: c.textPrimary,
                fontSize: 17,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
