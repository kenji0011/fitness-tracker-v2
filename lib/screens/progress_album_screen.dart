import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:jiggicons/jiggicons.dart';
import 'package:provider/provider.dart';

import '../models/local_profile.dart';
import '../services/active_profile_provider.dart';
import '../services/animation_speed_service.dart';
import '../services/local_media_service.dart';
import '../services/tempo_rust_db.dart';
import '../theme/app_colors.dart';
import '../widgets/ios_stretch_sheet.dart';
import '../widgets/liquid_glass_surface.dart';
import '../widgets/tempo_jigg_icon.dart';
import '../widgets/tempo_morph_route.dart';
import '../widgets/tempo_sliver_header.dart';
import '../widgets/tempo_spring_physics.dart';
import 'photo_compare_screen.dart';
import 'photo_editing_screen.dart';

/// Shared helper to compute the exact `BoxFit.contain` display rect inside
/// [screen] for a photo of any natural aspect ratio (portrait, square, or
/// landscape). Using this exact target rect makes a `BoxFit.cover` morph
/// continuously un-crop into a 1:1 pixel match with `BoxFit.contain` at t=1.
Rect _computeViewerPhotoRect(Size screen, double? aspectRatio) {
  final aspect =
      (aspectRatio != null && aspectRatio.isFinite && aspectRatio > 0.05)
          ? aspectRatio
          : 0.78;
  final screenAspect = screen.width / math.max(1.0, screen.height);
  final Size fitted = aspect >= screenAspect
      ? Size(screen.width, screen.width / aspect)
      : Size(screen.height * aspect, screen.height);
  return Alignment.center.inscribe(fitted, Offset.zero & screen);
}

int _computeAlbumTileDecodePx(BuildContext context) {
  final dpr = MediaQuery.devicePixelRatioOf(context);
  return (MediaQuery.sizeOf(context).width * 0.60 * dpr).round().clamp(360, 1080);
}

int _computeViewerDecodePx(BuildContext context) {
  final dpr = MediaQuery.devicePixelRatioOf(context);
  return (MediaQuery.sizeOf(context).width * dpr * 1.35)
      .round()
      .clamp(1080, 1920);
}

class ProgressAlbumScreen extends StatefulWidget {
  const ProgressAlbumScreen({super.key});

  @override
  State<ProgressAlbumScreen> createState() => _ProgressAlbumScreenState();
}

class _ProgressAlbumScreenState extends State<ProgressAlbumScreen> {
  static const double _kgToLb = 2.20462262;

  final ImagePicker _picker = ImagePicker();
  final Map<String, GlobalKey> _tileKeys = {};
  final Map<String, double> _photoAspectRatios = {};
  final ValueNotifier<String?> _hiddenPhotoId = ValueNotifier<String?>(null);
  List<LocalProgressPhoto> _photos = [];
  String _weightUnit = 'kg';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadPhotos();
  }

  @override
  void dispose() {
    _hiddenPhotoId.dispose();
    super.dispose();
  }

  GlobalKey _tileKeyFor(String id) =>
      _tileKeys.putIfAbsent(id, GlobalKey.new);

  Rect? _captureTileRect(String photoId) {
    final tileCtx = _tileKeys[photoId]?.currentContext;
    if (tileCtx == null || !tileCtx.mounted) return null;
    final box = tileCtx.findRenderObject();
    if (box is! RenderBox || !box.hasSize || !box.attached) return null;
    final size = box.size;
    if (size.width <= 1 || size.height <= 1) return null;

    RenderBox? ancestor;
    if (mounted) {
      final overlay = Overlay.maybeOf(context);
      final overlayObj = overlay?.context.findRenderObject();
      if (overlayObj is RenderBox && overlayObj.attached) {
        ancestor = overlayObj;
      }
    }
    final topLeft = box.localToGlobal(Offset.zero, ancestor: ancestor);
    if (!topLeft.dx.isFinite || !topLeft.dy.isFinite) return null;
    return topLeft & size;
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

    final saved = await pushTempoMorphRoute<bool>(
      context: context,
      sourceBorderRadius: 24,
      builder: (_) => PhotoEditingScreen(sourceImagePath: xfile.path),
    );
    if (saved == true && mounted) {
      context.read<ActiveProfileProvider>().notifyDataChanged();
      _loadPhotos();
    }
  }

  Future<bool> _confirmAndDeletePhoto(LocalProgressPhoto photo) async {
    final c = AppColors.of(context, listen: false);
    final confirmed = await showTempoSheet<bool>(
      context: context,
      backgroundColor: c.card,
      borderRadius: 28,
      showDragHandle: true,
      builder: (ctx) {
        final mc = AppColors.of(ctx);
        return Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            10,
            20,
            MediaQuery.paddingOf(ctx).bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Delete photo?',
                style: TextStyle(
                  color: mc.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'This removes the progress photo permanently from local device storage.',
                style: TextStyle(
                  color: mc.textSecondary,
                  fontSize: 14,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 48,
                      child: TextButton(
                        style: TextButton.styleFrom(
                          backgroundColor: mc.searchBg,
                          foregroundColor: mc.textPrimary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        onPressed: () => Navigator.of(ctx).pop(false),
                        child: const Text(
                          'Cancel',
                          style: TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SizedBox(
                      height: 48,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: mc.moveRed,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        onPressed: () => Navigator.of(ctx).pop(true),
                        child: const Text(
                          'Delete',
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
        );
      },
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

  /// Unified Tempo spring & stretch sheet used by both Add First Photo & the + button.
  void _showAddOptions() {
    HapticFeedback.selectionClick();
    final c = AppColors.of(context, listen: false);
    showTempoSheet<void>(
      context: context,
      backgroundColor: c.card,
      borderRadius: 28,
      showDragHandle: true,
      builder: (ctx) {
        final mc = AppColors.of(ctx);
        return Padding(
          padding: EdgeInsets.fromLTRB(
            18,
            6,
            18,
            MediaQuery.paddingOf(ctx).bottom + 18,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 2, 4, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Add progress photo',
                      style: TextStyle(
                        color: mc.textPrimary,
                        fontSize: 20,
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
                      leading: TempoJiggIcon(
                        'camera',
                        variant: JiggIconVariant.outline,
                        size: 22,
                        color: mc.textPrimary,
                        trigger: JiggIconTrigger.appear,
                        fallbackIcon: Icons.photo_camera_outlined,
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
              const SizedBox(height: 12),
              SizedBox(
                height: 48,
                child: TextButton(
                  style: TextButton.styleFrom(
                    backgroundColor: mc.searchBg,
                    foregroundColor: mc.textPrimary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: Text(
                    'Cancel',
                    style: TextStyle(
                      color: mc.textPrimary,
                      fontSize: 15.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openViewer(int initialIndex) async {
    if (initialIndex < 0 || initialIndex >= _photos.length) return;
    HapticFeedback.selectionClick();
    final tapped = _photos[initialIndex];
    final initialRect = _captureTileRect(tapped.id);
    final tileDecodePx = _computeAlbumTileDecodePx(context);

    await Navigator.of(context).push<void>(
      _PhotoMorphViewerRoute(
        photos: _photos,
        initialIndex: initialIndex,
        initialTileRect: initialRect,
        tileDecodePx: tileDecodePx,
        aspectRatios: _photoAspectRatios,
        tileRectGetter: _captureTileRect,
        hiddenPhotoIdNotifier: _hiddenPhotoId,
        formatWeight: _formatWeight,
        onDeletePhoto: _confirmAndDeletePhoto,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final tileDecodePx = _computeAlbumTileDecodePx(context);

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
              if (_photos.length >= 2)
                TempoHeaderAction(
                  tooltip: 'Compare Photos',
                  icon: Icon(
                    Icons.compare_rounded,
                    size: 21,
                    color: c.textPrimary,
                  ),
                  onPressed: () {
                    HapticFeedback.selectionClick();
                    pushTempoMorphRoute<void>(
                      context: context,
                      sourceBorderRadius: 24,
                      builder: (_) => PhotoCompareScreen(
                        photos: _photos,
                        weightUnit: _weightUnit,
                      ),
                    );
                  },
                ),
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
                          child: Center(
                            child: TempoJiggIcon(
                              'camera',
                              variant: JiggIconVariant.duotone,
                              size: 30,
                              color: c.accent,
                              trigger: JiggIconTrigger.appear,
                              fallbackIcon: CupertinoIcons.photo_on_rectangle,
                            ),
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
                        LocalMediaService.fileExistsCached(photo.filePath);
                    final tileChild = GestureDetector(
                      onTap: () => _openViewer(i),
                      onLongPress: () => _confirmAndDeletePhoto(photo),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            if (exists)
                              _AlbumGridPhotoImage(
                                filePath: photo.filePath,
                                decodeWidth: tileDecodePx,
                                onAspectRatioResolved: (aspect) {
                                  _photoAspectRatios[photo.id] = aspect;
                                },
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
                                  crossAxisAlignment: CrossAxisAlignment.start,
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
                    );
                    return RepaintBoundary(
                      key: _tileKeyFor(photo.id),
                      child: ValueListenableBuilder<String?>(
                        valueListenable: _hiddenPhotoId,
                        child: tileChild,
                        builder: (_, hiddenId, child) => Opacity(
                          opacity: hiddenId == photo.id ? 0.0 : 1.0,
                          child: child,
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

/// Renders a cached grid thumbnail and records the photo's true natural aspect
/// ratio (portrait, square, or landscape) as soon as its image stream resolves
/// so open/close morph flights target the exact `BoxFit.contain` display rect.
class _AlbumGridPhotoImage extends StatefulWidget {
  final String filePath;
  final int decodeWidth;
  final ValueChanged<double> onAspectRatioResolved;

  const _AlbumGridPhotoImage({
    required this.filePath,
    required this.decodeWidth,
    required this.onAspectRatioResolved,
  });

  @override
  State<_AlbumGridPhotoImage> createState() => _AlbumGridPhotoImageState();
}

class _AlbumGridPhotoImageState extends State<_AlbumGridPhotoImage> {
  ImageProvider? _provider;
  ImageStream? _stream;
  ImageStreamListener? _listener;

  @override
  void initState() {
    super.initState();
    _provider = ResizeImage(
      FileImage(File(widget.filePath)),
      width: widget.decodeWidth,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _listenForAspectRatio();
  }

  @override
  void didUpdateWidget(covariant _AlbumGridPhotoImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filePath != widget.filePath ||
        oldWidget.decodeWidth != widget.decodeWidth) {
      _detachListener();
      _provider = ResizeImage(
        FileImage(File(widget.filePath)),
        width: widget.decodeWidth,
      );
      _listenForAspectRatio();
    }
  }

  void _listenForAspectRatio() {
    final provider = _provider;
    if (provider == null) return;
    final newStream = provider.resolve(createLocalImageConfiguration(context));
    if (newStream.key == _stream?.key) return;
    _detachListener();
    _stream = newStream;
    _listener = ImageStreamListener(
      (ImageInfo info, bool _) {
        final w = info.image.width.toDouble();
        final h = info.image.height.toDouble();
        if (w > 0 && h > 0) {
          widget.onAspectRatioResolved(w / h);
        }
      },
      onError: (_, __) {},
    );
    _stream!.addListener(_listener!);
  }

  void _detachListener() {
    if (_stream != null && _listener != null) {
      _stream!.removeListener(_listener!);
    }
    _stream = null;
    _listener = null;
  }

  @override
  void dispose() {
    _detachListener();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Image(
      image: _provider!,
      gaplessPlayback: true,
      filterQuality: FilterQuality.medium,
      fit: BoxFit.cover,
    );
  }
}

/// Shared mutable flight state kept in sync between the full-screen viewer and
/// [_PhotoMorphViewerRoute] so closing (via back button, edge swipe, or pull
/// down to dismiss) morphs seamlessly from the photo's exact live position back
/// into the matching grid tile—even after swiping to another photo.
class _PhotoViewerFlightState {
  LocalProgressPhoto? activePhoto;
  Offset dragOffset = Offset.zero;
  double dragScale = 1.0;
  double dragRadius = 0.0;

  _PhotoViewerFlightState({required this.activePhoto});
}

/// Apple Photos / HyperOS Gallery-style orientation-aware morph route.
///
/// Key smoothness guarantees across portrait, square, and landscape photos:
/// - Computes the photo's exact `BoxFit.contain` display rect from its natural
///   aspect ratio so `BoxFit.cover` continuously un-crops from the grid tile
///   into a 100% pixel-exact match on landing (zero aspect-ratio snap/stutter).
/// - Flies using the grid tile's already-cached `ResizeImage` GPU texture
///   (zero Frame-0 12MP JPEG decode hitch), while pre-warming crisp viewer
///   resolution offstage during the 420ms flight.
/// - Keeps `PageView`, `InteractiveViewer`, and `BackdropFilter` offstage
///   during open/close flight so Impeller renders a single textured quad at 120Hz.
class _PhotoMorphViewerRoute extends PageRoute<void> {
  final List<LocalProgressPhoto> photos;
  final int initialIndex;
  final Rect? initialTileRect;
  final int tileDecodePx;
  final Map<String, double> aspectRatios;
  final Rect? Function(String photoId) tileRectGetter;
  final ValueNotifier<String?> hiddenPhotoIdNotifier;
  final String Function(double kg) formatWeight;
  final Future<bool> Function(LocalProgressPhoto photo) onDeletePhoto;

  late final _PhotoViewerFlightState _flightState;
  late final String? _initialPhotoId;
  Rect? _cachedCloseStartRect;
  Rect? _cachedCloseEndRect;
  double _cachedCloseStartRadius = 0.0;
  bool _capturedCloseGeometry = false;
  bool _attachedStatusListener = false;
  bool _disposed = false;

  static final Curve _openCurve = TempoSpringCurves.photoOpen;
  static final Curve _closeCurve = TempoSpringCurves.photoClose;

  _PhotoMorphViewerRoute({
    required this.photos,
    required this.initialIndex,
    required this.initialTileRect,
    required this.tileDecodePx,
    required this.aspectRatios,
    required this.tileRectGetter,
    required this.hiddenPhotoIdNotifier,
    required this.formatWeight,
    required this.onDeletePhoto,
  }) {
    final safeIdx = photos.isEmpty
        ? 0
        : initialIndex.clamp(0, photos.length - 1);
    final initialPhoto = photos.isEmpty ? null : photos[safeIdx];
    _initialPhotoId = initialPhoto?.id;
    _flightState = _PhotoViewerFlightState(activePhoto: initialPhoto);
  }

  @override
  bool get opaque => true;

  @override
  bool get barrierDismissible => false;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  bool get maintainState => true;

  @override
  Duration get transitionDuration =>
      TempoAnimationSpeedService.instance.scale(const Duration(milliseconds: 420));

  @override
  Duration get reverseTransitionDuration =>
      TempoAnimationSpeedService.instance.scale(const Duration(milliseconds: 360));

  @override
  Widget buildModalBarrier() {
    final anim = animation;
    if (anim == null) return const SizedBox.shrink();
    return AnimatedBuilder(
      animation: anim,
      builder: (context, _) {
        if (anim.status == AnimationStatus.reverse ||
            anim.status == AnimationStatus.dismissed) {
          return const SizedBox.shrink();
        }
        return super.buildModalBarrier();
      },
    );
  }

  void _setHiddenTileSync(String? targetId) {
    if (hiddenPhotoIdNotifier.value == targetId) return;
    hiddenPhotoIdNotifier.value = targetId;
  }

  void _handleRouteStatusChanged(AnimationStatus status) {
    if (_disposed) return;
    final photo = _flightState.activePhoto;
    switch (status) {
      case AnimationStatus.forward:
        _setHiddenTileSync(
          (photo != null && initialTileRect != null) ? photo.id : null,
        );
      case AnimationStatus.completed:
        _setHiddenTileSync(null);
      case AnimationStatus.reverse:
        if (photo != null) {
          final hasTile = tileRectGetter(photo.id) != null ||
              (photo.id == _initialPhotoId && initialTileRect != null);
          _setHiddenTileSync(hasTile ? photo.id : null);
        } else {
          _setHiddenTileSync(null);
        }
      case AnimationStatus.dismissed:
        _setHiddenTileSync(null);
    }
  }

  @override
  void install() {
    super.install();
    if (!_attachedStatusListener && animation != null) {
      _attachedStatusListener = true;
      animation!.addStatusListener(_handleRouteStatusChanged);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    if (_attachedStatusListener) {
      animation?.removeStatusListener(_handleRouteStatusChanged);
      _attachedStatusListener = false;
    }
    // Synchronously restore grid tile visibility so it can never remain hidden
    // on an idle post-dismiss frame.
    _setHiddenTileSync(null);
    super.dispose();
  }

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return _ProgressPhotoViewerScreen(
      photos: photos,
      initialIndex: initialIndex,
      tileDecodePx: tileDecodePx,
      aspectRatios: aspectRatios,
      flightState: _flightState,
      formatWeight: formatWeight,
      onDeletePhoto: onDeletePhoto,
      routeAnimation: animation,
    );
  }

  Rect _computeDraggedViewerRect(Size screen, LocalProgressPhoto photo) {
    final base = _computeViewerPhotoRect(screen, aspectRatios[photo.id]);
    final dragScale = _flightState.dragScale;
    final dragOffset = _flightState.dragOffset;
    if (dragOffset == Offset.zero && (dragScale - 1.0).abs() < 0.001) {
      return base;
    }
    final screenCenter = Offset(screen.width / 2.0, screen.height / 2.0);
    final shiftedCenter = screenCenter + dragOffset;
    return Rect.fromCenter(
      center: shiftedCenter,
      width: base.width * dragScale,
      height: base.height * dragScale,
    );
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (MediaQuery.disableAnimationsOf(context)) {
      return FadeTransition(opacity: animation, child: child);
    }

    final rawT = animation.value.clamp(0.0, 1.0);
    final settled = rawT >= 0.999 &&
        (animation.status == AnimationStatus.completed ||
            animation.status == AnimationStatus.forward);

    // Keep child in a persistent Stack slot (never reparenting on settle) so
    // _ProgressPhotoViewerScreen preserves State and swaps onstage with zero
    // GlobalKey reparent hiccup at t == 1.0.
    if (settled) {
      _capturedCloseGeometry = false;
      return Stack(
        fit: StackFit.expand,
        children: [
          Offstage(offstage: false, child: child),
        ],
      );
    }

    final photo = _flightState.activePhoto;
    if (photo == null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          FadeTransition(opacity: animation, child: child),
        ],
      );
    }

    final screen = MediaQuery.sizeOf(context);
    final isClosing = animation.status == AnimationStatus.reverse ||
        animation.status == AnimationStatus.dismissed;

    Rect? startRect;
    Rect? endRect;
    double startRadius;
    double endRadius;
    double flightT;
    double bgAlpha;

    if (isClosing) {
      if (!_capturedCloseGeometry) {
        _capturedCloseGeometry = true;
        _cachedCloseStartRect = _computeDraggedViewerRect(screen, photo);
        _cachedCloseStartRadius = _flightState.dragRadius;
        final liveTile = tileRectGetter(photo.id) ??
            (photo.id == _initialPhotoId ? initialTileRect : null);
        final onScreen = liveTile != null &&
            liveTile.right > -40 &&
            liveTile.left < screen.width + 40 &&
            liveTile.bottom > -40 &&
            liveTile.top < screen.height + 40;
        _cachedCloseEndRect = onScreen ? liveTile : null;
      }
      final closeP = _closeCurve.transform(1.0 - rawT).clamp(0.0, 1.0);
      flightT = closeP;
      startRect = _cachedCloseStartRect ??
          _computeViewerPhotoRect(screen, aspectRatios[photo.id]);
      endRect = _cachedCloseEndRect;
      startRadius = _cachedCloseStartRadius;
      endRadius = 20.0;
      final dragAlphaFactor =
          (1.0 - (_flightState.dragOffset.dy.abs() / 260.0).clamp(0.0, 1.0) * 0.72)
              .clamp(0.28, 1.0);
      bgAlpha = ((1.0 - closeP) * dragAlphaFactor).clamp(0.0, 1.0);
    } else {
      _capturedCloseGeometry = false;
      final openT = _openCurve.transform(rawT).clamp(0.0, 1.0);
      flightT = openT;
      startRect = initialTileRect ??
          Rect.fromCenter(
            center: Offset(screen.width / 2.0, screen.height / 2.0),
            width: screen.width * 0.45,
            height: screen.width * 0.58,
          );
      endRect = _computeViewerPhotoRect(screen, aspectRatios[photo.id]);
      startRadius = 20.0;
      endRadius = 0.0;
      bgAlpha = openT;
    }

    final exists = LocalMediaService.fileExistsCached(photo.filePath);
    final Widget flyingPhotoWidget;
    if (exists) {
      final file = File(photo.filePath);
      final tileProvider = ResizeImage(FileImage(file), width: tileDecodePx);
      if (isClosing) {
        // On close, prefer the viewer's already-hot hi-res image in ImageCache
        // with instant fallback to the cached grid thumbnail (zero invisible frame).
        final viewerProvider = ResizeImage(
          FileImage(file),
          width: _computeViewerDecodePx(context),
        );
        flyingPhotoWidget = Image(
          image: viewerProvider,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          filterQuality: FilterQuality.medium,
          frameBuilder: (ctx, imgChild, frame, wasSync) {
            if (wasSync || frame != null) return imgChild;
            return Image(
              image: tileProvider,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              filterQuality: FilterQuality.medium,
            );
          },
        );
      } else {
        flyingPhotoWidget = Image(
          image: tileProvider,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          filterQuality: FilterQuality.medium,
        );
      }
    } else {
      flyingPhotoWidget = Container(
        color: const Color(0xFF1C1C20),
        child: const Center(
          child: Icon(
            CupertinoIcons.photo,
            color: Colors.white38,
            size: 48,
          ),
        ),
      );
    }

    // If closing to a tile scrolled offscreen, softly shrink & fade down.
    final bool hasTargetRect = endRect != null;
    final Rect curRect = hasTargetRect
        ? Rect.lerp(startRect, endRect, flightT)!
        : Rect.fromCenter(
            center: startRect.center + Offset(0, 72.0 * flightT),
            width: startRect.width * lerpDouble(1.0, 0.78, flightT)!,
            height: startRect.height * lerpDouble(1.0, 0.78, flightT)!,
          );
    final double curRadius =
        lerpDouble(startRadius, endRadius, flightT)!.clamp(0.0, 28.0);
    final double photoOpacity = hasTargetRect
        ? 1.0
        : (1.0 - Curves.easeOutCubic.transform(flightT)).clamp(0.0, 1.0);

    return Stack(
      fit: StackFit.expand,
      children: [
        // Keep the full viewer mounted Offstage during flight so hi-res images
        // warm asynchronously with zero paint or BackdropFilter churn.
        Offstage(offstage: true, child: child),
        if (bgAlpha > 0.004)
          IgnorePointer(
            child: ColoredBox(
              color: const Color(0xFF0A0A0C).withValues(alpha: bgAlpha),
            ),
          ),
        Positioned.fromRect(
          rect: curRect,
          child: IgnorePointer(
            child: Opacity(
              opacity: photoOpacity,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(curRadius),
                child: flyingPhotoWidget,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Full-screen interactive gallery viewer for Progress Album photos with
/// orientation-exact landing, instant cached preview -> hi-res upgrade,
/// pinch-to-zoom, swipe pagination, and pull-down-to-dismiss.
class _ProgressPhotoViewerScreen extends StatefulWidget {
  final List<LocalProgressPhoto> photos;
  final int initialIndex;
  final int tileDecodePx;
  final Map<String, double> aspectRatios;
  final _PhotoViewerFlightState flightState;
  final String Function(double kg) formatWeight;
  final Future<bool> Function(LocalProgressPhoto photo) onDeletePhoto;
  final Animation<double> routeAnimation;

  const _ProgressPhotoViewerScreen({
    required this.photos,
    required this.initialIndex,
    required this.tileDecodePx,
    required this.aspectRatios,
    required this.flightState,
    required this.formatWeight,
    required this.onDeletePhoto,
    required this.routeAnimation,
  });

  @override
  State<_ProgressPhotoViewerScreen> createState() =>
      _ProgressPhotoViewerScreenState();
}

class _ProgressPhotoViewerScreenState extends State<_ProgressPhotoViewerScreen>
    with TickerProviderStateMixin {
  late final PageController _pageCtrl;
  late final AnimationController _snapBackCtrl;
  late final AnimationController _chromeCtrl;
  final TransformationController _transformCtrl = TransformationController();
  late List<LocalProgressPhoto> _items;
  late int _currentIndex;
  bool _showChrome = true;
  bool _isZoomed = false;
  bool _isDraggingDismiss = false;
  bool _prewarmedInitialHiRes = false;
  Offset _dragOffset = Offset.zero;
  Offset _snapStartOffset = Offset.zero;

  @override
  void initState() {
    super.initState();
    _items = List<LocalProgressPhoto>.from(widget.photos);
    _currentIndex = _items.isEmpty
        ? 0
        : widget.initialIndex.clamp(0, _items.length - 1);
    _pageCtrl = PageController(initialPage: _currentIndex);
    _transformCtrl.addListener(_syncZoomState);
    _chromeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
      value: widget.routeAnimation.isCompleted ? 1.0 : 0.0,
    );
    widget.routeAnimation.addStatusListener(_handleRouteStatus);
    _snapBackCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    )..addListener(() {
        final t = Curves.easeOutCubic.transform(_snapBackCtrl.value);
        setState(() {
          _dragOffset = Offset.lerp(_snapStartOffset, Offset.zero, t)!;
          _syncFlightState();
        });
      });
    _syncFlightState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_prewarmedInitialHiRes && _items.isNotEmpty) {
      _prewarmedInitialHiRes = true;
      _prewarmHiResForIndex(_currentIndex);
    }
  }

  void _prewarmHiResForIndex(int index) {
    if (index < 0 || index >= _items.length) return;
    final photo = _items[index];
    if (!LocalMediaService.fileExistsCached(photo.filePath)) return;
    final viewerPx = _computeViewerDecodePx(context);
    final provider = ResizeImage(
      FileImage(File(photo.filePath)),
      width: viewerPx,
    );
    precacheImage(provider, context, onError: (_, __) {});
  }

  void _handleRouteStatus(AnimationStatus status) {
    if (!mounted) return;
    if (status == AnimationStatus.completed) {
      if (_showChrome) {
        _chromeCtrl.forward();
      }
    } else if (status == AnimationStatus.reverse) {
      _chromeCtrl.value = 0.0;
    }
  }

  void _syncFlightState() {
    widget.flightState.activePhoto =
        _items.isEmpty ? null : _items[_currentIndex];
    final dragProgress = (_dragOffset.dy.abs() / 260.0).clamp(0.0, 1.0);
    widget.flightState.dragOffset = _dragOffset;
    widget.flightState.dragScale = lerpDouble(1.0, 0.80, dragProgress)!;
    widget.flightState.dragRadius = lerpDouble(0.0, 22.0, dragProgress)!;
  }

  void _syncZoomState() {
    final zoomed = _transformCtrl.value.getMaxScaleOnAxis() > 1.04;
    if (zoomed != _isZoomed && mounted) {
      setState(() => _isZoomed = zoomed);
    }
  }

  @override
  void dispose() {
    widget.routeAnimation.removeStatusListener(_handleRouteStatus);
    _transformCtrl.removeListener(_syncZoomState);
    _transformCtrl.dispose();
    _snapBackCtrl.dispose();
    _chromeCtrl.dispose();
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
      _syncFlightState();
    });
    if (_items.isEmpty && mounted) {
      Navigator.of(context).pop();
    }
  }

  void _onVerticalDragStart(DragStartDetails details) {
    if (_isZoomed) return;
    _snapBackCtrl.stop();
    setState(() {
      _isDraggingDismiss = true;
      _syncFlightState();
    });
  }

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    if (!_isDraggingDismiss) return;
    setState(() {
      _dragOffset = Offset(
        _dragOffset.dx + details.delta.dx * 0.45,
        (_dragOffset.dy + details.delta.dy).clamp(-60.0, 420.0),
      );
      _syncFlightState();
    });
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    if (!_isDraggingDismiss) return;
    final velocityY = details.primaryVelocity ?? 0.0;
    if (_dragOffset.dy > 105.0 || velocityY > 520.0) {
      HapticFeedback.selectionClick();
      _syncFlightState();
      Navigator.of(context).pop();
      return;
    }
    _snapStartOffset = _dragOffset;
    setState(() => _isDraggingDismiss = false);
    _snapBackCtrl.forward(from: 0.0);
  }

  @override
  Widget build(BuildContext context) {
    if (_items.isEmpty) return const SizedBox.shrink();
    final photo = _items[_currentIndex];
    final topPad = MediaQuery.paddingOf(context).top;
    final bottomPad = MediaQuery.paddingOf(context).bottom;
    final viewerPx = _computeViewerDecodePx(context);

    final dragProgress = (_dragOffset.dy.abs() / 260.0).clamp(0.0, 1.0);
    final dragScale = lerpDouble(1.0, 0.80, dragProgress)!;
    final dragRadius = lerpDouble(0.0, 22.0, dragProgress)!;
    final bgAlpha = (1.0 - dragProgress * 0.72).clamp(0.0, 1.0);

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0C).withValues(alpha: bgAlpha),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Swipeable pinch-to-zoom & pull-down-to-dismiss photo canvas
          GestureDetector(
            onTap: () {
              setState(() => _showChrome = !_showChrome);
              if (_showChrome) {
                _chromeCtrl.forward();
              } else {
                _chromeCtrl.reverse();
              }
            },
            onVerticalDragStart: _onVerticalDragStart,
            onVerticalDragUpdate: _onVerticalDragUpdate,
            onVerticalDragEnd: _onVerticalDragEnd,
            child: PageView.builder(
              controller: _pageCtrl,
              physics: _isZoomed || _isDraggingDismiss
                  ? const NeverScrollableScrollPhysics()
                  : const BouncingScrollPhysics(),
              itemCount: _items.length,
              onPageChanged: (i) {
                HapticFeedback.selectionClick();
                _transformCtrl.value = Matrix4.identity();
                setState(() {
                  _currentIndex = i;
                  _isZoomed = false;
                  _syncFlightState();
                });
                _prewarmHiResForIndex(i);
              },
              itemBuilder: (_, i) {
                final item = _items[i];
                final exists =
                    LocalMediaService.fileExistsCached(item.filePath);
                final isActive = i == _currentIndex;
                return Center(
                  child: Transform.translate(
                    offset: isActive ? _dragOffset : Offset.zero,
                    child: Transform.scale(
                      scale: isActive ? dragScale : 1.0,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(
                          isActive ? dragRadius : 0.0,
                        ),
                        child: InteractiveViewer(
                          transformationController:
                              isActive ? _transformCtrl : null,
                          minScale: 1.0,
                          maxScale: 4.0,
                          child: exists
                              ? _ViewerPhotoImage(
                                  filePath: item.filePath,
                                  tileDecodePx: widget.tileDecodePx,
                                  viewerDecodePx: viewerPx,
                                  onAspectRatioResolved: (aspect) {
                                    widget.aspectRatios[item.id] = aspect;
                                  },
                                )
                              : const Icon(
                                  CupertinoIcons.photo,
                                  color: Colors.white38,
                                  size: 64,
                                ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          // Floating top & bottom chrome isolated in their own AnimatedBuilder
          // so PageView & InteractiveViewer never rebuild on chrome transitions.
          AnimatedBuilder(
            animation: _chromeCtrl,
            builder: (context, _) {
              final chromeT = Curves.easeOutCubic.transform(_chromeCtrl.value) *
                  (1.0 - dragProgress * 2.4).clamp(0.0, 1.0);
              final showChromeNow =
                  _showChrome && !_isDraggingDismiss && chromeT > 0.02;

              return Stack(
                fit: StackFit.expand,
                children: [
                  // Floating top bar (Back | Date & Pose | Delete)
                  Positioned(
                    top: lerpDouble(-(topPad + 88), 0, chromeT)!,
                    left: 0,
                    right: 0,
                    child: IgnorePointer(
                      ignoring: !showChromeNow,
                      child: Container(
                        padding: EdgeInsets.fromLTRB(14, topPad + 10, 14, 18),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black.withValues(alpha: 0.72 * chromeT),
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

                  // Floating frosted bottom metadata pill (zero Opacity around BackdropFilter)
                  Positioned(
                    bottom: lerpDouble(-170, bottomPad + 18, chromeT)!,
                    left: 18,
                    right: 18,
                    child: IgnorePointer(
                      ignoring: !showChromeNow,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(22),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(
                            sigmaX: (22 * chromeT).clamp(0.0, 22.0),
                            sigmaY: (22 * chromeT).clamp(0.0, 22.0),
                          ),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 14,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1C1C20)
                                  .withValues(alpha: 0.78 * chromeT),
                              borderRadius: BorderRadius.circular(22),
                              border: Border.all(
                                color: Colors.white
                                    .withValues(alpha: 0.12 * chromeT),
                              ),
                            ),
                            child: Opacity(
                              opacity: chromeT,
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
                                          color: Colors.white
                                              .withValues(alpha: 0.12),
                                          borderRadius:
                                              BorderRadius.circular(999),
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
                                            fontFeatures: [
                                              FontFeature.tabularFigures(),
                                            ],
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
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Displays a capped high-res progress photo inside the viewer while falling
/// back immediately to the already-cached grid thumbnail until the hi-res frame
/// finishes decoding (zero black flash), and reports its natural aspect ratio.
class _ViewerPhotoImage extends StatefulWidget {
  final String filePath;
  final int tileDecodePx;
  final int viewerDecodePx;
  final ValueChanged<double> onAspectRatioResolved;

  const _ViewerPhotoImage({
    required this.filePath,
    required this.tileDecodePx,
    required this.viewerDecodePx,
    required this.onAspectRatioResolved,
  });

  @override
  State<_ViewerPhotoImage> createState() => _ViewerPhotoImageState();
}

class _ViewerPhotoImageState extends State<_ViewerPhotoImage> {
  late ImageProvider _tileProvider;
  late ImageProvider _hiResProvider;
  ImageStream? _stream;
  ImageStreamListener? _listener;

  @override
  void initState() {
    super.initState();
    _initProviders();
  }

  void _initProviders() {
    final file = File(widget.filePath);
    _tileProvider = ResizeImage(FileImage(file), width: widget.tileDecodePx);
    _hiResProvider = ResizeImage(FileImage(file), width: widget.viewerDecodePx);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _listenForAspectRatio();
  }

  @override
  void didUpdateWidget(covariant _ViewerPhotoImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filePath != widget.filePath ||
        oldWidget.tileDecodePx != widget.tileDecodePx ||
        oldWidget.viewerDecodePx != widget.viewerDecodePx) {
      _detachListener();
      _initProviders();
      _listenForAspectRatio();
    }
  }

  void _listenForAspectRatio() {
    final newStream =
        _hiResProvider.resolve(createLocalImageConfiguration(context));
    if (newStream.key == _stream?.key) return;
    _detachListener();
    _stream = newStream;
    _listener = ImageStreamListener(
      (ImageInfo info, bool _) {
        final w = info.image.width.toDouble();
        final h = info.image.height.toDouble();
        if (w > 0 && h > 0) {
          widget.onAspectRatioResolved(w / h);
        }
      },
      onError: (_, __) {},
    );
    _stream!.addListener(_listener!);
  }

  void _detachListener() {
    if (_stream != null && _listener != null) {
      _stream!.removeListener(_listener!);
    }
    _stream = null;
    _listener = null;
  }

  @override
  void dispose() {
    _detachListener();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Image(
      image: _hiResProvider,
      fit: BoxFit.contain,
      gaplessPlayback: true,
      filterQuality: FilterQuality.medium,
      width: double.infinity,
      height: double.infinity,
      frameBuilder: (ctx, child, frame, wasSynchronouslyLoaded) {
        if (wasSynchronouslyLoaded || frame != null) {
          return child;
        }
        return Image(
          image: _tileProvider,
          fit: BoxFit.contain,
          gaplessPlayback: true,
          filterQuality: FilterQuality.medium,
          width: double.infinity,
          height: double.infinity,
        );
      },
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
