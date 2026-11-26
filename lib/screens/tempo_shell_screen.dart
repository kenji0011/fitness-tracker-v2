import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';

import '../services/active_profile_provider.dart';
import '../services/app_update_service.dart';
import '../theme/app_colors.dart';
import '../widgets/liquid_glass_nav_bar.dart';
import '../widgets/tempo_startup_splash.dart';
import '../widgets/tempo_update_sheet.dart';
import 'health_dashboard.dart';
import 'my_profile.dart';
import 'profile_switcher_screen.dart';
import 'progress_tracking_screen.dart';
import 'workout_screen.dart';

/// Main Tempo navigation shell hosting the 4 core tabs:
/// 0: Summary | 1: Workout | 2: Progress | 3: Profile
/// Tabs mount lazily on first visit for fast cold startup, then stay alive
/// inside [IndexedStack] so scroll positions are preserved.
class TempoShellScreen extends StatefulWidget {
  const TempoShellScreen({super.key});

  @override
  State<TempoShellScreen> createState() => _TempoShellScreenState();
}

class _TempoShellScreenState extends State<TempoShellScreen> {
  int _currentIndex = 0;
  final Set<int> _mountedTabs = {0};
  String? _lastProfileId;
  bool _navMinimized = false;
  double _accumulatedScroll = 0.0;
  ScrollDirection _lastUserDirection = ScrollDirection.idle;

  static const double _minimizeThreshold = 48.0;
  static const double _expandThreshold = 36.0;
  static bool _didRunStartupUpdateCheck = false;

  @override
  void initState() {
    super.initState();
    _scheduleStartupUpdateCheck();
  }

  Future<void> _scheduleStartupUpdateCheck() async {
    if (_didRunStartupUpdateCheck) return;
    if (WidgetsBinding.instance.runtimeType.toString().contains('Test')) return;
    _didRunStartupUpdateCheck = true;

    // Reclaim any cached APK left over from a previous completed update.
    await AppUpdateService.cleanupStaleApks();

    // Wait cleanly past the 120Hz startup splash before checking GitHub Releases.
    await TempoStartupSplash.waitForCompletion();
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    if (!mounted) return;

    final result = await AppUpdateService.checkForUpdate(manual: false);
    if (!mounted) return;
    if (result.status == TempoUpdateCheckStatus.updateAvailable &&
        result.release != null) {
      await showTempoUpdateSheet(context, result.release!);
    }
  }

  void _onSelectTab(int index) {
    if (_currentIndex == index && _mountedTabs.contains(index)) return;
    setState(() {
      _currentIndex = index;
      _mountedTabs.add(index);
      _accumulatedScroll = 0.0;
      _lastUserDirection = ScrollDirection.idle;
    });
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification.metrics.axis != Axis.vertical) return false;

    if (notification is UserScrollNotification) {
      if (notification.direction != ScrollDirection.idle) {
        _lastUserDirection = notification.direction;
      }
      return false;
    }

    if (notification is ScrollEndNotification) {
      _accumulatedScroll = 0.0;
      return false;
    }

    if (notification is ScrollUpdateNotification) {
      final metrics = notification.metrics;
      final delta = notification.scrollDelta ?? 0.0;
      if (delta.abs() < 0.5) return false;

      final isUserDragging = notification.dragDetails != null;

      // Allow expanding when the user manually pulls down at the very top of a tab
      if (isUserDragging && delta < 0 && metrics.pixels <= 16) {
        if ((_accumulatedScroll > 0 && delta < 0)) {
          _accumulatedScroll = 0.0;
        }
        _accumulatedScroll += delta;
        if (_accumulatedScroll <= -_expandThreshold && _navMinimized) {
          setState(() {
            _navMinimized = false;
            _accumulatedScroll = 0.0;
          });
        }
        return false;
      }

      if (metrics.maxScrollExtent <= 0) return false;

      // Ignore rubber-band overscroll & bounce-back frames at top/bottom edges
      if (metrics.outOfRange) {
        _accumulatedScroll = 0.0;
        return false;
      }

      // Ignore ballistic bottom-bounce rebounds (negative delta without a user
      // upward scroll gesture or while settling right at maxScrollExtent)
      if (delta < 0 &&
          !isUserDragging &&
          (_lastUserDirection != ScrollDirection.forward ||
              metrics.pixels >= metrics.maxScrollExtent - 8)) {
        _accumulatedScroll = 0.0;
        return false;
      }

      // Ignore top-bounce rebounds when scrolling down
      if (delta > 0 &&
          !isUserDragging &&
          _lastUserDirection != ScrollDirection.reverse) {
        _accumulatedScroll = 0.0;
        return false;
      }

      // Reset accumulator on direction reversal (BitChord FloatingTabBar pattern)
      if ((_accumulatedScroll > 0 && delta < 0) ||
          (_accumulatedScroll < 0 && delta > 0)) {
        _accumulatedScroll = 0.0;
      }
      _accumulatedScroll += delta;

      if (_accumulatedScroll >= _minimizeThreshold && !_navMinimized) {
        setState(() {
          _navMinimized = true;
          _accumulatedScroll = 0.0;
        });
      } else if (_accumulatedScroll <= -_expandThreshold && _navMinimized) {
        setState(() {
          _navMinimized = false;
          _accumulatedScroll = 0.0;
        });
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final profileProvider = context.watch<ActiveProfileProvider>();
    final activeProfile = profileProvider.activeProfile;
    final activeProfileId = activeProfile?.id ?? 'none';
    final dataVersion = profileProvider.dataVersion;

    // Reset lazy tab cache cleanly when switching profiles
    if (_lastProfileId != activeProfileId) {
      _lastProfileId = activeProfileId;
      _mountedTabs
        ..clear()
        ..add(_currentIndex);
    }

    return Scaffold(
      backgroundColor: c.scaffold,
      extendBody: true,
      body: NotificationListener<ScrollNotification>(
        onNotification: _handleScrollNotification,
        child: KeyedSubtree(
          key: ValueKey('profile_shell_$activeProfileId'),
          child: Stack(
            fit: StackFit.expand,
            children: [
              _AnimatedTabPane(
                active: _currentIndex == 0,
                mounted: _mountedTabs.contains(0),
                child: HealthDashboard(
                  refreshVersion: dataVersion,
                  onSwitchToWorkouts: () => _onSelectTab(1),
                  onSwitchToProgress: () => _onSelectTab(2),
                  onDoubleTapProfileSwitcher: () =>
                      showProfileSwitcherSheet(context),
                ),
              ),
              _AnimatedTabPane(
                active: _currentIndex == 1,
                mounted: _mountedTabs.contains(1),
                child: WorkoutScreen(
                  showChatbot: false,
                  refreshVersion: dataVersion,
                ),
              ),
              _AnimatedTabPane(
                active: _currentIndex == 2,
                mounted: _mountedTabs.contains(2),
                child: ProgressTrackingScreen(
                  embedded: true,
                  refreshVersion: dataVersion,
                ),
              ),
              _AnimatedTabPane(
                active: _currentIndex == 3,
                mounted: _mountedTabs.contains(3),
                child: MyProfile(
                  refreshVersion: dataVersion,
                  showChatbot: false,
                  onOpenProfileSwitcher: () =>
                      showProfileSwitcherSheet(context),
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: LiquidGlassNavBar(
        currentIndex: _currentIndex,
        minimized: _navMinimized,
        onTap: _onSelectTab,
        onProfileDoubleTap: () => showProfileSwitcherSheet(context),
        profileName: activeProfile?.displayName,
        profileAvatarPath: activeProfile?.avatarPath,
      ),
    );
  }
}

class _AnimatedTabPane extends StatelessWidget {
  final bool active;
  final bool mounted;
  final Widget child;

  const _AnimatedTabPane({
    required this.active,
    required this.mounted,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    if (!mounted) return const SizedBox.shrink();
    return IgnorePointer(
      ignoring: !active,
      child: ExcludeSemantics(
        excluding: !active,
        child: AnimatedOpacity(
          opacity: active ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          child: AnimatedScale(
            scale: active ? 1.0 : 0.985,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            child: TickerMode(
              enabled: active,
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}
