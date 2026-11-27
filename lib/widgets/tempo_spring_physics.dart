import 'dart:ui' as ui;

import 'package:flutter/animation.dart';
import 'package:flutter/physics.dart';

/// Real `SpringSimulation`-backed [Curve] with C1-smooth tail feathering to
/// exact `1.0` so resting layouts never snap at the end of a route transition.
///
/// Unlike arbitrary `Cubic` bezier curves (which can develop hidden near-vertical
/// velocity cliffs when `x2 < x1`), `TempoSpringCurve` guarantees smooth,
/// physically continuous velocity profiles across 60Hz, 90Hz, and 120Hz displays.
class TempoSpringCurve extends Curve {
  final double stiffness;
  final double damping;
  final double durationSec;
  final double maxClamp;
  final double tailStart;
  final SpringSimulation _sim;

  TempoSpringCurve({
    required this.stiffness,
    required this.damping,
    required this.durationSec,
    this.maxClamp = 1.04,
    this.tailStart = 0.86,
  }) : _sim = SpringSimulation(
          SpringDescription(mass: 1.0, stiffness: stiffness, damping: damping),
          0.0,
          1.0,
          0.0,
        );

  @override
  double transformInternal(double t) {
    if (t <= 0.0) return 0.0;
    if (t >= 1.0) return 1.0;
    final raw = _sim.x(t * durationSec).clamp(0.0, maxClamp);
    if (t > tailStart) {
      final tail = ((t - tailStart) / (1.0 - tailStart)).clamp(0.0, 1.0);
      // C1-smooth cubic Hermite smoothstep eliminates any velocity kink at tailStart.
      final smooth = tail * tail * (3.0 - 2.0 * tail);
      return ui.lerpDouble(raw, 1.0, smooth)!;
    }
    return raw;
  }
}

/// Calibrated HyperOS 4 / iOS 26 spring presets shared across Tempo's route
/// morphs, popovers, dropdowns, bottom sheets, and photo viewer transitions.
abstract final class TempoSpringCurves {
  /// Rectangular card-to-page open: gentle acceleration, lush critically damped settle.
  static final TempoSpringCurve morphOpen = TempoSpringCurve(
    stiffness: 225.0,
    damping: 29.6,
    durationSec: 0.46,
    maxClamp: 1.0,
  );

  /// Rectangular page-to-card close: unhurried cushioned return with gentle dock settle.
  static final TempoSpringCurve morphClose = TempoSpringCurve(
    stiffness: 185.0,
    damping: 19.0,
    durationSec: 0.47,
    maxClamp: 1.08,
    tailStart: 0.90,
  );

  /// Circular button open — container expansion spring (slightly trails center).
  static final TempoSpringCurve dropletOpenSize = TempoSpringCurve(
    stiffness: 220.0,
    damping: 29.4,
    durationSec: 0.46,
    maxClamp: 1.0,
  );

  /// Circular button open — center launch spring (leads size slightly for floating arc).
  static final TempoSpringCurve dropletOpenCenter = TempoSpringCurve(
    stiffness: 290.0,
    damping: 33.4,
    durationSec: 0.46,
    maxClamp: 1.0,
  );

  /// Circular button close — silky slow underdamped droplet collapse with soft liquid settle.
  static final TempoSpringCurve dropletCloseSize = TempoSpringCurve(
    stiffness: 190.0,
    damping: 17.6,
    durationSec: 0.54,
    maxClamp: 1.12,
    tailStart: 0.90,
  );

  /// Circular button close — unhurried trailing center glide with gentle parabolic dock bounce.
  static final TempoSpringCurve dropletCloseCenter = TempoSpringCurve(
    stiffness: 155.0,
    damping: 16.0,
    durationSec: 0.54,
    maxClamp: 1.12,
    tailStart: 0.90,
  );

  /// HyperOS 4 Liquid Glass popover — detached open center spring (~1.2% elastic bloom).
  static final TempoSpringCurve popoverOpenCenter = TempoSpringCurve(
    stiffness: 460.0,
    damping: 33.4,
    durationSec: 0.58,
    maxClamp: 1.03,
    tailStart: 0.90,
  );

  /// HyperOS 4 Liquid Glass popover — open size expansion spring.
  static final TempoSpringCurve popoverOpenSize = TempoSpringCurve(
    stiffness: 220.0,
    damping: 24.6,
    durationSec: 0.58,
    maxClamp: 1.025,
    tailStart: 0.90,
  );

  /// HyperOS 4 Liquid Glass popover — unhurried droplet collapse with creamy liquid settle.
  static final TempoSpringCurve popoverCloseSize = TempoSpringCurve(
    stiffness: 240.0,
    damping: 19.6,
    durationSec: 0.47,
    maxClamp: 1.12,
    tailStart: 0.90,
  );

  /// HyperOS 4 Liquid Glass popover — smooth floating return with soft, relaxed dock bounce.
  static final TempoSpringCurve popoverCloseCenter = TempoSpringCurve(
    stiffness: 190.0,
    damping: 17.6,
    durationSec: 0.47,
    maxClamp: 1.12,
    tailStart: 0.90,
  );

  /// HyperOS vertical-unfold preference dropdown spring (~1.4% elastic settle).
  static final TempoSpringCurve dropdownUnfold = TempoSpringCurve(
    stiffness: 340.0,
    damping: 29.0,
    durationSec: 0.34,
    maxClamp: 1.03,
    tailStart: 0.88,
  );

  /// HyperOS dropdown fold-back close curve with smooth cushioned settle.
  static final TempoSpringCurve dropdownFoldClose = TempoSpringCurve(
    stiffness: 255.0,
    damping: 23.0,
    durationSec: 0.34,
    maxClamp: 1.06,
    tailStart: 0.90,
  );

  /// iOS 26 modal bottom sheet spring open (silky organic glide, ~1% gentle bloom).
  static final TempoSpringCurve sheetOpen = TempoSpringCurve(
    stiffness: 300.0,
    damping: 28.5,
    durationSec: 0.46,
    maxClamp: 1.02,
    tailStart: 0.88,
  );

  /// iOS 26 modal bottom sheet smooth critically damped dismissal.
  static final TempoSpringCurve sheetClose = TempoSpringCurve(
    stiffness: 340.0,
    damping: 36.8,
    durationSec: 0.28,
    maxClamp: 1.0,
    tailStart: 0.86,
  );

  /// Progress Album photo morph open / close springs.
  static final TempoSpringCurve photoOpen = TempoSpringCurve(
    stiffness: 260.0,
    damping: 31.8,
    durationSec: 0.36,
    maxClamp: 1.0,
  );

  static final TempoSpringCurve photoClose = TempoSpringCurve(
    stiffness: 275.0,
    damping: 32.8,
    durationSec: 0.32,
    maxClamp: 1.0,
  );
}
