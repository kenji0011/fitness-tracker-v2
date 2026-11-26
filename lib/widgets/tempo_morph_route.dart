import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../services/animation_speed_service.dart';
import '../theme/app_colors.dart';

/// Tracks the currently flying circular morph route's anchor button [Key] so
/// `TempoGlassCircleButton` swaps to an empty sized slot while its floating
/// circular droplet launches and docks back (zero ghost circle, unified with
/// `activeTempoPopoverAnchorKey`).
final ValueNotifier<Key?> activeTempoMorphAnchorKey =
    ValueNotifier<Key?>(null);

/// Pushes a full-screen page with an iOS / HyperOS 3-4 inspired container morph
/// transition that captures a live GPU snapshot of the tapped card or circular
/// header button ([sourceContext] or [sourceKey]), lifts & dissolves it into
/// the destination page on open, and cross-morphs back into the exact card or
/// floating circular button droplet when closed.
///
/// Engineered for locked 120Hz Impeller fluidity:
/// - Lays out the destination screen once at full size (zero RenderFlex
///   overflows or relayout churn during morph frames).
/// - Captures a synchronous GPU layer snapshot (`RenderRepaintBoundary.toImageSync`)
///   with zero tap latency and refreshes once on Frame 1 of close for cards so
///   closing matches resting `1.0`-scale live metrics.
/// - For circular header buttons (`sourceBorderRadius >= 999`, e.g. Summary `+`,
///   Progress Album camera, Stats Share), runs HyperOS 4's decoupled size-vs-center
///   droplet physics so closing collapses into a true 1:1 floating glass circle
///   with subtle Gaussian sharpen and zero ghost circle underneath.
/// - Never wraps `BackdropFilter` glass widgets in `Opacity`.
/// - Drops all clip/shadow/painter wrappers once settled (`t == 1.0`) and
///   releases the `ui.Image` immediately on route `dispose()`.
Future<T?> pushTempoMorphRoute<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  BuildContext? sourceContext,
  GlobalKey? sourceKey,
  double sourceBorderRadius = 22.0,
  Color? sourceColor,
  bool fullscreenDialog = false,
}) {
  final initialRect = _captureRect(
    sourceContext: sourceContext,
    sourceKey: sourceKey,
    navigatorContext: context,
  );
  final initialSnapshot = _captureSourceSnapshot(
    sourceContext: sourceContext,
    sourceKey: sourceKey,
    navigatorContext: context,
  );

  Rect? liveRectGetter() => _captureRect(
        sourceContext: sourceContext,
        sourceKey: sourceKey,
        navigatorContext: context,
      );

  TempoMorphCardSnapshot? liveSnapshotGetter() => _captureSourceSnapshot(
        sourceContext: sourceContext,
        sourceKey: sourceKey,
        navigatorContext: context,
      );

  final hasSource = sourceContext != null || sourceKey != null;

  return Navigator.of(context).push<T>(
    TempoMorphPageRoute<T>(
      builder: builder,
      sourceKey: sourceKey,
      initialSourceRect: initialRect,
      liveSourceRectGetter: hasSource ? liveRectGetter : null,
      initialSnapshot: initialSnapshot,
      liveSnapshotGetter: hasSource ? liveSnapshotGetter : null,
      sourceBorderRadius: sourceBorderRadius,
      sourceColor: sourceColor,
      fullscreenDialog: fullscreenDialog,
    ),
  );
}

/// Captured GPU layer snapshot of a morph source card/control, owned and
/// disposed by [TempoMorphPageRoute].
class TempoMorphCardSnapshot {
  final ui.Image image;
  final Rect srcRect;
  final Size logicalSize;
  final bool capturedIsDark;
  bool _disposed = false;

  TempoMorphCardSnapshot({
    required this.image,
    required this.srcRect,
    required this.logicalSize,
    required this.capturedIsDark,
  });

  bool get isUsable => !_disposed;

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    image.dispose();
  }
}

Rect? _captureRect({
  BuildContext? sourceContext,
  GlobalKey? sourceKey,
  required BuildContext navigatorContext,
}) {
  final targetCtx = sourceKey?.currentContext ?? sourceContext;
  if (targetCtx == null || !targetCtx.mounted) return null;
  final renderObject = targetCtx.findRenderObject();
  if (renderObject is! RenderBox ||
      !renderObject.hasSize ||
      !renderObject.attached) {
    return null;
  }
  final size = renderObject.size;
  if (size.width <= 1 || size.height <= 1) return null;

  RenderBox? ancestor;
  if (navigatorContext.mounted) {
    final overlay = Overlay.maybeOf(navigatorContext);
    final overlayObj = overlay?.context.findRenderObject();
    if (overlayObj is RenderBox && overlayObj.attached) {
      ancestor = overlayObj;
    }
  }

  final topLeft = renderObject.localToGlobal(Offset.zero, ancestor: ancestor);
  if (!topLeft.dx.isFinite || !topLeft.dy.isFinite) return null;
  return topLeft & size;
}

TempoMorphCardSnapshot? _captureSourceSnapshot({
  BuildContext? sourceContext,
  GlobalKey? sourceKey,
  required BuildContext navigatorContext,
}) {
  final targetCtx = sourceKey?.currentContext ?? sourceContext;
  if (targetCtx == null || !targetCtx.mounted) return null;
  final renderObject = targetCtx.findRenderObject();
  if (renderObject is! RenderBox ||
      !renderObject.hasSize ||
      !renderObject.attached) {
    return null;
  }
  final targetSize = renderObject.size;
  if (targetSize.width <= 1 || targetSize.height <= 1) return null;

  RenderObject? node = renderObject;
  RenderRepaintBoundary? boundary;
  while (node != null) {
    if (node is RenderRepaintBoundary) {
      boundary = node;
      break;
    }
    node = node.parent;
  }
  if (boundary == null || !boundary.attached || !boundary.hasSize) {
    return null;
  }

  // Release-safe check: RenderObject.debugNeedsPaint asserts internally and
  // throws LateInitializationError if read directly in release builds.
  var needsPaint = false;
  assert(() {
    needsPaint = boundary!.debugNeedsPaint;
    return true;
  }());
  if (needsPaint) return null;

  final boundarySize = boundary.size;
  if (boundarySize.width <= 1 || boundarySize.height <= 1) return null;

  final Offset offsetInBoundary;
  if (identical(renderObject, boundary)) {
    offsetInBoundary = Offset.zero;
  } else {
    offsetInBoundary = renderObject.localToGlobal(
      Offset.zero,
      ancestor: boundary,
    );
  }
  if (!offsetInBoundary.dx.isFinite || !offsetInBoundary.dy.isFinite) {
    return null;
  }

  final viewDpr = navigatorContext.mounted
      ? (View.maybeOf(navigatorContext)?.devicePixelRatio ?? 2.0)
      : 2.0;
  final maxDim = math.max(boundarySize.width, boundarySize.height);
  // Dedicated card/button boundaries capture crisp at up to 2.5x DPR (~0.5-1 MB).
  // Larger ancestor layers cap max dimension to 1080px to bound GPU memory.
  final double captureDpr = identical(renderObject, boundary)
      ? viewDpr.clamp(1.0, 2.5)
      : math.min(viewDpr.clamp(1.0, 2.2), 1080.0 / maxDim).clamp(0.75, 2.2);

  ui.Image image;
  try {
    image = boundary.toImageSync(pixelRatio: captureDpr);
  } catch (_) {
    return null;
  }

  final imgW = image.width.toDouble();
  final imgH = image.height.toDouble();
  if (imgW < 2 || imgH < 2) {
    image.dispose();
    return null;
  }

  final rawSrc = Rect.fromLTWH(
    offsetInBoundary.dx * captureDpr,
    offsetInBoundary.dy * captureDpr,
    targetSize.width * captureDpr,
    targetSize.height * captureDpr,
  );
  final clampedSrc = Rect.fromLTRB(
    rawSrc.left.clamp(0.0, imgW),
    rawSrc.top.clamp(0.0, imgH),
    rawSrc.right.clamp(0.0, imgW),
    rawSrc.bottom.clamp(0.0, imgH),
  );
  if (clampedSrc.width < 1 || clampedSrc.height < 1) {
    image.dispose();
    return null;
  }

  var capturedIsDark = false;
  if (navigatorContext.mounted) {
    try {
      capturedIsDark = AppColors.of(navigatorContext, listen: false).isDark;
    } catch (_) {
      capturedIsDark = Theme.of(navigatorContext).brightness == Brightness.dark;
    }
  }

  return TempoMorphCardSnapshot(
    image: image,
    srcRect: clampedSrc,
    logicalSize: targetSize,
    capturedIsDark: capturedIsDark,
  );
}

class TempoMorphPageRoute<T> extends PageRoute<T> {
  final WidgetBuilder builder;
  final GlobalKey? sourceKey;
  final Rect? initialSourceRect;
  final Rect? Function()? liveSourceRectGetter;
  final TempoMorphCardSnapshot? Function()? _liveSnapshotGetter;
  final double sourceBorderRadius;
  final Color? sourceColor;

  /// Silky, unhurried ease-in-out curve for opening (gentle launch, lush settle).
  static const Curve _openCurve = Cubic(0.36, 0.18, 0.18, 1.0);

  /// Slightly quicker center lead for circular button lift-off.
  static const Curve _openCircularCenterCurve = Cubic(0.32, 0.26, 0.18, 1.0);

  /// Smooth, cushioned collapse back into rectangular cards on closing.
  static const Curve _closeCurve = Cubic(0.38, 0.06, 0.22, 1.0);

  /// Calmer HyperOS 4-style decoupled curves for circular button close:
  /// gentle initial peel-off -> smooth 1:1 circle -> unhurried glide into slot.
  static const Curve _closeCircularSizeCurve = Cubic(0.38, 0.14, 0.20, 1.0);
  static const Curve _closeCircularCenterCurve = Cubic(0.46, 0.00, 0.22, 1.0);

  TempoMorphCardSnapshot? _sourceSnapshot;
  Rect? _cachedCloseRect;
  bool _capturedCloseRect = false;
  bool _scheduledCloseRecapture = false;
  bool _attachedStatusListener = false;
  bool _routeDisposed = false;

  TempoMorphPageRoute({
    required this.builder,
    this.sourceKey,
    this.initialSourceRect,
    this.liveSourceRectGetter,
    TempoMorphCardSnapshot? initialSnapshot,
    TempoMorphCardSnapshot? Function()? liveSnapshotGetter,
    this.sourceBorderRadius = 22.0,
    this.sourceColor,
    super.fullscreenDialog = false,
  })  : _sourceSnapshot = initialSnapshot,
        _liveSnapshotGetter = liveSnapshotGetter;

  bool get _isCircularKeySource {
    if (sourceKey == null || sourceBorderRadius < 999.0) return false;
    final r = initialSourceRect;
    if (r == null) return true;
    return (r.width - r.height).abs() <= 10.0 && r.width <= 84.0;
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
      TempoAnimationSpeedService.instance.scale(const Duration(milliseconds: 470));

  @override
  Duration get reverseTransitionDuration =>
      TempoAnimationSpeedService.instance.scale(const Duration(milliseconds: 420));

  void _syncAnchorSuppression(bool hideAnchor) {
    final key = sourceKey;
    if (key == null || !_isCircularKeySource) return;
    if (hideAnchor) {
      if (!identical(activeTempoMorphAnchorKey.value, key)) {
        activeTempoMorphAnchorKey.value = key;
      }
    } else if (identical(activeTempoMorphAnchorKey.value, key)) {
      activeTempoMorphAnchorKey.value = null;
    }
  }

  void _handleRouteStatus(AnimationStatus status) {
    if (_routeDisposed) return;
    final flying = status == AnimationStatus.forward ||
        status == AnimationStatus.reverse;
    _syncAnchorSuppression(flying);
  }

  @override
  void install() {
    super.install();
    if (_isCircularKeySource && !_attachedStatusListener && animation != null) {
      _attachedStatusListener = true;
      animation!.addStatusListener(_handleRouteStatus);
      _syncAnchorSuppression(true);
    }
  }

  @override
  void dispose() {
    _routeDisposed = true;
    if (_attachedStatusListener) {
      animation?.removeStatusListener(_handleRouteStatus);
      _attachedStatusListener = false;
    }
    _syncAnchorSuppression(false);
    _sourceSnapshot?.dispose();
    _sourceSnapshot = null;
    super.dispose();
  }

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return builder(context);
  }

  void _scheduleFreshCloseSnapshot() {
    if (_scheduledCloseRecapture ||
        _liveSnapshotGetter == null ||
        _isCircularKeySource) {
      return;
    }
    _scheduledCloseRecapture = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_routeDisposed) return;
      final fresh = _liveSnapshotGetter.call();
      if (fresh == null) return;
      if (_routeDisposed) {
        fresh.dispose();
        return;
      }
      final old = _sourceSnapshot;
      _sourceSnapshot = fresh;
      old?.dispose();
      changedInternalState();
    });
  }

  Rect? _resolveSourceRect(Size screen, {required bool isClosing}) {
    if (isClosing) {
      if (!_capturedCloseRect) {
        _capturedCloseRect = true;
        final live = liveSourceRectGetter?.call();
        if (live != null && _isReasonablyOnScreen(live, screen)) {
          _cachedCloseRect = live;
        } else if (initialSourceRect != null &&
            _isReasonablyOnScreen(initialSourceRect!, screen)) {
          _cachedCloseRect = initialSourceRect;
        }
      }
      return _cachedCloseRect;
    }
    _capturedCloseRect = false;
    _scheduledCloseRecapture = false;
    if (initialSourceRect != null &&
        _isReasonablyOnScreen(initialSourceRect!, screen)) {
      return initialSourceRect;
    }
    return null;
  }

  bool _isReasonablyOnScreen(Rect r, Size screen) {
    return r.right > -40 &&
        r.left < screen.width + 40 &&
        r.bottom > -40 &&
        r.top < screen.height + 40;
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

    final c = AppColors.of(context);
    final screen = MediaQuery.sizeOf(context);
    final rawT = animation.value.clamp(0.0, 1.0);
    final secRaw = secondaryAnimation.value.clamp(0.0, 1.0);

    // Zero overhead once completely settled with no stacked route above.
    if (rawT >= 0.999 && secRaw <= 0.001) {
      return child;
    }

    // Subtle layered depth scale when another morph route opens on top of this one.
    Widget pageContent = child;
    if (secRaw > 0.001) {
      final secT = Curves.easeOutCubic.transform(secRaw);
      final bgScale = ui.lerpDouble(1.0, 0.96, secT)!;
      pageContent = Transform.scale(
        scale: bgScale,
        child: pageContent,
      );
      if (rawT >= 0.999) {
        return pageContent;
      }
    }

    final isClosing = animation.status == AnimationStatus.reverse ||
        animation.status == AnimationStatus.dismissed;
    if (isClosing) {
      _scheduleFreshCloseSnapshot();
    }

    final double morphT = isClosing
        ? (1.0 - _closeCurve.transform(1.0 - rawT)).clamp(0.0, 1.0)
        : _openCurve.transform(rawT).clamp(0.0, 1.0);

    final fullRect = Offset.zero & screen;
    final sourceRect = _resolveSourceRect(screen, isClosing: isClosing) ??
        Rect.fromCenter(
          center: fullRect.center,
          width: screen.width * 0.84,
          height: screen.height * 0.70,
        );

    final maxOriginRadius =
        math.min(sourceRect.width, sourceRect.height) / 2.0;
    final startRadius = sourceBorderRadius.clamp(0.0, maxOriginRadius);
    final isCircularOrigin = sourceBorderRadius >= 999.0 &&
        (sourceRect.width - sourceRect.height).abs() <= 10.0 &&
        sourceRect.width <= 84.0;

    final Rect curRect;
    final double curRadius;
    final double effectiveFlightT;

    if (isCircularOrigin) {
      final sourceSize = math.max(sourceRect.width, sourceRect.height);
      if (isClosing) {
        // Unified HyperOS 4 circular droplet return:
        // Collapse width & height quickly into a true 1:1 circle while center
        // glides slightly behind into the clean empty top-right button slot.
        final closeP = (1.0 - rawT).clamp(0.0, 1.0);
        final sizeRemain =
            (1.0 - _closeCircularSizeCurve.transform(closeP)).clamp(0.0, 1.0);
        final centerRemain =
            (1.0 - _closeCircularCenterCurve.transform(closeP)).clamp(0.0, 1.0);

        final aspectToCircle =
            Curves.easeInOutCubic.transform((closeP / 0.56).clamp(0.0, 1.0));
        final rawW = ui.lerpDouble(sourceSize, fullRect.width, sizeRemain)!;
        final rawH = ui.lerpDouble(sourceSize, fullRect.height, sizeRemain)!;
        final circleD = ui.lerpDouble(
          sourceSize,
          math.min(fullRect.width, fullRect.height) * 0.54,
          sizeRemain,
        )!;
        final curW = ui.lerpDouble(rawW, circleD, aspectToCircle)!;
        final curH = ui.lerpDouble(rawH, circleD, aspectToCircle)!;
        final curCenter =
            Offset.lerp(sourceRect.center, fullRect.center, centerRemain)!;
        curRect = Rect.fromCenter(center: curCenter, width: curW, height: curH);

        final maxCurRadius = math.min(curW, curH) / 2.0;
        final radiusT = Curves.easeInCubic.transform(sizeRemain);
        curRadius = ui.lerpDouble(maxCurRadius, 0.0, radiusT)!
            .clamp(0.0, maxCurRadius);
        effectiveFlightT = centerRemain;
      } else {
        // Opening from circular button: circle lifts smoothly off its empty slot,
        // swells gracefully as a circle -> soft capsule, then unfurls to full screen.
        final sizeT = morphT;
        final centerT = _openCircularCenterCurve.transform(rawT).clamp(0.0, 1.0);
        final circleHold =
            (1.0 - Curves.easeInOutCubic.transform((rawT / 0.44).clamp(0.0, 1.0)))
                .clamp(0.0, 1.0);
        final rawW = ui.lerpDouble(sourceSize, fullRect.width, sizeT)!;
        final rawH = ui.lerpDouble(sourceSize, fullRect.height, sizeT)!;
        final circleD = ui.lerpDouble(
          sourceSize,
          math.min(fullRect.width, fullRect.height) * 0.58,
          sizeT,
        )!;
        final curW = ui.lerpDouble(rawW, circleD, circleHold * 0.72)!;
        final curH = ui.lerpDouble(rawH, circleD, circleHold * 0.72)!;
        final curCenter =
            Offset.lerp(sourceRect.center, fullRect.center, centerT)!;
        curRect = Rect.fromCenter(center: curCenter, width: curW, height: curH);

        final maxCurRadius = math.min(curW, curH) / 2.0;
        final radiusT = Curves.easeInCubic.transform(sizeT);
        curRadius = ui.lerpDouble(maxCurRadius, 0.0, radiusT)!
            .clamp(0.0, maxCurRadius);
        effectiveFlightT = sizeT;
      }
    } else {
      curRect = Rect.lerp(sourceRect, fullRect, morphT)!;
      final radiusT = Curves.easeInCubic.transform(morphT);
      final maxCurRadius = math.min(curRect.width, curRect.height) / 2.0;
      curRadius =
          ui.lerpDouble(startRadius, 0.0, radiusT)!.clamp(0.0, maxCurRadius);
      effectiveFlightT = morphT;
    }

    // Gentle proportional zoom of full-sized destination content inside the morphing clip.
    final startScale = (sourceRect.width / screen.width).clamp(0.56, 0.94);
    final contentScale = ui.lerpDouble(startScale, 1.0, effectiveFlightT)!;

    final effectiveSourceColor = sourceColor ?? c.card;
    final activeSnapshot = (_sourceSnapshot != null &&
            _sourceSnapshot!.isUsable &&
            _sourceSnapshot!.capturedIsDark == c.isDark)
        ? _sourceSnapshot
        : null;
    final hasSnapshot = activeSnapshot != null;

    // Two-stage GPU-snapshot cross-morph (zero Opacity around BackdropFilter).
    final double cardLayerAlpha;
    final double containerAlpha;
    final double snapshotBlurSigma;
    final bool renderPageContent;

    if (isClosing) {
      final closeP = (1.0 - rawT).clamp(0.0, 1.0);
      if (isCircularOrigin) {
        // Dissolve page smoothly into the circular droplet by closeP = 0.48 (~250ms,
        // right as curW x curH reaches a true 1:1 circle), then glide 100% opaque
        // straight into the clean empty top-right button slot.
        cardLayerAlpha = Curves.easeInOutCubic
            .transform(((closeP - 0.12) / 0.36).clamp(0.0, 1.0));
        renderPageContent = cardLayerAlpha < 0.995;
        containerAlpha = 1.0;
        // Subtle HyperOS 4 Gaussian sharpen as the circular icon materializes.
        final sharpP = ((closeP - 0.42) / 0.30).clamp(0.0, 1.0);
        snapshotBlurSigma =
            hasSnapshot ? 5.5 * (1.0 - Curves.easeOutCubic.transform(sharpP)) : 0.0;
      } else {
        cardLayerAlpha = Curves.easeInOutCubic
            .transform(((closeP - 0.10) / 0.42).clamp(0.0, 1.0));
        renderPageContent = cardLayerAlpha < 0.995;
        snapshotBlurSigma = 0.0;
        if (renderPageContent) {
          containerAlpha = 1.0;
        } else if (hasSnapshot) {
          containerAlpha = (1.0 -
                  Curves.easeOutCubic
                      .transform(((closeP - 0.86) / 0.14).clamp(0.0, 1.0)))
              .clamp(0.0, 1.0);
        } else {
          containerAlpha = (1.0 -
                  Curves.easeInOutCubic
                      .transform(((closeP - 0.52) / 0.48).clamp(0.0, 1.0)))
              .clamp(0.0, 1.0);
        }
      }
    } else {
      cardLayerAlpha = (1.0 -
              Curves.easeOutCubic
                  .transform(((rawT - 0.06) / 0.32).clamp(0.0, 1.0)))
          .clamp(0.0, 1.0);
      renderPageContent = rawT >= 0.05;
      containerAlpha = hasSnapshot
          ? 1.0
          : (renderPageContent
              ? 1.0
              : Curves.easeOutCubic.transform((rawT / 0.05).clamp(0.0, 1.0)));
      snapshotBlurSigma = isCircularOrigin && hasSnapshot
          ? 5.5 *
              Curves.easeInQuad
                  .transform(((rawT - 0.04) / 0.30).clamp(0.0, 1.0))
          : 0.0;
    }

    // Airy depth scrim + ultra-soft diffused shadow (zero dark outline/border).
    final scrimAlpha =
        (c.isDark ? 0.34 : 0.14) * effectiveFlightT * containerAlpha;
    final flightArc = math.sin(effectiveFlightT * math.pi).clamp(0.0, 1.0);
    final shadowAlpha =
        (c.isDark ? 0.24 : 0.09) * flightArc * containerAlpha;

    final surfaceColor =
        Color.lerp(effectiveSourceColor, c.scaffold, effectiveFlightT)!;

    Widget buildCardSurface(double alpha) {
      if (hasSnapshot) {
        Widget painted = CustomPaint(
          painter: _CardSnapshotPainter(
            snapshot: activeSnapshot,
            backgroundColor: effectiveSourceColor,
            sourceBorderRadius: startRadius,
            isCircularFill: isCircularOrigin,
            opacity: alpha,
            morphT: effectiveFlightT,
          ),
        );
        if (snapshotBlurSigma > 0.25) {
          painted = ImageFiltered(
            imageFilter: ui.ImageFilter.blur(
              sigmaX: snapshotBlurSigma,
              sigmaY: snapshotBlurSigma,
            ),
            child: painted,
          );
        }
        return painted;
      }
      return ColoredBox(
        color: effectiveSourceColor.withValues(alpha: alpha),
      );
    }

    Widget morphBody;
    if (renderPageContent) {
      morphBody = DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(curRadius),
          boxShadow: shadowAlpha > 0.004
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: shadowAlpha),
                    blurRadius: 36 * flightArc + 12,
                    spreadRadius: 0,
                    offset: Offset(0, 14 * flightArc + 2),
                  ),
                ]
              : const [],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(curRadius),
          child: ColoredBox(
            color: surfaceColor,
            child: Stack(
              fit: StackFit.expand,
              children: [
                OverflowBox(
                  alignment: Alignment.topCenter,
                  minWidth: screen.width,
                  maxWidth: screen.width,
                  minHeight: screen.height,
                  maxHeight: screen.height,
                  child: Transform.scale(
                    alignment: Alignment.topCenter,
                    scale: contentScale,
                    child: pageContent,
                  ),
                ),
                if (cardLayerAlpha > 0.004)
                  IgnorePointer(
                    child: buildCardSurface(cardLayerAlpha),
                  ),
              ],
            ),
          ),
        ),
      );
    } else {
      // Lightweight GPU card/circle snapshot gliding cleanly 1:1 into its slot
      // (zero BackdropFilter, zero destination subtree, zero stutter).
      morphBody = IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(curRadius),
            boxShadow: shadowAlpha > 0.004
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: shadowAlpha),
                      blurRadius: 32 * flightArc + 10,
                      offset: Offset(0, 10 * flightArc + 2),
                    ),
                  ]
                : const [],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(curRadius),
            child: buildCardSurface(containerAlpha),
          ),
        ),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        if (scrimAlpha > 0.004)
          IgnorePointer(
            child: ColoredBox(
              color: Colors.black.withValues(alpha: scrimAlpha),
            ),
          ),
        Positioned.fromRect(
          rect: curRect,
          child: morphBody,
        ),
      ],
    );
  }
}

/// Paints the captured GPU card/button snapshot cleanly inside the morphing
/// container with zero `saveLayer` overhead, aspect-preserving layout, and
/// corner-bleed masking for ancestor-captured cards.
class _CardSnapshotPainter extends CustomPainter {
  final TempoMorphCardSnapshot snapshot;
  final Color backgroundColor;
  final double sourceBorderRadius;
  final bool isCircularFill;
  final double opacity;
  final double morphT;

  const _CardSnapshotPainter({
    required this.snapshot,
    required this.backgroundColor,
    required this.sourceBorderRadius,
    required this.isCircularFill,
    required this.opacity,
    required this.morphT,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (opacity <= 0.004 || !snapshot.isUsable) return;
    final fullRect = Offset.zero & size;

    // Seamless card background behind the snapshot so any extra vertical height
    // during flight blends with zero seam.
    canvas.drawRect(
      fullRect,
      Paint()..color = backgroundColor.withValues(alpha: opacity),
    );

    final srcW = snapshot.logicalSize.width;
    final srcH = snapshot.logicalSize.height;
    if (srcW <= 1 || srcH <= 1) return;

    final isCompactControl = srcW < 88 || srcH < 64;
    final Rect dstRect;
    final double scaledRadius;

    if (isCircularFill) {
      // Fill the circular droplet cleanly with the captured TempoGlassCircleButton
      // (frosted surface + rim + centered glyph), scaling smoothly down to 1:1.
      final diameter = math.min(size.width, size.height);
      dstRect = Rect.fromCenter(
        center: fullRect.center,
        width: diameter,
        height: diameter,
      );
      scaledRadius = diameter / 2.0;
    } else if (isCompactControl) {
      // Keep small pill controls crisp & centered at a gentle capped scale.
      final scale = ui.lerpDouble(1.0, 1.28, morphT)!.clamp(1.0, 1.28);
      final w = math.min(size.width, srcW * scale);
      final h = math.min(size.height, srcH * scale);
      dstRect = Rect.fromCenter(center: fullRect.center, width: w, height: h);
      scaledRadius =
          (sourceBorderRadius * (w / srcW)).clamp(0.0, math.min(w, h) / 2.0);
    } else {
      // Full cards fill width proportionally from topCenter — icons, titles,
      // metric values, and mini charts never distort vertically.
      final scale = (size.width / srcW).clamp(0.5, 3.0);
      final dstW = size.width;
      final dstH = srcH * scale;
      dstRect = Rect.fromLTWH(0, 0, dstW, dstH);
      scaledRadius = (sourceBorderRadius * scale)
          .clamp(0.0, math.min(dstW, dstH) / 2.0);
    }

    canvas.save();
    if (scaledRadius > 0.5) {
      canvas.clipRRect(
        RRect.fromRectAndRadius(dstRect, Radius.circular(scaledRadius)),
      );
    }
    canvas.drawImageRect(
      snapshot.image,
      snapshot.srcRect,
      dstRect,
      Paint()
        ..color = Color.fromRGBO(255, 255, 255, opacity)
        ..filterQuality = FilterQuality.medium,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _CardSnapshotPainter oldDelegate) {
    return !identical(oldDelegate.snapshot, snapshot) ||
        oldDelegate.backgroundColor != backgroundColor ||
        oldDelegate.sourceBorderRadius != sourceBorderRadius ||
        oldDelegate.isCircularFill != isCircularFill ||
        oldDelegate.opacity != opacity ||
        oldDelegate.morphT != morphT;
  }
}
