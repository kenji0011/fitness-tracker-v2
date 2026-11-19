import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/active_profile_provider.dart';
import '../theme/app_colors.dart';
import '../widgets/liquid_glass_nav_bar.dart';
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

  void _onSelectTab(int index) {
    if (_currentIndex == index && _mountedTabs.contains(index)) return;
    setState(() {
      _currentIndex = index;
      _mountedTabs.add(index);
    });
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
      body: KeyedSubtree(
        key: ValueKey('profile_shell_$activeProfileId'),
        child: IndexedStack(
          index: _currentIndex,
          children: [
            _mountedTabs.contains(0)
                ? HealthDashboard(
                    refreshVersion: dataVersion,
                    onSwitchToWorkouts: () => _onSelectTab(1),
                    onSwitchToProgress: () => _onSelectTab(2),
                    onDoubleTapProfileSwitcher: () =>
                        showProfileSwitcherSheet(context),
                  )
                : const SizedBox.shrink(),
            _mountedTabs.contains(1)
                ? WorkoutScreen(
                    showChatbot: false,
                    refreshVersion: dataVersion,
                  )
                : const SizedBox.shrink(),
            _mountedTabs.contains(2)
                ? ProgressTrackingScreen(
                    embedded: true,
                    refreshVersion: dataVersion,
                  )
                : const SizedBox.shrink(),
            _mountedTabs.contains(3)
                ? MyProfile(
                    refreshVersion: dataVersion,
                    showChatbot: false,
                    onOpenProfileSwitcher: () =>
                        showProfileSwitcherSheet(context),
                  )
                : const SizedBox.shrink(),
          ],
        ),
      ),
      bottomNavigationBar: RepaintBoundary(
        child: LiquidGlassNavBar(
          currentIndex: _currentIndex,
          onTap: _onSelectTab,
          onProfileDoubleTap: () => showProfileSwitcherSheet(context),
          profileName: activeProfile?.displayName,
          profileAvatarPath: activeProfile?.avatarPath,
        ),
      ),
    );
  }
}
