import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/local_profile.dart';
import '../services/active_profile_provider.dart';
import '../services/local_media_service.dart';
import '../services/tempo_rust_db.dart';
import '../theme/app_colors.dart';
import '../widgets/liquid_glass_surface.dart';
import '../widgets/tempo_sliver_header.dart';
import 'photo_editing_screen.dart';

class ProgressAlbumScreen extends StatefulWidget {
  const ProgressAlbumScreen({super.key});

  @override
  State<ProgressAlbumScreen> createState() => _ProgressAlbumScreenState();
}

class _ProgressAlbumScreenState extends State<ProgressAlbumScreen> {
  final ImagePicker _picker = ImagePicker();
  List<LocalProgressPhoto> _photos = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadPhotos();
  }

  Future<void> _loadPhotos() async {
    final pid = context.read<ActiveProfileProvider>().activeProfileId;
    if (pid == null) return;
    final list = await TempoRustDb.instance.listProgressPhotos(pid);
    if (mounted) {
      setState(() {
        _photos = list;
        _loading = false;
      });
    }
  }

  Future<void> _addPhoto(ImageSource source) async {
    final xfile = await _picker.pickImage(source: source, imageQuality: 88);
    if (xfile == null || !mounted) return;

    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => PhotoEditingScreen(sourceImagePath: xfile.path),
      ),
    );
    if (saved == true && mounted) {
      context.read<ActiveProfileProvider>().notifyDataChanged();
      _loadPhotos();
    }
  }

  Future<void> _deletePhoto(LocalProgressPhoto photo) async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Delete Photo?'),
        content: const Text(
          'This removes the progress photo from local device storage.',
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await TempoRustDb.instance.deleteProgressPhoto(photo.id);
    await LocalMediaService.deleteLocalFile(photo.filePath);
    if (mounted) {
      context.read<ActiveProfileProvider>().notifyDataChanged();
      _loadPhotos();
    }
  }

  void _showAddOptions() {
    showCupertinoModalPopup<void>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: const Text('Add Progress Photo'),
        message: const Text('Stored privately on your phone'),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.of(ctx).pop();
              _addPhoto(ImageSource.camera);
            },
            child: const Text('Take Photo'),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.of(ctx).pop();
              _addPhoto(ImageSource.gallery);
            },
            child: const Text('Choose from Library'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          isDefaultAction: true,
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Cancel'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);

    return Scaffold(
      backgroundColor: c.scaffold,
      body: CustomScrollView(
        slivers: [
          TempoSliverHeader(
            title: 'Progress Album',
            showBackButton: true,
            actions: [
              TempoHeaderAction(
                tooltip: 'Add Photo',
                icon: Icon(CupertinoIcons.add, size: 22, color: c.textPrimary),
                onPressed: _showAddOptions,
              ),
            ],
          ),
          if (_loading)
            SliverFillRemaining(
              child: Center(child: CupertinoActivityIndicator(color: c.accent)),
            )
          else if (_photos.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: AppleCard(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          CupertinoIcons.photo_on_rectangle,
                          size: 46,
                          color: c.accent,
                        ),
                        const SizedBox(height: 14),
                        Text(
                          'Private On-Device Album',
                          style: TextStyle(
                            color: c.textPrimary,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Track your visual progress safely offline. Photos never leave your phone.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: c.textSecondary),
                        ),
                        const SizedBox(height: 18),
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: c.accent,
                            foregroundColor: Colors.white,
                          ),
                          onPressed: _showAddOptions,
                          icon: const Icon(CupertinoIcons.camera_fill, size: 18),
                          label: const Text('Add First Photo'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.all(16),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 0.78,
                ),
                delegate: SliverChildBuilderDelegate(
                  childCount: _photos.length,
                  (ctx, i) {
                    final photo = _photos[i];
                    final exists =
                        !kIsWeb && File(photo.filePath).existsSync();
                    return GestureDetector(
                      onTap: () => _openViewer(photo),
                      onLongPress: () => _deletePhoto(photo),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            if (exists)
                              Image.file(File(photo.filePath), fit: BoxFit.cover)
                            else
                              Container(
                                color: c.cardAlt,
                                child: Icon(
                                  CupertinoIcons.photo,
                                  color: c.textTertiary,
                                  size: 36,
                                ),
                              ),
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom: 0,
                              child: Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      Colors.transparent,
                                      Colors.black.withValues(alpha: 0.78),
                                    ],
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      DateFormat('MMM d, yyyy')
                                          .format(photo.takenAt.toLocal()),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    if (photo.caption.isNotEmpty)
                                      Text(
                                        photo.caption,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Colors.white70,
                                          fontSize: 11,
                                        ),
                                      ),
                                  ],
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
            ),
        ],
      ),
    );
  }

  void _openViewer(LocalProgressPhoto photo) {
    final c = AppColors.of(context, listen: false);
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: c.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!kIsWeb && File(photo.filePath).existsSync())
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 420),
                child: Image.file(File(photo.filePath), fit: BoxFit.cover),
              ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${photo.category} • ${DateFormat('MMM d, yyyy').format(photo.takenAt.toLocal())}',
                        style: TextStyle(
                          color: c.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (photo.weightKg != null)
                        Text(
                          '${photo.weightKg!.toStringAsFixed(1)} kg',
                          style: TextStyle(
                            color: c.accent,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                    ],
                  ),
                  if (photo.caption.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      photo.caption,
                      style: TextStyle(color: c.textSecondary),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () {
                          Navigator.of(ctx).pop();
                          _deletePhoto(photo);
                        },
                        child: Text(
                          'Delete',
                          style: TextStyle(color: c.moveRed),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        child: const Text('Close'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
