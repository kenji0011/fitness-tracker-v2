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
import '../widgets/tempo_toast.dart';
import '../widgets/tempo_wheel_picker.dart';

class _MetricMeta {
  final String key;
  final String label;
  final IconData icon;
  final Color color;
  final bool supportsDate;

  const _MetricMeta({
    required this.key,
    required this.label,
    required this.icon,
    required this.color,
    this.supportsDate = true,
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

  static const List<_MetricMeta> _metrics = [
    _MetricMeta(
      key: 'weight',
      label: 'Weight',
      icon: CupertinoIcons.gauge,
      color: Color(0xFF4CD964),
    ),
    _MetricMeta(
      key: 'sleep',
      label: 'Sleep',
      icon: CupertinoIcons.bed_double_fill,
      color: Color(0xFF6B63F6),
    ),
    _MetricMeta(
      key: 'steps',
      label: 'Steps',
      icon: CupertinoIcons.hare_fill,
      color: Color(0xFF93DC2A),
      supportsDate: false,
    ),
    _MetricMeta(
      key: 'calories',
      label: 'Calories',
      icon: CupertinoIcons.flame_fill,
      color: Color(0xFFF36432),
      supportsDate: false,
    ),
    _MetricMeta(
      key: 'minutes',
      label: 'Activity',
      icon: CupertinoIcons.clock_fill,
      color: Color(0xFF56B7FF),
      supportsDate: false,
    ),
    _MetricMeta(
      key: 'waist',
      label: 'Waist',
      icon: CupertinoIcons.resize_h,
      color: Color(0xFF3CC29E),
    ),
    _MetricMeta(
      key: 'water',
      label: 'Water',
      icon: CupertinoIcons.drop_fill,
      color: Color(0xFF38BDF8),
    ),
    _MetricMeta(
      key: 'height',
      label: 'Height',
      icon: CupertinoIcons.arrow_up_down,
      color: Color(0xFF0A84FF),
    ),
  ];

  // Wheel option lists
  static final List<String> _hours24 =
      List.generate(24, (i) => i.toString().padLeft(2, '0'));
  static final List<String> _hours10 =
      List.generate(10, (i) => i.toString().padLeft(2, '0'));
  static final List<String> _mins60 =
      List.generate(60, (i) => i.toString().padLeft(2, '0'));
  static final List<String> _tenths = List.generate(10, (i) => '$i');
  static final List<String> _kgWhole =
      List.generate(231, (i) => '${20 + i}'); // 20..250 kg
  static final List<String> _lbWhole =
      List.generate(507, (i) => '${44 + i}'); // 44..550 lb
  static final List<String> _waistWhole =
      List.generate(161, (i) => '${40 + i}'); // 40..200 cm
  static final List<String> _heightCm =
      List.generate(161, (i) => '${80 + i}'); // 80..240 cm
  static final List<String> _stepThousands =
      List.generate(51, (i) => '$i'); // 0..50k
  static final List<String> _stepHundreds =
      List.generate(10, (i) => (i * 100).toString().padLeft(3, '0')); // 000..900
  static final List<String> _calorieSteps =
      List.generate(160, (i) => '${(i + 1) * 25}'); // 25..4000 kcal
  static final List<String> _waterMlSteps =
      List.generate(80, (i) => '${(i + 1) * 50}'); // 50..4000 ml

  late String _selectedMetric;
  DateTime _selectedDate = DateTime.now();
  String _weightUnit = 'kg';
  bool _saving = false;

  // Per-metric wheel state
  int _weightWholeIdx = 45; // 65 kg default
  int _weightDecIdx = 0;
  int _sleepHrsIdx = 7;
  int _sleepMinsIdx = 30;
  int _actHrsIdx = 0;
  int _actMinsIdx = 30;
  int _stepsKIdx = 5; // 5,000
  int _stepsHIdx = 0;
  int _calIdx = 11; // 300 kcal
  int _waistWholeIdx = 38; // 78 cm
  int _waistDecIdx = 0;
  int _waterIdx = 4; // 250 ml
  int _heightIdx = 93; // 173 cm

  @override
  void initState() {
    super.initState();
    _selectedMetric = widget.initialMetric ?? 'weight';
    _loadPrefsAndSyncWheels();
  }

  Future<void> _loadPrefsAndSyncWheels() async {
    final pid = context.read<ActiveProfileProvider>().activeProfileId;
    if (pid != null) {
      final savedUnit = await TempoRustDb.instance.getSetting('weight_unit_$pid');
      if (mounted && savedUnit == 'lb') {
        _weightUnit = 'lb';
      }
    }
    if (!mounted) return;
    setState(_syncWheelsFromProfile);
  }

  void _syncWheelsFromProfile() {
    final profile = context.read<ActiveProfileProvider>().activeProfile;
    if (profile == null) return;

    if (profile.weightKg > 0) {
      final displayW =
          _weightUnit == 'lb' ? profile.weightKg * _kgToLb : profile.weightKg;
      final minW = _weightUnit == 'lb' ? 44 : 20;
      final maxW = _weightUnit == 'lb' ? 550 : 250;
      final whole = displayW.floor().clamp(minW, maxW);
      final dec = ((displayW - whole) * 10).round().clamp(0, 9);
      _weightWholeIdx = whole - minW;
      _weightDecIdx = dec;
    } else if (_weightUnit == 'lb') {
      _weightWholeIdx = 143 - 44;
      _weightDecIdx = 0;
    }

    if (profile.sleepHours > 0) {
      final totalMins = (profile.sleepHours * 60).round().clamp(15, 23 * 60 + 59);
      _sleepHrsIdx = totalMins ~/ 60;
      _sleepMinsIdx = totalMins % 60;
    }

    if (profile.waistCm > 0) {
      final whole = profile.waistCm.floor().clamp(40, 200);
      final dec = ((profile.waistCm - whole) * 10).round().clamp(0, 9);
      _waistWholeIdx = whole - 40;
      _waistDecIdx = dec;
    }

    if (profile.heightCm > 0) {
      _heightIdx = profile.heightCm.round().clamp(80, 240) - 80;
    }
  }

  _MetricMeta get _meta => _metrics.firstWhere(
        (m) => m.key == _selectedMetric,
        orElse: () => _metrics.first,
      );

  String _currentReadout() {
    switch (_selectedMetric) {
      case 'weight':
        final base = _weightUnit == 'lb' ? 44 : 20;
        final val = (base + _weightWholeIdx) + _weightDecIdx / 10.0;
        return '${val.toStringAsFixed(1)} $_weightUnit';
      case 'sleep':
        return '${_sleepHrsIdx}h ${_sleepMinsIdx.toString().padLeft(2, '0')}m';
      case 'minutes':
        final total = _actHrsIdx * 60 + _actMinsIdx;
        return _actHrsIdx > 0
            ? '${_actHrsIdx}h ${_actMinsIdx.toString().padLeft(2, '0')}m ($total min)'
            : '$total min';
      case 'steps':
        final total = _stepsKIdx * 1000 + _stepsHIdx * 100;
        return '${NumberFormat('#,###').format(total)} steps';
      case 'calories':
        return '${NumberFormat('#,###').format((_calIdx + 1) * 25)} kcal';
      case 'waist':
        final val = (40 + _waistWholeIdx) + _waistDecIdx / 10.0;
        return '${val.toStringAsFixed(1)} cm';
      case 'water':
        return '${NumberFormat('#,###').format((_waterIdx + 1) * 50)} ml';
      case 'height':
        return '${80 + _heightIdx} cm';
      default:
        return '';
    }
  }

  String? _currentProfileSummary(LocalProfile? profile) {
    if (profile == null) return null;
    switch (_selectedMetric) {
      case 'weight':
        if (profile.weightKg <= 0) return null;
        final w = _weightUnit == 'lb'
            ? profile.weightKg * _kgToLb
            : profile.weightKg;
        return 'Current: ${w.toStringAsFixed(1)} $_weightUnit';
      case 'sleep':
        if (profile.sleepHours <= 0) return null;
        final totalMins = (profile.sleepHours * 60).round();
        return 'Current: ${totalMins ~/ 60}h ${(totalMins % 60).toString().padLeft(2, '0')}m';
      case 'waist':
        if (profile.waistCm <= 0) return null;
        return 'Current: ${profile.waistCm.toStringAsFixed(1)} cm';
      case 'height':
        if (profile.heightCm <= 0) return null;
        return 'Current: ${profile.heightCm.round()} cm';
      default:
        return null;
    }
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

    HapticFeedback.lightImpact();
    setState(() => _saving = true);

    try {
      final db = TempoRustDb.instance;
      final now = DateTime.now();
      final recordedAt = DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
        now.hour,
        now.minute,
        now.second,
      );

      switch (_selectedMetric) {
        case 'steps':
          final steps = _stepsKIdx * 1000 + _stepsHIdx * 100;
          if (steps <= 0) {
            setState(() => _saving = false);
            showTempoToast(context, 'Scroll to select steps above 0', isError: true);
            return;
          }
          await db.upsertDailyActivity(profileId: profileId, steps: steps);
          break;
        case 'calories':
          final kcal = (_calIdx + 1) * 25;
          await db.upsertDailyActivity(profileId: profileId, calories: kcal);
          break;
        case 'minutes':
          final totalMin = _actHrsIdx * 60 + _actMinsIdx;
          if (totalMin <= 0) {
            setState(() => _saving = false);
            showTempoToast(
              context,
              'Scroll to select activity duration above 0 min',
              isError: true,
            );
            return;
          }
          await db.upsertDailyActivity(profileId: profileId, minutes: totalMin);
          break;
        case 'sleep':
          final totalMin = _sleepHrsIdx * 60 + _sleepMinsIdx;
          if (totalMin < 15) {
            setState(() => _saving = false);
            showTempoToast(
              context,
              'Select at least 15 minutes of sleep',
              isError: true,
            );
            return;
          }
          await db.logBodyMetric(
            profileId: profileId,
            metricType: 'sleep',
            value: totalMin / 60.0,
            recordedAt: recordedAt,
          );
          break;
        case 'weight':
          final base = _weightUnit == 'lb' ? 44 : 20;
          final displayW = (base + _weightWholeIdx) + _weightDecIdx / 10.0;
          final kgVal = _weightUnit == 'lb' ? displayW / _kgToLb : displayW;
          await db.logBodyMetric(
            profileId: profileId,
            metricType: 'weight',
            value: kgVal,
            recordedAt: recordedAt,
          );
          break;
        case 'waist':
          final cmVal = (40 + _waistWholeIdx) + _waistDecIdx / 10.0;
          await db.logBodyMetric(
            profileId: profileId,
            metricType: 'waist',
            value: cmVal,
            recordedAt: recordedAt,
          );
          break;
        case 'water':
          final mlVal = ((_waterIdx + 1) * 50).toDouble();
          await db.logBodyMetric(
            profileId: profileId,
            metricType: 'water',
            value: mlVal,
            recordedAt: recordedAt,
          );
          break;
        case 'height':
          final hVal = (80 + _heightIdx).toDouble();
          await db.logBodyMetric(
            profileId: profileId,
            metricType: 'height',
            value: hVal,
            recordedAt: recordedAt,
          );
          break;
      }

      await profileProvider.refreshProfiles();
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showTempoToast(context, 'Error saving data: $e', isError: true);
      }
    }
  }

  Widget _separatorSymbol(String symbol, AppColors c) {
    return Padding(
      padding: const EdgeInsets.only(top: 22, left: 4, right: 4),
      child: Text(
        symbol,
        style: TextStyle(
          color: c.textPrimary,
          fontSize: 32,
          fontWeight: FontWeight.w600,
          height: 1.0,
        ),
      ),
    );
  }

  Widget _inlineUnit(String unit, AppColors c) {
    return Padding(
      padding: const EdgeInsets.only(top: 24, left: 8),
      child: Text(
        unit,
        style: TextStyle(
          color: c.textSecondary,
          fontSize: 17,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildWheelForSelectedMetric(AppColors c) {
    switch (_selectedMetric) {
      case 'sleep':
        return TempoWheelStage(
          key: const ValueKey('wheel_sleep'),
          children: [
            TempoWheelColumn(
              key: const ValueKey('sleep_hrs_col'),
              headerLabel: 'hrs',
              items: _hours24,
              initialIndex: _sleepHrsIdx,
              looping: true,
              width: 96,
              onSelectedIndexChanged: (i) => setState(() => _sleepHrsIdx = i),
            ),
            _separatorSymbol(':', c),
            TempoWheelColumn(
              key: const ValueKey('sleep_min_col'),
              headerLabel: 'min',
              items: _mins60,
              initialIndex: _sleepMinsIdx,
              looping: true,
              width: 96,
              onSelectedIndexChanged: (i) => setState(() => _sleepMinsIdx = i),
            ),
          ],
        );

      case 'minutes':
        return TempoWheelStage(
          key: const ValueKey('wheel_minutes'),
          children: [
            TempoWheelColumn(
              key: const ValueKey('act_hrs_col'),
              headerLabel: 'hrs',
              items: _hours10,
              initialIndex: _actHrsIdx,
              looping: false,
              width: 96,
              onSelectedIndexChanged: (i) => setState(() => _actHrsIdx = i),
            ),
            _separatorSymbol(':', c),
            TempoWheelColumn(
              key: const ValueKey('act_min_col'),
              headerLabel: 'min',
              items: _mins60,
              initialIndex: _actMinsIdx,
              looping: true,
              width: 96,
              onSelectedIndexChanged: (i) => setState(() => _actMinsIdx = i),
            ),
          ],
        );

      case 'weight':
        final wholeList = _weightUnit == 'lb' ? _lbWhole : _kgWhole;
        return TempoWheelStage(
          key: ValueKey('wheel_weight_$_weightUnit'),
          children: [
            TempoWheelColumn(
              key: ValueKey('weight_whole_$_weightUnit'),
              headerLabel: _weightUnit,
              items: wholeList,
              initialIndex: _weightWholeIdx.clamp(0, wholeList.length - 1),
              width: 100,
              onSelectedIndexChanged: (i) =>
                  setState(() => _weightWholeIdx = i),
            ),
            _separatorSymbol('.', c),
            TempoWheelColumn(
              key: const ValueKey('weight_dec'),
              headerLabel: '.0',
              items: _tenths,
              initialIndex: _weightDecIdx,
              looping: true,
              width: 68,
              onSelectedIndexChanged: (i) => setState(() => _weightDecIdx = i),
            ),
            _inlineUnit(_weightUnit, c),
          ],
        );

      case 'waist':
        return TempoWheelStage(
          key: const ValueKey('wheel_waist'),
          children: [
            TempoWheelColumn(
              key: const ValueKey('waist_whole'),
              headerLabel: 'cm',
              items: _waistWhole,
              initialIndex: _waistWholeIdx,
              width: 98,
              onSelectedIndexChanged: (i) =>
                  setState(() => _waistWholeIdx = i),
            ),
            _separatorSymbol('.', c),
            TempoWheelColumn(
              key: const ValueKey('waist_dec'),
              headerLabel: '.0',
              items: _tenths,
              initialIndex: _waistDecIdx,
              looping: true,
              width: 68,
              onSelectedIndexChanged: (i) => setState(() => _waistDecIdx = i),
            ),
            _inlineUnit('cm', c),
          ],
        );

      case 'steps':
        return TempoWheelStage(
          key: const ValueKey('wheel_steps'),
          children: [
            TempoWheelColumn(
              key: const ValueKey('steps_k'),
              headerLabel: 'thousands',
              items: _stepThousands,
              initialIndex: _stepsKIdx,
              width: 82,
              onSelectedIndexChanged: (i) => setState(() => _stepsKIdx = i),
            ),
            _separatorSymbol(',', c),
            TempoWheelColumn(
              key: const ValueKey('steps_h'),
              headerLabel: 'hundreds',
              items: _stepHundreds,
              initialIndex: _stepsHIdx,
              looping: true,
              width: 102,
              onSelectedIndexChanged: (i) => setState(() => _stepsHIdx = i),
            ),
            _inlineUnit('steps', c),
          ],
        );

      case 'calories':
        return TempoWheelStage(
          key: const ValueKey('wheel_calories'),
          children: [
            TempoWheelColumn(
              key: const ValueKey('cal_col'),
              headerLabel: 'energy',
              items: _calorieSteps,
              initialIndex: _calIdx,
              width: 132,
              onSelectedIndexChanged: (i) => setState(() => _calIdx = i),
            ),
            _inlineUnit('kcal', c),
          ],
        );

      case 'water':
        return TempoWheelStage(
          key: const ValueKey('wheel_water'),
          children: [
            TempoWheelColumn(
              key: const ValueKey('water_col'),
              headerLabel: 'volume',
              items: _waterMlSteps,
              initialIndex: _waterIdx,
              width: 132,
              onSelectedIndexChanged: (i) => setState(() => _waterIdx = i),
            ),
            _inlineUnit('ml', c),
          ],
        );

      case 'height':
      default:
        return TempoWheelStage(
          key: const ValueKey('wheel_height'),
          children: [
            TempoWheelColumn(
              key: const ValueKey('height_col'),
              headerLabel: 'height',
              items: _heightCm,
              initialIndex: _heightIdx,
              width: 120,
              onSelectedIndexChanged: (i) => setState(() => _heightIdx = i),
            ),
            _inlineUnit('cm', c),
          ],
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final profile = context.watch<ActiveProfileProvider>().activeProfile;
    final meta = _meta;
    final currentSummary = _currentProfileSummary(profile);

    return Scaffold(
      backgroundColor: c.scaffold,
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 14),
          child: SizedBox(
            height: 54,
            width: double.infinity,
            child: TextButton(
              style: TextButton.styleFrom(
                backgroundColor: c.accent,
                disabledBackgroundColor: c.accent.withValues(alpha: 0.6),
                foregroundColor: Colors.white,
                disabledForegroundColor: Colors.white,
                elevation: 0,
                shadowColor: Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
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
                      'Save ${meta.label.toLowerCase()}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ),
        ),
      ),
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
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
            sliver: SliverList.list(
              children: [
                // Compact metric selector chips
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
                  children: _metrics.map((m) {
                    final selected = m.key == _selectedMetric;
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() => _selectedMetric = m.key);
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

                // Vertical Drum-Wheel Entry Card (HyperOS 3 / Clock inspired)
                AppleCard(
                  borderRadius: 26,
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: meta.color,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              meta.icon,
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
                                  meta.label,
                                  style: TextStyle(
                                    color: c.textPrimary,
                                    fontSize: 16.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                if (currentSummary != null)
                                  Text(
                                    currentSummary,
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
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 11,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: meta.color.withValues(
                                alpha: c.isDark ? 0.22 : 0.12,
                              ),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              _currentReadout(),
                              style: TextStyle(
                                color: meta.color,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 10),

                      // Smooth scrollable drum wheel(s)
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeInCubic,
                        child: _buildWheelForSelectedMetric(c),
                      ),

                      // Date selector for body/recovery metrics
                      if (meta.supportsDate) ...[
                        const SizedBox(height: 12),
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
              ],
            ),
          ),
        ],
      ),
    );
  }
}
