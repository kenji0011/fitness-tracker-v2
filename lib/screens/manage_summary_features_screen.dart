import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';
import '../widgets/tempo_sliver_header.dart';

class SummaryFeatureItem {
  final String id;
  final String title;
  final IconData icon;
  final Color color;

  const SummaryFeatureItem({
    required this.id,
    required this.title,
    required this.icon,
    required this.color,
  });
}

const List<SummaryFeatureItem> kAllSummaryFeatures = [
  SummaryFeatureItem(
    id: 'sleep',
    title: 'Sleep',
    icon: CupertinoIcons.bed_double_fill,
    color: Color(0xFF6B63F6),
  ),
  SummaryFeatureItem(
    id: 'weight',
    title: 'Weight',
    icon: CupertinoIcons.gauge,
    color: Color(0xFF4CD964),
  ),
  SummaryFeatureItem(
    id: 'bmi',
    title: 'BMI Index',
    icon: CupertinoIcons.heart_fill,
    color: Color(0xFFE84A4A),
  ),
  SummaryFeatureItem(
    id: 'waist',
    title: 'Waist',
    icon: CupertinoIcons.resize_h,
    color: Color(0xFF3CC29E),
  ),
  SummaryFeatureItem(
    id: 'burn',
    title: '7-Day Burn',
    icon: CupertinoIcons.bolt_fill,
    color: Color(0xFFF39C2E),
  ),
  SummaryFeatureItem(
    id: 'workouts',
    title: 'Workouts',
    icon: CupertinoIcons.flame_fill,
    color: Color(0xFFE8527A),
  ),
];

List<String> get kDefaultSummaryFeatureIds =>
    kAllSummaryFeatures.map((f) => f.id).toList(growable: false);

List<String> parseSummaryFeatureIds(String? raw) {
  if (raw == null || raw.isEmpty) return kDefaultSummaryFeatureIds;
  try {
    final decoded = jsonDecode(raw);
    if (decoded is List) {
      final validIds = kAllSummaryFeatures.map((f) => f.id).toSet();
      final result = <String>[];
      for (final item in decoded) {
        if (item is String && validIds.contains(item) && !result.contains(item)) {
          result.add(item);
        }
      }
      return result;
    }
  } catch (_) {}
  return kDefaultSummaryFeatureIds;
}

/// Lets users choose which health & fitness cards appear on the Summary page.
/// Uses [TempoSliverHeader] for the exact same collapsing header animation.
class ManageSummaryFeaturesScreen extends StatefulWidget {
  final List<String> initialSelectedIds;

  const ManageSummaryFeaturesScreen({
    super.key,
    required this.initialSelectedIds,
  });

  @override
  State<ManageSummaryFeaturesScreen> createState() =>
      _ManageSummaryFeaturesScreenState();
}

class _ManageSummaryFeaturesScreenState
    extends State<ManageSummaryFeaturesScreen> {
  late List<String> _selectedIds;

  @override
  void initState() {
    super.initState();
    final valid = kAllSummaryFeatures.map((f) => f.id).toSet();
    _selectedIds = widget.initialSelectedIds
        .where((id) => valid.contains(id))
        .toList();
  }

  SummaryFeatureItem _featureById(String id) =>
      kAllSummaryFeatures.firstWhere((f) => f.id == id);

  List<SummaryFeatureItem> get _activeFeatures =>
      _selectedIds.map(_featureById).toList();

  List<SummaryFeatureItem> get _hiddenFeatures => kAllSummaryFeatures
      .where((f) => !_selectedIds.contains(f.id))
      .toList();

  void _removeFeature(String id) {
    HapticFeedback.selectionClick();
    setState(() => _selectedIds.remove(id));
  }

  void _addFeature(String id) {
    HapticFeedback.selectionClick();
    if (_selectedIds.contains(id)) return;
    setState(() => _selectedIds.add(id));
  }

  void _save() {
    HapticFeedback.lightImpact();
    Navigator.of(context).pop(List<String>.from(_selectedIds));
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final active = _activeFeatures;
    final hidden = _hiddenFeatures;
    final bottomPad = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      backgroundColor: c.scaffold,
      body: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        slivers: [
          TempoSliverHeader(
            title: 'Manage health features',
            showBackButton: true,
            actions: [
              TempoHeaderAction(
                tooltip: 'Save',
                onPressed: _save,
                icon: Icon(
                  CupertinoIcons.checkmark_alt,
                  size: 24,
                  color: c.textPrimary,
                ),
              ),
            ],
          ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(18, 12, 18, bottomPad + 44),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 14),
                    child: Text(
                      'Frequently used',
                      style: TextStyle(
                        color: c.textSecondary,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 240),
                    curve: Curves.easeOutCubic,
                    child: active.isEmpty
                        ? Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 22,
                            ),
                            decoration: BoxDecoration(
                              color: c.card,
                              borderRadius: BorderRadius.circular(18),
                              border: c.isDark
                                  ? null
                                  : Border.all(
                                      color: Colors.black.withValues(
                                        alpha: 0.05,
                                      ),
                                    ),
                            ),
                            child: Text(
                              'No cards selected. Tap + below to add features back to Summary.',
                              style: TextStyle(
                                color: c.textTertiary,
                                fontSize: 13.5,
                                height: 1.4,
                              ),
                            ),
                          )
                        : _FeatureGrid(
                            items: active,
                            isActiveSection: true,
                            onTapItem: (item) => _removeFeature(item.id),
                          ),
                  ),
                  const SizedBox(height: 28),
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 14),
                    child: Text(
                      'More features',
                      style: TextStyle(
                        color: c.textSecondary,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 240),
                    curve: Curves.easeOutCubic,
                    child: hidden.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.only(left: 4),
                            child: Text(
                              'All features are displayed on Summary. Tap - on any card above to hide it.',
                              style: TextStyle(
                                color: c.textTertiary,
                                fontSize: 13.5,
                                height: 1.4,
                              ),
                            ),
                          )
                        : _FeatureGrid(
                            items: hidden,
                            isActiveSection: false,
                            onTapItem: (item) => _addFeature(item.id),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FeatureGrid extends StatelessWidget {
  final List<SummaryFeatureItem> items;
  final bool isActiveSection;
  final ValueChanged<SummaryFeatureItem> onTapItem;

  const _FeatureGrid({
    required this.items,
    required this.isActiveSection,
    required this.onTapItem,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (_, constraints) {
        const spacing = 14.0;
        final tileW = (constraints.maxWidth - spacing) / 2;
        return Wrap(
          spacing: spacing,
          runSpacing: 16,
          clipBehavior: Clip.none,
          children: items
              .map(
                (item) => SizedBox(
                  width: tileW,
                  child: _FeatureToggleCard(
                    key: ValueKey('${isActiveSection ? 'on' : 'off'}_${item.id}'),
                    item: item,
                    isActive: isActiveSection,
                    onTap: () => onTapItem(item),
                  ),
                ),
              )
              .toList(),
        );
      },
    );
  }
}

class _FeatureToggleCard extends StatelessWidget {
  final SummaryFeatureItem item;
  final bool isActive;
  final VoidCallback onTap;

  const _FeatureToggleCard({
    super.key,
    required this.item,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final badgeBg = isActive
        ? (c.isDark ? const Color(0xFF42434A) : const Color(0xFFB5B5BC))
        : const Color(0xFF4CD964);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            height: 74,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: c.card,
              borderRadius: BorderRadius.circular(18),
              border: c.isDark
                  ? null
                  : Border.all(color: Colors.black.withValues(alpha: 0.05)),
              boxShadow: c.isDark
                  ? null
                  : [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.03),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: item.color,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(item.icon, color: Colors.white, size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: c.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      height: 1.2,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Overlapping circular minus/plus action badge in top-right corner
          Positioned(
            top: -7,
            right: -3,
            child: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: badgeBg,
                shape: BoxShape.circle,
                border: Border.all(color: c.scaffold, width: 2),
              ),
              child: Icon(
                isActive ? CupertinoIcons.minus : CupertinoIcons.add,
                color: Colors.white,
                size: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
