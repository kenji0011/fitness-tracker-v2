import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../services/animation_speed_service.dart';
import '../theme/app_colors.dart';
import 'tempo_spring_physics.dart';

/// Tracks the currently flying circular morph route's anchor button [Key] so
/// `TempoGlassCircleButton` swaps to an empty sized slot while its floating
/// circular droplet launches and docks back (zero ghost circle, unified with
/// `activeTempoPopoverAnchorKey`).
final ValueNotifier<Key?> activeTempoMorphAnchorKey =
    ValueNotifier<Key?>(null);

/// Tracks the latest active [TempoMorphPageRoute] per anchor [Key] so rapid
/// re-taps mid-close immediately claim anchor ownership, suppress the stale
/// closing droplet, and reuse its GPU snapshot via zero-copy `image.clone()`.
final Map<Key, TempoMorphPageRoute<dynamic>> _activeMorphRouteByKey =
    <Key, TempoMorphPageRoute<dynamic>>{};

/// Pushes a full-screen page with a locked-120Hz iOS 26 / HyperOS 4 container
/// morph transition that captures a live GPU snapshot of the tapped card or
/// circular header button ([sourceContext] or [sourceKey]), lifts & dissolves
/// it into the destination page on open, and captures a synchronous GPU page
/// snapshot on close (`didPop`) so the entire return flight runs as a single
/// paint-only Canvas pass with zero reparenting, zero live `BackdropFilter`
/// raster churn, and zero dropped frames.
///
/// By default ([waitForCloseAnimation] = `true`), the returned [Future] waits
/// for `route.completed` before resolving so post-pop SQLite reloads and
/// `setState()` calls on the caller screen never contend with closing frames.
Future<T?> pushTempoMorphRoute<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  BuildContext? sourceContext,
  GlobalKey? sourceKey,
  double sourceBorderRadius = 22.0,
  Color? sourceColor,
  bool fullscreenDialog = false,
  bool waitForCloseAnimation = true,
}) async {
  var initialRect = _captureRect(
    sourceContext: sourceContext,
    sourceKey: sourceKey,
    navigatorContext: context,
  );
  var initialSnapshot = _captureSourceSnapshot(
    sourceContext: sourceContext,
    sourceKey: sourceKey,
    navigatorContext: context,
  );

  // Rapid re-tap support: if the user taps the same circular/squircle button
  // while its previous route is still mid-close (anchor hidden), inherit the
  // exact resting rect and a zero-copy cloned GPU snapshot with 0 ms delay!
  if (sourceKey != null) {
    final activePrev = _activeMorphRouteByKey[sourceKey];
    if (activePrev != null && !activePrev._routeDisposed) {
      initialRect ??= activePrev._cachedCloseRect ?? activePrev.initialSourceRect;
      initialSnapshot ??= activePrev._sourceSnapshot?.clone();
    }
  }

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

  final route = TempoMorphPageRoute<T>(
    builder: builder,
    sourceKey: sourceKey,
    initialSourceRect: initialRect,
    liveSourceRectGetter: hasSource ? liveRectGetter : null,
    initialSnapshot: initialSnapshot,
    liveSnapshotGetter: hasSource ? liveSnapshotGetter : null,
    sourceBorderRadius: sourceBorderRadius,
    sourceColor: sourceColor,
    fullscreenDialog: fullscreenDialog,
  );

  final result = await Navigator.of(context).push<T>(route);
  if (waitForCloseAnimation) {
    try {
      await route.completed;
    } catch (_) {}
  }
  return result;
}

/// Captured GPU layer snapshot of a morph source card/control or settled page,
/// owned and disposed by [TempoMorphPageRoute].
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

  /// Returns an independently owned zero-copy GPU texture handle (`ui.Image.clone`)
  /// so rapid re-taps mid-close can launch immediately without recapturing.
  TempoMorphCardSnapshot? clone() {
    if (_disposed) return null;
    try {
      return TempoMorphCardSnapshot(
        image: image.clone(),
        srcRect: srcRect,
        logicalSize: logicalSize,
        capturedIsDark: capturedIsDark,
      );
    } catch (_) {
      return null;
    }
  }

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
  // Dedicated card/button boundaries capture crisp at up to 2.5x DPR (~0.5 MB).
  // Larger ancestor layers cap max dimension to 1080px to bound GPU VRAM.
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

  final GlobalKey _pageBoundaryKey = GlobalKey();
  final ValueNotifier<int> _snapshotRevision = ValueNotifier<int>(0);

  TempoMorphCardSnapshot? _sourceSnapshot;
  TempoMorphCardSnapshot? _pageSnapshot;
  Rect? _cachedCloseRect;
  Rect? _lastMorphRect;
  bool _capturedCloseRect = false;
  bool _scheduledCloseRecapture = false;
  bool _scheduledPageSnapshotRetry = false;
  bool _attachedStatusListener = false;
  bool _routeDisposed = false;

  /// Exposes the most recently painted morph container rect for geometry tests.
  @visibleForTesting
  Rect? get debugLastMorphRect => _lastMorphRect;

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

  /// True for both circular glass header buttons (`sourceBorderRadius >= 999`)
  /// and compact square/squircle app-icon launchers (e.g. Workout HIIT Burn /
  /// Strength / Cardio / Endurance / Mobility `56×56` squircles) so they share
  /// zero-ghosting anchor suppression and HyperOS 4 decoupled icon physics.
  bool get _isCompactIconKeySource {
    if (sourceKey == null) return false;
    final r = initialSourceRect;
    if (r == null) return sourceBorderRadius >= 999.0;
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
      TempoAnimationSpeedService.instance.scale(const Duration(milliseconds: 460));

  @override
  Duration get reverseTransitionDuration => TempoAnimationSpeedService.instance
      .scale(Duration(milliseconds: _isCompactIconKeySource ? 540 : 470));

  void _syncAnchorSuppression(bool hideAnchor) {
    final key = sourceKey;
    if (key == null || !_isCompactIconKeySource) return;
    if (hideAnchor) {
      _activeMorphRouteByKey[key] = this;
      if (!identical(activeTempoMorphAnchorKey.value, key)) {
        activeTempoMorphAnchorKey.value = key;
      }
    } else if (identical(_activeMorphRouteByKey[key], this)) {
      _activeMorphRouteByKey.remove(key);
      if (identical(activeTempoMorphAnchorKey.value, key)) {
        activeTempoMorphAnchorKey.value = null;
      }
    }
  }

  bool get _supersededByNewerRoute {
    final key = sourceKey;
    if (key == null || !_isCompactIconKeySource) return false;
    final owner = _activeMorphRouteByKey[key];
    return owner != null && !identical(owner, this);
  }

  @override
  Widget buildModalBarrier() {
    final anim = animation;
    if (anim == null) return const SizedBox.shrink();
    return AnimatedBuilder(
      animation: anim,
      builder: (context, _) {
        // Release the full-screen modal barrier the instant close begins so
        // buttons & cards underneath respond on the very first tap (0 ms delay).
        if (anim.status == AnimationStatus.reverse ||
            anim.status == AnimationStatus.dismissed) {
          return const SizedBox.shrink();
        }
        return super.buildModalBarrier();
      },
    );
  }

  void _handleRouteStatus(AnimationStatus status) {
    if (_routeDisposed) return;
    final flying = status == AnimationStatus.forward ||
        status == AnimationStatus.reverse;
    _syncAnchorSuppression(flying);
    if (status == AnimationStatus.reverse) {
      _ensurePageSnapshotCaptured();
    }
  }

  /// Synchronously snapshots the settled destination page's cached GPU layer
  /// (`RenderRepaintBoundary.toImageSync`) in `< 0.5 ms` so closing never has
  /// to rasterize live `BackdropFilter`, `CustomScrollView`, or `CustomPaint`
  /// widgets at 120Hz.
  bool _capturePageSnapshot() {
    if (_routeDisposed) return false;
    if (_pageSnapshot != null && _pageSnapshot!.isUsable) return true;
    final boundaryCtx = _pageBoundaryKey.currentContext;
    if (boundaryCtx == null || !boundaryCtx.mounted) return false;
    final renderObj = boundaryCtx.findRenderObject();
    if (renderObj is! RenderRepaintBoundary ||
        !renderObj.attached ||
        !renderObj.hasSize) {
      return false;
    }

    var needsPaint = false;
    assert(() {
      needsPaint = renderObj.debugNeedsPaint;
      return true;
    }());
    if (needsPaint) return false;

    final size = renderObj.size;
    if (size.width <= 1 || size.height <= 1) return false;

    final viewDpr = View.maybeOf(boundaryCtx)?.devicePixelRatio ?? 2.0;
    final maxDim = math.max(size.width, size.height);
    // Cap longest edge to 1080px (~2-3 MB GPU texture, razor-sharp while shrinking).
    final captureDpr =
        math.min(viewDpr.clamp(1.0, 2.25), 1080.0 / maxDim).clamp(0.75, 2.25);

    ui.Image image;
    try {
      image = renderObj.toImageSync(pixelRatio: captureDpr);
    } catch (_) {
      return false;
    }

    final imgW = image.width.toDouble();
    final imgH = image.height.toDouble();
    if (imgW < 2 || imgH < 2) {
      image.dispose();
      return false;
    }

    var capturedIsDark = false;
    try {
      capturedIsDark = AppColors.of(boundaryCtx, listen: false).isDark;
    } catch (_) {
      capturedIsDark = Theme.of(boundaryCtx).brightness == Brightness.dark;
    }

    _pageSnapshot = TempoMorphCardSnapshot(
      image: image,
      srcRect: Rect.fromLTWH(0, 0, imgW, imgH),
      logicalSize: size,
      capturedIsDark: capturedIsDark,
    );
    return true;
  }

  void _ensurePageSnapshotCaptured() {
    if (_routeDisposed) return;
    if (_capturePageSnapshot()) return;
    if (_scheduledPageSnapshotRetry) return;
    _scheduledPageSnapshotRetry = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_routeDisposed) return;
      if (_capturePageSnapshot()) {
        _snapshotRevision.value++;
      }
    });
  }

  @override
  void install() {
    super.install();
    if (!_attachedStatusListener && animation != null) {
      _attachedStatusListener = true;
      animation!.addStatusListener(_handleRouteStatus);
      if (_isCompactIconKeySource) {
        _syncAnchorSuppression(true);
      }
    }
  }

  @override
  bool didPop(T? result) {
    // Freeze the settled destination page into a GPU texture synchronously
    // BEFORE Frame 0 of the reverse animation starts!
    _ensurePageSnapshotCaptured();
    if (_isCompactIconKeySource) {
      _syncAnchorSuppression(true);
    }
    return super.didPop(result);
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
    _pageSnapshot?.dispose();
    _pageSnapshot = null;
    _snapshotRevision.dispose();
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
        _isCompactIconKeySource) {
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
      // Notify only the CustomPainter — zero overlay/widget tree rebuild!
      _snapshotRevision.value++;
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

  /// Evaluates the exact morph geometry, alpha, and blur state at any tick
  /// [rawT] using mathematically smooth `TempoSpringCurves` (zero vertical
  /// velocity cliffs, zero black bezel, monotonic bell-curve deceleration).
  _MorphFrameGeometry _computeGeometry({
    required Size screen,
    required double rawT,
    required bool isClosing,
    required bool isDark,
    required bool hasSourceSnapshot,
  }) {
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
    final isAppIconOrigin = !isCircularOrigin &&
        (sourceRect.width - sourceRect.height).abs() <= 10.0 &&
        sourceRect.width <= 84.0 &&
        sourceBorderRadius >= 10.0;
    final isCompactIconOrigin = isCircularOrigin || isAppIconOrigin;

    final Rect curRect;
    final double curRadius;
    final double effectiveFlightT;

    if (isCompactIconOrigin) {
      final sourceSize = math.max(sourceRect.width, sourceRect.height);
      final targetCornerRatio = isCircularOrigin
          ? 0.5
          : (startRadius / math.max(1.0, sourceSize)).clamp(0.16, 0.5);
      if (isClosing) {
        final closeP = (1.0 - rawT).clamp(0.0, 1.0);
        final szRaw = TempoSpringCurves.dropletCloseSize.transform(closeP);
        final ctRaw = TempoSpringCurves.dropletCloseCenter.transform(closeP);

        // Phase 1 (approach): collapse smoothly from screen -> 1:1 circle/squircle.
        // Phase 2 (dock bounce): C1-continuous elastic squish gliding slowly and
        // smoothly back to exact resting 1:1 dimensions!
        final approachRemain =
            closeP < 0.48 ? (1.0 - szRaw).clamp(0.0, 1.0) : 0.0;
        final dockDelta =
            closeP >= 0.48 ? (1.0 - szRaw) : math.min(0.0, 1.0 - szRaw);
        final elasticScale = (1.0 + dockDelta * 1.10).clamp(0.88, 1.05);

        final wRem = math.pow(approachRemain, 1.02).toDouble();
        final hRem = math.pow(approachRemain, 1.38).toDouble();
        double curW = ui.lerpDouble(sourceSize, fullRect.width, wRem)!;
        double curH = math.max(
          curW,
          ui.lerpDouble(sourceSize, fullRect.height, hRem)!,
        );
        final circleU = ((closeP - 0.24) / 0.26).clamp(0.0, 1.0);
        final circleBlend = circleU * circleU * (3.0 - 2.0 * circleU);
        final targetD = math.min(curW, curH);
        curW = ui.lerpDouble(curW, targetD, circleBlend)! * elasticScale;
        curH = ui.lerpDouble(curH, targetD, circleBlend)! * elasticScale;

        // Positional spring overshoot proportional to approach direction (smooth
        // ~3.8px parabolic dock cushion with zero flat clamping or edge clip).
        final travel = fullRect.center - sourceRect.center;
        final dist = travel.distance;
        final Offset curCenter;
        if (ctRaw <= 1.0 && closeP < 0.54) {
          curCenter = Offset.lerp(
            sourceRect.center,
            fullRect.center,
            (1.0 - ctRaw).clamp(0.0, 1.0),
          )!;
        } else {
          final dir = dist > 0.1 ? travel / dist : Offset.zero;
          final overshootScale = math.min(dist, 54.0);
          curCenter = sourceRect.center + dir * ((1.0 - ctRaw) * overshootScale);
        }

        curRect = Rect.fromCenter(center: curCenter, width: curW, height: curH);

        final maxCurRadius = math.min(curW, curH) / 2.0;
        final targetRadius = math.min(curW, curH) * targetCornerRatio;
        final radBlend = math.pow(approachRemain, 2.2).toDouble();
        curRadius = (targetRadius * (1.0 - radBlend)).clamp(0.0, maxCurRadius);
        effectiveFlightT = (1.0 - ctRaw).clamp(0.0, 1.0);
      } else {
        final sizeT =
            TempoSpringCurves.dropletOpenSize.transform(rawT).clamp(0.0, 1.0);
        final centerT =
            TempoSpringCurves.dropletOpenCenter.transform(rawT).clamp(0.0, 1.0);

        final wT = math.pow(sizeT, 0.96).toDouble();
        final hT = math.pow(sizeT, 1.28).toDouble();
        double curW = ui.lerpDouble(sourceSize, fullRect.width, wT)!;
        double curH = math.max(
          curW,
          ui.lerpDouble(sourceSize, fullRect.height, hT)!,
        );
        final holdU = (1.0 - (rawT / 0.34).clamp(0.0, 1.0));
        final circleHold = holdU * holdU * (3.0 - 2.0 * holdU);
        final targetD = math.min(curW, curH);
        curW = ui.lerpDouble(curW, targetD, circleHold)!;
        curH = ui.lerpDouble(curH, targetD, circleHold)!;

        final curCenter =
            Offset.lerp(sourceRect.center, fullRect.center, centerT)!;
        curRect = Rect.fromCenter(center: curCenter, width: curW, height: curH);

        final maxCurRadius = math.min(curW, curH) / 2.0;
        final targetRadius = math.min(curW, curH) * targetCornerRatio;
        final radBlend = math.pow(sizeT, 2.2).toDouble();
        curRadius = (targetRadius * (1.0 - radBlend)).clamp(0.0, maxCurRadius);
        effectiveFlightT = sizeT;
      }
    } else {
      if (isClosing) {
        final closeP = (1.0 - rawT).clamp(0.0, 1.0);
        final closeRaw = TempoSpringCurves.morphClose.transform(closeP);
        final morphT = (1.0 - closeRaw).clamp(0.0, 1.0);
        final baseRect = Rect.lerp(sourceRect, fullRect, morphT)!;
        // Subtle tactile card dock cushion (~2.2% elastic settle into card slot).
        final dockDelta = math.min(0.0, 1.0 - closeRaw);
        final cardScale = (1.0 + dockDelta * 0.45).clamp(0.96, 1.02);
        curRect = Rect.fromCenter(
          center: baseRect.center,
          width: baseRect.width * cardScale,
          height: baseRect.height * cardScale,
        );
        final maxCurRadius = math.min(curRect.width, curRect.height) / 2.0;
        final radBlend = math.pow(morphT, 2.0).toDouble();
        curRadius =
            ui.lerpDouble(startRadius, 0.0, radBlend)!.clamp(0.0, maxCurRadius);
        effectiveFlightT = morphT;
      } else {
        final morphT =
            TempoSpringCurves.morphOpen.transform(rawT).clamp(0.0, 1.0);
        curRect = Rect.lerp(sourceRect, fullRect, morphT)!;
        final maxCurRadius = math.min(curRect.width, curRect.height) / 2.0;
        final radBlend = math.pow(morphT, 2.0).toDouble();
        curRadius =
            ui.lerpDouble(startRadius, 0.0, radBlend)!.clamp(0.0, maxCurRadius);
        effectiveFlightT = morphT;
      }
    }

    final double cardLayerAlpha;
    final double containerAlpha;
    final double snapshotBlurSigma;

    if (isClosing) {
      final closeP = (1.0 - rawT).clamp(0.0, 1.0);
      if (isCompactIconOrigin) {
        // Cross-dissolve smoothly from page snapshot into circular glass button
        // or squircle app icon right as it converges to 1:1 (~closeP = 0.34),
        // so the crisp icon glides and cushions smoothly into its empty slot.
        cardLayerAlpha = Curves.easeInOutCubic
            .transform(((closeP - 0.08) / 0.28).clamp(0.0, 1.0));
        containerAlpha = 1.0;
        // Subtle 120Hz-safe sharpen ONLY once icon is compact (< 115dp).
        final sharpP = ((closeP - 0.30) / 0.24).clamp(0.0, 1.0);
        final rawSigma = hasSourceSnapshot && curRect.width < 115.0
            ? (isCircularOrigin ? 3.0 : 2.0) *
                (1.0 - Curves.easeOutCubic.transform(sharpP))
            : 0.0;
        snapshotBlurSigma = (rawSigma * 2.0).round() / 2.0;
      } else {
        cardLayerAlpha = Curves.easeInOutCubic
            .transform(((closeP - 0.10) / 0.38).clamp(0.0, 1.0));
        snapshotBlurSigma = 0.0;
        if (cardLayerAlpha < 0.995) {
          containerAlpha = 1.0;
        } else if (hasSourceSnapshot) {
          containerAlpha = (1.0 -
                  Curves.easeOutCubic
                      .transform(((closeP - 0.90) / 0.10).clamp(0.0, 1.0)))
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
                  .transform(((rawT - 0.05) / 0.32).clamp(0.0, 1.0)))
          .clamp(0.0, 1.0);
      containerAlpha = 1.0;
      final rawSigma = isCompactIconOrigin &&
              hasSourceSnapshot &&
              curRect.width < 115.0
          ? (isCircularOrigin ? 3.0 : 2.0) *
              Curves.easeInQuad
                  .transform(((rawT - 0.04) / 0.28).clamp(0.0, 1.0))
          : 0.0;
      snapshotBlurSigma = (rawSigma * 2.0).round() / 2.0;
    }

    final scrimAlpha =
        (isDark ? 0.32 : 0.14) * effectiveFlightT * containerAlpha;
    final flightArc = math.sin(effectiveFlightT * math.pi).clamp(0.0, 1.0);
    final rectInset = math.min(
      math.min(curRect.left, screen.width - curRect.right),
      math.min(curRect.top, screen.height - curRect.bottom),
    );
    // Skip shadow draw when container fills the viewport (shadow lies offscreen).
    final shadowAlpha = rectInset > 2.0
        ? (isDark ? 0.24 : 0.10) * flightArc * containerAlpha
        : 0.0;

    return _MorphFrameGeometry(
      fullRect: fullRect,
      sourceRect: sourceRect,
      curRect: curRect,
      curRadius: curRadius,
      startRadius: startRadius,
      isCircularOrigin: isCircularOrigin,
      isCompactIconOrigin: isCompactIconOrigin,
      effectiveFlightT: effectiveFlightT,
      cardLayerAlpha: cardLayerAlpha,
      containerAlpha: containerAlpha,
      snapshotBlurSigma: snapshotBlurSigma,
      scrimAlpha: scrimAlpha,
      flightArc: flightArc,
      shadowAlpha: shadowAlpha,
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

    final c = AppColors.of(context);
    final screen = MediaQuery.sizeOf(context);
    final rawT = animation.value.clamp(0.0, 1.0);
    final isSettled = rawT >= 0.999 &&
        (animation.status == AnimationStatus.completed ||
            animation.status == AnimationStatus.forward);

    final isClosing = animation.status == AnimationStatus.reverse ||
        animation.status == AnimationStatus.dismissed;

    // If the user rapidly re-tapped the same anchor button while this route is
    // still finishing its close bounce, yield the visual immediately so the new
    // opening route launches cleanly with zero double-droplet overlap!
    if (isClosing && _supersededByNewerRoute) {
      return Stack(
        fit: StackFit.expand,
        children: [
          const IgnorePointer(
            key: ValueKey<String>('tempo_morph_backdrop'),
            child: CustomPaint(painter: null),
          ),
          ClipRRect(
            key: const ValueKey<String>('tempo_morph_live_page'),
            clipBehavior: Clip.none,
            child: Transform(
              transform: Matrix4.identity(),
              child: IgnorePointer(
                ignoring: true,
                child: Offstage(
                  offstage: true,
                  child: RepaintBoundary(
                    key: _pageBoundaryKey,
                    child: child,
                  ),
                ),
              ),
            ),
          ),
          const IgnorePointer(
            key: ValueKey<String>('tempo_morph_overlay'),
            child: CustomPaint(painter: null),
          ),
        ],
      );
    }

    if (isClosing) {
      _ensurePageSnapshotCaptured();
      _scheduleFreshCloseSnapshot();
    }

    final activeSourceSnapshot = (_sourceSnapshot != null &&
            _sourceSnapshot!.isUsable &&
            _sourceSnapshot!.capturedIsDark == c.isDark)
        ? _sourceSnapshot
        : null;
    final activePageSnapshot = (_pageSnapshot != null &&
            _pageSnapshot!.isUsable &&
            _pageSnapshot!.capturedIsDark == c.isDark)
        ? _pageSnapshot
        : null;

    final effectiveSourceColor = sourceColor ?? c.card;

    // Option A: Clean Pinned Background — NEVER apply 0.96x secondaryAnimation
    // scale over Flutter's raw #000000 canvas. And ALWAYS return the EXACT SAME
    // keyed 3-slot widget spine (`Stack -> [Backdrop, LivePageSlot, Overlay]`)
    // with constant widget types at every slot so Flutter's Element.updateChildren
    // NEVER deactivates or reparents `child` across Open -> Settled -> Close!
    final _MorphFrameGeometry? geo = isSettled
        ? null
        : _computeGeometry(
            screen: screen,
            rawT: rawT,
            isClosing: isClosing,
            isDark: c.isDark,
            hasSourceSnapshot: activeSourceSnapshot != null,
          );
    _lastMorphRect = geo?.curRect ?? (Offset.zero & screen);

    final useSnapshotCloseFlight =
        !isSettled && isClosing && activePageSnapshot != null;
    final hideLivePage = !isSettled &&
        (useSnapshotCloseFlight ||
            (isClosing && geo!.cardLayerAlpha >= 0.995));
    final clipLivePage = !isSettled && !hideLivePage;

    final Color? surfaceColor = geo == null
        ? null
        : Color.lerp(effectiveSourceColor, c.scaffold, geo.effectiveFlightT)!;

    // Paint-only Matrix4 mapping for live page during Open (and rare fallback close):
    // ZERO Positioned.fromRect / OverflowBox relayout at 120Hz!
    final Matrix4 livePageMatrix;
    if (isSettled || hideLivePage || geo == null) {
      livePageMatrix = Matrix4.identity();
    } else {
      final startScale =
          (geo.sourceRect.width / math.max(1.0, screen.width)).clamp(0.56, 0.94);
      final contentScale =
          ui.lerpDouble(startScale, 1.0, geo.effectiveFlightT)!;
      final tx = geo.curRect.center.dx - (screen.width * 0.5) * contentScale;
      final centeredTy =
          geo.curRect.center.dy - (screen.height * 0.5) * contentScale;
      final topBiasedTy =
          geo.curRect.top - (screen.height * 0.04) * (1.0 - geo.effectiveFlightT);
      final ty = ui.lerpDouble(
        geo.isCompactIconOrigin ? centeredTy : topBiasedTy,
        0.0,
        geo.effectiveFlightT,
      )!;
      livePageMatrix = Matrix4.identity()
        ..translateByDouble(tx, ty, 0.0, 1.0)
        ..scaleByDouble(contentScale, contentScale, 1.0, 1.0);
    }

    final CustomPainter? backdropPainter =
        (isSettled || useSnapshotCloseFlight || geo == null)
            ? null
            : _MorphBackdropPainter(
                geo: geo,
                surfaceColor: surfaceColor!,
                paintCardBase: !hideLivePage,
              );

    final CustomPainter? overlayPainter;
    if (isSettled || geo == null) {
      overlayPainter = null;
    } else if (useSnapshotCloseFlight) {
      overlayPainter = _CloseDualSnapshotPainter(
        geo: geo,
        pageSnapshot: activePageSnapshot,
        sourceSnapshot: activeSourceSnapshot,
        surfaceColor: surfaceColor!,
        effectiveSourceColor: effectiveSourceColor,
        repaint: _snapshotRevision,
      );
    } else if (geo.cardLayerAlpha > 0.004 || hideLivePage) {
      overlayPainter = _SourceSnapshotOverlayPainter(
        geo: geo,
        sourceSnapshot: activeSourceSnapshot,
        effectiveSourceColor: effectiveSourceColor,
        opacity: hideLivePage ? geo.containerAlpha : geo.cardLayerAlpha,
        repaint: _snapshotRevision,
      );
    } else {
      overlayPainter = null;
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        IgnorePointer(
          key: const ValueKey<String>('tempo_morph_backdrop'),
          child: CustomPaint(painter: backdropPainter),
        ),
        ClipRRect(
          key: const ValueKey<String>('tempo_morph_live_page'),
          clipBehavior:
              (clipLivePage && geo != null) ? Clip.antiAlias : Clip.none,
          clipper: (clipLivePage && geo != null)
              ? _MorphRRectClipper(geo.curRect, geo.curRadius)
              : null,
          child: Transform(
            transform: livePageMatrix,
            child: IgnorePointer(
              // Allow immediate back/button taps once open passes 15% (~70ms),
              // while keeping the closing route completely pass-through.
              ignoring: isClosing || (!isSettled && rawT < 0.15),
              child: Offstage(
                offstage: hideLivePage,
                child: RepaintBoundary(
                  key: _pageBoundaryKey,
                  child: child,
                ),
              ),
            ),
          ),
        ),
        IgnorePointer(
          key: const ValueKey<String>('tempo_morph_overlay'),
          child: CustomPaint(painter: overlayPainter),
        ),
      ],
    );
  }
}

class _MorphFrameGeometry {
  final Rect fullRect;
  final Rect sourceRect;
  final Rect curRect;
  final double curRadius;
  final double startRadius;
  final bool isCircularOrigin;
  final bool isCompactIconOrigin;
  final double effectiveFlightT;
  final double cardLayerAlpha;
  final double containerAlpha;
  final double snapshotBlurSigma;
  final double scrimAlpha;
  final double flightArc;
  final double shadowAlpha;

  const _MorphFrameGeometry({
    required this.fullRect,
    required this.sourceRect,
    required this.curRect,
    required this.curRadius,
    required this.startRadius,
    required this.isCircularOrigin,
    required this.isCompactIconOrigin,
    required this.effectiveFlightT,
    required this.cardLayerAlpha,
    required this.containerAlpha,
    required this.snapshotBlurSigma,
    required this.scrimAlpha,
    required this.flightArc,
    required this.shadowAlpha,
  });
}

/// Paint-only [CustomClipper] that clips the full-screen `RepaintBoundary` to
/// the morphing container without triggering any `Stack`/`Positioned` relayout.
class _MorphRRectClipper extends CustomClipper<RRect> {
  final Rect rect;
  final double radius;

  const _MorphRRectClipper(this.rect, this.radius);

  @override
  RRect getClip(Size size) {
    return RRect.fromRectAndRadius(rect, Radius.circular(radius));
  }

  @override
  bool shouldReclip(covariant _MorphRRectClipper oldClipper) {
    return oldClipper.rect != rect || oldClipper.radius != radius;
  }
}

/// Paints the airy dim scrim, constant-sigma diffused shadow, and opaque base
/// rect behind the live page during Open (1 single paint pass, zero layout).
class _MorphBackdropPainter extends CustomPainter {
  final _MorphFrameGeometry geo;
  final Color surfaceColor;
  final bool paintCardBase;

  static final ui.MaskFilter _shadowBlur =
      const ui.MaskFilter.blur(BlurStyle.normal, 14.0);

  const _MorphBackdropPainter({
    required this.geo,
    required this.surfaceColor,
    required this.paintCardBase,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (geo.scrimAlpha > 0.004) {
      canvas.drawRect(
        Offset.zero & size,
        Paint()..color = Colors.black.withValues(alpha: geo.scrimAlpha),
      );
    }

    final rrect = RRect.fromRectAndRadius(
      geo.curRect,
      Radius.circular(geo.curRadius),
    );

    if (geo.shadowAlpha > 0.004) {
      final shadowRRect = rrect.shift(Offset(0, 6.0 * geo.flightArc + 2.0));
      canvas.drawRRect(
        shadowRRect,
        Paint()
          ..color = Colors.black.withValues(alpha: geo.shadowAlpha)
          ..maskFilter = _shadowBlur,
      );
    }

    if (paintCardBase) {
      canvas.drawRRect(
        rrect,
        Paint()..color = surfaceColor,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _MorphBackdropPainter oldDelegate) {
    return oldDelegate.geo.curRect != geo.curRect ||
        oldDelegate.geo.curRadius != geo.curRadius ||
        oldDelegate.geo.scrimAlpha != geo.scrimAlpha ||
        oldDelegate.geo.shadowAlpha != geo.shadowAlpha ||
        oldDelegate.surfaceColor != surfaceColor ||
        oldDelegate.paintCardBase != paintCardBase;
  }
}

/// Single-pass 120Hz Canvas painter for the entire closing transition:
/// draws airy scrim + constant-sigma shadow + clipped aspect-preserving
/// `_pageSnapshot` cross-morphing seamlessly into `_sourceSnapshot`.
class _CloseDualSnapshotPainter extends CustomPainter {
  final _MorphFrameGeometry geo;
  final TempoMorphCardSnapshot pageSnapshot;
  final TempoMorphCardSnapshot? sourceSnapshot;
  final Color surfaceColor;
  final Color effectiveSourceColor;

  static final ui.MaskFilter _shadowBlur =
      const ui.MaskFilter.blur(BlurStyle.normal, 14.0);

  const _CloseDualSnapshotPainter({
    required this.geo,
    required this.pageSnapshot,
    required this.sourceSnapshot,
    required this.surfaceColor,
    required this.effectiveSourceColor,
    super.repaint,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Airy depth scrim behind the shrinking container.
    if (geo.scrimAlpha > 0.004) {
      canvas.drawRect(
        Offset.zero & size,
        Paint()..color = Colors.black.withValues(alpha: geo.scrimAlpha),
      );
    }

    if (geo.containerAlpha <= 0.004) return;

    final rrect = RRect.fromRectAndRadius(
      geo.curRect,
      Radius.circular(geo.curRadius),
    );

    // 2. Soft diffused elevation shadow (constant sigma keeps Impeller cache hot).
    if (geo.shadowAlpha > 0.004) {
      final shadowRRect = rrect.shift(Offset(0, 6.0 * geo.flightArc + 2.0));
      canvas.drawRRect(
        shadowRRect,
        Paint()
          ..color = Colors.black.withValues(alpha: geo.shadowAlpha)
          ..maskFilter = _shadowBlur,
      );
    }

    // 3. Clipped container interior: base -> pageSnapshot -> sourceSnapshot.
    canvas.save();
    canvas.clipRRect(rrect);

    final showPage = geo.cardLayerAlpha < 0.995 && pageSnapshot.isUsable;
    if (showPage) {
      canvas.drawRect(
        geo.curRect,
        Paint()..color = surfaceColor.withValues(alpha: geo.containerAlpha),
      );

      // Aspect-preserving BoxFit.cover mapping eliminates the blank status-bar
      // forehead while guaranteeing a 100% pixel-exact 1:1 match at closeP = 0!
      final fitted = applyBoxFit(
        BoxFit.cover,
        pageSnapshot.logicalSize,
        geo.curRect.size,
      );
      final srcScaleX =
          pageSnapshot.srcRect.width / math.max(1.0, pageSnapshot.logicalSize.width);
      final srcScaleY =
          pageSnapshot.srcRect.height / math.max(1.0, pageSnapshot.logicalSize.height);
      final alignY = geo.isCompactIconOrigin ? -0.35 : -0.55;
      final logicalCrop = Alignment(0.0, alignY).inscribe(
        fitted.source,
        Offset.zero & pageSnapshot.logicalSize,
      );
      final imageSrc = Rect.fromLTWH(
        pageSnapshot.srcRect.left + logicalCrop.left * srcScaleX,
        pageSnapshot.srcRect.top + logicalCrop.top * srcScaleY,
        logicalCrop.width * srcScaleX,
        logicalCrop.height * srcScaleY,
      );

      final pageAlpha = geo.isCompactIconOrigin
          ? ((1.0 - geo.cardLayerAlpha * 0.85) * geo.containerAlpha)
              .clamp(0.0, 1.0)
          : geo.containerAlpha;

      canvas.drawImageRect(
        pageSnapshot.image,
        imageSrc,
        geo.curRect,
        Paint()
          ..color = Color.fromRGBO(255, 255, 255, pageAlpha)
          ..filterQuality = FilterQuality.medium,
      );
    }

    final sourceAlpha =
        showPage ? geo.cardLayerAlpha * geo.containerAlpha : geo.containerAlpha;
    if (sourceAlpha > 0.004) {
      _paintSourceSnapshotInsideRect(
        canvas: canvas,
        targetRect: geo.curRect,
        snapshot: sourceSnapshot,
        backgroundColor: effectiveSourceColor,
        sourceBorderRadius: geo.startRadius,
        isCircularFill: geo.isCircularOrigin,
        isIconFill: geo.isCompactIconOrigin,
        opacity: sourceAlpha,
        morphT: geo.effectiveFlightT,
        blurSigma: geo.snapshotBlurSigma,
      );
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _CloseDualSnapshotPainter oldDelegate) {
    return oldDelegate.geo.curRect != geo.curRect ||
        oldDelegate.geo.curRadius != geo.curRadius ||
        oldDelegate.geo.cardLayerAlpha != geo.cardLayerAlpha ||
        oldDelegate.geo.containerAlpha != geo.containerAlpha ||
        oldDelegate.geo.scrimAlpha != geo.scrimAlpha ||
        oldDelegate.geo.shadowAlpha != geo.shadowAlpha ||
        oldDelegate.geo.snapshotBlurSigma != geo.snapshotBlurSigma ||
        !identical(oldDelegate.pageSnapshot, pageSnapshot) ||
        !identical(oldDelegate.sourceSnapshot, sourceSnapshot);
  }
}

/// Paints the captured card/button snapshot clipped inside [geo.curRect] during
/// Open (and rare no-page-snapshot close fallback) with zero `Stack` relayout.
class _SourceSnapshotOverlayPainter extends CustomPainter {
  final _MorphFrameGeometry geo;
  final TempoMorphCardSnapshot? sourceSnapshot;
  final Color effectiveSourceColor;
  final double opacity;

  const _SourceSnapshotOverlayPainter({
    required this.geo,
    required this.sourceSnapshot,
    required this.effectiveSourceColor,
    required this.opacity,
    super.repaint,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (opacity <= 0.004) return;
    final rrect = RRect.fromRectAndRadius(
      geo.curRect,
      Radius.circular(geo.curRadius),
    );
    canvas.save();
    canvas.clipRRect(rrect);
    _paintSourceSnapshotInsideRect(
      canvas: canvas,
      targetRect: geo.curRect,
      snapshot: sourceSnapshot,
      backgroundColor: effectiveSourceColor,
      sourceBorderRadius: geo.startRadius,
      isCircularFill: geo.isCircularOrigin,
      isIconFill: geo.isCompactIconOrigin,
      opacity: opacity,
      morphT: geo.effectiveFlightT,
      blurSigma: geo.snapshotBlurSigma,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SourceSnapshotOverlayPainter oldDelegate) {
    return oldDelegate.geo.curRect != geo.curRect ||
        oldDelegate.geo.curRadius != geo.curRadius ||
        oldDelegate.opacity != opacity ||
        oldDelegate.geo.snapshotBlurSigma != geo.snapshotBlurSigma ||
        !identical(oldDelegate.sourceSnapshot, sourceSnapshot);
  }
}

/// Shared zero-`saveLayer` GPU snapshot renderer for both circular droplets
/// and rectangular cards, with optional small-target quantized blur.
void _paintSourceSnapshotInsideRect({
  required Canvas canvas,
  required Rect targetRect,
  required TempoMorphCardSnapshot? snapshot,
  required Color backgroundColor,
  required double sourceBorderRadius,
  required bool isCircularFill,
  required bool isIconFill,
  required double opacity,
  required double morphT,
  required double blurSigma,
}) {
  if (opacity <= 0.004) return;

  if (snapshot == null || !snapshot.isUsable) {
    canvas.drawRect(
      targetRect,
      Paint()..color = backgroundColor.withValues(alpha: opacity),
    );
    return;
  }

  // Seamless card/button background fill behind the snapshot so extra height
  // during flight blends cleanly with zero seam.
  canvas.drawRect(
    targetRect,
    Paint()..color = backgroundColor.withValues(alpha: opacity),
  );

  final srcW = snapshot.logicalSize.width;
  final srcH = snapshot.logicalSize.height;
  if (srcW <= 1 || srcH <= 1) return;

  final isCompactControl = srcW < 88 || srcH < 64;
  final Rect dstRect;
  final double scaledRadius;

  if (isIconFill) {
    // Fill circular buttons and squircle app icons (e.g. Workout HIIT Burn)
    // proportionally 1:1 inside the morphing square so the icon never shrinks
    // or sits tiny inside a giant colored box.
    final diameter = math.min(targetRect.width, targetRect.height);
    dstRect = Rect.fromCenter(
      center: targetRect.center,
      width: diameter,
      height: diameter,
    );
    scaledRadius = isCircularFill
        ? diameter / 2.0
        : (diameter * (sourceBorderRadius / math.max(1.0, srcW)))
            .clamp(0.0, diameter / 2.0);
  } else if (isCompactControl) {
    final scale = ui.lerpDouble(1.0, 1.28, morphT)!.clamp(1.0, 1.28);
    final w = math.min(targetRect.width, srcW * scale);
    final h = math.min(targetRect.height, srcH * scale);
    dstRect = Rect.fromCenter(center: targetRect.center, width: w, height: h);
    scaledRadius =
        (sourceBorderRadius * (w / srcW)).clamp(0.0, math.min(w, h) / 2.0);
  } else {
    final scale = (targetRect.width / srcW).clamp(0.5, 3.0);
    final dstW = targetRect.width;
    final dstH = srcH * scale;
    dstRect = Rect.fromLTWH(targetRect.left, targetRect.top, dstW, dstH);
    scaledRadius = (sourceBorderRadius * scale)
        .clamp(0.0, math.min(dstW, dstH) / 2.0);
  }

  final paint = Paint()
    ..color = Color.fromRGBO(255, 255, 255, opacity)
    ..filterQuality = FilterQuality.medium;
  if (blurSigma >= 0.5) {
    paint.imageFilter = ui.ImageFilter.blur(
      sigmaX: blurSigma,
      sigmaY: blurSigma,
    );
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
    paint,
  );
  canvas.restore();
}
