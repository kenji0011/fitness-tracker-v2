import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/active_profile_provider.dart';
import '../services/local_media_service.dart';
import '../services/tempo_rust_db.dart';
import '../theme/app_colors.dart';
import '../widgets/liquid_glass_surface.dart';
import '../widgets/tempo_sliver_header.dart';

class PhotoEditingScreen extends StatefulWidget {
  final String sourceImagePath;

  const PhotoEditingScreen({super.key, required this.sourceImagePath});

  @override
  State<PhotoEditingScreen> createState() => _PhotoEditingScreenState();
}

class _PhotoEditingScreenState extends State<PhotoEditingScreen> {
  final _captionCtrl = TextEditingController();
  final _weightCtrl = TextEditingController();
  String _category = 'Front';
  bool _saving = false;

  static const _categories = ['Front', 'Side', 'Back', 'General'];

  @override
  void initState() {
    super.initState();
    final profile = context.read<ActiveProfileProvider>().activeProfile;
    if (profile != null && profile.weightKg > 0) {
      _weightCtrl.text = profile.weightKg.toStringAsFixed(1);
    }
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

    setState(() => _saving = true);
    try {
      final storedPath = await LocalMediaService.saveProgressPhotoFile(
        profileId: pid,
        sourcePath: widget.sourceImagePath,
      );
      await TempoRustDb.instance.addProgressPhoto(
        profileId: pid,
        filePath: storedPath,
        caption: _captionCtrl.text.trim(),
        category: _category,
        weightKg: double.tryParse(_weightCtrl.text.trim()),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save photo: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);

    return Scaffold(
      backgroundColor: c.scaffold,
      body: CustomScrollView(
        slivers: [
          TempoSliverHeader(
            title: 'Save Photo',
            showBackButton: true,
            onBack: () => Navigator.of(context).pop(false),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            sliver: SliverList.list(
              children: [
                ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: !kIsWeb && File(widget.sourceImagePath).existsSync()
                ? Image.file(
                    File(widget.sourceImagePath),
                    height: 300,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  )
                : Container(
                    height: 240,
                    color: c.cardAlt,
                    child: Icon(CupertinoIcons.photo, size: 48, color: c.textTertiary),
                  ),
          ),
          const SizedBox(height: 18),
          AppleCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Pose / Tag',
                  style: TextStyle(
                    color: c.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: _categories.map((cat) {
                    final sel = cat == _category;
                    return ChoiceChip(
                      label: Text(cat),
                      selected: sel,
                      selectedColor: c.accent,
                      labelStyle: TextStyle(
                        color: sel ? Colors.white : c.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                      onSelected: (_) => setState(() => _category = cat),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 14),
                Text(
                  'Weight (kg, optional)',
                  style: TextStyle(
                    color: c.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _weightCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  style: TextStyle(color: c.textPrimary),
                ),
                const SizedBox(height: 14),
                Text(
                  'Note / Caption',
                  style: TextStyle(
                    color: c.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _captionCtrl,
                  maxLines: 2,
                  style: TextStyle(color: c.textPrimary),
                  decoration: InputDecoration(
                    hintText: 'Week 4 check-in...',
                    hintStyle: TextStyle(color: c.textHint),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
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
                      'Save Privately to Device',
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
