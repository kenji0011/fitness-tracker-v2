import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../services/animation_speed_service.dart';
import '../services/appearance_service.dart';
import '../theme/app_colors.dart';
import 'liquid_glass_surface.dart';
import 'tempo_sliver_header.dart';
import 'tempo_spring_physics.dart';

/// Tracks the currently morphed calendar anchor [Key] so source date pills can
/// subtly suppress duplicate chrome during open/close flight.
final ValueNotifier<Key?> activeTempoCalendarAnchorKey =
    ValueNotifier<Key?>(null);

final Map<Key, Object> _activeCalendarOwnerByKey = <Key, Object>{};

/// Displays Tempo's unified floating **Liquid Glass Morphing Calendar** driven
/// by HyperOS 4 decoupled 2-spring physics (`popoverOpenCenter` / `Size` and
/// `popoverCloseCenter` / `Size`):
/// - Detaches seamlessly from [anchorKey]'s exact screen rect (`Date` pill) and
///   blooms into an elevated translucent Liquid Glass calendar card with
///   swipeable months, inline Month/Year quick-jump, `Today` jump pill, Tempo
///   Orange selected droplet, and cross-button touch-light scatter.
/// - Drops its modal barrier on Frame 0 of close (`0 ms` re-tap interruptibility)
///   and strictly avoids wrapping `BackdropFilter` in `Opacity`.
Future<DateTime?> showTempoMorphCalendar({
  required BuildContext context,
  required GlobalKey anchorKey,
  required DateTime initialDate,
  DateTime? firstDate,
  DateTime? lastDate,
  Set<String> recordedDateKeys = const {},
  Color? accentColor,
  double sourceBorderRadius = 18.0,
}) {
  final box = anchorKey.currentContext?.findRenderObject() as RenderBox?;
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;

  Rect anchorRect;
  if (box != null && box.attached && box.hasSize && overlay != null) {
    final topLeft = box.localToGlobal(Offset.zero, ancestor: overlay);
    anchorRect = topLeft & box.size;
  } else {
    final size = MediaQuery.sizeOf(context);
    anchorRect = Rect.fromCenter(
      center: Offset(size.width * 0.5, size.height * 0.62),
      width: (size.width - 48).clamp(200.0, 340.0),
      height: 48.0,
    );
  }

  final now = DateTime.now();
  final resolvedLast = lastDate ?? DateTime(now.year, now.month, now.day);
  final resolvedFirst = firstDate ?? DateTime(2020, 1, 1);
  final normalizedInit = DateTime(
    initialDate.year,
    initialDate.month,
    initialDate.day,
  );
  final clampedInit = normalizedInit.isAfter(resolvedLast)
      ? resolvedLast
      : (normalizedInit.isBefore(resolvedFirst)
          ? resolvedFirst
          : normalizedInit);

  return Navigator.of(context, rootNavigator: true).push<DateTime>(
    _TempoMorphCalendarRoute(
      anchorKey: anchorKey,
      anchorRect: anchorRect,
      initialDate: clampedInit,
      firstDate: DateTime(
        resolvedFirst.year,
        resolvedFirst.month,
        resolvedFirst.day,
      ),
      lastDate: DateTime(
        resolvedLast.year,
        resolvedLast.month,
        resolvedLast.day,
      ),
      recordedDateKeys: recordedDateKeys,
      accentColor: accentColor,
      sourceBorderRadius: sourceBorderRadius,
    ),
  );
}

class _TempoMorphCalendarRoute extends PopupRoute<DateTime> {
  final GlobalKey anchorKey;
  final Rect anchorRect;
  final DateTime initialDate;
  final DateTime firstDate;
  final DateTime lastDate;
  final Set<String> recordedDateKeys;
  final Color? accentColor;
  final double sourceBorderRadius;

  static final ImageFilter _glassBlurFilter = ImageFilter.blur(
    sigmaX: 24.0,
    sigmaY: 24.0,
  );

  bool _attachedStatusListener = false;

  _TempoMorphCalendarRoute({
    required this.anchorKey,
    required this.anchorRect,
    required this.initialDate,
    required this.firstDate,
    required this.lastDate,
    required this.recordedDateKeys,
    required this.accentColor,
    required this.sourceBorderRadius,
  });

  @override
  Color? get barrierColor => Colors.transparent;

  @override
  bool get barrierDismissible => true;

  @override
  String? get barrierLabel => 'Dismiss calendar';

  bool get _reduceMotion => TempoAppearanceService.instance.reduceAnimation;

  @override
  Duration get transitionDuration => _reduceMotion
      ? const Duration(milliseconds: 180)
      : TempoAnimationSpeedService.instance.scale(
          const Duration(milliseconds: 420),
        );

  @override
  Duration get reverseTransitionDuration => _reduceMotion
      ? const Duration(milliseconds: 150)
      : TempoAnimationSpeedService.instance.scale(
          const Duration(milliseconds: 280),
        );

  void _syncAnchorSuppression(bool hideAnchor) {
    if (hideAnchor) {
      _activeCalendarOwnerByKey[anchorKey] = this;
      if (!identical(activeTempoCalendarAnchorKey.value, anchorKey)) {
        activeTempoCalendarAnchorKey.value = anchorKey;
      }
    } else if (identical(_activeCalendarOwnerByKey[anchorKey], this)) {
      _activeCalendarOwnerByKey.remove(anchorKey);
      if (identical(activeTempoCalendarAnchorKey.value, anchorKey)) {
        activeTempoCalendarAnchorKey.value = null;
      }
    }
  }

  bool get _superseded {
    final owner = _activeCalendarOwnerByKey[anchorKey];
    return owner != null && !identical(owner, this);
  }

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

  void _handleStatus(AnimationStatus status) {
    // Release the real Date pill immediately when closing starts so the closing
    // glass shell melts seamlessly back into the real pill with zero flash/swap.
    final hideAnchor = status == AnimationStatus.forward ||
        status == AnimationStatus.completed;
    _syncAnchorSuppression(hideAnchor);
  }

  @override
  void install() {
    super.install();
    if (!_attachedStatusListener && animation != null) {
      _attachedStatusListener = true;
      animation!.addStatusListener(_handleStatus);
    }
    _syncAnchorSuppression(true);
  }

  @override
  void dispose() {
    if (_attachedStatusListener) {
      animation?.removeStatusListener(_handleStatus);
      _attachedStatusListener = false;
    }
    _syncAnchorSuppression(false);
    super.dispose();
  }

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    final c = AppColors.of(context);
    final screen = MediaQuery.sizeOf(context);
    final pad = MediaQuery.paddingOf(context);
    final viewInsets = MediaQuery.viewInsetsOf(context);
    final appearance = TempoAppearanceService.instance.value;

    final targetW = math.min(screen.width - 28.0, 364.0).clamp(280.0, 380.0);
    const targetH = 408.0;
    const endRadius = 28.0;

    final usableBottom =
        screen.height - math.max(pad.bottom, viewInsets.bottom) - 16.0;
    final minTop = pad.top + 16.0;
    final maxTop = math.max(minTop, usableBottom - targetH);

    // Anchor smoothly near the Date pill (preferring slightly above/centered on
    // the pill so it rises naturally from the control without leaving the screen).
    final preferredTop = (anchorRect.center.dy - targetH * 0.56);
    final endTop = preferredTop.clamp(minTop, maxTop).toDouble();
    final endLeft = ((screen.width - targetW) * 0.5)
        .clamp(
          14.0,
          math.max(14.0, screen.width - targetW - 14.0),
        )
        .toDouble();
    final endRect = Rect.fromLTWH(endLeft, endTop, targetW, targetH);

    final startW = anchorRect.width.clamp(48.0, targetW);
    final startH = anchorRect.height.clamp(38.0, targetH);
    final startCenter = anchorRect.center;
    final endCenter = endRect.center;
    final startRadius = sourceBorderRadius.clamp(12.0, startH * 0.5);

    final calendarContent = RepaintBoundary(
      child: SizedBox(
        width: targetW,
        height: targetH,
        child: _TempoMorphCalendarBody(
          initialDate: initialDate,
          firstDate: firstDate,
          lastDate: lastDate,
          recordedDateKeys: recordedDateKeys,
          accentColor: accentColor ?? c.accent,
          onSelect: (picked) => Navigator.of(context).pop(picked),
        ),
      ),
    );

    return AnimatedBuilder(
      animation: animation,
      child: calendarContent,
      builder: (context, child) {
        if (_superseded) return const SizedBox.shrink();

        final rawT = animation.value.clamp(0.0, 1.0);
        final isClosing = animation.status == AnimationStatus.reverse ||
            animation.status == AnimationStatus.dismissed;
        final isSettled = animation.status == AnimationStatus.completed;
        final reduced =
            _reduceMotion || MediaQuery.disableAnimationsOf(context);

        double sizeT;
        double centerT;
        double contentOpacity;
        double shellAlpha;
        double scrimAlpha;

        if (reduced) {
          final t = Curves.easeOutCubic.transform(rawT);
          sizeT = t;
          centerT = t;
          contentOpacity = ((t - 0.08) / 0.65).clamp(0.0, 1.0);
          shellAlpha = t;
          scrimAlpha = t;
        } else if (isClosing) {
          // Single-phase synchronized 120Hz collapse: size & center arrive
          // together at anchorRect with zero premature stall or dead-hang!
          final closeP = (1.0 - rawT).clamp(0.0, 1.0);
          final glide = Curves.easeOutCubic.transform(closeP);
          sizeT = (1.0 - glide).clamp(0.0, 1.0);
          centerT = (1.0 - glide).clamp(0.0, 1.0);
          // Fade calendar content out cleanly BEFORE the rect gets short (zero pancake squash)
          contentOpacity = (1.0 - closeP / 0.42).clamp(0.0, 1.0);
          // Dissolve frosted glass shell seamlessly into the real Date pill waiting underneath
          shellAlpha = (1.0 - ((closeP - 0.52) / 0.48)).clamp(0.0, 1.0);
          scrimAlpha = (1.0 - Curves.easeOut.transform(closeP)).clamp(0.0, 1.0);
        } else {
          sizeT = TempoSpringCurves.popoverOpenSize.transform(rawT);
          centerT = TempoSpringCurves.popoverOpenCenter.transform(rawT);
          contentOpacity = ((rawT - 0.14) / 0.42).clamp(0.0, 1.0);
          shellAlpha = (rawT / 0.28).clamp(0.0, 1.0);
          scrimAlpha = Curves.easeOut.transform(rawT);
        }

        if (shellAlpha <= 0.004 && scrimAlpha <= 0.004) {
          return const SizedBox.shrink();
        }

        final curW = (startW + (targetW - startW) * sizeT)
            .clamp(startW * 0.92, targetW * 1.025);
        final curH = (startH + (targetH - startH) * sizeT)
            .clamp(startH * 0.92, targetH * 1.025);
        final curCenter = Offset(
          startCenter.dx + (endCenter.dx - startCenter.dx) * centerT,
          startCenter.dy + (endCenter.dy - startCenter.dy) * centerT,
        );
        final curRadius =
            (startRadius + (endRadius - startRadius) * sizeT.clamp(0.0, 1.0))
                .clamp(10.0, math.min(curW, curH) * 0.5);

        // Aspect-preserving gentle content scale (0.90 -> 1.0) so calendar text
        // never distorts or squashes vertically during flight!
        final contentScale = 0.90 + 0.10 * sizeT.clamp(0.0, 1.03);
        final useLiveBlur =
            appearance.allowDynamicBlur && (isSettled || (!isClosing && rawT > 0.65));
        final useRim = appearance.useLiquidGlass;

        final fillColor = useLiveBlur
            ? (c.isDark
                ? const Color(0xFF1A1B20).withValues(alpha: 0.72)
                : Colors.white.withValues(alpha: 0.82))
            : (c.isDark
                ? const Color(0xFF1D1E24).withValues(alpha: 0.92 * shellAlpha)
                : Colors.white.withValues(alpha: 0.95 * shellAlpha));

        final cardFill = BoxDecoration(
          borderRadius: BorderRadius.circular(curRadius),
          color: fillColor,
          border: !useRim
              ? Border.all(
                  color: c.cardBorder.withValues(alpha: shellAlpha),
                  width: 0.9,
                )
              : null,
        );

        final innerContent = contentOpacity > 0.01
            ? Opacity(
                opacity: contentOpacity,
                child: OverflowBox(
                  alignment: Alignment.center,
                  minWidth: targetW,
                  maxWidth: targetW,
                  minHeight: targetH,
                  maxHeight: targetH,
                  child: Transform.scale(
                    scale: contentScale,
                    child: child,
                  ),
                ),
              )
            : const SizedBox.expand();

        final glassBody = DecoratedBox(
          decoration: cardFill,
          child: useRim
              ? CustomPaint(
                  foregroundPainter: LiquidGlassRimPainter(
                    borderRadius: curRadius,
                    isDark: c.isDark,
                    intensity: (c.isDark ? 1.08 : 1.02) * shellAlpha,
                    strokeWidth: 1.25,
                    showTopMeniscus: true,
                  ),
                  child: innerContent,
                )
              : innerContent,
        );

        final clippedCard = TempoTouchLightEffect(
          borderRadius: curRadius,
          emitLight: false,
          receiveScatter: isSettled,
          scatterGain: 1.08,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(curRadius),
            child: useLiveBlur
                ? BackdropFilter(
                    filter: _glassBlurFilter,
                    child: glassBody,
                  )
                : glassBody,
          ),
        );

        return IgnorePointer(
          ignoring: isClosing,
          child: Stack(
            children: [
              // Smoothly fading backdrop scrim (never snaps off abruptly on close!)
              if (scrimAlpha > 0.004)
                Positioned.fill(
                  child: IgnorePointer(
                    child: ColoredBox(
                      color: Colors.black.withValues(
                        alpha: (c.isDark ? 0.34 : 0.22) * scrimAlpha,
                      ),
                    ),
                  ),
                ),
              if (shellAlpha > 0.004)
                Positioned(
                  left: curCenter.dx - curW * 0.5,
                  top: curCenter.dy - curH * 0.5,
                  width: curW,
                  height: curH,
                  child: Material(
                    type: MaterialType.transparency,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(curRadius),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(
                              alpha: (c.isDark ? 0.52 : 0.16) * shellAlpha,
                            ),
                            blurRadius: 32,
                            spreadRadius: -4,
                            offset: const Offset(0, 14),
                          ),
                        ],
                      ),
                      child: clippedCard,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _TempoMorphCalendarBody extends StatefulWidget {
  final DateTime initialDate;
  final DateTime firstDate;
  final DateTime lastDate;
  final Set<String> recordedDateKeys;
  final Color accentColor;
  final ValueChanged<DateTime> onSelect;

  const _TempoMorphCalendarBody({
    required this.initialDate,
    required this.firstDate,
    required this.lastDate,
    required this.recordedDateKeys,
    required this.accentColor,
    required this.onSelect,
  });

  @override
  State<_TempoMorphCalendarBody> createState() =>
      _TempoMorphCalendarBodyState();
}

class _TempoMorphCalendarBodyState extends State<_TempoMorphCalendarBody> {
  static const List<String> _weekdays = [
    'MON',
    'TUE',
    'WED',
    'THU',
    'FRI',
    'SAT',
    'SUN',
  ];

  late DateTime _visibleMonth;
  late DateTime _selectedDate;
  late final DateTime _today;
  bool _pickingMonthYear = false;
  int _slideDir = 1;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _today = DateTime(now.year, now.month, now.day);
    _selectedDate = widget.initialDate;
    _visibleMonth = DateTime(_selectedDate.year, _selectedDate.month, 1);
  }

  bool get _canGoPrev {
    final prev = DateTime(_visibleMonth.year, _visibleMonth.month - 1, 1);
    final minMonth = DateTime(widget.firstDate.year, widget.firstDate.month, 1);
    return !prev.isBefore(minMonth);
  }

  bool get _canGoNext {
    final next = DateTime(_visibleMonth.year, _visibleMonth.month + 1, 1);
    final maxMonth = DateTime(widget.lastDate.year, widget.lastDate.month, 1);
    return !next.isAfter(maxMonth);
  }

  bool get _isViewingTodayMonth =>
      _visibleMonth.year == _today.year && _visibleMonth.month == _today.month;

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  void _stepMonth(int delta) {
    if (delta < 0 && !_canGoPrev) return;
    if (delta > 0 && !_canGoNext) return;
    HapticFeedback.selectionClick();
    setState(() {
      _slideDir = delta >= 0 ? 1 : -1;
      _visibleMonth = DateTime(_visibleMonth.year, _visibleMonth.month + delta, 1);
    });
  }

  void _stepYear(int delta) {
    final nextYear =
        (_visibleMonth.year + delta).clamp(widget.firstDate.year, widget.lastDate.year);
    if (nextYear == _visibleMonth.year) return;
    HapticFeedback.selectionClick();
    setState(() {
      _visibleMonth = DateTime(nextYear, _visibleMonth.month, 1);
    });
  }

  void _jumpToToday() {
    HapticFeedback.selectionClick();
    final target = _today.isAfter(widget.lastDate)
        ? widget.lastDate
        : (_today.isBefore(widget.firstDate) ? widget.firstDate : _today);
    if (_isSameDay(target, _selectedDate) && _isViewingTodayMonth) {
      widget.onSelect(target);
      return;
    }
    setState(() {
      _pickingMonthYear = false;
      _selectedDate = target;
      _visibleMonth = DateTime(target.year, target.month, 1);
    });
    widget.onSelect(target);
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final accent = widget.accentColor;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Top Header: Month/Year dropdown toggle + Today pill + Prev/Next arrows
          Row(
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _pickingMonthYear = !_pickingMonthYear);
                    },
                    child: TempoTouchLightEffect(
                      borderRadius: 999,
                      intensity: 0.9,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 11,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: c.isDark
                              ? Colors.white.withValues(alpha: 0.08)
                              : Colors.black.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: c.isDark
                                ? Colors.white.withValues(alpha: 0.10)
                                : Colors.black.withValues(alpha: 0.05),
                            width: 0.7,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                _pickingMonthYear
                                    ? '${_visibleMonth.year}'
                                    : DateFormat('MMMM yyyy')
                                        .format(_visibleMonth),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: c.textPrimary,
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -0.3,
                                ),
                              ),
                            ),
                            const SizedBox(width: 5),
                            AnimatedRotation(
                              turns: _pickingMonthYear ? 0.5 : 0.0,
                              duration: const Duration(milliseconds: 220),
                              curve: Curves.easeOutCubic,
                              child: Icon(
                                CupertinoIcons.chevron_down,
                                size: 13,
                                color: accent,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (!_isViewingTodayMonth || !_isSameDay(_selectedDate, _today)) ...[
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _jumpToToday,
                  child: TempoTouchLightEffect(
                    borderRadius: 999,
                    intensity: 0.9,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: c.isDark ? 0.22 : 0.12),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        'Today',
                        style: TextStyle(
                          color: accent,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
              ],
              TempoGlassCircleButton(
                size: 34,
                enableBlur: false,
                enableRefraction: false,
                tooltip: _pickingMonthYear ? 'Previous year' : 'Previous month',
                onPressed: _pickingMonthYear
                    ? () => _stepYear(-1)
                    : () => _stepMonth(-1),
                icon: Icon(
                  CupertinoIcons.chevron_left,
                  size: 15,
                  color: (_pickingMonthYear
                          ? _visibleMonth.year > widget.firstDate.year
                          : _canGoPrev)
                      ? c.textPrimary
                      : c.textTertiary.withValues(alpha: 0.35),
                ),
              ),
              const SizedBox(width: 6),
              TempoGlassCircleButton(
                size: 34,
                enableBlur: false,
                enableRefraction: false,
                tooltip: _pickingMonthYear ? 'Next year' : 'Next month',
                onPressed: _pickingMonthYear
                    ? () => _stepYear(1)
                    : () => _stepMonth(1),
                icon: Icon(
                  CupertinoIcons.chevron_right,
                  size: 15,
                  color: (_pickingMonthYear
                          ? _visibleMonth.year < widget.lastDate.year
                          : _canGoNext)
                      ? c.textPrimary
                      : c.textTertiary.withValues(alpha: 0.35),
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              child: _pickingMonthYear
                  ? _buildMonthYearGrid(c, accent)
                  : _buildDayGrid(c, accent),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDayGrid(AppColors c, Color accent) {
    final monthKey =
        ValueKey('${_visibleMonth.year}-${_visibleMonth.month}');
    final daysInMonth =
        DateUtils.getDaysInMonth(_visibleMonth.year, _visibleMonth.month);
    final leadingBlanks = _visibleMonth.weekday - 1; // Mon = 0
    final totalCells = leadingBlanks + daysInMonth;
    final rows = (totalCells / 7).ceil().clamp(4, 6);

    return GestureDetector(
      key: const ValueKey('day_grid_view'),
      behavior: HitTestBehavior.translucent,
      onHorizontalDragEnd: (details) {
        final vx = details.primaryVelocity ?? 0.0;
        if (vx < -180) {
          _stepMonth(1);
        } else if (vx > 180) {
          _stepMonth(-1);
        }
      },
      child: Column(
        children: [
          // Weekday header
          Row(
            children: _weekdays
                .map(
                  (d) => Expanded(
                    child: Center(
                      child: Text(
                        d,
                        style: TextStyle(
                          color: c.textTertiary,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 8),
          Divider(height: 1, color: c.divider),
          const SizedBox(height: 8),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              transitionBuilder: (child, anim) {
                final slide = Tween<Offset>(
                  begin: Offset(0.12 * _slideDir, 0),
                  end: Offset.zero,
                ).animate(
                  CurvedAnimation(parent: anim, curve: Curves.easeOutCubic),
                );
                return FadeTransition(
                  opacity: anim,
                  child: SlideTransition(position: slide, child: child),
                );
              },
              child: Column(
                key: monthKey,
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: List.generate(rows, (rowIdx) {
                  return Row(
                    children: List.generate(7, (colIdx) {
                      final dayNum = rowIdx * 7 + colIdx - leadingBlanks + 1;
                      if (dayNum < 1 || dayNum > daysInMonth) {
                        return const Expanded(child: SizedBox(height: 40));
                      }

                      final cellDate = DateTime(
                        _visibleMonth.year,
                        _visibleMonth.month,
                        dayNum,
                      );
                      final disabled = cellDate.isBefore(widget.firstDate) ||
                          cellDate.isAfter(widget.lastDate);
                      final isSelected = _isSameDay(cellDate, _selectedDate);
                      final isToday = _isSameDay(cellDate, _today);
                      final hasRecord = widget.recordedDateKeys.contains(
                        DateFormat('yyyy-MM-dd').format(cellDate),
                      );

                      return Expanded(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: disabled
                              ? null
                              : () {
                                  HapticFeedback.selectionClick();
                                  setState(() => _selectedDate = cellDate);
                                  widget.onSelect(cellDate);
                                },
                          child: SizedBox(
                            height: 42,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                TempoTouchLightEffect(
                                  borderRadius: 999,
                                  enabled: !disabled,
                                  isAccentSurface: isSelected,
                                  intensity: 0.9,
                                  receiveScatter: false,
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 160),
                                    curve: Curves.easeOutCubic,
                                    width: 36,
                                    height: 36,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: isSelected
                                          ? accent
                                          : Colors.transparent,
                                      border: !isSelected && isToday
                                          ? Border.all(
                                              color: accent.withValues(
                                                alpha: 0.72,
                                              ),
                                              width: 1.3,
                                            )
                                          : null,
                                      boxShadow: isSelected
                                          ? [
                                              BoxShadow(
                                                color: accent.withValues(
                                                  alpha: 0.34,
                                                ),
                                                blurRadius: 10,
                                                offset: const Offset(0, 3),
                                              ),
                                            ]
                                          : null,
                                    ),
                                    child: Text(
                                      '$dayNum',
                                      style: TextStyle(
                                        color: isSelected
                                            ? Colors.white
                                            : (disabled
                                                ? c.textTertiary
                                                    .withValues(alpha: 0.32)
                                                : (isToday
                                                    ? accent
                                                    : c.textPrimary)),
                                        fontSize: 14.5,
                                        fontWeight: isSelected || isToday
                                            ? FontWeight.w700
                                            : FontWeight.w500,
                                        fontFeatures: const [
                                          FontFeature.tabularFigures(),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                if (hasRecord && !isSelected)
                                  Positioned(
                                    bottom: 1,
                                    child: Container(
                                      width: 4,
                                      height: 4,
                                      decoration: BoxDecoration(
                                        color: accent,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }),
                  );
                }),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMonthYearGrid(AppColors c, Color accent) {
    final year = _visibleMonth.year;
    final minMonth = DateTime(widget.firstDate.year, widget.firstDate.month, 1);
    final maxMonth = DateTime(widget.lastDate.year, widget.lastDate.month, 1);

    return GridView.builder(
      key: ValueKey('month_grid_$year'),
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.only(top: 12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 12,
        crossAxisSpacing: 10,
        childAspectRatio: 2.05,
      ),
      itemCount: 12,
      itemBuilder: (_, idx) {
        final monthNum = idx + 1;
        final monthFirst = DateTime(year, monthNum, 1);
        final disabled =
            monthFirst.isBefore(minMonth) || monthFirst.isAfter(maxMonth);
        final isSelected = _visibleMonth.month == monthNum;
        final label = DateFormat('MMM').format(monthFirst);

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: disabled
              ? null
              : () {
                  HapticFeedback.selectionClick();
                  setState(() {
                    _visibleMonth = monthFirst;
                    _pickingMonthYear = false;
                  });
                },
          child: TempoTouchLightEffect(
            borderRadius: 16,
            enabled: !disabled,
            isAccentSurface: isSelected,
            intensity: 0.92,
            child: CustomPaint(
              foregroundPainter: LiquidGlassRimPainter(
                borderRadius: 16,
                isDark: c.isDark,
                intensity: isSelected ? 1.1 : 0.65,
                strokeWidth: 0.9,
                showTopMeniscus: false,
                tintColor: isSelected ? accent : null,
              ),
              child: Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isSelected
                      ? accent
                      : (c.isDark
                          ? Colors.white.withValues(alpha: 0.06)
                          : Colors.black.withValues(alpha: 0.04)),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    color: isSelected
                        ? Colors.white
                        : (disabled
                            ? c.textTertiary.withValues(alpha: 0.35)
                            : c.textPrimary),
                    fontSize: 15,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
