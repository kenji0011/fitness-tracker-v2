import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/local_profile.dart';
import '../services/active_profile_provider.dart';
import '../services/tempo_rust_db.dart';
import '../theme/app_colors.dart';
import '../widgets/liquid_glass_surface.dart';
import '../widgets/tempo_sliver_header.dart';
import 'add_data_screen.dart';

class DetailScreen extends StatefulWidget {
  final String title;
  final String metricType; // weight | waist | sleep | activity
  final String unit;
  final Color accentColor;
  final Widget? infoScreen;

  const DetailScreen({
    super.key,
    required this.title,
    required this.metricType,
    required this.unit,
    required this.accentColor,
    this.infoScreen,
  });

  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> {
  final TempoRustDb _db = TempoRustDb.instance;
  List<BodyMetricPoint> _metricPoints = [];
  List<LocalDailyActivity> _activityPoints = [];
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
    if (widget.metricType == 'activity') {
      final list = await _db.getDailyActivityHistory(pid, limit: 30);
      if (mounted) {
        setState(() {
          _activityPoints = list;
          _loading = false;
        });
      }
    } else {
      final list = await _db.getBodyMetricHistory(pid, widget.metricType, limit: 60);
      if (mounted) {
        setState(() {
          _metricPoints = list;
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final isActivity = widget.metricType == 'activity';

    final values = isActivity
        ? _activityPoints.map((e) => e.calories.toDouble()).toList()
        : _metricPoints.map((e) => e.value).toList();
    final latest = values.isNotEmpty ? values.last : 0.0;
    final avg = values.isNotEmpty
        ? values.reduce((a, b) => a + b) / values.length
        : 0.0;

    return Scaffold(
      backgroundColor: c.scaffold,
      body: CustomScrollView(
        slivers: [
          TempoSliverHeader(
            title: widget.title,
            showBackButton: true,
            actions: [
              if (widget.infoScreen != null)
                TempoHeaderAction(
                  tooltip: 'Info',
                  icon: Icon(
                    CupertinoIcons.info_circle,
                    size: 21,
                    color: c.textPrimary,
                  ),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => widget.infoScreen!),
                  ),
                ),
              TempoHeaderAction(
                tooltip: 'Add Data',
                icon: Icon(
                  CupertinoIcons.add,
                  size: 22,
                  color: c.textPrimary,
                ),
                onPressed: () async {
                  final changed = await Navigator.push<bool>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AddDataScreen(
                        initialMetric:
                            isActivity ? 'steps' : widget.metricType,
                      ),
                    ),
                  );
                  if (changed == true) _load();
                },
              ),
            ],
          ),
          if (_loading)
            SliverFillRemaining(
              child: Center(child: CupertinoActivityIndicator(color: c.accent)),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 32),
              sliver: SliverList.list(
                children: [
                  AppleCard(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'LATEST',
                        style: TextStyle(
                          color: c.textTertiary,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.7,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            values.isEmpty
                                ? '--'
                                : (isActivity
                                    ? latest.round().toString()
                                    : latest.toStringAsFixed(1)),
                            style: TextStyle(
                              color: c.textPrimary,
                              fontSize: 38,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -1,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            widget.unit,
                            style: TextStyle(
                              color: c.textSecondary,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const Spacer(),
                          if (values.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: widget.accentColor.withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(99),
                              ),
                              child: Text(
                                'Avg ${avg.toStringAsFixed(1)} ${widget.unit}',
                                style: TextStyle(
                                  color: widget.accentColor,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 22),
                      SizedBox(
                        height: 180,
                        child: values.length < 2
                            ? Center(
                                child: Text(
                                  'Add at least 2 entries to view trend chart',
                                  style: TextStyle(color: c.textSecondary),
                                ),
                              )
                            : LineChart(
                                LineChartData(
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
                                      color: widget.accentColor,
                                      barWidth: 3,
                                      dotData: const FlDotData(show: true),
                                      belowBarData: BarAreaData(
                                        show: true,
                                        color: widget.accentColor
                                            .withValues(alpha: 0.15),
                                      ),
                                      spots: List.generate(
                                        values.length,
                                        (i) => FlSpot(i.toDouble(), values[i]),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'History',
                  style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                if (values.isEmpty)
                  AppleCard(
                    child: Text(
                      'No local entries recorded yet. Tap + to add one.',
                      style: TextStyle(color: c.textSecondary),
                    ),
                  )
                else if (isActivity)
                  ..._activityPoints.reversed.map(
                    (a) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: AppleCard(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  DateFormat('EEE, MMM d').format(a.date),
                                  style: TextStyle(
                                    color: c.textPrimary,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text(
                                  '${a.steps} steps • ${a.minutes} min • ${a.workoutsCount} workouts',
                                  style: TextStyle(
                                    color: c.textSecondary,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                            Text(
                              '${a.calories} kcal',
                              style: TextStyle(
                                color: widget.accentColor,
                                fontWeight: FontWeight.w800,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                else
                  ..._metricPoints.reversed.map(
                    (pt) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: AppleCard(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              DateFormat('MMM d, yyyy • h:mm a')
                                  .format(pt.recordedAt.toLocal()),
                              style: TextStyle(
                                color: c.textSecondary,
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            Text(
                              '${pt.value.toStringAsFixed(1)} ${widget.unit}',
                              style: TextStyle(
                                color: c.textPrimary,
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
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
