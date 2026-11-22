import 'dart:async';
import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';

OverlayEntry? _activeTempoToast;
Timer? _activeTempoToastTimer;

/// Displays a sleek frosted floating top pill toast below the status bar so
/// feedback never collides with Tempo's floating Liquid Glass navigation bar.
void showTempoToast(
  BuildContext context,
  String message, {
  bool isError = false,
  IconData? icon,
  Duration duration = const Duration(milliseconds: 2400),
}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;

  _activeTempoToastTimer?.cancel();
  _activeTempoToast?.remove();
  _activeTempoToast = null;

  HapticFeedback.selectionClick();
  final c = AppColors.of(context, listen: false);

  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (ctx) => _TempoToastOverlay(
      message: message,
      isError: isError,
      icon: icon,
      colors: c,
      duration: duration,
      onDismissed: () {
        if (_activeTempoToast == entry) {
          _activeTempoToast = null;
        }
        entry.remove();
      },
    ),
  );

  _activeTempoToast = entry;
  overlay.insert(entry);
}

class _TempoToastOverlay extends StatefulWidget {
  final String message;
  final bool isError;
  final IconData? icon;
  final AppColors colors;
  final Duration duration;
  final VoidCallback onDismissed;

  const _TempoToastOverlay({
    required this.message,
    required this.isError,
    required this.icon,
    required this.colors,
    required this.duration,
    required this.onDismissed,
  });

  @override
  State<_TempoToastOverlay> createState() => _TempoToastOverlayState();
}

class _TempoToastOverlayState extends State<_TempoToastOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _opacity;
  late final Animation<Offset> _slide;
  Timer? _dismissTimer;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
      reverseDuration: const Duration(milliseconds: 200),
    );
    _opacity = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: const Offset(0, -0.8),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));

    _ctrl.forward();
    _dismissTimer = Timer(widget.duration, () {
      if (!mounted) return;
      _ctrl.reverse().whenComplete(() {
        if (mounted) widget.onDismissed();
      });
    });
    _activeTempoToastTimer = _dismissTimer;
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    if (_activeTempoToastTimer == _dismissTimer) {
      _activeTempoToastTimer = null;
    }
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.colors;
    final topPad = MediaQuery.paddingOf(context).top;
    final badgeColor = widget.isError ? c.moveRed : c.accent;
    final iconData = widget.icon ??
        (widget.isError
            ? CupertinoIcons.exclamationmark_circle_fill
            : CupertinoIcons.checkmark_circle_fill);

    return Positioned(
      top: topPad + 10,
      left: 20,
      right: 20,
      child: IgnorePointer(
        child: Center(
          child: SlideTransition(
            position: _slide,
            child: FadeTransition(
              opacity: _opacity,
              child: Material(
                type: MaterialType.transparency,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 11,
                      ),
                      decoration: BoxDecoration(
                        color: c.isDark
                            ? const Color(0xFF242428).withValues(alpha: 0.92)
                            : Colors.white.withValues(alpha: 0.94),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: c.isDark
                              ? Colors.white.withValues(alpha: 0.12)
                              : Colors.black.withValues(alpha: 0.07),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(
                              alpha: c.isDark ? 0.42 : 0.12,
                            ),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(iconData, size: 18, color: badgeColor),
                          const SizedBox(width: 9),
                          Flexible(
                            child: Text(
                              widget.message,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: c.textPrimary,
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                                letterSpacing: -0.1,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
