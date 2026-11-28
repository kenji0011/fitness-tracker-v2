import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/local_profile.dart';
import '../services/active_profile_provider.dart';
import '../services/local_media_service.dart';
import '../services/share_template_service.dart';
import '../services/tempo_rust_db.dart';
import '../theme/app_colors.dart';
import '../widgets/bitchord_segmented_slider.dart';
import '../widgets/ios_stretch_sheet.dart';
import '../widgets/liquid_glass_surface.dart';
import '../widgets/oval_activity_rings.dart';
import '../widgets/tempo_sliver_header.dart';
import '../widgets/tempo_startup_splash.dart';
import '../widgets/tempo_toast.dart';

class _ShareBackgroundPreset {
  final String id;
  final String label;
  final List<Color> colors;
  final Color lineColor;
  final String pattern; // 'track' | 'court' | 'grid' | 'lane' | 'stripes' | 'minimal'

  const _ShareBackgroundPreset({
    required this.id,
    required this.label,
    required this.colors,
    required this.lineColor,
    required this.pattern,
  });
}

/// Share studio launched from the Stats page: supports Day & Month progress
/// posters, curated + custom photo backgrounds, customizable metrics & layout,
/// reusable local templates, direct Save to Gallery, and native Android sharing.
class ProgressShareScreen extends StatefulWidget {
  final DateTime? initialDate;
  final String initialMode; // 'day' | 'month'

  const ProgressShareScreen({
    super.key,
    this.initialDate,
    this.initialMode = 'day',
  });

  @override
  State<ProgressShareScreen> createState() => _ProgressShareScreenState();
}

class _ProgressShareScreenState extends State<ProgressShareScreen> {
  static const double _kgToLb = 2.20462262;
  static const Color _calColor = Color(0xFFF36432);
  static const Color _stepColor = Color(0xFFA6EB3C);
  static const Color _minColor = Color(0xFF56B7FF);
  static const Color _waterColor = Color(0xFF38BDF8);
  static const Color _sleepColor = Color(0xFF8B84FF);
  static const Color _weightColor = Color(0xFF4CD964);
  static const Color _streakColor = Color(0xFFFFB020);

  static const List<_ShareBackgroundPreset> _presets = [
    _ShareBackgroundPreset(
      id: 'track_sunset',
      label: 'Track',
      colors: [Color(0xFF2B1325), Color(0xFF7D2E26), Color(0xFF4E1B16)],
      lineColor: Color(0x66FFFFFF),
      pattern: 'track',
    ),
    _ShareBackgroundPreset(
      id: 'midnight_court',
      label: 'Court',
      colors: [Color(0xFF0B1018), Color(0xFF1D2939), Color(0xFF101826)],
      lineColor: Color(0x3894A3B8),
      pattern: 'court',
    ),
    _ShareBackgroundPreset(
      id: 'emerald_turf',
      label: 'Turf',
      colors: [Color(0xFF15342B), Color(0xFF285947), Color(0xFF112620)],
      lineColor: Color(0x45E2F5EC),
      pattern: 'grid',
    ),
    _ShareBackgroundPreset(
      id: 'ocean_lane',
      label: 'Ocean',
      colors: [Color(0xFF0E2A47), Color(0xFF1B4F7A), Color(0xFF0A1D33)],
      lineColor: Color(0x55E0F2FE),
      pattern: 'lane',
    ),
    _ShareBackgroundPreset(
      id: 'tempo_ember',
      label: 'Tempo',
      colors: [Color(0xFFF36D31), Color(0xFFE24E23), Color(0xFFC53C19)],
      lineColor: Color(0x28FFFFFF),
      pattern: 'stripes',
    ),
    _ShareBackgroundPreset(
      id: 'obsidian_minimal',
      label: 'Minimal',
      colors: [Color(0xFF1E2026), Color(0xFF121317), Color(0xFF0B0C0F)],
      lineColor: Color(0x1EFFFFFF),
      pattern: 'minimal',
    ),
  ];

  final TempoRustDb _db = TempoRustDb.instance;
  final GlobalKey _posterKey = GlobalKey();
  final ScrollController _scrollController = ScrollController();

  late DateTime _selectedDate;
  late String _mode; // 'day' | 'month'
  String _backgroundId = 'track_sunset';
  String? _customPhotoPath;
  String _layout = 'classic'; // 'classic' | 'centered' | 'minimal'
  List<String> _selectedMetrics = List<String>.from(
    ShareMetricOption.defaultMetrics,
  );
  bool _showRings = true;
  bool _showProfile = true;
  bool _showDate = true;
  bool _showBrandBadge = true;
  String _caption = '';
  String? _activeTemplateId;

  bool _loading = true;
  bool _exporting = false;

  LocalProfile? _profile;
  Map<String, LocalDailyActivity> _activityByDay = {};
  Map<String, double> _waterMlByDay = {};
  String _weightUnit = 'kg';
  int _currentStreak = 0;
  List<ProgressShareTemplate> _savedTemplates = const [];

  @override
  void initState() {
    super.initState();
    final base = widget.initialDate ?? DateTime.now();
    _selectedDate = DateTime(base.year, base.month, base.day);
    _mode = widget.initialMode == 'month' ? 'month' : 'day';
    _loadData();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  String _dayKey(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

  Future<void> _loadData() async {
    final provider = context.read<ActiveProfileProvider>();
    final pid = provider.activeProfileId;
    if (pid == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    try {
      final results = await Future.wait([
        _db.getDashboardSummary(pid),
        _db.getDailyActivityHistory(pid, limit: 400),
        _db.getBodyMetricHistory(pid, 'water', limit: 600),
        _db.getSetting('weight_unit_$pid'),
        ShareTemplateService.loadTemplates(pid),
      ]);
      if (!mounted) return;

      final summary = results[0] as LocalDashboardSummary;
      final history = results[1] as List<LocalDailyActivity>;
      final waterPts = results[2] as List<BodyMetricPoint>;
      final savedUnit = results[3] as String?;
      final templates = results[4] as List<ProgressShareTemplate>;

      final actMap = <String, LocalDailyActivity>{};
      for (final a in history) {
        actMap[a.dateKey] = a;
      }
      actMap.putIfAbsent(summary.today.dateKey, () => summary.today);

      final waterMap = <String, double>{};
      for (final pt in waterPts) {
        final k = _dayKey(pt.recordedAt.toLocal());
        waterMap[k] = (waterMap[k] ?? 0) + pt.value;
      }

      setState(() {
        _profile = summary.profile;
        _currentStreak = summary.currentStreak;
        _activityByDay = actMap;
        _waterMlByDay = waterMap;
        _weightUnit = savedUnit == 'lb' ? 'lb' : 'kg';
        _savedTemplates = templates;
        _loading = false;
      });
    } catch (e) {
      debugPrint('Failed to load share data: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  LocalDailyActivity _activityFor(DateTime d) {
    final k = _dayKey(d);
    return _activityByDay[k] ?? LocalDailyActivity(dateKey: k);
  }

  int get _calGoal => (_profile?.dailyCaloriesGoal ?? 600).clamp(100, 10000);
  int get _stepGoal => (_profile?.dailyStepsGoal ?? 7000).clamp(500, 100000);
  int get _minGoal => (_profile?.dailyMinutesGoal ?? 60).clamp(10, 600);

  ({
    int totalCalories,
    int totalSteps,
    int totalMinutes,
    double totalWaterMl,
    int activeDays,
    int goalDays,
    int daysElapsed,
  }) _monthSummary() {
    final year = _selectedDate.year;
    final month = _selectedDate.month;
    final daysInMonth = DateUtils.getDaysInMonth(year, month);
    final now = DateTime.now();
    final isCurrentMonth = year == now.year && month == now.month;
    final elapsed = isCurrentMonth ? now.day.clamp(1, daysInMonth) : daysInMonth;

    int cals = 0;
    int steps = 0;
    int mins = 0;
    double water = 0;
    int activeDays = 0;
    int goalDays = 0;

    for (int d = 1; d <= daysInMonth; d++) {
      final date = DateTime(year, month, d);
      final key = _dayKey(date);
      final act = _activityByDay[key];
      final w = _waterMlByDay[key] ?? 0;
      water += w;
      if (act != null) {
        cals += act.calories;
        steps += act.steps;
        mins += act.minutes;
        if (act.calories > 0 || act.steps > 0 || act.minutes > 0) {
          activeDays++;
        }
        if (act.calories >= _calGoal ||
            act.steps >= _stepGoal ||
            act.minutes >= _minGoal) {
          goalDays++;
        }
      }
    }

    return (
      totalCalories: cals,
      totalSteps: steps,
      totalMinutes: mins,
      totalWaterMl: water,
      activeDays: activeDays,
      goalDays: goalDays,
      daysElapsed: elapsed,
    );
  }

  _ShareBackgroundPreset get _activePreset {
    final fallbackId = _mode == 'month' ? 'tempo_ember' : 'track_sunset';
    return _presets.firstWhere(
      (p) => p.id == _backgroundId,
      orElse: () => _presets.firstWhere((p) => p.id == fallbackId),
    );
  }

  void _applyTemplate(ProgressShareTemplate t) {
    HapticFeedback.selectionClick();
    setState(() {
      _activeTemplateId = t.id;
      _mode = t.mode;
      _backgroundId = t.backgroundId;
      _customPhotoPath = t.customPhotoPath;
      _layout = t.layout;
      _selectedMetrics = List<String>.from(t.metrics);
      _showRings = t.showRings;
      _showProfile = t.showProfile;
      _showDate = t.showDate;
      _showBrandBadge = t.showBrandBadge;
      _caption = t.caption;
    });
    showTempoToast(context, 'Applied "${t.name}"');
  }

  Future<void> _pickCustomBackgroundPhoto() async {
    final pid = context.read<ActiveProfileProvider>().activeProfileId;
    if (pid == null) return;
    HapticFeedback.selectionClick();
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        imageQuality: 90,
      );
      if (picked == null || !mounted) return;
      final persisted =
          await ShareTemplateService.persistTemplateBackgroundPhoto(
        picked.path,
        pid,
      );
      if (!mounted) return;
      setState(() {
        _backgroundId = 'custom_photo';
        _customPhotoPath = persisted;
      });
    } catch (e) {
      debugPrint('Pick share background failed: $e');
      if (mounted) {
        showTempoToast(context, 'Could not pick photo', isError: true);
      }
    }
  }

  Future<Uint8List?> _capturePosterPng() async {
    final boundary = _posterKey.currentContext?.findRenderObject()
        as RenderRepaintBoundary?;
    if (boundary == null) return null;
    final image = await boundary.toImage(pixelRatio: 3.0);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return byteData?.buffer.asUint8List();
  }

  Future<void> _saveImageToGallery() async {
    if (_exporting) return;
    HapticFeedback.lightImpact();
    setState(() => _exporting = true);
    try {
      await WidgetsBinding.instance.endOfFrame;
      final bytes = await _capturePosterPng();
      if (bytes == null) {
        if (mounted) {
          showTempoToast(context, 'Could not render poster', isError: true);
        }
        return;
      }
      final res = await ShareTemplateService.savePosterToGallery(
        bytes,
        prefix: 'Tempo_${_mode == 'month' ? 'Month' : 'Day'}',
      );
      if (mounted) {
        showTempoToast(context, res.message, isError: !res.ok);
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _sharePosterNative() async {
    if (_exporting) return;
    HapticFeedback.lightImpact();
    setState(() => _exporting = true);
    try {
      await WidgetsBinding.instance.endOfFrame;
      final bytes = await _capturePosterPng();
      if (bytes == null) {
        if (mounted) {
          showTempoToast(context, 'Could not render poster', isError: true);
        }
        return;
      }
      final periodLabel = _mode == 'month'
          ? DateFormat('MMMM yyyy').format(_selectedDate)
          : DateFormat('MMMM d, yyyy').format(_selectedDate);
      final res = await ShareTemplateService.sharePoster(
        bytes,
        prefix: 'Tempo_${_mode == 'month' ? 'Month' : 'Day'}',
        shareText: 'My Tempo fitness stats for $periodLabel',
      );
      if (mounted && !res.ok) {
        showTempoToast(context, res.message, isError: true);
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _openSaveTemplateSheet() async {
    final pid = context.read<ActiveProfileProvider>().activeProfileId;
    if (pid == null) return;
    HapticFeedback.selectionClick();

    final existing = _activeTemplateId != null
        ? _savedTemplates
            .where((t) => t.id == _activeTemplateId)
            .firstOrNull
        : null;
    final defaultName = existing?.name ??
        '${_mode == 'month' ? 'Monthly' : 'Daily'} ${_activePreset.label}';

    final templateName = await showTempoSheet<String>(
      context: context,
      backgroundColor: AppColors.of(context, listen: false).card,
      borderRadius: 28,
      showDragHandle: true,
      builder: (ctx) => _SaveTemplateSheetBody(initialName: defaultName),
    );

    if (templateName == null || !mounted) return;

    final tpl = ProgressShareTemplate(
      id: existing?.name.toLowerCase() == templateName.toLowerCase()
          ? existing!.id
          : '',
      name: templateName,
      mode: _mode,
      backgroundId: _backgroundId,
      customPhotoPath:
          _backgroundId == 'custom_photo' ? _customPhotoPath : null,
      layout: _layout,
      metrics: List<String>.from(_selectedMetrics),
      showRings: _showRings,
      showProfile: _showProfile,
      showDate: _showDate,
      showBrandBadge: _showBrandBadge,
      caption: _caption.trim(),
      updatedAt: DateTime.now(),
    );
    final updated = await ShareTemplateService.saveTemplate(
      profileId: pid,
      template: tpl,
    );
    if (!mounted) return;
    setState(() {
      _savedTemplates = updated;
      _activeTemplateId = updated.first.id;
    });
    showTempoToast(context, 'Template "$templateName" saved');
  }

  Future<void> _deleteSavedTemplate(ProgressShareTemplate tpl) async {
    final pid = context.read<ActiveProfileProvider>().activeProfileId;
    if (pid == null) return;
    HapticFeedback.selectionClick();
    final updated = await ShareTemplateService.deleteTemplate(
      profileId: pid,
      templateId: tpl.id,
    );
    if (!mounted) return;
    setState(() {
      _savedTemplates = updated;
      if (_activeTemplateId == tpl.id) _activeTemplateId = null;
    });
    showTempoToast(context, 'Removed "${tpl.name}"');
  }

  void _framePosterAtTop() {
    if (!_scrollController.hasClients || _scrollController.offset <= 1.0) {
      return;
    }
    _scrollController.animateTo(
      0.0,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  double _computeCustomizePeekHeight(BuildContext ctx) {
    final mq = MediaQuery.of(ctx);
    final screenH = mq.size.height;
    final bottomPad = mq.padding.bottom;
    final minLayoutPeek = 186.0 + math.max(bottomPad, 14.0);
    final posterBox =
        _posterKey.currentContext?.findRenderObject() as RenderBox?;
    if (posterBox != null && posterBox.hasSize) {
      final scrollOffset =
          _scrollController.hasClients ? _scrollController.offset : 0.0;
      final posterBottomAtTop =
          posterBox.localToGlobal(Offset(0, posterBox.size.height)).dy +
              scrollOffset;
      final spaceBelowPoster = screenH - posterBottomAtTop - 10.0;
      final maxComfortable = math.max(minLayoutPeek, 224.0 + bottomPad);
      return spaceBelowPoster.clamp(178.0 + bottomPad, maxComfortable);
    }
    return minLayoutPeek.clamp(178.0, screenH * 0.34);
  }

  Future<void> _openCustomizeSheet() async {
    HapticFeedback.selectionClick();
    final sheetController = TempoSheetController();
    final peekHeight = _computeCustomizePeekHeight(context);
    try {
      await showTempoSheet<void>(
        context: context,
        backgroundColor: AppColors.of(context, listen: false).card,
        borderRadius: 28,
        showDragHandle: true,
        controller: sheetController,
        peekHeight: peekHeight,
        peekScrimAlpha: 0.06,
        builder: (ctx) => _CustomizeTemplateSheetBody(
          initialLayout: _layout,
          initialMetrics: List<String>.from(_selectedMetrics),
          initialShowRings: _showRings,
          initialShowProfile: _showProfile,
          initialShowDate: _showDate,
          initialShowBrandBadge: _showBrandBadge,
          initialCaption: _caption,
          sheetController: sheetController,
          onRequestPosterFraming: _framePosterAtTop,
          onChanged: ({
            required String layout,
            required List<String> metrics,
            required bool showRings,
            required bool showProfile,
            required bool showDate,
            required bool showBrandBadge,
            required String caption,
          }) {
            if (!mounted) return;
            setState(() {
              _layout = layout;
              _selectedMetrics = metrics;
              _showRings = showRings;
              _showProfile = showProfile;
              _showDate = showDate;
              _showBrandBadge = showBrandBadge;
              _caption = caption;
            });
          },
        ),
      );
    } finally {
      sheetController.dispose();
    }
  }

  ({IconData icon, Color color, String label, String value, String unit})
      _metricEntry(String key, LocalDailyActivity act, double dayWaterMl) {
    final p = _profile;
    switch (key) {
      case 'calories':
        return (
          icon: CupertinoIcons.flame_fill,
          color: _calColor,
          label: 'Calories',
          value: NumberFormat('#,###').format(act.calories),
          unit: 'kcal',
        );
      case 'steps':
        return (
          icon: Icons.directions_walk_rounded,
          color: _stepColor,
          label: 'Steps',
          value: NumberFormat('#,###').format(act.steps),
          unit: 'steps',
        );
      case 'minutes':
        return (
          icon: CupertinoIcons.clock_fill,
          color: _minColor,
          label: 'Activity time',
          value: '${act.minutes}',
          unit: 'mins',
        );
      case 'water':
        return (
          icon: CupertinoIcons.drop_fill,
          color: _waterColor,
          label: 'Hydration',
          value: NumberFormat('#,###').format(dayWaterMl.round()),
          unit: 'ml',
        );
      case 'sleep':
        final hrs = p?.sleepHours ?? 0;
        return (
          icon: CupertinoIcons.moon_fill,
          color: _sleepColor,
          label: 'Sleep',
          value: hrs > 0 ? hrs.toStringAsFixed(1) : '0.0',
          unit: 'hrs',
        );
      case 'weight':
        final kg = p?.weightKg ?? 0;
        final w = _weightUnit == 'lb' ? kg * _kgToLb : kg;
        return (
          icon: CupertinoIcons.gauge,
          color: _weightColor,
          label: 'Weight',
          value: w > 0 ? w.toStringAsFixed(1) : '--',
          unit: _weightUnit,
        );
      case 'streak':
      default:
        return (
          icon: CupertinoIcons.sparkles,
          color: _streakColor,
          label: 'Streak',
          value: '$_currentStreak',
          unit: _currentStreak == 1 ? 'day' : 'days',
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final bottomPad = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      backgroundColor: c.scaffold,
      bottomNavigationBar: Container(
        padding: EdgeInsets.fromLTRB(
          20,
          12,
          20,
          math.max(bottomPad, 16),
        ),
        decoration: BoxDecoration(
          color: c.scaffold,
          border: Border(
            top: BorderSide(color: c.divider, width: 0.6),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _ShareActionButton(
              icon: CupertinoIcons.arrow_down_to_line,
              color: const Color(0xFF3B82F6),
              label: 'Save',
              busy: _exporting,
              onTap: _saveImageToGallery,
            ),
            _ShareActionButton(
              icon: CupertinoIcons.bookmark_fill,
              color: const Color(0xFF6366F1),
              label: 'Template',
              onTap: _openSaveTemplateSheet,
            ),
            _ShareActionButton(
              icon: CupertinoIcons.slider_horizontal_3,
              color: c.accent,
              label: 'Customize',
              onTap: _openCustomizeSheet,
            ),
            _ShareActionButton(
              icon: CupertinoIcons.share,
              color: const Color(0xFF22C55E),
              label: 'Share',
              busy: _exporting,
              onTap: _sharePosterNative,
            ),
          ],
        ),
      ),
      body: CustomScrollView(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        slivers: [
          TempoSliverHeader(
            title: 'Share',
            showBackButton: true,
            actions: [
              TempoHeaderAction(
                tooltip: 'Customize template',
                onPressed: _openCustomizeSheet,
                icon: Icon(
                  CupertinoIcons.slider_horizontal_3,
                  size: 19,
                  color: c.textPrimary,
                ),
              ),
            ],
          ),
          if (_loading)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: CupertinoActivityIndicator(color: c.accent),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(18, 6, 18, 24),
              sliver: SliverList.list(
                children: [
                  // Day | Month Segmented Switcher
                  _ShareModeSwitcher(
                    mode: _mode,
                    onChanged: (nextMode) {
                      HapticFeedback.selectionClick();
                      setState(() {
                        _mode = nextMode;
                        if (nextMode == 'month' &&
                            _backgroundId == 'track_sunset') {
                          _backgroundId = 'tempo_ember';
                        } else if (nextMode == 'day' &&
                            _backgroundId == 'tempo_ember') {
                          _backgroundId = 'track_sunset';
                        }
                      });
                    },
                  ),
                  const SizedBox(height: 18),

                  // Live Capturable Poster Preview
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 380),
                      child: RepaintBoundary(
                        key: _posterKey,
                        child: _mode == 'day'
                            ? _buildDayPoster()
                            : _buildMonthPoster(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),

                  // Saved Local Templates Strip (if any saved)
                  if (_savedTemplates.isNotEmpty) ...[
                    Row(
                      children: [
                        Text(
                          'Saved templates',
                          style: TextStyle(
                            color: c.textSecondary,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '${_savedTemplates.length} saved',
                          style: TextStyle(
                            color: c.textTertiary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 40,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _savedTemplates.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (_, i) {
                          final tpl = _savedTemplates[i];
                          final isSelected = tpl.id == _activeTemplateId;
                          return GestureDetector(
                            onTap: () => _applyTemplate(tpl),
                            child: Container(
                              padding: const EdgeInsets.fromLTRB(12, 0, 6, 0),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? c.accent.withValues(
                                        alpha: c.isDark ? 0.24 : 0.14,
                                      )
                                    : c.card,
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: isSelected ? c.accent : c.cardBorder,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    tpl.mode == 'month'
                                        ? CupertinoIcons.calendar
                                        : CupertinoIcons.sparkles,
                                    size: 13.5,
                                    color: isSelected
                                        ? c.accent
                                        : c.textSecondary,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    tpl.name,
                                    style: TextStyle(
                                      color: isSelected
                                          ? c.accent
                                          : c.textPrimary,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: () => _deleteSavedTemplate(tpl),
                                    child: Padding(
                                      padding: const EdgeInsets.all(4),
                                      child: Icon(
                                        CupertinoIcons.xmark_circle_fill,
                                        size: 15,
                                        color: c.textTertiary,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Background Thumbnail Picker
                  Text(
                    'Background',
                    style: TextStyle(
                      color: c.textSecondary,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 74,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        // Custom Gallery Photo option
                        GestureDetector(
                          onTap: _pickCustomBackgroundPhoto,
                          child: Container(
                            width: 70,
                            height: 70,
                            margin: const EdgeInsets.only(right: 10),
                            decoration: BoxDecoration(
                              color: c.card,
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: _backgroundId == 'custom_photo'
                                    ? c.accent
                                    : c.cardBorder,
                                width:
                                    _backgroundId == 'custom_photo' ? 2.2 : 1,
                              ),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: _backgroundId == 'custom_photo' &&
                                      _customPhotoPath != null &&
                                      LocalMediaService.fileExistsCached(
                                        _customPhotoPath!,
                                      )
                                  ? Stack(
                                      fit: StackFit.expand,
                                      children: [
                                        Image.file(
                                          File(_customPhotoPath!),
                                          fit: BoxFit.cover,
                                        ),
                                        Container(
                                          color: Colors.black
                                              .withValues(alpha: 0.25),
                                          child: const Icon(
                                            CupertinoIcons.photo_fill,
                                            color: Colors.white,
                                            size: 20,
                                          ),
                                        ),
                                      ],
                                    )
                                  : Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          CupertinoIcons.photo_on_rectangle,
                                          color: c.textSecondary,
                                          size: 22,
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Photo',
                                          style: TextStyle(
                                            color: c.textSecondary,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                            ),
                          ),
                        ),
                        for (final preset in _presets)
                          GestureDetector(
                            onTap: () {
                              HapticFeedback.selectionClick();
                              setState(() => _backgroundId = preset.id);
                            },
                            child: Container(
                              width: 70,
                              height: 70,
                              margin: const EdgeInsets.only(right: 10),
                              padding: const EdgeInsets.all(2.5),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                  color: _backgroundId == preset.id
                                      ? c.accent
                                      : Colors.transparent,
                                  width: 2.2,
                                ),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(14.5),
                                child: _PosterBackgroundCanvas(
                                  preset: preset,
                                  customPhotoPath: null,
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
        ],
      ),
    );
  }

  Widget _buildDayPoster() {
    final act = _activityFor(_selectedDate);
    final dayWater = _waterMlByDay[_dayKey(_selectedDate)] ?? 0;
    final calProgress = (act.calories / _calGoal).clamp(0.0, 1.0);
    final stepProgress = (act.steps / _stepGoal).clamp(0.0, 1.0);
    final minProgress = (act.minutes / _minGoal).clamp(0.0, 1.0);
    final metrics = _selectedMetrics
        .map((k) => _metricEntry(k, act, dayWater))
        .toList();
    final preset = _activePreset;
    final photoPath = _backgroundId == 'custom_photo' ? _customPhotoPath : null;

    return AspectRatio(
      aspectRatio: 0.80,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          fit: StackFit.expand,
          children: [
            _PosterBackgroundCanvas(
              preset: preset,
              customPhotoPath: photoPath,
            ),
            // Subtle bottom-left readability vignette
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.34),
                    Colors.black.withValues(alpha: 0.14),
                    Colors.black.withValues(alpha: 0.56),
                  ],
                  stops: const [0.0, 0.42, 1.0],
                ),
              ),
            ),

            Padding(
              padding: const EdgeInsets.all(22),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                child: KeyedSubtree(
                  key: ValueKey<String>(_layout),
                  child: _layout == 'centered'
                      ? _buildCenteredDayContent(
                          metrics: metrics,
                          calProgress: calProgress,
                          stepProgress: stepProgress,
                          minProgress: minProgress,
                        )
                      : _layout == 'minimal'
                          ? _buildMinimalDayContent(
                              metrics: metrics,
                              calProgress: calProgress,
                              stepProgress: stepProgress,
                              minProgress: minProgress,
                            )
                          : _buildClassicDayContent(
                              metrics: metrics,
                              calProgress: calProgress,
                              stepProgress: stepProgress,
                              minProgress: minProgress,
                            ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPosterHeader({bool centered = false}) {
    final name = _profile?.displayName.trim().isNotEmpty == true
        ? _profile!.displayName
        : 'Tempo Athlete';
    final dateText = _mode == 'month'
        ? '${DateFormat('MMMM yyyy').format(_selectedDate)} · Stats'
        : '${DateFormat('MMMM d, yyyy').format(_selectedDate)} · Stats';

    if (!_showProfile && !_showDate && !_showBrandBadge) {
      return const SizedBox.shrink();
    }

    return Row(
      mainAxisAlignment:
          centered ? MainAxisAlignment.center : MainAxisAlignment.start,
      children: [
        if (_showProfile) ...[
          LocalProfileAvatar(
            name: name,
            avatarPath: _profile?.avatarPath ?? '',
            size: 36,
            borderWidth: 1.6,
            borderColor: Colors.white.withValues(alpha: 0.75),
            showShadow: false,
          ),
          const SizedBox(width: 10),
        ],
        if (_showProfile || _showDate)
          Flexible(
            child: Column(
              crossAxisAlignment: centered
                  ? CrossAxisAlignment.center
                  : CrossAxisAlignment.start,
              children: [
                if (_showProfile)
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                    ),
                  ),
                if (_showDate)
                  Text(
                    dateText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.80),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
              ],
            ),
          ),
        if (!centered && _showBrandBadge) ...[
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.28),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.16),
              ),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TempoDualRingLogo(size: 14),
                SizedBox(width: 5),
                Text(
                  'Tempo',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.1,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildClassicDayContent({
    required List<
            ({IconData icon, Color color, String label, String value, String unit})>
        metrics,
    required double calProgress,
    required double stepProgress,
    required double minProgress,
  }) {
    return Stack(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildPosterHeader(),
            if (_caption.trim().isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                _caption.trim(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.90),
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const Spacer(),
            for (int i = 0; i < metrics.length; i++) ...[
              if (i > 0) const SizedBox(height: 14),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(metrics[i].icon, color: metrics[i].color, size: 16),
                  const SizedBox(width: 6),
                  Text(
                    metrics[i].label,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.88),
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    metrics[i].value,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.8,
                      height: 1.05,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    metrics[i].unit,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.82),
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
        if (_showRings)
          Positioned(
            right: -6,
            bottom: 4,
            child: OvalActivityRings(
              size: 112,
              caloriesProgress: calProgress,
              stepsProgress: stepProgress,
              minutesProgress: minProgress,
              darkModeOverride: true,
              showPinstripes: false,
              showCapIcons: false,
            ),
          ),
      ],
    );
  }

  Widget _buildCenteredDayContent({
    required List<
            ({IconData icon, Color color, String label, String value, String unit})>
        metrics,
    required double calProgress,
    required double stepProgress,
    required double minProgress,
  }) {
    return Column(
      children: [
        _buildPosterHeader(centered: true),
        if (_caption.trim().isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            _caption.trim(),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.90),
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
        const Spacer(),
        if (_showRings)
          OvalActivityRings(
            size: 148,
            caloriesProgress: calProgress,
            stepsProgress: stepProgress,
            minutesProgress: minProgress,
            darkModeOverride: true,
            showPinstripes: true,
            showCapIcons: true,
          ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.34),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
          ),
          child: Row(
            children: [
              for (final m in metrics)
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(m.icon, color: m.color, size: 15),
                      const SizedBox(height: 4),
                      Text(
                        m.value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                      Text(
                        m.unit,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.72),
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMinimalDayContent({
    required List<
            ({IconData icon, Color color, String label, String value, String unit})>
        metrics,
    required double calProgress,
    required double stepProgress,
    required double minProgress,
  }) {
    final hero = metrics.first;
    final rest = metrics.skip(1).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildPosterHeader(),
        const Spacer(),
        if (_caption.trim().isNotEmpty) ...[
          Text(
            _caption.trim().toUpperCase(),
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.74),
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 6),
        ],
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    hero.label,
                    style: TextStyle(
                      color: hero.color,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        hero.value,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 44,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -1.4,
                          height: 1.0,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        hero.unit,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.80),
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (_showRings)
              OvalActivityRings(
                size: 86,
                caloriesProgress: calProgress,
                stepsProgress: stepProgress,
                minutesProgress: minProgress,
                darkModeOverride: true,
                showPinstripes: false,
                showCapIcons: false,
              ),
          ],
        ),
        if (rest.isNotEmpty) ...[
          const SizedBox(height: 18),
          Container(height: 1, color: Colors.white.withValues(alpha: 0.16)),
          const SizedBox(height: 14),
          Row(
            children: [
              for (final m in rest)
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        m.label,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.72),
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${m.value} ${m.unit}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15.5,
                          fontWeight: FontWeight.w700,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildMonthPoster() {
    final summary = _monthSummary();
    final year = _selectedDate.year;
    final month = _selectedDate.month;
    final daysInMonth = DateUtils.getDaysInMonth(year, month);
    final firstWeekday = DateTime(year, month, 1).weekday; // Mon=1..Sun=7
    final leadingBlanks = firstWeekday - 1;
    final totalCells = leadingBlanks + daysInMonth;
    final distKm = (summary.totalSteps * 0.00076);
    final avgCals = summary.daysElapsed > 0
        ? (summary.totalCalories / summary.daysElapsed).round()
        : 0;
    final preset = _activePreset;
    final photoPath = _backgroundId == 'custom_photo' ? _customPhotoPath : null;

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Stack(
        children: [
          Positioned.fill(
            child: _PosterBackgroundCanvas(
              preset: preset,
              customPhotoPath: photoPath,
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.14),
                    Colors.black.withValues(alpha: 0.28),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildPosterHeader(centered: _layout == 'centered'),
                if (_caption.trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    _caption.trim(),
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.90),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                const SizedBox(height: 16),

                // Monthly Totals Hero
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_selectedMetrics.contains('calories')) ...[
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.baseline,
                              textBaseline: TextBaseline.alphabetic,
                              children: [
                                Text(
                                  NumberFormat('#,###')
                                      .format(summary.totalCalories),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 31,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -0.9,
                                    height: 1.05,
                                    fontFeatures: [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'kcal',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.86),
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                            Text(
                              'Daily average: ${NumberFormat('#,###').format(avgCals)} kcal',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.82),
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 12),
                          ],
                          if (_selectedMetrics.contains('steps')) ...[
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.baseline,
                              textBaseline: TextBaseline.alphabetic,
                              children: [
                                Text(
                                  NumberFormat('#,###')
                                      .format(summary.totalSteps),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 28,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -0.8,
                                    height: 1.05,
                                    fontFeatures: [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'steps',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.86),
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                            Text(
                              'Estimated distance: ${distKm.toStringAsFixed(1)} km',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.82),
                                fontSize: 12,
                              ),
                            ),
                          ],
                          if (_selectedMetrics.contains('minutes') ||
                              _selectedMetrics.contains('water')) ...[
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              children: [
                                if (_selectedMetrics.contains('minutes'))
                                  _MonthMiniPill(
                                    label:
                                        '${NumberFormat('#,###').format(summary.totalMinutes)} mins active',
                                  ),
                                if (_selectedMetrics.contains('water'))
                                  _MonthMiniPill(
                                    label:
                                        '${(summary.totalWaterMl / 1000).toStringAsFixed(1)} L water',
                                  ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '${summary.goalDays} ${summary.goalDays == 1 ? 'day' : 'days'}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                        Text(
                          'Goals met',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.82),
                            fontSize: 11.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${summary.activeDays} active',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.85),
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // White Calendar Card with Mini Oval Rings for Every Day of Month
                if (_showRings)
                  Container(
                    padding: const EdgeInsets.fromLTRB(10, 14, 10, 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            for (final d in const [
                              'Mon',
                              'Tue',
                              'Wed',
                              'Thu',
                              'Fri',
                              'Sat',
                              'Sun',
                            ])
                              Expanded(
                                child: Center(
                                  child: Text(
                                    d,
                                    style: const TextStyle(
                                      color: Color(0xFF4B5563),
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: totalCells,
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 7,
                            mainAxisSpacing: 8,
                            crossAxisSpacing: 2,
                            childAspectRatio: 0.86,
                          ),
                          itemBuilder: (_, idx) {
                            if (idx < leadingBlanks) {
                              return const SizedBox.shrink();
                            }
                            final dayNum = idx - leadingBlanks + 1;
                            final date = DateTime(year, month, dayNum);
                            final act = _activityFor(date);
                            final isFuture = date.isAfter(DateTime.now());
                            return Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                MiniOvalActivityRings(
                                  size: 25,
                                  caloriesProgress: act.calories / _calGoal,
                                  stepsProgress: act.steps / _stepGoal,
                                  minutesProgress: act.minutes / _minGoal,
                                  darkModeOverride: false,
                                  muted: isFuture,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '$dayNum',
                                  style: TextStyle(
                                    color: isFuture
                                        ? const Color(0xFFB4B9C4)
                                        : const Color(0xFF111827),
                                    fontSize: 11,
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

class _MonthMiniPill extends StatelessWidget {
  final String label;

  const _MonthMiniPill({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _ShareModeSwitcher extends StatelessWidget {
  final String mode;
  final ValueChanged<String> onChanged;

  const _ShareModeSwitcher({required this.mode, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return BitChordSegmentedSlider(
      height: 44,
      fontSize: 14,
      labels: const ['Day', 'Month'],
      selectedIndex: mode == 'month' ? 1 : 0,
      onChanged: (idx) => onChanged(idx == 1 ? 'month' : 'day'),
    );
  }
}

class _ShareActionButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;
  final bool busy;

  const _ShareActionButton({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: busy ? null : onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: Colors.white,
                      ),
                    )
                  : Icon(icon, color: Colors.white, size: 22),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              color: c.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _PosterBackgroundCanvas extends StatelessWidget {
  final _ShareBackgroundPreset preset;
  final String? customPhotoPath;

  const _PosterBackgroundCanvas({
    required this.preset,
    required this.customPhotoPath,
  });

  @override
  Widget build(BuildContext context) {
    if (customPhotoPath != null &&
        LocalMediaService.fileExistsCached(customPhotoPath!)) {
      return Image.file(
        File(customPhotoPath!),
        fit: BoxFit.cover,
      );
    }
    return CustomPaint(
      painter: _PosterBackgroundPainter(preset: preset),
      child: const SizedBox.expand(),
    );
  }
}

class _PosterBackgroundPainter extends CustomPainter {
  final _ShareBackgroundPreset preset;

  const _PosterBackgroundPainter({required this.preset});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final bgPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: preset.colors,
      ).createShader(rect);
    canvas.drawRect(rect, bgPaint);

    final linePaint = Paint()
      ..color = preset.lineColor
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true;

    switch (preset.pattern) {
      case 'track':
        // Athletic running track lanes & subtle warm surface glow
        final glowPaint = Paint()
          ..shader = RadialGradient(
            center: const Alignment(0.6, 0.4),
            radius: 0.9,
            colors: [
              const Color(0xFFFF7A33).withValues(alpha: 0.28),
              Colors.transparent,
            ],
          ).createShader(rect);
        canvas.drawRect(rect, glowPaint);

        linePaint.strokeWidth = math.max(1.2, size.width * 0.008);
        for (int i = 0; i < 4; i++) {
          final yStart = size.height * (0.28 + i * 0.19);
          final yEnd = size.height * (0.12 + i * 0.21);
          canvas.drawLine(
            Offset(-10, yStart),
            Offset(size.width + 10, yEnd),
            linePaint,
          );
        }
        break;
      case 'court':
        // Diagonal dramatic gym shadow bars
        final barPaint = Paint()
          ..color = Colors.white.withValues(alpha: 0.055)
          ..style = PaintingStyle.fill;
        for (int i = -2; i < 8; i++) {
          final x = size.width * (i * 0.18);
          final path = Path()
            ..moveTo(x, 0)
            ..lineTo(x + size.width * 0.07, 0)
            ..lineTo(x - size.width * 0.24, size.height)
            ..lineTo(x - size.width * 0.31, size.height)
            ..close();
          canvas.drawPath(path, barPaint);
        }
        linePaint.strokeWidth = math.max(1.0, size.width * 0.006);
        canvas.drawCircle(
          Offset(size.width * 0.72, size.height * 0.32),
          size.width * 0.26,
          linePaint,
        );
        break;
      case 'grid':
        // Crisp tennis court geometry & net mesh
        linePaint.strokeWidth = math.max(1.0, size.width * 0.006);
        final step = size.width / 8;
        for (double x = 0; x <= size.width; x += step) {
          canvas.drawLine(
            Offset(x, 0),
            Offset(x, size.height * 0.45),
            linePaint..color = preset.lineColor.withValues(alpha: 0.16),
          );
        }
        for (double y = 0; y <= size.height * 0.45; y += step) {
          canvas.drawLine(
            Offset(0, y),
            Offset(size.width, y),
            linePaint,
          );
        }
        linePaint
          ..color = preset.lineColor
          ..strokeWidth = math.max(1.4, size.width * 0.01);
        canvas.drawLine(
          Offset(0, size.height * 0.62),
          Offset(size.width, size.height * 0.48),
          linePaint,
        );
        break;
      case 'lane':
        // Crisp diagonal pool / court accent stripe
        linePaint.strokeWidth = math.max(2.0, size.width * 0.016);
        canvas.drawLine(
          Offset(size.width * 0.12, size.height),
          Offset(size.width * 0.78, 0),
          linePaint,
        );
        linePaint
          ..strokeWidth = math.max(1.0, size.width * 0.006)
          ..color = preset.lineColor.withValues(alpha: 0.35);
        canvas.drawLine(
          Offset(size.width * 0.24, size.height),
          Offset(size.width * 0.90, 0),
          linePaint,
        );
        break;
      case 'stripes':
        // Soft diagonal translucent Tempo signature bands
        final stripePaint = Paint()
          ..color = Colors.white.withValues(alpha: 0.065)
          ..style = PaintingStyle.fill;
        for (int i = -1; i < 6; i++) {
          final x = size.width * (i * 0.28);
          final path = Path()
            ..moveTo(x, 0)
            ..lineTo(x + size.width * 0.13, 0)
            ..lineTo(x - size.width * 0.25, size.height)
            ..lineTo(x - size.width * 0.38, size.height)
            ..close();
          canvas.drawPath(path, stripePaint);
        }
        break;
      case 'minimal':
      default:
        final haloPaint = Paint()
          ..shader = RadialGradient(
            center: const Alignment(0.75, -0.55),
            radius: 0.85,
            colors: [
              const Color(0xFFFF6A24).withValues(alpha: 0.16),
              Colors.transparent,
            ],
          ).createShader(rect);
        canvas.drawRect(rect, haloPaint);
        break;
    }
  }

  @override
  bool shouldRepaint(covariant _PosterBackgroundPainter oldDelegate) =>
      oldDelegate.preset.id != preset.id;
}

class _SaveTemplateSheetBody extends StatefulWidget {
  final String initialName;

  const _SaveTemplateSheetBody({required this.initialName});

  @override
  State<_SaveTemplateSheetBody> createState() => _SaveTemplateSheetBodyState();
}

class _SaveTemplateSheetBodyState extends State<_SaveTemplateSheetBody> {
  late final TextEditingController _nameCtrl;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mc = AppColors.of(context);
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        20,
        10,
        20,
        math.max(
              MediaQuery.viewInsetsOf(context).bottom,
              MediaQuery.paddingOf(context).bottom,
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
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFF6366F1).withValues(
                    alpha: mc.isDark ? 0.22 : 0.13,
                  ),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  CupertinoIcons.bookmark_fill,
                  color: Color(0xFF6366F1),
                  size: 19,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Save Template Locally',
                  style: TextStyle(
                    color: mc.textPrimary,
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
              TempoGlassCircleButton(
                size: 34,
                enableBlur: false,
                enableRefraction: false,
                tooltip: 'Close',
                onPressed: () => Navigator.of(context).pop(),
                icon: Icon(
                  CupertinoIcons.xmark,
                  size: 15,
                  color: mc.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Save your chosen layout, background, and visible metrics so you can reuse this style anytime.',
            style: TextStyle(
              color: mc.textSecondary,
              fontSize: 13.5,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            decoration: BoxDecoration(
              color: mc.searchBg,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: mc.isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.black.withValues(alpha: 0.045),
              ),
            ),
            child: TextField(
              controller: _nameCtrl,
              textCapitalization: TextCapitalization.words,
              style: TextStyle(
                color: mc.textPrimary,
                fontSize: 15.5,
                fontWeight: FontWeight.w600,
              ),
              decoration: InputDecoration(
                hintText: 'Template name',
                hintStyle: TextStyle(color: mc.textTertiary),
                filled: false,
                border: InputBorder.none,
                focusedBorder: InputBorder.none,
                enabledBorder: InputBorder.none,
              ),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: TempoLiquidButton(
                  primary: false,
                  height: 50,
                  borderRadius: 999,
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(
                    'Cancel',
                    style: TextStyle(
                      color: mc.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: TempoBouncyButton(
                  height: 50,
                  onPressed: () {
                    final trimmed = _nameCtrl.text.trim();
                    if (trimmed.isEmpty) return;
                    HapticFeedback.lightImpact();
                    Navigator.of(context).pop(trimmed);
                  },
                  child: const Text('Save template'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CustomizeTemplateSheetBody extends StatefulWidget {
  final String initialLayout;
  final List<String> initialMetrics;
  final bool initialShowRings;
  final bool initialShowProfile;
  final bool initialShowDate;
  final bool initialShowBrandBadge;
  final String initialCaption;
  final TempoSheetController sheetController;
  final VoidCallback onRequestPosterFraming;
  final void Function({
    required String layout,
    required List<String> metrics,
    required bool showRings,
    required bool showProfile,
    required bool showDate,
    required bool showBrandBadge,
    required String caption,
  }) onChanged;

  const _CustomizeTemplateSheetBody({
    required this.initialLayout,
    required this.initialMetrics,
    required this.initialShowRings,
    required this.initialShowProfile,
    required this.initialShowDate,
    required this.initialShowBrandBadge,
    required this.initialCaption,
    required this.sheetController,
    required this.onRequestPosterFraming,
    required this.onChanged,
  });

  @override
  State<_CustomizeTemplateSheetBody> createState() =>
      _CustomizeTemplateSheetBodyState();
}

class _CustomizeTemplateSheetBodyState
    extends State<_CustomizeTemplateSheetBody> {
  late String _layout;
  late List<String> _metrics;
  late bool _showRings;
  late bool _showProfile;
  late bool _showDate;
  late bool _showBrandBadge;
  late final TextEditingController _captionCtrl;
  final ScrollController _bodyScrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    _layout = widget.initialLayout;
    _metrics = List<String>.from(widget.initialMetrics);
    _showRings = widget.initialShowRings;
    _showProfile = widget.initialShowProfile;
    _showDate = widget.initialShowDate;
    _showBrandBadge = widget.initialShowBrandBadge;
    _captionCtrl = TextEditingController(text: widget.initialCaption);
    widget.sheetController.addListener(_onSheetDetentChanged);
  }

  void _onSheetDetentChanged() {
    if (!mounted) return;
    if (widget.sheetController.isPeeking) {
      widget.onRequestPosterFraming();
      if (_bodyScrollCtrl.hasClients && _bodyScrollCtrl.offset > 0.5) {
        _bodyScrollCtrl.animateTo(
          0.0,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        );
      }
    }
    setState(() {});
  }

  void _enterLayoutPreviewPeek() {
    widget.onRequestPosterFraming();
    widget.sheetController.setPeeking(true);
  }

  @override
  void dispose() {
    widget.sheetController.removeListener(_onSheetDetentChanged);
    _bodyScrollCtrl.dispose();
    _captionCtrl.dispose();
    super.dispose();
  }

  void _emit() {
    widget.onChanged(
      layout: _layout,
      metrics: List<String>.from(_metrics),
      showRings: _showRings,
      showProfile: _showProfile,
      showDate: _showDate,
      showBrandBadge: _showBrandBadge,
      caption: _captionCtrl.text,
    );
  }

  void _toggleMetric(String key) {
    HapticFeedback.selectionClick();
    setState(() {
      if (_metrics.contains(key)) {
        if (_metrics.length > 1) {
          _metrics.remove(key);
        }
      } else {
        if (_metrics.length >= 4) {
          _metrics.removeLast();
        }
        _metrics.add(key);
      }
    });
    _emit();
  }

  @override
  Widget build(BuildContext context) {
    final mc = AppColors.of(context);
    final isPeeking = widget.sheetController.isPeeking;
    final bottomInset = math.max(
      MediaQuery.viewInsetsOf(context).bottom,
      MediaQuery.paddingOf(context).bottom,
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 8, 20, bottomInset + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Pinned header with circular icon badge, Reset chip, and Peek/Expand toggle
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: mc.accent.withValues(alpha: mc.isDark ? 0.22 : 0.13),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  CupertinoIcons.slider_horizontal_3,
                  color: mc.accent,
                  size: 19,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Customize Template',
                  style: TextStyle(
                    color: mc.textPrimary,
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.35,
                  ),
                ),
              ),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  HapticFeedback.selectionClick();
                  _captionCtrl.clear();
                  setState(() {
                    _layout = 'classic';
                    _metrics = List<String>.from(
                      ShareMetricOption.defaultMetrics,
                    );
                    _showRings = true;
                    _showProfile = true;
                    _showDate = true;
                    _showBrandBadge = true;
                  });
                  _emit();
                },
                child: TempoTouchLightEffect(
                  borderRadius: 999,
                  intensity: 0.9,
                  child: CustomPaint(
                    foregroundPainter: LiquidGlassRimPainter(
                      borderRadius: 999,
                      isDark: mc.isDark,
                      intensity: 0.72,
                      strokeWidth: 0.85,
                      showTopMeniscus: false,
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: mc.searchBg,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        'Reset',
                        style: TextStyle(
                          color: mc.accent,
                          fontSize: 12.8,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Tooltip(
                message: isPeeking ? 'Expand options' : 'Preview poster',
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    if (!isPeeking) {
                      widget.onRequestPosterFraming();
                    }
                    widget.sheetController.togglePeek();
                  },
                  child: TempoTouchLightEffect(
                    borderRadius: 999,
                    intensity: 0.85,
                    child: CustomPaint(
                      foregroundPainter: LiquidGlassRimPainter(
                        borderRadius: 999,
                        isDark: mc.isDark,
                        intensity: 0.72,
                        strokeWidth: 0.85,
                        showTopMeniscus: false,
                      ),
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: mc.searchBg,
                          shape: BoxShape.circle,
                        ),
                        child: AnimatedRotation(
                          turns: isPeeking ? 0.5 : 0.0,
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOutCubic,
                          child: Icon(
                            CupertinoIcons.chevron_down,
                            size: 14,
                            color: mc.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Scrollable customization controls
          Flexible(
            child: SingleChildScrollView(
              controller: _bodyScrollCtrl,
              physics: isPeeking
                  ? const NeverScrollableScrollPhysics()
                  : const BouncingScrollPhysics(),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Layout Style using unified BitChord Liquid Glass slider.
                  // Interacting lowers the sheet into Preview Peek so the live
                  // Share poster above stays completely visible while comparing.
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 8),
                    child: Text(
                      'LAYOUT STYLE',
                      style: TextStyle(
                        color: mc.textTertiary,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.65,
                      ),
                    ),
                  ),
                  BitChordSegmentedSlider(
                    labels: const ['Classic', 'Centered', 'Minimal'],
                    selectedIndex: switch (_layout) {
                      'centered' => 1,
                      'minimal' => 2,
                      _ => 0,
                    },
                    height: 40,
                    trackColor: mc.searchBg,
                    onInteract: _enterLayoutPreviewPeek,
                    onChanged: (idx) {
                      const layouts = ['classic', 'centered', 'minimal'];
                      setState(() => _layout = layouts[idx]);
                      _emit();
                      _enterLayoutPreviewPeek();
                    },
                  ),
                  const SizedBox(height: 16),

                  // Metrics Shown (tapping while peeking smoothly expands the sheet)
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: isPeeking
                        ? () {
                            HapticFeedback.selectionClick();
                            widget.sheetController.setPeeking(false);
                          }
                        : null,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 4, right: 4, bottom: 8),
                      child: Row(
                        children: [
                          Text(
                            'METRICS SHOWN',
                            style: TextStyle(
                              color: mc.textTertiary,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.65,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '${_metrics.length} of 4 selected',
                            style: TextStyle(
                              color: mc.textSecondary,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: ShareMetricOption.all.map((opt) {
                      final active = _metrics.contains(opt.key);
                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => _toggleMetric(opt.key),
                        child: TempoTouchLightEffect(
                          borderRadius: 999,
                          isAccentSurface: active,
                          intensity: 0.92,
                          scatterGain: 1.05,
                          child: CustomPaint(
                            foregroundPainter: LiquidGlassRimPainter(
                              borderRadius: 999,
                              isDark: mc.isDark,
                              intensity: active ? 1.12 : 0.65,
                              strokeWidth: 0.9,
                              showTopMeniscus: false,
                              tintColor: active ? mc.accent : null,
                            ),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 160),
                              curve: Curves.easeOutCubic,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 9,
                              ),
                              decoration: BoxDecoration(
                                color: active ? mc.accent : mc.searchBg,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                opt.label,
                                style: TextStyle(
                                  color: active ? Colors.white : mc.textPrimary,
                                  fontSize: 13.2,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),

                  // Poster Elements (clean 2x2 Liquid Glass toggle tiles)
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 8),
                    child: Text(
                      'POSTER ELEMENTS',
                      style: TextStyle(
                        color: mc.textTertiary,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.65,
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: _posterToggleTile(
                          c: mc,
                          label: 'Activity rings',
                          active: _showRings,
                          onTap: () {
                            setState(() => _showRings = !_showRings);
                            _emit();
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _posterToggleTile(
                          c: mc,
                          label: 'Profile avatar',
                          active: _showProfile,
                          onTap: () {
                            setState(() => _showProfile = !_showProfile);
                            _emit();
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _posterToggleTile(
                          c: mc,
                          label: 'Date label',
                          active: _showDate,
                          onTap: () {
                            setState(() => _showDate = !_showDate);
                            _emit();
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _posterToggleTile(
                          c: mc,
                          label: 'Tempo mark',
                          active: _showBrandBadge,
                          onTap: () {
                            setState(() => _showBrandBadge = !_showBrandBadge);
                            _emit();
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 8),
                    child: Text(
                      'CUSTOM NOTE',
                      style: TextStyle(
                        color: mc.textTertiary,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.65,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: mc.searchBg,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: mc.isDark
                            ? Colors.white.withValues(alpha: 0.08)
                            : Colors.black.withValues(alpha: 0.045),
                      ),
                    ),
                    child: TextField(
                      controller: _captionCtrl,
                      maxLength: 48,
                      onChanged: (_) => _emit(),
                      style: TextStyle(color: mc.textPrimary, fontSize: 14.5),
                      decoration: InputDecoration(
                        counterText: '',
                        hintText: 'Optional note on poster',
                        hintStyle: TextStyle(color: mc.textTertiary),
                        filled: false,
                        border: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        enabledBorder: InputBorder.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                ],
              ),
            ),
          ),

          const SizedBox(height: 14),

          // Pinned bouncy Done CTA (always reachable without scrolling)
          TempoBouncyButton(
            height: 50,
            onPressed: () {
              HapticFeedback.lightImpact();
              Navigator.of(context).pop();
            },
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  Widget _posterToggleTile({
    required AppColors c,
    required String label,
    required bool active,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: TempoTouchLightEffect(
        borderRadius: 999,
        isAccentSurface: active,
        intensity: 0.9,
        scatterGain: 1.05,
        child: CustomPaint(
          foregroundPainter: LiquidGlassRimPainter(
            borderRadius: 999,
            isDark: c.isDark,
            intensity: active ? 1.08 : 0.62,
            strokeWidth: 0.9,
            showTopMeniscus: false,
            tintColor: active ? c.accent : null,
          ),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: active ? c.accent : c.searchBg,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: active ? Colors.white : c.textPrimary,
                fontSize: 13.2,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
