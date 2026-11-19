import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../widgets/liquid_glass_surface.dart';
import '../widgets/tempo_sliver_header.dart';

class CaloriesInfoScreen extends StatelessWidget {
  const CaloriesInfoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Scaffold(
      backgroundColor: c.scaffold,
      body: CustomScrollView(
        slivers: [
          const TempoSliverHeader(
            title: 'About Calories',
            showBackButton: true,
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 32),
            sliver: SliverList.list(
              children: [
                _InfoCard(
                  title: 'Total Calories',
                  body: 'Total calories = resting calories + active calories.',
                  accent: c.moveRed,
                  icon: CupertinoIcons.flame_fill,
                ),
                const SizedBox(height: 12),
                _InfoCard(
                  title: 'Resting Calories',
                  body:
                      'Resting calories refer to the energy burned while your body is at rest, estimated from your resting metabolic rate (RMR) using age, height, weight, and sex.',
                  accent: c.accent,
                  icon: CupertinoIcons.heart_fill,
                ),
                const SizedBox(height: 12),
                _InfoCard(
                  title: 'Active Calories',
                  body:
                      'Active calories measure energy burned through workouts and daily movement like walking, lifting, running, and household activity.',
                  accent: c.energyOrange,
                  icon: CupertinoIcons.bolt_fill,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final String title;
  final String body;
  final Color accent;
  final IconData icon;

  const _InfoCard({
    required this.title,
    required this.body,
    required this.accent,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return AppleCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: accent, size: 20),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  color: c.textPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: TextStyle(
              color: c.textSecondary,
              fontSize: 14,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
