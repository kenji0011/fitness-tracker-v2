import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';

/// Smooth 120Hz hold-and-drag 2-column reorderable grid for Summary health cards.
///
/// - Normal taps and vertical page scrolling pass through cleanly.
/// - Long-pressing any card lifts it with haptic feedback, subtle elevation,
///   and a soft Tempo Orange glow; dragging glides neighboring cards smoothly
///   into their new slots via [AnimatedPositioned].
class ReorderableSummaryGrid extends StatefulWidget {
  final List<String> itemIds;
  final Widget Function(BuildContext context, String id, bool isDragging)
      itemBuilder;
  final ValueChanged<List<String>> onReorder;
  final double spacing;
  final double childAspectRatio;

  const ReorderableSummaryGrid({
    super.key,
    required this.itemIds,
    required this.itemBuilder,
    required this.onReorder,
    this.spacing = 10,
    this.childAspectRatio = 0.94,
  });

  @override
  State<ReorderableSummaryGrid> createState() => _ReorderableSummaryGridState();
}

class _ReorderableSummaryGridState extends State<ReorderableSummaryGrid> {
  late List<String> _order;
  String? _draggingId;
  Offset _dragOriginSlot = Offset.zero;
  Offset _dragDelta = Offset.zero;
  bool _reorderedDuringDrag = false;

  @override
  void initState() {
    super.initState();
    _order = List<String>.from(widget.itemIds);
  }

  @override
  void didUpdateWidget(covariant ReorderableSummaryGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_draggingId == null && !_listEquals(_order, widget.itemIds)) {
      _order = List<String>.from(widget.itemIds);
    }
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
    setState(() {
      _draggingId = _order[idx];
      _dragOriginSlot = _slotOffset(idx, tileW, tileH);
      _dragDelta = Offset.zero;
      _reorderedDuringDrag = false;
    });
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
    if (_order.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth;
        final tileW = (maxW - widget.spacing) / 2;
        final tileH = tileW / widget.childAspectRatio;
        final rows = (_order.length + 1) ~/ 2;
        final totalH = rows * tileH + (rows - 1) * widget.spacing;

        // Render non-dragged tiles first, and the lifted dragged tile on top.
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
          onLongPressMoveUpdate: (d) => _handleLongPressMove(d, tileW, tileH),
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
                          borderRadius: BorderRadius.circular(22),
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
  }

  Widget _buildPositionedTile({
    required BuildContext context,
    required AppColors c,
    required String id,
    required double tileW,
    required double tileH,
  }) {
    final isDragging = id == _draggingId;
    final idx = _order.indexOf(id);
    final slot = _slotOffset(idx, tileW, tileH);
    final left = isDragging ? _dragOriginSlot.dx + _dragDelta.dx : slot.dx;
    final top = isDragging ? _dragOriginSlot.dy + _dragDelta.dy : slot.dy;

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
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 170),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
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
        ),
      ),
    );
  }
}
