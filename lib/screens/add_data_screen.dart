import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/local_profile.dart';
import '../services/active_profile_provider.dart';
import '../services/tempo_rust_db.dart';
import '../theme/app_colors.dart';
import '../widgets/liquid_glass_surface.dart';
import '../widgets/tempo_sliver_header.dart';

class _MetricSpec {
  final String key;
  final String label;
  final String unit;
  final String hint;
  final IconData icon;
  final Color color;
  final double step;
  final double minVal;
  final double maxVal;
  final bool isInteger;
  final bool supportsDate;
  final List<double> presets;

  const _MetricSpec({
    required this.key,
    required this.label,
    required this.unit,
    required this.hint,
    required this.icon,
    required this.color,
    required this.step,
    required this.minVal,
    required this.maxVal,
    this.isInteger = false,
    this.supportsDate = true,
    this.presets = const [],
  });
}

class AddDataScreen extends StatefulWidget {
  final String? initialMetric;

  const AddDataScreen({super.key, this.initialMetric});

  @override
  State<AddDataScreen> createState() => _AddDataScreenState();
}

class _AddDataScreenState extends State<AddDataScreen> {
  static const double _kgToLb = 2.20462262;

  final _valueCtrl = TextEditingController();
  late String _selectedMetric;
  DateTime _selectedDate = DateTime.now();
  String _weightUnit = 'kg';
  bool _saving = false;

  static const List<_MetricSpec> _baseMetrics = [
    _MetricSpec(
      key: 'weight',
      label: 'Weight',
      unit: 'kg',
      hint: '65.0',
      icon: CupertinoIcons.gauge,
      color: Color(0xFF4CD964),
      step: 0.1,
      minVal: 20,
      maxVal: 350,
      presets: [55, 60, 65, 70, 75],
    ),
    _MetricSpec(
      key: 'sleep',
      label: 'Sleep',
      unit: 'hrs',
      hint: '7.5',
      icon: CupertinoIcons.bed_double_fill,
      color: Color(0xFF6B63F6),
      step: 0.5,
      minVal: 0.5,
      maxVal: 16,
      presets: [6.0, 7.0, 7.5, 8.0, 9.0],
    ),
    _MetricSpec(
      key: 'steps',
      label: 'Steps',
      unit: 'steps',
      hint: '5000',
      icon: CupertinoIcons.hare_fill,
      color: Color(0xFF93DC2A),
      step: 500,
      minVal: 1,
      maxVal: 100000,
      isInteger: true,
      supportsDate: false,
      presets: [1000, 2500, 5000, 7500, 10000],
    ),
    _MetricSpec(
      key: 'calories',
      label: 'Calories',
      unit: 'kcal',
      hint: '300',
      icon: CupertinoIcons.flame_fill,
      color: Color(0xFFF36432),
      step: 50,
      minVal: 1,
      maxVal: 10000,
      isInteger: true,
      supportsDate: false,
      presets: [150, 300, 450, 600, 800],
    ),
    _MetricSpec(
      key: 'minutes',
      label: 'Activity',
      unit: 'min',
      hint: '30',
      icon: CupertinoIcons.clock_fill,
      color: Color(0xFF56B7FF),
      step: 5,
      minVal: 1,
      maxVal: 600,
      isInteger: true,
      supportsDate: false,
      presets: [15, 30, 45, 60, 90],
    ),
    _MetricSpec(
      key: 'waist',
      label: 'Waist',
      unit: 'cm',
      hint: '78.0',
      icon: CupertinoIcons.resize_h,
      color: Color(0xFF3CC29E),
      step: 0.5,
      minVal: 40,
      maxVal: 200,
      presets: [70, 75, 80, 85, 90],
    ),
    _MetricSpec(
      key: 'height',
      label: 'Height',
      unit: 'cm',
      hint: '173',
      icon: CupertinoIcons.arrow_up_down,
      color: Color(0xFF0A84FF),
      step: 1,
      minVal: 80,
      maxVal: 240,
      isInteger: true,
      presets: [160, 165, 170, 175, 180],
    ),
  ];

  @override
  void initState() {
    super.initState();
    _selectedMetric = widget.initialMetric ?? 'weight';
    _loadPrefsAndPrefill();
  }

  Future<void> _loadPrefsAndPrefill() async {
    final pid = context.read<ActiveProfileProvider>().activeProfileId;
    if (pid != null) {
      final savedUnit = await TempoRustDb.instance.getSetting('weight_unit_$pid');
      if (mounted && savedUnit == 'lb') {
        _weightUnit = 'lb';
      }
    }
    if (!mounted) return;
    setState(() {
      _prefillCurrentValue();
    });
  }

  void _prefillCurrentValue() {
    final profile = context.read<ActiveProfileProvider>().activeProfile;
    final val = _currentProfileValue(profile);
    if (val != null && val > 0) {
      _valueCtrl.text = _formatForInput(val);
    } else {
      _valueCtrl.clear();
    }
  }

  @override
  void dispose() {
    _valueCtrl.dispose();
    super.dispose();
  }

  _MetricSpec get _spec {
    final base = _baseMetrics.firstWhere(
      (m) => m.key == _selectedMetric,
      orElse: () => _baseMetrics.first,
    );
    if (base.key == 'weight' && _weightUnit == 'lb') {
      return const _MetricSpec(
        key: 'weight',
        label: 'Weight',
        unit: 'lb',
        hint: '143.0',
        icon: CupertinoIcons.gauge,
        color: Color(0xFF4CD964),
        step: 0.2,
        minVal: 44,
        maxVal: 770,
        presets: [120, 135, 150, 165, 180],
      );
    }
    return base;
  }

  double? _currentProfileValue(LocalProfile? profile) {
    if (profile == null) return null;
    switch (_selectedMetric) {
      case 'weight':
        if (profile.weightKg <= 0) return null;
        return _weightUnit == 'lb'
            ? profile.weightKg * _kgToLb
            : profile.weightKg;
      case 'sleep':
        return profile.sleepHours > 0 ? profile.sleepHours : null;
      case 'waist':
        return profile.waistCm > 0 ? profile.waistCm : null;
      case 'height':
        return profile.heightCm > 0 ? profile.heightCm : null;
      default:
        return null;
    }
  }

  String _formatForInput(double val) {
    final s = _spec;
    if (s.isInteger) return val.round().toString();
    if (s.key == 'weight') return val.toStringAsFixed(2);
    return val.toStringAsFixed(1);
  }

  String _formatPreset(double val) {
    final s = _spec;
    if (s.key == 'steps') {
      return val >= 1000 ? '${(val / 1000).toStringAsFixed(val % 1000 == 0 ? 0 : 1)}k' : '${val.round()}';
    }
    if (val == val.roundToDouble()) return '${val.round()}';
    return val.toStringAsFixed(1);
  }

  void _stepBy(double delta) {
    HapticFeedback.selectionClick();
    final s = _spec;
    final fallback = double.tryParse(s.hint) ?? s.minVal;
    final cur = double.tryParse(_valueCtrl.text.trim()) ?? fallback;
    final next = (cur + delta).clamp(s.minVal, s.maxVal);
    setState(() {
      _valueCtrl.text = _formatForInput(next);
    });
  }

  Future<void> _pickDate() async {
    HapticFeedback.selectionClick();
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate.isAfter(now) ? now : _selectedDate,
      firstDate: DateTime(2020),
      lastDate: now,
    );
    if (picked != null && mounted) {
      setState(() => _selectedDate = picked);
    }
  }

  Future<void> _save() async {
    final profileProvider = context.read<ActiveProfileProvider>();
    final profileId = profileProvider.activeProfileId;
    if (profileId == null) return;

    final s = _spec;
    final raw = double.tryParse(_valueCtrl.text.trim());
    if (raw == null || raw < s.minVal || raw > s.maxVal) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Enter a value between ${s.minVal.toStringAsFixed(s.isInteger ? 0 : 1)} and ${s.maxVal.toStringAsFixed(s.isInteger ? 0 : 1)} ${s.unit}',
          ),
        ),
      );
      return;
    }

    HapticFeedback.lightImpact();
    setState(() => _saving = true);
    try {
      final db = TempoRustDb.instance;
      if (_selectedMetric == 'steps') {
        await db.upsertDailyActivity(
          profileId: profileId,
          steps: raw.round(),
        );
      } else if (_selectedMetric == 'calories') {
        await db.upsertDailyActivity(
          profileId: profileId,
          calories: raw.round(),
        );
      } else if (_selectedMetric == 'minutes') {
        await db.upsertDailyActivity(
          profileId: profileId,
          minutes: raw.round(),
        );
      } else {
        final valueToStore =
            (_selectedMetric == 'weight' && _weightUnit == 'lb')
                ? raw / _kgToLb
                : raw;
        final now = DateTime.now();
        final recordedAt = DateTime(
          _selectedDate.year,
          _selectedDate.month,
          _selectedDate.day,
          now.hour,
          now.minute,
        );
        await db.logBodyMetric(
          profileId: profileId,
          metricType: _selectedMetric,
          value: valueToStore,
          recordedAt: recordedAt,
        );
      }
      await profileProvider.refreshProfiles();
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving data: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final profile = context.watch<ActiveProfileProvider>().activeProfile;
    final spec = _spec;
    final currentVal = _currentProfileValue(profile);
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      backgroundColor: c.scaffold,
      body: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        slivers: [
          TempoSliverHeader(
            title: 'Log Health Data',
            showBackButton: true,
            onBack: () => Navigator.of(context).pop(false),
          ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(18, 8, 18, bottomInset + 36),
            sliver: SliverList.list(
              children: [
                // Compact metric selector cards
                Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 10),
                  child: Text(
                    'Metric',
                    style: TextStyle(
                      color: c.textSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Wrap(
                  spacing: 9,
                  runSpacing: 9,
                  children: _baseMetrics.map((m) {
                    final selected = m.key == _selectedMetric;
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() {
                          _selectedMetric = m.key;
                          _prefillCurrentValue();
                        });
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOutCubic,
                        padding: const EdgeInsets.fromLTRB(9, 8, 13, 8),
                        decoration: BoxDecoration(
                          color: selected
                              ? m.color.withValues(alpha: c.isDark ? 0.24 : 0.13)
                              : c.card,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: selected
                                ? m.color.withValues(alpha: 0.7)
                                : (c.isDark
                                    ? Colors.white.withValues(alpha: 0.06)
                                    : Colors.black.withValues(alpha: 0.06)),
                            width: selected ? 1.4 : 1.0,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 26,
                              height: 26,
                              decoration: BoxDecoration(
                                color: m.color,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                m.icon,
                                size: 14,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              m.label,
                              style: TextStyle(
                                color: c.textPrimary,
                                fontWeight: selected
                                    ? FontWeight.w600
                                    : FontWeight.w500,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),

                const SizedBox(height: 18),

                // Main tactile value entry card
                AppleCard(
                  borderRadius: 24,
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: spec.color,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              spec.icon,
                              color: Colors.white,
                              size: 16,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  spec.label,
                                  style: TextStyle(
                                    color: c.textPrimary,
                                    fontSize: 16.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                if (currentVal != null)
                                  Text(
                                    'Current: ${_formatForInput(currentVal)} ${spec.unit}',
                                    style: TextStyle(
                                      color: c.textTertiary,
                                      fontSize: 12.5,
                                      fontFeatures: const [
                                        FontFeature.tabularFigures(),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),

                      // Stepper + centered tabular input
                      Row(
                        children: [
                          _InputStepper(
                            icon: CupertinoIcons.minus,
                            onTap: () => _stepBy(-spec.step),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: _valueCtrl,
                              textAlign: TextAlign.center,
                              keyboardType: TextInputType.numberWithOptions(
                                decimal: !spec.isInteger,
                              ),
                              style: TextStyle(
                                color: c.textPrimary,
                                fontSize: 28,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.5,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                              decoration: InputDecoration(
                                hintText: spec.hint,
                                hintStyle: TextStyle(
                                  color: c.textHint,
                                  fontSize: 24,
                                  fontWeight: FontWeight.w500,
                                ),
                                suffixText: spec.unit,
                                suffixStyle: TextStyle(
                                  color: c.textSecondary,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                                filled: true,
                                fillColor: c.searchBg,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 14,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          _InputStepper(
                            icon: CupertinoIcons.add,
                            onTap: () => _stepBy(spec.step),
                          ),
                        ],
                      ),

                      // Quick preset chips
                      if (spec.presets.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: spec.presets.map((p) {
                            final currentNum =
                                double.tryParse(_valueCtrl.text.trim());
                            final active =
                                currentNum != null && (currentNum - p).abs() < 0.01;
                            return Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 3,
                                ),
                                child: GestureDetector(
                                  onTap: () {
                                    HapticFeedback.selectionClick();
                                    setState(() {
                                      _valueCtrl.text = _formatForInput(p);
                                    });
                                  },
                                  child: AnimatedContainer(
                                    duration:
                                        const Duration(milliseconds: 160),
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 8,
                                    ),
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: active
                                          ? spec.color.withValues(alpha: 0.16)
                                          : c.searchBg,
                                      borderRadius: BorderRadius.circular(12),
                                      border: active
                                          ? Border.all(
                                              color: spec.color
                                                  .withValues(alpha: 0.55),
                                            )
                                          : null,
                                    ),
                                    child: Text(
                                      _formatPreset(p),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: active
                                            ? spec.color
                                            : c.textSecondary,
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w600,
                                        fontFeatures: const [
                                          FontFeature.tabularFigures(),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ],

                      // Date row for body/recovery metrics
                      if (spec.supportsDate) ...[
                        const SizedBox(height: 14),
                        GestureDetector(
                          onTap: _pickDate,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              color: c.searchBg,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  CupertinoIcons.calendar,
                                  size: 18,
                                  color: c.textSecondary,
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  'Date',
                                  style: TextStyle(
                                    color: c.textSecondary,
                                    fontSize: 14.5,
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  DateFormat('MM/dd/yyyy')
                                      .format(_selectedDate),
                                  style: TextStyle(
                                    color: c.textPrimary,
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.w600,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Icon(
                                  CupertinoIcons.chevron_right,
                                  size: 14,
                                  color: c.textTertiary,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                const SizedBox(height: 18),

                SizedBox(
                  height: 52,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: c.accent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            'Save ${spec.label.toLowerCase()}',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
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

class _InputStepper extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _InputStepper({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: c.searchBg,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: c.textPrimary, size: 20),
      ),
    );
  }
}
