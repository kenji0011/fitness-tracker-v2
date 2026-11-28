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
import '../widgets/bitchord_segmented_slider.dart';
import '../widgets/bmi_detail_popup.dart';
import '../widgets/ios_popover_menu.dart';
import '../widgets/ios_stretch_sheet.dart';
import '../widgets/liquid_glass_surface.dart';
import '../widgets/tempo_morph_calendar.dart';
import '../widgets/tempo_morph_route.dart';
import '../widgets/tempo_sliver_header.dart';
import 'history_calendar_screen.dart';
import 'weight_unit_screen.dart';

class WeightDetailScreen extends StatefulWidget {
  const WeightDetailScreen({super.key});

  @override
  State<WeightDetailScreen> createState() => _WeightDetailScreenState();
}

class _WeightDetailScreenState extends State<WeightDetailScreen> {
  static const Color _weightGreen = Color(0xFF4FD065);
  static const List<String> _tabs = ['Latest', 'Week', 'M', 'Y'];
  static const double _kgToLb = 2.20462262;

  final TempoRustDb _db = TempoRustDb.instance;
  final GlobalKey _moreButtonKey = GlobalKey();
  final GlobalKey _dateButtonKey = GlobalKey();

  int _selectedTab = 0; // 0 = Latest, 1 = Week, 2 = M, 3 = Y
  DateTime _anchorDate = DateTime.now();
  List<BodyMetricPoint> _allPoints = [];
  double? _customTargetKg;
  String _unit = 'kg';
  bool _loading = true;

  double _toDisplay(double kg) => _unit == 'lb' ? kg * _kgToLb : kg;
  double _fromDisplay(double displayVal) =>
      _unit == 'lb' ? displayVal / _kgToLb : displayVal;

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
      _db.getBodyMetricHistory(pid, 'weight', limit: 365),
      _db.getSetting('weight_target_kg_$pid'),
      _db.getSetting('weight_unit_$pid'),
    ]);
    if (!mounted) return;

    final pts = (results[0] as List<BodyMetricPoint>)
      ..sort((a, b) => a.recordedAt.compareTo(b.recordedAt));
    final savedTarget = double.tryParse((results[1] as String?) ?? '');
    final savedUnit = results[2] as String?;

    setState(() {
      _allPoints = pts;
      _customTargetKg = (savedTarget != null && savedTarget > 0)
          ? savedTarget
          : null;
      _unit = savedUnit == 'lb' ? 'lb' : 'kg';
      _loading = false;
    });
  }

  /// End-of-day cutoff for `_anchorDate`.
  DateTime get _anchorEnd => DateTime(
        _anchorDate.year,
        _anchorDate.month,
        _anchorDate.day,
        23,
        59,
        59,
      );

  /// Points recorded on or before `_anchorDate`.
  List<BodyMetricPoint> get _pointsUpToAnchor =>
      _allPoints.where((p) => !p.recordedAt.toLocal().isAfter(_anchorEnd)).toList();

  /// Points filtered for the active tab window (`Week`, `M`, `Y`).
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

  double _currentWeight(LocalProfile? profile) {
    final upTo = _pointsUpToAnchor;
    if (upTo.isNotEmpty) return upTo.last.value;
    return profile?.weightKg ?? 0.0;
  }

  DateTime? get _latestRecordedDate {
    final upTo = _pointsUpToAnchor;
    return upTo.isNotEmpty ? upTo.last.recordedAt.toLocal() : null;
  }

  /// Computes weight delta compared to ~28 days prior (or earliest available entry).
  ({double? delta, String caption}) _comparisonDelta(double currentWeight) {
    final upTo = _pointsUpToAnchor;
    if (upTo.length < 2 || currentWeight <= 0) {
      return (delta: null, caption: 'Compared with 28 days ago');
    }

    final latestDt = upTo.last.recordedAt.toLocal();
    final targetDays = _selectedTab == 1
        ? 7
        : (_selectedTab == 3 ? 365 : 28);
    final targetDate = latestDt.subtract(Duration(days: targetDays));

    // Find entry closest to targetDate (excluding the latest point itself)
    BodyMetricPoint baseline = upTo.first;
    int bestDiff =
        (baseline.recordedAt.toLocal().difference(targetDate).inHours).abs();
    for (int i = 0; i < upTo.length - 1; i++) {
      final pt = upTo[i];
      final diff =
          (pt.recordedAt.toLocal().difference(targetDate).inHours).abs();
      if (diff < bestDiff) {
        bestDiff = diff;
        baseline = pt;
      }
    }

    final actualDays =
        latestDt.difference(baseline.recordedAt.toLocal()).inDays;
    final caption = actualDays >= 20 && actualDays <= 35
        ? 'Compared with 28 days ago'
        : (actualDays <= 0
            ? 'Compared with earlier today'
            : 'Compared with $actualDays ${actualDays == 1 ? 'day' : 'days'} ago');

    return (delta: currentWeight - baseline.value, caption: caption);
  }

  double _suggestedWeight(LocalProfile? profile) {
    if (_customTargetKg != null && _customTargetKg! > 0) {
      return _customTargetKg!;
    }
    final hCm = profile?.heightCm ?? 0;
    if (hCm <= 0) return 0;
    final hM = hCm / 100.0;
    // Healthy midpoint BMI (21.7)
    return 21.7 * hM * hM;
  }

  double _bmiFor(double weightKg, LocalProfile? profile) {
    final hCm = profile?.heightCm ?? 0;
    if (weightKg <= 0 || hCm <= 0) return 0;
    final hM = hCm / 100.0;
    return weightKg / (hM * hM);
  }

  Future<void> _pickAnchorDate() async {
    HapticFeedback.selectionClick();
    final recordedKeys = _allPoints
        .map((p) => DateFormat('yyyy-MM-dd').format(p.recordedAt.toLocal()))
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

  Future<void> _openAddWeightSheet() async {
    final pid = context.read<ActiveProfileProvider>().activeProfileId;
    final profile = context.read<ActiveProfileProvider>().activeProfile;
    if (pid == null) return;

    final isLb = _unit == 'lb';
    final minVal = isLb ? 44.0 : 20.0;
    final maxVal = isLb ? 770.0 : 350.0;
    final step = isLb ? 0.2 : 0.1;

    double initialKg = _currentWeight(profile);
    if (initialKg <= 0) initialKg = 65.0;
    final initialVal = _toDisplay(initialKg);

    final ctrl = TextEditingController(text: initialVal.toStringAsFixed(2));
    DateTime selectedDate = _anchorDate;
    final datePillKey = GlobalKey();

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
              final next = (cur + delta).clamp(minVal, maxVal);
              ctrl.text = next.toStringAsFixed(2);
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
                  Row(
                    children: [
                      const _GreenCircleBadge(
                        icon: CupertinoIcons.gauge,
                        color: _weightGreen,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Add weight',
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
                          tooltip: 'Decrease weight',
                          onPressed: () => adjust(-step),
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
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                  decimal: true,
                                ),
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
                                _unit,
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
                          tooltip: 'Increase weight',
                          onPressed: () => adjust(step),
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
                        accentColor: _weightGreen,
                        sourceBorderRadius: 18,
                      );
                      if (d != null) {
                        setModalState(() => selectedDate = d);
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
                  const SizedBox(height: 18),
                  TempoBouncyButton(
                    onPressed: () async {
                      HapticFeedback.lightImpact();
                      final val = double.tryParse(ctrl.text.trim());
                      if (val == null || val < minVal || val > maxVal) return;
                      final kgVal = _fromDisplay(val);
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
                        metricType: 'weight',
                        value: kgVal,
                        recordedAt: recorded,
                      );
                      if (ctx.mounted) Navigator.of(ctx).pop(true);
                    },
                    child: const Text('Save weight'),
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

  Future<void> _openUnitScreen() async {
    final pid = context.read<ActiveProfileProvider>().activeProfileId;
    final picked = await pushTempoMorphRoute<String>(
      context: context,
      sourceKey: _moreButtonKey,
      sourceBorderRadius: 999,
      builder: (_) => WeightUnitScreen(initialUnit: _unit),
    );
    if (picked != null && picked != _unit && mounted) {
      if (pid != null) {
        await _db.setSetting('weight_unit_$pid', picked);
      }
      if (!mounted) return;
      setState(() => _unit = picked);
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
          onTap: _openAddWeightSheet,
        ),
        TempoPopoverAction(
          label: 'Unit',
          onTap: _openUnitScreen,
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
                  const _GreenCircleBadge(
                    icon: CupertinoIcons.gauge,
                    color: _weightGreen,
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
                'Body weight records your scale measurements over time so you can follow gradual shifts rather than day-to-day fluctuations.',
                style: TextStyle(
                  color: mc.textSecondary,
                  fontSize: 14.5,
                  height: 1.55,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Weighing yourself under similar conditions, such as in the morning, gives a clearer picture of your long-term progress.',
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

  String _formatDateLabel(DateTime dt) {
    final now = DateTime.now();
    if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
      return 'Today';
    }
    return DateFormat('MMM d, yyyy').format(dt);
  }

  void _openBodyCompositionSheet(LocalProfile? profile, double weightKg) {
    final bmi = _bmiFor(weightKg, profile);
    final hCm = profile?.heightCm ?? 0;
    showBmiDetailPopup(
      context: context,
      bmi: bmi,
      heightCm: hCm,
      weightPoints: _pointsUpToAnchor,
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
                          'No weight records yet. Tap + to add an entry.',
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
                                '${_toDisplay(pt.value).toStringAsFixed(2)} $_unit',
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
    final currentKg = _currentWeight(profile);
    final latestDate = _latestRecordedDate;
    final comparison = _comparisonDelta(currentKg);
    final suggestedKg = _suggestedWeight(profile);
    final bmi = _bmiFor(currentKg, profile);
    final windowPts = _windowPoints;

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
                            'Weight',
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

            // Main scrollable cards
            Expanded(
              child: _loading
                  ? Center(child: CupertinoActivityIndicator(color: c.accent))
                  : RefreshIndicator(
                      color: _weightGreen,
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
                          // Card 1: Weight management (+ animated trend chart on Week/M/Y)
                          AppleCard(
                            borderRadius: 24,
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const _GreenCircleBadge(
                                      icon: CupertinoIcons.gauge,
                                      color: _weightGreen,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        'Weight management',
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
                                        color: _weightGreen.withValues(
                                          alpha: c.isDark ? 0.18 : 0.13,
                                        ),
                                        borderRadius:
                                            BorderRadius.circular(999),
                                      ),
                                      child: Text(
                                        _unit,
                                        style: const TextStyle(
                                          color: _weightGreen,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
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
                                                  currentKg > 0
                                                      ? _toDisplay(currentKg)
                                                          .toStringAsFixed(2)
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
                                            comparison.delta != null
                                                ? '${comparison.delta! > 0 ? '+' : ''}${_toDisplay(comparison.delta!).toStringAsFixed(2)} $_unit'
                                                : '0.00 $_unit',
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

                                // Animated Trend Graph when viewing Week / M / Y
                                AnimatedSize(
                                  duration: const Duration(milliseconds: 280),
                                  curve: Curves.easeOutCubic,
                                  child: _selectedTab == 0
                                      ? const SizedBox.shrink()
                                      : Padding(
                                          padding:
                                              const EdgeInsets.only(top: 22),
                                          child: _WeightTrendChart(
                                            points: windowPts,
                                            lineColor: _weightGreen,
                                            unit: _unit,
                                            factor: _unit == 'lb'
                                                ? _kgToLb
                                                : 1.0,
                                          ),
                                        ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),

                          // Card 2: Body composition
                          AppleCard(
                            borderRadius: 24,
                            padding: const EdgeInsets.all(20),
                            onTap: () =>
                                _openBodyCompositionSheet(profile, currentKg),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const _GreenCircleBadge(
                                      icon: Icons.accessibility_new_rounded,
                                      color: _weightGreen,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        'Body composition',
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
                                                suggestedKg > 0
                                                    ? _toDisplay(suggestedKg)
                                                        .toStringAsFixed(2)
                                                    : '--',
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
                                              if (suggestedKg > 0) ...[
                                                const SizedBox(width: 3),
                                                Text(
                                                  _unit,
                                                  style: TextStyle(
                                                    color: c.textSecondary,
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            _customTargetKg != null
                                                ? 'Target'
                                                : 'Suggested',
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
                                            bmi > 0
                                                ? bmi.toStringAsFixed(1)
                                                : '--',
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
                                          const SizedBox(height: 4),
                                          Text(
                                            'BMI',
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
                                    const _GreenCircleBadge(
                                      icon: CupertinoIcons.layers_alt_fill,
                                      color: _weightGreen,
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
                                    const _GreenCircleBadge(
                                      icon: CupertinoIcons.info,
                                      color: _weightGreen,
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

class _WeightTrendChart extends StatelessWidget {
  final List<BodyMetricPoint> points;
  final Color lineColor;
  final String unit;
  final double factor;

  const _WeightTrendChart({
    required this.points,
    required this.lineColor,
    required this.unit,
    required this.factor,
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
              ? 'No weight entries in this timeframe'
              : 'Add one more entry in this timeframe to plot a trend',
          textAlign: TextAlign.center,
          style: TextStyle(color: c.textTertiary, fontSize: 13),
        ),
      );
    }

    final vals = points.map((p) => p.value * factor).toList();
    final minV = vals.reduce((a, b) => a < b ? a : b);
    final maxV = vals.reduce((a, b) => a > b ? a : b);
    final pad = ((maxV - minV) * 0.25).clamp(1.0, 10.0);

    return Column(
      children: [
        SizedBox(
          height: 146,
          child: LineChart(
            LineChartData(
              minY: minV - pad,
              maxY: maxV + pad,
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
                          '${s.y.toStringAsFixed(2)} $unit',
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
              'Min ${minV.toStringAsFixed(1)} · Max ${maxV.toStringAsFixed(1)} $unit',
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

class _GreenCircleBadge extends StatelessWidget {
  final IconData icon;
  final Color color;

  const _GreenCircleBadge({required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: Icon(icon, color: Colors.white, size: 17),
    );
  }
}
