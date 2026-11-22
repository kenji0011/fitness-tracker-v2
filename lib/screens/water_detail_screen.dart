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

  Future<void> _load() async {
    final pid = context.read<ActiveProfileProvider>().activeProfileId;
    if (pid == null) return;
    setState(() => _loading = true);

    final results = await Future.wait([
      _db.getBodyMetricHistory(pid, 'water', limit: 365),
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

    final now = DateTime.now();
    final recorded = DateTime(
      _anchorDate.year,
      _anchorDate.month,
      _anchorDate.day,
      now.hour,
      now.minute,
    );
    await _db.logBodyMetric(
      profileId: pid,
      metricType: 'water',
      value: ml.toDouble(),
      recordedAt: recorded,
    );
    provider.notifyDataChanged();
    await _load();
    if (mounted) {
      showTempoToast(context, '+$ml ml logged');
    }
  }

  Future<void> _pickAnchorDate() async {
    HapticFeedback.selectionClick();
    final recordedKeys = _allPoints
        .map((p) => _dayKey(p.recordedAt.toLocal()))
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

  Future<void> _openAddCustomWaterSheet() async {
    final ctrl = TextEditingController(text: '250');
    DateTime selectedDate = _anchorDate;

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
              MediaQuery.viewInsetsOf(ctx).bottom + 24,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Add water',
                  style: TextStyle(
                    color: mc.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    _WaterStepper(
                      icon: CupertinoIcons.minus,
                      onTap: () => adjust(-50),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: ctrl,
                        textAlign: TextAlign.center,
                        keyboardType: TextInputType.number,
                        style: TextStyle(
                          color: mc.textPrimary,
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                        decoration: InputDecoration(
                          suffixText: 'ml',
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
                    _WaterStepper(
                      icon: CupertinoIcons.add,
                      onTap: () => adjust(50),
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
                    onPressed: () {
                      final val = int.tryParse(ctrl.text.trim());
                      if (val == null || val < 50 || val > 5000) return;
                      Navigator.of(ctx).pop(val);
                    },
                    child: const Text(
                      'Save water',
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
      ),
    );

    ctrl.dispose();
    if (savedMl != null && mounted) {
      final provider = context.read<ActiveProfileProvider>();
      final pid = provider.activeProfileId;
      if (pid == null) return;
      final now = DateTime.now();
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
        ),
      );
      provider.notifyDataChanged();
      await _load();
      if (mounted) showTempoToast(context, '+$savedMl ml logged');
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
                  'Daily water goal',
                  style: TextStyle(
                    color: mc.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 16),
                Center(
                  child: Text(
                    '${NumberFormat('#,###').format(tempGoal)} ml',
                    style: TextStyle(
                      color: mc.textPrimary,
                      fontSize: 32,
                      fontWeight: FontWeight.w700,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
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
                const SizedBox(height: 12),
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
                    onPressed: () => Navigator.of(ctx).pop(tempGoal),
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
                          'No water logs yet. Tap +250 ml to start.',
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
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      DateFormat('MM/dd/yyyy')
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
      actions: [
        TempoPopoverAction(
          label: 'All data',
          onTap: () => _openHistorySheet(title: 'All data'),
        ),
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

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final todayMl = _anchorDayTotalMl.round();
    final progress = (_goalMl > 0 ? todayMl / _goalMl : 0.0).clamp(0.0, 1.0);
    final pct = (_goalMl > 0 ? (todayMl / _goalMl) * 100 : 0).round();
    final windowPts = _windowDailyTotals;

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
                          'Water',
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

            Padding(
              padding: const EdgeInsets.fromLTRB(18, 2, 18, 16),
              child: _WaterSegmentBar(
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
                      color: _waterBlue,
                      onRefresh: _load,
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(18, 0, 18, 40),
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
                                      child: const Icon(
                                        CupertinoIcons.drop_fill,
                                        color: Colors.white,
                                        size: 17,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Text(
                                      'Daily hydration',
                                      style: TextStyle(
                                        color: c.textPrimary,
                                        fontSize: 16.5,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const Spacer(),
                                    Text(
                                      '$pct%',
                                      style: TextStyle(
                                        color: _waterBlue,
                                        fontSize: 14.5,
                                        fontWeight: FontWeight.w700,
                                        fontFeatures: const [
                                          FontFeature.tabularFigures(),
                                        ],
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
                                const SizedBox(height: 12),
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
                                      minHeight: 8,
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

                          // Card 2: Daily Target
                          AppleCard(
                            borderRadius: 24,
                            padding: const EdgeInsets.all(20),
                            onTap: _openGoalSheet,
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
                                    CupertinoIcons.scope,
                                    color: Colors.white,
                                    size: 17,
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Daily goal',
                                        style: TextStyle(
                                          color: c.textPrimary,
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      Text(
                                        '${NumberFormat('#,###').format(_goalMl)} ml per day',
                                        style: TextStyle(
                                          color: c.textTertiary,
                                          fontSize: 13,
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
                                  onTap: _openHistorySheet,
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
                                          decoration: const BoxDecoration(
                                            color: _waterBlue,
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
                                  onTap: _openAddCustomWaterSheet,
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

class _WaterSegmentBar extends StatelessWidget {
  final List<String> tabs;
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  const _WaterSegmentBar({
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

class _WaterStepper extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _WaterStepper({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(color: c.searchBg, shape: BoxShape.circle),
        child: Icon(icon, color: c.textPrimary, size: 20),
      ),
    );
  }
}
