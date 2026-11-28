import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:jiggicons/jiggicons.dart';

import '../services/animation_speed_service.dart';
import '../services/appearance_service.dart';
import '../theme/app_colors.dart';
import 'bitchord_glass_lens.dart';
import 'bitchord_pill_motion.dart';
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

/// BitChord-calibrated floating Liquid Glass Navigation Bar powered by:
/// - **BitChord / Kyant0 7-band chromatic dispersion circular-dome shader**
///   (`shaders/liquid_glass_lens.frag`, `LENS_HEIGHT = 12 dp`, `LENS_AMOUNT = 14 dp`)
///   running inside a single zero-allocation pooled `RenderProxyBox`
///   (`BackdropFilterLayer`) with 0-frame lag `paint()` coordinates.
/// - **BitChord 120Hz `BitChordPillMotion`** (`1/240 s` semi-implicit Euler
///   substeps, decoupled X/Y lift springs, `PILL_GROW_HEIGHT = 9 dp` overhang,
///   `FOLLOW_TAU = 0.05 s` smooth finger/hover chase, edge rubber-band, and
///   2nd-derivative `±12%` acceleration squash).
/// - **Zero-rebuild glide pipeline:** Outer dock and tab icons stay isolated in
///   `RepaintBoundary` layers while the flat resting pill and lifted crystal
///   lens repaint directly from `BitChordPillMotion` (`0` `setState` calls and
///   `0` shader allocations per frame).
/// - **Full Appearance settings integration:** Honors `Reduce animation`,
///   `Reduce Dynamic Blur`, `Liquid Glass`, and `Better Performance for Glass`.
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

  late final BitChordPillMotion _motion;
  late final ValueNotifier<int> _activeVisualIndex;

  /// Per-tab SF-Symbols-inspired spring click bounce animation (Profile avatar)
  late final AnimationController _iconBounceController;
  int _bouncingTabIndex = -1;

  /// Per-tab Jiggicon spring controllers (Summary: heart, Workout: dumbbell, Progress: trophy)
  late final List<JiggIconController> _jiggControllers;

  /// Smooth scroll-driven liquid collapse (0.0 = expanded with labels, 1.0 = compact icons-only pill)
  late final AnimationController _minimizeController;
  late final Animation<double> _minimizeAnimation;

  Timer? _jiggPlayTimer;
  Timer? _holdLiftTimer;
  DateTime? _lastProfileTapTime;
  int? _lastTriggeredTab;
  int _lastHapticIndex = 0;

  // Low-slop pointer scrub state (eliminates Flutter's 18 dp horizontal drag deadzone)
  int? _activePointerId;
  Offset _pointerDownLocal = Offset.zero;
  bool _isScrubbing = false;
  bool _isHovering = false;
  double _currentTotalWidth = 0.0;

  @override
  void initState() {
    super.initState();
    _lastHapticIndex = widget.currentIndex;
    _activeVisualIndex = ValueNotifier<int>(widget.currentIndex);

    _motion = BitChordPillMotion(
      vsync: this,
      initialIndex: widget.currentIndex,
    )..reduceMotion = TempoAppearanceService.instance.reduceAnimation;

    _loadShader();

    final speed = TempoAnimationSpeedService.instance;
    _iconBounceController = AnimationController(
      vsync: this,
      duration: speed.scale(const Duration(milliseconds: 420)),
    );
    _jiggControllers = List<JiggIconController>.generate(
      widget.items.length,
      (_) => JiggIconController(),
    );

    _minimizeController = AnimationController(
      vsync: this,
      value: widget.minimized ? 1.0 : 0.0,
      duration: speed.scale(const Duration(milliseconds: 300)),
      reverseDuration: speed.scale(const Duration(milliseconds: 320)),
    );
    _minimizeAnimation = CurvedAnimation(
      parent: _minimizeController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeOutCubic,
    );

    speed.notifier.addListener(_syncSpeedDurations);
    TempoAppearanceService.instance.notifier.addListener(_syncAppearance);
  }

  void _syncAppearance() {
    if (!mounted) return;
    final reduced = TempoAppearanceService.instance.reduceAnimation ||
        MediaQuery.disableAnimationsOf(context);
    _motion.reduceMotion = reduced;
  }

  void _syncSpeedDurations() {
    final speed = TempoAnimationSpeedService.instance;
    _iconBounceController.duration =
        speed.scale(const Duration(milliseconds: 420));
    _minimizeController.duration =
        speed.scale(const Duration(milliseconds: 300));
    _minimizeController.reverseDuration =
        speed.scale(const Duration(milliseconds: 320));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _motion.reduceMotion = TempoAppearanceService.instance.reduceAnimation ||
        MediaQuery.disableAnimationsOf(context);
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
    if (oldWidget.currentIndex != widget.currentIndex && !_isScrubbing) {
      _lastHapticIndex = widget.currentIndex;
      if (!_isHovering) {
        _activeVisualIndex.value = widget.currentIndex;
        _motion.animateTo(widget.currentIndex);
      }
      if (_lastTriggeredTab != widget.currentIndex) {
        _triggerIconBounce(widget.currentIndex, delayed: true);
      }
      _lastTriggeredTab = null;
    }
    if (oldWidget.minimized != widget.minimized) {
      if (_motion.reduceMotion) {
        _minimizeController.value = widget.minimized ? 1.0 : 0.0;
      } else if (widget.minimized) {
        _minimizeController.forward();
      } else {
        _minimizeController.reverse();
      }
    }
  }

  @override
  void dispose() {
    TempoAnimationSpeedService.instance.notifier
        .removeListener(_syncSpeedDurations);
    TempoAppearanceService.instance.notifier.removeListener(_syncAppearance);
    _jiggPlayTimer?.cancel();
    _holdLiftTimer?.cancel();
    _motion.dispose();
    _activeVisualIndex.dispose();
    _iconBounceController.dispose();
    for (final ctrl in _jiggControllers) {
      ctrl.dispose();
    }
    _minimizeController.dispose();
    super.dispose();
  }

  void _triggerIconBounce(int index, {bool delayed = false}) {
    _jiggPlayTimer?.cancel();
    if (_motion.reduceMotion) return;
    void playNow() {
      if (!mounted) return;
      _bouncingTabIndex = index;
      _iconBounceController.forward(from: 0);
      if (index >= 0 && index < _jiggControllers.length) {
        _jiggControllers[index].play();
      }
    }

    if (!delayed) {
      playNow();
      return;
    }
    _jiggPlayTimer = Timer(const Duration(milliseconds: 70), playNow);
  }

  double _dxToUnclampedPos(double localDx, double totalWidth) {
    if (totalWidth <= 0 || widget.items.isEmpty) return 0.0;
    final tabWidth = totalWidth / widget.items.length;
    return (localDx - tabWidth * 0.5) / tabWidth;
  }

  int _posToIndex(double pos) =>
      pos.round().clamp(0, widget.items.length - 1);

  void _enterScrubMode(double localDx, double totalWidth) {
    if (_isScrubbing) return;
    _holdLiftTimer?.cancel();
    _jiggPlayTimer?.cancel();
    _isScrubbing = true;
    final rawPos = _dxToUnclampedPos(localDx, totalWidth);
    final nearest = _posToIndex(rawPos);
    _lastHapticIndex = nearest;
    _activeVisualIndex.value = nearest;
    _motion.startDrag();
    _motion.dragTo(rawPos, itemCount: widget.items.length);
    HapticFeedback.lightImpact();
  }

  void _handlePointerDown(PointerDownEvent event, double totalWidth) {
    if (_activePointerId != null) return;
    if (event.kind == PointerDeviceKind.mouse &&
        event.buttons != kPrimaryButton) {
      return;
    }
    _activePointerId = event.pointer;
    _pointerDownLocal = event.localPosition;
    _isScrubbing = false;
    _holdLiftTimer?.cancel();

    // Holding a thumb briefly (110 ms) lifts the BitChord crystal lens right
    // under your finger with zero horizontal movement required!
    _holdLiftTimer = Timer(const Duration(milliseconds: 110), () {
      if (!mounted || _activePointerId != event.pointer || _isScrubbing) return;
      _enterScrubMode(_pointerDownLocal.dx, _currentTotalWidth);
    });
  }

  void _handlePointerMove(PointerMoveEvent event, double totalWidth) {
    if (event.pointer != _activePointerId) return;
    final dx = (event.localPosition.dx - _pointerDownLocal.dx).abs();
    final dy = (event.localPosition.dy - _pointerDownLocal.dy).abs();

    if (!_isScrubbing) {
      // Responsive 6 dp threshold (3× faster engagement than Flutter's 18 dp drag slop)
      if (dx >= 6.0 && dx >= dy * 0.8) {
        _enterScrubMode(event.localPosition.dx, totalWidth);
      } else if (dy > 24.0) {
        _holdLiftTimer?.cancel();
      }
      return;
    }

    final rawPos = _dxToUnclampedPos(event.localPosition.dx, totalWidth);
    _motion.dragTo(rawPos, itemCount: widget.items.length);

    final nearest = _posToIndex(rawPos);
    if (nearest != _lastHapticIndex) {
      _lastHapticIndex = nearest;
      _activeVisualIndex.value = nearest;
      HapticFeedback.selectionClick();
      _triggerIconBounce(nearest);
    }
  }

  void _handlePointerUp(PointerUpEvent event, double totalWidth) {
    if (event.pointer != _activePointerId) return;
    _holdLiftTimer?.cancel();
    _activePointerId = null;

    if (_isScrubbing) {
      _isScrubbing = false;
      // Match BitChord (FloatingTabBar.kt:916): commit the exact tab under the
      // finger on lift so fast flicks always land where you release, while the
      // spring glides the lifted crystal lens smoothly into that slot!
      final targetIndex = _posToIndex(
        _dxToUnclampedPos(event.localPosition.dx, totalWidth),
      );
      _activeVisualIndex.value = targetIndex;
      _motion.release(targetIndex);
      if (targetIndex != widget.currentIndex) {
        _lastTriggeredTab = targetIndex;
        _triggerIconBounce(targetIndex, delayed: true);
        widget.onTap(targetIndex);
      } else {
        _triggerIconBounce(targetIndex);
      }
      return;
    }

    _handleTapAt(event.localPosition.dx, totalWidth);
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    if (event.pointer != _activePointerId) return;
    _holdLiftTimer?.cancel();
    _activePointerId = null;
    if (_isScrubbing) {
      _isScrubbing = false;
      _activeVisualIndex.value = widget.currentIndex;
      _motion.release(widget.currentIndex);
    }
  }

  void _handleTapAt(double localDx, double totalWidth) {
    final index = _posToIndex(_dxToUnclampedPos(localDx, totalWidth));
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

    final switchingTab = index != widget.currentIndex;
    HapticFeedback.selectionClick();
    _lastTriggeredTab = index;
    _activeVisualIndex.value = index;
    if (switchingTab) {
      // BitChord behavior: tapping another tab lifts the crystal lens & glides!
      _motion.animateTo(index);
      _triggerIconBounce(index, delayed: true);
      widget.onTap(index);
    } else {
      _triggerIconBounce(index);
    }
  }

  // Only allow real pointer hover (mouse / trackpad / stylus) — never touch!
  bool _isPointerHoverDevice(PointerEvent event) =>
      event.kind != PointerDeviceKind.touch;

  void _handleHoverEnter(PointerEnterEvent event, double totalWidth) {
    if (!_isPointerHoverDevice(event) || _isScrubbing) return;
    _isHovering = true;
    final rawPos = _dxToUnclampedPos(event.localPosition.dx, totalWidth);
    _motion.startDrag();
    _motion.dragTo(rawPos, itemCount: widget.items.length);
    _activeVisualIndex.value = _posToIndex(rawPos);
  }

  void _handleHoverMove(PointerHoverEvent event, double totalWidth) {
    if (!_isPointerHoverDevice(event) || _isScrubbing) return;
    _isHovering = true;
    final rawPos = _dxToUnclampedPos(event.localPosition.dx, totalWidth);
    _motion.dragTo(rawPos, itemCount: widget.items.length);
    _activeVisualIndex.value = _posToIndex(rawPos);
  }

  void _handleHoverExit(PointerExitEvent event) {
    if (!_isHovering) return;
    _isHovering = false;
    if (!_isScrubbing) {
      _activeVisualIndex.value = widget.currentIndex;
      _motion.release(widget.currentIndex);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final isDark = c.isDark;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return ValueListenableBuilder<TempoAppearanceSettings>(
      valueListenable: TempoAppearanceService.instance.notifier,
      builder: (context, appearance, _) {
        _motion.reduceMotion = appearance.reduceAnimation ||
            MediaQuery.disableAnimationsOf(context);

        return AnimatedBuilder(
          animation: _minimizeAnimation,
          builder: (context, _) {
            final m = _minimizeAnimation.value.clamp(0.0, 1.0);
            final hPad = ui.lerpDouble(18.0, 48.0, m)!;
            final maxBarWidth = ui.lerpDouble(460.0, 272.0, m)!;
            final capsuleHeight = ui.lerpDouble(64.0, 52.0, m)!;
            final capsuleRadius = capsuleHeight * 0.5;
            final growHeight = ui.lerpDouble(
              BitChordPillMotion.pillGrowHeightDp,
              BitChordPillMotion.pillGrowHeightMinimizedDp,
              m,
            )!;
            // Extra vertical allowance around the capsule so the lifted lens can
            // stand boldly past the top and bottom edges of the dock (+9 dp).
            final capsuleInsetV = ui.lerpDouble(10.0, 8.0, m)!;
            final dockBoxHeight = capsuleHeight + capsuleInsetV * 2.0;
            final labelReveal = (1.0 - m * 1.45).clamp(0.0, 1.0);
            final labelHeightFactor = (1.0 - m).clamp(0.0, 1.0);

            return Padding(
              padding: EdgeInsets.fromLTRB(
                hPad,
                0,
                hPad,
                bottomPadding > 0 ? bottomPadding : 12,
              ),
              child: Center(
                heightFactor: 1,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxBarWidth),
                  child: SizedBox(
                    height: dockBoxHeight,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final totalWidth = constraints.maxWidth;
                        _currentTotalWidth = totalWidth;
                        final tabWidth = totalWidth / widget.items.length;
                        _motion.stepDp = tabWidth;

                        const restInset = 4.0;
                        final restSize = Size(
                          (tabWidth - restInset * 2.0).clamp(44.0, 140.0),
                          (capsuleHeight - restInset * 2.0).clamp(38.0, 58.0),
                        );
                        final liftedH = capsuleHeight + growHeight;
                        final liftedW = (liftedH * restSize.width / restSize.height)
                            .clamp(restSize.width + 10.0, tabWidth * 1.24);
                        final liftedSize = Size(liftedW, liftedH);

                        final showLiftedGlass =
                            appearance.useLiquidGlass && !appearance.reduceAnimation;

                        return MouseRegion(
                          onEnter: (e) => _handleHoverEnter(e, totalWidth),
                          onHover: (e) => _handleHoverMove(e, totalWidth),
                          onExit: _handleHoverExit,
                          child: Listener(
                            behavior: HitTestBehavior.opaque,
                            onPointerDown: (e) =>
                                _handlePointerDown(e, totalWidth),
                            onPointerMove: (e) =>
                                _handlePointerMove(e, totalWidth),
                            onPointerUp: (e) =>
                                _handlePointerUp(e, totalWidth),
                            onPointerCancel: _handlePointerCancel,
                            child: Stack(
                              clipBehavior: Clip.none,
                              alignment: Alignment.center,
                              children: [
                                // LAYER 1 (STATIC): BitChord Liquid Glass Outer Capsule
                                Positioned(
                                  left: 0,
                                  right: 0,
                                  top: capsuleInsetV,
                                  bottom: capsuleInsetV,
                                  child: RepaintBoundary(
                                    child: _OpticalLiquidGlassDock(
                                      radius: capsuleRadius,
                                      isDark: isDark,
                                      dpr: dpr,
                                      program: _program,
                                      appearance: appearance,
                                      cardColor: c.card,
                                      borderColor: c.cardBorder,
                                    ),
                                  ),
                                ),

                                // LAYER 2A (PAINT-ONLY): Resting Flat Selection Pill
                                // Repaints directly from `_motion` with 0 widget rebuilds!
                                Positioned.fill(
                                  child: IgnorePointer(
                                    child: CustomPaint(
                                      painter: _FlatSelectionPillPainter(
                                        motion: _motion,
                                        tabWidth: tabWidth,
                                        itemCount: widget.items.length,
                                        dockBoxHeight: dockBoxHeight,
                                        restSize: restSize,
                                        liftedSize: liftedSize,
                                        isDark: isDark,
                                        clearWhileLifted:
                                            appearance.useGlassRefraction &&
                                                showLiftedGlass,
                                      ),
                                    ),
                                  ),
                                ),

                                // LAYER 2B (ISOLATED): Tab Icons & Collapsing Labels
                                // Only updates when the highlighted integer tab changes!
                                Positioned(
                                  left: 0,
                                  right: 0,
                                  top: capsuleInsetV,
                                  bottom: capsuleInsetV,
                                  child: RepaintBoundary(
                                    child: ValueListenableBuilder<int>(
                                      valueListenable: _activeVisualIndex,
                                      builder: (context, activeIdx, _) {
                                        return AnimatedBuilder(
                                          animation: _iconBounceController,
                                          builder: (context, _) {
                                            return Row(
                                              children: List.generate(
                                                widget.items.length,
                                                (i) => _buildTabCell(
                                                  index: i,
                                                  isActive: i == activeIdx,
                                                  c: c,
                                                  isDark: isDark,
                                                  labelHeightFactor:
                                                      labelHeightFactor,
                                                  labelReveal: labelReveal,
                                                ),
                                              ),
                                            );
                                          },
                                        );
                                      },
                                    ),
                                  ),
                                ),

                                // LAYER 3 (TOP, ZERO-ALLOCATION POOLED GPU LENS):
                                // BitChord 7-band chromatic dispersion crystal droplet!
                                // Listens directly to `_motion` in RenderObject -> 0 rebuilds!
                                if (showLiftedGlass)
                                  Positioned.fill(
                                    child: IgnorePointer(
                                      child: BitChordGlassLensBox(
                                        program: _program,
                                        repaint: _motion,
                                        isDark: isDark,
                                        dpr: dpr,
                                        useRefractionShader:
                                            appearance.useGlassRefraction,
                                        frameBuilder: (_) {
                                          if (_motion.isFlat ||
                                              tabWidth <= 0) {
                                            return BitChordLensFrame.inactive;
                                          }
                                          final liveSize = _motion.liveSize(
                                            restSize,
                                            liftedSize,
                                          );
                                          final cx =
                                              (_motion.position + 0.5) *
                                                  tabWidth;
                                          final cy = dockBoxHeight * 0.5;
                                          final localRect = Rect.fromCenter(
                                            center: Offset(cx, cy),
                                            width: liveSize.width,
                                            height: liveSize.height,
                                          );
                                          final presence =
                                              _motion.glassPresence;
                                          final material = _motion.material;
                                          final rimAlpha =
                                              (material * _motion.rimFactor)
                                                  .clamp(0.0, 1.0);
                                          return BitChordLensFrame(
                                            active: true,
                                            rect: localRect,
                                            borderRadius:
                                                liveSize.height * 0.5,
                                            refractionHeightDp:
                                                12.0 * presence,
                                            refractionAmountDp:
                                                14.0 * material,
                                            depthEffect: 0.45,
                                            aberration: 1.0,
                                            rimAlpha: rimAlpha,
                                            shadowAlpha: rimAlpha,
                                            material: material,
                                          );
                                        },
                                      ),
                                    ),
                                  ),
                              ],
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
      },
    );
  }

  Widget _buildTabCell({
    required int index,
    required bool isActive,
    required AppColors c,
    required bool isDark,
    required double labelHeightFactor,
    required double labelReveal,
  }) {
    final item = widget.items[index];
    final activeTint = isActive ? c.accent : c.navInactive;
    final isProfileTab = index == widget.items.length - 1;
    final hasProfileAvatar =
        isProfileTab && (widget.profileName?.trim().isNotEmpty ?? false);

    final isJiggTab = index >= 0 && index <= 2;
    final animVal =
        (_bouncingTabIndex == index && _iconBounceController.isAnimating)
            ? _iconBounceController.value
            : 0.0;
    final bounceScale = (!isJiggTab && animVal > 0)
        ? 1.0 +
            0.24 * math.sin(animVal * math.pi) * (1.0 - animVal * 0.35)
        : 1.0;

    return Expanded(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Transform.scale(
            scale: bounceScale,
            child: hasProfileAvatar
                ? LocalProfileAvatar(
                    name: widget.profileName!,
                    avatarPath: widget.profileAvatarPath ?? '',
                    size: 25,
                    showBorder: true,
                    borderWidth: 1.8,
                    borderColor: isActive
                        ? c.accent
                        : (isDark
                            ? Colors.white.withValues(alpha: 0.35)
                            : Colors.white),
                    showShadow: false,
                  )
                : _buildNavIcon(
                    index: index,
                    item: item,
                    isActive: isActive,
                    color: activeTint,
                  ),
          ),
          if (labelHeightFactor > 0.02)
            ClipRect(
              child: Align(
                alignment: Alignment.topCenter,
                heightFactor: labelHeightFactor,
                child: Opacity(
                  opacity: labelReveal,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      item.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight:
                            isActive ? FontWeight.w700 : FontWeight.w500,
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

/// Outer floating navbar capsule calibrated to BitChord's `Modifier.liquidGlass`:
/// - Full Liquid Glass: vibrant `sigma = 8.5` translucent blur + live optical
///   dome refraction (`shaders/liquid_glass_lens.frag`) + translucent BitChord
///   tint (`#121212 @ 36%` Dark / `#FAFAFA @ 38%` Light) + crisp 45° specular rim.
/// - Better Performance for Glass: smooth `sigma = 16.0` frosted blur without
///   the refraction shader + matching translucent tint & specular rim.
/// - Liquid Glass OFF: classic soft `sigma = 18.0` frosted blur.
/// - Reduce Dynamic Blur ON: zero `BackdropFilter`, clean opaque `c.card` capsule.
class _OpticalLiquidGlassDock extends StatelessWidget {
  final double radius;
  final bool isDark;
  final double dpr;
  final ui.FragmentProgram? program;
  final TempoAppearanceSettings appearance;
  final Color cardColor;
  final Color borderColor;

  const _OpticalLiquidGlassDock({
    required this.radius,
    required this.isDark,
    required this.dpr,
    required this.program,
    required this.appearance,
    required this.cardColor,
    required this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    if (appearance.reduceDynamicBlur) {
      return Container(
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.10)
                : borderColor,
            width: 0.7,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.42 : 0.08),
              blurRadius: 20,
              spreadRadius: -3,
              offset: const Offset(0, 8),
            ),
          ],
        ),
      );
    }

    // Exact BitChord LiquidGlass.kt blur calibration:
    // 8.5 dp when optical lens refraction is active (so colors behind glow
    // vividly through the glass!), 16 dp frosted fallback under Better Performance.
    final blurSigma = !appearance.liquidGlass
        ? 18.0
        : (appearance.betterGlassPerformance ? 16.0 : 8.5);

    final surfaceTint = isDark
        ? const Color(0xFF121212).withValues(alpha: 0.36)
        : const Color(0xFFFAFAFA).withValues(alpha: 0.38);

    final inner = Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        color: surfaceTint,
        border: Border.all(
          color: appearance.liquidGlass
              ? (isDark
                  ? Colors.white.withValues(alpha: 0.14)
                  : Colors.white.withValues(alpha: 0.62))
              : borderColor,
          width: appearance.liquidGlass ? 0.6 : 0.8,
        ),
      ),
    );

    final rimmedInner = appearance.liquidGlass
        ? TempoTouchLightEffect(
            borderRadius: radius,
            intensity: 0.85,
            scatterGain: 0.92,
            child: CustomPaint(
              foregroundPainter: LiquidGlassRimPainter(
                borderRadius: radius,
                isDark: isDark,
                intensity: isDark ? 1.05 : 0.96,
                strokeWidth: 1.05,
                showTopMeniscus: false,
              ),
              child: inner,
            ),
          )
        : inner;

    final refractedOrPlain = appearance.useGlassRefraction
        ? BitChordGlassLensBox(
            program: program,
            isDark: isDark,
            dpr: dpr,
            useRefractionShader: true,
            frameBuilder: (sz) {
              if (sz.isEmpty) return BitChordLensFrame.inactive;
              return BitChordLensFrame(
                active: true,
                rect: Offset.zero & sz,
                borderRadius: radius,
                refractionHeightDp: 16.0,
                refractionAmountDp: 18.0,
                depthEffect: 0.45,
                aberration: 0.45,
                rimAlpha: 0.35,
                shadowAlpha: 0.0,
                material: 1.0,
              );
            },
            child: rimmedInner,
          )
        : rimmedInner;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.48)
                : Colors.black.withValues(alpha: 0.09),
            blurRadius: 24,
            spreadRadius: -3,
            offset: const Offset(0, 9),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(
            sigmaX: blurSigma,
            sigmaY: blurSigma,
            tileMode: ui.TileMode.clamp,
          ),
          child: refractedOrPlain,
        ),
      ),
    );
  }
}

/// Paint-only resting selection pill driven directly by [BitChordPillMotion].
/// Fades smoothly out (`1 - material`) when the crystal refraction lens lifts
/// so the lifted lens stays 100% transparent glass (exact BitChord handoff).
class _FlatSelectionPillPainter extends CustomPainter {
  final BitChordPillMotion motion;
  final double tabWidth;
  final int itemCount;
  final double dockBoxHeight;
  final Size restSize;
  final Size liftedSize;
  final bool isDark;
  final bool clearWhileLifted;

  _FlatSelectionPillPainter({
    required this.motion,
    required this.tabWidth,
    required this.itemCount,
    required this.dockBoxHeight,
    required this.restSize,
    required this.liftedSize,
    required this.isDark,
    required this.clearWhileLifted,
  }) : super(repaint: motion);

  @override
  void paint(Canvas canvas, Size size) {
    final alphaFactor =
        clearWhileLifted ? (1.0 - motion.material).clamp(0.0, 1.0) : 1.0;
    if (alphaFactor <= 0.004 || tabWidth <= 0) return;

    final liveSize = motion.liveSize(restSize, liftedSize);
    final cx = (motion.position + 0.5) * tabWidth;
    final cy = dockBoxHeight * 0.5;
    final rect = Rect.fromCenter(
      center: Offset(cx, cy),
      width: liveSize.width,
      height: liveSize.height,
    );
    final rrect = RRect.fromRectAndRadius(
      rect,
      Radius.circular(liveSize.height * 0.5),
    );

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: isDark
            ? [
                Colors.white.withValues(alpha: 0.16 * alphaFactor),
                Colors.white.withValues(alpha: 0.12 * alphaFactor),
                Colors.white.withValues(alpha: 0.14 * alphaFactor),
              ]
            : [
                const Color(0xFF1C1C1E).withValues(alpha: 0.125 * alphaFactor),
                const Color(0xFF1C1C1E).withValues(alpha: 0.095 * alphaFactor),
                const Color(0xFF1C1C1E).withValues(alpha: 0.110 * alphaFactor),
              ],
        stops: const [0.0, 0.52, 1.0],
      ).createShader(rect);
    canvas.drawRRect(rrect, fillPaint);

    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.65
      ..color = isDark
          ? Colors.white.withValues(alpha: 0.11 * alphaFactor)
          : Colors.black.withValues(alpha: 0.045 * alphaFactor);
    canvas.drawRRect(rrect, borderPaint);
  }

  @override
  bool shouldRepaint(covariant _FlatSelectionPillPainter oldDelegate) =>
      oldDelegate.tabWidth != tabWidth ||
      oldDelegate.dockBoxHeight != dockBoxHeight ||
      oldDelegate.restSize != restSize ||
      oldDelegate.liftedSize != liftedSize ||
      oldDelegate.isDark != isDark ||
      oldDelegate.clearWhileLifted != clearWhileLifted;
}
