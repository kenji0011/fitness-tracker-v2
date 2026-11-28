import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/animation_speed_service.dart';
import '../services/appearance_service.dart';
import '../theme/app_colors.dart';
import 'bitchord_glass_lens.dart';
import 'liquid_glass_surface.dart';

/// HyperOS 3 / iOS 27-inspired 120Hz **3D cylindrical drum-wheel column** with:
/// - True sculpted barrel geometry (`diameterRatio: 1.48`, `perspective: 0.0042`,
///   `squeeze: 1.12`, optional inward `offAxisFraction` on paired columns).
/// - Zero-rebuild continuous sub-pixel scroll interpolation (`ValueNotifier<double>`)
///   driving smoothstep scale (`0.75× → 1.08×`), 3D drum pitch tilt, tonal
///   contrast falloff, and progressive font weight right under the center lens.
/// - Tap-to-center on any visible neighbor row & smooth animated spin when
///   updated externally by quick-adjust preset chips.
/// - Crisp detent haptics on every tick.
class TempoWheelColumn extends StatefulWidget {
  final List<String> items;
  final int initialIndex;
  final ValueChanged<int> onSelectedIndexChanged;
  final bool looping;
  final String? headerLabel;
  final double width;
  final double height;
  final double itemExtent;
  final double fontSize;
  final double offAxisFraction;
  final bool animateOnExternalChange;

  const TempoWheelColumn({
    super.key,
    required this.items,
    required this.initialIndex,
    required this.onSelectedIndexChanged,
    this.looping = false,
    this.headerLabel,
    this.width = 94,
    this.height = 198,
    this.itemExtent = 44,
    this.fontSize = 35,
    this.offAxisFraction = 0.0,
    this.animateOnExternalChange = true,
  });

  @override
  State<TempoWheelColumn> createState() => _TempoWheelColumnState();
}

class _TempoWheelColumnState extends State<TempoWheelColumn> {
  late FixedExtentScrollController _ctrl;
  late int _selectedIndex;
  late final ValueNotifier<double> _scrollPos;
  bool _programmaticScroll = false;

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.items.isEmpty
        ? 0
        : widget.initialIndex.clamp(0, widget.items.length - 1);
    _scrollPos = ValueNotifier<double>(_selectedIndex.toDouble());
    _ctrl = FixedExtentScrollController(initialItem: _selectedIndex)
      ..addListener(_handleScroll);
  }

  void _handleScroll() {
    if (!_ctrl.hasClients || widget.itemExtent <= 0) return;
    final nextPos = _ctrl.offset / widget.itemExtent;
    if ((nextPos - _scrollPos.value).abs() > 0.001) {
      _scrollPos.value = nextPos;
    }
  }

  int _shortestLoopTargetRaw(int targetIdx) {
    final n = widget.items.length;
    if (!widget.looping || n <= 1 || !_ctrl.hasClients) return targetIdx;
    final curRaw = _ctrl.selectedItem;
    final curNorm = ((curRaw % n) + n) % n;
    int delta = targetIdx - curNorm;
    if (delta > n ~/ 2) delta -= n;
    if (delta < -(n ~/ 2)) delta += n;
    return curRaw + delta;
  }

  void _spinToNormalized(int targetIdx, {required bool animate}) {
    if (widget.items.isEmpty) return;
    final clamped = targetIdx.clamp(0, widget.items.length - 1);
    final rawTarget = _shortestLoopTargetRaw(clamped);
    if (!_ctrl.hasClients) {
      _selectedIndex = clamped;
      _scrollPos.value = clamped.toDouble();
      return;
    }
    final reduced = TempoAppearanceService.instance.reduceAnimation;
    if (!animate || reduced) {
      _ctrl.jumpToItem(rawTarget);
      _scrollPos.value = rawTarget.toDouble();
      return;
    }
    _programmaticScroll = true;
    _ctrl
        .animateToItem(
          rawTarget,
          duration: TempoAnimationSpeedService.instance.scale(
            const Duration(milliseconds: 300),
          ),
          curve: Curves.easeOutCubic,
        )
        .whenComplete(() {
      _programmaticScroll = false;
    });
  }

  @override
  void didUpdateWidget(covariant TempoWheelColumn oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.items.isEmpty) return;
    final clamped = widget.initialIndex.clamp(0, widget.items.length - 1);
    if (oldWidget.items.length != widget.items.length) {
      _selectedIndex = clamped;
      if (_ctrl.hasClients) {
        _ctrl.jumpToItem(clamped);
        _scrollPos.value = clamped.toDouble();
      } else {
        _ctrl.removeListener(_handleScroll);
        _ctrl.dispose();
        _ctrl = FixedExtentScrollController(initialItem: clamped)
          ..addListener(_handleScroll);
        _scrollPos.value = clamped.toDouble();
      }
    } else if (oldWidget.initialIndex != widget.initialIndex &&
        clamped != _selectedIndex) {
      _selectedIndex = clamped;
      _spinToNormalized(clamped, animate: widget.animateOnExternalChange);
    }
  }

  @override
  void dispose() {
    _ctrl.removeListener(_handleScroll);
    _ctrl.dispose();
    _scrollPos.dispose();
    super.dispose();
  }

  Widget _buildItem(BuildContext context, int index, AppColors c) {
    final count = widget.items.length;
    final normalized = count == 0 ? 0 : ((index % count) + count) % count;
    final label = count == 0 ? '' : widget.items[normalized];

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () {
        if (normalized == _selectedIndex) return;
        HapticFeedback.selectionClick();
        _spinToNormalized(normalized, animate: true);
      },
      child: ValueListenableBuilder<double>(
        valueListenable: _scrollPos,
        builder: (_, pos, __) {
          double delta;
          if (widget.looping && count > 1) {
            final wrappedPos = ((pos % count) + count) % count;
            delta = normalized - wrappedPos;
            if (delta > count * 0.5) delta -= count;
            if (delta < -count * 0.5) delta += count;
          } else {
            delta = normalized - pos;
          }

          final dist = delta.abs().clamp(0.0, 2.6);
          final rawFocus = (1.0 - dist / 1.38).clamp(0.0, 1.0);
          final focus = rawFocus * rawFocus * (3.0 - 2.0 * rawFocus);

          final scale = ui.lerpDouble(0.75, 1.08, focus)!;
          final depthAlpha = math
              .pow((1.0 - dist / 2.65).clamp(0.0, 1.0), 1.25)
              .toDouble()
              .clamp(0.22, 1.0);
          final textColor = Color.lerp(
            c.textSecondary.withValues(alpha: c.isDark ? 0.52 : 0.48),
            c.textPrimary,
            focus,
          )!
              .withValues(alpha: depthAlpha);

          final weight = dist < 0.45
              ? FontWeight.w700
              : (dist < 1.15 ? FontWeight.w500 : FontWeight.w400);

          // Subtle physical drum roll pitch layered on top of cylinder perspective
          final tiltRad = (delta.clamp(-2.2, 2.2) * 0.19);
          final transform = Matrix4.identity()
            ..setEntry(3, 2, 0.0016)
            ..rotateX(-tiltRad)
            ..multiply(Matrix4.diagonal3Values(scale, scale, 1.0));

          return Center(
            child: Transform(
              alignment: Alignment.center,
              transform: transform,
              child: Text(
                label,
                maxLines: 1,
                softWrap: false,
                style: TextStyle(
                  color: textColor,
                  fontSize: widget.fontSize,
                  fontWeight: weight,
                  letterSpacing: -0.9,
                  height: 1.0,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final wheel = SizedBox(
      width: widget.width,
      height: widget.height,
      child: ShaderMask(
        shaderCallback: (bounds) => const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            Color(0x5AFFFFFF),
            Colors.white,
            Colors.white,
            Color(0x5AFFFFFF),
            Colors.transparent,
          ],
          stops: [0.0, 0.14, 0.35, 0.65, 0.86, 1.0],
        ).createShader(bounds),
        blendMode: BlendMode.dstIn,
        child: ListWheelScrollView.useDelegate(
          controller: _ctrl,
          itemExtent: widget.itemExtent,
          diameterRatio: 1.48,
          perspective: 0.0042,
          squeeze: 1.12,
          offAxisFraction: widget.offAxisFraction,
          overAndUnderCenterOpacity: 0.94,
          physics: const FixedExtentScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          onSelectedItemChanged: (rawIdx) {
            if (widget.items.isEmpty) return;
            final idx = ((rawIdx % widget.items.length) + widget.items.length) %
                widget.items.length;
            if (idx == _selectedIndex) return;
            if (!_programmaticScroll) {
              HapticFeedback.selectionClick();
            }
            _selectedIndex = idx;
            widget.onSelectedIndexChanged(idx);
          },
          childDelegate: widget.looping
              ? ListWheelChildLoopingListDelegate(
                  children: List.generate(
                    widget.items.length,
                    (i) => _buildItem(context, i, c),
                  ),
                )
              : ListWheelChildBuilderDelegate(
                  childCount: widget.items.length,
                  builder: (ctx, i) => _buildItem(ctx, i, c),
                ),
        ),
      ),
    );

    if (widget.headerLabel == null) return wheel;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          widget.headerLabel!,
          style: TextStyle(
            color: c.textTertiary,
            fontSize: 11.8,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.45,
          ),
        ),
        const SizedBox(height: 6),
        wheel,
      ],
    );
  }
}

/// Framed 3D drum-wheel stage featuring:
/// - Recessed cylindrical depth cavity shading (top/bottom radial drum housing)
/// - Delicate watch-bezel graduation ticks aligned to the active selection axis
/// - Floating **BitChord Liquid Glass magnifying capsule** refracting numbers
///   as they roll through center + catching HyperOS 3 proximity scatter light
///   when neighboring preset chips or date pills are pressed.
class TempoWheelStage extends StatefulWidget {
  final List<Widget> children;
  final double height;
  final double selectionBandHeight;
  final Color? accentColor;

  const TempoWheelStage({
    super.key,
    required this.children,
    this.height = 224,
    this.selectionBandHeight = 54,
    this.accentColor,
  });

  @override
  State<TempoWheelStage> createState() => _TempoWheelStageState();
}

class _TempoWheelStageState extends State<TempoWheelStage> {
  Animation<double>? _routeAnim;
  bool _routeSettled = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final nextAnim = ModalRoute.of(context)?.animation;
    if (!identical(_routeAnim, nextAnim)) {
      _routeAnim?.removeStatusListener(_onRouteStatus);
      _routeAnim = nextAnim;
      _routeAnim?.addStatusListener(_onRouteStatus);
      _routeSettled = _routeAnim == null ||
          _routeAnim!.status == AnimationStatus.completed;
    }
  }

  void _onRouteStatus(AnimationStatus status) {
    final settled = status == AnimationStatus.completed;
    if (settled != _routeSettled && mounted) {
      setState(() => _routeSettled = settled);
    }
  }

  @override
  void dispose() {
    _routeAnim?.removeStatusListener(_onRouteStatus);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final isDark = c.isDark;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final bandTop = (widget.height - widget.selectionBandHeight) / 2 + 11;

    return ValueListenableBuilder<TempoAppearanceSettings>(
      valueListenable: TempoAppearanceService.instance.notifier,
      builder: (context, appearance, _) {
        final useGlass = appearance.useLiquidGlass;
        final useLens =
            useGlass && appearance.useGlassRefraction && _routeSettled;

        return SizedBox(
          height: widget.height,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Layer 0: Subtle 3D cylindrical drum-cavity recessed shading
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: isDark
                              ? [
                                  Colors.black.withValues(alpha: 0.24),
                                  Colors.transparent,
                                  Colors.transparent,
                                  Colors.black.withValues(alpha: 0.26),
                                ]
                              : [
                                  Colors.black.withValues(alpha: 0.045),
                                  Colors.transparent,
                                  Colors.transparent,
                                  Colors.black.withValues(alpha: 0.05),
                                ],
                          stops: const [0.0, 0.22, 0.78, 1.0],
                        ),
                      ),
                    ),
                  ),
                ),

                // Layer 1: Soft recessed backdrop pill + fine bezel ticks
                Positioned(
                  left: 4,
                  right: 4,
                  top: bandTop,
                  height: widget.selectionBandHeight,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: useGlass
                            ? (isDark
                                ? Colors.white.withValues(alpha: 0.065)
                                : Colors.black.withValues(alpha: 0.042))
                            : c.searchBg.withValues(alpha: isDark ? 0.72 : 0.75),
                        borderRadius: BorderRadius.circular(999),
                        border: !useGlass
                            ? Border.all(
                                color: isDark
                                    ? Colors.white.withValues(alpha: 0.08)
                                    : Colors.black.withValues(alpha: 0.045),
                              )
                            : null,
                      ),
                    ),
                  ),
                ),

                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: _WheelBezelTicksPainter(
                        centerY: bandTop + widget.selectionBandHeight * 0.5,
                        isDark: isDark,
                        accentColor: widget.accentColor ?? c.accent,
                      ),
                    ),
                  ),
                ),

                // Layer 2: 3D Drum-wheel columns
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: widget.children,
                ),

                // Layer 3 (TOP): Crystal-clear BitChord Liquid Glass magnifying
                // lens band catching both refraction AND proximity light scatter!
                if (useGlass)
                  Positioned(
                    left: 4,
                    right: 4,
                    top: bandTop,
                    height: widget.selectionBandHeight,
                    child: IgnorePointer(
                      child: TempoTouchLightEffect(
                        borderRadius: widget.selectionBandHeight * 0.5,
                        emitLight: false,
                        receiveScatter: true,
                        scatterGain: 1.05,
                        child: CustomPaint(
                          foregroundPainter: LiquidGlassRimPainter(
                            borderRadius: widget.selectionBandHeight * 0.5,
                            isDark: isDark,
                            intensity: isDark ? 0.96 : 0.98,
                            strokeWidth: 1.1,
                            showTopMeniscus: false,
                          ),
                          child: useLens
                              ? BitChordGlassLensBox(
                                  program: TempoLiquidShaderCache.program,
                                  isDark: isDark,
                                  dpr: dpr,
                                  useRefractionShader: true,
                                  frameBuilder: (sz) {
                                    if (sz.isEmpty) {
                                      return BitChordLensFrame.inactive;
                                    }
                                    return BitChordLensFrame(
                                      active: true,
                                      rect: Offset.zero & sz,
                                      borderRadius: sz.height * 0.5,
                                      refractionHeightDp: 11.0,
                                      refractionAmountDp: 13.5,
                                      depthEffect: 0.48,
                                      aberration: 0.85,
                                      rimAlpha: 0.58,
                                      shadowAlpha: 0.28,
                                      material: 0.96,
                                    );
                                  },
                                )
                              : const SizedBox.expand(),
                        ),
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
}

/// Delicate graduated watch-bezel tick marks along the left and right edges of
/// the 3D drum stage, visually grounding the cylindrical rotation axis.
class _WheelBezelTicksPainter extends CustomPainter {
  final double centerY;
  final bool isDark;
  final Color accentColor;

  const _WheelBezelTicksPainter({
    required this.centerY,
    required this.isDark,
    required this.accentColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    const tickOffsets = [-56.0, -38.0, -20.0, 0.0, 20.0, 38.0, 56.0];
    final baseColor = isDark ? Colors.white : const Color(0xFF1C1C1E);

    for (final dy in tickOffsets) {
      final y = centerY + dy;
      if (y < 14 || y > size.height - 14) continue;
      final isCenter = dy == 0.0;
      final falloff = (1.0 - (dy.abs() / 72.0)).clamp(0.18, 1.0);
      final tickLen = isCenter ? 10.0 : (5.5 + 2.5 * falloff);
      final paint = Paint()
        ..color = isCenter
            ? accentColor.withValues(alpha: isDark ? 0.72 : 0.62)
            : baseColor.withValues(alpha: (isDark ? 0.22 : 0.14) * falloff)
        ..strokeWidth = isCenter ? 1.8 : 1.1
        ..strokeCap = StrokeCap.round;

      // Left edge tick
      canvas.drawLine(Offset(10, y), Offset(10 + tickLen, y), paint);
      // Right edge tick
      canvas.drawLine(
        Offset(size.width - 10 - tickLen, y),
        Offset(size.width - 10, y),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WheelBezelTicksPainter oldDelegate) =>
      oldDelegate.centerY != centerY ||
      oldDelegate.isDark != isDark ||
      oldDelegate.accentColor != accentColor;
}
