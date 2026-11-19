import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../theme/app_colors.dart';
import '../widgets/tempo_sliver_header.dart';

class HistoryCalendarSelection {
  final DateTime date;

  /// 0 = Day (Latest), 1 = Week, 2 = Month (M), 3 = Year (Y)
  final int modeIndex;

  const HistoryCalendarSelection({
    required this.date,
    required this.modeIndex,
  });
}

/// Reusable full-screen History Calendar picker (Day | Week | Month | Year)
/// inspired by Mi Fitness / HyperOS 3, fully compatible with Light & Dark Mode.
class HistoryCalendarScreen extends StatefulWidget {
  final DateTime initialDate;

  /// 0 = Day, 1 = Week, 2 = Month, 3 = Year
  final int initialModeIndex;

  /// Optional set of `yyyy-MM-dd` keys that have recorded entries (shown with subtle dot).
  final Set<String> recordedDateKeys;

  const HistoryCalendarScreen({
    super.key,
    required this.initialDate,
    this.initialModeIndex = 0,
    this.recordedDateKeys = const {},
  });

  @override
  State<HistoryCalendarScreen> createState() => _HistoryCalendarScreenState();
}

class _HistoryCalendarScreenState extends State<HistoryCalendarScreen> {
  static const Color _accentCoral = Color(0xFFD95B5B);
  static const List<String> _weekdays = [
    'MON',
    'TUE',
    'WED',
    'THU',
    'FRI',
    'SAT',
    'SUN',
  ];

  late DateTime _selectedDate;
  late int _modeIndex;
  late final DateTime _today;
  late final List<DateTime> _months;
  final ScrollController _monthScrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _today = DateTime(now.year, now.month, now.day);
    _selectedDate = DateTime(
      widget.initialDate.year,
      widget.initialDate.month,
      widget.initialDate.day,
    );
    _modeIndex = widget.initialModeIndex.clamp(0, 3);

    // Build 18 past months + current month + next month (like Nov + Dec in reference)
    final startMonth = DateTime(_today.year, _today.month - 18, 1);
    _months = List.generate(
      20,
      (i) => DateTime(startMonth.year, startMonth.month + i, 1),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToSelectedMonth());
  }

  void _scrollToSelectedMonth({bool animate = false}) {
    if (!_monthScrollCtrl.hasClients) return;
    final targetIdx = _months.indexWhere(
      (m) => m.year == _selectedDate.year && m.month == _selectedDate.month,
    );
    if (targetIdx < 0) return;
    // Approximate height per month block (~336px)
    final offset = (targetIdx * 336.0)
        .clamp(0.0, _monthScrollCtrl.position.maxScrollExtent);
    if (animate) {
      _monthScrollCtrl.animateTo(
        offset,
        duration: const Duration(milliseconds: 340),
        curve: Curves.easeOutCubic,
      );
    } else {
      _monthScrollCtrl.jumpTo(offset);
    }
  }

  @override
  void dispose() {
    _monthScrollCtrl.dispose();
    super.dispose();
  }

  void _jumpToToday() {
    HapticFeedback.selectionClick();
    setState(() {
      _selectedDate = _today;
    });
    if (_modeIndex == 0 || _modeIndex == 1) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _scrollToSelectedMonth(animate: true),
      );
    }
  }

  void _commitSelection(DateTime date, int mode) {
    HapticFeedback.selectionClick();
    final clamped = date.isAfter(_today) ? _today : date;
    Navigator.of(context).pop(
      HistoryCalendarSelection(date: clamped, modeIndex: mode),
    );
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  bool _isInSelectedWeek(DateTime d) {
    final monday = _selectedDate.subtract(
      Duration(days: _selectedDate.weekday - 1),
    );
    final sunday = monday.add(const Duration(days: 6));
    return !d.isBefore(monday) && !d.isAfter(sunday);
  }

  String _dateSubtitle() {
    switch (_modeIndex) {
      case 1:
        final mon = _selectedDate.subtract(
          Duration(days: _selectedDate.weekday - 1),
        );
        final sun = mon.add(const Duration(days: 6));
        return '${DateFormat('MM/dd').format(mon)} – ${DateFormat('MM/dd/yyyy').format(sun)}';
      case 2:
        return DateFormat('MMMM yyyy').format(_selectedDate);
      case 3:
        return '${_selectedDate.year}';
      default:
        return DateFormat('MM/dd/yyyy').format(_selectedDate);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);

    return Scaffold(
      backgroundColor: c.scaffold,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Top Bar: Back arrow | Today calendar jump icon
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 12, 6),
              child: Row(
                children: [
                  TempoGlassCircleButton(
                    glassOpacity: 0.0,
                    icon: TempoBackChevron(color: c.textPrimary, size: 22),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const Spacer(),
                  TempoGlassCircleButton(
                    glassOpacity: 0.0,
                    tooltip: 'Jump to today',
                    icon: Icon(
                      CupertinoIcons.calendar_today,
                      size: 22,
                      color: c.textPrimary,
                    ),
                    onPressed: _jumpToToday,
                  ),
                ],
              ),
            ),

            // Title "History" + live formatted date subtitle
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 6, 22, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'History',
                    style: TextStyle(
                      color: c.textPrimary,
                      fontSize: 30,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.6,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _dateSubtitle(),
                    style: TextStyle(
                      color: c.textSecondary,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),

            // 4-Mode Row: Day | Week | Month | Year
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                children: [
                  _ModeTab(
                    icon: Icons.calendar_today_rounded,
                    label: 'Day',
                    selected: _modeIndex == 0,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _modeIndex = 0);
                    },
                  ),
                  _ModeTab(
                    icon: Icons.view_week_rounded,
                    label: 'Week',
                    selected: _modeIndex == 1,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _modeIndex = 1);
                    },
                  ),
                  _ModeTab(
                    icon: Icons.calendar_month_rounded,
                    label: 'Month',
                    selected: _modeIndex == 2,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _modeIndex = 2);
                    },
                  ),
                  _ModeTab(
                    icon: Icons.date_range_rounded,
                    label: 'Year',
                    selected: _modeIndex == 3,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _modeIndex = 3);
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Weekday header row for Day & Week modes
            if (_modeIndex == 0 || _modeIndex == 1) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: _weekdays
                      .map(
                        (d) => Expanded(
                          child: Center(
                            child: Text(
                              d,
                              style: TextStyle(
                                color: c.textPrimary,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.4,
                              ),
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
              const SizedBox(height: 10),
              Divider(height: 1, color: c.divider),
            ] else
              Divider(height: 1, color: c.divider),

            // Main Calendar Body
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: _buildModeBody(c),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModeBody(AppColors c) {
    if (_modeIndex == 2) return _buildMonthPicker(c);
    if (_modeIndex == 3) return _buildYearPicker(c);
    return _buildVerticalCalendar(c);
  }

  Widget _buildVerticalCalendar(AppColors c) {
    final isWeekMode = _modeIndex == 1;
    return ListView.builder(
      key: ValueKey('calendar_mode_$_modeIndex'),
      controller: _monthScrollCtrl,
      padding: const EdgeInsets.fromLTRB(12, 18, 12, 40),
      itemCount: _months.length,
      itemBuilder: (context, index) {
        final monthStart = _months[index];
        final daysInMonth =
            DateUtils.getDaysInMonth(monthStart.year, monthStart.month);
        // Monday = 1 -> leading blanks = weekday - 1
        final leadingBlanks = monthStart.weekday - 1;
        final totalCells = leadingBlanks + daysInMonth;
        final rows = (totalCells / 7).ceil();
        final showYear = monthStart.year != _today.year;
        final monthLabel = showYear
            ? DateFormat('MMM yyyy').format(monthStart)
            : DateFormat('MMM').format(monthStart);

        return Padding(
          padding: const EdgeInsets.only(bottom: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 10, bottom: 14),
                child: Text(
                  monthLabel,
                  style: const TextStyle(
                    color: _accentCoral,
                    fontSize: 22,
                    fontWeight: FontWeight.w500,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
              ...List.generate(rows, (rowIdx) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: List.generate(7, (colIdx) {
                      final cellIdx = rowIdx * 7 + colIdx;
                      final dayNum = cellIdx - leadingBlanks + 1;
                      if (dayNum < 1 || dayNum > daysInMonth) {
                        return const Expanded(child: SizedBox(height: 44));
                      }
                      final cellDate = DateTime(
                        monthStart.year,
                        monthStart.month,
                        dayNum,
                      );
                      final isFuture = cellDate.isAfter(_today);
                      final isSelected = isWeekMode
                          ? _isInSelectedWeek(cellDate)
                          : _isSameDay(cellDate, _selectedDate);
                      final isToday = _isSameDay(cellDate, _today);
                      final dateKey = DateFormat('yyyy-MM-dd').format(cellDate);
                      final hasRecord =
                          widget.recordedDateKeys.contains(dateKey);

                      return Expanded(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: isFuture
                              ? null
                              : () {
                                  if (isWeekMode) {
                                    // Anchor to Sunday of chosen week (clamped to today)
                                    final sun = cellDate.add(
                                      Duration(days: 7 - cellDate.weekday),
                                    );
                                    _commitSelection(sun, 1);
                                  } else {
                                    _commitSelection(cellDate, 0);
                                  }
                                },
                          child: SizedBox(
                            height: 46,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                if (isWeekMode && isSelected)
                                  Container(
                                    height: 36,
                                    decoration: BoxDecoration(
                                      color: _accentCoral.withValues(
                                        alpha: c.isDark ? 0.34 : 0.20,
                                      ),
                                      borderRadius: BorderRadius.horizontal(
                                        left: Radius.circular(
                                          colIdx == 0 ? 18 : 0,
                                        ),
                                        right: Radius.circular(
                                          colIdx == 6 ? 18 : 0,
                                        ),
                                      ),
                                    ),
                                  ),
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: (!isWeekMode && isSelected)
                                        ? _accentCoral
                                        : Colors.transparent,
                                    border: (!isWeekMode && isSelected)
                                        ? Border.all(
                                            color: c.isDark
                                                ? Colors.white
                                                    .withValues(alpha: 0.85)
                                                : _accentCoral,
                                            width: 1.4,
                                          )
                                        : (isToday && !isSelected
                                            ? Border.all(
                                                color: _accentCoral.withValues(
                                                  alpha: 0.65,
                                                ),
                                                width: 1.2,
                                              )
                                            : null),
                                  ),
                                  alignment: Alignment.center,
                                  child: Text(
                                    '$dayNum',
                                    style: TextStyle(
                                      color: (!isWeekMode && isSelected)
                                          ? Colors.white
                                          : (isFuture
                                              ? c.textTertiary
                                                  .withValues(alpha: 0.45)
                                              : c.textPrimary),
                                      fontSize: 16,
                                      fontWeight: isSelected || isToday
                                          ? FontWeight.w600
                                          : FontWeight.w500,
                                      fontFeatures: const [
                                        FontFeature.tabularFigures(),
                                      ],
                                    ),
                                  ),
                                ),
                                if (hasRecord && !isSelected)
                                  Positioned(
                                    bottom: 2,
                                    child: Container(
                                      width: 4,
                                      height: 4,
                                      decoration: const BoxDecoration(
                                        color: _accentCoral,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMonthPicker(AppColors c) {
    final years = List.generate(4, (i) => _today.year - i);
    return ListView.builder(
      key: const ValueKey('calendar_mode_month'),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
      itemCount: years.length,
      itemBuilder: (_, yi) {
        final year = years[yi];
        return Padding(
          padding: const EdgeInsets.only(bottom: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$year',
                style: const TextStyle(
                  color: _accentCoral,
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 2.2,
                ),
                itemCount: 12,
                itemBuilder: (_, mIdx) {
                  final monthNum = mIdx + 1;
                  final monthFirst = DateTime(year, monthNum, 1);
                  final isFuture = monthFirst.isAfter(_today);
                  final isSelected = _selectedDate.year == year &&
                      _selectedDate.month == monthNum;
                  final label = DateFormat('MMM').format(monthFirst);

                  return GestureDetector(
                    onTap: isFuture
                        ? null
                        : () {
                            final lastDay =
                                DateUtils.getDaysInMonth(year, monthNum);
                            _commitSelection(
                              DateTime(year, monthNum, lastDay),
                              2,
                            );
                          },
                    child: Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: isSelected
                            ? _accentCoral
                            : (c.isDark
                                ? const Color(0xFF1C1C1E)
                                : c.card),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isSelected ? _accentCoral : c.cardBorder,
                        ),
                      ),
                      child: Text(
                        label,
                        style: TextStyle(
                          color: isSelected
                              ? Colors.white
                              : (isFuture
                                  ? c.textTertiary.withValues(alpha: 0.45)
                                  : c.textPrimary),
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildYearPicker(AppColors c) {
    final years = List.generate(7, (i) => _today.year - i);
    return ListView.separated(
      key: const ValueKey('calendar_mode_year'),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
      itemCount: years.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final year = years[i];
        final isSelected = _selectedDate.year == year;
        return GestureDetector(
          onTap: () => _commitSelection(DateTime(year, 12, 31), 3),
          child: Container(
            height: 56,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(
              color: isSelected
                  ? _accentCoral
                  : (c.isDark ? const Color(0xFF1C1C1E) : c.card),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isSelected ? _accentCoral : c.cardBorder,
              ),
            ),
            child: Row(
              children: [
                Text(
                  '$year',
                  style: TextStyle(
                    color: isSelected ? Colors.white : c.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const Spacer(),
                Icon(
                  CupertinoIcons.chevron_right,
                  size: 16,
                  color: isSelected ? Colors.white70 : c.textTertiary,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ModeTab extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ModeTab({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final color = selected ? c.textPrimary : c.textTertiary;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 22, color: color),
              const SizedBox(height: 6),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: color,
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
