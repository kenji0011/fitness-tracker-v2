import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../models/local_profile.dart';
import '../services/local_media_service.dart';
import '../services/weight_unit_helper.dart';
import '../theme/app_colors.dart';
import '../widgets/liquid_glass_surface.dart';
import '../widgets/tempo_sliver_header.dart';

/// Interactive Before / After comparison viewer for Progress Album photos.
/// Supports both draggable split-slider overlay and side-by-side comparison.
class PhotoCompareScreen extends StatefulWidget {
  final List<LocalProgressPhoto> photos;
  final String weightUnit;

  const PhotoCompareScreen({
    super.key,
    required this.photos,
    required this.weightUnit,
  });

  @override
  State<PhotoCompareScreen> createState() => _PhotoCompareScreenState();
}

class _PhotoCompareScreenState extends State<PhotoCompareScreen> {
  late int _beforeIdx;
  late int _afterIdx;
  double _splitFraction = 0.5;
  bool _sideBySide = false;

  @override
  void initState() {
    super.initState();
    // Photos list is newest-first: earliest = last, latest = 0
    _beforeIdx = widget.photos.length > 1 ? widget.photos.length - 1 : 0;
    _afterIdx = 0;
  }

  LocalProgressPhoto get _before => widget.photos[_beforeIdx];
  LocalProgressPhoto get _after => widget.photos[_afterIdx];

  Widget _photoImage(LocalProgressPhoto photo) {
    final exists = LocalMediaService.fileExistsCached(photo.filePath);
    if (!exists) {
      return Container(
        color: const Color(0xFF18181C),
        child: const Center(
          child: Icon(CupertinoIcons.photo, color: Colors.white38, size: 44),
        ),
      );
    }
    return Image.file(
      File(photo.filePath),
      fit: BoxFit.cover,
      gaplessPlayback: true,
      filterQuality: FilterQuality.medium,
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final daysBetween =
        _after.takenAt.toLocal().difference(_before.takenAt.toLocal()).inDays.abs();
    final weightDiffKg =
        (_before.weightKg != null && _after.weightKg != null)
            ? (_after.weightKg! - _before.weightKg!)
            : null;

    return Scaffold(
      backgroundColor: c.scaffold,
      body: SafeArea(
        child: Column(
          children: [
            // Top bar
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 12, 10),
              child: Row(
                children: [
                  TempoGlassCircleButton(
                    icon: TempoBackChevron(color: c.textPrimary, size: 22),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        'Compare',
                        style: TextStyle(
                          color: c.textPrimary,
                          fontSize: 19,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.3,
                        ),
                      ),
                    ),
                  ),
                  TempoLiquidButton(
                    primary: false,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    onPressed: () {
                      HapticFeedback.selectionClick();
                      setState(() => _sideBySide = !_sideBySide);
                    },
                    child: Text(
                      _sideBySide ? 'Slider' : 'Split',
                      style: TextStyle(
                        color: c.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Comparison canvas
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: _sideBySide
                      ? Row(
                          children: [
                            Expanded(
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  _photoImage(_before),
                                  _CornerLabel(
                                    text:
                                        'Before · ${DateFormat('MMM d').format(_before.takenAt.toLocal())}',
                                    alignLeft: true,
                                  ),
                                ],
                              ),
                            ),
                            Container(width: 2, color: c.scaffold),
                            Expanded(
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  _photoImage(_after),
                                  _CornerLabel(
                                    text:
                                        'After · ${DateFormat('MMM d').format(_after.takenAt.toLocal())}',
                                    alignLeft: false,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        )
                      : LayoutBuilder(
                          builder: (_, constraints) {
                            final w = constraints.maxWidth;
                            final dividerX = w * _splitFraction;
                            return GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onHorizontalDragUpdate: (d) {
                                setState(() {
                                  _splitFraction =
                                      ((_splitFraction * w + d.delta.dx) / w)
                                          .clamp(0.08, 0.92);
                                });
                              },
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  // Base layer: After photo
                                  _photoImage(_after),
                                  // Clipped left layer: Before photo
                                  ClipRect(
                                    clipper: _LeftClipper(_splitFraction),
                                    child: _photoImage(_before),
                                  ),
                                  _CornerLabel(
                                    text:
                                        'Before · ${DateFormat('MMM d').format(_before.takenAt.toLocal())}',
                                    alignLeft: true,
                                  ),
                                  _CornerLabel(
                                    text:
                                        'After · ${DateFormat('MMM d').format(_after.takenAt.toLocal())}',
                                    alignLeft: false,
                                  ),
                                  // Draggable vertical handle
                                  Positioned(
                                    left: dividerX - 1.5,
                                    top: 0,
                                    bottom: 0,
                                    width: 3,
                                    child: Container(color: Colors.white),
                                  ),
                                  Positioned(
                                    left: dividerX - 18,
                                    top: constraints.maxHeight * 0.5 - 18,
                                    child: Container(
                                      width: 36,
                                      height: 36,
                                      decoration: BoxDecoration(
                                        color: c.accent,
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: Colors.white,
                                          width: 2,
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black
                                                .withValues(alpha: 0.35),
                                            blurRadius: 10,
                                          ),
                                        ],
                                      ),
                                      child: const Icon(
                                        Icons.code_rounded,
                                        color: Colors.white,
                                        size: 18,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ),
            ),

            const SizedBox(height: 14),

            // Delta summary + photo pickers
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: AppleCard(
                borderRadius: 22,
                padding: const EdgeInsets.all(14),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _CompareStat(
                          label: 'Time span',
                          value: '$daysBetween ${daysBetween == 1 ? 'day' : 'days'}',
                        ),
                        Container(width: 1, height: 28, color: c.divider),
                        _CompareStat(
                          label: 'Weight change',
                          value: weightDiffKg != null
                              ? '${weightDiffKg >= 0 ? '+' : ''}${WeightUnitHelper.format(weightDiffKg, widget.weightUnit)}'
                              : '--',
                        ),
                      ],
                    ),
                    if (widget.photos.length > 2) ...[
                      const SizedBox(height: 12),
                      Divider(height: 1, color: c.divider),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _CycleButton(
                              label:
                                  'Before: ${DateFormat('M/d').format(_before.takenAt.toLocal())}',
                              onTap: () {
                                HapticFeedback.selectionClick();
                                setState(() {
                                  _beforeIdx =
                                      (_beforeIdx + 1) % widget.photos.length;
                                });
                              },
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _CycleButton(
                              label:
                                  'After: ${DateFormat('M/d').format(_after.takenAt.toLocal())}',
                              onTap: () {
                                HapticFeedback.selectionClick();
                                setState(() {
                                  _afterIdx =
                                      (_afterIdx + 1) % widget.photos.length;
                                });
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
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

class _LeftClipper extends CustomClipper<Rect> {
  final double fraction;
  const _LeftClipper(this.fraction);

  @override
  Rect getClip(Size size) =>
      Rect.fromLTWH(0, 0, size.width * fraction, size.height);

  @override
  bool shouldReclip(covariant _LeftClipper oldClipper) =>
      oldClipper.fraction != fraction;
}

class _CornerLabel extends StatelessWidget {
  final String text;
  final bool alignLeft;

  const _CornerLabel({required this.text, required this.alignLeft});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 12,
      left: alignLeft ? 12 : null,
      right: alignLeft ? null : 12,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.56),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          text,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _CompareStat extends StatelessWidget {
  final String label;
  final String value;

  const _CompareStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            color: c.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w700,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(color: c.textTertiary, fontSize: 12),
        ),
      ],
    );
  }
}

class _CycleButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _CycleButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: c.searchBg,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: c.textPrimary,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              CupertinoIcons.chevron_up_chevron_down,
              size: 12,
              color: c.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}
