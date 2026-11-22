import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';

/// Full-screen circular profile photo cropper (Move, Pinch-to-Zoom, Rotate 90°).
/// Returns cropped PNG bytes (`Uint8List`) when the user taps "Choose", or `null`
/// on cancel.
class AvatarCropScreen extends StatefulWidget {
  final String imagePath;

  const AvatarCropScreen({super.key, required this.imagePath});

  @override
  State<AvatarCropScreen> createState() => _AvatarCropScreenState();
}

class _AvatarCropScreenState extends State<AvatarCropScreen> {
  final GlobalKey _cropBoundaryKey = GlobalKey();

  Offset _offset = Offset.zero;
  double _scale = 1.0;
  int _quarterTurns = 0;

  Offset _startFocalPoint = Offset.zero;
  Offset _startOffset = Offset.zero;
  double _startScale = 1.0;

  bool _interacting = false;
  bool _exporting = false;
  Size? _imageNaturalSize;

  @override
  void initState() {
    super.initState();
    _resolveNaturalSize();
  }

  void _resolveNaturalSize() {
    if (widget.imagePath.trim().isEmpty) return;
    final file = File(widget.imagePath);
    if (!file.existsSync()) return;
    final provider = FileImage(file);
    final stream = provider.resolve(ImageConfiguration.empty);
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) {
        if (mounted) {
          setState(() {
            _imageNaturalSize = Size(
              info.image.width.toDouble(),
              info.image.height.toDouble(),
            );
          });
        }
        stream.removeListener(listener);
      },
      onError: (_, __) {
        stream.removeListener(listener);
      },
    );
    stream.addListener(listener);
  }

  Size _displaySizeFor(double cropSize) {
    final nat = _imageNaturalSize;
    if (nat == null || nat.width <= 0 || nat.height <= 0) {
      return Size(cropSize, cropSize);
    }
    final isSwapped = _quarterTurns.isOdd;
    final w = isSwapped ? nat.height : nat.width;
    final h = isSwapped ? nat.width : nat.height;
    final aspect = w / h;
    if (aspect >= 1.0) {
      // Landscape: fit height to cropSize so width overflows smoothly
      return Size(cropSize * aspect, cropSize);
    } else {
      // Portrait: fit width to cropSize so height overflows smoothly
      return Size(cropSize, cropSize / aspect);
    }
  }

  Offset _clampOffset(Offset raw, double scale, double cropSize) {
    final base = _displaySizeFor(cropSize);
    final scaledW = base.width * scale;
    final scaledH = base.height * scale;
    final maxDx = math.max(0.0, (scaledW - cropSize) / 2);
    final maxDy = math.max(0.0, (scaledH - cropSize) / 2);
    return Offset(
      raw.dx.clamp(-maxDx, maxDx),
      raw.dy.clamp(-maxDy, maxDy),
    );
  }

  void _onScaleStart(ScaleStartDetails details) {
    setState(() {
      _interacting = true;
      _startFocalPoint = details.focalPoint;
      _startOffset = _offset;
      _startScale = _scale;
    });
  }

  void _onScaleUpdate(ScaleUpdateDetails details, double cropSize) {
    final nextScale = (_startScale * details.scale).clamp(1.0, 4.0);
    final focalDelta = details.focalPoint - _startFocalPoint;
    final scaleRatio = nextScale / _startScale;
    final nextOffset = _clampOffset(
      _startOffset * scaleRatio + focalDelta,
      nextScale,
      cropSize,
    );
    setState(() {
      _scale = nextScale;
      _offset = nextOffset;
    });
  }

  void _onScaleEnd(ScaleEndDetails details, double cropSize) {
    setState(() {
      _interacting = false;
      _offset = _clampOffset(_offset, _scale, cropSize);
    });
  }

  void _rotate90(double cropSize) {
    HapticFeedback.selectionClick();
    setState(() {
      _quarterTurns = (_quarterTurns + 1) % 4;
      _offset = _clampOffset(_offset, _scale, cropSize);
    });
  }

  void _resetCrop() {
    HapticFeedback.selectionClick();
    setState(() {
      _scale = 1.0;
      _offset = Offset.zero;
      _quarterTurns = 0;
    });
  }

  Future<void> _confirmCrop() async {
    if (_exporting) return;
    HapticFeedback.mediumImpact();
    setState(() => _exporting = true);
    try {
      // Wait a frame so any interaction grid is hidden before capture
      await Future<void>.delayed(const Duration(milliseconds: 24));
      final boundary = _cropBoundaryKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) {
        if (mounted) Navigator.of(context).pop<Uint8List?>(null);
        return;
      }
      final targetPx = 640.0;
      final pixelRatio = (targetPx / boundary.size.width).clamp(1.5, 3.0);
      final image = await boundary.toImage(pixelRatio: pixelRatio);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (!mounted) return;
      Navigator.of(context).pop<Uint8List?>(byteData?.buffer.asUint8List());
    } catch (_) {
      if (mounted) {
        setState(() => _exporting = false);
      }
    }
  }

  Widget _buildTransformedImage(double cropSize) {
    final base = _displaySizeFor(cropSize);
    final file = File(widget.imagePath);
    final imageWidget = widget.imagePath.isNotEmpty && file.existsSync()
        ? Image.file(
            file,
            fit: BoxFit.cover,
            filterQuality: FilterQuality.high,
            gaplessPlayback: true,
          )
        : Container(
            color: const Color(0xFF1F2128),
            child: const Center(
              child: Icon(
                CupertinoIcons.person_fill,
                color: Colors.white38,
                size: 72,
              ),
            ),
          );

    return Transform.translate(
      offset: _offset,
      child: Transform.scale(
        scale: _scale,
        child: SizedBox(
          width: base.width,
          height: base.height,
          child: RotatedBox(
            quarterTurns: _quarterTurns,
            child: imageWidget,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final size = MediaQuery.sizeOf(context);
    final cropSize = math.min(size.width - 40, size.height * 0.56).clamp(220.0, 360.0);

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
              child: Row(
                children: [
                  const SizedBox(width: 40),
                  const Expanded(
                    child: Text(
                      'Move and Scale',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _rotate90(cropSize),
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        CupertinoIcons.rotate_right,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Interactive crop stage
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onDoubleTap: _resetCrop,
                onScaleStart: _onScaleStart,
                onScaleUpdate: (d) => _onScaleUpdate(d, cropSize),
                onScaleEnd: (d) => _onScaleEnd(d, cropSize),
                child: ClipRect(
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Dimmed full-canvas image preview outside the crop circle
                      Opacity(
                        opacity: 0.36,
                        child: OverflowBox(
                          maxWidth: double.infinity,
                          maxHeight: double.infinity,
                          child: _buildTransformedImage(cropSize),
                        ),
                      ),

                      // Crisp circular viewport + exact square RepaintBoundary captured on save
                      ClipOval(
                        child: RepaintBoundary(
                          key: _cropBoundaryKey,
                          child: Container(
                            width: cropSize,
                            height: cropSize,
                            color: Colors.black,
                            alignment: Alignment.center,
                            child: OverflowBox(
                              maxWidth: double.infinity,
                              maxHeight: double.infinity,
                              child: _buildTransformedImage(cropSize),
                            ),
                          ),
                        ),
                      ),

                      // Circular guide ring + rule-of-thirds overlay while dragging/zooming
                      IgnorePointer(
                        child: SizedBox(
                          width: cropSize,
                          height: cropSize,
                          child: CustomPaint(
                            painter: _CircularCropGuidePainter(
                              showGrid: _interacting,
                              accentColor: c.accent,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Hint + Bottom Action Bar
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
              child: Column(
                children: [
                  Text(
                    'Pinch to zoom · Drag to position · Double-tap to reset',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.56),
                      fontSize: 12.5,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 48,
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white,
                              side: BorderSide(
                                color: Colors.white.withValues(alpha: 0.24),
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(999),
                              ),
                            ),
                            onPressed: _exporting
                                ? null
                                : () => Navigator.of(context).pop<Uint8List?>(null),
                            child: const Text(
                              'Cancel',
                              style: TextStyle(fontWeight: FontWeight.w600),
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
                              backgroundColor: c.accent,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(999),
                              ),
                            ),
                            onPressed: _exporting ? null : _confirmCrop,
                            child: _exporting
                                ? const CupertinoActivityIndicator(
                                    color: Colors.white,
                                  )
                                : const Text(
                                    'Choose',
                                    style: TextStyle(fontWeight: FontWeight.w700),
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
      ),
    );
  }
}

class _CircularCropGuidePainter extends CustomPainter {
  final bool showGrid;
  final Color accentColor;

  const _CircularCropGuidePainter({
    required this.showGrid,
    required this.accentColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    if (showGrid) {
      canvas.save();
      canvas.clipPath(
        Path()..addOval(Rect.fromCircle(center: center, radius: radius)),
      );
      final gridPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.28)
        ..strokeWidth = 0.8;
      final thirdW = size.width / 3;
      final thirdH = size.height / 3;
      for (int i = 1; i <= 2; i++) {
        canvas.drawLine(
          Offset(thirdW * i, 0),
          Offset(thirdW * i, size.height),
          gridPaint,
        );
        canvas.drawLine(
          Offset(0, thirdH * i),
          Offset(size.width, thirdH * i),
          gridPaint,
        );
      }
      canvas.restore();
    }

    final ringPaint = Paint()
      ..color = showGrid
          ? accentColor.withValues(alpha: 0.92)
          : Colors.white.withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = showGrid ? 2.2 : 1.6;
    canvas.drawCircle(center, radius - 1, ringPaint);
  }

  @override
  bool shouldRepaint(covariant _CircularCropGuidePainter oldDelegate) =>
      oldDelegate.showGrid != showGrid || oldDelegate.accentColor != accentColor;
}
