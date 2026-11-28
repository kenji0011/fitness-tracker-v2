import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../theme/app_colors.dart';
import '../services/animation_speed_service.dart';
import '../services/appearance_service.dart';
import 'liquid_glass_surface.dart';

/// Impeller-native Liquid Glass exercise video player built directly on
/// `video_player` (replacing stock Material `Chewie` controls).
///
/// Features:
/// - `24 dp` rounded cinema stage with specular `LiquidGlassRimPainter` bevel.
/// - Auto-hiding (`3.0s`) floating smoked-glass HUD with zero `BackdropFilter`
///   wrapped in `Opacity` (locked 120Hz Impeller playback).
/// - Center `-5s` / Play-Pause droplet / `+5s` cluster + double-tap left/right
///   seek gestures with frosted feedback flash.
/// - Playback speed cycling (`0.5x`, `0.75x`, `1.0x`, `1.25x`), loop toggle,
///   mute toggle, custom Tempo Orange liquid scrubber, and zero-reload shared
///   controller fullscreen viewer.
class TempoLiquidVideoPlayer extends StatefulWidget {
  final String? assetPath;
  final String exerciseName;
  final bool autoPlay;
  final bool initialLooping;
  final double borderRadius;

  /// Optional external controller (used by fullscreen and widget tests).
  final VideoPlayerController? externalController;

  const TempoLiquidVideoPlayer({
    super.key,
    required this.assetPath,
    required this.exerciseName,
    this.autoPlay = false,
    this.initialLooping = true,
    this.borderRadius = 24,
    this.externalController,
  });

  @override
  State<TempoLiquidVideoPlayer> createState() => _TempoLiquidVideoPlayerState();
}

class _TempoLiquidVideoPlayerState extends State<TempoLiquidVideoPlayer> {
  static const List<double> _speeds = [0.5, 0.75, 1.0, 1.25];

  VideoPlayerController? _controller;
  bool _ownsController = false;
  bool _initializing = true;
  bool _hasError = false;
  bool _showHud = true;
  bool _isLooping = true;
  bool _isMuted = false;
  int _speedIndex = 2; // 1.0x
  bool _isScrubbing = false;
  double _scrubFraction = 0.0;

  Timer? _hideTimer;
  Timer? _seekFlashTimer;
  int? _seekFlashDelta; // -5 or +5

  @override
  void initState() {
    super.initState();
    _isLooping = widget.initialLooping;
    _initController();
  }

  @override
  void didUpdateWidget(covariant TempoLiquidVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.assetPath != widget.assetPath &&
        widget.externalController == null) {
      _disposeOwnedController();
      _initController();
    }
  }

  Future<void> _initController() async {
    _hideTimer?.cancel();
    if (widget.externalController != null) {
      _controller = widget.externalController;
      _ownsController = false;
      _controller!.addListener(_onVideoTick);
      if (mounted) {
        setState(() {
          _initializing = !_controller!.value.isInitialized;
          _hasError = _controller!.value.hasError;
          _isLooping = _controller!.value.isLooping;
          _isMuted = _controller!.value.volume <= 0.01;
        });
      }
      return;
    }

    final path = widget.assetPath?.trim() ?? '';
    if (path.isEmpty) {
      if (mounted) {
        setState(() {
          _initializing = false;
          _hasError = true;
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        _initializing = true;
        _hasError = false;
      });
    }

    try {
      final ctrl = VideoPlayerController.asset(path);
      _controller = ctrl;
      _ownsController = true;
      await ctrl.initialize();
      await ctrl.setLooping(_isLooping);
      await ctrl.setPlaybackSpeed(_speeds[_speedIndex]);
      ctrl.addListener(_onVideoTick);
      if (widget.autoPlay) {
        await ctrl.play();
        _scheduleAutoHide();
      }
      if (mounted) {
        setState(() {
          _initializing = false;
          _hasError = false;
        });
      }
    } catch (_) {
      _disposeOwnedController();
      if (mounted) {
        setState(() {
          _initializing = false;
          _hasError = true;
        });
      }
    }
  }

  void _disposeOwnedController() {
    _controller?.removeListener(_onVideoTick);
    if (_ownsController) {
      _controller?.dispose();
    }
    _controller = null;
    _ownsController = false;
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _seekFlashTimer?.cancel();
    _disposeOwnedController();
    super.dispose();
  }

  void _onVideoTick() {
    if (!mounted) return;
    setState(() {});
  }

  void _scheduleAutoHide() {
    _hideTimer?.cancel();
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isPlaying || _isScrubbing) return;
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && (_controller?.value.isPlaying ?? false) && !_isScrubbing) {
        setState(() => _showHud = false);
      }
    });
  }

  void _toggleHud() {
    setState(() => _showHud = !_showHud);
    if (_showHud) {
      _scheduleAutoHide();
    } else {
      _hideTimer?.cancel();
    }
  }

  Future<void> _togglePlayPause() async {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized) return;
    HapticFeedback.selectionClick();
    if (ctrl.value.isPlaying) {
      await ctrl.pause();
      _hideTimer?.cancel();
      if (mounted) setState(() => _showHud = true);
    } else {
      if (ctrl.value.duration > Duration.zero &&
          ctrl.value.position >= ctrl.value.duration - const Duration(milliseconds: 150)) {
        await ctrl.seekTo(Duration.zero);
      }
      await ctrl.play();
      if (mounted) setState(() => _showHud = true);
      _scheduleAutoHide();
    }
  }

  Future<void> _seekRelative(int deltaSeconds, {bool showFlash = false}) async {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized) return;
    HapticFeedback.selectionClick();
    final dur = ctrl.value.duration;
    final targetMs = (ctrl.value.position.inMilliseconds + deltaSeconds * 1000)
        .clamp(0, dur.inMilliseconds);
    await ctrl.seekTo(Duration(milliseconds: targetMs));
    if (showFlash && mounted) {
      _seekFlashTimer?.cancel();
      setState(() => _seekFlashDelta = deltaSeconds);
      _seekFlashTimer = Timer(const Duration(milliseconds: 620), () {
        if (mounted) setState(() => _seekFlashDelta = null);
      });
    }
    _scheduleAutoHide();
  }

  Future<void> _cycleSpeed() async {
    HapticFeedback.selectionClick();
    final nextIdx = (_speedIndex + 1) % _speeds.length;
    setState(() => _speedIndex = nextIdx);
    final ctrl = _controller;
    if (ctrl != null && ctrl.value.isInitialized) {
      await ctrl.setPlaybackSpeed(_speeds[nextIdx]);
    }
    _scheduleAutoHide();
  }

  Future<void> _toggleLoop() async {
    HapticFeedback.selectionClick();
    final next = !_isLooping;
    setState(() => _isLooping = next);
    final ctrl = _controller;
    if (ctrl != null && ctrl.value.isInitialized) {
      await ctrl.setLooping(next);
    }
    _scheduleAutoHide();
  }

  Future<void> _toggleMute() async {
    HapticFeedback.selectionClick();
    final next = !_isMuted;
    setState(() => _isMuted = next);
    final ctrl = _controller;
    if (ctrl != null && ctrl.value.isInitialized) {
      await ctrl.setVolume(next ? 0.0 : 1.0);
    }
    _scheduleAutoHide();
  }

  Future<void> _openFullscreen() async {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized) return;
    HapticFeedback.selectionClick();
    _hideTimer?.cancel();
    await Navigator.of(context).push<void>(
      PageRouteBuilder<void>(
        opaque: true,
        transitionDuration: TempoAnimationSpeedService.instance.scale(
          const Duration(milliseconds: 240),
        ),
        reverseTransitionDuration: TempoAnimationSpeedService.instance.scale(
          const Duration(milliseconds: 210),
        ),
        pageBuilder: (_, __, ___) => _TempoFullscreenVideoScreen(
          controller: ctrl,
          exerciseName: widget.exerciseName,
          initialSpeedIndex: _speedIndex,
          initialLooping: _isLooping,
          initialMuted: _isMuted,
          onStateSync: (speedIdx, looping, muted) {
            if (!mounted) return;
            setState(() {
              _speedIndex = speedIdx;
              _isLooping = looping;
              _isMuted = muted;
            });
          },
        ),
        transitionsBuilder: (_, anim, __, child) {
          final curved = CurvedAnimation(
            parent: anim,
            curve: Curves.easeOutCubic,
          );
          return ScaleTransition(
            scale: Tween<double>(begin: 0.94, end: 1.0).animate(curved),
            child: child,
          );
        },
      ),
    );
    if (mounted) {
      setState(() => _showHud = true);
      _scheduleAutoHide();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final useGlass = TempoAppearanceService.instance.value.liquidGlass;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(widget.borderRadius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: c.isDark ? 0.42 : 0.14),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(widget.borderRadius),
        child: AspectRatio(
          aspectRatio: _resolvedAspectRatio(),
          child: CustomPaint(
            foregroundPainter: useGlass
                ? LiquidGlassRimPainter(
                    borderRadius: widget.borderRadius,
                    isDark: true,
                    intensity: 0.92,
                    strokeWidth: 1.2,
                    showTopMeniscus: false,
                  )
                : null,
            child: _buildStage(c),
          ),
        ),
      ),
    );
  }

  double _resolvedAspectRatio() {
    final ctrl = _controller;
    if (ctrl != null && ctrl.value.isInitialized && ctrl.value.aspectRatio > 0) {
      return ctrl.value.aspectRatio.clamp(1.15, 2.0);
    }
    return 16 / 9;
  }

  Widget _buildStage(AppColors c) {
    if (_initializing) {
      return Container(
        color: c.isDark ? const Color(0xFF101218) : const Color(0xFF161922),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CupertinoActivityIndicator(color: c.accent, radius: 13),
              const SizedBox(height: 10),
              Text(
                'Loading demonstration',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.72),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final ctrl = _controller;
    if (_hasError || ctrl == null || !ctrl.value.isInitialized) {
      return Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: c.isDark
                ? const [Color(0xFF1B1D24), Color(0xFF111318)]
                : const [Color(0xFF232732), Color(0xFF161922)],
          ),
        ),
        padding: const EdgeInsets.all(22),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.10),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.22),
                  width: 0.9,
                ),
              ),
              child: Icon(
                CupertinoIcons.play_rectangle_fill,
                color: c.accent,
                size: 24,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              widget.exerciseName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Form video preview unavailable',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.65),
                fontSize: 12.5,
              ),
            ),
          ],
        ),
      );
    }

    return _VideoPlayerOverlayShell(
      controller: ctrl,
      showHud: _showHud,
      isLooping: _isLooping,
      isMuted: _isMuted,
      speed: _speeds[_speedIndex],
      isScrubbing: _isScrubbing,
      scrubFraction: _scrubFraction,
      seekFlashDelta: _seekFlashDelta,
      isFullscreen: false,
      onToggleHud: _toggleHud,
      onTogglePlayPause: _togglePlayPause,
      onSeekRelative: (d, {bool flash = false}) =>
          _seekRelative(d, showFlash: flash),
      onCycleSpeed: _cycleSpeed,
      onToggleLoop: _toggleLoop,
      onToggleMute: _toggleMute,
      onToggleFullscreen: _openFullscreen,
      onScrubStart: (f) {
        _hideTimer?.cancel();
        setState(() {
          _isScrubbing = true;
          _scrubFraction = f;
        });
      },
      onScrubUpdate: (f) {
        setState(() => _scrubFraction = f);
      },
      onScrubEnd: (f) async {
        final dur = ctrl.value.duration;
        if (dur > Duration.zero) {
          await ctrl.seekTo(
            Duration(milliseconds: (dur.inMilliseconds * f).round()),
          );
        }
        if (mounted) {
          setState(() => _isScrubbing = false);
          _scheduleAutoHide();
        }
      },
    );
  }
}

/// Shared zero-reload video canvas + Liquid Glass HUD shell reused across inline
/// and fullscreen players. Never wraps `BackdropFilter` inside `Opacity`.
class _VideoPlayerOverlayShell extends StatelessWidget {
  final VideoPlayerController controller;
  final bool showHud;
  final bool isLooping;
  final bool isMuted;
  final double speed;
  final bool isScrubbing;
  final double scrubFraction;
  final int? seekFlashDelta;
  final bool isFullscreen;
  final VoidCallback onToggleHud;
  final VoidCallback onTogglePlayPause;
  final void Function(int deltaSeconds, {bool flash}) onSeekRelative;
  final VoidCallback onCycleSpeed;
  final VoidCallback onToggleLoop;
  final VoidCallback onToggleMute;
  final VoidCallback onToggleFullscreen;
  final ValueChanged<double> onScrubStart;
  final ValueChanged<double> onScrubUpdate;
  final ValueChanged<double> onScrubEnd;

  const _VideoPlayerOverlayShell({
    required this.controller,
    required this.showHud,
    required this.isLooping,
    required this.isMuted,
    required this.speed,
    required this.isScrubbing,
    required this.scrubFraction,
    required this.seekFlashDelta,
    required this.isFullscreen,
    required this.onToggleHud,
    required this.onTogglePlayPause,
    required this.onSeekRelative,
    required this.onCycleSpeed,
    required this.onToggleLoop,
    required this.onToggleMute,
    required this.onToggleFullscreen,
    required this.onScrubStart,
    required this.onScrubUpdate,
    required this.onScrubEnd,
  });

  String _formatSpeed(double s) {
    if (s == 1.0) return '1x';
    if (s == 0.5) return '0.5x';
    return '${s}x';
  }

  String _formatDuration(Duration d) {
    final totalSec = d.inSeconds.clamp(0, 35999);
    final m = totalSec ~/ 60;
    final s = totalSec % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final val = controller.value;
    final durMs = val.duration.inMilliseconds;
    final posMs = val.position.inMilliseconds.clamp(0, durMs > 0 ? durMs : 1);
    final liveFraction = durMs > 0 ? (posMs / durMs).clamp(0.0, 1.0) : 0.0;
    final progress = isScrubbing ? scrubFraction : liveFraction;
    final displayPosition = isScrubbing && durMs > 0
        ? Duration(milliseconds: (durMs * scrubFraction).round())
        : val.position;

    return Container(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Live Video Surface
          Center(
            child: AspectRatio(
              aspectRatio:
                  val.aspectRatio > 0 ? val.aspectRatio : (16 / 9),
              child: VideoPlayer(controller),
            ),
          ),

          // 2. Tap / Double-Tap Gesture Surface (left = -5s, right = +5s)
          Positioned.fill(
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: onToggleHud,
                    onDoubleTap: () => onSeekRelative(-5, flash: true),
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: onToggleHud,
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: onToggleHud,
                    onDoubleTap: () => onSeekRelative(5, flash: true),
                  ),
                ),
              ],
            ),
          ),

          // 3. Double-tap +/-5s Seek Flash Badge
          if (seekFlashDelta != null)
            Align(
              alignment: seekFlashDelta! < 0
                  ? const Alignment(-0.55, 0.0)
                  : const Alignment(0.55, 0.0),
              child: _HudGlassPill(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      seekFlashDelta! < 0
                          ? Icons.replay_5_rounded
                          : Icons.forward_5_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      seekFlashDelta! < 0 ? '-5s' : '+5s',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // 4. Floating Liquid Glass HUD (zero BackdropFilter inside Opacity)
          Positioned.fill(
            child: IgnorePointer(
              ignoring: !showHud,
              child: AnimatedOpacity(
                opacity: showHud ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.46),
                        Colors.black.withValues(alpha: 0.08),
                        Colors.black.withValues(alpha: 0.52),
                      ],
                      stops: const [0.0, 0.50, 1.0],
                    ),
                  ),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      12,
                      isFullscreen ? 14 : 10,
                      12,
                      isFullscreen ? 16 : 10,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Top Controls Bar
                        Row(
                          children: [
                            if (isFullscreen) ...[
                              _HudGlassCircleButton(
                                size: 38,
                                tooltip: 'Exit fullscreen',
                                icon: const Icon(
                                  CupertinoIcons.xmark,
                                  color: Colors.white,
                                  size: 17,
                                ),
                                onPressed: onToggleFullscreen,
                              ),
                              const SizedBox(width: 8),
                            ],
                            _HudGlassPill(
                              key: const ValueKey('video_loop_toggle'),
                              active: isLooping,
                              accentColor: c.accent,
                              onTap: onToggleLoop,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 11,
                                vertical: 7,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    CupertinoIcons.repeat,
                                    color: isLooping ? c.accent : Colors.white,
                                    size: 14,
                                  ),
                                  const SizedBox(width: 5),
                                  Text(
                                    'Loop',
                                    style: TextStyle(
                                      color:
                                          isLooping ? c.accent : Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Spacer(),
                            _HudGlassPill(
                              key: const ValueKey('video_speed_toggle'),
                              onTap: onCycleSpeed,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 11,
                                vertical: 7,
                              ),
                              child: Text(
                                _formatSpeed(speed),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  fontFeatures: [FontFeature.tabularFigures()],
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            _HudGlassCircleButton(
                              key: const ValueKey('video_mute_toggle'),
                              size: 36,
                              tooltip: isMuted ? 'Unmute' : 'Mute',
                              icon: Icon(
                                isMuted
                                    ? CupertinoIcons.speaker_slash_fill
                                    : CupertinoIcons.speaker_2_fill,
                                color: Colors.white,
                                size: 16,
                              ),
                              onPressed: onToggleMute,
                            ),
                            if (!isFullscreen) ...[
                              const SizedBox(width: 8),
                              _HudGlassCircleButton(
                                key: const ValueKey('video_fullscreen_toggle'),
                                size: 36,
                                tooltip: 'Fullscreen',
                                icon: const Icon(
                                  CupertinoIcons.fullscreen,
                                  color: Colors.white,
                                  size: 16,
                                ),
                                onPressed: onToggleFullscreen,
                              ),
                            ],
                          ],
                        ),

                        // Center Playback Cluster (-5s, 56dp Play/Pause Droplet, +5s)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _HudGlassCircleButton(
                              key: const ValueKey('video_rewind_5s'),
                              size: 42,
                              tooltip: 'Back 5 seconds',
                              icon: const Icon(
                                Icons.replay_5_rounded,
                                color: Colors.white,
                                size: 22,
                              ),
                              onPressed: () => onSeekRelative(-5),
                            ),
                            const SizedBox(width: 22),
                            _HudGlassCircleButton(
                              key: const ValueKey('video_play_pause'),
                              size: 56,
                              tooltip: val.isPlaying ? 'Pause' : 'Play',
                              tintColor: val.isPlaying ? null : c.accent,
                              icon: Icon(
                                val.isPlaying
                                    ? CupertinoIcons.pause_fill
                                    : CupertinoIcons.play_fill,
                                color: Colors.white,
                                size: 24,
                              ),
                              onPressed: onTogglePlayPause,
                            ),
                            const SizedBox(width: 22),
                            _HudGlassCircleButton(
                              key: const ValueKey('video_forward_5s'),
                              size: 42,
                              tooltip: 'Forward 5 seconds',
                              icon: const Icon(
                                Icons.forward_5_rounded,
                                color: Colors.white,
                                size: 22,
                              ),
                              onPressed: () => onSeekRelative(5),
                            ),
                          ],
                        ),

                        // Bottom Floating Liquid Scrubber Dock
                        _HudGlassPill(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 38,
                                child: Text(
                                  _formatDuration(displayPosition),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                    fontFeatures: [FontFeature.tabularFigures()],
                                  ),
                                ),
                              ),
                              Expanded(
                                child: _TempoLiquidScrubber(
                                  progress: progress,
                                  accentColor: c.accent,
                                  isDragging: isScrubbing,
                                  onScrubStart: onScrubStart,
                                  onScrubUpdate: onScrubUpdate,
                                  onScrubEnd: onScrubEnd,
                                ),
                              ),
                              SizedBox(
                                width: 38,
                                child: Text(
                                  _formatDuration(val.duration),
                                  textAlign: TextAlign.right,
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.72),
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
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
}

class _HudGlassPill extends StatefulWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final bool active;
  final Color? accentColor;

  const _HudGlassPill({
    super.key,
    required this.child,
    required this.padding,
    this.onTap,
    this.active = false,
    this.accentColor,
  });

  @override
  State<_HudGlassPill> createState() => _HudGlassPillState();
}

class _HudGlassPillState extends State<_HudGlassPill> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final pill = TempoTouchLightEffect(
      borderRadius: 999,
      emitLight: widget.onTap != null,
      receiveScatter: true,
      intensity: 0.95,
      child: CustomPaint(
        foregroundPainter: LiquidGlassRimPainter(
          borderRadius: 999,
          isDark: true,
          intensity: _pressed ? 1.25 : 0.92,
          strokeWidth: 1.0,
          showTopMeniscus: false,
          tintColor: widget.active ? widget.accentColor : null,
        ),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: widget.padding,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            color: widget.active && widget.accentColor != null
                ? widget.accentColor!.withValues(alpha: 0.24)
                : Colors.black.withValues(alpha: _pressed ? 0.62 : 0.46),
          ),
          child: widget.child,
        ),
      ),
    );

    if (widget.onTap == null) return pill;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.94 : 1.0,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOutCubic,
        child: pill,
      ),
    );
  }
}

class _HudGlassCircleButton extends StatefulWidget {
  final double size;
  final Widget icon;
  final VoidCallback onPressed;
  final String? tooltip;
  final Color? tintColor;

  const _HudGlassCircleButton({
    super.key,
    required this.size,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.tintColor,
  });

  @override
  State<_HudGlassCircleButton> createState() => _HudGlassCircleButtonState();
}

class _HudGlassCircleButtonState extends State<_HudGlassCircleButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final fillColor = widget.tintColor != null
        ? widget.tintColor!.withValues(alpha: _pressed ? 0.92 : 0.80)
        : Colors.black.withValues(alpha: _pressed ? 0.66 : 0.48);

    Widget btn = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: () {
        HapticFeedback.selectionClick();
        widget.onPressed();
      },
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0.0, end: _pressed ? 1.0 : 0.0),
        duration: Duration(milliseconds: _pressed ? 100 : 270),
        curve: _pressed ? Curves.easeOutCubic : Curves.easeOutBack,
        builder: (context, p, child) {
          final sx = 1.0 + 0.08 * p;
          final sy = 1.0 - 0.07 * p;
          return Transform(
            alignment: Alignment.center,
            transform: Matrix4.diagonal3Values(sx, sy, 1.0),
            child: child,
          );
        },
        child: SizedBox(
          width: widget.size,
          height: widget.size,
          child: TempoTouchLightEffect(
            borderRadius: widget.size * 0.5,
            isAccentSurface: widget.tintColor != null,
            emitLight: true,
            receiveScatter: true,
            intensity: 1.0,
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: (widget.tintColor ?? Colors.black).withValues(
                      alpha: widget.tintColor != null ? 0.34 : 0.28,
                    ),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: CustomPaint(
                foregroundPainter: LiquidGlassRimPainter(
                  borderRadius: widget.size * 0.5,
                  isDark: true,
                  intensity: _pressed ? 1.28 : 1.02,
                  strokeWidth: 1.15,
                  showTopMeniscus: false,
                  tintColor: widget.tintColor,
                ),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 140),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: fillColor,
                  ),
                  child: Center(child: widget.icon),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    if (widget.tooltip != null && widget.tooltip!.isNotEmpty) {
      btn = Tooltip(message: widget.tooltip!, child: btn);
    }
    return btn;
  }
}

class _TempoLiquidScrubber extends StatelessWidget {
  final double progress;
  final Color accentColor;
  final bool isDragging;
  final ValueChanged<double> onScrubStart;
  final ValueChanged<double> onScrubUpdate;
  final ValueChanged<double> onScrubEnd;

  const _TempoLiquidScrubber({
    required this.progress,
    required this.accentColor,
    required this.isDragging,
    required this.onScrubStart,
    required this.onScrubUpdate,
    required this.onScrubEnd,
  });

  double _fractionFor(BuildContext context, Offset localPosition) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || box.size.width <= 0) return progress;
    return (localPosition.dx / box.size.width).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (d) {
        final f = _fractionFor(context, d.localPosition);
        onScrubStart(f);
        onScrubEnd(f);
      },
      onHorizontalDragStart: (d) =>
          onScrubStart(_fractionFor(context, d.localPosition)),
      onHorizontalDragUpdate: (d) =>
          onScrubUpdate(_fractionFor(context, d.localPosition)),
      onHorizontalDragEnd: (_) => onScrubEnd(progress),
      child: SizedBox(
        height: 26,
        child: CustomPaint(
          painter: _LiquidScrubberPainter(
            progress: progress.clamp(0.0, 1.0),
            accentColor: accentColor,
            isDragging: isDragging,
          ),
        ),
      ),
    );
  }
}

class _LiquidScrubberPainter extends CustomPainter {
  final double progress;
  final Color accentColor;
  final bool isDragging;

  const _LiquidScrubberPainter({
    required this.progress,
    required this.accentColor,
    required this.isDragging,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final trackH = isDragging ? 6.5 : 4.5;
    final cy = size.height * 0.5;
    final radius = Radius.circular(trackH * 0.5);

    final bgRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, cy - trackH * 0.5, size.width, trackH),
      radius,
    );
    canvas.drawRRect(
      bgRect,
      Paint()..color = Colors.white.withValues(alpha: 0.24),
    );

    final fillW = (size.width * progress).clamp(0.0, size.width);
    if (fillW > 0.5) {
      final fillRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(0, cy - trackH * 0.5, fillW, trackH),
        radius,
      );
      canvas.drawRRect(fillRect, Paint()..color = accentColor);
    }

    final thumbR = isDragging ? 7.0 : 5.0;
    final thumbCenter = Offset(fillW.clamp(thumbR, size.width - thumbR), cy);
    if (isDragging) {
      canvas.drawCircle(
        thumbCenter,
        thumbR + 4.5,
        Paint()..color = accentColor.withValues(alpha: 0.34),
      );
    }
    canvas.drawCircle(thumbCenter, thumbR, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant _LiquidScrubberPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.accentColor != accentColor ||
      oldDelegate.isDragging != isDragging;
}

class _TempoFullscreenVideoScreen extends StatefulWidget {
  final VideoPlayerController controller;
  final String exerciseName;
  final int initialSpeedIndex;
  final bool initialLooping;
  final bool initialMuted;
  final void Function(int speedIdx, bool looping, bool muted) onStateSync;

  const _TempoFullscreenVideoScreen({
    required this.controller,
    required this.exerciseName,
    required this.initialSpeedIndex,
    required this.initialLooping,
    required this.initialMuted,
    required this.onStateSync,
  });

  @override
  State<_TempoFullscreenVideoScreen> createState() =>
      _TempoFullscreenVideoScreenState();
}

class _TempoFullscreenVideoScreenState
    extends State<_TempoFullscreenVideoScreen> {
  static const List<double> _speeds = [0.5, 0.75, 1.0, 1.25];

  bool _showHud = true;
  late int _speedIndex;
  late bool _isLooping;
  late bool _isMuted;
  bool _isScrubbing = false;
  double _scrubFraction = 0.0;
  int? _seekFlashDelta;
  Timer? _hideTimer;
  Timer? _seekFlashTimer;

  @override
  void initState() {
    super.initState();
    _speedIndex = widget.initialSpeedIndex;
    _isLooping = widget.initialLooping;
    _isMuted = widget.initialMuted;
    widget.controller.addListener(_onTick);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _scheduleHide();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _seekFlashTimer?.cancel();
    widget.controller.removeListener(_onTick);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _onTick() {
    if (mounted) setState(() {});
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    if (!widget.controller.value.isPlaying || _isScrubbing) return;
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && widget.controller.value.isPlaying && !_isScrubbing) {
        setState(() => _showHud = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: _VideoPlayerOverlayShell(
          controller: widget.controller,
          showHud: _showHud,
          isLooping: _isLooping,
          isMuted: _isMuted,
          speed: _speeds[_speedIndex],
          isScrubbing: _isScrubbing,
          scrubFraction: _scrubFraction,
          seekFlashDelta: _seekFlashDelta,
          isFullscreen: true,
          onToggleHud: () {
            setState(() => _showHud = !_showHud);
            if (_showHud) _scheduleHide();
          },
          onTogglePlayPause: () async {
            HapticFeedback.selectionClick();
            if (widget.controller.value.isPlaying) {
              await widget.controller.pause();
              _hideTimer?.cancel();
              if (mounted) setState(() => _showHud = true);
            } else {
              await widget.controller.play();
              _scheduleHide();
            }
          },
          onSeekRelative: (delta, {bool flash = false}) async {
            HapticFeedback.selectionClick();
            final dur = widget.controller.value.duration;
            final targetMs =
                (widget.controller.value.position.inMilliseconds + delta * 1000)
                    .clamp(0, dur.inMilliseconds);
            await widget.controller.seekTo(Duration(milliseconds: targetMs));
            if (flash && mounted) {
              _seekFlashTimer?.cancel();
              setState(() => _seekFlashDelta = delta);
              _seekFlashTimer = Timer(const Duration(milliseconds: 620), () {
                if (mounted) setState(() => _seekFlashDelta = null);
              });
            }
            _scheduleHide();
          },
          onCycleSpeed: () async {
            HapticFeedback.selectionClick();
            final next = (_speedIndex + 1) % _speeds.length;
            setState(() => _speedIndex = next);
            await widget.controller.setPlaybackSpeed(_speeds[next]);
            widget.onStateSync(_speedIndex, _isLooping, _isMuted);
            _scheduleHide();
          },
          onToggleLoop: () async {
            HapticFeedback.selectionClick();
            final next = !_isLooping;
            setState(() => _isLooping = next);
            await widget.controller.setLooping(next);
            widget.onStateSync(_speedIndex, _isLooping, _isMuted);
            _scheduleHide();
          },
          onToggleMute: () async {
            HapticFeedback.selectionClick();
            final next = !_isMuted;
            setState(() => _isMuted = next);
            await widget.controller.setVolume(next ? 0.0 : 1.0);
            widget.onStateSync(_speedIndex, _isLooping, _isMuted);
            _scheduleHide();
          },
          onToggleFullscreen: () => Navigator.of(context).pop(),
          onScrubStart: (f) {
            _hideTimer?.cancel();
            setState(() {
              _isScrubbing = true;
              _scrubFraction = f;
            });
          },
          onScrubUpdate: (f) => setState(() => _scrubFraction = f),
          onScrubEnd: (f) async {
            final dur = widget.controller.value.duration;
            if (dur > Duration.zero) {
              await widget.controller.seekTo(
                Duration(milliseconds: (dur.inMilliseconds * f).round()),
              );
            }
            if (mounted) {
              setState(() => _isScrubbing = false);
              _scheduleHide();
            }
          },
        ),
      ),
    );
  }
}
