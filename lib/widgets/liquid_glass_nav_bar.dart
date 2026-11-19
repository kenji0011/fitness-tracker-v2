import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';
import 'liquid_glass_surface.dart';

class LiquidGlassNavItem {
  final String label;
  final IconData icon;
  final IconData activeIcon;

  const LiquidGlassNavItem({
    required this.label,
    required this.icon,
    required this.activeIcon,
  });
}

/// iOS 26/27-inspired floating Liquid Glass Navigation Bar powered by a real
/// GPU screen-space SDF refraction + chromatic dispersion fragment shader
/// (`shaders/liquid_glass_lens.frag`) ported from QWEA0/Liquid-Glass-Android.
///
/// Interaction model:
/// - **At rest:** Clean floating frosted-glass capsule with a subtle, flush resting pill.
/// - **On horizontal drag / touch-scrub / desktop hover:** The optical **Liquid Glass Droplet**
///   inflates **over** the tab row, refracts & chromatically disperses the live icons & labels
///   underneath at its curved bevel, stretches elastically (`scaleX/scaleY`), gives haptic
///   clicks across tabs, and settles cleanly back into the resting pill on release.
/// - **Double-tap `Profile`:** Instantly opens the 4-digit PIN local profile switcher with zero
///   tap lag on single taps.
class LiquidGlassNavBar extends StatefulWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final VoidCallback? onProfileDoubleTap;
  final String? profileName;
  final String? profileAvatarPath;
  final List<LiquidGlassNavItem> items;

  const LiquidGlassNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
    this.onProfileDoubleTap,
    this.profileName,
    this.profileAvatarPath,
    this.items = const [
      LiquidGlassNavItem(
        label: 'Summary',
        icon: CupertinoIcons.heart,
        activeIcon: CupertinoIcons.heart_fill,
      ),
      LiquidGlassNavItem(
        label: 'Workout',
        icon: CupertinoIcons.bolt_circle,
        activeIcon: CupertinoIcons.bolt_circle_fill,
      ),
      LiquidGlassNavItem(
        label: 'Progress',
        icon: CupertinoIcons.chart_bar_square,
        activeIcon: CupertinoIcons.chart_bar_square_fill,
      ),
      LiquidGlassNavItem(
        label: 'Profile',
        icon: CupertinoIcons.person_crop_circle,
        activeIcon: CupertinoIcons.person_crop_circle_fill,
      ),
    ],
  });

  @override
  State<LiquidGlassNavBar> createState() => _LiquidGlassNavBarState();
}

class _LiquidGlassNavBarState extends State<LiquidGlassNavBar>
    with TickerProviderStateMixin {
  static ui.FragmentProgram? _cachedProgram;
  ui.FragmentProgram? _program;

  final GlobalKey _barKey = GlobalKey();

  late final AnimationController _lensController;
  late final Animation<double> _lensAnimation;

  late final AnimationController _slideController;
  Animation<double>? _slideAnimation;

  /// Per-tab SF-Symbols-inspired spring click bounce animation
  late final AnimationController _iconBounceController;
  int _bouncingTabIndex = -1;

  Timer? _tapPulseTimer;
  DateTime? _lastProfileTapTime;

  /// Continuous tab position in `[0.0, items.length - 1]`.
  double _currentPos = 0.0;
  double _slideDistance = 0.0;
  bool _isDragging = false;
  bool _isHovering = false;
  bool _isTapPulsing = false;
  double _dragVelocityStretch = 0.0;
  int _lastHapticIndex = 0;

  @override
  void initState() {
    super.initState();
    _currentPos = widget.currentIndex.toDouble();
    _lastHapticIndex = widget.currentIndex;

    _loadShader();

    _lensController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 210),
      reverseDuration: const Duration(milliseconds: 250),
    );
    _lensAnimation = CurvedAnimation(
      parent: _lensController,
      curve: Curves.easeOutBack,
      reverseCurve: Curves.easeOutCubic,
    );

    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 340),
    )..addListener(() {
        if (_slideAnimation != null) {
          setState(() => _currentPos = _slideAnimation!.value);
        }
      });

    _iconBounceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
  }

  Future<void> _loadShader() async {
    if (_cachedProgram != null) {
      _program = _cachedProgram;
      return;
    }
    if (!ui.ImageFilter.isShaderFilterSupported) return;
    try {
      final program =
          await ui.FragmentProgram.fromAsset('shaders/liquid_glass_lens.frag');
      _cachedProgram = program;
      if (mounted) {
        setState(() => _program = program);
      }
    } catch (e) {
      debugPrint('LiquidGlass shader fallback active: $e');
    }
  }

  @override
  void didUpdateWidget(covariant LiquidGlassNavBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentIndex != widget.currentIndex && !_isDragging) {
      _lastHapticIndex = widget.currentIndex;
      if (!_isHovering) {
        _animatePosTo(widget.currentIndex.toDouble());
      }
    }
  }

  @override
  void dispose() {
    _tapPulseTimer?.cancel();
    _lensController.dispose();
    _slideController.dispose();
    _iconBounceController.dispose();
    super.dispose();
  }

  void _triggerIconBounce(int index) {
    _bouncingTabIndex = index;
    _iconBounceController.forward(from: 0);
  }

  bool get _isGlassLensEngaged => _isDragging || _isHovering || _isTapPulsing;

  void _syncLensExpansion() {
    if (_isGlassLensEngaged) {
      _lensController.forward();
    } else {
      _lensController.reverse();
    }
  }

  void _animatePosTo(double target) {
    if ((target - _currentPos).abs() < 0.005) {
      _slideController.stop();
      setState(() => _currentPos = target);
      return;
    }
    _slideController.stop();
    _slideDistance = (target - _currentPos).abs();
    _slideAnimation = Tween<double>(
      begin: _currentPos,
      end: target,
    ).animate(
      CurvedAnimation(parent: _slideController, curve: Curves.easeOutCubic),
    );
    _slideController.forward(from: 0);
  }

  double _dxToContinuousPos(double localDx, double totalWidth) {
    final tabWidth = totalWidth / widget.items.length;
    final raw = (localDx - tabWidth / 2) / tabWidth;
    return raw.clamp(0.0, (widget.items.length - 1).toDouble());
  }

  int _posToIndex(double pos) =>
      pos.round().clamp(0, widget.items.length - 1);

  void _handleTapAt(double localDx, double totalWidth) {
    final index = _posToIndex(_dxToContinuousPos(localDx, totalWidth));
    final isProfileTab = index == widget.items.length - 1;

    // Instant double-tap check on Profile tab (zero single-tap delay!)
    if (isProfileTab && widget.onProfileDoubleTap != null) {
      final now = DateTime.now();
      if (_lastProfileTapTime != null &&
          now.difference(_lastProfileTapTime!).inMilliseconds <= 320) {
        _lastProfileTapTime = null;
        HapticFeedback.mediumImpact();
        widget.onProfileDoubleTap!();
        return;
      }
      _lastProfileTapTime = now;
    } else {
      _lastProfileTapTime = null;
    }

    HapticFeedback.selectionClick();
    _triggerIconBounce(index);
    _tapPulseTimer?.cancel();
    setState(() => _isTapPulsing = true);
    _animatePosTo(index.toDouble());
    _syncLensExpansion();

    if (index != widget.currentIndex) {
      widget.onTap(index);
    }

    _tapPulseTimer = Timer(const Duration(milliseconds: 280), () {
      if (!mounted) return;
      setState(() => _isTapPulsing = false);
      _syncLensExpansion();
    });
  }

  void _handleDragStart(DragStartDetails details, double totalWidth) {
    _tapPulseTimer?.cancel();
    _slideController.stop();
    final pos = _dxToContinuousPos(details.localPosition.dx, totalWidth);
    setState(() {
      _isTapPulsing = false;
      _isDragging = true;
      _currentPos = pos;
      _dragVelocityStretch = 0.0;
    });
    _lastHapticIndex = _posToIndex(pos);
    HapticFeedback.lightImpact();
    _syncLensExpansion();
  }

  void _handleDragUpdate(DragUpdateDetails details, double totalWidth) {
    final pos = _dxToContinuousPos(details.localPosition.dx, totalWidth);
    final nearest = _posToIndex(pos);
    if (nearest != _lastHapticIndex) {
      _lastHapticIndex = nearest;
      HapticFeedback.selectionClick();
    }
    setState(() {
      _currentPos = pos;
      _dragVelocityStretch = (details.delta.dx.abs() / 18.0).clamp(0.0, 0.20);
    });
  }

  void _handleDragEnd(DragEndDetails details) {
    final targetIndex = _posToIndex(_currentPos);
    setState(() {
      _isDragging = false;
      _dragVelocityStretch = 0.0;
    });
    _animatePosTo(targetIndex.toDouble());
    if (targetIndex != widget.currentIndex) {
      _triggerIconBounce(targetIndex);
      widget.onTap(targetIndex);
    }
    _syncLensExpansion();
  }

  void _handleDragCancel() {
    setState(() {
      _isDragging = false;
      _dragVelocityStretch = 0.0;
    });
    _animatePosTo(widget.currentIndex.toDouble());
    _syncLensExpansion();
  }

  // Only allow real pointer hover (mouse / trackpad / stylus) — never touch!
  // This prevents Android/HyperOS touch events from ever leaving hover stuck.
  bool _isPointerHoverDevice(PointerEvent event) =>
      event.kind != PointerDeviceKind.touch;

  void _handleHoverEnter(PointerEnterEvent event, double totalWidth) {
    if (!_isPointerHoverDevice(event) || _isDragging) return;
    final pos = _dxToContinuousPos(event.localPosition.dx, totalWidth);
    setState(() => _isHovering = true);
    _animatePosTo(pos);
    _syncLensExpansion();
  }

  void _handleHoverMove(PointerHoverEvent event, double totalWidth) {
    if (!_isPointerHoverDevice(event) || _isDragging) return;
    final pos = _dxToContinuousPos(event.localPosition.dx, totalWidth);
    _slideController.stop();
    setState(() {
      _isHovering = true;
      _currentPos = pos;
    });
  }

  void _handleHoverExit(PointerExitEvent event) {
    if (!_isHovering) return;
    setState(() => _isHovering = false);
    if (!_isDragging) {
      _animatePosTo(widget.currentIndex.toDouble());
    }
    _syncLensExpansion();
  }

  Offset? _barGlobalOrigin() {
    final box = _barKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize || !box.attached) return null;
    return box.localToGlobal(Offset.zero);
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final isDark = c.isDark;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        18,
        0,
        18,
        bottomPadding > 0 ? bottomPadding : 14,
      ),
      child: Center(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: SizedBox(
            key: _barKey,
            height: 82,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final totalWidth = constraints.maxWidth;
                final tabWidth = totalWidth / widget.items.length;

                return MouseRegion(
                  onEnter: (e) => _handleHoverEnter(e, totalWidth),
                  onHover: (e) => _handleHoverMove(e, totalWidth),
                  onExit: _handleHoverExit,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapUp: (details) =>
                        _handleTapAt(details.localPosition.dx, totalWidth),
                    onHorizontalDragStart: (d) =>
                        _handleDragStart(d, totalWidth),
                    onHorizontalDragUpdate: (d) =>
                        _handleDragUpdate(d, totalWidth),
                    onHorizontalDragEnd: _handleDragEnd,
                    onHorizontalDragCancel: _handleDragCancel,
                    child: AnimatedBuilder(
                      animation: Listenable.merge([
                        _lensAnimation,
                        _slideController,
                        _iconBounceController,
                      ]),
                      builder: (context, _) {
                        final t = _lensAnimation.value.clamp(0.0, 1.12);
                        final tClamped = t.clamp(0.0, 1.0);

                        // Volume-preserving liquid droplet stretch
                        final slideWave = _slideController.isAnimating
                            ? math.sin(
                                math.pi *
                                    (_slideController.value * 1.15)
                                        .clamp(0.0, 1.0),
                              )
                            : 0.0;
                        final slideStretch = 0.18 *
                            (_slideDistance / 3.0).clamp(0.0, 1.0) *
                            slideWave;
                        final totalStretch =
                            math.max(_dragVelocityStretch, slideStretch);

                        final scaleX = 1.0 + totalStretch;
                        final scaleY = 1.0 - totalStretch * 0.55;

                        // Resting subtle pill rect (follows continuous _currentPos so it never jumps!)
                        final restPillWidth = (tabWidth - 10).clamp(64.0, 106.0);
                        final restPillLeft = (_currentPos * tabWidth +
                                (tabWidth - restPillWidth) / 2)
                            .clamp(6.0, totalWidth - restPillWidth - 6.0);

                        // Active Liquid Glass droplet rect (inflates over icons when dragging/hovering/pulsing)
                        final dropletWidth =
                            (tabWidth * 1.02).clamp(76.0, 116.0) *
                                ui.lerpDouble(0.88, 1.0, t)! *
                                scaleX;
                        final dropletHeight =
                            ui.lerpDouble(52.0, 74.0, t)! * scaleY;
                        final dropletTop = (82.0 - dropletHeight) / 2;
                        final dropletLeft = (_currentPos * tabWidth +
                                (tabWidth - dropletWidth) / 2)
                            .clamp(-2.0, totalWidth - dropletWidth + 2.0);

                        // Single source of truth for highlighted tab (never two blue tabs at once!)
                        final activeVisualIndex = (_isDragging || _isHovering)
                            ? _posToIndex(_currentPos)
                            : widget.currentIndex;

                        // Compute exact screen-space rect for Impeller BackdropFilter shader
                        final barOrigin =
                            tClamped > 0.01 ? _barGlobalOrigin() : null;
                        final dropletScreenRect = barOrigin != null
                            ? Rect.fromLTWH(
                                barOrigin.dx + dropletLeft,
                                barOrigin.dy + dropletTop,
                                dropletWidth,
                                dropletHeight,
                              )
                            : Rect.zero;

                        return Stack(
                          clipBehavior: Clip.none,
                          alignment: Alignment.center,
                          children: [
                            // LAYER 1: Outer floating frosted-glass capsule dock
                            Positioned(
                              left: 0,
                              right: 0,
                              top: 9,
                              bottom: 9,
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(34),
                                  boxShadow: [
                                    BoxShadow(
                                      color: isDark
                                          ? Colors.black.withValues(alpha: 0.52)
                                          : Colors.black.withValues(alpha: 0.09),
                                      blurRadius: 28,
                                      spreadRadius: -2,
                                      offset: const Offset(0, 10),
                                    ),
                                  ],
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(34),
                                  child: BackdropFilter(
                                    filter: ui.ImageFilter.blur(
                                      sigmaX: 28,
                                      sigmaY: 28,
                                    ),
                                    child: Container(
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(34),
                                        gradient: LinearGradient(
                                          begin: Alignment.topCenter,
                                          end: Alignment.bottomCenter,
                                          colors: isDark
                                              ? [
                                                  const Color(0xFF28282C)
                                                      .withValues(alpha: 0.78),
                                                  const Color(0xFF151518)
                                                      .withValues(alpha: 0.84),
                                                ]
                                              : [
                                                  Colors.white
                                                      .withValues(alpha: 0.86),
                                                  const Color(0xFFF7F7F8)
                                                      .withValues(alpha: 0.80),
                                                ],
                                        ),
                                        border: Border.all(
                                          color: isDark
                                              ? Colors.white
                                                  .withValues(alpha: 0.14)
                                              : Colors.black
                                                  .withValues(alpha: 0.07),
                                          width: 1,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),

                            // LAYER 2A: Subtle resting active pill (cleanly tracks _currentPos, fades out under droplet)
                            if (tClamped < 0.99)
                              Positioned(
                                left: restPillLeft,
                                top: 15,
                                width: restPillWidth,
                                height: 52,
                                child: IgnorePointer(
                                  child: Opacity(
                                    opacity: (1.0 - tClamped).clamp(0.0, 1.0),
                                    child: Container(
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(26),
                                        color: isDark
                                            ? Colors.white
                                                .withValues(alpha: 0.12)
                                            : Colors.black
                                                .withValues(alpha: 0.055),
                                      ),
                                    ),
                                  ),
                                ),
                              ),

                            // LAYER 2B: Tab Icons & Labels
                            Positioned(
                              left: 0,
                              right: 0,
                              top: 9,
                              bottom: 9,
                              child: Row(
                                children: List.generate(widget.items.length, (i) {
                                  final item = widget.items[i];
                                  final isActive = i == activeVisualIndex;
                                  final navOrange = isDark
                                      ? const Color(0xFFFF7A33)
                                      : const Color(0xFFFF6A24);
                                  final activeTint =
                                      isActive ? navOrange : c.navInactive;
                                  final isProfileTab =
                                      i == widget.items.length - 1;
                                  final hasProfileAvatar = isProfileTab &&
                                      (widget.profileName?.trim().isNotEmpty ??
                                          false);

                                  // SF-Symbols-inspired per-tab bounce/wiggle/lift animation on click
                                  final animVal = (_bouncingTabIndex == i &&
                                          _iconBounceController.isAnimating)
                                      ? _iconBounceController.value
                                      : 0.0;
                                  final bounceScale = animVal > 0
                                      ? 1.0 +
                                          0.26 *
                                              math.sin(animVal * math.pi) *
                                              (1.0 - animVal * 0.35)
                                      : 1.0;
                                  // Tab 1 (Workout): subtle energetic tilt wiggle; Tab 2 (Progress): upward pop lift
                                  final tiltAngle = (i == 1 && animVal > 0)
                                      ? math.sin(animVal * math.pi * 3) *
                                          0.16 *
                                          (1.0 - animVal)
                                      : 0.0;
                                  final liftY = (i == 2 && animVal > 0)
                                      ? -3.5 * math.sin(animVal * math.pi)
                                      : 0.0;

                                  return Expanded(
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Transform.translate(
                                          offset: Offset(0, liftY),
                                          child: Transform.rotate(
                                            angle: tiltAngle,
                                            child: Transform.scale(
                                              scale: bounceScale,
                                              child: hasProfileAvatar
                                                  ? LocalProfileAvatar(
                                                      name:
                                                          widget.profileName!,
                                                      avatarPath: widget
                                                              .profileAvatarPath ??
                                                          '',
                                                      size: 25,
                                                      showBorder: true,
                                                      borderWidth: 1.8,
                                                      borderColor: isActive
                                                          ? navOrange
                                                          : (isDark
                                                              ? Colors.white
                                                                  .withValues(
                                                                      alpha:
                                                                          0.35)
                                                              : Colors.white),
                                                      showShadow: false,
                                                    )
                                                  : _buildNavIcon(
                                                      index: i,
                                                      item: item,
                                                      isActive: isActive,
                                                      color: activeTint,
                                                    ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          item.label,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: isActive
                                                ? FontWeight.w700
                                                : FontWeight.w500,
                                            letterSpacing: -0.1,
                                            color: activeTint,
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }),
                              ),
                            ),

                            // LAYER 3 (TOP): Screen-space GPU Optical Liquid Glass Droplet
                            // Only active when dragging, hovering, or briefly pulsing on tap
                            if (tClamped > 0.01 && barOrigin != null)
                              Positioned(
                                left: dropletLeft,
                                top: dropletTop,
                                width: dropletWidth,
                                height: dropletHeight,
                                child: IgnorePointer(
                                  child: _OpticalLiquidGlassDroplet(
                                    program: _program,
                                    screenRect: dropletScreenRect,
                                    expansion: tClamped,
                                    isDark: isDark,
                                    dpr: dpr,
                                    pressIntensity: _isDragging ? 0.85 : 0.30,
                                  ),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavIcon({
    required int index,
    required LiquidGlassNavItem item,
    required bool isActive,
    required Color color,
  }) {
    if (index == 0) {
      return SizedBox(
        width: 24,
        height: 24,
        child: CustomPaint(
          painter: _HealthRingNavIconPainter(
            color: color,
            isActive: isActive,
          ),
        ),
      );
    }
    if (index == 1) {
      return SizedBox(
        width: 24,
        height: 24,
        child: CustomPaint(
          painter: _WorkoutRunnerNavIconPainter(
            color: color,
            isActive: isActive,
          ),
        ),
      );
    }
    return Icon(
      isActive ? item.activeIcon : item.icon,
      size: 24,
      color: color,
    );
  }
}

/// Thick circular ring ("Health" / Summary) icon matching the Mi Fitness nav style.
class _HealthRingNavIconPainter extends CustomPainter {
  final Color color;
  final bool isActive;

  const _HealthRingNavIconPainter({
    required this.color,
    required this.isActive,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = isActive ? size.width * 0.22 : size.width * 0.20;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..isAntiAlias = true;
    final radius = (size.width * 0.80 - stroke) / 2;
    canvas.drawCircle(
      Offset(size.width / 2, size.height / 2),
      radius,
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _HealthRingNavIconPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.isActive != isActive;
}

/// Dynamic sprinting runner ("Workout") icon matching the Mi Fitness nav style.
class _WorkoutRunnerNavIconPainter extends CustomPainter {
  final Color color;
  final bool isActive;

  const _WorkoutRunnerNavIconPainter({
    required this.color,
    required this.isActive,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final fillPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    final limbStroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * (isActive ? 0.115 : 0.105)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    // Head (leaning forward top-right)
    canvas.drawCircle(Offset(w * 0.67, h * 0.20), w * 0.11, fillPaint);

    // Torso (slanted forward athletic posture)
    final torsoPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * (isActive ? 0.145 : 0.135)
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;
    canvas.drawLine(
      Offset(w * 0.56, h * 0.37),
      Offset(w * 0.42, h * 0.58),
      torsoPaint,
    );

    // Trailing arm (reaching back-left)
    final backArm = Path()
      ..moveTo(w * 0.54, h * 0.38)
      ..lineTo(w * 0.37, h * 0.34)
      ..lineTo(w * 0.25, h * 0.44);
    canvas.drawPath(backArm, limbStroke);

    // Leading arm (bent forward-right)
    final frontArm = Path()
      ..moveTo(w * 0.56, h * 0.39)
      ..lineTo(w * 0.70, h * 0.46)
      ..lineTo(w * 0.81, h * 0.38);
    canvas.drawPath(frontArm, limbStroke);

    // Leading driving leg
    final frontLeg = Path()
      ..moveTo(w * 0.44, h * 0.58)
      ..lineTo(w * 0.63, h * 0.65)
      ..lineTo(w * 0.57, h * 0.86);
    canvas.drawPath(frontLeg, limbStroke);

    // Trailing extended sprint leg
    final backLeg = Path()
      ..moveTo(w * 0.41, h * 0.58)
      ..lineTo(w * 0.28, h * 0.73)
      ..lineTo(w * 0.14, h * 0.79);
    canvas.drawPath(backLeg, limbStroke);
  }

  @override
  bool shouldRepaint(covariant _WorkoutRunnerNavIconPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.isActive != isActive;
}

class _OpticalLiquidGlassDroplet extends StatelessWidget {
  final ui.FragmentProgram? program;
  final Rect screenRect;
  final double expansion;
  final bool isDark;
  final double dpr;
  final double pressIntensity;

  const _OpticalLiquidGlassDroplet({
    required this.program,
    required this.screenRect,
    required this.expansion,
    required this.isDark,
    required this.dpr,
    required this.pressIntensity,
  });

  @override
  Widget build(BuildContext context) {
    final radius = ui.lerpDouble(26.0, 38.0, expansion)!;

    Widget lensContent;
    if (program != null && ui.ImageFilter.isShaderFilterSupported) {
      final shader = program!.fragmentShader();
      // Indices 0 & 1 are u_size (populated automatically by Impeller)
      shader.setFloat(2, screenRect.left * dpr); // u_rectLeft
      shader.setFloat(3, screenRect.top * dpr); // u_rectTop
      shader.setFloat(4, screenRect.width * dpr); // u_rectWidth
      shader.setFloat(5, screenRect.height * dpr); // u_rectHeight
      shader.setFloat(6, expansion); // u_expansion
      shader.setFloat(7, 11.0 * dpr); // u_bevel
      shader.setFloat(8, 9.0 * dpr); // u_refract
      shader.setFloat(9, 0.08); // u_dispersion
      shader.setFloat(10, isDark ? 1.0 : 0.0); // u_isDark
      shader.setFloat(11, pressIntensity); // u_press

      lensContent = ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(
          filter: ui.ImageFilter.shader(shader),
          child: const SizedBox.expand(),
        ),
      );
    } else {
      lensContent = ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isDark
                  ? [
                      Colors.white.withValues(alpha: 0.16 * expansion),
                      Colors.transparent,
                      Colors.white.withValues(alpha: 0.10 * expansion),
                    ]
                  : [
                      Colors.white.withValues(alpha: 0.34 * expansion),
                      Colors.white.withValues(alpha: 0.04 * expansion),
                      Colors.white.withValues(alpha: 0.22 * expansion),
                    ],
            ),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.35 * expansion)
                  : Colors.white.withValues(alpha: 0.92 * expansion),
              width: 1.4,
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
            color: Colors.black
                .withValues(alpha: (isDark ? 0.36 : 0.11) * expansion),
            blurRadius: 16 * expansion,
            offset: Offset(0, 5 * expansion),
          ),
        ],
      ),
      child: lensContent,
    );
  }
}
