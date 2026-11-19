import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../widgets/liquid_glass_surface.dart';
import '../widgets/tempo_sliver_header.dart';

class SleepInfoScreen extends StatelessWidget {
  const SleepInfoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Scaffold(
      backgroundColor: c.scaffold,
      body: CustomScrollView(
        slivers: [
          const TempoSliverHeader(
            title: 'About Sleep',
            showBackButton: true,
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 32),
            sliver: SliverList.list(
              children: [
                AppleCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            CupertinoIcons.bed_double_fill,
                            color: c.sleepPurple,
                            size: 22,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Why Sleep Matters',
                            style: TextStyle(
                              color: c.textPrimary,
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Quality sleep (7–9 hours per night for most adults) is essential for muscle repair, hormone balance, reaction time, and sustained training performance.',
                        style: TextStyle(
                          color: c.textSecondary,
                          fontSize: 14,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Keep a consistent bedtime and wake time, minimize screens 45 minutes before sleep, and log your nightly hours in Tempo to spot recovery patterns.',
                        style: TextStyle(
                          color: c.textSecondary,
                          fontSize: 14,
                          height: 1.5,
                        ),
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
}
