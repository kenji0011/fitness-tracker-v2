import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/local_profile.dart';
import '../services/active_profile_provider.dart';
import '../services/tempo_rust_db.dart';
import '../theme/app_colors.dart';
import '../widgets/ios_popover_menu.dart';
import '../widgets/ios_stretch_sheet.dart';
import '../widgets/liquid_glass_surface.dart';
import '../widgets/tempo_sliver_header.dart';
import '../widgets/tempo_toast.dart';
import 'history_calendar_screen.dart';

enum TempoMetricKind {
  waist,
  calories,
  steps,
  minutes,
  burn,
}

class _MetricPoint {
  final DateTime date;
  final double value;

  const _MetricPoint({required this.date, required this.value});
}

/// Unified Weight/Sleep-grade detail page for Waist, Calories, Steps,
/// Activity Minutes, and 7-Day Burn — featuring History Calendar, sliding
/// Latest | Week | M | Y tabs, iOS spring popover, editable daily goal,
/// animated trend chart, Data source, and Add data.
class MetricDetailScreen extends StatefulWidget {
  final TempoMetricKind kind;

  const MetricDetailScreen({super.key, required this.kind});

  @override
  State<MetricDetailScreen> createState() => _MetricDetailScreenState();
}

class _MetricDetailScreenState extends State<MetricDetailScreen> {
  static const List<String> _tabs = ['Latest', 'Week', 'M', 'Y'];

  final TempoRustDb _db = TempoRustDb.instance;
  final GlobalKey _moreButtonKey = GlobalKey();

  int _selectedTab = 0; // 0 = Latest, 1 = Week, 2 = M, 3 = Y
  DateTime _anchorDate = DateTime.now();
  List<_MetricPoint> _allPoints = [];
  double? _customWaistTargetCm;
  bool _loading = true;

  String get _title {
    switch (widget.kind) {
      case TempoMetricKind.waist:
        return 'Waist';
      case TempoMetricKind.calories:
        return 'Calories';
      case TempoMetricKind.steps:
        return 'Steps';
      case TempoMetricKind.minutes:
        return 'Activity';
      case TempoMetricKind.burn:
        return '7-Day Burn';
    }
  }

  String get _cardTitle {
    switch (widget.kind) {
      case TempoMetricKind.waist:
        return 'Waist measurement';
      case TempoMetricKind.calories:
        return 'Active calories';
      case TempoMetricKind.steps:
        return 'Daily steps';
      case TempoMetricKind.minutes:
        return 'Activity minutes';
      case TempoMetricKind.burn:
        return 'Energy burn';
    }
  }

  String get _unit {
    switch (widget.kind) {
      case TempoMetricKind.waist:
        return 'cm';
      case TempoMetricKind.calories:
      case TempoMetricKind.burn:
        return 'kcal';
      case TempoMetricKind.steps:
        return 'steps';
      case TempoMetricKind.minutes:
        return 'min';
    }
  }

  Color get _badgeColor {
    switch (widget.kind) {
      case TempoMetricKind.waist:
        return const Color(0xFF3CC29E);
      case TempoMetricKind.calories:
        return const Color(0xFFF36432);
      case TempoMetricKind.steps:
        return const Color(0xFF93DC2A);
      case TempoMetricKind.minutes:
        return const Color(0xFF56B7FF);
      case TempoMetricKind.burn:
        return const Color(0xFFF39C2E);
    }
  }

  IconData get _badgeIcon {
    switch (widget.kind) {
      case TempoMetricKind.waist:
        return CupertinoIcons.resize_h;
      case TempoMetricKind.calories:
        return CupertinoIcons.flame_fill;
      case TempoMetricKind.steps:
        return CupertinoIcons.hare_fill;
      case TempoMetricKind.minutes:
        return CupertinoIcons.clock_fill;
      case TempoMetricKind.burn:
        return CupertinoIcons.bolt_fill;
    }
  }

  bool get _isInteger => widget.kind != TempoMetricKind.waist;

  double get _stepSize {
    switch (widget.kind) {
      case TempoMetricKind.waist:
        return 0.5;
      case TempoMetricKind.calories:
      case TempoMetricKind.burn:
        return 50;
      case TempoMetricKind.steps:
        return 500;
      case TempoMetricKind.minutes:
        return 5;
    }
  }

  double get _minVal => widget.kind == TempoMetricKind.waist ? 40 : 1;
  double get _maxVal {
    switch (widget.kind) {
      case TempoMetricKind.waist:
        return 200;
      case TempoMetricKind.calories:
      case TempoMetricKind.burn:
        return 10000;
      case TempoMetricKind.steps:
        return 100000;
      case TempoMetricKind.minutes:
        return 600;
    }
  }

  String _aboutCopy() {
    switch (widget.kind) {
      case TempoMetricKind.waist:
        return 'Waist circumference tracks core composition over time independently of scale fluctuations. Measure around the narrowest part of your midsection at the same time of day.';
      case TempoMetricKind.calories:
      case TempoMetricKind.burn:
        return 'Active calories measure energy burned through workouts and daily movement. Customize your daily target anytime to match your current training block.';
      case TempoMetricKind.steps:
        return 'Steps track daily walking activity using your phone\'s motion sensor offline. Aiming for 7,000–10,000 steps per day supports cardiovascular health and recovery.';
      case TempoMetricKind.minutes:
        return 'Activity minutes record moderate-to-vigorous training time. Most adults benefit from 30–60 active minutes per day or at least 150 minutes per week.';
    }
  }

  @override
  void initState() {
    super.initState();
    if (widget.kind == TempoMetricKind.burn) {
      _selectedTab = 1; // Default to Week view for 7-Day Burn
    }
    _load();
  }

  Future<void> _load() async {
    final pid = context.read<ActiveProfileProvider>().activeProfileId;
    if (pid == null) return;
    setState(() => _loading = true);

    if (widget.kind == TempoMetricKind.waist) {
      final results = await Future.wait([
        _db.getBodyMetricHistory(pid, 'waist', limit: 365),
        _db.getSetting('waist_target_cm_$pid'),
      ]);
      if (!mounted) return;
      final pts = (results[0] as List<BodyMetricPoint>)
        ..sort((a, b) => a.recordedAt.compareTo(b.recordedAt));
      setState(() {
        _allPoints = pts
            .map((p) => _MetricPoint(date: p.recordedAt.toLocal(), value: p.value))
            .toList();
        _customWaistTargetCm = double.tryParse((results[1] as String?) ?? '');
        _loading = false;
      });
    } else {
      final list = await _db.getDailyActivityHistory(pid, limit: 365);
      if (!mounted) return;
      list.sort((a, b) => a.dateKey.compareTo(b.dateKey));
      final mapped = <_MetricPoint>[];
      for (final d in list) {
        final v = switch (widget.kind) {
          TempoMetricKind.steps => d.steps.toDouble(),
          TempoMetricKind.minutes => d.minutes.toDouble(),
          TempoMetricKind.calories || TempoMetricKind.burn => d.calories.toDouble(),
          TempoMetricKind.waist => 0.0,
        };
        if (v > 0) {
          mapped.add(_MetricPoint(date: d.date, value: v));
        }
      }
      setState(() {
        _allPoints = mapped;
        _loading = false;
      });
    }
  }

  DateTime get _anchorEnd => DateTime(
        _anchorDate.year,
        _anchorDate.month,
        _anchorDate.day,
        23,
        59,
        59,
      );

  List<_MetricPoint> get _pointsUpToAnchor =>
      _allPoints.where((p) => !p.date.isAfter(_anchorEnd)).toList();

  List<_MetricPoint> get _windowPoints {
    final upTo = _pointsUpToAnchor;
    if (_selectedTab == 0) return upTo;
    final days = _selectedTab == 1 ? 7 : (_selectedTab == 2 ? 30 : 365);
    final start = DateTime(
      _anchorDate.year,
      _anchorDate.month,
      _anchorDate.day,
    ).subtract(Duration(days: days - 1));
    return upTo.where((p) => !p.date.isBefore(start)).toList();
  }

  double _currentValue(LocalProfile? profile) {
    final upTo = _pointsUpToAnchor;
    if (upTo.isNotEmpty) return upTo.last.value;
    if (widget.kind == TempoMetricKind.waist) return profile?.waistCm ?? 0;
    return 0;
  }

  double _goalValue(LocalProfile? profile) {
    switch (widget.kind) {
      case TempoMetricKind.waist:
        return (_customWaistTargetCm != null && _customWaistTargetCm! > 0)
            ? _customWaistTargetCm!
            : 80.0;
      case TempoMetricKind.calories:
      case TempoMetricKind.burn:
        return (profile?.dailyCaloriesGoal ?? 600).toDouble();
      case TempoMetricKind.steps:
        return (profile?.dailyStepsGoal ?? 10000).toDouble();
      case TempoMetricKind.minutes:
        return (profile?.dailyMinutesGoal ?? 60).toDouble();
    }
  }

  String _formatVal(double v) {
    if (_isInteger) return NumberFormat('#,###').format(v.round());
    return v.toStringAsFixed(1);
  }

  Future<void> _pickAnchorDate() async {
    HapticFeedback.selectionClick();
    final recordedKeys = _allPoints
        .map((p) => DateFormat('yyyy-MM-dd').format(p.date))
        .toSet();
    final result = await Navigator.push<HistoryCalendarSelection>(
      context,
      MaterialPageRoute(
        builder: (_) => HistoryCalendarScreen(
          initialDate: _anchorDate,
          initialModeIndex: _selectedTab,
          recordedDateKeys: recordedKeys,
        ),
      ),
    );
    if (result != null && mounted) {
      setState(() {
        _anchorDate = result.date;
        _selectedTab = result.modeIndex;
      });
    }
  }

  Future<void> _openAddSheet() async {
    final profileProvider = context.read<ActiveProfileProvider>();
    final pid = profileProvider.activeProfileId;
    final profile = profileProvider.activeProfile;
    if (pid == null) return;

    double initVal = _currentValue(profile);
    if (initVal <= 0) {
      initVal = switch (widget.kind) {
        TempoMetricKind.waist => 78.0,
        TempoMetricKind.calories || TempoMetricKind.burn => 350.0,
        TempoMetricKind.steps => 5000.0,
        TempoMetricKind.minutes => 30.0,
      };
    }

    final ctrl = TextEditingController(
      text: _isInteger ? initVal.round().toString() : initVal.toStringAsFixed(1),
    );
    DateTime selectedDate = _anchorDate;

    final saved = await showTempoSheet<bool>(
      context: context,
      backgroundColor: AppColors.of(context, listen: false).card,
      borderRadius: 28,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          final mc = AppColors.of(ctx);
          void adjust(double delta) {
            HapticFeedback.selectionClick();
            final cur = double.tryParse(ctrl.text.trim()) ?? initVal;
            final next = (cur + delta).clamp(_minVal, _maxVal);
            ctrl.text =
                _isInteger ? next.round().toString() : next.toStringAsFixed(1);
            setModalState(() {});
          }

          return Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              12,
              20,
              MediaQuery.viewInsetsOf(ctx).bottom + 24,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Add ${_title.toLowerCase()}',
                  style: TextStyle(
                    color: mc.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    _MetricStepperCircle(
                      icon: CupertinoIcons.minus,
                      onTap: () => adjust(-_stepSize),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: ctrl,
                        textAlign: TextAlign.center,
                        keyboardType: TextInputType.numberWithOptions(
                          decimal: !_isInteger,
                        ),
                        style: TextStyle(
                          color: mc.textPrimary,
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                        decoration: InputDecoration(
                          suffixText: _unit,
                          suffixStyle: TextStyle(
                            color: mc.textSecondary,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                          filled: true,
                          fillColor: mc.searchBg,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    _MetricStepperCircle(
                      icon: CupertinoIcons.add,
                      onTap: () => adjust(_stepSize),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                GestureDetector(
                  onTap: () async {
                    final now = DateTime.now();
                    final d = await showDatePicker(
                      context: ctx,
                      initialDate:
                          selectedDate.isAfter(now) ? now : selectedDate,
                      firstDate: DateTime(2020),
                      lastDate: now,
                    );
                    if (d != null) setModalState(() => selectedDate = d);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: mc.searchBg,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          CupertinoIcons.calendar,
                          size: 18,
                          color: mc.textSecondary,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'Date',
                          style: TextStyle(
                            color: mc.textSecondary,
                            fontSize: 14.5,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          DateFormat('MM/dd/yyyy').format(selectedDate),
                          style: TextStyle(
                            color: mc.textPrimary,
                            fontSize: 14.5,
                            fontWeight: FontWeight.w600,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  height: 50,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: mc.accent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    onPressed: () async {
                      final val = double.tryParse(ctrl.text.trim());
                      if (val == null || val < _minVal || val > _maxVal) return;
                      final now = DateTime.now();
                      final recorded = DateTime(
                        selectedDate.year,
                        selectedDate.month,
                        selectedDate.day,
                        now.hour,
                        now.minute,
                      );
                      final dateKey =
                          DateFormat('yyyy-MM-dd').format(selectedDate);
                      if (widget.kind == TempoMetricKind.waist) {
                        await _db.logBodyMetric(
                          profileId: pid,
                          metricType: 'waist',
                          value: val,
                          recordedAt: recorded,
                        );
                      } else if (widget.kind == TempoMetricKind.steps) {
                        await _db.upsertDailyActivity(
                          profileId: pid,
                          dateKey: dateKey,
                          steps: val.round(),
                        );
                      } else if (widget.kind == TempoMetricKind.minutes) {
                        await _db.upsertDailyActivity(
                          profileId: pid,
                          dateKey: dateKey,
                          minutes: val.round(),
                        );
                      } else {
                        await _db.upsertDailyActivity(
                          profileId: pid,
                          dateKey: dateKey,
                          calories: val.round(),
                        );
                      }
                      if (ctx.mounted) Navigator.of(ctx).pop(true);
                    },
                    child: Text(
                      'Save ${_title.toLowerCase()}',
                      style: const TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );

    ctrl.dispose();
    if (saved == true && mounted) {
      await profileProvider.refreshProfiles();
      await _load();
      if (mounted) showTempoToast(context, '$_title saved');
    }
  }

  Future<void> _openGoalSheet() async {
    final profileProvider = context.read<ActiveProfileProvider>();
    final pid = profileProvider.activeProfileId;
    final profile = profileProvider.activeProfile;
    if (pid == null) return;

    final currentGoal = _goalValue(profile);
    final ctrl = TextEditingController(
      text: _isInteger
          ? currentGoal.round().toString()
          : currentGoal.toStringAsFixed(1),
    );

    final savedVal = await showTempoSheet<double>(
      context: context,
      backgroundColor: AppColors.of(context, listen: false).card,
      borderRadius: 28,
      showDragHandle: true,
      builder: (ctx) {
        final mc = AppColors.of(ctx);
        return Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            12,
            20,
            MediaQuery.viewInsetsOf(ctx).bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.kind == TempoMetricKind.waist
                    ? 'Target waist'
                    : 'Daily ${_title.toLowerCase()} goal',
                style: TextStyle(
                  color: mc.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: ctrl,
                textAlign: TextAlign.center,
                keyboardType:
                    TextInputType.numberWithOptions(decimal: !_isInteger),
                style: TextStyle(
                  color: mc.textPrimary,
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
                decoration: InputDecoration(
                  suffixText: _unit,
                  filled: true,
                  fillColor: mc.searchBg,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                height: 50,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: mc.accent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  onPressed: () {
                    final parsed = double.tryParse(ctrl.text.trim());
                    if (parsed == null || parsed <= 0) return;
                    Navigator.of(ctx).pop(parsed);
                  },
                  child: const Text(
                    'Save goal',
                    style: TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );

    ctrl.dispose();
    if (savedVal != null && mounted) {
      if (widget.kind == TempoMetricKind.waist) {
        await _db.setSetting('waist_target_cm_$pid', savedVal.toStringAsFixed(1));
        if (!mounted) return;
        setState(() => _customWaistTargetCm = savedVal);
      } else if (widget.kind == TempoMetricKind.steps) {
        await profileProvider.updateActiveProfile(
          dailyStepsGoal: savedVal.round(),
        );
      } else if (widget.kind == TempoMetricKind.minutes) {
        await profileProvider.updateActiveProfile(
          dailyMinutesGoal: savedVal.round(),
        );
      } else {
        await profileProvider.updateActiveProfile(
          dailyCaloriesGoal: savedVal.round(),
        );
      }
      if (mounted) showTempoToast(context, 'Goal updated');
    }
  }

  void _openAboutSheet() {
    HapticFeedback.selectionClick();
    showTempoSheet<void>(
      context: context,
      backgroundColor: AppColors.of(context, listen: false).card,
      borderRadius: 28,
      showDragHandle: true,
      builder: (ctx) {
        final mc = AppColors.of(ctx);
        return Padding(
          padding: EdgeInsets.fromLTRB(
            22,
            10,
            22,
            MediaQuery.paddingOf(ctx).bottom + 22,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'About $_title',
                style: TextStyle(
                  color: mc.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                _aboutCopy(),
                style: TextStyle(
                  color: mc.textSecondary,
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                height: 50,
                child: TextButton(
                  style: TextButton.styleFrom(
                    backgroundColor: mc.searchBg,
                    foregroundColor: mc.textPrimary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text(
                    'Close',
                    style: TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _openDataSourceSheet({String title = 'Data source'}) {
    HapticFeedback.selectionClick();
    final history = _allPoints.reversed.toList();
    showTempoSheet<void>(
      context: context,
      backgroundColor: AppColors.of(context, listen: false).card,
      borderRadius: 28,
      showDragHandle: true,
      builder: (ctx) {
        final mc = AppColors.of(ctx);
        final sheetH = MediaQuery.sizeOf(ctx).height * 0.62;
        return SizedBox(
          height: sheetH,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
                child: Row(
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: mc.textPrimary,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      'Local on-device',
                      style: TextStyle(
                        color: mc.textSecondary,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: mc.divider),
              Expanded(
                child: history.isEmpty
                    ? Center(
                        child: Text(
                          'No records yet. Tap Add data to log one.',
                          style: TextStyle(
                            color: mc.textSecondary,
                            fontSize: 14,
                          ),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(20),
                        itemCount: history.length,
                        separatorBuilder: (_, __) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          child: Divider(height: 1, color: mc.divider),
                        ),
                        itemBuilder: (_, i) {
                          final pt = history[i];
                          return Row(
                            children: [
                              Expanded(
                                child: Text(
                                  DateFormat('MM/dd/yyyy').format(pt.date),
                                  style: TextStyle(
                                    color: mc.textPrimary,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),
                              ),
                              Text(
                                '${_formatVal(pt.value)} $_unit',
                                style: TextStyle(
                                  color: mc.textPrimary,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                            ],
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _openMoreMenu() {
    HapticFeedback.selectionClick();
    showTempoPopoverMenu(
      context: context,
      anchorKey: _moreButtonKey,
      actions: [
        TempoPopoverAction(
          label: 'All data',
          onTap: () => _openDataSourceSheet(title: 'All data'),
        ),
        TempoPopoverAction(
          label: 'Add data',
          onTap: _openAddSheet,
        ),
        TempoPopoverAction(
          label: 'Daily goal',
          onTap: _openGoalSheet,
        ),
        TempoPopoverAction(
          label: 'About',
          onTap: _openAboutSheet,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final profile = context.watch<ActiveProfileProvider>().activeProfile;
    final upTo = _pointsUpToAnchor;
    final windowPts = _windowPoints;
    final currentVal = _currentValue(profile);
    final goalVal = _goalValue(profile);
    final latestDate = upTo.isNotEmpty ? upTo.last.date : null;
    final avgVal = windowPts.isNotEmpty
        ? windowPts.fold<double>(0, (s, p) => s + p.value) / windowPts.length
        : 0.0;
    final goalPct = (currentVal > 0 && goalVal > 0)
        ? ((currentVal / goalVal) * 100).round().clamp(0, 999)
        : 0;

    return Scaffold(
      backgroundColor: c.scaffold,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // Top bar matching Weight & Sleep
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
              child: Row(
                children: [
                  TempoGlassCircleButton(
                    glassOpacity: 0.0,
                    icon: TempoBackChevron(color: c.textPrimary, size: 22),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _title,
                          style: TextStyle(
                            color: c.textPrimary,
                            fontSize: 19,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(height: 1),
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: _pickAnchorDate,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                DateFormat('MM/dd/yyyy').format(_anchorDate),
                                style: TextStyle(
                                  color: c.textSecondary,
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w500,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 3),
                              Icon(
                                Icons.arrow_drop_down_rounded,
                                size: 18,
                                color: c.textSecondary,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  TempoGlassCircleButton(
                    key: _moreButtonKey,
                    glassOpacity: 0.0,
                    icon: Icon(
                      CupertinoIcons.ellipsis_vertical,
                      size: 20,
                      color: c.textPrimary,
                    ),
                    onPressed: _openMoreMenu,
                  ),
                ],
              ),
            ),

            // 4-Segment Sliding Timeframe Pill (Latest | Week | M | Y)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 2, 18, 16),
              child: _MetricSegmentBar(
                tabs: _tabs,
                selectedIndex: _selectedTab,
                onChanged: (idx) {
                  HapticFeedback.selectionClick();
                  setState(() => _selectedTab = idx);
                },
              ),
            ),

            Expanded(
              child: _loading
                  ? Center(child: CupertinoActivityIndicator(color: c.accent))
                  : RefreshIndicator(
                      color: _badgeColor,
                      onRefresh: _load,
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(18, 0, 18, 40),
                        children: [
                          // Card 1: Primary Metric + Animated Trend Graph
                          AppleCard(
                            borderRadius: 24,
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      width: 32,
                                      height: 32,
                                      decoration: BoxDecoration(
                                        color: _badgeColor,
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(
                                        _badgeIcon,
                                        color: Colors.white,
                                        size: 17,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Text(
                                      _cardTitle,
                                      style: TextStyle(
                                        color: c.textPrimary,
                                        fontSize: 16.5,
                                        fontWeight: FontWeight.w600,
                                        letterSpacing: -0.2,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 22),
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.baseline,
                                            textBaseline:
                                                TextBaseline.alphabetic,
                                            children: [
                                              Flexible(
                                                child: TweenAnimationBuilder<
                                                    double>(
                                                  tween: Tween<double>(
                                                    begin: 0,
                                                    end: currentVal,
                                                  ),
                                                  duration: const Duration(
                                                    milliseconds: 420,
                                                  ),
                                                  curve: Curves.easeOutCubic,
                                                  builder: (_, v, __) => Text(
                                                    currentVal > 0
                                                        ? _formatVal(v)
                                                        : '--',
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: TextStyle(
                                                      color: c.textPrimary,
                                                      fontSize: 32,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      letterSpacing: -1.0,
                                                      fontFeatures: const [
                                                        FontFeature
                                                            .tabularFigures(),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                _unit,
                                                style: TextStyle(
                                                  color: c.textPrimary,
                                                  fontSize: 15,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            latestDate != null
                                                ? DateFormat('MM/dd/yyyy')
                                                    .format(latestDate)
                                                : 'No entries yet',
                                            style: TextStyle(
                                              color: c.textTertiary,
                                              fontSize: 13,
                                              fontFeatures: const [
                                                FontFeature.tabularFigures(),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const SizedBox(height: 5),
                                          Text(
                                            avgVal > 0
                                                ? '${_formatVal(avgVal)} $_unit'
                                                : '-- $_unit',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: c.textPrimary,
                                              fontSize: 21,
                                              fontWeight: FontWeight.w600,
                                              letterSpacing: -0.4,
                                              fontFeatures: const [
                                                FontFeature.tabularFigures(),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            _selectedTab == 0
                                                ? 'Overall average'
                                                : '${_tabs[_selectedTab]} average',
                                            style: TextStyle(
                                              color: c.textTertiary,
                                              fontSize: 13,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                AnimatedSize(
                                  duration: const Duration(milliseconds: 280),
                                  curve: Curves.easeOutCubic,
                                  child: _selectedTab == 0
                                      ? const SizedBox.shrink()
                                      : Padding(
                                          padding:
                                              const EdgeInsets.only(top: 22),
                                          child: _MetricTrendChart(
                                            points: windowPts,
                                            lineColor: _badgeColor,
                                            unit: _unit,
                                            isInteger: _isInteger,
                                            goalLine: goalVal > 0
                                                ? goalVal
                                                : null,
                                          ),
                                        ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),

                          // Card 2: Daily Target / Goal (tappable to edit!)
                          AppleCard(
                            borderRadius: 24,
                            padding: const EdgeInsets.all(20),
                            onTap: _openGoalSheet,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      width: 32,
                                      height: 32,
                                      decoration: BoxDecoration(
                                        color: _badgeColor,
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        CupertinoIcons.scope,
                                        color: Colors.white,
                                        size: 17,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Text(
                                      widget.kind == TempoMetricKind.waist
                                          ? 'Target goal'
                                          : 'Daily target',
                                      style: TextStyle(
                                        color: c.textPrimary,
                                        fontSize: 16.5,
                                        fontWeight: FontWeight.w600,
                                        letterSpacing: -0.2,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                Divider(height: 1, color: c.divider),
                                const SizedBox(height: 16),
                                Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '${_formatVal(goalVal)} $_unit',
                                            style: TextStyle(
                                              color: c.textPrimary,
                                              fontSize: 21,
                                              fontWeight: FontWeight.w600,
                                              fontFeatures: const [
                                                FontFeature.tabularFigures(),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            'Tap to edit goal',
                                            style: TextStyle(
                                              color: c.textTertiary,
                                              fontSize: 12.5,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Container(
                                      width: 1,
                                      height: 36,
                                      margin: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                      ),
                                      color: c.divider,
                                    ),
                                    Expanded(
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  currentVal > 0
                                                      ? '$goalPct%'
                                                      : '--',
                                                  style: TextStyle(
                                                    color: c.textPrimary,
                                                    fontSize: 21,
                                                    fontWeight: FontWeight.w600,
                                                    fontFeatures: const [
                                                      FontFeature
                                                          .tabularFigures(),
                                                    ],
                                                  ),
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  'Of target',
                                                  style: TextStyle(
                                                    color: c.textTertiary,
                                                    fontSize: 12.5,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          Icon(
                                            CupertinoIcons.chevron_right,
                                            size: 16,
                                            color: c.textTertiary,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),

                          // Card 3: Data source + Add data
                          AppleCard(
                            borderRadius: 24,
                            padding: EdgeInsets.zero,
                            child: Column(
                              children: [
                                InkWell(
                                  borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(24),
                                  ),
                                  onTap: _openDataSourceSheet,
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 20,
                                      vertical: 17,
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 32,
                                          height: 32,
                                          decoration: BoxDecoration(
                                            color: _badgeColor,
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Icon(
                                            Icons.workspaces_rounded,
                                            color: Colors.white,
                                            size: 17,
                                          ),
                                        ),
                                        const SizedBox(width: 14),
                                        Expanded(
                                          child: Text(
                                            'Data source',
                                            style: TextStyle(
                                              color: c.textPrimary,
                                              fontSize: 16,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ),
                                        if (_allPoints.isNotEmpty)
                                          Text(
                                            '${_allPoints.length}',
                                            style: TextStyle(
                                              color: c.textTertiary,
                                              fontSize: 13.5,
                                              fontFeatures: const [
                                                FontFeature.tabularFigures(),
                                              ],
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 20,
                                  ),
                                  child: Divider(height: 1, color: c.divider),
                                ),
                                InkWell(
                                  borderRadius: const BorderRadius.vertical(
                                    bottom: Radius.circular(24),
                                  ),
                                  onTap: _openAddSheet,
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 20,
                                      vertical: 17,
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 32,
                                          height: 32,
                                          decoration: BoxDecoration(
                                            color: c.isDark
                                                ? const Color(0xFF0A0A0C)
                                                : const Color(0xFF1C1C1E),
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Icon(
                                            Icons.edit_rounded,
                                            color: Colors.white,
                                            size: 16,
                                          ),
                                        ),
                                        const SizedBox(width: 14),
                                        Expanded(
                                          child: Text(
                                            'Add data',
                                            style: TextStyle(
                                              color: c.textPrimary,
                                              fontSize: 16,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricSegmentBar extends StatelessWidget {
  final List<String> tabs;
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  const _MetricSegmentBar({
    required this.tabs,
    required this.selectedIndex,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Container(
      height: 42,
      padding: const EdgeInsets.all(3.5),
      decoration: BoxDecoration(
        color: c.isDark
            ? const Color(0xFF1C1C1E)
            : Colors.black.withValues(alpha: 0.055),
        borderRadius: BorderRadius.circular(14),
      ),
      child: LayoutBuilder(
        builder: (_, constraints) {
          final segW = constraints.maxWidth / tabs.length;
          return Stack(
            children: [
              AnimatedPositioned(
                duration: const Duration(milliseconds: 240),
                curve: Curves.easeOutCubic,
                left: selectedIndex * segW,
                top: 0,
                bottom: 0,
                width: segW,
                child: Container(
                  decoration: BoxDecoration(
                    color: c.isDark ? const Color(0xFF323338) : c.card,
                    borderRadius: BorderRadius.circular(11),
                    boxShadow: c.isDark
                        ? null
                        : [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.06),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                  ),
                ),
              ),
              Row(
                children: List.generate(tabs.length, (i) {
                  final sel = i == selectedIndex;
                  return Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => onChanged(i),
                      child: Center(
                        child: Text(
                          tabs[i],
                          style: TextStyle(
                            color: sel ? c.textPrimary : c.textSecondary,
                            fontSize: 13.5,
                            fontWeight: sel ? FontWeight.w600 : FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _MetricTrendChart extends StatelessWidget {
  final List<_MetricPoint> points;
  final Color lineColor;
  final String unit;
  final bool isInteger;
  final double? goalLine;

  const _MetricTrendChart({
    required this.points,
    required this.lineColor,
    required this.unit,
    required this.isInteger,
    this.goalLine,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    if (points.length < 2) {
      return Container(
        height: 132,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: c.searchBg.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          points.isEmpty
              ? 'No entries in this timeframe'
              : 'Add one more entry in this timeframe to plot a trend',
          textAlign: TextAlign.center,
          style: TextStyle(color: c.textTertiary, fontSize: 13),
        ),
      );
    }

    final vals = points.map((p) => p.value).toList();
    final minV = vals.reduce((a, b) => a < b ? a : b);
    final maxV = vals.reduce((a, b) => a > b ? a : b);
    final pad = ((maxV - minV) * 0.25).clamp(1.0, maxV * 0.3 + 5.0);

    return Column(
      children: [
        SizedBox(
          height: 146,
          child: LineChart(
            LineChartData(
              minY: (minV - pad).clamp(0.0, double.infinity),
              maxY: maxV + pad,
              extraLinesData: goalLine != null
                  ? ExtraLinesData(
                      horizontalLines: [
                        HorizontalLine(
                          y: goalLine!,
                          color: lineColor.withValues(alpha: 0.35),
                          strokeWidth: 1.2,
                          dashArray: const [4, 4],
                        ),
                      ],
                    )
                  : null,
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                getDrawingHorizontalLine: (_) => FlLine(
                  color: c.divider,
                  strokeWidth: 1,
                ),
              ),
              borderData: FlBorderData(show: false),
              titlesData: const FlTitlesData(show: false),
              lineTouchData: LineTouchData(
                touchTooltipData: LineTouchTooltipData(
                  getTooltipColor: (_) =>
                      c.isDark ? const Color(0xFF2C2C2E) : c.textPrimary,
                  getTooltipItems: (spots) => spots
                      .map(
                        (s) => LineTooltipItem(
                          '${isInteger ? s.y.round() : s.y.toStringAsFixed(1)} $unit',
                          const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
              lineBarsData: [
                LineChartBarData(
                  isCurved: true,
                  color: lineColor,
                  barWidth: 2.6,
                  dotData: FlDotData(show: points.length <= 14),
                  belowBarData: BarAreaData(
                    show: true,
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        lineColor.withValues(alpha: 0.24),
                        lineColor.withValues(alpha: 0.0),
                      ],
                    ),
                  ),
                  spots: List.generate(
                    vals.length,
                    (i) => FlSpot(i.toDouble(), vals[i]),
                  ),
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
              style: TextStyle(color: c.textTertiary, fontSize: 11.5),
            ),
            Text(
              'Min ${isInteger ? minV.round() : minV.toStringAsFixed(1)} · Max ${isInteger ? maxV.round() : maxV.toStringAsFixed(1)} $unit',
              style: TextStyle(
                color: c.textSecondary,
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            Text(
              DateFormat('MM/dd').format(points.last.date),
              style: TextStyle(color: c.textTertiary, fontSize: 11.5),
            ),
          ],
        ),
      ],
    );
  }
}

class _MetricStepperCircle extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _MetricStepperCircle({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return GestureDetector(
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
