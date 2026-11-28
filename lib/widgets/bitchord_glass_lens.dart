import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Immutable per-frame lens parameters consumed by [BitChordGlassLensBox] right
/// inside `RenderProxyBox.paint()` with 0 widget rebuilds and 0 shader allocations.
@immutable
class BitChordLensFrame {
  final bool active;
  final Rect rect;
  final double borderRadius;
  final double refractionHeightDp;
  final double refractionAmountDp;
  final double depthEffect;
  final double aberration;
  final double rimAlpha;
  final double shadowAlpha;
  final double material;

  const BitChordLensFrame({
    required this.active,
    required this.rect,
    required this.borderRadius,
    required this.refractionHeightDp,
    required this.refractionAmountDp,
    this.depthEffect = 0.45,
    this.aberration = 1.0,
    required this.rimAlpha,
    required this.shadowAlpha,
    required this.material,
  });

  static const BitChordLensFrame inactive = BitChordLensFrame(
    active: false,
    rect: Rect.zero,
    borderRadius: 0.0,
    refractionHeightDp: 0.0,
    refractionAmountDp: 0.0,
    rimAlpha: 0.0,
    shadowAlpha: 0.0,
    material: 0.0,
  );
}

/// Shared zero-allocation, zero-rebuild Impeller GPU Liquid Glass lens layer
/// powered by `shaders/liquid_glass_lens.frag` (BitChord / Kyant0 hemispherical
/// dome refraction + 7-band chromatic rainbow dispersion + 45° specular rim).
///
/// Reused across:
/// - `LiquidGlassNavBar` (lifted tab droplet)
/// - `WorkoutProgramCard` `_InlineDifficultySwitcher` (`Easy | Med | Hard` glass pill)
/// - `ReorderableSummaryGrid` (lifted dragged Summary cards refracting cards behind)
///
/// When [frameBuilder] returns `active: false`, the underlying `BackdropFilterLayer`
/// is detached immediately (`0%` GPU cost at rest).
class BitChordGlassLensBox extends SingleChildRenderObjectWidget {
  final ui.FragmentProgram? program;
  final Listenable? repaint;
  final BitChordLensFrame Function(Size size) frameBuilder;
  final bool isDark;
  final double dpr;
  final bool useRefractionShader;

  const BitChordGlassLensBox({
    super.key,
    required this.program,
    this.repaint,
    required this.frameBuilder,
    required this.isDark,
    required this.dpr,
    required this.useRefractionShader,
    super.child,
  });

  @override
  RenderBitChordGlassLens createRenderObject(BuildContext context) {
    return RenderBitChordGlassLens(
      program: program,
      repaint: repaint,
      frameBuilder: frameBuilder,
      isDark: isDark,
      dpr: dpr,
      useRefractionShader: useRefractionShader,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderBitChordGlassLens renderObject,
  ) {
    renderObject
      ..program = program
      ..repaint = repaint
      ..frameBuilder = frameBuilder
      ..isDark = isDark
      ..dpr = dpr
      ..useRefractionShader = useRefractionShader;
  }
}

class RenderBitChordGlassLens extends RenderProxyBox {
  ui.FragmentProgram? _program;
  ui.FragmentShader? _shader;
  final LayerHandle<BackdropFilterLayer> _backdropHandle =
      LayerHandle<BackdropFilterLayer>();

  Listenable? _repaint;
  BitChordLensFrame Function(Size size) _frameBuilder;
  bool _isDark;
  double _dpr;
  bool _useRefractionShader;

  RenderBitChordGlassLens({
    required ui.FragmentProgram? program,
    required Listenable? repaint,
    required BitChordLensFrame Function(Size size) frameBuilder,
    required bool isDark,
    required double dpr,
    required bool useRefractionShader,
  })  : _program = program,
        _repaint = repaint,
        _frameBuilder = frameBuilder,
        _isDark = isDark,
        _dpr = dpr,
        _useRefractionShader = useRefractionShader;

  bool get _canRunGpuShader =>
      _useRefractionShader &&
      _program != null &&
      ui.ImageFilter.isShaderFilterSupported;

  @override
  bool get alwaysNeedsCompositing => _canRunGpuShader;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _repaint?.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _repaint?.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  void dispose() {
    _backdropHandle.layer = null;
    _shader?.dispose();
    _shader = null;
    super.dispose();
  }

  set program(ui.FragmentProgram? value) {
    if (identical(_program, value)) return;
    final wasCompositing = _canRunGpuShader;
    _program = value;
    _shader?.dispose();
    _shader = null;
    if (wasCompositing != _canRunGpuShader) markNeedsCompositingBitsUpdate();
    markNeedsPaint();
  }

  set repaint(Listenable? value) {
    if (identical(_repaint, value)) return;
    if (attached) _repaint?.removeListener(markNeedsPaint);
    _repaint = value;
    if (attached) _repaint?.addListener(markNeedsPaint);
    markNeedsPaint();
  }

  set frameBuilder(BitChordLensFrame Function(Size size) value) {
    _frameBuilder = value;
    markNeedsPaint();
  }

  set isDark(bool value) {
    if (_isDark == value) return;
    _isDark = value;
    markNeedsPaint();
  }

  set dpr(double value) {
    if (_dpr == value) return;
    _dpr = value;
    markNeedsPaint();
  }

  set useRefractionShader(bool value) {
    if (_useRefractionShader == value) return;
    final wasCompositing = _canRunGpuShader;
    _useRefractionShader = value;
    if (wasCompositing != _canRunGpuShader) markNeedsCompositingBitsUpdate();
    markNeedsPaint();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final frame = _frameBuilder(size);
    if (!frame.active ||
        frame.rect.isEmpty ||
        (frame.refractionHeightDp <= 0.04 &&
            frame.rimAlpha <= 0.004 &&
            frame.shadowAlpha <= 0.004)) {
      _backdropHandle.layer = null;
      layer = null;
      super.paint(context, offset);
      return;
    }

    final localRect = frame.rect;
    final clampedRadius = math.min(
      frame.borderRadius,
      localRect.shortestSide * 0.5,
    );

    if (_canRunGpuShader) {
      _shader ??= _program!.fragmentShader();
      final shader = _shader!;
      final matrix = getTransformTo(null);
      final globalRect = MatrixUtils.transformRect(matrix, localRect);
      final scale = localRect.height > 0
          ? globalRect.height / localRect.height
          : 1.0;
      final pxScale = _dpr * scale;

      // Indices 0 & 1 are u_size (populated automatically by Impeller)
      shader.setFloat(2, globalRect.center.dx * _dpr);
      shader.setFloat(3, globalRect.center.dy * _dpr);
      shader.setFloat(4, (globalRect.width * 0.5) * _dpr);
      shader.setFloat(5, (globalRect.height * 0.5) * _dpr);
      shader.setFloat(6, clampedRadius * pxScale);
      shader.setFloat(7, frame.refractionHeightDp * pxScale);
      shader.setFloat(8, frame.refractionAmountDp * pxScale);
      shader.setFloat(9, frame.depthEffect);
      shader.setFloat(10, frame.aberration);
      shader.setFloat(11, frame.rimAlpha.clamp(0.0, 1.0));
      shader.setFloat(12, frame.shadowAlpha.clamp(0.0, 1.0));
      shader.setFloat(13, _isDark ? 1.0 : 0.0);
      shader.setFloat(14, frame.material.clamp(0.0, 1.0));

      final shadowMargin =
          (frame.refractionHeightDp * 1.9 + 10.0).clamp(16.0, 46.0);
      final clipRect = localRect.inflate(shadowMargin);

      layer = context.pushClipRect(
        needsCompositing,
        offset,
        clipRect,
        (innerCtx, innerOffset) {
          final bLayer = _backdropHandle.layer ?? BackdropFilterLayer();
          bLayer
            ..filter = ui.ImageFilter.shader(shader)
            ..blendMode = BlendMode.srcOver;
          _backdropHandle.layer = bLayer;
          innerCtx.pushLayer(bLayer, super.paint, innerOffset);
        },
        oldLayer: layer as ClipRectLayer?,
      );
      return;
    }

    // Better Performance for Glass OR headless flutter test fallback:
    // clean lifted specular glass rim + soft contact shadow (zero GPU shader cost).
    _backdropHandle.layer = null;
    layer = null;
    final rimAlpha = frame.rimAlpha.clamp(0.0, 1.0);
    if (rimAlpha > 0.004) {
      final shifted = localRect.shift(offset);
      final rrect = RRect.fromRectAndRadius(
        shifted,
        Radius.circular(clampedRadius),
      );
      if (frame.shadowAlpha > 0.004) {
        final shadowPaint = Paint()
          ..color = Colors.black.withValues(
            alpha: (_isDark ? 0.30 : 0.10) * frame.shadowAlpha.clamp(0.0, 1.0),
          )
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10.0);
        context.canvas.drawRRect(rrect.shift(const Offset(0, 2)), shadowPaint);
      }

      final rimPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1
        ..shader = SweepGradient(
          center: Alignment.center,
          colors: [
            Colors.white.withValues(alpha: (_isDark ? 0.10 : 0.22) * rimAlpha),
            Colors.white.withValues(alpha: (_isDark ? 0.55 : 0.90) * rimAlpha),
            Colors.white.withValues(alpha: (_isDark ? 0.10 : 0.22) * rimAlpha),
            Colors.white.withValues(alpha: (_isDark ? 0.65 : 0.95) * rimAlpha),
            Colors.white.withValues(alpha: (_isDark ? 0.10 : 0.22) * rimAlpha),
          ],
          stops: const [0.0, 0.125, 0.38, 0.625, 1.0],
        ).createShader(shifted);
      context.canvas.drawRRect(rrect, rimPaint);
    }
    super.paint(context, offset);
  }
}

/// True 2-pass separable 25×25 (625-tap equivalent) progressive Gaussian faded
/// frosted blur powered by `shaders/frosted_fade_blur.frag`.
///
/// Matches BitChord's `TopFadeBlur`: creamy frosted blur strongest along the
/// status bar and easing via quintic `smootherStep` (`6t⁵ - 15t⁴ + 10t³`) down
/// to exact `0.0 px` below the toolbar — with ZERO bottom border and ZERO
/// sparse-ring ghosting!
class FrostedFadeBlurBackdrop extends SingleChildRenderObjectWidget {
  final ui.FragmentProgram? program;
  final double strength;
  final double maxRadiusDp;
  final Color scrimColor;
  final double scrimAlpha;
  final double softKnee;
  final double dpr;
  final bool enableFrostedBlur;

  const FrostedFadeBlurBackdrop({
    super.key,
    required this.program,
    required this.strength,
    required this.maxRadiusDp,
    required this.scrimColor,
    required this.scrimAlpha,
    this.softKnee = 0.34,
    required this.dpr,
    required this.enableFrostedBlur,
    super.child,
  });

  @override
  RenderFrostedFadeBlurBackdrop createRenderObject(BuildContext context) {
    return RenderFrostedFadeBlurBackdrop(
      program: program,
      strength: strength,
      maxRadiusDp: maxRadiusDp,
      scrimColor: scrimColor,
      scrimAlpha: scrimAlpha,
      softKnee: softKnee,
      dpr: dpr,
      enableFrostedBlur: enableFrostedBlur,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderFrostedFadeBlurBackdrop renderObject,
  ) {
    renderObject
      ..program = program
      ..strength = strength
      ..maxRadiusDp = maxRadiusDp
      ..scrimColor = scrimColor
      ..scrimAlpha = scrimAlpha
      ..softKnee = softKnee
      ..dpr = dpr
      ..enableFrostedBlur = enableFrostedBlur;
  }
}

class RenderFrostedFadeBlurBackdrop extends RenderProxyBox {
  ui.FragmentProgram? _program;
  ui.FragmentShader? _horizShader;
  ui.FragmentShader? _vertShader;
  final LayerHandle<BackdropFilterLayer> _horizHandle =
      LayerHandle<BackdropFilterLayer>();
  final LayerHandle<BackdropFilterLayer> _vertHandle =
      LayerHandle<BackdropFilterLayer>();

  double _strength;
  double _maxRadiusDp;
  Color _scrimColor;
  double _scrimAlpha;
  double _softKnee;
  double _dpr;
  bool _enableFrostedBlur;

  RenderFrostedFadeBlurBackdrop({
    required ui.FragmentProgram? program,
    required double strength,
    required double maxRadiusDp,
    required Color scrimColor,
    required double scrimAlpha,
    required double softKnee,
    required double dpr,
    required bool enableFrostedBlur,
  })  : _program = program,
        _strength = strength,
        _maxRadiusDp = maxRadiusDp,
        _scrimColor = scrimColor,
        _scrimAlpha = scrimAlpha,
        _softKnee = softKnee,
        _dpr = dpr,
        _enableFrostedBlur = enableFrostedBlur;

  bool get _canRunGpuShader =>
      _enableFrostedBlur &&
      _program != null &&
      ui.ImageFilter.isShaderFilterSupported;

  @override
  bool get alwaysNeedsCompositing => _canRunGpuShader;

  @override
  void dispose() {
    _horizHandle.layer = null;
    _vertHandle.layer = null;
    _horizShader?.dispose();
    _vertShader?.dispose();
    _horizShader = null;
    _vertShader = null;
    super.dispose();
  }

  set program(ui.FragmentProgram? value) {
    if (identical(_program, value)) return;
    final wasCompositing = _canRunGpuShader;
    _program = value;
    _horizShader?.dispose();
    _vertShader?.dispose();
    _horizShader = null;
    _vertShader = null;
    if (wasCompositing != _canRunGpuShader) markNeedsCompositingBitsUpdate();
    markNeedsPaint();
  }

  set strength(double value) {
    if (_strength == value) return;
    _strength = value;
    markNeedsPaint();
  }

  set maxRadiusDp(double value) {
    if (_maxRadiusDp == value) return;
    _maxRadiusDp = value;
    markNeedsPaint();
  }

  set scrimColor(Color value) {
    if (_scrimColor == value) return;
    _scrimColor = value;
    markNeedsPaint();
  }

  set scrimAlpha(double value) {
    if (_scrimAlpha == value) return;
    _scrimAlpha = value;
    markNeedsPaint();
  }

  set softKnee(double value) {
    if (_softKnee == value) return;
    _softKnee = value;
    markNeedsPaint();
  }

  set dpr(double value) {
    if (_dpr == value) return;
    _dpr = value;
    markNeedsPaint();
  }

  set enableFrostedBlur(bool value) {
    if (_enableFrostedBlur == value) return;
    final wasCompositing = _canRunGpuShader;
    _enableFrostedBlur = value;
    if (wasCompositing != _canRunGpuShader) markNeedsCompositingBitsUpdate();
    markNeedsPaint();
  }

  static double _smootherStep(double x) {
    final t = x.clamp(0.0, 1.0);
    return t * t * t * (t * (t * 6.0 - 15.0) + 10.0);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final s = _strength.clamp(0.0, 1.0);
    if (s <= 0.005 || size.isEmpty) {
      _horizHandle.layer = null;
      _vertHandle.layer = null;
      layer = null;
      super.paint(context, offset);
      return;
    }

    if (_canRunGpuShader) {
      _horizShader ??= _program!.fragmentShader();
      _vertShader ??= _program!.fragmentShader();
      final hShader = _horizShader!;
      final vShader = _vertShader!;

      final localRect = Offset.zero & size;
      final globalRect = MatrixUtils.transformRect(
        getTransformTo(null),
        localRect,
      );
      final scale = localRect.height > 0
          ? globalRect.height / localRect.height
          : 1.0;
      final pxScale = _dpr * scale;
      final topPx = globalRect.top * _dpr;
      final bottomPx =
          math.max(topPx + 1.0, (globalRect.bottom - 2.0) * _dpr);
      final radiusPx = _maxRadiusDp * s * pxScale;
      final knee = _softKnee.clamp(0.0, 0.65);

      // Pass 1: Horizontal 25-tap progressive Gaussian blur (scrim = 0.0)
      hShader.setFloat(2, topPx);
      hShader.setFloat(3, bottomPx);
      hShader.setFloat(4, radiusPx);
      hShader.setFloat(5, 1.0);
      hShader.setFloat(6, 0.0);
      hShader.setFloat(7, _scrimColor.r);
      hShader.setFloat(8, _scrimColor.g);
      hShader.setFloat(9, _scrimColor.b);
      hShader.setFloat(10, 0.0);
      hShader.setFloat(11, knee);

      // Pass 2: Vertical 25-tap progressive Gaussian blur + subtle faded mist
      vShader.setFloat(2, topPx);
      vShader.setFloat(3, bottomPx);
      vShader.setFloat(4, radiusPx);
      vShader.setFloat(5, 0.0);
      vShader.setFloat(6, 1.0);
      vShader.setFloat(7, _scrimColor.r);
      vShader.setFloat(8, _scrimColor.g);
      vShader.setFloat(9, _scrimColor.b);
      vShader.setFloat(10, (_scrimAlpha * s).clamp(0.0, 1.0));
      vShader.setFloat(11, knee);

      layer = context.pushClipRect(
        needsCompositing,
        offset,
        localRect,
        (innerCtx, innerOffset) {
          final hLayer = _horizHandle.layer ?? BackdropFilterLayer();
          hLayer
            ..filter = ui.ImageFilter.shader(hShader)
            ..blendMode = BlendMode.srcOver;
          _horizHandle.layer = hLayer;

          final vLayer = _vertHandle.layer ?? BackdropFilterLayer();
          vLayer
            ..filter = ui.ImageFilter.shader(vShader)
            ..blendMode = BlendMode.srcOver;
          _vertHandle.layer = vLayer;

          // Push horizontal pass, then vertical pass on top of its output!
          innerCtx.pushLayer(hLayer, (ctx2, off2) {
            ctx2.pushLayer(vLayer, super.paint, off2);
          }, innerOffset);
        },
        oldLayer: layer as ClipRectLayer?,
      );
      return;
    }

    // Fallback (Progressive Blur OFF, Reduce Dynamic Blur ON, or headless test):
    // 16-stop smootherStep faded mist with zero hard border (exact FadeCurve.kt).
    _horizHandle.layer = null;
    _vertHandle.layer = null;
    layer = null;
    final rect = offset & size;
    final peakAlpha = (_enableFrostedBlur ? _scrimAlpha : 0.94) * s;
    const stopCount = 16;
    final colors = <Color>[];
    final stops = <double>[];
    for (int i = 0; i < stopCount; i++) {
      final t = i / (stopCount - 1);
      final fade = 1.0 - _smootherStep(t);
      colors.add(_scrimColor.withValues(alpha: (peakAlpha * fade).clamp(0.0, 1.0)));
      stops.add(t);
    }
    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: colors,
        stops: stops,
      ).createShader(rect);
    context.canvas.drawRect(rect, paint);
    super.paint(context, offset);
  }
}
