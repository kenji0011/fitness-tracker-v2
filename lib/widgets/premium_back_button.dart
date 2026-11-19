import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'tempo_sliver_header.dart';

class PremiumBackButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final Color? iconColor;
  final double glassOpacity;

  const PremiumBackButton({
    super.key,
    this.onPressed,
    this.iconColor,
    this.glassOpacity = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Center(
      widthFactor: 1.0,
      heightFactor: 1.0,
      child: TempoGlassCircleButton(
        glassOpacity: glassOpacity,
        icon: TempoBackChevron(color: iconColor ?? c.textPrimary, size: 22),
        onPressed: onPressed ??
            () {
              if (Navigator.canPop(context)) {
                Navigator.pop(context);
              }
            },
      ),
    );
  }
}
