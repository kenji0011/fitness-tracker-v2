import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../data/exercise_data2.dart';
import '../models/workout_model.dart';
import '../services/active_profile_provider.dart';
import '../services/tempo_rust_db.dart';
import '../theme/app_colors.dart';
import '../widgets/liquid_glass_surface.dart';
import '../widgets/tempo_sliver_header.dart';
import '../widgets/tempo_toast.dart';

/// Persistence helper for user-created Custom Workouts (stored per profile in
/// local SQLite settings with zero schema migration required).
class CustomWorkoutsStore {
  static String _key(String profileId) => 'custom_workouts_v1_$profileId';

  static Future<List<Workout>> load(String profileId) async {
    final raw = await TempoRustDb.instance.getSetting(_key(profileId));
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final catalog = _allCatalogExercises();
      final results = <Workout>[];
      for (final item in decoded) {
        if (item is! Map) continue;
        final map = Map<String, dynamic>.from(item);
        final exNames = (map['exerciseNames'] as List? ?? const [])
            .map((e) => e.toString())
            .toList();
        final exList = <Exercise>[];
        for (final name in exNames) {
          final match = catalog[name.toLowerCase()];
          if (match != null) {
            exList.add(match);
          } else {
            exList.add(
              Exercise(
                name: name,
                baseCaloriesPerMinute: 7,
                duration: 45,
                description: 'Custom workout exercise.',
              ),
            );
          }
        }
        if (exList.isEmpty) continue;
        final mins = (exList.fold<int>(0, (s, e) => s + e.duration) / 60)
            .ceil()
            .clamp(5, 180);
        results.add(
          Workout(
            id: (map['id'] ?? 'custom_${results.length}').toString(),
            title: (map['title'] ?? 'Custom Routine').toString(),
            duration: '$mins min',
            exercises: '${exList.length} exercises',
            level: (map['level'] ?? 'Custom').toString(),
            bodyFocus: (map['bodyFocus'] ?? 'Full Body').toString(),
            videoAsset: '',
            thumbnailAsset: 'assets/defaultVid.jpg',
            exerciseList: exList,
            journeyName: 'Custom',
          ),
        );
      }
      return results;
    } catch (_) {
      return const [];
    }
  }

  static Future<void> save(String profileId, List<Workout> workouts) async {
    final encoded = jsonEncode(
      workouts
          .map(
            (w) => {
              'id': w.id,
              'title': w.title,
              'level': w.level,
              'bodyFocus': w.bodyFocus,
              'exerciseNames': w.exerciseList.map((e) => e.name).toList(),
            },
          )
          .toList(),
    );
    await TempoRustDb.instance.setSetting(_key(profileId), encoded);
  }

  static Map<String, Exercise> _allCatalogExercises() {
    final map = <String, Exercise>{};
    for (final w in exerciseWorkouts) {
      for (final ex in w.exerciseList) {
        map.putIfAbsent(ex.name.toLowerCase(), () => ex);
      }
    }
    return map;
  }
}

/// Lets users compose & save custom workouts by picking from Tempo's offline
/// video exercise library.
class CustomWorkoutBuilderScreen extends StatefulWidget {
  final Workout? existing;

  const CustomWorkoutBuilderScreen({super.key, this.existing});

  @override
  State<CustomWorkoutBuilderScreen> createState() =>
      _CustomWorkoutBuilderScreenState();
}

class _CustomWorkoutBuilderScreenState
    extends State<CustomWorkoutBuilderScreen> {
  static const List<String> _focusOptions = [
    'Full Body',
    'Chest',
    'Back',
    'Shoulders',
    'Arms',
    'Abs',
    'Legs',
  ];

  final _titleCtrl = TextEditingController();
  final _searchCtrl = TextEditingController();
  String _bodyFocus = 'Full Body';
  String _query = '';
  final List<Exercise> _selected = [];
  late final List<Exercise> _catalog;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final unique = <String, Exercise>{};
    for (final w in exerciseWorkouts) {
      for (final ex in w.exerciseList) {
        unique.putIfAbsent(ex.name.toLowerCase(), () => ex);
      }
    }
    _catalog = unique.values.toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    if (widget.existing != null) {
      _titleCtrl.text = widget.existing!.title;
      _bodyFocus = _focusOptions.contains(widget.existing!.bodyFocus)
          ? widget.existing!.bodyFocus
          : 'Full Body';
      _selected.addAll(widget.existing!.exerciseList);
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  List<Exercise> get _filteredCatalog {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _catalog;
    return _catalog
        .where(
          (e) =>
              e.name.toLowerCase().contains(q) ||
              e.description.toLowerCase().contains(q),
        )
        .toList();
  }

  bool _isPicked(Exercise ex) =>
      _selected.any((s) => s.name.toLowerCase() == ex.name.toLowerCase());

  void _toggleExercise(Exercise ex) {
    HapticFeedback.selectionClick();
    setState(() {
      final idx = _selected
          .indexWhere((s) => s.name.toLowerCase() == ex.name.toLowerCase());
      if (idx >= 0) {
        _selected.removeAt(idx);
      } else {
        _selected.add(ex);
      }
    });
  }

  Future<void> _saveRoutine() async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      showTempoToast(context, 'Enter a workout name', isError: true);
      return;
    }
    if (_selected.isEmpty) {
      showTempoToast(context, 'Pick at least one exercise', isError: true);
      return;
    }

    final pid = context.read<ActiveProfileProvider>().activeProfileId;
    if (pid == null) return;

    setState(() => _saving = true);
    final current = await CustomWorkoutsStore.load(pid);
    final mins = (_selected.fold<int>(0, (s, e) => s + e.duration) / 60)
        .ceil()
        .clamp(5, 180);
    final newWorkout = Workout(
      id: widget.existing?.id ??
          'custom_${DateTime.now().millisecondsSinceEpoch}',
      title: title,
      duration: '$mins min',
      exercises: '${_selected.length} exercises',
      level: 'Custom',
      bodyFocus: _bodyFocus,
      videoAsset: '',
      thumbnailAsset: 'assets/defaultVid.jpg',
      exerciseList: List<Exercise>.from(_selected),
      journeyName: 'Custom',
    );

    final updated = List<Workout>.from(current);
    final existingIdx = updated.indexWhere((w) => w.id == newWorkout.id);
    if (existingIdx >= 0) {
      updated[existingIdx] = newWorkout;
    } else {
      updated.insert(0, newWorkout);
    }

    await CustomWorkoutsStore.save(pid, updated);
    if (mounted) {
      showTempoToast(context, 'Custom workout saved');
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final filtered = _filteredCatalog;
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      backgroundColor: c.scaffold,
      body: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        slivers: [
          TempoSliverHeader(
            title: widget.existing == null ? 'Custom Workout' : 'Edit Workout',
            showBackButton: true,
            actions: [
              TempoHeaderAction(
                tooltip: 'Save',
                onPressed: _saving ? () {} : _saveRoutine,
                icon: Icon(
                  CupertinoIcons.checkmark_alt,
                  size: 23,
                  color: c.accent,
                ),
              ),
            ],
          ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(18, 6, 18, bottomInset + 36),
            sliver: SliverList.list(
              children: [
                AppleCard(
                  borderRadius: 22,
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Routine name',
                        style: TextStyle(
                          color: c.textSecondary,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _titleCtrl,
                        style: TextStyle(
                          color: c.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                        decoration: InputDecoration(
                          hintText: 'e.g. Push Day Express',
                          hintStyle: TextStyle(color: c.textHint),
                          filled: true,
                          fillColor: c.searchBg,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'Focus',
                        style: TextStyle(
                          color: c.textSecondary,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 34,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: _focusOptions.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 8),
                          itemBuilder: (_, i) {
                            final f = _focusOptions[i];
                            final sel = f == _bodyFocus;
                            return GestureDetector(
                              onTap: () {
                                HapticFeedback.selectionClick();
                                setState(() => _bodyFocus = f);
                              },
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 160),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 7,
                                ),
                                decoration: BoxDecoration(
                                  color: sel ? c.accent : c.searchBg,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  f,
                                  style: TextStyle(
                                    color: sel ? Colors.white : c.textPrimary,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Selected summary strip
                Row(
                  children: [
                    Text(
                      'Select exercises',
                      style: TextStyle(
                        color: c.textPrimary,
                        fontSize: 16.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${_selected.length} selected',
                      style: TextStyle(
                        color: _selected.isEmpty ? c.textTertiary : c.accent,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // Pill search bar matching WorkoutScreen
                Container(
                  height: 44,
                  decoration: BoxDecoration(
                    color: c.searchBg,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: TextField(
                    controller: _searchCtrl,
                    onChanged: (v) => setState(() => _query = v),
                    textAlignVertical: TextAlignVertical.center,
                    style: TextStyle(color: c.textPrimary, fontSize: 14.5),
                    decoration: InputDecoration(
                      isDense: true,
                      filled: false,
                      border: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      prefixIcon: Icon(
                        CupertinoIcons.search,
                        color: c.textTertiary,
                        size: 17,
                      ),
                      hintText: 'Search exercises...',
                      hintStyle: TextStyle(color: c.textTertiary),
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                // Exercise catalog list
                AppleCard(
                  borderRadius: 22,
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: List.generate(filtered.length, (i) {
                      final ex = filtered[i];
                      final picked = _isPicked(ex);
                      final isLast = i == filtered.length - 1;
                      return Column(
                        children: [
                          InkWell(
                            onTap: () => _toggleExercise(ex),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 13,
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          ex.name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: c.textPrimary,
                                            fontSize: 14.5,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          '${ex.duration}s${ex.requiresWeightInput ? ' · Weighted' : ' · Bodyweight'}',
                                          style: TextStyle(
                                            color: c.textTertiary,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  AnimatedContainer(
                                    duration: const Duration(milliseconds: 160),
                                    width: 24,
                                    height: 24,
                                    decoration: BoxDecoration(
                                      color: picked
                                          ? c.accent
                                          : Colors.transparent,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color:
                                            picked ? c.accent : c.textTertiary,
                                        width: 1.6,
                                      ),
                                    ),
                                    child: picked
                                        ? const Icon(
                                            CupertinoIcons.checkmark_alt,
                                            color: Colors.white,
                                            size: 14,
                                          )
                                        : null,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          if (!isLast)
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 16),
                              child: Divider(height: 1, color: c.divider),
                            ),
                        ],
                      );
                    }),
                  ),
                ),

                const SizedBox(height: 18),

                SizedBox(
                  height: 52,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: c.accent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    onPressed: _saving ? null : _saveRoutine,
                    child: Text(
                      'Save routine (${_selected.length})',
                      style: const TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w600,
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
