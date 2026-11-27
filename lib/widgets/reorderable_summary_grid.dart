import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/animation_speed_service.dart';
import '../services/appearance_service.dart';
import '../theme/app_colors.dart';
import 'bitchord_glass_lens.dart';
import 'liquid_glass_surface.dart';

/// Smooth 120Hz hold-and-drag 2-column reorderable grid for Summary health cards.
///
/// - Normal taps and vertical page scrolling pass through cleanly.
/// - Long-pressing any card lifts it into a crystal-clear BitChord Liquid Glass
///   lens (`shaders/liquid_glass_lens.frag`) so underlying Summary cards visibly
///   refract with 7-band chromatic rainbow edge dispersion and a 45° specular rim
///   as you drag across the grid!
/// - Zero GPU cost at rest: non-dragged tiles remain standard opaque cards.
class ReorderableSummaryGrid extends StatefulWidget {
  final List<String> itemIds;
  final Widget Function(BuildContext context, String id, bool isDragging)
      itemBuilder;
  final ValueChanged<List<String>> onReorder;
  final double spacing;
  final double childAspectRatio;
  final double cardBorderRadius;

  const ReorderableSummaryGrid({
    super.key,
    required this.itemIds,
    required this.itemBuilder,
    required this.onReorder,
    this.spacing = 10,
    this.childAspectRatio = 0.94,
    this.cardBorderRadius = 20,
  });

  @override
  State<ReorderableSummaryGrid> createState() => _ReorderableSummaryGridState();
}

class _ReorderableSummaryGridState extends State<ReorderableSummaryGrid>
    with SingleTickerProviderStateMixin {
  ui.FragmentProgram? _program;
  late final AnimationController _liftController;

  late List<String> _order;
  String? _draggingId;
  Offset _dragOriginSlot = Offset.zero;
  Offset _dragDelta = Offset.zero;
  bool _reorderedDuringDrag = false;

  @override
  void initState() {
    super.initState();
    _order = List<String>.from(widget.itemIds);
    _liftController = AnimationController(
      vsync: this,
      duration: TempoAnimationSpeedService.instance.scale(
        const Duration(milliseconds: 190),
      ),
    );
    _loadShader();
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
  void didUpdateWidget(covariant ReorderableSummaryGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_draggingId == null && !_listEquals(_order, widget.itemIds)) {
      _order = List<String>.from(widget.itemIds);
    }
  }

  @override
  void dispose() {
    _liftController.dispose();
    super.dispose();
  }

  bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  Offset _slotOffset(int index, double tileW, double tileH) {
    final col = index % 2;
    final row = index ~/ 2;
    return Offset(
      col * (tileW + widget.spacing),
      row * (tileH + widget.spacing),
    );
  }

  int? _hitTestIndex(Offset localPos, double tileW, double tileH) {
    for (int i = 0; i < _order.length; i++) {
      final origin = _slotOffset(i, tileW, tileH);
      final rect = Rect.fromLTWH(origin.dx, origin.dy, tileW, tileH);
      if (rect.contains(localPos)) return i;
    }
    return null;
  }

  void _handleLongPressStart(
    LongPressStartDetails details,
    double tileW,
    double tileH,
  ) {
    if (_order.length < 2) return;
    final idx = _hitTestIndex(details.localPosition, tileW, tileH);
    if (idx == null) return;
    HapticFeedback.mediumImpact();
    final reduced = TempoAppearanceService.instance.reduceAnimation;
    _liftController.duration = TempoAnimationSpeedService.instance.scale(
      const Duration(milliseconds: 190),
    );
    setState(() {
      _draggingId = _order[idx];
      _dragOriginSlot = _slotOffset(idx, tileW, tileH);
      _dragDelta = Offset.zero;
      _reorderedDuringDrag = false;
    });
    if (reduced) {
      _liftController.value = 1.0;
    } else {
      _liftController.forward(from: 0.0);
    }
  }

  void _handleLongPressMove(
    LongPressMoveUpdateDetails details,
    double tileW,
    double tileH,
  ) {
    if (_draggingId == null) return;
    final nextDelta = details.offsetFromOrigin;
    final currentPos = _dragOriginSlot + nextDelta;
    final centerX = currentPos.dx + tileW / 2;
    final centerY = currentPos.dy + tileH / 2;

    final col = (centerX / (tileW + widget.spacing)).floor().clamp(0, 1);
    final totalRows = (_order.length + 1) ~/ 2;
    final row =
        (centerY / (tileH + widget.spacing)).floor().clamp(0, totalRows - 1);
    final targetIdx = (row * 2 + col).clamp(0, _order.length - 1);
    final currentIdx = _order.indexOf(_draggingId!);

    if (currentIdx >= 0 && targetIdx != currentIdx) {
      HapticFeedback.selectionClick();
      setState(() {
        final item = _order.removeAt(currentIdx);
        _order.insert(targetIdx, item);
        _dragDelta = nextDelta;
        _reorderedDuringDrag = true;
      });
    } else {
      setState(() {
        _dragDelta = nextDelta;
      });
    }
  }

  void _handleLongPressEnd() {
    if (_draggingId == null) return;
    final shouldCommit = _reorderedDuringDrag;
    final finalOrder = List<String>.from(_order);
    HapticFeedback.lightImpact();
    _liftController.value = 0.0;
    setState(() {
      _draggingId = null;
      _dragDelta = Offset.zero;
      _reorderedDuringDrag = false;
    });
    if (shouldCommit) {
      widget.onReorder(finalOrder);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    if (_order.isEmpty) return const SizedBox.shrink();

    return ValueListenableBuilder<TempoAppearanceSettings>(
      valueListenable: TempoAppearanceService.instance.notifier,
      builder: (context, appearance, _) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final maxW = constraints.maxWidth;
            final tileW = (maxW - widget.spacing) / 2;
            final tileH = tileW / widget.childAspectRatio;
            final rows = (_order.length + 1) ~/ 2;
            final totalH = rows * tileH + (rows - 1) * widget.spacing;

            // Render non-dragged tiles first, and the lifted dragged tile LAST
            // on top so its Liquid Glass lens refracts every card underneath it!
            final renderIds = <String>[
              for (final id in _order)
                if (id != _draggingId) id,
              if (_draggingId != null) _draggingId!,
            ];

            final draggingIdx =
                _draggingId != null ? _order.indexOf(_draggingId!) : -1;
            final placeholderSlot = draggingIdx >= 0
                ? _slotOffset(draggingIdx, tileW, tileH)
                : Offset.zero;

            return GestureDetector(
              behavior: HitTestBehavior.translucent,
              onLongPressStart: (d) => _handleLongPressStart(d, tileW, tileH),
              onLongPressMoveUpdate: (d) =>
                  _handleLongPressMove(d, tileW, tileH),
              onLongPressEnd: (_) => _handleLongPressEnd(),
              onLongPressCancel: _handleLongPressEnd,
              child: SizedBox(
                width: maxW,
                height: totalH,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // Subtle drop-target placeholder underneath the dragged card
                    if (_draggingId != null && draggingIdx >= 0)
                      AnimatedPositioned(
                        key: const ValueKey('summary_drag_placeholder'),
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOutCubic,
                        left: placeholderSlot.dx,
                        top: placeholderSlot.dy,
                        width: tileW,
                        height: tileH,
                        child: IgnorePointer(
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(
                                widget.cardBorderRadius,
                              ),
                              color: c.accent.withValues(
                                alpha: c.isDark ? 0.08 : 0.06,
                              ),
                              border: Border.all(
                                color: c.accent.withValues(alpha: 0.35),
                                width: 1.4,
                              ),
                            ),
                          ),
                        ),
                      ),

                    // Reorderable cards (AnimatedPositioned MUST be direct child of Stack)
                    for (final id in renderIds)
                      _buildPositionedTile(
                        context: context,
                        c: c,
                        appearance: appearance,
                        dpr: dpr,
                        id: id,
                        tileW: tileW,
                        tileH: tileH,
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildPositionedTile({
    required BuildContext context,
    required AppColors c,
    required TempoAppearanceSettings appearance,
    required double dpr,
    required String id,
    required double tileW,
    required double tileH,
  }) {
    final isDragging = id == _draggingId;
    final idx = _order.indexOf(id);
    final slot = _slotOffset(idx, tileW, tileH);
    final left = isDragging ? _dragOriginSlot.dx + _dragDelta.dx : slot.dx;
    final top = isDragging ? _dragOriginSlot.dy + _dragDelta.dy : slot.dy;
    final useGlassDrag = isDragging && appearance.useLiquidGlass;
    final radius = widget.cardBorderRadius;

    Widget tileChild;
    if (useGlassDrag) {
      final useShader = appearance.useGlassRefraction;
      tileChild = Stack(
        clipBehavior: Clip.none,
        fit: StackFit.expand,
        children: [
          // Layer 1: Live BitChord 7-band optical refraction lens (or lighter
          // frosted backdrop in Better Performance mode) refracting underlying
          // Summary cards behind the dragged card with 0-frame lag!
          if (useShader)
            Positioned.fill(
              child: IgnorePointer(
                child: BitChordGlassLensBox(
                  program: _program,
                  repaint: _liftController,
                  isDark: c.isDark,
                  dpr: dpr,
                  useRefractionShader: true,
                  frameBuilder: (sz) {
                    final t = Curves.easeOutCubic.transform(
                      _liftController.value,
                    );
                    if (t <= 0.004 || sz.isEmpty) {
                      return BitChordLensFrame.inactive;
                    }
                    return BitChordLensFrame(
                      active: true,
                      rect: Offset.zero & sz,
                      borderRadius: radius,
                      refractionHeightDp: 18.0 * t,
                      refractionAmountDp: 20.0 * t,
                      depthEffect: 0.45,
                      aberration: 1.15,
                      rimAlpha: t,
                      shadowAlpha: t,
                      material: t,
                    );
                  },
                ),
              ),
            )
          else
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(radius),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(
                          alpha: c.isDark ? 0.36 : 0.14,
                        ),
                        blurRadius: 22,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(radius),
                    child: BackdropFilter(
                      filter: ui.ImageFilter.blur(
                        sigmaX: 14.0,
                        sigmaY: 14.0,
                        tileMode: ui.TileMode.clamp,
                      ),
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
              ),
            ),

          // Layer 2: Crystal-clear optical glass veil + crisp 45° specular rim
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _liftController,
                builder: (_, __) {
                  final t = Curves.easeOutCubic.transform(
                    _liftController.value,
                  );
                  return CustomPaint(
                    foregroundPainter: LiquidGlassRimPainter(
                      borderRadius: radius,
                      isDark: c.isDark,
                      intensity: 0.96 * t,
                      strokeWidth: 1.25,
                      showTopMeniscus: true,
                    ),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(radius),
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: c.isDark
                              ? [
                                  const Color(0xFF282A32)
                                      .withValues(alpha: 0.28 * t),
                                  const Color(0xFF14151A)
                                      .withValues(alpha: 0.18 * t),
                                ]
                              : [
                                  Colors.white.withValues(alpha: 0.24 * t),
                                  const Color(0xFFF6F7FB)
                                      .withValues(alpha: 0.12 * t),
                                ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),

          // Layer 3: Crisp transparent-background Summary card content on top
          IgnorePointer(
            ignoring: true,
            child: widget.itemBuilder(context, id, true),
          ),
        ],
      );
    } else {
      tileChild = AnimatedContainer(
        duration: const Duration(milliseconds: 170),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          boxShadow: isDragging
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(
                      alpha: c.isDark ? 0.42 : 0.16,
                    ),
                    blurRadius: 24,
                    offset: const Offset(0, 12),
                  ),
                  BoxShadow(
                    color: c.accent.withValues(alpha: 0.18),
                    blurRadius: 14,
                    spreadRadius: 1,
                  ),
                ]
              : const [],
        ),
        child: IgnorePointer(
          ignoring: _draggingId != null,
          child: widget.itemBuilder(context, id, isDragging),
        ),
      );
    }

    return AnimatedPositioned(
      key: ValueKey('summary_pos_$id'),
      duration: isDragging ? Duration.zero : const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      left: left,
      top: top,
      width: tileW,
      height: tileH,
      child: AnimatedScale(
        scale: isDragging ? 1.045 : 1.0,
        duration: const Duration(milliseconds: 170),
        curve: Curves.easeOutCubic,
        child: tileChild,
      ),
    );
  }
}
