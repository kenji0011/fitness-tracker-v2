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
import '../widgets/tempo_morph_calendar.dart';
import '../widgets/tempo_sliver_header.dart';
import '../widgets/tempo_toast.dart';
import '../widgets/tempo_wheel_picker.dart';

class _MetricMeta {
  final String key;
  final String label;
  final IconData icon;
  final Color color;

  const _MetricMeta({
    required this.key,
    required this.label,
    required this.icon,
    required this.color,
  });
}

class _QuickPreset {
  final String label;
  final VoidCallback onTap;
  final bool active;

  const _QuickPreset({
    required this.label,
    required this.onTap,
    this.active = false,
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
    ),
    _MetricMeta(
      key: 'calories',
      label: 'Calories',
      icon: CupertinoIcons.flame_fill,
      color: Color(0xFFF36432),
    ),
    _MetricMeta(
      key: 'minutes',
      label: 'Activity',
      icon: CupertinoIcons.clock_fill,
      color: Color(0xFF56B7FF),
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

  final GlobalKey _datePillKey = GlobalKey();
  late final Map<String, GlobalKey> _metricChipKeys = {
    for (final m in _metrics) m.key: GlobalKey(),
  };

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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollSelectedMetricIntoView(animate: false);
    });
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

  void _scrollSelectedMetricIntoView({bool animate = true}) {
    final ctx = _metricChipKeys[_selectedMetric]?.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      alignment: 0.45,
      duration: animate ? const Duration(milliseconds: 280) : Duration.zero,
      curve: Curves.easeOutCubic,
    );
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

  void _toggleWeightUnit() async {
    HapticFeedback.selectionClick();
    final oldBase = _weightUnit == 'lb' ? 44 : 20;
    final currentDisplay = (oldBase + _weightWholeIdx) + _weightDecIdx / 10.0;
    final kgVal =
        _weightUnit == 'lb' ? currentDisplay / _kgToLb : currentDisplay;

    final nextUnit = _weightUnit == 'kg' ? 'lb' : 'kg';
    final nextDisplay = nextUnit == 'lb' ? kgVal * _kgToLb : kgVal;
    final minW = nextUnit == 'lb' ? 44 : 20;
    final maxW = nextUnit == 'lb' ? 550 : 250;
    final clamped = nextDisplay.clamp(minW.toDouble(), maxW.toDouble());
    final whole = clamped.floor().clamp(minW, maxW);
    final dec = ((clamped - whole) * 10).round().clamp(0, 9);

    setState(() {
      _weightUnit = nextUnit;
      _weightWholeIdx = whole - minW;
      _weightDecIdx = dec;
    });

    final pid = context.read<ActiveProfileProvider>().activeProfileId;
    if (pid != null) {
      await TempoRustDb.instance.setSetting('weight_unit_$pid', nextUnit);
    }
  }

  _MetricMeta get _meta => _metrics.firstWhere(
        (m) => m.key == _selectedMetric,
        orElse: () => _metrics.first,
      );

  ({String value, String unit}) _currentHeroParts() {
    switch (_selectedMetric) {
      case 'weight':
        final base = _weightUnit == 'lb' ? 44 : 20;
        final val = (base + _weightWholeIdx) + _weightDecIdx / 10.0;
        return (value: val.toStringAsFixed(1), unit: _weightUnit);
      case 'sleep':
        return (
          value: '${_sleepHrsIdx}h ${_sleepMinsIdx.toString().padLeft(2, '0')}m',
          unit: 'rest',
        );
      case 'minutes':
        final total = _actHrsIdx * 60 + _actMinsIdx;
        return (
          value: _actHrsIdx > 0
              ? '${_actHrsIdx}h ${_actMinsIdx.toString().padLeft(2, '0')}m'
              : '$total',
          unit: _actHrsIdx > 0 ? '($total min)' : 'min',
        );
      case 'steps':
        final total = _stepsKIdx * 1000 + _stepsHIdx * 100;
        return (value: NumberFormat('#,###').format(total), unit: 'steps');
      case 'calories':
        return (
          value: NumberFormat('#,###').format((_calIdx + 1) * 25),
          unit: 'kcal',
        );
      case 'waist':
        final val = (40 + _waistWholeIdx) + _waistDecIdx / 10.0;
        return (value: val.toStringAsFixed(1), unit: 'cm');
      case 'water':
        return (
          value: NumberFormat('#,###').format((_waterIdx + 1) * 50),
          unit: 'ml',
        );
      case 'height':
        return (value: '${80 + _heightIdx}', unit: 'cm');
      default:
        return (value: '', unit: '');
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
      case 'steps':
        if (profile.dailyStepsGoal <= 0) return null;
        return 'Goal: ${NumberFormat('#,###').format(profile.dailyStepsGoal)} steps';
      case 'calories':
        if (profile.dailyCaloriesGoal <= 0) return null;
        return 'Goal: ${NumberFormat('#,###').format(profile.dailyCaloriesGoal)} kcal';
      case 'minutes':
        if (profile.dailyMinutesGoal <= 0) return null;
        return 'Goal: ${profile.dailyMinutesGoal} min';
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

  String _formatFriendlyDate(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(dt.year, dt.month, dt.day);
    final diff = today.difference(target).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    return DateFormat('MMM d, yyyy').format(target);
  }

  Future<void> _pickDate() async {
    HapticFeedback.selectionClick();
    final now = DateTime.now();
    final picked = await showTempoMorphCalendar(
      context: context,
      anchorKey: _datePillKey,
      initialDate: _selectedDate.isAfter(now) ? now : _selectedDate,
      firstDate: DateTime(2020),
      lastDate: now,
      accentColor: _meta.color,
      sourceBorderRadius: 20,
    );
    if (picked != null && mounted) {
      setState(() => _selectedDate = picked);
    }
  }

  void _nudgeWeight(double delta) {
    HapticFeedback.selectionClick();
    final minW = _weightUnit == 'lb' ? 44 : 20;
    final maxW = _weightUnit == 'lb' ? 550 : 250;
    final cur = (minW + _weightWholeIdx) + _weightDecIdx / 10.0;
    final next = (cur + delta).clamp(minW.toDouble(), maxW.toDouble());
    final tenthsTotal = (next * 10).round();
    final whole = (tenthsTotal ~/ 10).clamp(minW, maxW);
    final dec = (tenthsTotal % 10).clamp(0, 9);
    setState(() {
      _weightWholeIdx = whole - minW;
      _weightDecIdx = dec;
    });
  }

  void _nudgeWaist(double delta) {
    HapticFeedback.selectionClick();
    final cur = (40 + _waistWholeIdx) + _waistDecIdx / 10.0;
    final next = (cur + delta).clamp(40.0, 200.0);
    final tenthsTotal = (next * 10).round();
    final whole = (tenthsTotal ~/ 10).clamp(40, 200);
    final dec = (tenthsTotal % 10).clamp(0, 9);
    setState(() {
      _waistWholeIdx = whole - 40;
      _waistDecIdx = dec;
    });
  }

  List<_QuickPreset> _presetsForSelectedMetric() {
    switch (_selectedMetric) {
      case 'weight':
        return [
          _QuickPreset(label: '-1.0', onTap: () => _nudgeWeight(-1.0)),
          _QuickPreset(label: '-0.5', onTap: () => _nudgeWeight(-0.5)),
          _QuickPreset(label: '+0.5', onTap: () => _nudgeWeight(0.5)),
          _QuickPreset(label: '+1.0', onTap: () => _nudgeWeight(1.0)),
        ];
      case 'sleep':
        final totalMin = _sleepHrsIdx * 60 + _sleepMinsIdx;
        return [
          for (final p in const [
            (label: '6h', h: 6, m: 0),
            (label: '7h', h: 7, m: 0),
            (label: '7.5h', h: 7, m: 30),
            (label: '8h', h: 8, m: 0),
            (label: '9h', h: 9, m: 0),
          ])
            _QuickPreset(
              label: p.label,
              active: totalMin == p.h * 60 + p.m,
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() {
                  _sleepHrsIdx = p.h;
                  _sleepMinsIdx = p.m;
                });
              },
            ),
        ];
      case 'steps':
        final total = _stepsKIdx * 1000 + _stepsHIdx * 100;
        return [
          for (final p in const [
            (label: '5k', k: 5, h: 0),
            (label: '7.5k', k: 7, h: 5),
            (label: '10k', k: 10, h: 0),
            (label: '12k', k: 12, h: 0),
          ])
            _QuickPreset(
              label: p.label,
              active: total == p.k * 1000 + p.h * 100,
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() {
                  _stepsKIdx = p.k;
                  _stepsHIdx = p.h;
                });
              },
            ),
        ];
      case 'calories':
        final kcal = (_calIdx + 1) * 25;
        return [
          for (final v in const [300, 500, 750, 1000])
            _QuickPreset(
              label: v == 1000 ? '1k' : '$v',
              active: kcal == v,
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => _calIdx = (v ~/ 25) - 1);
              },
            ),
        ];
      case 'minutes':
        final total = _actHrsIdx * 60 + _actMinsIdx;
        return [
          for (final mins in const [15, 30, 45, 60])
            _QuickPreset(
              label: '${mins}m',
              active: total == mins,
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() {
                  _actHrsIdx = mins ~/ 60;
                  _actMinsIdx = mins % 60;
                });
              },
            ),
        ];
      case 'water':
        final ml = (_waterIdx + 1) * 50;
        return [
          for (final v in const [250, 500, 750, 1000])
            _QuickPreset(
              label: v == 1000 ? '1 L' : '$v ml',
              active: ml == v,
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => _waterIdx = (v ~/ 50) - 1);
              },
            ),
        ];
      case 'waist':
        return [
          _QuickPreset(label: '-2.0', onTap: () => _nudgeWaist(-2.0)),
          _QuickPreset(label: '-0.5', onTap: () => _nudgeWaist(-0.5)),
          _QuickPreset(label: '+0.5', onTap: () => _nudgeWaist(0.5)),
          _QuickPreset(label: '+2.0', onTap: () => _nudgeWaist(2.0)),
        ];
      case 'height':
      default:
        return [
          for (final d in const [-2, -1, 1, 2])
            _QuickPreset(
              label: d > 0 ? '+$d cm' : '$d cm',
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() {
                  _heightIdx = (_heightIdx + d).clamp(0, _heightCm.length - 1);
                });
              },
            ),
        ];
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
      final dateKey = DateFormat('yyyy-MM-dd').format(_selectedDate);

      switch (_selectedMetric) {
        case 'steps':
          final steps = _stepsKIdx * 1000 + _stepsHIdx * 100;
          if (steps <= 0) {
            setState(() => _saving = false);
            showTempoToast(
              context,
              'Scroll to select steps above 0',
              isError: true,
            );
            return;
          }
          await db.upsertDailyActivity(
            profileId: profileId,
            dateKey: dateKey,
            steps: steps,
          );
          break;
        case 'calories':
          final kcal = (_calIdx + 1) * 25;
          await db.upsertDailyActivity(
            profileId: profileId,
            dateKey: dateKey,
            calories: kcal,
          );
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
          await db.upsertDailyActivity(
            profileId: profileId,
            dateKey: dateKey,
            minutes: totalMin,
          );
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
      padding: const EdgeInsets.only(top: 22, left: 2, right: 2),
      child: Text(
        symbol,
        style: TextStyle(
          color: c.textPrimary,
          fontSize: 30,
          fontWeight: FontWeight.w700,
          height: 1.0,
        ),
      ),
    );
  }

  Widget _inlineUnit(String unit, AppColors c) {
    return Padding(
      padding: const EdgeInsets.only(top: 24, left: 6),
      child: Text(
        unit,
        style: TextStyle(
          color: c.textSecondary,
          fontSize: 16.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildWheelForSelectedMetric(AppColors c) {
    final accent = _meta.color;
    switch (_selectedMetric) {
      case 'sleep':
        return TempoWheelStage(
          key: const ValueKey('wheel_sleep'),
          accentColor: accent,
          children: [
            TempoWheelColumn(
              key: const ValueKey('sleep_hrs_col'),
              headerLabel: 'HRS',
              items: _hours24,
              initialIndex: _sleepHrsIdx,
              looping: true,
              width: 96,
              offAxisFraction: -0.14,
              onSelectedIndexChanged: (i) => setState(() => _sleepHrsIdx = i),
            ),
            _separatorSymbol(':', c),
            TempoWheelColumn(
              key: const ValueKey('sleep_min_col'),
              headerLabel: 'MIN',
              items: _mins60,
              initialIndex: _sleepMinsIdx,
              looping: true,
              width: 96,
              offAxisFraction: 0.14,
              onSelectedIndexChanged: (i) => setState(() => _sleepMinsIdx = i),
            ),
          ],
        );

      case 'minutes':
        return TempoWheelStage(
          key: const ValueKey('wheel_minutes'),
          accentColor: accent,
          children: [
            TempoWheelColumn(
              key: const ValueKey('act_hrs_col'),
              headerLabel: 'HRS',
              items: _hours10,
              initialIndex: _actHrsIdx,
              looping: false,
              width: 96,
              offAxisFraction: -0.14,
              onSelectedIndexChanged: (i) => setState(() => _actHrsIdx = i),
            ),
            _separatorSymbol(':', c),
            TempoWheelColumn(
              key: const ValueKey('act_min_col'),
              headerLabel: 'MIN',
              items: _mins60,
              initialIndex: _actMinsIdx,
              looping: true,
              width: 96,
              offAxisFraction: 0.14,
              onSelectedIndexChanged: (i) => setState(() => _actMinsIdx = i),
            ),
          ],
        );

      case 'weight':
        final wholeList = _weightUnit == 'lb' ? _lbWhole : _kgWhole;
        return TempoWheelStage(
          key: ValueKey('wheel_weight_$_weightUnit'),
          accentColor: accent,
          children: [
            TempoWheelColumn(
              key: ValueKey('weight_whole_$_weightUnit'),
              headerLabel: _weightUnit.toUpperCase(),
              items: wholeList,
              initialIndex: _weightWholeIdx.clamp(0, wholeList.length - 1),
              width: 102,
              offAxisFraction: -0.14,
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
              offAxisFraction: 0.14,
              onSelectedIndexChanged: (i) => setState(() => _weightDecIdx = i),
            ),
            _inlineUnit(_weightUnit, c),
          ],
        );

      case 'waist':
        return TempoWheelStage(
          key: const ValueKey('wheel_waist'),
          accentColor: accent,
          children: [
            TempoWheelColumn(
              key: const ValueKey('waist_whole'),
              headerLabel: 'CM',
              items: _waistWhole,
              initialIndex: _waistWholeIdx,
              width: 98,
              offAxisFraction: -0.14,
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
              offAxisFraction: 0.14,
              onSelectedIndexChanged: (i) => setState(() => _waistDecIdx = i),
            ),
            _inlineUnit('cm', c),
          ],
        );

      case 'steps':
        return TempoWheelStage(
          key: const ValueKey('wheel_steps'),
          accentColor: accent,
          children: [
            TempoWheelColumn(
              key: const ValueKey('steps_k'),
              headerLabel: 'THOUSANDS',
              items: _stepThousands,
              initialIndex: _stepsKIdx,
              width: 84,
              offAxisFraction: -0.14,
              onSelectedIndexChanged: (i) => setState(() => _stepsKIdx = i),
            ),
            _separatorSymbol(',', c),
            TempoWheelColumn(
              key: const ValueKey('steps_h'),
              headerLabel: 'HUNDREDS',
              items: _stepHundreds,
              initialIndex: _stepsHIdx,
              looping: true,
              width: 104,
              offAxisFraction: 0.14,
              onSelectedIndexChanged: (i) => setState(() => _stepsHIdx = i),
            ),
            _inlineUnit('steps', c),
          ],
        );

      case 'calories':
        return TempoWheelStage(
          key: const ValueKey('wheel_calories'),
          accentColor: accent,
          children: [
            TempoWheelColumn(
              key: const ValueKey('cal_col'),
              headerLabel: 'ENERGY',
              items: _calorieSteps,
              initialIndex: _calIdx,
              width: 142,
              fontSize: 37,
              onSelectedIndexChanged: (i) => setState(() => _calIdx = i),
            ),
            _inlineUnit('kcal', c),
          ],
        );

      case 'water':
        return TempoWheelStage(
          key: const ValueKey('wheel_water'),
          accentColor: accent,
          children: [
            TempoWheelColumn(
              key: const ValueKey('water_col'),
              headerLabel: 'VOLUME',
              items: _waterMlSteps,
              initialIndex: _waterIdx,
              width: 142,
              fontSize: 37,
              onSelectedIndexChanged: (i) => setState(() => _waterIdx = i),
            ),
            _inlineUnit('ml', c),
          ],
        );

      case 'height':
      default:
        return TempoWheelStage(
          key: const ValueKey('wheel_height'),
          accentColor: accent,
          children: [
            TempoWheelColumn(
              key: const ValueKey('height_col'),
              headerLabel: 'HEIGHT',
              items: _heightCm,
              initialIndex: _heightIdx,
              width: 132,
              fontSize: 37,
              onSelectedIndexChanged: (i) => setState(() => _heightIdx = i),
            ),
            _inlineUnit('cm', c),
          ],
        );
    }
  }

  Widget _buildMetricRail(AppColors c) {
    return SizedBox(
      height: 50,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 18),
        itemCount: _metrics.length,
        separatorBuilder: (_, __) => const SizedBox(width: 9),
        itemBuilder: (_, idx) {
          final m = _metrics[idx];
          final selected = m.key == _selectedMetric;
          return GestureDetector(
            key: _metricChipKeys[m.key],
            behavior: HitTestBehavior.opaque,
            onTap: () {
              if (selected) return;
              HapticFeedback.selectionClick();
              setState(() => _selectedMetric = m.key);
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _scrollSelectedMetricIntoView();
              });
            },
            child: Center(
              child: TempoTouchLightEffect(
                borderRadius: 999,
                isAccentSurface: selected,
                intensity: 0.94,
                scatterGain: 1.08,
                child: CustomPaint(
                  foregroundPainter: LiquidGlassRimPainter(
                    borderRadius: 999,
                    isDark: c.isDark,
                    intensity: selected ? 1.18 : 0.72,
                    strokeWidth: selected ? 1.15 : 0.9,
                    showTopMeniscus: false,
                    tintColor: selected ? m.color : null,
                  ),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOutCubic,
                    padding: const EdgeInsets.fromLTRB(7, 7, 14, 7),
                    decoration: BoxDecoration(
                      color: selected
                          ? m.color.withValues(alpha: c.isDark ? 0.25 : 0.14)
                          : (c.isDark
                              ? const Color(0xFF1A1B20).withValues(alpha: 0.76)
                              : Colors.white.withValues(alpha: 0.84)),
                      borderRadius: BorderRadius.circular(999),
                      boxShadow: [
                        BoxShadow(
                          color: selected
                              ? m.color.withValues(alpha: c.isDark ? 0.26 : 0.16)
                              : Colors.black.withValues(
                                  alpha: c.isDark ? 0.22 : 0.045,
                                ),
                          blurRadius: selected ? 14 : 9,
                          offset: const Offset(0, 4),
                        ),
                      ],
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
                            size: 13.5,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          m.label,
                          style: TextStyle(
                            color: c.textPrimary,
                            fontWeight:
                                selected ? FontWeight.w700 : FontWeight.w500,
                            fontSize: 13.8,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildQuickPresetsRow(AppColors c, _MetricMeta meta) {
    final presets = _presetsForSelectedMetric();
    if (presets.isEmpty) return const SizedBox.shrink();

    return Row(
      children: [
        for (int i = 0; i < presets.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: presets[i].onTap,
              child: TempoTouchLightEffect(
                borderRadius: 999,
                isAccentSurface: presets[i].active,
                intensity: 0.92,
                scatterGain: 1.06,
                child: CustomPaint(
                  foregroundPainter: LiquidGlassRimPainter(
                    borderRadius: 999,
                    isDark: c.isDark,
                    intensity: presets[i].active ? 1.12 : 0.62,
                    strokeWidth: 0.85,
                    showTopMeniscus: false,
                    tintColor: presets[i].active ? meta.color : null,
                  ),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    curve: Curves.easeOutCubic,
                    height: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: presets[i].active
                          ? meta.color.withValues(alpha: c.isDark ? 0.24 : 0.14)
                          : (c.isDark
                              ? Colors.white.withValues(alpha: 0.065)
                              : Colors.black.withValues(alpha: 0.042)),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      presets[i].label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color:
                            presets[i].active ? meta.color : c.textSecondary,
                        fontSize: 12.6,
                        fontWeight: presets[i].active
                            ? FontWeight.w700
                            : FontWeight.w600,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final profile = context.watch<ActiveProfileProvider>().activeProfile;
    final meta = _meta;
    final currentSummary = _currentProfileSummary(profile);
    final hero = _currentHeroParts();

    return Scaffold(
      backgroundColor: c.scaffold,
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 14),
          child: TempoBouncyButton(
            height: 54,
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

          // Horizontal snapping Liquid Glass metric pill rail
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 10),
              child: _buildMetricRail(c),
            ),
          ),

          SliverPadding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 20),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                // Sculpted Liquid Glass 3D Wheel Deck
                LiquidGlassSurface(
                  borderRadius: 28,
                  padding: const EdgeInsets.fromLTRB(16, 15, 16, 15),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Hero Metric Header + Live Tabular Value Readout
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: meta.color,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: meta.color.withValues(alpha: 0.30),
                                  blurRadius: 10,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: Icon(
                              meta.icon,
                              color: Colors.white,
                              size: 18,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      meta.label,
                                      style: TextStyle(
                                        color: c.textPrimary,
                                        fontSize: 17,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: -0.3,
                                      ),
                                    ),
                                    if (_selectedMetric == 'weight') ...[
                                      const SizedBox(width: 8),
                                      GestureDetector(
                                        behavior: HitTestBehavior.opaque,
                                        onTap: _toggleWeightUnit,
                                        child: TempoTouchLightEffect(
                                          borderRadius: 999,
                                          intensity: 0.85,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 3,
                                            ),
                                            decoration: BoxDecoration(
                                              color: c.isDark
                                                  ? Colors.white
                                                      .withValues(alpha: 0.09)
                                                  : Colors.black
                                                      .withValues(alpha: 0.055),
                                              borderRadius:
                                                  BorderRadius.circular(999),
                                            ),
                                            child: Text(
                                              _weightUnit.toUpperCase(),
                                              style: TextStyle(
                                                color: c.textSecondary,
                                                fontSize: 11,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                if (currentSummary != null)
                                  Text(
                                    currentSummary,
                                    style: TextStyle(
                                      color: c.textTertiary,
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w500,
                                      fontFeatures: const [
                                        FontFeature.tabularFigures(),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                hero.value,
                                style: TextStyle(
                                  color: c.textPrimary,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.6,
                                  height: 1.05,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                              Text(
                                hero.unit,
                                style: TextStyle(
                                  color: meta.color,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),

                      const SizedBox(height: 12),

                      // True 3D Cylindrical Drum Wheel with BitChord Glass Lens
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeInCubic,
                        transitionBuilder: (child, anim) => FadeTransition(
                          opacity: anim,
                          child: ScaleTransition(
                            scale: Tween<double>(begin: 0.96, end: 1.0)
                                .animate(anim),
                            child: child,
                          ),
                        ),
                        child: _buildWheelForSelectedMetric(c),
                      ),

                      const SizedBox(height: 14),

                      // Contextual Quick-Adjust Glass Preset Chips
                      _buildQuickPresetsRow(c, meta),
                    ],
                  ),
                ),

                const SizedBox(height: 14),

                // Unified Liquid Glass Morphing Date Pill (enabled for all 8 metrics!)
                ValueListenableBuilder<Key?>(
                  valueListenable: activeTempoCalendarAnchorKey,
                  builder: (_, activeKey, child) {
                    final hidden = identical(activeKey, _datePillKey);
                    return Visibility(
                      visible: !hidden,
                      maintainSize: true,
                      maintainAnimation: true,
                      maintainState: true,
                      child: child!,
                    );
                  },
                  child: TempoLiquidButton(
                    key: _datePillKey,
                    primary: false,
                    borderRadius: 20,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    onPressed: _pickDate,
                    child: Row(
                      children: [
                        Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            color: meta.color
                                .withValues(alpha: c.isDark ? 0.22 : 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            CupertinoIcons.calendar,
                            size: 16,
                            color: meta.color,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'Date',
                          style: TextStyle(
                            color: c.textSecondary,
                            fontSize: 14.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          _formatFriendlyDate(_selectedDate),
                          style: TextStyle(
                            color: c.textPrimary,
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                        const SizedBox(width: 6),
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
            ),
            ),
          ),
        ],
      ),
    );
  }
}
