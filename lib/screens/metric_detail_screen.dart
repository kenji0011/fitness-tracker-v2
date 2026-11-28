import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../models/local_profile.dart';
import '../services/active_profile_provider.dart';
import '../services/goal_completion_service.dart';
import '../services/step_counter_sync.dart';
import '../services/tempo_rust_db.dart';
import '../theme/app_colors.dart';
import '../widgets/bitchord_segmented_slider.dart';
import '../widgets/ios_popover_menu.dart';
import '../widgets/ios_stretch_sheet.dart';
import '../widgets/liquid_glass_surface.dart';
import '../widgets/step_accuracy_warning_sheet.dart';
import '../widgets/tempo_morph_calendar.dart';
import '../widgets/tempo_morph_route.dart';
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

/// Unified detail page for Calories, Steps, Activity, Waist, and 7-Day Burn,
/// aligned with Activity Stats, Water, Weight, and Sleep:
/// centered header + calendar picker, Latest | Week | M | Y segmented switcher,
/// goal progress bar, animated trend chart, editable daily target, and separate
/// Data source and About cards.
class MetricDetailScreen extends StatefulWidget {
  final TempoMetricKind kind;
  final DateTime? initialDate;

  const MetricDetailScreen({
    super.key,
    required this.kind,
    this.initialDate,
  });

  @override
  State<MetricDetailScreen> createState() => _MetricDetailScreenState();
}

class _MetricDetailScreenState extends State<MetricDetailScreen> {
  static const List<String> _tabs = ['Latest', 'Week', 'M', 'Y'];

  final TempoRustDb _db = TempoRustDb.instance;
  final GlobalKey _moreButtonKey = GlobalKey();
  final GlobalKey _dateButtonKey = GlobalKey();

  int _selectedTab = 0; // 0 = Latest, 1 = Week, 2 = M, 3 = Y
  late DateTime _anchorDate;
  List<_MetricPoint> _allPoints = [];
  double? _customWaistTargetCm;
  bool _liveStepsEnabled = false;
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
        return 'Activity time';
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
        return Icons.directions_walk_rounded;
      case TempoMetricKind.minutes:
        return CupertinoIcons.clock_fill;
      case TempoMetricKind.burn:
        return CupertinoIcons.bolt_fill;
    }
  }

  bool get _isInteger => widget.kind != TempoMetricKind.waist;

  bool get _showProgressBar => widget.kind != TempoMetricKind.waist;

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

  String get _averageCaption {
    switch (_selectedTab) {
      case 1:
        return '7-day average';
      case 2:
        return '30-day average';
      case 3:
        return '12-month average';
      default:
        return 'Overall average';
    }
  }

  List<String> _aboutParagraphs() {
    switch (widget.kind) {
      case TempoMetricKind.waist:
        return const [
          'Waist circumference measures the distance around the narrowest part of your midsection.',
          'Tracking it over time helps show changes in body composition beyond what scale weight alone reflects.',
        ];
      case TempoMetricKind.calories:
      case TempoMetricKind.burn:
        return const [
          'Active calories measure the energy your body burns through physical movement, including workouts, walking, and everyday activity.',
          'Tracking active calories helps you understand your daily energy output and stay consistent with your training.',
        ];
      case TempoMetricKind.steps:
        return const [
          'Steps count the total strides you take throughout the day using your phone motion sensor or manual entries.',
          'Steady daily walking supports cardiovascular health, boosts energy, and aids recovery between workouts.',
        ];
      case TempoMetricKind.minutes:
        return const [
          'Activity time measures the minutes you spend in moderate to vigorous movement, such as brisk walking, running, cycling, or strength training.',
          'Building regular active minutes each day improves endurance, strength, and overall fitness.',
        ];
    }
  }

  @override
  void initState() {
    super.initState();
    final initial = widget.initialDate ?? DateTime.now();
    _anchorDate = DateTime(initial.year, initial.month, initial.day);
    if (widget.kind == TempoMetricKind.burn) {
      _selectedTab = 1; // Default to Week view for 7-Day Burn
    }
    _load();
  }

  Future<void> _toggleLiveSteps(bool wantEnabled) async {
    final profileProvider = context.read<ActiveProfileProvider>();
    final pid = profileProvider.activeProfileId;
    if (pid == null) return;
    HapticFeedback.selectionClick();

    if (wantEnabled && await StepCounterSync.shouldShowAccuracyWarning(pid)) {
      if (!mounted) return;
      final choice = await showStepAccuracyWarningSheet(context);
      if (!mounted || choice == null || !choice.proceed) return;
      if (choice.suppressForToday) {
        await StepCounterSync.dismissAccuracyWarningForToday(pid);
      }
    }

    final res = await StepCounterSync.requestAndToggleLiveSteps(pid, wantEnabled);
    if (!mounted) return;
    setState(() => _liveStepsEnabled = res.enabled);
    profileProvider.notifyDataChanged();
    if (res.enabled) {
      showTempoToast(context, 'Live step counter enabled');
    } else if (wantEnabled && res.deniedPermanently) {
      showTempoToast(
        context,
        'Enable Physical Activity in phone settings',
        isError: true,
      );
      await openAppSettings();
    } else if (wantEnabled) {
      showTempoToast(
        context,
        'Physical Activity permission is needed for live steps',
        isError: true,
      );
    } else {
      showTempoToast(context, 'Live step counter paused');
    }
  }

  Future<void> _load({bool showSpinner = true}) async {
    final pid = context.read<ActiveProfileProvider>().activeProfileId;
    if (pid == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    if (showSpinner && _allPoints.isEmpty) {
      setState(() => _loading = true);
    }

    try {
      if (widget.kind == TempoMetricKind.steps) {
        final live = await StepCounterSync.isLiveEnabled(pid);
        if (mounted) _liveStepsEnabled = live;
      }

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
    } catch (e) {
      debugPrint('Failed to load MetricDetailScreen (${widget.kind}): $e');
      if (mounted) setState(() => _loading = false);
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

  String _formatDateLabel(DateTime dt) {
    final now = DateTime.now();
    if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
      return 'Today';
    }
    return DateFormat('MMM d, yyyy').format(dt);
  }

  Future<void> _pickAnchorDate() async {
    HapticFeedback.selectionClick();
    final recordedKeys = _allPoints
        .map((p) => DateFormat('yyyy-MM-dd').format(p.date))
        .toSet();
    final result = await pushTempoMorphRoute<HistoryCalendarSelection>(
      context: context,
      sourceKey: _dateButtonKey,
      sourceBorderRadius: 14,
      builder: (_) => HistoryCalendarScreen(
        initialDate: _anchorDate,
        initialModeIndex: _selectedTab,
        recordedDateKeys: recordedKeys,
      ),
    );
    if (result != null && mounted) {
      setState(() {
        _anchorDate = DateTime(
          result.date.year,
          result.date.month,
          result.date.day,
        );
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

    final result = await showTempoSheet<({double value, DateTime date})>(
      context: context,
      backgroundColor: AppColors.of(context, listen: false).card,
      borderRadius: 28,
      showDragHandle: true,
      builder: (_) => _AddMetricSheetBody(
        title: 'Add ${_title.toLowerCase()}',
        saveLabel: 'Save ${_title.toLowerCase()}',
        badgeIcon: _badgeIcon,
        badgeColor: _badgeColor,
        unit: _unit,
        initialValue: initVal,
        initialDate: _anchorDate,
        minVal: _minVal,
        maxVal: _maxVal,
        stepSize: _stepSize,
        isInteger: _isInteger,
      ),
    );

    if (result == null || !mounted) return;
    final val = result.value;
    final selectedDate = result.date;
    final now = DateTime.now();
    final recorded = DateTime(
      selectedDate.year,
      selectedDate.month,
      selectedDate.day,
      now.hour,
      now.minute,
    );
    final dateKey = DateFormat('yyyy-MM-dd').format(selectedDate);

    try {
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
      if (!mounted) return;
      await profileProvider.refreshProfiles();
      await _load(showSpinner: false);
      if (mounted) {
        showTempoToast(context, '$_title saved');
        if (dateKey == TempoRustDb.todayKey()) {
          await GoalCompletionService.instance.checkAndCelebrate(
            context,
            profileId: pid,
          );
        }
      }
    } catch (e) {
      debugPrint('Failed to save metric (${widget.kind}): $e');
      if (mounted) {
        showTempoToast(context, 'Could not save $_title', isError: true);
      }
    }
  }

  Future<void> _openGoalSheet() async {
    final profileProvider = context.read<ActiveProfileProvider>();
    final pid = profileProvider.activeProfileId;
    final profile = profileProvider.activeProfile;
    if (pid == null) return;

    final currentGoal = _goalValue(profile);

    final savedVal = await showTempoSheet<double>(
      context: context,
      backgroundColor: AppColors.of(context, listen: false).card,
      borderRadius: 28,
      showDragHandle: true,
      builder: (_) => _GoalMetricSheetBody(
        title: widget.kind == TempoMetricKind.waist
            ? 'Target waist'
            : 'Daily ${_title.toLowerCase()} goal',
        subtitle: switch (widget.kind) {
          TempoMetricKind.waist =>
            'Set your target waist circumference to track body recomposition.',
          TempoMetricKind.steps =>
            'Consistent daily steps boost endurance and cardiovascular health.',
          TempoMetricKind.minutes =>
            'Aim for steady active minutes each day to build lasting momentum.',
          TempoMetricKind.calories || TempoMetricKind.burn =>
            'Set an achievable daily active energy target to keep your streak alive.',
        },
        badgeIcon: _badgeIcon,
        badgeColor: _badgeColor,
        unit: _unit,
        initialGoal: currentGoal,
        minVal: _minVal,
        maxVal: _maxVal,
        stepSize: _stepSize,
        isInteger: _isInteger,
        presets: switch (widget.kind) {
          TempoMetricKind.waist => const [70.0, 75.0, 80.0, 85.0],
          TempoMetricKind.steps => const [5000.0, 7500.0, 10000.0, 12000.0],
          TempoMetricKind.minutes => const [30.0, 45.0, 60.0, 90.0],
          TempoMetricKind.calories || TempoMetricKind.burn =>
            const [400.0, 600.0, 800.0, 1000.0],
        },
      ),
    );

    if (savedVal == null || !mounted) return;
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

  void _openAboutSheet() {
    HapticFeedback.selectionClick();
    final paragraphs = _aboutParagraphs();
    showTempoSheet<void>(
      context: context,
      backgroundColor: AppColors.of(context, listen: false).card,
      borderRadius: 28,
      showDragHandle: true,
      builder: (ctx) {
        final mc = AppColors.of(ctx);
        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            22,
            8,
            22,
            MediaQuery.paddingOf(ctx).bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
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
                  Expanded(
                    child: Text(
                      'About',
                      style: TextStyle(
                        color: mc.textPrimary,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              for (int i = 0; i < paragraphs.length; i++) ...[
                if (i > 0) const SizedBox(height: 10),
                Text(
                  paragraphs[i],
                  style: TextStyle(
                    color: mc.textSecondary,
                    fontSize: 14.5,
                    height: 1.55,
                  ),
                ),
              ],
              const SizedBox(height: 22),
              TempoLiquidButton(
                primary: false,
                height: 50,
                borderRadius: 999,
                onPressed: () {
                  HapticFeedback.selectionClick();
                  Navigator.of(ctx).pop();
                },
                child: const Text(
                  'Close',
                  style: TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w600,
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
                child: Text(
                  title,
                  style: TextStyle(
                    color: mc.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Divider(height: 1, color: mc.divider),
              Expanded(
                child: history.isEmpty
                    ? Center(
                        child: Text(
                          'No records yet. Tap + to add an entry.',
                          style: TextStyle(
                            color: mc.textSecondary,
                            fontSize: 14,
                          ),
                        ),
                      )
                    : ListView.separated(
                        padding: EdgeInsets.fromLTRB(
                          20,
                          16,
                          20,
                          MediaQuery.paddingOf(ctx).bottom + 20,
                        ),
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
                                  DateFormat('MMMM d, yyyy').format(pt.date),
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
      anchorIcon: CupertinoIcons.add,
      actions: [
        TempoPopoverAction(
          label: 'Add data',
          onTap: _openAddSheet,
        ),
        TempoPopoverAction(
          label: 'Daily goal',
          onTap: _openGoalSheet,
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
    final goalProgress =
        (currentVal > 0 && goalVal > 0) ? (currentVal / goalVal).clamp(0.0, 1.0) : 0.0;
    final goalPct = (currentVal > 0 && goalVal > 0)
        ? ((currentVal / goalVal) * 100).round().clamp(0, 999)
        : 0;
    final remainingVal = math.max(0.0, goalVal - currentVal);
    final goalReached = _showProgressBar && goalVal > 0 && currentVal >= goalVal;

    return Scaffold(
      backgroundColor: c.scaffold,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // Centered top bar aligned with ActivityStatsScreen
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TempoGlassCircleButton(
                        icon: TempoBackChevron(color: c.textPrimary, size: 22),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 58),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: c.textPrimary,
                              fontSize: 19,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(height: 1),
                          GestureDetector(
                            key: _dateButtonKey,
                            behavior: HitTestBehavior.opaque,
                            onTap: _pickAnchorDate,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(
                                  child: Text(
                                    DateFormat('MMMM d, yyyy')
                                        .format(_anchorDate),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: c.textSecondary,
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 2),
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
                    Align(
                      alignment: Alignment.centerRight,
                      child: TempoGlassCircleButton(
                        key: _moreButtonKey,
                        tooltip: 'Quick actions',
                        icon: Icon(
                          CupertinoIcons.add,
                          size: 22,
                          color: c.textPrimary,
                        ),
                        onPressed: _openMoreMenu,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // 4-Segment BitChord Liquid Glass Sliding Timeframe Pill (Latest | Week | M | Y)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 2, 18, 16),
              child: BitChordSegmentedSlider(
                labels: _tabs,
                selectedIndex: _selectedTab,
                onChanged: (idx) => setState(() => _selectedTab = idx),
              ),
            ),

            Expanded(
              child: _loading
                  ? Center(child: CupertinoActivityIndicator(color: c.accent))
                  : RefreshIndicator(
                      color: _badgeColor,
                      onRefresh: () => _load(showSpinner: false),
                      child: ListView(
                        physics: const BouncingScrollPhysics(
                          parent: AlwaysScrollableScrollPhysics(),
                        ),
                        padding: EdgeInsets.fromLTRB(
                          18,
                          0,
                          18,
                          MediaQuery.paddingOf(context).bottom + 32,
                        ),
                        children: [
                          // Card 1: Primary Metric + Goal Progress + Animated Trend Graph
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
                                    Expanded(
                                      child: Text(
                                        _cardTitle,
                                        style: TextStyle(
                                          color: c.textPrimary,
                                          fontSize: 16.5,
                                          fontWeight: FontWeight.w600,
                                          letterSpacing: -0.2,
                                        ),
                                      ),
                                    ),
                                    if (_showProgressBar && goalVal > 0)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: _badgeColor.withValues(
                                            alpha: c.isDark ? 0.18 : 0.13,
                                          ),
                                          borderRadius:
                                              BorderRadius.circular(999),
                                        ),
                                        child: Text(
                                          '$goalPct%',
                                          style: TextStyle(
                                            color: _badgeColor,
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
                                const SizedBox(height: 20),
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
                                                      fontSize: 34,
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
                                              const SizedBox(width: 5),
                                              Text(
                                                _unit,
                                                style: TextStyle(
                                                  color: c.textSecondary,
                                                  fontSize: 15,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 5),
                                          Text(
                                            latestDate != null
                                                ? _formatDateLabel(latestDate)
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
                                          const SizedBox(height: 6),
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
                                            _averageCaption,
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
                                if (_showProgressBar && goalVal > 0) ...[
                                  const SizedBox(height: 16),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(99),
                                    child: TweenAnimationBuilder<double>(
                                      tween: Tween<double>(
                                        begin: 0,
                                        end: goalProgress,
                                      ),
                                      duration:
                                          const Duration(milliseconds: 420),
                                      curve: Curves.easeOutCubic,
                                      builder: (_, v, __) =>
                                          LinearProgressIndicator(
                                        value: v,
                                        minHeight: 7,
                                        backgroundColor: c.divider,
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                          _badgeColor,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
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

                          // Card 2: Daily Target / Goal (tappable to edit)
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
                                    Expanded(
                                      child: Text(
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
                                    ),
                                    Text(
                                      'Edit',
                                      style: TextStyle(
                                        color: c.textTertiary,
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Icon(
                                      CupertinoIcons.chevron_right,
                                      size: 15,
                                      color: c.textTertiary,
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
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
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
                                            widget.kind == TempoMetricKind.waist
                                                ? 'Target waist'
                                                : 'Daily goal',
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
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            _showProgressBar
                                                ? (goalReached
                                                    ? 'Reached'
                                                    : '${_formatVal(remainingVal)} $_unit')
                                                : (currentVal > 0
                                                    ? '$goalPct%'
                                                    : '--'),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: goalReached
                                                  ? _badgeColor
                                                  : c.textPrimary,
                                              fontSize: 21,
                                              fontWeight: FontWeight.w600,
                                              fontFeatures: const [
                                                FontFeature.tabularFigures(),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            _showProgressBar
                                                ? (goalReached
                                                    ? 'Target status'
                                                    : 'To reach goal')
                                                : 'Of target',
                                            style: TextStyle(
                                              color: c.textTertiary,
                                              fontSize: 12.5,
                                            ),
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

                          if (widget.kind == TempoMetricKind.steps) ...[
                            AppleCard(
                              borderRadius: 24,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 14,
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
                                      Icons.directions_walk_rounded,
                                      color: Colors.white,
                                      size: 17,
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Text(
                                      'Live step counter',
                                      style: TextStyle(
                                        color: c.textPrimary,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        letterSpacing: -0.15,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  CupertinoSwitch(
                                    activeTrackColor: c.accent,
                                    value: _liveStepsEnabled,
                                    onChanged: _toggleLiveSteps,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 14),
                          ],

                          // Card 3: Data source (standalone card)
                          AppleCard(
                            borderRadius: 24,
                            padding: EdgeInsets.zero,
                            child: _MetricActionRow(
                              borderRadius: BorderRadius.circular(24),
                              icon: CupertinoIcons.layers_alt_fill,
                              iconBackground: _badgeColor,
                              iconColor: Colors.white,
                              title: 'Data source',
                              trailingText: _allPoints.isNotEmpty
                                  ? '${_allPoints.length}'
                                  : null,
                              onTap: _openDataSourceSheet,
                            ),
                          ),
                          const SizedBox(height: 14),

                          // Card 4: About (standalone card)
                          AppleCard(
                            borderRadius: 24,
                            padding: EdgeInsets.zero,
                            child: _MetricActionRow(
                              borderRadius: BorderRadius.circular(24),
                              icon: CupertinoIcons.info,
                              iconBackground: _badgeColor,
                              iconColor: Colors.white,
                              title: 'About',
                              onTap: _openAboutSheet,
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

class _MetricActionRow extends StatelessWidget {
  final BorderRadius borderRadius;
  final IconData icon;
  final Color iconBackground;
  final Color iconColor;
  final String title;
  final String? trailingText;
  final VoidCallback onTap;

  const _MetricActionRow({
    required this.borderRadius,
    required this.icon,
    required this.iconBackground,
    required this.iconColor,
    required this.title,
    this.trailingText,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return InkWell(
      borderRadius: borderRadius,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: iconBackground,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: iconColor, size: 17),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  color: c.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.15,
                ),
              ),
            ),
            if (trailingText != null) ...[
              Text(
                trailingText!,
                style: TextStyle(
                  color: c.textTertiary,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: 6),
            ],
            Icon(
              CupertinoIcons.chevron_right,
              size: 16,
              color: c.textTertiary,
            ),
          ],
        ),
      ),
    );
  }
}

class _AddMetricSheetBody extends StatefulWidget {
  final String title;
  final String saveLabel;
  final IconData badgeIcon;
  final Color badgeColor;
  final String unit;
  final double initialValue;
  final DateTime initialDate;
  final double minVal;
  final double maxVal;
  final double stepSize;
  final bool isInteger;

  const _AddMetricSheetBody({
    required this.title,
    required this.saveLabel,
    required this.badgeIcon,
    required this.badgeColor,
    required this.unit,
    required this.initialValue,
    required this.initialDate,
    required this.minVal,
    required this.maxVal,
    required this.stepSize,
    required this.isInteger,
  });

  @override
  State<_AddMetricSheetBody> createState() => _AddMetricSheetBodyState();
}

class _AddMetricSheetBodyState extends State<_AddMetricSheetBody> {
  late final TextEditingController _ctrl;
  late DateTime _selectedDate;
  final GlobalKey _datePillKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(
      text: widget.isInteger
          ? widget.initialValue.round().toString()
          : widget.initialValue.toStringAsFixed(1),
    );
    _selectedDate = widget.initialDate;
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _adjust(double delta) {
    HapticFeedback.selectionClick();
    final cur = double.tryParse(_ctrl.text.trim()) ?? widget.initialValue;
    final next = (cur + delta).clamp(widget.minVal, widget.maxVal);
    _ctrl.text =
        widget.isInteger ? next.round().toString() : next.toStringAsFixed(1);
    setState(() {});
  }

  void _submit() {
    final val = double.tryParse(_ctrl.text.trim());
    if (val == null || val < widget.minVal || val > widget.maxVal) {
      showTempoToast(
        context,
        'Enter a valid value in ${widget.unit}',
        isError: true,
      );
      return;
    }
    Navigator.of(context).pop((value: val, date: _selectedDate));
  }

  @override
  Widget build(BuildContext context) {
    final mc = AppColors.of(context);
    final bottomInset = math.max(
      MediaQuery.viewInsetsOf(context).bottom,
      MediaQuery.paddingOf(context).bottom,
    );

    return Padding(
      padding: EdgeInsets.fromLTRB(22, 10, 22, bottomInset + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: widget.badgeColor,
                  shape: BoxShape.circle,
                ),
                child: Icon(widget.badgeIcon, color: Colors.white, size: 19),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  widget.title,
                  style: TextStyle(
                    color: mc.textPrimary,
                    fontSize: 19.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.35,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            decoration: BoxDecoration(
              color: mc.searchBg,
              borderRadius: BorderRadius.circular(32),
              border: Border.all(color: mc.cardBorder, width: 0.8),
            ),
            child: Row(
              children: [
                TempoGlassCircleButton(
                  size: 50,
                  tooltip: 'Decrease value',
                  onPressed: () => _adjust(-widget.stepSize),
                  icon: Icon(
                    CupertinoIcons.minus,
                    color: mc.textPrimary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: _ctrl,
                        textAlign: TextAlign.center,
                        keyboardType: TextInputType.numberWithOptions(
                          decimal: !widget.isInteger,
                        ),
                        style: TextStyle(
                          color: mc.textPrimary,
                          fontSize: 30,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.7,
                          height: 1.05,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                        decoration: const InputDecoration(
                          isDense: true,
                          filled: false,
                          border: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(vertical: 2),
                        ),
                      ),
                      Text(
                        widget.unit,
                        style: TextStyle(
                          color: mc.textTertiary,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                TempoGlassCircleButton(
                  size: 50,
                  tooltip: 'Increase value',
                  onPressed: () => _adjust(widget.stepSize),
                  icon: Icon(
                    CupertinoIcons.add,
                    color: mc.textPrimary,
                    size: 20,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          TempoLiquidButton(
            key: _datePillKey,
            primary: false,
            borderRadius: 18,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            onPressed: () async {
              HapticFeedback.selectionClick();
              final now = DateTime.now();
              final d = await showTempoMorphCalendar(
                context: context,
                anchorKey: _datePillKey,
                initialDate: _selectedDate.isAfter(now) ? now : _selectedDate,
                firstDate: DateTime(2020),
                lastDate: now,
                accentColor: widget.badgeColor,
                sourceBorderRadius: 18,
              );
              if (d != null && mounted) {
                setState(() => _selectedDate = d);
              }
            },
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
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const Spacer(),
                Text(
                  DateFormat('MMMM d, yyyy').format(_selectedDate),
                  style: TextStyle(
                    color: mc.textPrimary,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          TempoBouncyButton(
            onPressed: () {
              HapticFeedback.lightImpact();
              _submit();
            },
            child: Text(widget.saveLabel),
          ),
        ],
      ),
    );
  }
}

class _GoalMetricSheetBody extends StatefulWidget {
  final String title;
  final String subtitle;
  final IconData badgeIcon;
  final Color badgeColor;
  final String unit;
  final double initialGoal;
  final double minVal;
  final double maxVal;
  final double stepSize;
  final bool isInteger;
  final List<double> presets;

  const _GoalMetricSheetBody({
    required this.title,
    required this.subtitle,
    required this.badgeIcon,
    required this.badgeColor,
    required this.unit,
    required this.initialGoal,
    required this.minVal,
    required this.maxVal,
    required this.stepSize,
    required this.isInteger,
    required this.presets,
  });

  @override
  State<_GoalMetricSheetBody> createState() => _GoalMetricSheetBodyState();
}

class _GoalMetricSheetBodyState extends State<_GoalMetricSheetBody> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(
      text: widget.isInteger
          ? widget.initialGoal.round().toString()
          : widget.initialGoal.toStringAsFixed(1),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  double get _currentVal =>
      double.tryParse(_ctrl.text.trim()) ?? widget.initialGoal;

  void _setVal(double nextVal) {
    HapticFeedback.selectionClick();
    final clamped = nextVal.clamp(widget.minVal, widget.maxVal);
    _ctrl.text = widget.isInteger
        ? clamped.round().toString()
        : clamped.toStringAsFixed(1);
    setState(() {});
  }

  void _adjust(double delta) => _setVal(_currentVal + delta);

  String _formatPreset(double val) => widget.isInteger
      ? NumberFormat('#,###').format(val.round())
      : val.toStringAsFixed(1);

  void _submit() {
    HapticFeedback.lightImpact();
    final parsed = double.tryParse(_ctrl.text.trim());
    if (parsed == null || parsed <= 0 || parsed > widget.maxVal) {
      showTempoToast(
        context,
        'Enter a valid goal in ${widget.unit}',
        isError: true,
      );
      return;
    }
    Navigator.of(context).pop(parsed);
  }

  @override
  Widget build(BuildContext context) {
    final mc = AppColors.of(context);
    final bottomInset = math.max(
      MediaQuery.viewInsetsOf(context).bottom,
      MediaQuery.paddingOf(context).bottom,
    );
    final current = _currentVal;

    return Padding(
      padding: EdgeInsets.fromLTRB(22, 10, 22, bottomInset + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Editorial icon-anchored modal header
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: widget.badgeColor,
                  shape: BoxShape.circle,
                ),
                child: Icon(widget.badgeIcon, color: Colors.white, size: 19),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      style: TextStyle(
                        color: mc.textPrimary,
                        fontSize: 19.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.35,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: mc.textSecondary,
                        fontSize: 12.5,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Recessed pill stepper tray with circular Liquid Glass - / + buttons
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            decoration: BoxDecoration(
              color: mc.searchBg,
              borderRadius: BorderRadius.circular(32),
              border: Border.all(color: mc.cardBorder, width: 0.8),
            ),
            child: Row(
              children: [
                TempoGlassCircleButton(
                  size: 50,
                  tooltip: 'Decrease target',
                  onPressed: () => _adjust(-widget.stepSize),
                  icon: Icon(
                    CupertinoIcons.minus,
                    color: mc.textPrimary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: _ctrl,
                        textAlign: TextAlign.center,
                        onChanged: (_) => setState(() {}),
                        keyboardType: TextInputType.numberWithOptions(
                          decimal: !widget.isInteger,
                        ),
                        style: TextStyle(
                          color: mc.textPrimary,
                          fontSize: 30,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.7,
                          height: 1.05,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                        decoration: const InputDecoration(
                          isDense: true,
                          filled: false,
                          border: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(vertical: 2),
                        ),
                      ),
                      Text(
                        widget.unit,
                        style: TextStyle(
                          color: mc.textTertiary,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                TempoGlassCircleButton(
                  size: 50,
                  tooltip: 'Increase target',
                  onPressed: () => _adjust(widget.stepSize),
                  icon: Icon(
                    CupertinoIcons.add,
                    color: mc.textPrimary,
                    size: 20,
                  ),
                ),
              ],
            ),
          ),

          if (widget.presets.isNotEmpty) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                for (int i = 0; i < widget.presets.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  Expanded(
                    child: Builder(
                      builder: (_) {
                        final p = widget.presets[i];
                        final active = (current - p).abs() < 0.05;
                        return GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => _setVal(p),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 170),
                            curve: Curves.easeOutCubic,
                            padding: const EdgeInsets.symmetric(vertical: 9),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: active
                                  ? widget.badgeColor.withValues(
                                      alpha: mc.isDark ? 0.24 : 0.14,
                                    )
                                  : mc.searchBg,
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: active
                                    ? widget.badgeColor.withValues(alpha: 0.55)
                                    : mc.cardBorder,
                                width: active ? 1.1 : 0.7,
                              ),
                            ),
                            child: Text(
                              _formatPreset(p),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: active
                                    ? widget.badgeColor
                                    : mc.textSecondary,
                                fontSize: 12.5,
                                fontWeight:
                                    active ? FontWeight.w700 : FontWeight.w600,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ],
            ),
          ],

          const SizedBox(height: 20),
          TempoBouncyButton(
            onPressed: _submit,
            child: const Text('Save goal'),
          ),
        ],
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

  String _fmt(double v) =>
      isInteger ? NumberFormat('#,###').format(v.round()) : v.toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    if (points.length < 2) {
      return Container(
        height: 132,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 18),
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
    final ceilingV = goalLine != null ? math.max(maxV, goalLine!) : maxV;
    final pad = ((ceilingV - minV) * 0.22).clamp(1.0, ceilingV * 0.25 + 5.0);

    return Column(
      children: [
        SizedBox(
          height: 146,
          child: LineChart(
            LineChartData(
              minY: (minV - pad).clamp(0.0, double.infinity),
              maxY: ceilingV + pad,
              extraLinesData: goalLine != null
                  ? ExtraLinesData(
                      horizontalLines: [
                        HorizontalLine(
                          y: goalLine!,
                          color: lineColor.withValues(alpha: 0.42),
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
                          '${_fmt(s.y)} $unit',
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
              DateFormat('MMM d').format(points.first.date),
              style: TextStyle(color: c.textTertiary, fontSize: 11.5),
            ),
            Text(
              'Min ${_fmt(minV)}  Max ${_fmt(maxV)} $unit',
              style: TextStyle(
                color: c.textSecondary,
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            Text(
              DateFormat('MMM d').format(points.last.date),
              style: TextStyle(color: c.textTertiary, fontSize: 11.5),
            ),
          ],
        ),
      ],
    );
  }
}
