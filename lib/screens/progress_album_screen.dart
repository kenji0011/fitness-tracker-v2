import 'dart:io';
import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  static const double _kgToLb = 2.20462262;

  final ImagePicker _picker = ImagePicker();
  List<LocalProgressPhoto> _photos = [];
  String _weightUnit = 'kg';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadPhotos();
  }

  Future<void> _loadPhotos() async {
    final pid = context.read<ActiveProfileProvider>().activeProfileId;
    if (pid == null) return;
    final results = await Future.wait([
      TempoRustDb.instance.listProgressPhotos(pid),
      TempoRustDb.instance.getSetting('weight_unit_$pid'),
    ]);
    if (mounted) {
      setState(() {
        _photos = results[0] as List<LocalProgressPhoto>;
        _weightUnit = (results[1] as String?) == 'lb' ? 'lb' : 'kg';
        _loading = false;
      });
    }
  }

  String _formatWeight(double kg) {
    final v = _weightUnit == 'lb' ? kg * _kgToLb : kg;
    return '${v.toStringAsFixed(1)} $_weightUnit';
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

  Future<bool> _confirmAndDeletePhoto(LocalProgressPhoto photo) async {
    final c = AppColors.of(context, listen: false);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(
          'Delete photo?',
          style: TextStyle(
            color: c.textPrimary,
            fontSize: 19,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Text(
          'This removes the progress photo permanently from local device storage.',
          style: TextStyle(color: c.textSecondary, fontSize: 14.5, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              'Cancel',
              style: TextStyle(
                color: c.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              'Delete',
              style: TextStyle(
                color: c.moveRed,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return false;

    await TempoRustDb.instance.deleteProgressPhoto(photo.id);
    await LocalMediaService.deleteLocalFile(photo.filePath);
    if (mounted) {
      context.read<ActiveProfileProvider>().notifyDataChanged();
      await _loadPhotos();
    }
    return true;
  }

  /// Native Material 3 Android bottom sheet used by both Add First Photo & the + button.
  void _showAddOptions() {
    HapticFeedback.selectionClick();
    final c = AppColors.of(context, listen: false);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: c.card,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) {
        final mc = AppColors.of(ctx);
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 2, 8, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Add progress photo',
                        style: TextStyle(
                          color: mc.textPrimary,
                          fontSize: 19,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Stored privately on your phone',
                        style: TextStyle(
                          color: mc.textSecondary,
                          fontSize: 13.5,
                        ),
                      ),
                    ],
                  ),
                ),
                Material(
                  color: mc.searchBg,
                  borderRadius: BorderRadius.circular(18),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      ListTile(
                        leading: Icon(
                          Icons.photo_camera_outlined,
                          color: mc.textPrimary,
                        ),
                        title: Text(
                          'Take photo',
                          style: TextStyle(
                            color: mc.textPrimary,
                            fontSize: 15.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        subtitle: Text(
                          'Capture a new check-in with camera',
                          style: TextStyle(
                            color: mc.textTertiary,
                            fontSize: 12.5,
                          ),
                        ),
                        onTap: () {
                          Navigator.of(ctx).pop();
                          _addPhoto(ImageSource.camera);
                        },
                      ),
                      Divider(
                        height: 1,
                        indent: 56,
                        color: mc.divider,
                      ),
                      ListTile(
                        leading: Icon(
                          Icons.photo_library_outlined,
                          color: mc.textPrimary,
                        ),
                        title: Text(
                          'Choose from gallery',
                          style: TextStyle(
                            color: mc.textPrimary,
                            fontSize: 15.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        subtitle: Text(
                          'Pick an existing photo from your device',
                          style: TextStyle(
                            color: mc.textTertiary,
                            fontSize: 12.5,
                          ),
                        ),
                        onTap: () {
                          Navigator.of(ctx).pop();
                          _addPhoto(ImageSource.gallery);
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                TextButton(
                  style: TextButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: Text(
                    'Cancel',
                    style: TextStyle(
                      color: mc.textSecondary,
                      fontSize: 15.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openViewer(int initialIndex) async {
    HapticFeedback.selectionClick();
    await Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: true,
        transitionDuration: const Duration(milliseconds: 260),
        reverseTransitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (_, animation, __) => FadeTransition(
          opacity: animation,
          child: _ProgressPhotoViewerScreen(
            photos: _photos,
            initialIndex: initialIndex,
            formatWeight: _formatWeight,
            onDeletePhoto: _confirmAndDeletePhoto,
          ),
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
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
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
                  padding: const EdgeInsets.all(24),
                  child: AppleCard(
                    borderRadius: 24,
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 60,
                          height: 60,
                          decoration: BoxDecoration(
                            color: c.accent.withValues(
                              alpha: c.isDark ? 0.18 : 0.10,
                            ),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            CupertinoIcons.photo_on_rectangle,
                            size: 28,
                            color: c.accent,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Private On-Device Album',
                          style: TextStyle(
                            color: c.textPrimary,
                            fontSize: 18.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.2,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Track your visual progress safely offline. Photos never leave your phone.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: c.textSecondary,
                            fontSize: 14,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 20),
                        SizedBox(
                          height: 48,
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: c.accent,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            onPressed: _showAddOptions,
                            icon: const Icon(
                              Icons.add_a_photo_outlined,
                              size: 18,
                            ),
                            label: const Text(
                              'Add First Photo',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 36),
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
                      onTap: () => _openViewer(i),
                      onLongPress: () => _confirmAndDeletePhoto(photo),
                      child: Hero(
                        tag: 'progress_photo_${photo.id}',
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              if (exists)
                                Image.file(
                                  File(photo.filePath),
                                  fit: BoxFit.cover,
                                )
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
                                top: 10,
                                left: 10,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 9,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.48),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    photo.category,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                              Positioned(
                                left: 0,
                                right: 0,
                                bottom: 0,
                                child: Container(
                                  padding: const EdgeInsets.fromLTRB(
                                    11,
                                    22,
                                    11,
                                    10,
                                  ),
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
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        DateFormat('MMM d, yyyy')
                                            .format(photo.takenAt.toLocal()),
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 12.5,
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
                                            fontSize: 11.5,
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
                    );
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Full-screen interactive gallery viewer for clicked Progress Album photos.
class _ProgressPhotoViewerScreen extends StatefulWidget {
  final List<LocalProgressPhoto> photos;
  final int initialIndex;
  final String Function(double kg) formatWeight;
  final Future<bool> Function(LocalProgressPhoto photo) onDeletePhoto;

  const _ProgressPhotoViewerScreen({
    required this.photos,
    required this.initialIndex,
    required this.formatWeight,
    required this.onDeletePhoto,
  });

  @override
  State<_ProgressPhotoViewerScreen> createState() =>
      _ProgressPhotoViewerScreenState();
}

class _ProgressPhotoViewerScreenState
    extends State<_ProgressPhotoViewerScreen> {
  late final PageController _pageCtrl;
  late List<LocalProgressPhoto> _items;
  late int _currentIndex;
  bool _showChrome = true;

  @override
  void initState() {
    super.initState();
    _items = List<LocalProgressPhoto>.from(widget.photos);
    _currentIndex = widget.initialIndex.clamp(0, _items.length - 1);
    _pageCtrl = PageController(initialPage: _currentIndex);
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleDelete() async {
    if (_items.isEmpty) return;
    final photo = _items[_currentIndex];
    final deleted = await widget.onDeletePhoto(photo);
    if (!deleted || !mounted) return;
    setState(() {
      _items.removeAt(_currentIndex);
      if (_currentIndex >= _items.length && _items.isNotEmpty) {
        _currentIndex = _items.length - 1;
      }
    });
    if (_items.isEmpty && mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_items.isEmpty) return const SizedBox.shrink();
    final photo = _items[_currentIndex];
    final topPad = MediaQuery.paddingOf(context).top;
    final bottomPad = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0C),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Swipeable pinch-to-zoom full-bleed photo canvas
          GestureDetector(
            onTap: () => setState(() => _showChrome = !_showChrome),
            child: PageView.builder(
              controller: _pageCtrl,
              itemCount: _items.length,
              onPageChanged: (i) {
                HapticFeedback.selectionClick();
                setState(() => _currentIndex = i);
              },
              itemBuilder: (_, i) {
                final item = _items[i];
                final exists = !kIsWeb && File(item.filePath).existsSync();
                return Center(
                  child: Hero(
                    tag: 'progress_photo_${item.id}',
                    child: InteractiveViewer(
                      minScale: 1.0,
                      maxScale: 4.0,
                      child: exists
                          ? Image.file(
                              File(item.filePath),
                              fit: BoxFit.contain,
                              width: double.infinity,
                              height: double.infinity,
                            )
                          : const Icon(
                              CupertinoIcons.photo,
                              color: Colors.white38,
                              size: 64,
                            ),
                    ),
                  ),
                );
              },
            ),
          ),

          // Floating top bar (Back | Date & Pose | Delete)
          AnimatedPositioned(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            top: _showChrome ? 0 : -(topPad + 80),
            left: 0,
            right: 0,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 200),
              opacity: _showChrome ? 1.0 : 0.0,
              child: Container(
                padding: EdgeInsets.fromLTRB(14, topPad + 10, 14, 18),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.72),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: Row(
                  children: [
                    _ViewerGlassButton(
                      icon: const TempoBackChevron(
                        color: Colors.white,
                        size: 20,
                      ),
                      onTap: () => Navigator.of(context).pop(),
                    ),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            DateFormat('MMM d, yyyy')
                                .format(photo.takenAt.toLocal()),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.2,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _items.length > 1
                                ? '${photo.category} · ${_currentIndex + 1} of ${_items.length}'
                                : photo.category,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    _ViewerGlassButton(
                      icon: const Icon(
                        CupertinoIcons.trash,
                        color: Color(0xFFFF5E57),
                        size: 19,
                      ),
                      onTap: _handleDelete,
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Floating frosted bottom metadata pill (Weight + Caption + Time)
          AnimatedPositioned(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            bottom: _showChrome ? bottomPad + 18 : -160,
            left: 18,
            right: 18,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 200),
              opacity: _showChrome ? 1.0 : 0.0,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1C1C20).withValues(alpha: 0.78),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.12),
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                photo.category,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              DateFormat('h:mm a')
                                  .format(photo.takenAt.toLocal()),
                              style: const TextStyle(
                                color: Colors.white60,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const Spacer(),
                            if (photo.weightKg != null)
                              Text(
                                widget.formatWeight(photo.weightKg!),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 15.5,
                                  fontWeight: FontWeight.w700,
                                  fontFeatures: [FontFeature.tabularFigures()],
                                ),
                              ),
                          ],
                        ),
                        if (photo.caption.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            photo.caption,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 13.5,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ViewerGlassButton extends StatelessWidget {
  final Widget icon;
  final VoidCallback onTap;

  const _ViewerGlassButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: ClipOval(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.42),
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.16),
              ),
            ),
            child: Center(child: icon),
          ),
        ),
      ),
    );
  }
}
