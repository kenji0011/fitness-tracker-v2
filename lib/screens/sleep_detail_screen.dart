import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:jiggicons/jiggicons.dart';
import 'package:provider/provider.dart';

import '../models/local_profile.dart';
import '../services/active_profile_provider.dart';
import '../services/tempo_rust_db.dart';
import '../theme/app_colors.dart';
import '../widgets/ios_popover_menu.dart';
import '../widgets/ios_stretch_sheet.dart';
import '../widgets/liquid_glass_surface.dart';
import '../widgets/tempo_jigg_icon.dart';
import '../widgets/tempo_morph_route.dart';
import '../widgets/tempo_sliver_header.dart';
import 'history_calendar_screen.dart';

class SleepDetailScreen extends StatefulWidget {
  const SleepDetailScreen({super.key});

  @override
  State<SleepDetailScreen> createState() => _SleepDetailScreenState();
}

class _SleepDetailScreenState extends State<SleepDetailScreen> {
  static const Color _sleepPurple = Color(0xFF6B63F6);
  static const List<String> _tabs = ['Latest', 'Week', 'M', 'Y'];

  final TempoRustDb _db = TempoRustDb.instance;
  final GlobalKey _moreButtonKey = GlobalKey();

  int _selectedTab = 0; // 0 = Latest, 1 = Week, 2 = M, 3 = Y
  DateTime _anchorDate = DateTime.now();
  List<BodyMetricPoint> _allPoints = [];
  double _goalHours = 8.0;
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
      _db.getBodyMetricHistory(pid, 'sleep', limit: 365),
      _db.getSetting('sleep_goal_hrs_$pid'),
    ]);
    if (!mounted) return;

    final pts = (results[0] as List<BodyMetricPoint>)
      ..sort((a, b) => a.recordedAt.compareTo(b.recordedAt));
    final savedGoal = double.tryParse((results[1] as String?) ?? '');

    setState(() {
      _allPoints = pts;
      _goalHours = (savedGoal != null && savedGoal >= 4.0 && savedGoal <= 12.0)
          ? savedGoal
          : 8.0;
      _loading = false;
    });
  }

  DateTime get _anchorEnd => DateTime(
        _anchorDate.year,
        _anchorDate.month,
        _anchorDate.day,
        23,
        59,
        59,
      );

  List<BodyMetricPoint> get _pointsUpToAnchor => _allPoints
      .where((p) => !p.recordedAt.toLocal().isAfter(_anchorEnd))
      .toList();

  List<BodyMetricPoint> get _windowPoints {
    final upTo = _pointsUpToAnchor;
    if (_selectedTab == 0) return upTo;
    final days = _selectedTab == 1 ? 7 : (_selectedTab == 2 ? 30 : 365);
    final start = DateTime(
      _anchorDate.year,
      _anchorDate.month,
      _anchorDate.day,
    ).subtract(Duration(days: days - 1));
    return upTo.where((p) => !p.recordedAt.toLocal().isBefore(start)).toList();
  }

  double _currentSleep(LocalProfile? profile) {
    final upTo = _pointsUpToAnchor;
    if (upTo.isNotEmpty) return upTo.last.value;
    return profile?.sleepHours ?? 0.0;
  }

  DateTime? get _latestRecordedDate {
    final upTo = _pointsUpToAnchor;
    return upTo.isNotEmpty ? upTo.last.recordedAt.toLocal() : null;
  }

  ({double? delta, String caption}) _comparisonDelta(double currentHours) {
    final upTo = _pointsUpToAnchor;
    if (upTo.length < 2 || currentHours <= 0) {
      return (delta: null, caption: 'Compared with 7-day avg');
    }
    final previous = upTo.sublist(0, upTo.length - 1);
    final recent = previous.length > 7
        ? previous.sublist(previous.length - 7)
        : previous;
    final avg =
        recent.fold<double>(0, (sum, p) => sum + p.value) / recent.length;
    return (
      delta: currentHours - avg,
      caption: recent.length >= 2
          ? 'Compared with ${recent.length}-entry avg'
          : 'Compared with previous night',
    );
  }

  String _sleepLevel(double hrs) {
    if (hrs <= 0) return '--';
    if (hrs < 6.0) return 'Short';
    if (hrs < 7.0) return 'Fair';
    if (hrs <= 9.0) return 'Optimal';
    return 'Long';
  }

  String _sleepAdvice(double hrs) {
    if (hrs <= 0) {
      return 'Log your nightly sleep to track recovery quality and consistency over time.';
    }
    if (hrs < 6.0) {
      return 'Under 6 hours can slow muscle recovery and focus. Aim for an earlier wind-down tonight.';
    }
    if (hrs < 7.0) {
      return 'Slightly below optimal recovery. Adding 30–60 minutes helps boost energy and training output.';
    }
    if (hrs <= 9.0) {
      return 'Great recovery window. Maintaining a steady sleep schedule supports peak performance.';
    }
    return 'Extended sleep can reflect deep recovery after heavy training or accumulated fatigue.';
  }

  String _formatHoursMinutes(double hrs) {
    final totalMins = (hrs * 60).round();
    final h = totalMins ~/ 60;
    final m = totalMins % 60;
    if (m == 0) return '${h}h';
    return '${h}h ${m}m';
  }

  Future<void> _pickAnchorDate() async {
    HapticFeedback.selectionClick();
    final recordedKeys = _allPoints
        .map((p) => DateFormat('yyyy-MM-dd').format(p.recordedAt.toLocal()))
        .toSet();
    final result = await pushTempoMorphRoute<HistoryCalendarSelection>(
      context: context,
      sourceBorderRadius: 16,
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

  Future<void> _openAddSleepSheet() async {
    final pid = context.read<ActiveProfileProvider>().activeProfileId;
    final profile = context.read<ActiveProfileProvider>().activeProfile;
    if (pid == null) return;

    double initialVal = _currentSleep(profile);
    if (initialVal <= 0) initialVal = _goalHours;

    final ctrl = TextEditingController(text: initialVal.toStringAsFixed(1));
    DateTime selectedDate = _anchorDate;
    const presets = [6.0, 7.0, 7.5, 8.0, 9.0];

    final saved = await showTempoSheet<bool>(
      context: context,
      backgroundColor: AppColors.of(context, listen: false).card,
      borderRadius: 28,
      showDragHandle: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final mc = AppColors.of(ctx);
            void adjust(double delta) {
              HapticFeedback.selectionClick();
              final cur = double.tryParse(ctrl.text.trim()) ?? initialVal;
              final next = (cur + delta).clamp(0.5, 16.0);
              ctrl.text = next.toStringAsFixed(1);
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
                    'Add sleep',
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
                      _SleepStepperCircle(
                        icon: CupertinoIcons.minus,
                        onTap: () => adjust(-0.5),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: ctrl,
                          textAlign: TextAlign.center,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          style: TextStyle(
                            color: mc.textPrimary,
                            fontSize: 26,
                            fontWeight: FontWeight.w700,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                          decoration: InputDecoration(
                            suffixText: 'hrs',
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
                      _SleepStepperCircle(
                        icon: CupertinoIcons.add,
                        onTap: () => adjust(0.5),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: presets.map((h) {
                      final active =
                          (double.tryParse(ctrl.text.trim()) ?? -1) == h;
                      return GestureDetector(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          ctrl.text = h.toStringAsFixed(1);
                          setModalState(() {});
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 160),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: active
                                ? _sleepPurple.withValues(alpha: 0.16)
                                : mc.searchBg,
                            borderRadius: BorderRadius.circular(12),
                            border: active
                                ? Border.all(
                                    color: _sleepPurple.withValues(alpha: 0.5),
                                  )
                                : null,
                          ),
                          child: Text(
                            '${h.toStringAsFixed(h == h.roundToDouble() ? 0 : 1)}h',
                            style: TextStyle(
                              color: active ? _sleepPurple : mc.textSecondary,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
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
                      if (d != null) {
                        setModalState(() => selectedDate = d);
                      }
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
                            ),
                          ),
                          const Spacer(),
                          Text(
                            DateFormat('MM/dd/yyyy').format(selectedDate),
                            style: TextStyle(
                              color: mc.textPrimary,
                              fontSize: 14.5,
                              fontWeight: FontWeight.w600,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
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
                        if (val == null || val < 0.5 || val > 16.0) return;
                        final now = DateTime.now();
                        final recorded = DateTime(
                          selectedDate.year,
                          selectedDate.month,
                          selectedDate.day,
                          now.hour,
                          now.minute,
                        );
                        await _db.logBodyMetric(
                          profileId: pid,
                          metricType: 'sleep',
                          value: val,
                          recordedAt: recorded,
                        );
                        if (ctx.mounted) Navigator.of(ctx).pop(true);
                      },
                      child: const Text(
                        'Save sleep',
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
      },
    );

    ctrl.dispose();
    if (saved == true && mounted) {
      await context.read<ActiveProfileProvider>().refreshProfiles();
      await _load();
    }
  }

  Future<void> _openSleepGoalSheet() async {
    final pid = context.read<ActiveProfileProvider>().activeProfileId;
    if (pid == null) return;
    double tempGoal = _goalHours;

    final saved = await showTempoSheet<double>(
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
                  'Sleep goal',
                  style: TextStyle(
                    color: mc.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Most adults recover best between 7 and 9 hours per night.',
                  style: TextStyle(color: mc.textSecondary, fontSize: 13.5),
                ),
                const SizedBox(height: 18),
                Center(
                  child: Text(
                    '${tempGoal.toStringAsFixed(1)} hrs',
                    style: TextStyle(
                      color: mc.textPrimary,
                      fontSize: 32,
                      fontWeight: FontWeight.w700,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                Slider(
                  value: tempGoal,
                  min: 5.0,
                  max: 10.5,
                  divisions: 11,
                  activeColor: _sleepPurple,
                  onChanged: (v) {
                    HapticFeedback.selectionClick();
                    setModalState(() => tempGoal = v);
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
      await _db.setSetting('sleep_goal_hrs_$pid', saved.toStringAsFixed(1));
      if (!mounted) return;
      setState(() => _goalHours = saved);
    }
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
          onTap: _openAddSleepSheet,
        ),
        TempoPopoverAction(
          label: 'Sleep goal',
          onTap: _openSleepGoalSheet,
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
                  const _PurpleCircleBadge(
                    icon: CupertinoIcons.bed_double_fill,
                    color: _sleepPurple,
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
                'Sleep duration tracks how many hours of rest you get each night so you can spot patterns in your recovery and energy.',
                style: TextStyle(
                  color: mc.textSecondary,
                  fontSize: 14.5,
                  height: 1.55,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Most adults recover best with 7 to 9 hours of consistent sleep per night, supporting muscle repair, focus, and workout performance.',
                style: TextStyle(
                  color: mc.textSecondary,
                  fontSize: 14.5,
                  height: 1.55,
                ),
              ),
              const SizedBox(height: 22),
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

  String _formatDateLabel(DateTime dt) {
    final now = DateTime.now();
    if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
      return 'Today';
    }
    return DateFormat('MMM d, yyyy').format(dt);
  }

  void _openSleepQualityPopup(double currentHours) {
    HapticFeedback.selectionClick();
    final c = AppColors.of(context, listen: false);
    final pos = currentHours <= 0
        ? 0.55
        : ((currentHours - 4.0) / 7.0).clamp(0.05, 0.95);

    showTempoSheet<void>(
      context: context,
      backgroundColor: c.isDark ? const Color(0xFF141416) : c.card,
      borderRadius: 28,
      showDragHandle: true,
      builder: (ctx) {
        final mc = AppColors.of(ctx);
        final bottomInset = MediaQuery.paddingOf(ctx).bottom;
        return Padding(
          padding: EdgeInsets.fromLTRB(22, 8, 22, bottomInset + 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          currentHours > 0
                              ? _formatHoursMinutes(currentHours)
                              : '--',
                          style: TextStyle(
                            color: mc.textPrimary,
                            fontSize: 28,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.5,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Duration',
                          style: TextStyle(
                            color: mc.textTertiary,
                            fontSize: 13.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 42,
                    margin: const EdgeInsets.symmetric(horizontal: 18),
                    color: mc.divider,
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _sleepLevel(currentHours),
                          style: TextStyle(
                            color: mc.textPrimary,
                            fontSize: 26,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.4,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Recovery',
                          style: TextStyle(
                            color: mc.textTertiary,
                            fontSize: 13.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Divider(height: 1, color: mc.divider),
              const SizedBox(height: 16),
              LayoutBuilder(
                builder: (_, constraints) {
                  final w = constraints.maxWidth;
                  return Column(
                    children: [
                      SizedBox(
                        height: 30,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            TweenAnimationBuilder<double>(
                              tween: Tween<double>(begin: 0.1, end: pos),
                              duration: const Duration(milliseconds: 500),
                              curve: Curves.easeOutCubic,
                              builder: (_, p, __) => Positioned(
                                left: (w * p - 6).clamp(4.0, w - 16),
                                top: 0,
                                child: Container(
                                  width: 10,
                                  height: 10,
                                  decoration: BoxDecoration(
                                    color: mc.textPrimary,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                            ),
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom: 0,
                              height: 14,
                              child: Row(
                                children: [
                                  Expanded(
                                    flex: 25,
                                    child: Container(
                                      decoration: const BoxDecoration(
                                        color: Color(0xFFF49342),
                                        borderRadius: BorderRadius.horizontal(
                                          left: Radius.circular(8),
                                          right: Radius.circular(1.5),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 2.5),
                                  Expanded(
                                    flex: 20,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF7C648),
                                        borderRadius:
                                            BorderRadius.circular(1.5),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 2.5),
                                  Expanded(
                                    flex: 35,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: _sleepPurple,
                                        borderRadius:
                                            BorderRadius.circular(1.5),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 2.5),
                                  Expanded(
                                    flex: 20,
                                    child: Container(
                                      decoration: const BoxDecoration(
                                        color: Color(0xFF67B7F7),
                                        borderRadius: BorderRadius.horizontal(
                                          left: Radius.circular(1.5),
                                          right: Radius.circular(8),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '6h',
                            style: TextStyle(
                              color: mc.textTertiary,
                              fontSize: 12,
                            ),
                          ),
                          Text(
                            '7h – 9h Optimal',
                            style: TextStyle(
                              color: mc.textSecondary,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            '9h+',
                            style: TextStyle(
                              color: mc.textTertiary,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 16),
              Text(
                _sleepAdvice(currentHours),
                style: TextStyle(
                  color: mc.textSecondary,
                  fontSize: 13.5,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                height: 50,
                child: TextButton(
                  style: TextButton.styleFrom(
                    backgroundColor:
                        mc.isDark ? const Color(0xFF26272B) : mc.searchBg,
                    foregroundColor: mc.textPrimary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    Navigator.of(ctx).pop();
                  },
                  child: Text(
                    'Collapse',
                    style: TextStyle(
                      color: mc.textPrimary,
                      fontSize: 16,
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
                          'No sleep records yet. Tap + to add an entry.',
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
                                        fontFeatures: const [
                                          FontFeature.tabularFigures(),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 2),
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
                                '${pt.value.toStringAsFixed(1)} hrs',
                                style: TextStyle(
                                  color: mc.textPrimary,
                                  fontSize: 16.5,
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

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final profile = context.watch<ActiveProfileProvider>().activeProfile;
    final currentHrs = _currentSleep(profile);
    final latestDate = _latestRecordedDate;
    final comparison = _comparisonDelta(currentHrs);
    final windowPts = _windowPoints;
    final goalPct = currentHrs > 0
        ? ((currentHrs / _goalHours) * 100).round().clamp(0, 150)
        : 0;

    final sleepProgress =
        (currentHrs > 0 && _goalHours > 0) ? (currentHrs / _goalHours).clamp(0.0, 1.0) : 0.0;

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
                            'Sleep',
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

            // 4-Segment Sliding Timeframe Pill (Latest | Week | M | Y)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 2, 18, 16),
              child: _SleepSegmentBar(
                tabs: _tabs,
                selectedIndex: _selectedTab,
                onChanged: (idx) {
                  HapticFeedback.selectionClick();
                  setState(() => _selectedTab = idx);
                },
              ),
            ),

            // Main scrollable cards
            Expanded(
              child: _loading
                  ? Center(child: CupertinoActivityIndicator(color: c.accent))
                  : RefreshIndicator(
                      color: _sleepPurple,
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
                          // Card 1: Sleep duration (+ progress bar + animated trend chart on Week/M/Y)
                          AppleCard(
                            borderRadius: 24,
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const _PurpleCircleBadge(
                                      icon: CupertinoIcons.bed_double_fill,
                                      jiggIconName: 'weather-moon',
                                      color: _sleepPurple,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        'Sleep duration',
                                        style: TextStyle(
                                          color: c.textPrimary,
                                          fontSize: 16.5,
                                          fontWeight: FontWeight.w600,
                                          letterSpacing: -0.2,
                                        ),
                                      ),
                                    ),
                                    if (_goalHours > 0)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: _sleepPurple.withValues(
                                            alpha: c.isDark ? 0.18 : 0.13,
                                          ),
                                          borderRadius:
                                              BorderRadius.circular(999),
                                        ),
                                        child: Text(
                                          '$goalPct%',
                                          style: const TextStyle(
                                            color: _sleepPurple,
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
                                                child: Text(
                                                  currentHrs > 0
                                                      ? currentHrs
                                                          .toStringAsFixed(1)
                                                      : '--',
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    color: c.textPrimary,
                                                    fontSize: 34,
                                                    fontWeight: FontWeight.w700,
                                                    letterSpacing: -1.0,
                                                    fontFeatures: const [
                                                      FontFeature
                                                          .tabularFigures(),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 5),
                                              Text(
                                                'hrs',
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
                                            comparison.delta != null
                                                ? '${comparison.delta! > 0 ? '+' : ''}${comparison.delta!.toStringAsFixed(1)} hrs'
                                                : '0.0 hrs',
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
                                            comparison.caption,
                                            style: TextStyle(
                                              color: c.textTertiary,
                                              fontSize: 13,
                                              height: 1.3,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(99),
                                  child: TweenAnimationBuilder<double>(
                                    tween: Tween<double>(
                                      begin: 0,
                                      end: sleepProgress,
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
                                        _sleepPurple,
                                      ),
                                    ),
                                  ),
                                ),

                                AnimatedSize(
                                  duration: const Duration(milliseconds: 280),
                                  curve: Curves.easeOutCubic,
                                  child: _selectedTab == 0
                                      ? const SizedBox.shrink()
                                      : Padding(
                                          padding:
                                              const EdgeInsets.only(top: 22),
                                          child: _SleepTrendChart(
                                            points: windowPts,
                                            lineColor: _sleepPurple,
                                            goalHours: _goalHours,
                                          ),
                                        ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),

                          // Card 2: Sleep quality & target
                          AppleCard(
                            borderRadius: 24,
                            padding: const EdgeInsets.all(20),
                            onTap: () => _openSleepQualityPopup(currentHrs),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const _PurpleCircleBadge(
                                      icon: CupertinoIcons.moon_stars_fill,
                                      color: _sleepPurple,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        'Sleep quality',
                                        style: TextStyle(
                                          color: c.textPrimary,
                                          fontSize: 16.5,
                                          fontWeight: FontWeight.w600,
                                          letterSpacing: -0.2,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      'Details',
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
                                          Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.baseline,
                                            textBaseline:
                                                TextBaseline.alphabetic,
                                            children: [
                                              Text(
                                                _goalHours.toStringAsFixed(1),
                                                style: TextStyle(
                                                  color: c.textPrimary,
                                                  fontSize: 22,
                                                  fontWeight: FontWeight.w600,
                                                  letterSpacing: -0.4,
                                                  fontFeatures: const [
                                                    FontFeature
                                                        .tabularFigures(),
                                                  ],
                                                ),
                                              ),
                                              const SizedBox(width: 3),
                                              Text(
                                                'hrs',
                                                style: TextStyle(
                                                  color: c.textSecondary,
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            'Target',
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
                                            currentHrs > 0
                                                ? _sleepLevel(currentHrs)
                                                : '--',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: c.textPrimary,
                                              fontSize: 21,
                                              fontWeight: FontWeight.w600,
                                              letterSpacing: -0.4,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            currentHrs > 0
                                                ? '$goalPct% of goal'
                                                : 'Recovery',
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
                              onTap: _openDataSourceSheet,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 16,
                                ),
                                child: Row(
                                  children: [
                                    const _PurpleCircleBadge(
                                      icon: CupertinoIcons.layers_alt_fill,
                                      color: _sleepPurple,
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
                                    const _PurpleCircleBadge(
                                      icon: CupertinoIcons.info,
                                      color: _sleepPurple,
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

class _SleepSegmentBar extends StatelessWidget {
  final List<String> tabs;
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  const _SleepSegmentBar({
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

class _SleepTrendChart extends StatelessWidget {
  final List<BodyMetricPoint> points;
  final Color lineColor;
  final double goalHours;

  const _SleepTrendChart({
    required this.points,
    required this.lineColor,
    required this.goalHours,
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
              ? 'No sleep entries in this timeframe'
              : 'Add one more entry in this timeframe to plot a trend',
          textAlign: TextAlign.center,
          style: TextStyle(color: c.textTertiary, fontSize: 13),
        ),
      );
    }

    final vals = points.map((p) => p.value).toList();
    final minV = vals.reduce((a, b) => a < b ? a : b);
    final maxV = vals.reduce((a, b) => a > b ? a : b);
    final minY = (minV < goalHours ? minV : goalHours) - 1.0;
    final maxY = (maxV > goalHours ? maxV : goalHours) + 1.0;

    return Column(
      children: [
        SizedBox(
          height: 146,
          child: LineChart(
            LineChartData(
              minY: minY.clamp(0.0, 12.0),
              maxY: maxY.clamp(minY + 2.0, 16.0),
              extraLinesData: ExtraLinesData(
                horizontalLines: [
                  HorizontalLine(
                    y: goalHours,
                    color: lineColor.withValues(alpha: 0.35),
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
              lineTouchData: LineTouchData(
                touchTooltipData: LineTouchTooltipData(
                  getTooltipColor: (_) =>
                      c.isDark ? const Color(0xFF2C2C2E) : c.textPrimary,
                  getTooltipItems: (spots) => spots
                      .map(
                        (s) => LineTooltipItem(
                          '${s.y.toStringAsFixed(1)} hrs',
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
              DateFormat('MM/dd').format(points.first.recordedAt.toLocal()),
              style: TextStyle(color: c.textTertiary, fontSize: 11.5),
            ),
            Text(
              'Min ${minV.toStringAsFixed(1)} · Max ${maxV.toStringAsFixed(1)} hrs',
              style: TextStyle(
                color: c.textSecondary,
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            Text(
              DateFormat('MM/dd').format(points.last.recordedAt.toLocal()),
              style: TextStyle(color: c.textTertiary, fontSize: 11.5),
            ),
          ],
        ),
      ],
    );
  }
}

class _PurpleCircleBadge extends StatelessWidget {
  final IconData icon;
  final String? jiggIconName;
  final Color color;

  const _PurpleCircleBadge({
    required this.icon,
    this.jiggIconName,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: Center(
        child: jiggIconName != null
            ? TempoJiggIcon(
                jiggIconName!,
                variant: JiggIconVariant.solid,
                color: Colors.white,
                size: 17,
                trigger: JiggIconTrigger.appear,
                fallbackIcon: icon,
              )
            : Icon(icon, color: Colors.white, size: 17),
      ),
    );
  }
}

class _SleepStepperCircle extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _SleepStepperCircle({required this.icon, required this.onTap});

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
