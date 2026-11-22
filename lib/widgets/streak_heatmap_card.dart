import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/local_profile.dart';
import '../theme/app_colors.dart';
import 'liquid_glass_surface.dart';

/// 12-week workout & activity heatmap calendar shaded in Tempo Orange intensity.
class StreakHeatmapCard extends StatelessWidget {
  final List<LocalDailyActivity> dailyHistory;
  final Set<String> workoutDayKeys;
  final int currentStreak;
  final int longestStreak;

  const StreakHeatmapCard({
    super.key,
    required this.dailyHistory,
    required this.workoutDayKeys,
    required this.currentStreak,
    required this.longestStreak,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // Map YYYY-MM-DD -> activity intensity (0..3)
    final activityMap = <String, LocalDailyActivity>{
      for (final d in dailyHistory) d.dateKey: d,
    };

    const weeks = 12;
    // Align grid so the rightmost column ends on this week's Sunday (or today's week)
    final daysSinceMon = today.weekday - 1; // 0=Mon..6=Sun
    final currentWeekMonday = today.subtract(Duration(days: daysSinceMon));
    final startMonday =
        currentWeekMonday.subtract(const Duration(days: (weeks - 1) * 7));

    int activeDaysInWindow = 0;

    int intensityFor(DateTime day) {
      if (day.isAfter(today)) return -1;
      final key = DateFormat('yyyy-MM-dd').format(day);
      final act = activityMap[key];
      final hasWorkout =
          workoutDayKeys.contains(key) || (act?.workoutsCount ?? 0) > 0;
      final mins = act?.minutes ?? 0;
      final steps = act?.steps ?? 0;
      final cals = act?.calories ?? 0;

      int level = 0;
      if (hasWorkout || mins >= 40 || cals >= 450) {
        level = 3;
      } else if (mins >= 20 || steps >= 6000 || cals >= 220) {
        level = 2;
      } else if (mins > 0 || steps >= 1500 || cals > 0) {
        level = 1;
      }
      if (level > 0) activeDaysInWindow++;
      return level;
    }

    final grid = List.generate(weeks, (w) {
      return List.generate(7, (d) {
        final date = startMonday.add(Duration(days: w * 7 + d));
        return (date: date, level: intensityFor(date));
      });
    });

    Color cellColor(int level) {
      if (level < 0) return Colors.transparent;
      if (level == 0) {
        return c.isDark
            ? Colors.white.withValues(alpha: 0.07)
            : Colors.black.withValues(alpha: 0.055);
      }
      if (level == 1) return c.accent.withValues(alpha: c.isDark ? 0.34 : 0.28);
      if (level == 2) return c.accent.withValues(alpha: c.isDark ? 0.66 : 0.62);
      return c.accent;
    }

    return RepaintBoundary(
      child: AppleCard(
        borderRadius: 24,
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  CupertinoIcons.calendar,
                  size: 16,
                  color: c.accent,
                ),
                const SizedBox(width: 7),
                Text(
                  'Activity heatmap',
                  style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 15.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.2,
                  ),
                ),
                const Spacer(),
                Text(
                  '$activeDaysInWindow active days',
                  style: TextStyle(
                    color: c.textTertiary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            LayoutBuilder(
              builder: (_, constraints) {
                const gap = 4.0;
                const labelW = 24.0;
                final availW = constraints.maxWidth - labelW - 4;
                final cellSize = ((availW - gap * (weeks - 1)) / weeks)
                    .clamp(10.0, 22.0);
                const dayLabels = ['M', '', 'W', '', 'F', '', 'S'];

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: labelW,
                      child: Column(
                        children: List.generate(7, (d) {
                          return SizedBox(
                            height: cellSize + (d < 6 ? gap : 0),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                dayLabels[d],
                                style: TextStyle(
                                  color: c.textTertiary,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          );
                        }),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: List.generate(weeks, (w) {
                          return Column(
                            children: List.generate(7, (d) {
                              final item = grid[w][d];
                              final isToday = item.date == today;
                              return Padding(
                                padding: EdgeInsets.only(
                                  bottom: d < 6 ? gap : 0,
                                ),
                                child: Container(
                                  width: cellSize,
                                  height: cellSize,
                                  decoration: BoxDecoration(
                                    color: cellColor(item.level),
                                    borderRadius: BorderRadius.circular(
                                      (cellSize * 0.28).clamp(3.0, 5.0),
                                    ),
                                    border: isToday
                                        ? Border.all(
                                            color: c.textPrimary,
                                            width: 1.4,
                                          )
                                        : null,
                                  ),
                                ),
                              );
                            }),
                          );
                        }),
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Text(
                  'Last 12 weeks',
                  style: TextStyle(color: c.textTertiary, fontSize: 11.5),
                ),
                const Spacer(),
                Text(
                  'Less',
                  style: TextStyle(color: c.textTertiary, fontSize: 11),
                ),
                const SizedBox(width: 5),
                for (final lvl in [0, 1, 2, 3]) ...[
                  Container(
                    width: 10,
                    height: 10,
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    decoration: BoxDecoration(
                      color: cellColor(lvl),
                      borderRadius: BorderRadius.circular(2.5),
                    ),
                  ),
                ],
                const SizedBox(width: 5),
                Text(
                  'More',
                  style: TextStyle(color: c.textTertiary, fontSize: 11),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
