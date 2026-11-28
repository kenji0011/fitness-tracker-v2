import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/appearance_service.dart';
import '../theme/app_colors.dart';
import 'bitchord_glass_lens.dart';
import 'bitchord_pill_motion.dart';
import 'liquid_glass_surface.dart';

/// Reusable BitChord-calibrated Liquid Glass segmented tab slider powered by
/// [BitChordPillMotion] (120Hz coupled lift/travel/squash springs) and
/// [BitChordGlassLensBox] (`shaders/liquid_glass_lens.frag` 7-band chromatic
/// dispersion circular-dome refraction).
///
/// Used consistently across:
/// - `Latest | Week | M | Y` timeframe tabs (Calories, Steps, Activity, Waist,
///   7-Day Burn, Sleep, Weight, Water)
/// - `Exercise PRs | Sessions` and `7D | 14D | 30D` on Progress
/// - `System | Light | Dark` Theme selector on Appearance
/// - `Day | Month` mode switcher on Progress Share Studio
///
/// Features:
/// - **Tap OR slide/scrub smoothly** with a responsive `6 dp` horizontal engage
///   threshold and `110 ms` hold-lift (never fights vertical page scrolling).
/// - **Zero GPU cost at rest:** `BackdropFilterLayer` detaches completely when
///   settled (`_motion.isFlat == true`).
/// - **Full Appearance settings integration:** Honors `Liquid Glass`,
///   `Better Performance for Glass`, `Reduce animation`, and `Reduce Dynamic Blur`.
class BitChordSegmentedSlider extends StatefulWidget {
  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onChanged;
  final double height;
  final double borderRadius;
  final double fontSize;
  final Color? trackColor;
  final Color? thumbColor;
  final bool showTrackBorder;
  final bool liveUpdateWhileSliding;
  final VoidCallback? onInteract;

  const BitChordSegmentedSlider({
    super.key,
    required this.labels,
    required this.selectedIndex,
    required this.onChanged,
    this.height = 42.0,
    this.borderRadius = 999.0,
    this.fontSize = 13.5,
    this.trackColor,
    this.thumbColor,
    this.showTrackBorder = false,
    this.liveUpdateWhileSliding = true,
    this.onInteract,
  });

  @override
  State<BitChordSegmentedSlider> createState() =>
      _BitChordSegmentedSliderState();
}

class _BitChordSegmentedSliderState extends State<BitChordSegmentedSlider>
    with TickerProviderStateMixin {
  ui.FragmentProgram? _program;
  late final BitChordPillMotion _motion;
  late final ValueNotifier<int> _visualIndex;

  Timer? _holdLiftTimer;
  int? _activePointerId;
  Offset _pointerDownLocal = Offset.zero;
  bool _isScrubbing = false;
  bool _scrollRejected = false;
  bool _isHovering = false;
  double _currentTrackWidth = 0.0;
  int _lastHapticIndex = 0;

  int get _clampedSelected =>
      widget.labels.isEmpty
          ? 0
          : widget.selectedIndex.clamp(0, widget.labels.length - 1);

  @override
  void initState() {
    super.initState();
    final initial = _clampedSelected;
    _lastHapticIndex = initial;
    _visualIndex = ValueNotifier<int>(initial);
    _motion = BitChordPillMotion(
      vsync: this,
      initialIndex: initial,
    )..reduceMotion = TempoAppearanceService.instance.reduceAnimation;
    _loadShader();
    TempoAppearanceService.instance.notifier.addListener(_syncAppearance);
  }

  void _syncAppearance() {
    if (!mounted) return;
    _motion.reduceMotion = TempoAppearanceService.instance.reduceAnimation ||
        MediaQuery.disableAnimationsOf(context);
  }

  Future<void> _loadShader() async {
    final existing = TempoLiquidShaderCache.program;
    if (existing != null) {
      _program = existing;
      return;
    }
    final loaded = await TempoLiquidShaderCache.load();
    if (loaded != null && mounted) {
      setState(() => _program = loaded);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _motion.reduceMotion = TempoAppearanceService.instance.reduceAnimation ||
        MediaQuery.disableAnimationsOf(context);
  }

  @override
  void didUpdateWidget(covariant BitChordSegmentedSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextIdx = _clampedSelected;
    if (!_isScrubbing && !_isHovering && nextIdx != _motion.index) {
      _lastHapticIndex = nextIdx;
      _visualIndex.value = nextIdx;
      _motion.animateTo(nextIdx);
    }
  }

  @override
  void dispose() {
    TempoAppearanceService.instance.notifier.removeListener(_syncAppearance);
    _holdLiftTimer?.cancel();
    _motion.dispose();
    _visualIndex.dispose();
    super.dispose();
  }

  double _dxToUnclampedPos(double localDx, double trackWidth) {
    if (trackWidth <= 0 || widget.labels.isEmpty) return 0.0;
    final segW = trackWidth / widget.labels.length;
    return (localDx - segW * 0.5) / segW;
  }

  int _posToIndex(double pos) =>
      widget.labels.isEmpty
          ? 0
          : pos.round().clamp(0, widget.labels.length - 1);

  void _enterScrubMode(double localDx, double trackWidth) {
    if (_isScrubbing || _scrollRejected || widget.labels.isEmpty) return;
    _holdLiftTimer?.cancel();
    _isScrubbing = true;
    final rawPos = _dxToUnclampedPos(localDx, trackWidth);
    final nearest = _posToIndex(rawPos);
    _lastHapticIndex = nearest;
    _visualIndex.value = nearest;
    _motion.startDrag();
    _motion.dragTo(rawPos, itemCount: widget.labels.length);
    HapticFeedback.lightImpact();
    widget.onInteract?.call();
    if (widget.liveUpdateWhileSliding && nearest != widget.selectedIndex) {
      widget.onChanged(nearest);
    }
  }

  void _handlePointerDown(PointerDownEvent event, double trackWidth) {
    if (_activePointerId != null || widget.labels.isEmpty) return;
    if (event.kind == PointerDeviceKind.mouse &&
        event.buttons != kPrimaryButton) {
      return;
    }
    _activePointerId = event.pointer;
    _pointerDownLocal = event.localPosition;
    _isScrubbing = false;
    _scrollRejected = false;
    _holdLiftTimer?.cancel();

    _holdLiftTimer = Timer(const Duration(milliseconds: 110), () {
      if (!mounted ||
          _activePointerId != event.pointer ||
          _isScrubbing ||
          _scrollRejected) {
        return;
      }
      _enterScrubMode(_pointerDownLocal.dx, _currentTrackWidth);
    });
  }

  void _handlePointerMove(PointerMoveEvent event, double trackWidth) {
    if (event.pointer != _activePointerId) return;
    final dx = (event.localPosition.dx - _pointerDownLocal.dx).abs();
    final dy = (event.localPosition.dy - _pointerDownLocal.dy).abs();

    if (!_isScrubbing) {
      if (_scrollRejected) return;
      if (dx >= 6.0 && dx >= dy * 0.85) {
        _enterScrubMode(event.localPosition.dx, trackWidth);
      } else if (dy > 14.0 && dy > dx) {
        _scrollRejected = true;
        _holdLiftTimer?.cancel();
      }
      return;
    }

    final rawPos = _dxToUnclampedPos(event.localPosition.dx, trackWidth);
    _motion.dragTo(rawPos, itemCount: widget.labels.length);

    final nearest = _posToIndex(rawPos);
    if (nearest != _lastHapticIndex) {
      _lastHapticIndex = nearest;
      _visualIndex.value = nearest;
      HapticFeedback.selectionClick();
      if (widget.liveUpdateWhileSliding && nearest != widget.selectedIndex) {
        widget.onChanged(nearest);
      }
    }
  }

  void _handlePointerUp(PointerUpEvent event, double trackWidth) {
    if (event.pointer != _activePointerId) return;
    _holdLiftTimer?.cancel();
    _activePointerId = null;

    if (_isScrubbing) {
      _isScrubbing = false;
      final targetIdx =
          _posToIndex(_dxToUnclampedPos(event.localPosition.dx, trackWidth));
      _visualIndex.value = targetIdx;
      _motion.release(targetIdx);
      if (targetIdx != widget.selectedIndex) {
        widget.onChanged(targetIdx);
      }
      return;
    }

    if (_scrollRejected) {
      _scrollRejected = false;
      return;
    }

    // Crisp tap: lift crystal lens & glide smoothly to tapped tab!
    final targetIdx =
        _posToIndex(_dxToUnclampedPos(event.localPosition.dx, trackWidth));
    _visualIndex.value = targetIdx;
    widget.onInteract?.call();
    if (targetIdx != _motion.index || targetIdx != widget.selectedIndex) {
      HapticFeedback.selectionClick();
      _motion.animateTo(targetIdx);
      widget.onChanged(targetIdx);
    }
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    if (event.pointer != _activePointerId) return;
    _holdLiftTimer?.cancel();
    _activePointerId = null;
    _scrollRejected = false;
    if (_isScrubbing) {
      _isScrubbing = false;
      final active = _clampedSelected;
      _visualIndex.value = active;
      _motion.release(active);
    }
  }

  bool _isPointerHoverDevice(PointerEvent event) =>
      event.kind != PointerDeviceKind.touch;

  void _handleHoverEnter(PointerEnterEvent event, double trackWidth) {
    if (!_isPointerHoverDevice(event) || _isScrubbing) return;
    _isHovering = true;
    final rawPos = _dxToUnclampedPos(event.localPosition.dx, trackWidth);
    _motion.startDrag();
    _motion.dragTo(rawPos, itemCount: widget.labels.length);
    _visualIndex.value = _posToIndex(rawPos);
  }

  void _handleHoverMove(PointerHoverEvent event, double trackWidth) {
    if (!_isPointerHoverDevice(event) || _isScrubbing) return;
    _isHovering = true;
    final rawPos = _dxToUnclampedPos(event.localPosition.dx, trackWidth);
    _motion.dragTo(rawPos, itemCount: widget.labels.length);
    _visualIndex.value = _posToIndex(rawPos);
  }

  void _handleHoverExit(PointerExitEvent event) {
    if (!_isHovering) return;
    _isHovering = false;
    if (!_isScrubbing) {
      final active = _clampedSelected;
      _visualIndex.value = active;
      _motion.release(active);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.labels.isEmpty) return const SizedBox.shrink();

    final c = AppColors.of(context);
    final isDark = c.isDark;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final count = widget.labels.length;
    final trackH = widget.height;
    final pad = trackH <= 34 ? 3.0 : 3.5;
    final growH = trackH <= 34 ? 6.5 : 8.5;
    final resolvedTrackColor = widget.trackColor ??
        (isDark
            ? const Color(0xFF1C1C1E)
            : Colors.black.withValues(alpha: 0.055));
    final resolvedThumbColor = widget.thumbColor ??
        (isDark ? const Color(0xFF2E3038) : Colors.white);

    return ValueListenableBuilder<TempoAppearanceSettings>(
      valueListenable: TempoAppearanceService.instance.notifier,
      builder: (context, appearance, _) {
        _motion.reduceMotion = appearance.reduceAnimation ||
            MediaQuery.disableAnimationsOf(context);
        final showLiftedGlass =
            appearance.useLiquidGlass && !appearance.reduceAnimation;

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {},
          onHorizontalDragStart: (_) {},
          onHorizontalDragUpdate: (_) {},
          onHorizontalDragEnd: (_) {},
          child: SizedBox(
            height: trackH,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final trackWidth = constraints.maxWidth;
                _currentTrackWidth = trackWidth;
                final segWidth = trackWidth / count;
                _motion.stepDp = segWidth;

                final restSize = Size(
                  (segWidth - pad * 2.0).clamp(24.0, 260.0),
                  (trackH - pad * 2.0).clamp(20.0, 64.0),
                );
                final liftedSize = Size(
                  (segWidth + 8.0).clamp(restSize.width + 6.0, 280.0),
                  trackH + growH,
                );
                final refractHeightBase = (trackH * 0.25).clamp(7.5, 11.5);
                final refractAmountBase = (trackH * 0.31).clamp(10.0, 14.0);

                return MouseRegion(
                  onEnter: (e) => _handleHoverEnter(e, trackWidth),
                  onHover: (e) => _handleHoverMove(e, trackWidth),
                  onExit: _handleHoverExit,
                  child: Listener(
                    behavior: HitTestBehavior.opaque,
                    onPointerDown: (e) => _handlePointerDown(e, trackWidth),
                    onPointerMove: (e) => _handlePointerMove(e, trackWidth),
                    onPointerUp: (e) => _handlePointerUp(e, trackWidth),
                    onPointerCancel: _handlePointerCancel,
                    child: Stack(
                      clipBehavior: Clip.none,
                      alignment: Alignment.center,
                      children: [
                        // Layer 1: Clean rounded pill track (catches HyperOS
                        // proximity scatter light when nearby glass buttons are pressed)
                        Positioned.fill(
                          child: TempoTouchLightEffect(
                            borderRadius: widget.borderRadius,
                            intensity: 0.72,
                            scatterGain: 0.92,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: resolvedTrackColor,
                                borderRadius:
                                    BorderRadius.circular(widget.borderRadius),
                                border: widget.showTrackBorder
                                    ? Border.all(color: c.cardBorder)
                                    : null,
                              ),
                            ),
                          ),
                        ),

                        // Layer 2: Paint-only resting thumb (fades out cleanly
                        // as the crystal refraction lens lifts!)
                        Positioned.fill(
                          child: IgnorePointer(
                            child: CustomPaint(
                              painter: _SegmentedRestThumbPainter(
                                motion: _motion,
                                segWidth: segWidth,
                                trackHeight: trackH,
                                restSize: restSize,
                                liftedSize: liftedSize,
                                isDark: isDark,
                                thumbColor: resolvedThumbColor,
                                borderRadius: widget.borderRadius,
                                clearWhileLifted:
                                    appearance.useGlassRefraction &&
                                        showLiftedGlass,
                              ),
                            ),
                          ),
                        ),

                        // Layer 3: Segment labels (hit-testable for widget tests)
                        Positioned.fill(
                          child: ValueListenableBuilder<int>(
                            valueListenable: _visualIndex,
                            builder: (_, visIdx, __) {
                              return Row(
                                children: List.generate(count, (i) {
                                  final selected = i == visIdx;
                                  return Expanded(
                                    child: Center(
                                      child: Text(
                                        widget.labels[i],
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: selected
                                              ? c.textPrimary
                                              : c.textSecondary,
                                          fontSize: widget.fontSize,
                                          fontWeight: selected
                                              ? FontWeight.w700
                                              : FontWeight.w500,
                                          letterSpacing: -0.1,
                                        ),
                                      ),
                                    ),
                                  );
                                }),
                              );
                            },
                          ),
                        ),

                        // Layer 4 (TOP, ZERO-ALLOCATION GPU LENS):
                        // BitChord 7-band crystal refraction droplet while
                        // sliding/tapping; detached completely at rest!
                        if (showLiftedGlass)
                          Positioned.fill(
                            child: IgnorePointer(
                              child: BitChordGlassLensBox(
                                program: _program,
                                repaint: _motion,
                                isDark: isDark,
                                dpr: dpr,
                                useRefractionShader:
                                    appearance.useGlassRefraction,
                                frameBuilder: (_) {
                                  if (_motion.isFlat || segWidth <= 0) {
                                    return BitChordLensFrame.inactive;
                                  }
                                  final liveSize = _motion.liveSize(
                                    restSize,
                                    liftedSize,
                                  );
                                  final cx =
                                      (_motion.position + 0.5) * segWidth;
                                  final cy = trackH * 0.5;
                                  final localRect = Rect.fromCenter(
                                    center: Offset(cx, cy),
                                    width: liveSize.width,
                                    height: liveSize.height,
                                  );
                                  final presence = _motion.glassPresence;
                                  final material = _motion.material;
                                  final rimAlpha =
                                      (material * _motion.rimFactor)
                                          .clamp(0.0, 1.0);
                                  return BitChordLensFrame(
                                    active: true,
                                    rect: localRect,
                                    borderRadius: liveSize.height * 0.5,
                                    refractionHeightDp:
                                        refractHeightBase * presence,
                                    refractionAmountDp:
                                        refractAmountBase * material,
                                    depthEffect: 0.45,
                                    aberration: 1.0,
                                    rimAlpha: rimAlpha,
                                    shadowAlpha: rimAlpha,
                                    material: material,
                                  );
                                },
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
        );
      },
    );
  }
}

class _SegmentedRestThumbPainter extends CustomPainter {
  final BitChordPillMotion motion;
  final double segWidth;
  final double trackHeight;
  final Size restSize;
  final Size liftedSize;
  final bool isDark;
  final Color thumbColor;
  final double borderRadius;
  final bool clearWhileLifted;

  _SegmentedRestThumbPainter({
    required this.motion,
    required this.segWidth,
    required this.trackHeight,
    required this.restSize,
    required this.liftedSize,
    required this.isDark,
    required this.thumbColor,
    required this.borderRadius,
    required this.clearWhileLifted,
  }) : super(repaint: motion);

  @override
  void paint(Canvas canvas, Size size) {
    final alphaFactor =
        clearWhileLifted ? (1.0 - motion.material).clamp(0.0, 1.0) : 1.0;
    if (alphaFactor <= 0.004 || segWidth <= 0) return;

    final liveSize = motion.liveSize(restSize, liftedSize);
    final cx = (motion.position + 0.5) * segWidth;
    final cy = trackHeight * 0.5;
    final rect = Rect.fromCenter(
      center: Offset(cx, cy),
      width: liveSize.width,
      height: liveSize.height,
    );
    final radius = borderRadius >= 99.0
        ? liveSize.height * 0.5
        : (borderRadius - 3.0).clamp(6.0, liveSize.height * 0.5);
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(radius));

    if (!isDark) {
      final shadowPaint = Paint()
        ..color = Colors.black.withValues(alpha: 0.065 * alphaFactor)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0);
      canvas.drawRRect(rrect.shift(const Offset(0, 1.5)), shadowPaint);
    }

    final fillPaint = Paint()
      ..color = thumbColor.withValues(alpha: thumbColor.a * alphaFactor);
    canvas.drawRRect(rrect, fillPaint);

    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.7
      ..color = isDark
          ? Colors.white.withValues(alpha: 0.10 * alphaFactor)
          : Colors.black.withValues(alpha: 0.045 * alphaFactor);
    canvas.drawRRect(rrect, borderPaint);
  }

  @override
  bool shouldRepaint(covariant _SegmentedRestThumbPainter oldDelegate) =>
      oldDelegate.segWidth != segWidth ||
      oldDelegate.trackHeight != trackHeight ||
      oldDelegate.restSize != restSize ||
      oldDelegate.liftedSize != liftedSize ||
      oldDelegate.isDark != isDark ||
      oldDelegate.thumbColor != thumbColor ||
      oldDelegate.borderRadius != borderRadius ||
      oldDelegate.clearWhileLifted != clearWhileLifted;
}
