import 'package:flutter/widgets.dart';
import 'package:jiggicons/jiggicons.dart';

/// Synchronous pre-warm cache for the bundled free Jiggicons used across Tempo.
///
/// Calling [prewarm] once during `main()` loads all needed JSON icon definitions
/// into memory before the first frame so every [TempoJiggIcon] paints on Frame 0
/// with zero async blank flash.
class TempoJiggicons {
  TempoJiggicons._();

  static const List<String> _usedIconIds = <String>[
    // Floating Liquid Glass Navbar
    'heart',
    'dumbbell',
    'trophy',
    // Summary & Detail Cards
    'drop',
    'weather-moon',
    'flash',
    'calendar',
    'clock',
    // Celebrations & Progress Album
    'confetti',
    'camera',
    // Profile Settings & Local Backup
    'bell',
    'lock',
    'key',
    'palette',
    'download',
    'upload',
    'book',
    'star',
    'rocket',
  ];

  static final Map<String, JiggiconData> _syncCache = <String, JiggiconData>{};
  static Future<void>? _prewarmFuture;

  /// Returns synchronously cached icon data if already loaded.
  static JiggiconData? cached(String name) => _syncCache[name];

  /// Loads [name] and stores it in the synchronous cache.
  static Future<JiggiconData?> load(String name) async {
    final existing = _syncCache[name];
    if (existing != null) return existing;
    try {
      final data = await Jiggicons.icon(name);
      _syncCache[name] = data;
      return data;
    } catch (_) {
      return null;
    }
  }

  /// Pre-loads all Tempo Jiggicons in parallel during startup (<10ms).
  static Future<void> prewarm() {
    return _prewarmFuture ??= Future.wait(
      _usedIconIds.map(load),
    ).then((_) {});
  }
}

/// Zero-blink, 120Hz `RepaintBoundary`-isolated wrapper around [JiggIconFrame]:
/// - Reads synchronously from [TempoJiggicons.cached] on Frame 0 (zero empty
///   box flash in production).
/// - Displays [fallbackIcon] cleanly if the asset is still loading (e.g. inside
///   isolated widget tests that skip `main()`).
/// - Silent by default (`sound: false`) so tapping icons never interrupts
///   workout audio, and automatically respects OS reduced motion.
class TempoJiggIcon extends StatefulWidget {
  final String name;
  final JiggIconVariant variant;
  final double size;
  final Color? color;
  final bool sound;
  final double volume;
  final JiggIconTrigger trigger;
  final JiggIconController? controller;
  final IconData? fallbackIcon;
  final String? semanticLabel;

  const TempoJiggIcon(
    this.name, {
    super.key,
    this.variant = JiggIconVariant.outline,
    this.size = 24,
    this.color,
    this.sound = false,
    this.volume = 0.7,
    this.trigger = JiggIconTrigger.none,
    this.controller,
    this.fallbackIcon,
    this.semanticLabel,
  });

  @override
  State<TempoJiggIcon> createState() => _TempoJiggIconState();
}

class _TempoJiggIconState extends State<TempoJiggIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _motion;
  JiggiconData? _icon;
  bool _playing = false;
  bool _appearPlayed = false;

  @override
  void initState() {
    super.initState();
    _motion = AnimationController(vsync: this);
    _motion.addStatusListener(_onStatusChanged);
    widget.controller?.addListener(play);

    _icon = TempoJiggicons.cached(widget.name);
    if (_icon != null) {
      _maybePlayOnAppear();
    } else {
      _loadAsync();
    }
  }

  @override
  void didUpdateWidget(covariant TempoJiggIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.removeListener(play);
      widget.controller?.addListener(play);
    }
    if (oldWidget.name != widget.name) {
      _appearPlayed = false;
      _icon = TempoJiggicons.cached(widget.name);
      if (_icon != null) {
        _maybePlayOnAppear();
      } else {
        _loadAsync();
      }
    }
  }

  void _onStatusChanged(AnimationStatus status) {
    if (status == AnimationStatus.completed && mounted && _playing) {
      setState(() => _playing = false);
    }
  }

  Future<void> _loadAsync() async {
    final targetName = widget.name;
    final loaded = await TempoJiggicons.load(targetName);
    if (!mounted || widget.name != targetName || loaded == null) return;
    setState(() => _icon = loaded);
    _maybePlayOnAppear();
  }

  void _maybePlayOnAppear() {
    if (widget.trigger != JiggIconTrigger.appear || _appearPlayed) return;
    _appearPlayed = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) play();
    });
  }

  /// Plays the icon's spring motion (and sound only when `widget.sound == true`).
  void play() {
    final icon = _icon;
    if (icon == null || !mounted) return;
    if (widget.sound) {
      JiggiconsAudio.instance.play(
        icon,
        widget.variant,
        volume: widget.volume,
      );
    }
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return;
    final micros = (icon.ms * 1000).round().clamp(16000, 3000000);
    _motion.duration = Duration(microseconds: micros);
    if (!_playing) {
      setState(() => _playing = true);
    }
    _motion.forward(from: 0);
  }

  @override
  void dispose() {
    widget.controller?.removeListener(play);
    _motion.removeStatusListener(_onStatusChanged);
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = IconTheme.of(context);
    final resolvedColor =
        widget.color ?? theme.color ?? const Color(0xFF000000);
    final icon = _icon;

    Widget child;
    if (icon != null) {
      child = RepaintBoundary(
        child: AnimatedBuilder(
          animation: _motion,
          builder: (context, _) => JiggIconFrame(
            icon: icon,
            variant: widget.variant,
            size: widget.size,
            color: resolvedColor,
            seconds: _playing ? _motion.value * icon.ms / 1000 : null,
          ),
        ),
      );
    } else if (widget.fallbackIcon != null) {
      child = Icon(
        widget.fallbackIcon,
        size: widget.size,
        color: resolvedColor,
      );
    } else {
      child = SizedBox.square(dimension: widget.size);
    }

    if (widget.trigger == JiggIconTrigger.tap) {
      child = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: play,
        child: child,
      );
    }

    if (widget.semanticLabel != null) {
      return Semantics(
        label: widget.semanticLabel,
        image: true,
        excludeSemantics: true,
        child: child,
      );
    }
    return ExcludeSemantics(child: child);
  }
}
