import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:jiggicons/jiggicons.dart';
import 'package:provider/provider.dart';

import '../models/local_profile.dart';
import '../services/active_profile_provider.dart';
import '../services/goal_completion_service.dart';
import '../services/tempo_rust_db.dart';
import '../theme/app_colors.dart';
import '../widgets/bitchord_segmented_slider.dart';
import '../widgets/ios_popover_menu.dart';
import '../widgets/ios_stretch_sheet.dart';
import '../widgets/liquid_glass_surface.dart';
import '../widgets/tempo_jigg_icon.dart';
import '../widgets/tempo_morph_calendar.dart';
import '../widgets/tempo_morph_route.dart';
import '../widgets/tempo_sliver_header.dart';
import '../widgets/tempo_toast.dart';
import 'history_calendar_screen.dart';

/// Hydration / Water Intake detail page matching Tempo's Weight & Sleep architecture:
/// History Calendar date selector, iOS spring popover, Latest | Week | M | Y tabs,
/// quick-add cup buttons (+250 / +500 / +750 ml), editable daily goal, and trend graph.
class WaterDetailScreen extends StatefulWidget {
  const WaterDetailScreen({super.key});

  @override
  State<WaterDetailScreen> createState() => _WaterDetailScreenState();
}

class _WaterDetailScreenState extends State<WaterDetailScreen> {
  static const Color _waterBlue = Color(0xFF38BDF8);
  static const List<String> _tabs = ['Latest', 'Week', 'M', 'Y'];

  final TempoRustDb _db = TempoRustDb.instance;
  final GlobalKey _moreButtonKey = GlobalKey();
  final GlobalKey _dateButtonKey = GlobalKey();
  final JiggIconController _dropController = JiggIconController();

  int _selectedTab = 0;
  DateTime _anchorDate = DateTime.now();
  List<BodyMetricPoint> _allPoints = [];
  int _goalMl = 2500;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _dropController.dispose();
    super.dispose();
  }

  Future<void> _load({bool showLoading = true}) async {
    final pid = context.read<ActiveProfileProvider>().activeProfileId;
    if (pid == null) return;
    if (showLoading && _allPoints.isEmpty) {
      setState(() => _loading = true);
    }

    try {
      final results = await Future.wait([
        _db.getBodyMetricHistory(pid, 'water', limit: 2000),
        _db.getSetting('water_goal_ml_$pid'),
      ]);
      if (!mounted) return;

      final pts = (results[0] as List<BodyMetricPoint>)
        ..sort((a, b) => a.recordedAt.compareTo(b.recordedAt));
      final savedGoal = int.tryParse((results[1] as String?) ?? '');

      setState(() {
        _allPoints = pts;
        _goalMl = (savedGoal != null && savedGoal >= 500 && savedGoal <= 10000)
            ? savedGoal
            : 2500;
        _loading = false;
      });
    } catch (e) {
      debugPrint('Failed to load water history: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  String _dayKey(DateTime dt) => DateFormat('yyyy-MM-dd').format(dt);

  /// Aggregates individual water cup logs into daily totals (`yyyy-MM-dd` -> ml).
  List<({DateTime date, double ml})> get _dailyTotals {
    final map = <String, double>{};
    for (final pt in _allPoints) {
      final local = pt.recordedAt.toLocal();
      final k = _dayKey(local);
      map[k] = (map[k] ?? 0) + pt.value;
    }
    final keys = map.keys.toList()..sort();
    return keys
        .map((k) => (date: DateTime.parse(k), ml: map[k]!))
        .toList();
  }

  double get _anchorDayTotalMl {
    final k = _dayKey(_anchorDate);
    double sum = 0;
    for (final pt in _allPoints) {
      if (_dayKey(pt.recordedAt.toLocal()) == k) {
        sum += pt.value;
      }
    }
    return sum;
  }

  List<({DateTime date, double ml})> get _windowDailyTotals {
    final anchorEnd = DateTime(
      _anchorDate.year,
      _anchorDate.month,
      _anchorDate.day,
      23,
      59,
      59,
    );
    final upTo = _dailyTotals.where((e) => !e.date.isAfter(anchorEnd)).toList();
    if (_selectedTab == 0) return upTo;
    final days = _selectedTab == 1 ? 7 : (_selectedTab == 2 ? 30 : 365);
    final start = DateTime(
      _anchorDate.year,
      _anchorDate.month,
      _anchorDate.day,
    ).subtract(Duration(days: days - 1));
    return upTo.where((e) => !e.date.isBefore(start)).toList();
  }

  Future<void> _quickAddWater(int ml) async {
    final provider = context.read<ActiveProfileProvider>();
    final pid = provider.activeProfileId;
    if (pid == null) return;
    HapticFeedback.lightImpact();
    _dropController.play();

    final now = DateTime.now();
    final recorded = DateTime(
      _anchorDate.year,
      _anchorDate.month,
      _anchorDate.day,
      now.hour,
      now.minute,
      now.second,
    );
    try {
      await _db.logBodyMetric(
        profileId: pid,
        metricType: 'water',
        value: ml.toDouble(),
        recordedAt: recorded,
      );
      provider.notifyDataChanged();
      await _load(showLoading: false);
      if (mounted) {
        showTempoToast(context, '+$ml ml logged');
        if (_dayKey(recorded) == TempoRustDb.todayKey()) {
          await GoalCompletionService.instance.checkAndCelebrate(
            context,
            profileId: pid,
          );
        }
      }
    } catch (e) {
      debugPrint('Failed to log water intake: $e');
      if (mounted) {
        showTempoToast(context, 'Could not save water intake', isError: true);
      }
    }
  }

  Future<void> _pickAnchorDate() async {
    HapticFeedback.selectionClick();
    final recordedKeys = _allPoints
        .map((p) => _dayKey(p.recordedAt.toLocal()))
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
        _anchorDate = result.date;
        _selectedTab = result.modeIndex;
      });
    }
  }

  Future<void> _openAddCustomWaterSheet() async {
    final ctrl = TextEditingController(text: '250');
    DateTime selectedDate = _anchorDate;
    final datePillKey = GlobalKey();

    final savedMl = await showTempoSheet<int>(
      context: context,
      backgroundColor: AppColors.of(context, listen: false).card,
      borderRadius: 28,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          final mc = AppColors.of(ctx);
          void adjust(int delta) {
            HapticFeedback.selectionClick();
            final cur = int.tryParse(ctrl.text.trim()) ?? 250;
            ctrl.text = (cur + delta).clamp(50, 3000).toString();
            setModalState(() {});
          }

          return Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              12,
              20,
              math.max(
                    MediaQuery.viewInsetsOf(ctx).bottom,
                    MediaQuery.paddingOf(ctx).bottom,
                  ) +
                  24,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: const BoxDecoration(
                        color: _waterBlue,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        CupertinoIcons.drop_fill,
                        color: Colors.white,
                        size: 19,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Add water',
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: mc.searchBg,
                    borderRadius: BorderRadius.circular(32),
                    border: Border.all(color: mc.cardBorder, width: 0.8),
                  ),
                  child: Row(
                    children: [
                      TempoGlassCircleButton(
                        size: 50,
                        tooltip: 'Decrease water',
                        onPressed: () => adjust(-50),
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
                              controller: ctrl,
                              textAlign: TextAlign.center,
                              keyboardType: TextInputType.number,
                              style: TextStyle(
                                color: mc.textPrimary,
                                fontSize: 30,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.7,
                                height: 1.05,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                              decoration: const InputDecoration(
                                isDense: true,
                                filled: false,
                                border: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                contentPadding:
                                    EdgeInsets.symmetric(vertical: 2),
                              ),
                            ),
                            Text(
                              'ml',
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
                        tooltip: 'Increase water',
                        onPressed: () => adjust(50),
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
                  key: datePillKey,
                  primary: false,
                  borderRadius: 18,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  onPressed: () async {
                    HapticFeedback.selectionClick();
                    final now = DateTime.now();
                    final d = await showTempoMorphCalendar(
                      context: ctx,
                      anchorKey: datePillKey,
                      initialDate:
                          selectedDate.isAfter(now) ? now : selectedDate,
                      firstDate: DateTime(2020),
                      lastDate: now,
                      accentColor: _waterBlue,
                      sourceBorderRadius: 18,
                    );
                    if (d != null) setModalState(() => selectedDate = d);
                  },
                  child: Row(
                    children: [
                      TempoJiggIcon(
                        'calendar',
                        variant: JiggIconVariant.outline,
                        size: 18,
                        color: mc.textSecondary,
                        trigger: JiggIconTrigger.appear,
                        fallbackIcon: CupertinoIcons.calendar,
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
                        DateFormat('MM/dd/yyyy').format(selectedDate),
                        style: TextStyle(
                          color: mc.textPrimary,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                TempoBouncyButton(
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    final val = int.tryParse(ctrl.text.trim());
                    if (val == null || val < 50 || val > 5000) {
                      showTempoToast(
                        ctx,
                        'Enter an amount between 50 and 5,000 ml',
                        isError: true,
                      );
                      return;
                    }
                    Navigator.of(ctx).pop(val);
                  },
                  child: const Text('Save water'),
                ),
              ],
            ),
          );
        },
      ),
    );

    ctrl.dispose();
    if (savedMl != null && mounted) {
      final provider = context.read<ActiveProfileProvider>();
      final pid = provider.activeProfileId;
      if (pid == null) return;
      final now = DateTime.now();
      try {
        await _db.logBodyMetric(
          profileId: pid,
          metricType: 'water',
          value: savedMl.toDouble(),
          recordedAt: DateTime(
            selectedDate.year,
            selectedDate.month,
            selectedDate.day,
            now.hour,
            now.minute,
            now.second,
          ),
        );
        provider.notifyDataChanged();
        if (mounted && _dayKey(selectedDate) != _dayKey(_anchorDate)) {
          setState(() => _anchorDate = selectedDate);
        }
        await _load(showLoading: false);
        _dropController.play();
        if (mounted) {
          showTempoToast(context, '+$savedMl ml logged');
          if (_dayKey(selectedDate) == TempoRustDb.todayKey()) {
            await GoalCompletionService.instance.checkAndCelebrate(
              context,
              profileId: pid,
            );
          }
        }
      } catch (e) {
        debugPrint('Failed to save custom water intake: $e');
        if (mounted) {
          showTempoToast(context, 'Could not save water intake', isError: true);
        }
      }
    }
  }

  Future<void> _openGoalSheet() async {
    final pid = context.read<ActiveProfileProvider>().activeProfileId;
    if (pid == null) return;
    int tempGoal = _goalMl;

    final saved = await showTempoSheet<int>(
      context: context,
      backgroundColor: AppColors.of(context, listen: false).card,
      borderRadius: 28,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          final mc = AppColors.of(ctx);
          const presets = [2000, 2500, 3000, 3500];
          void adjust(int delta) {
            HapticFeedback.selectionClick();
            setModalState(() {
              tempGoal = (tempGoal + delta).clamp(1000, 5000);
            });
          }

          return Padding(
            padding: EdgeInsets.fromLTRB(
              22,
              10,
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
                      width: 38,
                      height: 38,
                      decoration: const BoxDecoration(
                        color: _waterBlue,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        CupertinoIcons.drop_fill,
                        color: Colors.white,
                        size: 19,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Daily water goal',
                            style: TextStyle(
                              color: mc.textPrimary,
                              fontSize: 19.5,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.35,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Steady daily hydration supports recovery and focus.',
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

                // Recessed pill tray with Liquid Glass - / + buttons
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: mc.searchBg,
                    borderRadius: BorderRadius.circular(32),
                    border: Border.all(color: mc.cardBorder, width: 0.8),
                  ),
                  child: Row(
                    children: [
                      TempoGlassCircleButton(
                        size: 50,
                        tooltip: 'Decrease water goal',
                        onPressed: () => adjust(-250),
                        icon: Icon(
                          CupertinoIcons.minus,
                          color: mc.textPrimary,
                          size: 20,
                        ),
                      ),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              NumberFormat('#,###').format(tempGoal),
                              style: TextStyle(
                                color: mc.textPrimary,
                                fontSize: 30,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.7,
                                height: 1.05,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                            Text(
                              'ml / day',
                              style: TextStyle(
                                color: mc.textTertiary,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      TempoGlassCircleButton(
                        size: 50,
                        tooltip: 'Increase water goal',
                        onPressed: () => adjust(250),
                        icon: Icon(
                          CupertinoIcons.add,
                          color: mc.textPrimary,
                          size: 20,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Slider(
                  value: tempGoal.toDouble(),
                  min: 1000,
                  max: 5000,
                  divisions: 16,
                  activeColor: _waterBlue,
                  onChanged: (v) {
                    HapticFeedback.selectionClick();
                    setModalState(() => tempGoal = (v / 250).round() * 250);
                  },
                ),
                Row(
                  children: [
                    for (int i = 0; i < presets.length; i++) ...[
                      if (i > 0) const SizedBox(width: 8),
                      Expanded(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setModalState(() => tempGoal = presets[i]);
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 170),
                            curve: Curves.easeOutCubic,
                            padding: const EdgeInsets.symmetric(vertical: 9),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: tempGoal == presets[i]
                                  ? _waterBlue.withValues(
                                      alpha: mc.isDark ? 0.24 : 0.14,
                                    )
                                  : mc.searchBg,
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: tempGoal == presets[i]
                                    ? _waterBlue.withValues(alpha: 0.55)
                                    : mc.cardBorder,
                                width: tempGoal == presets[i] ? 1.1 : 0.7,
                              ),
                            ),
                            child: Text(
                              '${(presets[i] / 1000).toStringAsFixed(1)}L',
                              style: TextStyle(
                                color: tempGoal == presets[i]
                                    ? _waterBlue
                                    : mc.textSecondary,
                                fontSize: 12.5,
                                fontWeight: tempGoal == presets[i]
                                    ? FontWeight.w700
                                    : FontWeight.w600,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 18),
                TempoBouncyButton(
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    Navigator.of(ctx).pop(tempGoal);
                  },
                  child: const Text('Save goal'),
                ),
              ],
            ),
          );
        },
      ),
    );

    if (saved != null && mounted) {
      await _db.setSetting('water_goal_ml_$pid', '$saved');
      if (!mounted) return;
      setState(() => _goalMl = saved);
      showTempoToast(context, 'Water goal updated');
    }
  }

  void _openHistorySheet({String title = 'Data source'}) {
    HapticFeedback.selectionClick();
    final history = _allPoints.reversed.toList();
    showTempoSheet<void>(
      context: context,
      backgroundColor: AppColors.of(context, listen: false).card,
      borderRadius: 28,
      showDragHandle: true,
      builder: (ctx) {
        final mc = AppColors.of(ctx);
        return SizedBox(
          height: MediaQuery.sizeOf(ctx).height * 0.62,
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
                          'No water logs yet. Tap +250 ml to start.',
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
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      DateFormat('MMMM d, yyyy')
                                          .format(pt.recordedAt.toLocal()),
                                      style: TextStyle(
                                        color: mc.textPrimary,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    Text(
                                      DateFormat('h:mm a')
                                          .format(pt.recordedAt.toLocal()),
                                      style: TextStyle(
                                        color: mc.textTertiary,
                                        fontSize: 12.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                '+${pt.value.round()} ml',
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
          onTap: _openAddCustomWaterSheet,
        ),
        TempoPopoverAction(
          label: 'Daily goal',
          onTap: _openGoalSheet,
        ),
      ],
    );
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
                    decoration: const BoxDecoration(
                      color: _waterBlue,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      CupertinoIcons.drop_fill,
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
              Text(
                'Daily hydration tracks the water you drink throughout the day in milliliters so you can stay consistently hydrated.',
                style: TextStyle(
                  color: mc.textSecondary,
                  fontSize: 14.5,
                  height: 1.55,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Adequate fluid intake supports temperature regulation, joint comfort, focus, and workout recovery.',
                style: TextStyle(
                  color: mc.textSecondary,
                  fontSize: 14.5,
                  height: 1.55,
                ),
              ),
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

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final todayMl = _anchorDayTotalMl.round();
    final progress = (_goalMl > 0 ? todayMl / _goalMl : 0.0).clamp(0.0, 1.0);
    final pct = (_goalMl > 0 ? (todayMl / _goalMl) * 100 : 0).round();
    final remainingMl = math.max(0, _goalMl - todayMl);
    final goalReached = _goalMl > 0 && todayMl >= _goalMl;
    final windowPts = _windowDailyTotals;

    return Scaffold(
      backgroundColor: c.scaffold,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // Centered top bar aligned across all metric pages
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
                            'Water',
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
                      color: _waterBlue,
                      onRefresh: _load,
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
                          // Card 1: Daily Hydration + Quick Cup Buttons
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
                                      decoration: const BoxDecoration(
                                        color: _waterBlue,
                                        shape: BoxShape.circle,
                                      ),
                                      child: Center(
                                        child: TempoJiggIcon(
                                          'drop',
                                          variant: JiggIconVariant.solid,
                                          color: Colors.white,
                                          size: 17,
                                          controller: _dropController,
                                          trigger: JiggIconTrigger.appear,
                                          fallbackIcon: CupertinoIcons.drop_fill,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        'Daily hydration',
                                        style: TextStyle(
                                          color: c.textPrimary,
                                          fontSize: 16.5,
                                          fontWeight: FontWeight.w600,
                                          letterSpacing: -0.2,
                                        ),
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: _waterBlue.withValues(
                                          alpha: c.isDark ? 0.18 : 0.13,
                                        ),
                                        borderRadius:
                                            BorderRadius.circular(999),
                                      ),
                                      child: Text(
                                        '$pct%',
                                        style: const TextStyle(
                                          color: _waterBlue,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                          fontFeatures: [
                                            FontFeature.tabularFigures(),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 20),
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.baseline,
                                  textBaseline: TextBaseline.alphabetic,
                                  children: [
                                    Text(
                                      NumberFormat('#,###').format(todayMl),
                                      style: TextStyle(
                                        color: c.textPrimary,
                                        fontSize: 34,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: -1.0,
                                        fontFeatures: const [
                                          FontFeature.tabularFigures(),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      '/ ${NumberFormat('#,###').format(_goalMl)} ml',
                                      style: TextStyle(
                                        color: c.textSecondary,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 14),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(99),
                                  child: TweenAnimationBuilder<double>(
                                    tween: Tween<double>(
                                      begin: 0,
                                      end: progress,
                                    ),
                                    duration: const Duration(milliseconds: 420),
                                    curve: Curves.easeOutCubic,
                                    builder: (_, v, __) =>
                                        LinearProgressIndicator(
                                      value: v,
                                      minHeight: 7,
                                      backgroundColor: c.divider,
                                      valueColor:
                                          const AlwaysStoppedAnimation<Color>(
                                        _waterBlue,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 18),
                                Row(
                                  children: [
                                    for (final ml in [250, 500, 750]) ...[
                                      if (ml != 250) const SizedBox(width: 8),
                                      Expanded(
                                        child: FilledButton.tonal(
                                          style: FilledButton.styleFrom(
                                            backgroundColor: _waterBlue
                                                .withValues(
                                                    alpha:
                                                        c.isDark ? 0.18 : 0.12),
                                            foregroundColor: _waterBlue,
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 11,
                                            ),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(14),
                                            ),
                                          ),
                                          onPressed: () => _quickAddWater(ml),
                                          child: Text(
                                            '+$ml ml',
                                            style: const TextStyle(
                                              fontSize: 13.5,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
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
                                          child: _WaterTrendChart(
                                            points: windowPts,
                                            goalMl: _goalMl.toDouble(),
                                          ),
                                        ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),

                          // Card 2: Daily Target (unified 2-column target card)
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
                                      decoration: const BoxDecoration(
                                        color: _waterBlue,
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
                                        'Daily target',
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
                                            '${NumberFormat('#,###').format(_goalMl)} ml',
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
                                            'Daily goal',
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
                                            goalReached
                                                ? 'Reached'
                                                : '${NumberFormat('#,###').format(remainingMl)} ml',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: goalReached
                                                  ? _waterBlue
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
                                            goalReached
                                                ? 'Target status'
                                                : 'To reach goal',
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

                          // Card 3: Data source (standalone card)
                          AppleCard(
                            borderRadius: 24,
                            padding: EdgeInsets.zero,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(24),
                              onTap: _openHistorySheet,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 16,
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 32,
                                      height: 32,
                                      decoration: const BoxDecoration(
                                        color: _waterBlue,
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        CupertinoIcons.layers_alt_fill,
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
                                          fontWeight: FontWeight.w600,
                                          letterSpacing: -0.15,
                                        ),
                                      ),
                                    ),
                                    if (_allPoints.isNotEmpty) ...[
                                      Text(
                                        '${_allPoints.length}',
                                        style: TextStyle(
                                          color: c.textTertiary,
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.w500,
                                          fontFeatures: const [
                                            FontFeature.tabularFigures(),
                                          ],
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
                            ),
                          ),
                          const SizedBox(height: 14),

                          // Card 4: About (standalone card)
                          AppleCard(
                            borderRadius: 24,
                            padding: EdgeInsets.zero,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(24),
                              onTap: _openAboutSheet,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 16,
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 32,
                                      height: 32,
                                      decoration: const BoxDecoration(
                                        color: _waterBlue,
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        CupertinoIcons.info,
                                        color: Colors.white,
                                        size: 17,
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Text(
                                        'About',
                                        style: TextStyle(
                                          color: c.textPrimary,
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                          letterSpacing: -0.15,
                                        ),
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

class _WaterTrendChart extends StatelessWidget {
  final List<({DateTime date, double ml})> points;
  final double goalMl;

  const _WaterTrendChart({required this.points, required this.goalMl});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    const lineColor = Color(0xFF38BDF8);
    if (points.length < 2) {
      return Container(
        height: 120,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: c.searchBg.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          'Log water across 2+ days to plot your hydration trend',
          textAlign: TextAlign.center,
          style: TextStyle(color: c.textTertiary, fontSize: 13),
        ),
      );
    }

    final maxV = points
        .map((p) => p.ml)
        .fold<double>(goalMl, (a, b) => a > b ? a : b);

    return SizedBox(
      height: 140,
      child: LineChart(
        LineChartData(
          minY: 0,
          maxY: maxV * 1.15,
          extraLinesData: ExtraLinesData(
            horizontalLines: [
              HorizontalLine(
                y: goalMl,
                color: lineColor.withValues(alpha: 0.4),
                strokeWidth: 1.2,
                dashArray: const [4, 4],
              ),
            ],
          ),
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
                    lineColor.withValues(alpha: 0.25),
                    lineColor.withValues(alpha: 0.0),
                  ],
                ),
              ),
              spots: List.generate(
                points.length,
                (i) => FlSpot(i.toDouble(), points[i].ml),
              ),
            ),
          ],
        ),
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      ),
    );
  }
}
