import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../widgets/liquid_glass_surface.dart';
import '../widgets/tempo_sliver_header.dart';

class MovingInfoScreen extends StatelessWidget {
  const MovingInfoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Scaffold(
      backgroundColor: c.scaffold,
      body: CustomScrollView(
        slivers: [
          const TempoSliverHeader(
            title: 'Exercise Minutes',
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
                            CupertinoIcons.timer,
                            color: c.exerciseGreen,
                            size: 22,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Active Movement',
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
                        'Exercise minutes record the time spent in moderate- or high-intensity training sessions.',
                        style: TextStyle(
                          color: c.textSecondary,
                          fontSize: 14,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Engaging in 30–60 minutes of moderate-intensity exercise most days (at least 150 minutes per week) or 75 minutes of vigorous activity per week delivers major cardiovascular and strength benefits.',
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
