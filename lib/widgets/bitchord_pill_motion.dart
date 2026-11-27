import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../services/animation_speed_service.dart';

/// Pure-Dart port of BitChord's 120Hz `GlassPillMotion` & `PillSquashModel`
/// (originally ported from `liquid_glass_easy` into BitChord's `GlassSelectionPill.kt`).
///
/// Physics architecture:
/// - **Travel spring** (`k = 280, d = 31.4`): carries the pill between tabs
///   preserving velocity across rapid retargets.
/// - **Decoupled X/Y lift springs** (`k = 250, dx = 19.0 (ζ=0.60), dy = 22.1 (ζ=0.70)`):
///   inflates the pill past the bar (`PILL_GROW_HEIGHT = 9 dp`) with subtle
///   underdamped overshoot, holding it aloft through the journey and releasing
///   at `HANDOVER_START = 0.92` so it deflates gracefully into its resting slot.
/// - **Fast material spring** (`k = 1000, d = 63.3`, critically damped): brings
///   crystal glass refraction online almost immediately on touch/tap.
/// - **Exponential finger follower** (`FOLLOW_TAU = 0.05 s`): eliminates raw
///   touch-digitizer jitter and stopping/stuttering when scrubbing or hovering,
///   plus gentle rubber-band resistance past the first/last tab.
/// - **2nd-derivative `PillSquashModel`**: stretches wide & flat on launch and
///   squashes narrow & tall when braking (`±12%` max deformation).
class BitChordPillMotion extends ChangeNotifier {
  static const double pillGrowHeightDp = 9.0;
  static const double pillGrowHeightMinimizedDp = 7.0;

  static const double _travelStiffness = 280.0;
  static const double _travelDamping = 31.4;

  static const double _liftStiffness = 250.0;
  static const double _liftDampingX = 19.0;
  static const double _liftDampingY = 22.1;

  static const double _materialStiffness = 1000.0;
  static const double _materialDamping = 63.3;

  static const double _handoverStart = 0.92;
  static const double _handoverTau = 0.09;
  static const double _glassReturnTau = 0.05;
  static const double _followTau = 0.05;
  static const double _signTau = 0.25;

  final TickerProvider _vsync;
  Ticker? _ticker;
  Duration? _lastElapsed;
  double _simTimeSec = 0.0;

  /// One tab step in logical dp, used by the acceleration squash model.
  double stepDp = 0.0;

  /// When true ("Reduce animation"), all moves snap instantly without lift.
  bool reduceMotion = false;

  int _index;
  double _travelPos;
  double _travelVel = 0.0;
  double _travelTarget;
  double _travelFrom;
  bool _travelActive = false;

  bool _lifted = false;
  double _liftXPos = 0.0;
  double _liftXVel = 0.0;
  double _liftYPos = 0.0;
  double _liftYVel = 0.0;
  double _liftPos = 0.0;
  double _liftVel = 0.0;

  bool _dragging = false;
  double _dragTarget = 0.0;
  double _dragFollow = 0.0;

  double _travelSign = 0.0;
  double _travelSignEased = 0.0;
  double _handover = 1.0;
  double _squash = 0.0;
  final _PillSquashModel _squashModel = _PillSquashModel();

  // Published frame outputs
  double _position;
  double _liftX = 0.0;
  double _liftY = 0.0;
  double _material = 0.0;
  double _deviation = 0.0;
  double _glassPresence = 0.0;
  bool _isFlat = true;

  BitChordPillMotion({
    required TickerProvider vsync,
    required int initialIndex,
  })  : _vsync = vsync,
        _index = initialIndex,
        _travelPos = initialIndex.toDouble(),
        _travelTarget = initialIndex.toDouble(),
        _travelFrom = initialIndex.toDouble(),
        _position = initialIndex.toDouble();

  /// Where the pill is drawn, in continuous tab steps (`0.0 .. count - 1`).
  double get position => _position;

  /// Width lift (`0` at rest, `1` at lifted size; underdamped overshoot allowed).
  double get liftX => _liftX;

  /// Height lift (`0` at rest, `1` at lifted size; underdamped overshoot allowed).
  double get liftY => _liftY;

  /// How strongly the crystal glass material is engaged (`0.0 .. 1.0`).
  double get material => _material;

  /// Acceleration squash: width scales by `1 + deviation`, height by `1 - deviation`.
  double get deviation => _deviation;

  /// Remaining glass lens presence (`1.0` lifted down to `0.0` flat resting pill).
  double get glassPresence => _glassPresence;

  /// True when fully settled at rest (plain flat pill draws identical pixels,
  /// zero GPU shader cost, Ticker stopped).
  bool get isFlat => _isFlat;

  /// True while a finger or pointer is actively scrubbing/hovering the pill.
  bool get isDragging => _dragging;

  /// Target tab index the pill is resting on or traveling toward.
  int get index => _index;

  /// BitChord's rim & shadow shed factor: gone by the time handover is 55% done.
  double get rimFactor => ((_glassPresence - 0.45) / 0.55).clamp(0.0, 1.0);

  /// Live pixel/dp size of the pill on this frame between [rest] and [lifted].
  Size liveSize(Size rest, Size lifted) {
    final w = rest.width + (lifted.width - rest.width) * _liftX;
    final h = rest.height + (lifted.height - rest.height) * _liftY;
    return Size(
      math.max(1.0, w * (1.0 + _deviation)),
      math.max(1.0, h * (1.0 - _deviation)),
    );
  }

  /// Tab tapped: lift into crystal glass and glide there on the travel spring.
  void animateTo(int next) {
    if (next == _index && !_dragging && _isFlat) return;
    if (reduceMotion) {
      snapTo(next);
      return;
    }
    _index = next;
    _dragging = false;
    _travelActive = true;
    _lifted = true;
    // Retarget smoothly from current position, preserving momentum!
    _travelFrom = _travelPos;
    _travelTarget = next.toDouble();
    _travelSign = _signOfTravel(_travelTarget - _travelFrom);
    _isFlat = false;
    _ensureRunning();
    notifyListeners();
  }

  /// Instant rest placement with zero lift or travel.
  void snapTo(int target) {
    _stopTicker();
    _index = target;
    _travelPos = target.toDouble();
    _travelTarget = _travelPos;
    _travelFrom = _travelPos;
    _travelVel = 0.0;
    _travelActive = false;
    _dragging = false;
    _lifted = false;
    _liftXPos = 0.0;
    _liftXVel = 0.0;
    _liftYPos = 0.0;
    _liftYVel = 0.0;
    _liftPos = 0.0;
    _liftVel = 0.0;
    _handover = 1.0;
    _squash = 0.0;
    _squashModel.stop();
    _travelSign = 0.0;
    _travelSignEased = 0.0;
    _publish();
    _isFlat = true;
    notifyListeners();
  }

  /// Finger or pointer picked up / started hovering the glass pill.
  void startDrag({double? initialPosition}) {
    final basePos = initialPosition ?? (_dragging ? _dragFollow : _travelPos);
    _dragging = true;
    _travelActive = false;
    _lifted = !reduceMotion;
    _travelSign = 0.0;
    if (initialPosition != null && _isFlat) {
      _dragFollow = basePos;
      _travelPos = basePos;
    } else {
      _dragFollow = _travelPos;
    }
    _dragTarget = basePos;
    _travelVel = 0.0;
    _isFlat = false;
    _ensureRunning();
    notifyListeners();
  }

  /// Updates the continuous finger/hover target in tab steps (`0.0 .. count - 1`),
  /// applying gentle rubber-band resistance past the ends.
  void dragTo(double rawPosition, {required int itemCount}) {
    if (!_dragging) startDrag(initialPosition: rawPosition.clamp(0.0, (itemCount - 1).toDouble()));
    final maxIdx = math.max(0, itemCount - 1).toDouble();
    double target = rawPosition;
    if (rawPosition < 0.0) {
      final over = -rawPosition;
      target = -0.22 * (1.0 - math.exp(-over * 3.0));
    } else if (rawPosition > maxIdx) {
      final over = rawPosition - maxIdx;
      target = maxIdx + 0.22 * (1.0 - math.exp(-over * 3.0));
    }
    _dragTarget = target;
    _ensureRunning();
  }

  /// Finger released / hover exited: snap cleanly onto [next] while staying
  /// lifted until landing (`HANDOVER_START`), then deflate into the flat pill.
  void release(int next) {
    if (!_dragging) return;
    final from = _dragFollow;
    _dragging = false;
    _index = next;
    if (reduceMotion) {
      snapTo(next);
      return;
    }
    _travelActive = true;
    _travelPos = from;
    _travelVel = 0.0;
    _travelFrom = from;
    _travelTarget = next.toDouble();
    _travelSign = _signOfTravel(_travelTarget - _travelFrom);
    _ensureRunning();
    notifyListeners();
  }

  void _ensureRunning() {
    _ticker ??= _vsync.createTicker(_onTick);
    if (!_ticker!.isActive) {
      _lastElapsed = null;
      _ticker!.start();
    }
  }

  void _stopTicker() {
    _ticker?.stop();
    _lastElapsed = null;
  }

  void _onTick(Duration elapsed) {
    final prev = _lastElapsed;
    _lastElapsed = elapsed;
    final rawDt = prev == null
        ? 0.0
        : (elapsed - prev).inMicroseconds / 1e6;
    // Clamp pathological frame hitches to 50 ms so springs never explode,
    // and scale simulation speed cleanly with TempoAnimationSpeedService!
    final speedFactor = 1.0 /
        TempoAnimationSpeedService.instance.multiplier.clamp(0.5, 1.6);
    final dt = (rawDt.clamp(0.0, 0.05)) * speedFactor;
    _simTimeSec += dt;

    final keepGoing = stepFrame(dt, _simTimeSec);
    if (!keepGoing) {
      _stopTicker();
    }
  }

  /// Advances the full coupled spring & squash simulation by [dt] seconds.
  /// Exposed as `@visibleForTesting` for deterministic unit testing.
  @visibleForTesting
  bool stepFrame(double dt, double nowSec) {
    // 1. Travel spring
    var travelSettled = true;
    if (_travelActive) {
      final (nx, nv) = _springStep(
        _travelPos,
        _travelVel,
        _travelTarget,
        dt,
        _travelStiffness,
        _travelDamping,
      );
      _travelPos = nx;
      _travelVel = nv;
      travelSettled =
          (_travelPos - _travelTarget).abs() < 0.003 && _travelVel.abs() < 0.05;
      if (travelSettled) {
        _travelPos = _travelTarget;
        _travelVel = 0.0;
      }
    }

    // 2. Smooth exponential finger/hover follower (`FOLLOW_TAU = 0.05s`)
    if (_dragging) {
      if (reduceMotion) {
        _dragFollow = _dragTarget;
      } else if (dt > 0.0) {
        _dragFollow += (_dragTarget - _dragFollow) * (1.0 - math.exp(-dt / _followTau));
      }
      _travelPos = _dragFollow;
    }

    // 3. Lifted size & material springs (held aloft until HANDOVER_START = 0.92)
    if (!_dragging && (travelSettled || _travelProgress() >= _handoverStart)) {
      _lifted = false;
    }
    final liftTarget = _lifted ? 1.0 : 0.0;
    final (lx, lxv) = _stepLift(
      _liftXPos,
      _liftXVel,
      liftTarget,
      dt,
      _liftStiffness,
      _liftDampingX,
    );
    _liftXPos = lx;
    _liftXVel = lxv;

    final (ly, lyv) = _stepLift(
      _liftYPos,
      _liftYVel,
      liftTarget,
      dt,
      _liftStiffness,
      _liftDampingY,
    );
    _liftYPos = ly;
    _liftYVel = lyv;

    final (lm, lmv) = _stepLift(
      _liftPos,
      _liftVel,
      liftTarget,
      dt,
      _materialStiffness,
      _materialDamping,
    );
    _liftPos = lm;
    _liftVel = lmv;

    final liftSettled = !_lifted &&
        _liftXPos == 0.0 &&
        _liftYPos == 0.0 &&
        _liftPos == 0.0;

    // 4. Deflation outlives the travel spring
    if (_travelActive && travelSettled && liftSettled && !_dragging) {
      _travelActive = false;
    }

    // 5. 2nd-derivative acceleration squash (`PillSquashModel`)
    final frac = _dragging ? _dragFollow : _travelPos;
    if (stepDp > 0.0 && !reduceMotion) {
      if (!_squashModel.isTracking) _squashModel.start();
      _squash = _squashModel.track(frac * stepDp, nowSec, dt);
      if (_travelSignEased == 0.0) {
        _travelSignEased = _travelSign;
      } else if (_travelSignEased != _travelSign && dt > 0.0) {
        _travelSignEased +=
            (_travelSign - _travelSignEased) * (1.0 - math.exp(-dt / _signTau));
        if ((_travelSign - _travelSignEased).abs() < 0.01) {
          _travelSignEased = _travelSign;
        }
      }
      final key = _travelSignEased;
      if (key != 0.0) {
        _squash = _squash * (1.0 - key.abs()) - key * _squash.abs();
      }
    }

    // 6. Glass-to-flat handover rides the landing deflation
    final handoverTarget = _lifted ? 0.0 : 1.0;
    if (dt > 0.0) {
      final tau = handoverTarget > _handover ? _handoverTau : _glassReturnTau;
      _handover += (handoverTarget - _handover) * (1.0 - math.exp(-dt / tau));
      if ((handoverTarget - _handover).abs() < 0.002) {
        _handover = handoverTarget;
      }
    }

    final settled = !_travelActive &&
        !_dragging &&
        liftSettled &&
        _squash.abs() < 0.0005 &&
        _handover >= 1.0;
    if (settled) {
      _squashModel.stop();
      _squash = 0.0;
      _travelSign = 0.0;
      _travelSignEased = 0.0;
    }

    _publish();
    _isFlat = settled;
    notifyListeners();
    return !settled;
  }

  void _publish() {
    _position = _dragging ? _dragFollow : _travelPos;
    _liftX = _liftXPos;
    _liftY = _liftYPos;
    _material = _liftPos.clamp(0.0, 1.0);
    _deviation = _squash;
    _glassPresence = (1.0 - _handover).clamp(0.0, 1.0);
  }

  double _travelProgress() {
    final span = (_travelTarget - _travelFrom).abs();
    if (span < 1e-6) return 1.0;
    return (1.0 - (_travelTarget - _travelPos).abs() / span).clamp(0.0, 1.0);
  }

  static double _signOfTravel(double span) =>
      span.abs() < 1e-6 ? 0.0 : span.sign;

  /// Semi-implicit Euler in `1/240 s` substeps (exact BitChord integrator).
  static (double, double) _springStep(
    double x,
    double vel,
    double target,
    double dt,
    double stiffness,
    double damping,
  ) {
    var t = dt;
    var px = x;
    var pv = vel;
    const maxSubstep = 1.0 / 240.0;
    while (t > 0.0) {
      final step = t > maxSubstep ? maxSubstep : t;
      final accel = -stiffness * (px - target) - damping * pv;
      pv += accel * step;
      px += pv * step;
      t -= step;
    }
    return (px, pv);
  }

  static (double, double) _stepLift(
    double x,
    double vel,
    double target,
    double dt,
    double stiffness,
    double damping,
  ) {
    final (nx, nv) = _springStep(x, vel, target, dt, stiffness, damping);
    if ((nx - target).abs() < 0.0008 && nv.abs() < 0.01) {
      return (target, 0.0);
    }
    return (nx, nv);
  }

  @override
  void dispose() {
    _ticker?.dispose();
    _ticker = null;
    super.dispose();
  }
}

/// Exact Dart port of BitChord's `PillSquashModel`: differentiates position
/// twice over a `0.30 s` rolling window to convert acceleration (`dp/s²`) into
/// smooth volume-preserving width/height deformation (`±12%` max).
class _PillSquashModel {
  static const double _sampleWindow = 0.30;
  static const double _sensitivity = 0.00007;
  static const double _maxDeformation = 0.12;
  static const double _responseTime = 0.18;

  final List<(double x, double t)> _history = <(double, double)>[];
  bool isTracking = false;
  double _value = 0.0;

  void start() {
    _history.clear();
    _value = 0.0;
    isTracking = true;
  }

  void stop() {
    isTracking = false;
    _history.clear();
    _value = 0.0;
  }

  double track(double x, double nowSec, double dt) {
    if (!isTracking) return _value;
    _history.add((x, nowSec));
    final cutoff = nowSec - _sampleWindow;
    _history.removeWhere((sample) => sample.$2 < cutoff);

    final raw = (_averageAcceleration() * _sensitivity)
        .clamp(-_maxDeformation, _maxDeformation);
    final ease = dt > 0.0 ? (dt / _responseTime).clamp(0.0, 1.0) : 0.0;
    _value += (raw - _value) * ease;
    return _value;
  }

  double _averageAcceleration() {
    if (_history.length < 3) return 0.0;
    final velocities = <(double v, double t)>[];
    for (int i = 1; i < _history.length; i++) {
      final dt = _history[i].$2 - _history[i - 1].$2;
      if (dt <= 1e-6) continue;
      velocities.add((
        (_history[i].$1 - _history[i - 1].$1) / dt,
        (_history[i].$2 + _history[i - 1].$2) * 0.5,
      ));
    }
    if (velocities.length < 2) return 0.0;
    double total = 0.0;
    int count = 0;
    for (int i = 1; i < velocities.length; i++) {
      final dt = velocities[i].$2 - velocities[i - 1].$2;
      if (dt <= 1e-6) continue;
      total += (velocities[i].$1 - velocities[i - 1].$1) / dt;
      count++;
    }
    return count == 0 ? 0.0 : total / count;
  }
}
