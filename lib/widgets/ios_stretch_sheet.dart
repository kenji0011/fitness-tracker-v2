import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

import '../services/animation_speed_service.dart';
import '../services/appearance_service.dart';
import '../theme/app_colors.dart';
import 'tempo_spring_physics.dart';

/// Optional controller for two-detent sheets (Expanded <-> Preview Peek).
///
/// When passed to [showTempoSheet] alongside [peekHeight], the sheet can glide
/// smoothly between its full expanded height and a compact preview peek height
/// so the underlying screen stays unobstructed while adjusting live controls.
class TempoSheetController extends ChangeNotifier {
  bool _peeking;

  TempoSheetController({bool initialPeeking = false})
      : _peeking = initialPeeking;

  bool get isPeeking => _peeking;

  void setPeeking(bool value) {
    if (_peeking == value) return;
    _peeking = value;
    notifyListeners();
  }

  void togglePeek() => setPeeking(!_peeking);
}

/// Shows an iOS 26/27-inspired modal bottom sheet with:
/// - Critically-damped spring opening animation (slide + subtle scale + scrim fade)
/// - Real rubber-band upward stretch physics (`UISheetPresentationController` feel)
///   with a seamless bottom skirt and `SpringSimulation` recoil on release
/// - Optional two-detent Preview Peek mode ([controller] + [peekHeight]) with
///   live scrim lightening so underlying previews stay unobstructed
/// - Smooth interactive drag-to-dismiss with dynamic scrim opacity
Future<T?> showTempoSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  Color? backgroundColor,
  Color? skirtColor,
  double borderRadius = 28,
  bool isDismissible = true,
  bool enableDrag = true,
  bool showDragHandle = false,
  bool useRootNavigator = false,
  TempoSheetController? controller,
  double? peekHeight,
  double peekScrimAlpha = 0.08,
}) {
  return Navigator.of(context, rootNavigator: useRootNavigator).push<T>(
    _TempoSpringSheetRoute<T>(
      builder: builder,
      backgroundColor: backgroundColor,
      skirtColor: skirtColor,
      borderRadius: borderRadius,
      isDismissible: isDismissible,
      enableDrag: enableDrag,
      showDragHandle: showDragHandle,
      sheetController: controller,
      peekHeight: peekHeight,
      peekScrimAlpha: peekScrimAlpha,
    ),
  );
}

class _TempoSpringSheetRoute<T> extends PopupRoute<T> {
  final WidgetBuilder builder;
  final Color? backgroundColor;
  final Color? skirtColor;
  final double borderRadius;
  final bool isDismissible;
  final bool enableDrag;
  final bool showDragHandle;
  final TempoSheetController? sheetController;
  final double? peekHeight;
  final double peekScrimAlpha;

  final ValueNotifier<double> _dismissProgress = ValueNotifier<double>(0.0);

  _TempoSpringSheetRoute({
    required this.builder,
    this.backgroundColor,
    this.skirtColor,
    required this.borderRadius,
    required this.isDismissible,
    required this.enableDrag,
    required this.showDragHandle,
    this.sheetController,
    this.peekHeight,
    required this.peekScrimAlpha,
  });

  @override
  Color? get barrierColor => null; // Drawn manually for dynamic drag scrim fade

  @override
  bool get barrierDismissible => false;

  @override
  String? get barrierLabel => 'Dismiss';

  @override
  Duration get transitionDuration =>
      TempoAnimationSpeedService.instance.scale(const Duration(milliseconds: 440));

  @override
  Duration get reverseTransitionDuration =>
      TempoAnimationSpeedService.instance.scale(const Duration(milliseconds: 260));

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

  @override
  void dispose() {
    _dismissProgress.dispose();
    super.dispose();
  }

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return _TempoStretchSheetShell(
      routeAnimation: animation,
      dismissProgress: _dismissProgress,
      backgroundColor: backgroundColor,
      skirtColor: skirtColor,
      borderRadius: borderRadius,
      isDismissible: isDismissible,
      enableDrag: enableDrag,
      showDragHandle: showDragHandle,
      controller: sheetController,
      peekHeight: peekHeight,
      peekScrimAlpha: peekScrimAlpha,
      onDismiss: () {
        if (isCurrent) {
          Navigator.of(context).pop();
        }
      },
      child: Builder(builder: builder),
    );
  }
}

class _TempoStretchSheetShell extends StatefulWidget {
  final Animation<double> routeAnimation;
  final ValueNotifier<double> dismissProgress;
  final Color? backgroundColor;
  final Color? skirtColor;
  final double borderRadius;
  final bool isDismissible;
  final bool enableDrag;
  final bool showDragHandle;
  final TempoSheetController? controller;
  final double? peekHeight;
  final double peekScrimAlpha;
  final VoidCallback onDismiss;
  final Widget child;

  const _TempoStretchSheetShell({
    required this.routeAnimation,
    required this.dismissProgress,
    required this.backgroundColor,
    required this.skirtColor,
    required this.borderRadius,
    required this.isDismissible,
    required this.enableDrag,
    required this.showDragHandle,
    required this.controller,
    required this.peekHeight,
    required this.peekScrimAlpha,
    required this.onDismiss,
    required this.child,
  });

  @override
  State<_TempoStretchSheetShell> createState() =>
      _TempoStretchSheetShellState();
}

class _TempoStretchSheetShellState extends State<_TempoStretchSheetShell>
    with SingleTickerProviderStateMixin {
  final GlobalKey _sheetKey = GlobalKey();
  late final AnimationController _springController;

  /// Negative = stretched upward (rubber-band); Positive = dragged downward (peek/dismiss)
  double _dragOffset = 0.0;
  bool _isDragging = false;
  bool _stretchHapticFired = false;
  bool _syncingFromDrag = false;

  static const _springDesc = SpringDescription(
    mass: 1.0,
    stiffness: 380.0,
    damping: 25.0,
  );

  static const _detentSpringDesc = SpringDescription(
    mass: 1.0,
    stiffness: 360.0,
    damping: 32.0,
  );

  @override
  void initState() {
    super.initState();
    _springController = AnimationController.unbounded(vsync: this)
      ..addListener(() {
        setState(() {
          _dragOffset = _springController.value;
          _syncDismissProgress();
        });
      });
    widget.controller?.addListener(_onControllerChanged);
    if (widget.controller?.isPeeking == true && widget.peekHeight != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_hasPeekDetent) return;
        setState(() {
          _dragOffset = _peekOffset;
          _syncDismissProgress();
        });
      });
    }
  }

  @override
  void didUpdateWidget(covariant _TempoStretchSheetShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.removeListener(_onControllerChanged);
      widget.controller?.addListener(_onControllerChanged);
    }
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_onControllerChanged);
    _springController.dispose();
    super.dispose();
  }

  double get _sheetHeight {
    final box = _sheetKey.currentContext?.findRenderObject() as RenderBox?;
    return box?.size.height ?? 420.0;
  }

  double get _peekOffset {
    final targetPeek = widget.peekHeight;
    if (targetPeek == null) return 0.0;
    return math.max(0.0, _sheetHeight - targetPeek);
  }

  bool get _hasPeekDetent => widget.peekHeight != null && _peekOffset > 24.0;

  void _onControllerChanged() {
    if (!mounted || _isDragging || _syncingFromDrag || !_hasPeekDetent) return;
    final target = (widget.controller?.isPeeking ?? false) ? _peekOffset : 0.0;
    if ((_dragOffset - target).abs() < 0.5) return;
    final reduceMotion = TempoAppearanceService.instance.reduceAnimation ||
        MediaQuery.disableAnimationsOf(context);
    _springController.stop();
    if (reduceMotion) {
      setState(() {
        _dragOffset = target;
        _syncDismissProgress();
      });
      return;
    }
    final sim = SpringSimulation(
      _detentSpringDesc,
      _dragOffset,
      target,
      0.0,
    );
    _springController.animateWith(sim);
  }

  /// Authentic iOS logarithmic rubber-banding formula:
  /// `f(x, d) = (c * x * d) / (d + c * x)`
  double _rubberBand(double rawOverscroll, double dimension) {
    if (rawOverscroll <= 0) return 0.0;
    const c = 0.55;
    return (c * rawOverscroll * dimension) / (dimension + c * rawOverscroll);
  }

  void _syncDismissProgress() {
    if (_dragOffset > 0) {
      widget.dismissProgress.value =
          (_dragOffset / math.max(_sheetHeight, 260.0)).clamp(0.0, 1.0);
    } else {
      widget.dismissProgress.value = 0.0;
    }
  }

  void _onDragStart() {
    if (!widget.enableDrag) return;
    _springController.stop();
    _isDragging = true;
    _stretchHapticFired = false;
  }

  void _onDragDelta(double deltaY) {
    if (!widget.enableDrag) return;
    setState(() {
      _dragOffset += deltaY;
      if (_dragOffset < -28 && !_stretchHapticFired) {
        _stretchHapticFired = true;
        HapticFeedback.selectionClick();
      } else if (_dragOffset >= -8) {
        _stretchHapticFired = false;
      }
      _syncDismissProgress();
    });
  }

  void _onDragEnd(double velocityY) {
    if (!widget.enableDrag || !_isDragging) return;
    _isDragging = false;
    final h = _sheetHeight;

    if (_hasPeekDetent) {
      final peek = _peekOffset;
      final wasPeeking =
          widget.controller?.isPeeking ?? (_dragOffset > peek * 0.5);

      final shouldDismiss = widget.isDismissible &&
          _dragOffset > 0 &&
          (wasPeeking
              ? (_dragOffset > peek + 64.0 || velocityY > 560.0)
              : (_dragOffset > peek + 96.0 || velocityY > 1450.0));

      if (shouldDismiss) {
        HapticFeedback.lightImpact();
        widget.onDismiss();
        return;
      }

      final bool shouldPeek;
      if (wasPeeking) {
        shouldPeek = !(_dragOffset < peek - 36.0 || velocityY < -380.0);
      } else {
        shouldPeek =
            _dragOffset > math.min(peek * 0.25, 68.0) || velocityY > 380.0;
      }

      if (shouldPeek != wasPeeking) {
        HapticFeedback.selectionClick();
      }

      if (widget.controller != null &&
          widget.controller!.isPeeking != shouldPeek) {
        _syncingFromDrag = true;
        widget.controller!.setPeeking(shouldPeek);
        _syncingFromDrag = false;
      }

      final target = shouldPeek ? peek : 0.0;
      final sim = SpringSimulation(
        _detentSpringDesc,
        _dragOffset,
        target,
        velocityY.clamp(-2400.0, 2400.0),
      );
      _springController.animateWith(sim);
      return;
    }

    // Dismiss if dragged down far enough or flicked downward quickly
    final shouldDismiss = widget.isDismissible &&
        _dragOffset > 0 &&
        (velocityY > 680.0 || _dragOffset > math.min(h * 0.32, 150.0));

    if (shouldDismiss) {
      HapticFeedback.lightImpact();
      widget.onDismiss();
      return;
    }

    // Spring smoothly back to 0 using real SpringSimulation physics!
    final sim = SpringSimulation(
      _springDesc,
      _dragOffset,
      0.0,
      velocityY.clamp(-2400.0, 2400.0),
    );
    _springController.animateWith(sim);
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (!widget.enableDrag) return false;

    if (notification is OverscrollNotification &&
        notification.metrics.axis == Axis.vertical &&
        notification.dragDetails != null) {
      // User pulled past the top or bottom edge of an inner scrollable:
      // overscroll < 0 means pulling DOWN past top; overscroll > 0 means pulling UP past bottom
      if (!_isDragging) _onDragStart();
      _onDragDelta(-notification.overscroll);
      return false;
    }

    if (notification is ScrollUpdateNotification &&
        notification.metrics.axis == Axis.vertical &&
        _isDragging &&
        _dragOffset != 0.0 &&
        notification.dragDetails != null) {
      final dy = notification.dragDetails!.delta.dy;
      // Allow reversing back smoothly before handing control back to scroll
      if ((_dragOffset > 0 && dy < 0) || (_dragOffset < 0 && dy > 0)) {
        final next = _dragOffset + dy;
        if ((_dragOffset > 0 && next <= 0) || (_dragOffset < 0 && next >= 0)) {
          setState(() {
            _dragOffset = 0.0;
            _syncDismissProgress();
          });
        } else {
          _onDragDelta(dy);
        }
      }
      return false;
    }

    if (notification is ScrollEndNotification && _isDragging) {
      final velocity = notification.dragDetails?.primaryVelocity ?? 0.0;
      _onDragEnd(velocity);
      return false;
    }

    return false;
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final screenH = MediaQuery.sizeOf(context).height;
    final hasExplicitBg = widget.backgroundColor != null &&
        widget.backgroundColor != Colors.transparent;
    final effectiveSkirtColor = widget.skirtColor ??
        (hasExplicitBg
            ? widget.backgroundColor!
            : (c.isDark
                ? const Color(0xFF1C1C1E).withValues(alpha: 0.96)
                : const Color(0xFFF2F2F7).withValues(alpha: 0.96)));

    // Compute interactive transforms from _dragOffset
    final double stretchPx =
        _dragOffset < 0 ? _rubberBand(-_dragOffset, 220.0) : 0.0;
    final double translateY = _dragOffset > 0 ? _dragOffset : -stretchPx;
    // Subtle volume-preserving iOS elastic elongation on upward pull
    final double stretchScaleY = 1.0 + (stretchPx / 2400.0).clamp(0.0, 0.045);
    final double stretchScaleX = 1.0 - (stretchPx / 5400.0).clamp(0.0, 0.018);

    Widget content = widget.child;
    if (hasExplicitBg || widget.showDragHandle) {
      final baseColor = hasExplicitBg ? widget.backgroundColor! : c.card;
      content = Container(
        decoration: BoxDecoration(
          color: baseColor,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(widget.borderRadius),
          ),
          border: Border(
            top: BorderSide(
              color: c.isDark
                  ? Colors.white.withValues(alpha: 0.14)
                  : Colors.white.withValues(alpha: 0.90),
              width: 1.0,
            ),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: c.isDark ? 0.48 : 0.12),
              blurRadius: 28,
              spreadRadius: -4,
              offset: const Offset(0, -6),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(widget.borderRadius),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.showDragHandle)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: widget.controller != null && _hasPeekDetent
                      ? () {
                          HapticFeedback.selectionClick();
                          widget.controller!.togglePeek();
                        }
                      : null,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 10, bottom: 2),
                    child: Center(
                      child: Container(
                        width: 38,
                        height: 4.5,
                        decoration: BoxDecoration(
                          color: c.textTertiary.withValues(alpha: 0.36),
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                    ),
                  ),
                ),
              Flexible(child: widget.child),
            ],
          ),
        ),
      );
    } else {
      content = Material(
        type: MaterialType.transparency,
        child: widget.child,
      );
    }

    final Widget cachedSheetContent = RepaintBoundary(child: content);

    return AnimatedBuilder(
      animation: Listenable.merge([
        widget.routeAnimation,
        widget.dismissProgress,
      ]),
      builder: (context, child) {
        final rawT = widget.routeAnimation.value.clamp(0.0, 1.0);
        final isClosing =
            widget.routeAnimation.status == AnimationStatus.reverse ||
                widget.routeAnimation.status == AnimationStatus.dismissed;
        final t = isClosing
            ? (1.0 - TempoSpringCurves.sheetClose.transform(1.0 - rawT))
                .clamp(0.0, 1.0)
            : TempoSpringCurves.sheetOpen.transform(rawT);

        // Backdrop scrim smoothly fades in on open, lightens in Preview Peek
        // so live previews above stay vivid, and fades out during dismiss drag.
        final double baseScrim;
        if (_hasPeekDetent) {
          final peek = _peekOffset;
          if (_dragOffset <= 0) {
            baseScrim = 0.44;
          } else if (_dragOffset <= peek) {
            final p = (_dragOffset / peek).clamp(0.0, 1.0);
            baseScrim = ui.lerpDouble(
              0.44,
              widget.peekScrimAlpha,
              Curves.easeOut.transform(p),
            )!;
          } else {
            final remaining = math.max(_sheetHeight - peek, 120.0);
            final d = ((_dragOffset - peek) / remaining).clamp(0.0, 1.0);
            baseScrim = widget.peekScrimAlpha * (1.0 - d);
          }
        } else {
          baseScrim = 0.44 * (1.0 - widget.dismissProgress.value * 0.85);
        }
        final scrimAlpha = baseScrim * rawT;

        // Slide smoothly over the sheet's true measured height (zero Opacity
        // around BackdropFilter glass sheets, zero premature cutoff on tall sheets).
        final travelHeight = isClosing && _dragOffset > 0
            ? math.max(_sheetHeight - _dragOffset + 32.0, 220.0)
            : math.max(_sheetHeight + 28.0, screenH * 0.42);
        final openSlideY = (1.0 - t) * travelHeight;
        final openScale = 0.97 + 0.03 * t.clamp(0.0, 1.03);

        return IgnorePointer(
          ignoring: isClosing,
          child: Stack(
            children: [
              // Dynamic dimmed backdrop
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: widget.isDismissible ? widget.onDismiss : null,
                  child: ColoredBox(
                    color: Colors.black.withValues(alpha: scrimAlpha.clamp(0.0, 0.55)),
                  ),
                ),
              ),

              // Positioned sheet anchored at bottom
              Align(
                alignment: Alignment.bottomCenter,
                child: Transform.translate(
                  offset: Offset(0, openSlideY + translateY),
                  child: Transform(
                    alignment: Alignment.bottomCenter,
                    transform: Matrix4.diagonal3Values(
                      openScale * stretchScaleX,
                      openScale * stretchScaleY,
                      1.0,
                    ),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        // Seamless elastic bottom skirt so stretching upward never shows a gap!
                        if (stretchPx > 0.5)
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: -(stretchPx + 64),
                            height: stretchPx + 84,
                            child: IgnorePointer(
                              child: ColoredBox(color: effectiveSkirtColor),
                            ),
                          ),
                        NotificationListener<ScrollNotification>(
                          onNotification: _handleScrollNotification,
                          child: GestureDetector(
                            behavior: HitTestBehavior.translucent,
                            onVerticalDragStart: (_) => _onDragStart(),
                            onVerticalDragUpdate: (details) =>
                                _onDragDelta(details.delta.dy),
                            onVerticalDragEnd: (details) =>
                                _onDragEnd(details.primaryVelocity ?? 0.0),
                            onVerticalDragCancel: () => _onDragEnd(0.0),
                            child: ConstrainedBox(
                              key: _sheetKey,
                              constraints: BoxConstraints(
                                maxHeight: screenH * 0.92,
                              ),
                              child: child,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
      child: cachedSheetContent,
    );
  }
}
