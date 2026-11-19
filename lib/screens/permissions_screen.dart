import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../services/live_workout_service.dart';
import '../theme/app_colors.dart';
import '../widgets/liquid_glass_surface.dart';
import '../widgets/tempo_sliver_header.dart';

class PermissionsScreen extends StatefulWidget {
  const PermissionsScreen({super.key});

  @override
  State<PermissionsScreen> createState() => _PermissionsScreenState();
}

class _PermissionsScreenState extends State<PermissionsScreen>
    with WidgetsBindingObserver {
  PermissionStatus _activityStatus = PermissionStatus.denied;
  PermissionStatus _cameraStatus = PermissionStatus.denied;
  PermissionStatus _notificationStatus = PermissionStatus.denied;
  LiveUpdateStatus _liveUpdateStatus = LiveUpdateStatus.unsupported;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _check();
    }
  }

  Future<void> _check() async {
    if (kIsWeb) return;
    final act = await Permission.activityRecognition.status;
    final cam = await Permission.camera.status;
    final notif = await Permission.notification.status;
    final live = await LiveWorkoutService.instance.getStatus();
    if (mounted) {
      setState(() {
        _activityStatus = act;
        _cameraStatus = cam;
        _notificationStatus = notif;
        _liveUpdateStatus = live;
      });
    }
  }

  Future<void> _request(Permission p) async {
    if (kIsWeb) return;
    HapticFeedback.selectionClick();
    await p.request();
    await _check();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Scaffold(
      backgroundColor: c.scaffold,
      body: CustomScrollView(
        slivers: [
          const TempoSliverHeader(
            title: 'Permissions',
            showBackButton: true,
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 36),
            sliver: SliverList.list(
              children: [
                AppleCard(
                  borderRadius: 24,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    children: [
                      _permRow(
                        icon: CupertinoIcons.hare_fill,
                        badgeColor: const Color(0xFF4AC9A5),
                        title: 'Physical Activity & Steps',
                        subtitle: 'Count daily steps offline on your phone.',
                        granted: _activityStatus.isGranted,
                        actionLabel: 'Allow',
                        onRequest: () =>
                            _request(Permission.activityRecognition),
                        c: c,
                      ),
                      _permRow(
                        icon: CupertinoIcons.camera_fill,
                        badgeColor: const Color(0xFF7A6FF0),
                        title: 'Camera & Photos',
                        subtitle:
                            'Save avatars and progress photos privately on device.',
                        granted: _cameraStatus.isGranted,
                        actionLabel: 'Allow',
                        onRequest: () => _request(Permission.camera),
                        c: c,
                      ),
                      _permRow(
                        icon: CupertinoIcons.bell_fill,
                        badgeColor: const Color(0xFFF4BD3E),
                        title: 'Notifications',
                        subtitle:
                            'Display active workout timers and session status.',
                        granted: _notificationStatus.isGranted,
                        actionLabel: 'Allow',
                        onRequest: () => _request(Permission.notification),
                        c: c,
                      ),
                      _permRow(
                        icon: CupertinoIcons.sparkles,
                        badgeColor: const Color(0xFF3D9CF6),
                        title: 'Live Updates (HyperIsland)',
                        subtitle: _liveUpdateStatus.supported
                            ? 'Show live workout timer & progress in HyperIsland.'
                            : 'Available on Android 16+ / HyperOS 3 devices.',
                        granted: _liveUpdateStatus.canPostPromoted,
                        actionLabel: 'Settings',
                        onRequest: () async {
                          HapticFeedback.selectionClick();
                          await LiveWorkoutService.instance
                              .openLiveUpdatesSettings();
                        },
                        c: c,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _permRow({
    required IconData icon,
    required Color badgeColor,
    required String title,
    required String subtitle,
    required bool granted,
    required String actionLabel,
    required VoidCallback onRequest,
    required AppColors c,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: badgeColor,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.white, size: 17),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: c.textSecondary,
                    fontSize: 12.5,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          granted
              ? Icon(
                  CupertinoIcons.checkmark_circle_fill,
                  color: c.accent,
                  size: 22,
                )
              : FilledButton.tonal(
                  onPressed: onRequest,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    actionLabel,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
        ],
      ),
    );
  }
}
