import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:jiggicons/jiggicons.dart';

import '../config/app_version.dart';
import '../services/app_update_service.dart';
import '../theme/app_colors.dart';
import 'ios_stretch_sheet.dart';
import 'liquid_glass_surface.dart';
import 'tempo_jigg_icon.dart';
import 'tempo_sliver_header.dart';
import 'tempo_toast.dart';

/// Displays Tempo's floating bottom update prompt with generous clearance above
/// Android's bottom navigation bar (gesture pill or 3-button bar).
Future<void> showTempoUpdateSheet(
  BuildContext context,
  TempoReleaseInfo release,
) {
  return showTempoSheet<void>(
    context: context,
    backgroundColor: null,
    skirtColor: Colors.transparent,
    showDragHandle: false,
    useRootNavigator: true,
    builder: (_) => _TempoUpdateFloatingModal(release: release),
  );
}

enum _UpdatePhase {
  idle,
  downloading,
  verifying,
  needsPermission,
  readyToInstall,
  error,
}

class _TempoUpdateFloatingModal extends StatefulWidget {
  final TempoReleaseInfo release;

  const _TempoUpdateFloatingModal({required this.release});

  @override
  State<_TempoUpdateFloatingModal> createState() =>
      _TempoUpdateFloatingModalState();
}

class _TempoUpdateFloatingModalState extends State<_TempoUpdateFloatingModal>
    with WidgetsBindingObserver {
  final JiggIconController _rocketController = JiggIconController();
  TempoDownloadCancelToken? _cancelToken;

  _UpdatePhase _phase = _UpdatePhase.idle;
  int _receivedBytes = 0;
  int _totalBytes = 0;
  String? _downloadedPath;
  String? _errorMessage;
  bool _awaitingPermissionReturn = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _totalBytes = widget.release.apkSizeBytes;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cancelToken?.cancel();
    _rocketController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        _awaitingPermissionReturn &&
        _downloadedPath != null &&
        mounted) {
      _awaitingPermissionReturn = false;
      _launchInstaller(_downloadedPath!);
    }
  }

  Future<void> _startDownloadAndInstall() async {
    HapticFeedback.selectionClick();
    _rocketController.play();

    if (_downloadedPath != null) {
      await _launchInstaller(_downloadedPath!);
      return;
    }

    final token = TempoDownloadCancelToken();
    _cancelToken = token;

    setState(() {
      _phase = _UpdatePhase.downloading;
      _receivedBytes = 0;
      _totalBytes = widget.release.apkSizeBytes;
      _errorMessage = null;
    });

    try {
      final path = await AppUpdateService.downloadApk(
        widget.release,
        cancelToken: token,
        onProgress: (received, total) {
          if (!mounted) return;
          final effectiveTotal =
              total > 0 ? total : widget.release.apkSizeBytes;
          final verifying = effectiveTotal > 0 && received >= effectiveTotal;
          setState(() {
            _receivedBytes = received;
            _totalBytes = effectiveTotal;
            if (verifying && _phase == _UpdatePhase.downloading) {
              _phase = _UpdatePhase.verifying;
            }
          });
        },
      );

      if (!mounted) return;
      _downloadedPath = path;
      await _launchInstaller(path);
    } on TempoDownloadCancelledException {
      if (!mounted) return;
      setState(() {
        _phase = _UpdatePhase.idle;
        _receivedBytes = 0;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _UpdatePhase.error;
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _launchInstaller(String filePath) async {
    final canInstall = await AppUpdateService.canInstallPackages();
    if (!mounted) return;
    if (!canInstall) {
      setState(() {
        _phase = _UpdatePhase.needsPermission;
      });
      return;
    }

    setState(() => _phase = _UpdatePhase.readyToInstall);
    final res = await AppUpdateService.installApk(filePath);
    if (!mounted) return;

    if (res.needsPermission) {
      setState(() => _phase = _UpdatePhase.needsPermission);
      return;
    }

    if (!res.ok) {
      setState(() {
        _phase = _UpdatePhase.error;
        _errorMessage = res.message ?? 'Could not open Android installer.';
      });
    }
  }

  Future<void> _openPermissionSettings() async {
    HapticFeedback.selectionClick();
    _awaitingPermissionReturn = true;
    final opened = await AppUpdateService.openInstallPermissionSettings();
    if (!opened && mounted) {
      _awaitingPermissionReturn = false;
      showTempoToast(
        context,
        'Open Android Settings to allow Tempo to install updates',
        isError: true,
      );
    }
  }

  void _cancelDownload() {
    HapticFeedback.selectionClick();
    _cancelToken?.cancel();
  }

  Future<void> _skipVersion() async {
    HapticFeedback.selectionClick();
    await AppUpdateService.skipVersion(widget.release.version);
    if (!mounted) return;
    Navigator.of(context).pop();
    showTempoToast(context, 'Skipped ${widget.release.displayVersion}');
  }

  String _formatMb(int bytes) => (bytes / (1024 * 1024)).toStringAsFixed(1);

  String _cleanedNotes(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return 'Includes performance improvements, bug fixes, and the latest Tempo features.';
    }
    return trimmed
        .replaceAll(RegExp(r'^#+\s*', multiLine: true), '')
        .replaceAll('**', '')
        .trim();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final bottomInset = math.max(MediaQuery.viewPaddingOf(context).bottom, 14.0);
    // Generous bottom cushion so the floating modal never collides with
    // Android's gesture pill or 3-button system navigation bar.
    final floatingBottomMargin = bottomInset + 22.0;

    final progress = (_totalBytes > 0)
        ? (_receivedBytes / _totalBytes).clamp(0.0, 1.0)
        : 0.0;
    final pct = (progress * 100).round();

    return Padding(
      padding: EdgeInsets.fromLTRB(14, 0, 14, floatingBottomMargin),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: c.isDark ? 0.56 : 0.16),
              blurRadius: 32,
              spreadRadius: -4,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: CustomPaint(
          foregroundPainter: LiquidGlassRimPainter(
            borderRadius: 28,
            isDark: c.isDark,
            intensity: 1.05,
            strokeWidth: 1.2,
          ),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: c.isDark
                    ? const [Color(0xFF23242A), Color(0xFF16171B)]
                    : const [Color(0xFFFFFFFF), Color(0xFFF5F6FA)],
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Subtle floating drag handle
                  Center(
                    child: Container(
                      width: 38,
                      height: 4.5,
                      decoration: BoxDecoration(
                        color: c.textTertiary.withValues(alpha: 0.34),
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Header Row: Animated Rocket + Title/Versions + Close Glass Circle
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: c.accent
                              .withValues(alpha: c.isDark ? 0.22 : 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: TempoJiggIcon(
                            'rocket',
                            variant: JiggIconVariant.solid,
                            color: c.accent,
                            size: 24,
                            controller: _rocketController,
                            trigger: JiggIconTrigger.appear,
                            fallbackIcon: CupertinoIcons.arrow_up_circle_fill,
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Update Available',
                              style: TextStyle(
                                color: c.textPrimary,
                                fontSize: 19,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.35,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '$kTempoDisplayVersion  →  ${widget.release.displayVersion}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: c.accent,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      TempoGlassCircleButton(
                        size: 36,
                        tooltip: 'Dismiss',
                        enableBlur: false,
                        onPressed: () {
                          _cancelToken?.cancel();
                          Navigator.of(context).pop();
                        },
                        icon: Icon(
                          CupertinoIcons.xmark,
                          size: 16,
                          color: c.textPrimary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Release Notes & Size Box
                  Container(
                    constraints: const BoxConstraints(maxHeight: 148),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: c.searchBg,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: c.cardBorder),
                    ),
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                "What's new",
                                style: TextStyle(
                                  color: c.textSecondary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.1,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                widget.release.formattedSize,
                                style: TextStyle(
                                  color: c.textTertiary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _cleanedNotes(widget.release.releaseNotes),
                            style: TextStyle(
                              color: c.textPrimary,
                              fontSize: 13.5,
                              height: 1.42,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Dynamic phase area (Download Progress / Permission / Error)
                  if (_phase == _UpdatePhase.downloading ||
                      _phase == _UpdatePhase.verifying) ...[
                    Row(
                      children: [
                        Text(
                          _phase == _UpdatePhase.verifying
                              ? 'Verifying package...'
                              : 'Downloading Tempo...',
                          style: TextStyle(
                            color: c.textPrimary,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          _totalBytes > 0
                              ? '${_formatMb(_receivedBytes)} / ${_formatMb(_totalBytes)} MB · $pct%'
                              : '${_formatMb(_receivedBytes)} MB',
                          style: TextStyle(
                            color: c.textSecondary,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            fontFeatures: const [
                              FontFeature.tabularFigures(),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: LinearProgressIndicator(
                        value: _phase == _UpdatePhase.verifying
                            ? null
                            : (_totalBytes > 0 ? progress : null),
                        minHeight: 7,
                        backgroundColor: c.divider,
                        valueColor: AlwaysStoppedAnimation<Color>(c.accent),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TempoLiquidButton(
                      primary: false,
                      height: 46,
                      onPressed: _cancelDownload,
                      child: const Text(
                        'Cancel download',
                        style: TextStyle(fontSize: 15),
                      ),
                    ),
                  ] else if (_phase == _UpdatePhase.needsPermission) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: c.accent.withValues(alpha: c.isDark ? 0.16 : 0.10),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        'Enable "Allow from this source" in Android Settings for Tempo — installation will resume automatically when you come back.',
                        style: TextStyle(
                          color: c.textPrimary,
                          fontSize: 13,
                          height: 1.38,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TempoLiquidButton(
                      primary: true,
                      height: 48,
                      onPressed: _openPermissionSettings,
                      child: const Text(
                        'Allow in Settings',
                        style: TextStyle(fontSize: 15.5),
                      ),
                    ),
                  ] else ...[
                    if (_phase == _UpdatePhase.error &&
                        _errorMessage != null) ...[
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Text(
                          _errorMessage!,
                          style: TextStyle(
                            color: c.moveRed,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                    TempoLiquidButton(
                      primary: true,
                      height: 48,
                      onPressed: _startDownloadAndInstall,
                      child: Text(
                        _phase == _UpdatePhase.readyToInstall
                            ? 'Install update'
                            : (_phase == _UpdatePhase.error
                                ? 'Retry download'
                                : 'Update now'),
                        style: const TextStyle(fontSize: 15.5),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TempoLiquidButton(
                            primary: false,
                            height: 42,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            onPressed: () {
                              HapticFeedback.selectionClick();
                              Navigator.of(context).pop();
                            },
                            child: Text(
                              'Later',
                              style: TextStyle(
                                color: c.textPrimary,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TempoLiquidButton(
                            primary: false,
                            height: 42,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            onPressed: _skipVersion,
                            child: Text(
                              'Skip version',
                              style: TextStyle(
                                color: c.textSecondary,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
