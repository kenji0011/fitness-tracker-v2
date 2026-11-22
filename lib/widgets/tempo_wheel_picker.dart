import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';

/// HyperOS 3 / iOS-style vertical drum wheel picker with 5 visible rows,
/// progressive top/bottom fade, smooth inertial snapping (`FixedExtentScrollPhysics`),
/// and crisp haptic feedback on every tick.
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

  const TempoWheelColumn({
    super.key,
    required this.items,
    required this.initialIndex,
    required this.onSelectedIndexChanged,
    this.looping = false,
    this.headerLabel,
    this.width = 94,
    this.height = 204,
    this.itemExtent = 46,
    this.fontSize = 36,
  });

  @override
  State<TempoWheelColumn> createState() => _TempoWheelColumnState();
}

class _TempoWheelColumnState extends State<TempoWheelColumn> {
  late FixedExtentScrollController _ctrl;
  late int _selectedIndex;

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialIndex.clamp(0, widget.items.length - 1);
    _ctrl = FixedExtentScrollController(initialItem: _selectedIndex);
  }

  @override
  void didUpdateWidget(covariant TempoWheelColumn oldWidget) {
    super.didUpdateWidget(oldWidget);
    final clamped = widget.initialIndex.clamp(0, widget.items.length - 1);
    if (oldWidget.items.length != widget.items.length ||
        (oldWidget.initialIndex != widget.initialIndex && clamped != _selectedIndex)) {
      _selectedIndex = clamped;
      if (_ctrl.hasClients) {
        _ctrl.jumpToItem(clamped);
      } else {
        _ctrl.dispose();
        _ctrl = FixedExtentScrollController(initialItem: clamped);
      }
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Widget _buildItem(BuildContext context, int index, AppColors c) {
    final normalized = widget.items.isEmpty
        ? 0
        : ((index % widget.items.length) + widget.items.length) %
            widget.items.length;
    final isSelected = normalized == _selectedIndex;

    return Center(
      child: AnimatedDefaultTextStyle(
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOutCubic,
        style: TextStyle(
          color: isSelected
              ? c.textPrimary
              : c.textSecondary.withValues(alpha: c.isDark ? 0.52 : 0.48),
          fontSize: isSelected ? widget.fontSize : widget.fontSize * 0.72,
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
          letterSpacing: -0.8,
          height: 1.0,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
        child: Text(
          widget.items[normalized],
          maxLines: 1,
          softWrap: false,
        ),
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
            Color(0x55FFFFFF),
            Colors.white,
            Colors.white,
            Color(0x55FFFFFF),
            Colors.transparent,
          ],
          stops: [0.0, 0.16, 0.36, 0.64, 0.84, 1.0],
        ).createShader(bounds),
        blendMode: BlendMode.dstIn,
        child: ListWheelScrollView.useDelegate(
          controller: _ctrl,
          itemExtent: widget.itemExtent,
          diameterRatio: 2.4,
          perspective: 0.0022,
          squeeze: 1.04,
          physics: const FixedExtentScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          onSelectedItemChanged: (rawIdx) {
            if (widget.items.isEmpty) return;
            final idx = ((rawIdx % widget.items.length) + widget.items.length) %
                widget.items.length;
            if (idx == _selectedIndex) return;
            HapticFeedback.selectionClick();
            setState(() => _selectedIndex = idx);
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
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
        ),
        const SizedBox(height: 6),
        wheel,
      ],
    );
  }
}

/// Framed drum-wheel stage with a subtle centered selection pill behind the
/// active row and optional separator/unit inline labels.
class TempoWheelStage extends StatelessWidget {
  final List<Widget> children;
  final double height;
  final double selectionBandHeight;

  const TempoWheelStage({
    super.key,
    required this.children,
    this.height = 232,
    this.selectionBandHeight = 52,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return SizedBox(
      height: height,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Subtle centered selection highlight band aligned with the middle wheel row
          Positioned(
            left: 4,
            right: 4,
            top: (height - selectionBandHeight) / 2 + 12,
            height: selectionBandHeight,
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  color: c.searchBg.withValues(alpha: c.isDark ? 0.72 : 0.75),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: c.isDark
                        ? Colors.white.withValues(alpha: 0.08)
                        : Colors.black.withValues(alpha: 0.045),
                  ),
                ),
              ),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: children,
          ),
        ],
      ),
    );
  }
}
