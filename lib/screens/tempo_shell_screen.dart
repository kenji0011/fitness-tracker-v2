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
/// Floating above content is the iOS 26/27 Liquid Glass Navigation Bar.
/// Double-tapping the Profile tab opens the multi-profile PIN switcher!
class TempoShellScreen extends StatefulWidget {
  const TempoShellScreen({super.key});

  @override
  State<TempoShellScreen> createState() => _TempoShellScreenState();
}

class _TempoShellScreenState extends State<TempoShellScreen> {
  int _currentIndex = 0;

  void _onSelectTab(int index) {
    if (_currentIndex == index) return;
    setState(() => _currentIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final profileProvider = context.watch<ActiveProfileProvider>();
    final activeProfile = profileProvider.activeProfile;
    final activeProfileId = activeProfile?.id ?? 'none';
    final dataVersion = profileProvider.dataVersion;

    return Scaffold(
      backgroundColor: c.scaffold,
      extendBody: true,
      body: KeyedSubtree(
        // Automatically resets tab views cleanly whenever a user switches profiles
        key: ValueKey('profile_shell_$activeProfileId'),
        child: IndexedStack(
          index: _currentIndex,
          children: [
            HealthDashboard(
              refreshVersion: dataVersion,
              onSwitchToWorkouts: () => _onSelectTab(1),
              onSwitchToProgress: () => _onSelectTab(2),
              onDoubleTapProfileSwitcher: () =>
                  showProfileSwitcherSheet(context),
            ),
            WorkoutScreen(
              showChatbot: false,
              refreshVersion: dataVersion,
            ),
            ProgressTrackingScreen(
              embedded: true,
              refreshVersion: dataVersion,
            ),
            MyProfile(
              refreshVersion: dataVersion,
              showChatbot: false,
              onOpenProfileSwitcher: () => showProfileSwitcherSheet(context),
            ),
          ],
        ),
      ),
      bottomNavigationBar: LiquidGlassNavBar(
        currentIndex: _currentIndex,
        onTap: _onSelectTab,
        onProfileDoubleTap: () => showProfileSwitcherSheet(context),
        profileName: activeProfile?.displayName,
        profileAvatarPath: activeProfile?.avatarPath,
      ),
    );
  }
}
