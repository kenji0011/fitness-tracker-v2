import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../services/active_profile_provider.dart';
import '../services/local_media_service.dart';
import '../services/tempo_rust_db.dart';
import '../theme/app_colors.dart';
import '../widgets/liquid_glass_surface.dart';
import '../widgets/tempo_sliver_header.dart';
import '../widgets/tempo_toast.dart';

class PhotoEditingScreen extends StatefulWidget {
  final String sourceImagePath;

  const PhotoEditingScreen({super.key, required this.sourceImagePath});

  @override
  State<PhotoEditingScreen> createState() => _PhotoEditingScreenState();
}

class _PhotoEditingScreenState extends State<PhotoEditingScreen> {
  static const double _kgToLb = 2.20462262;
  static const _categories = ['Front', 'Side', 'Back', 'General'];

  final _captionCtrl = TextEditingController();
  final _weightCtrl = TextEditingController();
  String _category = 'Front';
  String _weightUnit = 'kg';
  bool _fitContain = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadDefaults();
  }

  Future<void> _loadDefaults() async {
    final provider = context.read<ActiveProfileProvider>();
    final pid = provider.activeProfileId;
    final profile = provider.activeProfile;
    if (pid != null) {
      final savedUnit = await TempoRustDb.instance.getSetting('weight_unit_$pid');
      if (mounted && savedUnit == 'lb') {
        _weightUnit = 'lb';
      }
    }
    if (!mounted) return;
    if (profile != null && profile.weightKg > 0) {
      final displayWeight = _weightUnit == 'lb'
          ? profile.weightKg * _kgToLb
          : profile.weightKg;
      _weightCtrl.text = displayWeight.toStringAsFixed(1);
    }
    setState(() {});
  }

  @override
  void dispose() {
    _captionCtrl.dispose();
    _weightCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveLocally() async {
    final pid = context.read<ActiveProfileProvider>().activeProfileId;
    if (pid == null) return;

    HapticFeedback.lightImpact();
    setState(() => _saving = true);
    try {
      final parsedWeight = double.tryParse(_weightCtrl.text.trim());
      final weightKg = parsedWeight == null
          ? null
          : (_weightUnit == 'lb' ? parsedWeight / _kgToLb : parsedWeight);

      final storedPath = await LocalMediaService.saveProgressPhotoFile(
        profileId: pid,
        sourcePath: widget.sourceImagePath,
      );
      await TempoRustDb.instance.addProgressPhoto(
        profileId: pid,
        filePath: storedPath,
        caption: _captionCtrl.text.trim(),
        category: _category,
        weightKg: weightKg,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showTempoToast(context, 'Could not save photo: $e', isError: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final hasFile = LocalMediaService.fileExistsCached(widget.sourceImagePath);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final previewDecodePx =
        (MediaQuery.sizeOf(context).width * dpr).round().clamp(480, 1440);
    final selectedIdx = _categories.indexOf(_category).clamp(0, _categories.length - 1);
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      backgroundColor: c.scaffold,
      body: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        slivers: [
          TempoSliverHeader(
            title: 'Save Photo',
            showBackButton: true,
            onBack: () => Navigator.of(context).pop(false),
          ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(18, 6, 18, bottomInset + 32),
            sliver: SliverList.list(
              children: [
                // Framed Photo Preview with Fit/Fill toggle & live overlay tag
                Container(
                  height: 340,
                  decoration: BoxDecoration(
                    color: c.isDark
                        ? const Color(0xFF141416)
                        : const Color(0xFF1C1C1E),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: c.isDark
                          ? Colors.white.withValues(alpha: 0.08)
                          : Colors.black.withValues(alpha: 0.06),
                    ),
                    boxShadow: c.isDark
                        ? null
                        : [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.08),
                              blurRadius: 18,
                              offset: const Offset(0, 8),
                            ),
                          ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(23),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (hasFile)
                          Image.file(
                            File(widget.sourceImagePath),
                            cacheWidth: previewDecodePx,
                            gaplessPlayback: true,
                            filterQuality: FilterQuality.medium,
                            fit: _fitContain ? BoxFit.contain : BoxFit.cover,
                          )
                        else
                          Center(
                            child: Icon(
                              CupertinoIcons.photo,
                              size: 48,
                              color: c.textTertiary,
                            ),
                          ),
                        // Subtle bottom scrim with live preview metadata
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: Container(
                            padding: const EdgeInsets.fromLTRB(14, 24, 14, 12),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.transparent,
                                  Colors.black.withValues(alpha: 0.68),
                                ],
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.18),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    _category,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  DateFormat('MMM d, yyyy')
                                      .format(DateTime.now()),
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const Spacer(),
                                GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: () {
                                    HapticFeedback.selectionClick();
                                    setState(() => _fitContain = !_fitContain);
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 5,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(alpha: 0.45),
                                      borderRadius: BorderRadius.circular(999),
                                      border: Border.all(
                                        color: Colors.white.withValues(alpha: 0.18),
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          _fitContain
                                              ? Icons.crop_free_rounded
                                              : Icons.fit_screen_rounded,
                                          size: 14,
                                          color: Colors.white,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          _fitContain ? 'Fill' : 'Fit',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
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
                ),

                const SizedBox(height: 16),

                // Details Card matching Tempo's clean input styling
                AppleCard(
                  borderRadius: 24,
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Pose',
                        style: TextStyle(
                          color: c.textSecondary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 10),
                      // Sliding segment bar (consistent with Weight/Sleep)
                      Container(
                        height: 40,
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: c.isDark
                              ? const Color(0xFF1C1C1E)
                              : Colors.black.withValues(alpha: 0.055),
                          borderRadius: BorderRadius.circular(13),
                        ),
                        child: LayoutBuilder(
                          builder: (_, constraints) {
                            final segW =
                                constraints.maxWidth / _categories.length;
                            return Stack(
                              children: [
                                AnimatedPositioned(
                                  duration: const Duration(milliseconds: 220),
                                  curve: Curves.easeOutCubic,
                                  left: selectedIdx * segW,
                                  top: 0,
                                  bottom: 0,
                                  width: segW,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: c.isDark
                                          ? const Color(0xFF323338)
                                          : c.card,
                                      borderRadius: BorderRadius.circular(10),
                                      boxShadow: c.isDark
                                          ? null
                                          : [
                                              BoxShadow(
                                                color: Colors.black
                                                    .withValues(alpha: 0.06),
                                                blurRadius: 6,
                                                offset: const Offset(0, 2),
                                              ),
                                            ],
                                    ),
                                  ),
                                ),
                                Row(
                                  children:
                                      List.generate(_categories.length, (i) {
                                    final cat = _categories[i];
                                    final sel = i == selectedIdx;
                                    return Expanded(
                                      child: GestureDetector(
                                        behavior: HitTestBehavior.opaque,
                                        onTap: () {
                                          HapticFeedback.selectionClick();
                                          setState(() => _category = cat);
                                        },
                                        child: Center(
                                          child: Text(
                                            cat,
                                            style: TextStyle(
                                              color: sel
                                                  ? c.textPrimary
                                                  : c.textSecondary,
                                              fontSize: 13.5,
                                              fontWeight: sel
                                                  ? FontWeight.w600
                                                  : FontWeight.w500,
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
                      ),

                      const SizedBox(height: 16),

                      Text(
                        'Weight (optional)',
                        style: TextStyle(
                          color: c.textSecondary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _weightCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        style: TextStyle(
                          color: c.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                        decoration: InputDecoration(
                          hintText: _weightUnit == 'lb' ? 'e.g. 140.0' : 'e.g. 63.5',
                          hintStyle: TextStyle(color: c.textHint),
                          suffixText: _weightUnit,
                          suffixStyle: TextStyle(
                            color: c.textSecondary,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                          filled: true,
                          fillColor: c.searchBg,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 13,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),

                      const SizedBox(height: 16),

                      Text(
                        'Note',
                        style: TextStyle(
                          color: c.textSecondary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _captionCtrl,
                        maxLines: 2,
                        style: TextStyle(
                          color: c.textPrimary,
                          fontSize: 15,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Week 4 check-in...',
                          hintStyle: TextStyle(color: c.textHint),
                          filled: true,
                          fillColor: c.searchBg,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 18),

                // Consistent action buttons row (Discard + Save photo)
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: SizedBox(
                        height: 52,
                        child: TextButton(
                          style: TextButton.styleFrom(
                            backgroundColor: c.searchBg,
                            foregroundColor: c.textPrimary,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          onPressed: _saving
                              ? null
                              : () => Navigator.of(context).pop(false),
                          child: Text(
                            'Discard',
                            style: TextStyle(
                              color: c.textPrimary,
                              fontSize: 15.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 3,
                      child: SizedBox(
                        height: 52,
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: c.accent,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          onPressed: _saving ? null : _saveLocally,
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
                                  'Save photo',
                                  style: TextStyle(
                                    fontSize: 15.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
