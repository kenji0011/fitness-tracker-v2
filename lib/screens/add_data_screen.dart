import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/active_profile_provider.dart';
import '../services/tempo_rust_db.dart';
import '../theme/app_colors.dart';
import '../widgets/liquid_glass_surface.dart';
import '../widgets/tempo_sliver_header.dart';

class AddDataScreen extends StatefulWidget {
  final String? initialMetric;

  const AddDataScreen({super.key, this.initialMetric});

  @override
  State<AddDataScreen> createState() => _AddDataScreenState();
}

class _AddDataScreenState extends State<AddDataScreen> {
  final _valueCtrl = TextEditingController();
  late String _selectedMetric;
  bool _saving = false;

  static const _metrics = <Map<String, dynamic>>[
    {
      'key': 'steps',
      'label': 'Today\'s Steps',
      'unit': 'steps',
      'hint': 'e.g. 4050',
      'icon': CupertinoIcons.hare_fill,
    },
    {
      'key': 'calories',
      'label': 'Calories Burned',
      'unit': 'kcal',
      'hint': 'e.g. 250',
      'icon': CupertinoIcons.flame_fill,
    },
    {
      'key': 'minutes',
      'label': 'Activity Mins',
      'unit': 'mins',
      'hint': 'e.g. 30',
      'icon': CupertinoIcons.clock_fill,
    },
    {
      'key': 'weight',
      'label': 'Weight',
      'unit': 'kg',
      'hint': 'e.g. 68.5',
      'icon': CupertinoIcons.gauge,
    },
    {
      'key': 'waist',
      'label': 'Waist',
      'unit': 'cm',
      'hint': 'e.g. 78.0',
      'icon': CupertinoIcons.resize_h,
    },
    {
      'key': 'sleep',
      'label': 'Sleep',
      'unit': 'hours',
      'hint': 'e.g. 7.5',
      'icon': CupertinoIcons.bed_double_fill,
    },
    {
      'key': 'height',
      'label': 'Height',
      'unit': 'cm',
      'hint': 'e.g. 175',
      'icon': CupertinoIcons.arrow_up_down,
    },
  ];

  @override
  void initState() {
    super.initState();
    _selectedMetric = widget.initialMetric ?? 'weight';
  }

  @override
  void dispose() {
    _valueCtrl.dispose();
    super.dispose();
  }

  Map<String, dynamic> get _currentSpec => _metrics.firstWhere(
        (m) => m['key'] == _selectedMetric,
        orElse: () => _metrics.first,
      );

  Future<void> _save() async {
    final profileProvider = context.read<ActiveProfileProvider>();
    final profileId = profileProvider.activeProfileId;
    if (profileId == null) return;

    final raw = double.tryParse(_valueCtrl.text.trim());
    if (raw == null || raw <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid positive number')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final db = TempoRustDb.instance;
      if (_selectedMetric == 'steps') {
        await db.upsertDailyActivity(
          profileId: profileId,
          steps: raw.round(),
        );
      } else if (_selectedMetric == 'calories') {
        await db.upsertDailyActivity(
          profileId: profileId,
          calories: raw.round(),
        );
      } else if (_selectedMetric == 'minutes') {
        await db.upsertDailyActivity(
          profileId: profileId,
          minutes: raw.round(),
        );
      } else {
        await db.logBodyMetric(
          profileId: profileId,
          metricType: _selectedMetric,
          value: raw,
        );
      }
      await profileProvider.refreshProfiles();
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving data: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final spec = _currentSpec;

    return Scaffold(
      backgroundColor: c.scaffold,
      body: CustomScrollView(
        slivers: [
          TempoSliverHeader(
            title: 'Log Health Data',
            showBackButton: true,
            onBack: () => Navigator.of(context).pop(false),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            sliver: SliverList.list(
              children: [
                Text(
                  'Select Metric',
              style: TextStyle(
                color: c.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: _metrics.map((m) {
                final selected = m['key'] == _selectedMetric;
                return GestureDetector(
                  onTap: () => setState(() {
                    _selectedMetric = m['key'] as String;
                    _valueCtrl.clear();
                  }),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: selected ? c.accent : c.card,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: selected ? c.accent : c.cardBorder,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          m['icon'] as IconData,
                          size: 17,
                          color: selected ? Colors.white : c.textSecondary,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          m['label'] as String,
                          style: TextStyle(
                            color: selected ? Colors.white : c.textPrimary,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 24),
            AppleCard(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${spec['label']} (${spec['unit']})',
                    style: TextStyle(
                      color: c.textPrimary,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _valueCtrl,
                    autofocus: true,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    style: TextStyle(
                      color: c.textPrimary,
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                    ),
                    decoration: InputDecoration(
                      hintText: spec['hint'] as String,
                      hintStyle: TextStyle(
                        color: c.textHint,
                        fontSize: 22,
                        fontWeight: FontWeight.w500,
                      ),
                      suffixText: spec['unit'] as String,
                      suffixStyle: TextStyle(
                        color: c.textSecondary,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 54,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: c.accent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        'Save to Local Database',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
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
