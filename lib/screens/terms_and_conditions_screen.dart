import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../widgets/liquid_glass_surface.dart';
import '../widgets/tempo_sliver_header.dart';

class TermsAndConditionsScreen extends StatelessWidget {
  const TermsAndConditionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);

    return Scaffold(
      backgroundColor: c.scaffold,
      body: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        slivers: [
          const TempoSliverHeader(
            title: 'Privacy & Terms',
            showBackButton: true,
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 36),
            sliver: SliverList.list(
              children: [
                // 1. On-Device Privacy
                _PolicyCard(
                  icon: CupertinoIcons.lock_shield_fill,
                  iconColor: const Color(0xFF34C759),
                  title: 'On-Device Privacy',
                  paragraphs: const [
                    'All profiles, 4-digit PIN hashes, workout logs, body measurements, hydration and sleep records, and progress photos are stored strictly on your device in a local database.',
                    'We do not require online accounts, collect usage analytics, track your location, or upload your personal fitness records or photos to any remote server.',
                  ],
                ),

                const SizedBox(height: 14),

                // 2. Permissions & Network Use
                AppleCard(
                  borderRadius: 22,
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              color: const Color(0xFF0A84FF).withValues(
                                alpha: c.isDark ? 0.22 : 0.14,
                              ),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              CupertinoIcons.slider_horizontal_3,
                              color: Color(0xFF0A84FF),
                              size: 17,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Permissions & Network Access',
                              style: TextStyle(
                                color: c.textPrimary,
                                fontSize: 16.5,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.2,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      const _PermissionItem(
                        title: 'Activity & Motion Sensors',
                        body:
                            'Used only when you turn on the live step counter to estimate daily steps from your phone sensors. You can turn it off or log steps manually at any time.',
                      ),
                      Divider(height: 20, thickness: 0.7, color: c.divider),
                      const _PermissionItem(
                        title: 'Camera & Photo Library',
                        body:
                            'Used only when you choose to capture or import progress photos or set a profile picture. Images remain inside private local app storage on your device.',
                      ),
                      Divider(height: 20, thickness: 0.7, color: c.divider),
                      const _PermissionItem(
                        title: 'App Update Checks',
                        body:
                            'When Auto-updates is enabled or you tap Check for updates, the app checks public GitHub Releases to see if a newer version is available and downloads the installer when you choose to update. No personal profile data is sent.',
                      ),
                      const SizedBox(height: 6),
                    ],
                  ),
                ),

                const SizedBox(height: 14),

                // 3. Data Control & Backups
                _PolicyCard(
                  icon: CupertinoIcons.folder_fill,
                  iconColor: const Color(0xFF5856D6),
                  title: 'Your Data & Backups',
                  paragraphs: const [
                    'You stay in full control of your records. You can export a local backup file or restore an earlier backup anytime from Profile settings.',
                    'Deleting a local profile permanently erases that profile along with its workouts, health metrics, and saved progress photos from this device.',
                  ],
                ),

                const SizedBox(height: 14),

                // 4. Health Disclaimer & Terms of Use
                _PolicyCard(
                  icon: CupertinoIcons.heart_fill,
                  iconColor: c.accent,
                  title: 'Health Disclaimer & Terms',
                  paragraphs: const [
                    'Workout programs, calorie estimates, BMI figures, and sensor-based step counts are provided for general wellness and personal tracking only. They do not constitute medical advice, diagnosis, or treatment.',
                    'Always listen to your body and consult a qualified healthcare professional before beginning a new exercise program or making major changes to your routine.',
                    'By using this app, you agree to track and train responsibly at your own pace.',
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PolicyCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final List<String> paragraphs;

  const _PolicyCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.paragraphs,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return AppleCard(
      borderRadius: 22,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: c.isDark ? 0.22 : 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: iconColor, size: 17),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 16.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (int i = 0; i < paragraphs.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            Text(
              paragraphs[i],
              style: TextStyle(
                color: c.textSecondary,
                fontSize: 14,
                height: 1.52,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PermissionItem extends StatelessWidget {
  final String title;
  final String body;

  const _PermissionItem({
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: c.textPrimary,
            fontSize: 14.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          body,
          style: TextStyle(
            color: c.textSecondary,
            fontSize: 13.5,
            height: 1.48,
          ),
        ),
      ],
    );
  }
}
