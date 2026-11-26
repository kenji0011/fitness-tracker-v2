import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:jiggicons/jiggicons.dart';

import '../theme/app_colors.dart';
import 'liquid_glass_surface.dart';
import 'tempo_jigg_icon.dart';

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
  final bool minimized;
  final List<LiquidGlassNavItem> items;

  const LiquidGlassNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
    this.onProfileDoubleTap,
    this.profileName,
    this.profileAvatarPath,
    this.minimized = false,
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
  ui.FragmentProgram? _program;
  bool _layoutSynced = false;

  final GlobalKey _barKey = GlobalKey();

  late final AnimationController _lensController;
  late final Animation<double> _lensAnimation;

  late final AnimationController _slideController;
  Animation<double>? _slideAnimation;

  /// Per-tab SF-Symbols-inspired spring click bounce animation (Profile avatar)
  late final AnimationController _iconBounceController;
  int _bouncingTabIndex = -1;

  /// Per-tab Jiggicon spring controllers (Summary: heart, Workout: dumbbell, Progress: trophy)
  late final List<JiggIconController> _jiggControllers;

  /// Smooth scroll-driven liquid collapse (0.0 = expanded with labels, 1.0 = compact icons-only pill)
  late final AnimationController _minimizeController;
  late final Animation<double> _minimizeAnimation;

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
    _jiggControllers = List<JiggIconController>.generate(
      widget.items.length,
      (_) => JiggIconController(),
    );

    _minimizeController = AnimationController(
      vsync: this,
      value: widget.minimized ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 300),
      reverseDuration: const Duration(milliseconds: 320),
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed ||
            status == AnimationStatus.dismissed) {
          _scheduleLayoutSync();
        }
      });
    _minimizeAnimation = CurvedAnimation(
      parent: _minimizeController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeOutCubic,
    );
    _scheduleLayoutSync();
  }

  void _scheduleLayoutSync() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_barGlobalOrigin() != null) {
        setState(() => _layoutSynced = true);
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_layoutSynced) {
      _scheduleLayoutSync();
    }
  }

  Future<void> _loadShader() async {
    final existing = TempoLiquidShaderCache.program;
    if (existing != null) {
      _program = existing;
      return;
    }
    final program = await TempoLiquidShaderCache.load();
    if (program != null && mounted) {
      setState(() => _program = program);
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
    if (oldWidget.minimized != widget.minimized) {
      if (widget.minimized) {
        _minimizeController.forward();
      } else {
        _minimizeController.reverse();
      }
    }
  }

  @override
  void dispose() {
    _tapPulseTimer?.cancel();
    _lensController.dispose();
    _slideController.dispose();
    _iconBounceController.dispose();
    for (final ctrl in _jiggControllers) {
      ctrl.dispose();
    }
    _minimizeController.dispose();
    super.dispose();
  }

  void _triggerIconBounce(int index) {
    _bouncingTabIndex = index;
    _iconBounceController.forward(from: 0);
    if (index >= 0 && index < _jiggControllers.length) {
      _jiggControllers[index].play();
    }
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

    return AnimatedBuilder(
      animation: _minimizeAnimation,
      builder: (context, _) {
        final m = _minimizeAnimation.value.clamp(0.0, 1.0);
        final hPad = ui.lerpDouble(18.0, 48.0, m)!;
        final maxBarWidth = ui.lerpDouble(460.0, 272.0, m)!;
        final dockBoxHeight = ui.lerpDouble(82.0, 66.0, m)!;
        final capsuleInsetV = ui.lerpDouble(9.0, 7.0, m)!;
        final capsuleHeight = dockBoxHeight - capsuleInsetV * 2;
        final capsuleRadius = capsuleHeight / 2;
        final labelReveal = (1.0 - m * 1.45).clamp(0.0, 1.0);
        final labelHeightFactor = (1.0 - m).clamp(0.0, 1.0);

        return Padding(
          padding: EdgeInsets.fromLTRB(
            hPad,
            0,
            hPad,
            bottomPadding > 0 ? bottomPadding : 14,
          ),
          child: Center(
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxBarWidth),
              child: SizedBox(
                key: _barKey,
                height: dockBoxHeight,
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

                            // BitChord volume-preserving liquid droplet stretch (STRETCH=0.16, SQUASH=0.50)
                            final slideWave = _slideController.isAnimating
                                ? math.sin(
                                    math.pi *
                                        (_slideController.value * 1.15)
                                            .clamp(0.0, 1.0),
                                  )
                                : 0.0;
                            final slideStretch = 0.16 *
                                (_slideDistance / 3.0).clamp(0.0, 1.0) *
                                slideWave;
                            final totalStretch =
                                math.max(_dragVelocityStretch, slideStretch);

                            final scaleX = 1.0 + totalStretch;
                            final scaleY = 1.0 - totalStretch * 0.50;

                            // Resting subtle pill rect (scales cleanly with minimized dock)
                            final restPillWidth =
                                (tabWidth - ui.lerpDouble(10.0, 8.0, m)!)
                                    .clamp(46.0, 106.0);
                            final restPillHeight =
                                (capsuleHeight - 12.0).clamp(38.0, 52.0);
                            final restPillTop =
                                (dockBoxHeight - restPillHeight) / 2;
                            final restPillLeft = (_currentPos * tabWidth +
                                    (tabWidth - restPillWidth) / 2)
                                .clamp(5.0, totalWidth - restPillWidth - 5.0);

                            // Active Liquid Glass droplet rect (inflates over icons when dragging/hovering/pulsing)
                            final dropletWidth =
                                (tabWidth * 1.02).clamp(56.0, 116.0) *
                                    ui.lerpDouble(0.88, 1.0, t)! *
                                    scaleX;
                            final dropletHeight = ui.lerpDouble(
                                  restPillHeight,
                                  ui.lerpDouble(74.0, 58.0, m)!,
                                  t,
                                )! *
                                scaleY;
                            final dropletTop =
                                (dockBoxHeight - dropletHeight) / 2;
                            final dropletLeft = (_currentPos * tabWidth +
                                    (tabWidth - dropletWidth) / 2)
                                .clamp(-2.0, totalWidth - dropletWidth + 2.0);

                            // Single source of truth for highlighted tab
                            final activeVisualIndex =
                                (_isDragging || _isHovering)
                                    ? _posToIndex(_currentPos)
                                    : widget.currentIndex;

                            // Compute exact screen-space rects for live Impeller GPU refraction
                            // on BOTH the floating outer capsule dock (always live while scrolling!)
                            // and the elevated hover/drag/tap droplet lens.
                            final barOrigin = _barGlobalOrigin();
                            final dockScreenRect = barOrigin != null
                                ? Rect.fromLTWH(
                                    barOrigin.dx,
                                    barOrigin.dy + capsuleInsetV,
                                    totalWidth,
                                    capsuleHeight,
                                  )
                                : null;
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
                                // LAYER 1: Live GPU Optical Refraction Floating Navbar Dock
                                // Uses the exact same screen-space SDF refraction + chromatic
                                // dispersion shader as the hover/drag pill so scrolling cards,
                                // rings, and charts visibly pass & bend behind the glass dock!
                                Positioned(
                                  left: 0,
                                  right: 0,
                                  top: capsuleInsetV,
                                  bottom: capsuleInsetV,
                                  child: _OpticalLiquidGlassDock(
                                    program: _program,
                                    screenRect: dockScreenRect,
                                    radius: capsuleRadius,
                                    isDark: isDark,
                                    dpr: dpr,
                                  ),
                                ),

                                // LAYER 2A: Elevated 3D Domed Liquid Glass Active Selection Pill
                                // Pure neutral optical glass lens at rest, morphing seamlessly
                                // into the GPU chromatic-refraction droplet (Layer 3) on tap/drag.
                                if (tClamped < 0.99)
                                  Positioned(
                                    left: restPillLeft,
                                    top: restPillTop,
                                    width: restPillWidth,
                                    height: restPillHeight,
                                    child: IgnorePointer(
                                      child: Opacity(
                                        opacity:
                                            (1.0 - tClamped).clamp(0.0, 1.0),
                                        child: Container(
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(
                                              restPillHeight / 2,
                                            ),
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.black.withValues(
                                                  alpha: isDark ? 0.38 : 0.09,
                                                ),
                                                blurRadius: 12,
                                                spreadRadius: -2,
                                                offset: const Offset(0, 3),
                                              ),
                                            ],
                                          ),
                                          child: CustomPaint(
                                            foregroundPainter:
                                                LiquidGlassRimPainter(
                                              borderRadius: restPillHeight / 2,
                                              isDark: isDark,
                                              intensity: 1.15,
                                              strokeWidth: 1.2,
                                            ),
                                            child: Container(
                                              decoration: BoxDecoration(
                                                borderRadius:
                                                    BorderRadius.circular(
                                                  restPillHeight / 2,
                                                ),
                                                gradient: LiquidGlassPalette
                                                    .activeLensGradient(
                                                  isDark: isDark,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),

                                // LAYER 2B: Tab Icons & Collapsing Labels
                                Positioned(
                                  left: 0,
                                  right: 0,
                                  top: capsuleInsetV,
                                  bottom: capsuleInsetV,
                                  child: Row(
                                    children:
                                        List.generate(widget.items.length, (i) {
                                      final item = widget.items[i];
                                      final isActive = i == activeVisualIndex;
                                      final activeTint =
                                          isActive ? c.accent : c.navInactive;
                                      final isProfileTab =
                                          i == widget.items.length - 1;
                                      final hasProfileAvatar = isProfileTab &&
                                          (widget.profileName
                                                  ?.trim()
                                                  .isNotEmpty ??
                                              false);

                                      final isJiggTab = i >= 0 && i <= 2;
                                      final animVal = (_bouncingTabIndex == i &&
                                              _iconBounceController.isAnimating)
                                          ? _iconBounceController.value
                                          : 0.0;
                                      // Jiggicons (tabs 0-2) already play rich intrinsic spring physics;
                                      // keep only a gentle tactile scale lift on them, and full bounce on Profile.
                                      final bounceScale = animVal > 0
                                          ? 1.0 +
                                              (isJiggTab ? 0.08 : 0.24) *
                                                  math.sin(animVal * math.pi) *
                                                  (1.0 - animVal * 0.35)
                                          : 1.0;
                                      final tiltAngle = 0.0;
                                      final liftY = 0.0;

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
                                                          name: widget
                                                              .profileName!,
                                                          avatarPath: widget
                                                                  .profileAvatarPath ??
                                                              '',
                                                          size: 25,
                                                          showBorder: true,
                                                          borderWidth: 1.8,
                                                          borderColor: isActive
                                                              ? c.accent
                                                              : (isDark
                                                                  ? Colors.white
                                                                      .withValues(
                                                                          alpha:
                                                                              0.35)
                                                                  : Colors
                                                                      .white),
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
                                            if (labelHeightFactor > 0.02)
                                              ClipRect(
                                                child: Align(
                                                  alignment: Alignment.topCenter,
                                                  heightFactor:
                                                      labelHeightFactor,
                                                  child: Opacity(
                                                    opacity: labelReveal,
                                                    child: Padding(
                                                      padding:
                                                          const EdgeInsets.only(
                                                        top: 3,
                                                      ),
                                                      child: Text(
                                                        item.label,
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        style: TextStyle(
                                                          fontSize: 11,
                                                          fontWeight: isActive
                                                              ? FontWeight.w700
                                                              : FontWeight.w500,
                                                          letterSpacing: -0.1,
                                                          color: activeTint,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                      );
                                    }),
                                  ),
                                ),

                                // LAYER 3 (TOP): Screen-space GPU Optical Liquid Glass Droplet
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
                                        pressIntensity:
                                            _isDragging ? 0.85 : 0.30,
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
      },
    );
  }

  Widget _buildNavIcon({
    required int index,
    required LiquidGlassNavItem item,
    required bool isActive,
    required Color color,
  }) {
    final jiggName = switch (index) {
      0 => 'heart',
      1 => 'dumbbell',
      2 => 'trophy',
      _ => null,
    };
    if (jiggName != null) {
      final ctrl =
          index < _jiggControllers.length ? _jiggControllers[index] : null;
      return TempoJiggIcon(
        jiggName,
        variant: isActive ? JiggIconVariant.solid : JiggIconVariant.outline,
        size: 24,
        color: color,
        controller: ctrl,
        trigger: JiggIconTrigger.none,
        fallbackIcon: isActive ? item.activeIcon : item.icon,
      );
    }
    return Icon(
      isActive ? item.activeIcon : item.icon,
      size: 24,
      color: color,
    );
  }
}

/// Live GPU-refracted floating outer navbar capsule using `shaders/liquid_glass_lens.frag`
/// so scrolled cards, rings, and colors visibly pass through and bend along the curved bevel,
/// matching the exact optical glass effect of the hover/drag pill.
class _OpticalLiquidGlassDock extends StatelessWidget {
  final ui.FragmentProgram? program;
  final Rect? screenRect;
  final double radius;
  final bool isDark;
  final double dpr;

  const _OpticalLiquidGlassDock({
    required this.program,
    required this.screenRect,
    required this.radius,
    required this.isDark,
    required this.dpr,
  });

  @override
  Widget build(BuildContext context) {
    final useLiveShader = program != null &&
        screenRect != null &&
        !screenRect!.isEmpty &&
        ui.ImageFilter.isShaderFilterSupported;

    ui.ImageFilter backdropFilter;
    if (useLiveShader) {
      final shader = program!.fragmentShader();
      shader.setFloat(2, screenRect!.left * dpr); // u_rectLeft
      shader.setFloat(3, screenRect!.top * dpr); // u_rectTop
      shader.setFloat(4, screenRect!.width * dpr); // u_rectWidth
      shader.setFloat(5, screenRect!.height * dpr); // u_rectHeight
      shader.setFloat(6, 1.0); // u_expansion (always active!)
      shader.setFloat(7, 15.0 * dpr); // u_bevel (wide curved rim refraction)
      shader.setFloat(8, 10.5 * dpr); // u_refract (live bending as content scrolls)
      shader.setFloat(9, 0.075); // u_dispersion (subtle chromatic edge shimmer)
      shader.setFloat(10, isDark ? 1.0 : 0.0); // u_isDark
      shader.setFloat(11, 0.14); // u_press (calm resting optical lens depth)
      backdropFilter = ui.ImageFilter.shader(shader);
    } else {
      backdropFilter = ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12);
    }

    // Balanced 75% frosted neutral glass veil over the live refracted backdrop:
    // substantial Liquid Glass presence & crisp icon contrast while scrolling
    // cards and colors still visibly refract & pass behind the capsule.
    final sheerVeil = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: isDark
          ? [
              const Color(0xFF2C2E36).withValues(alpha: 0.74),
              const Color(0xFF14151A).withValues(alpha: 0.78),
            ]
          : [
              Colors.white.withValues(alpha: 0.78),
              const Color(0xFFF4F6FB).withValues(alpha: 0.72),
            ],
    );

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.56)
                : Colors.black.withValues(alpha: 0.11),
            blurRadius: 30,
            spreadRadius: -3,
            offset: const Offset(0, 12),
          ),
          if (!isDark)
            BoxShadow(
              color: Colors.white.withValues(alpha: 0.32),
              blurRadius: 6,
              spreadRadius: -1,
              offset: const Offset(0, -1),
            ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(
          filter: backdropFilter,
          child: CustomPaint(
            foregroundPainter: LiquidGlassRimPainter(
              borderRadius: radius,
              isDark: isDark,
              intensity: 1.08,
              strokeWidth: 1.25,
            ),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(radius),
                gradient: sheerVeil,
              ),
            ),
          ),
        ),
      ),
    );
  }
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
