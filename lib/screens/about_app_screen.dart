import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../config/app_version.dart';
import '../theme/app_colors.dart';
import '../widgets/liquid_glass_surface.dart';
import '../widgets/tempo_sliver_header.dart';
import '../widgets/tempo_startup_splash.dart';

class AboutAppScreen extends StatelessWidget {
  const AboutAppScreen({super.key});

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
            title: 'About Tempo',
            showBackButton: true,
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 36),
            sliver: SliverList.list(
              children: [
                // Brand Logo & Version Card (no redundant app name heading)
                AppleCard(
                  borderRadius: 24,
                  padding: const EdgeInsets.fromLTRB(24, 26, 24, 24),
                  child: Column(
                    children: [
                      Container(
                        width: 84,
                        height: 84,
                        decoration: BoxDecoration(
                          color: kTempoSplashBackground,
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(
                            color: c.isDark
                                ? Colors.white.withValues(alpha: 0.14)
                                : Colors.black.withValues(alpha: 0.08),
                            width: 1,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(
                                alpha: c.isDark ? 0.42 : 0.14,
                              ),
                              blurRadius: 18,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(21),
                          child: Image.asset(
                            'assets/tempo_app_icon.png',
                            width: 84,
                            height: 84,
                            cacheWidth: 256,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const Center(
                              child: TempoDualRingLogo(size: 56),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Your personal offline fitness companion',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: c.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: c.searchBg,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          kTempoDisplayVersion,
                          style: TextStyle(
                            color: c.textSecondary,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Overview Card
                AppleCard(
                  borderRadius: 22,
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Designed Around Your Routine',
                        style: TextStyle(
                          color: c.textPrimary,
                          fontSize: 16.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Track daily movement, workouts, hydration, sleep, body metrics, and progress photos in one calm space. Everything stays fast, uncluttered, and ready whenever you train, even without an internet connection.',
                        style: TextStyle(
                          color: c.textSecondary,
                          fontSize: 14,
                          height: 1.52,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Highlights Card
                AppleCard(
                  borderRadius: 22,
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    children: [
                      _AboutHighlightRow(
                        icon: CupertinoIcons.lock_shield_fill,
                        color: const Color(0xFF34C759),
                        title: 'Private by Default',
                        subtitle:
                            'Profiles, workout history, and progress photos remain stored directly on your device.',
                      ),
                      _insetDivider(c),
                      _AboutHighlightRow(
                        icon: CupertinoIcons.bolt_fill,
                        color: c.accent,
                        title: 'Offline First',
                        subtitle:
                            'Log sessions, daily goals, and body logs instantly with no accounts or cloud dependency.',
                      ),
                      _insetDivider(c),
                      _AboutHighlightRow(
                        icon: CupertinoIcons.person_2_fill,
                        color: const Color(0xFF0A84FF),
                        title: 'Multiple Local Profiles',
                        subtitle:
                            'Keep separate personal fitness spaces on one phone, each protected by its own 4-digit PIN.',
                      ),
                      _insetDivider(c),
                      const _AboutHighlightRow(
                        icon: CupertinoIcons.arrow_down_doc_fill,
                        color: Color(0xFF5856D6),
                        title: 'Portable Local Backups',
                        subtitle:
                            'Export or restore your training records anytime directly from your device storage.',
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                Center(
                  child: Text(
                    'Crafted for everyday consistency.',
                    style: TextStyle(
                      color: c.textTertiary,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _insetDivider(AppColors c) {
    return Padding(
      padding: const EdgeInsets.only(left: 64, right: 18),
      child: Divider(height: 1, thickness: 0.7, color: c.divider),
    );
  }
}

class _AboutHighlightRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;

  const _AboutHighlightRow({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            margin: const EdgeInsets.only(top: 1),
            decoration: BoxDecoration(
              color: color.withValues(alpha: c.isDark ? 0.22 : 0.14),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 17),
          ),
          const SizedBox(width: 12),
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
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: c.textSecondary,
                    fontSize: 13.5,
                    height: 1.42,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
