import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class PremiumSnackBar {
  static void show(
    BuildContext context, {
    required String message,
    required String type,
    Duration duration = const Duration(seconds: 3),
  }) {
    final c = AppColors.of(context, listen: false);
    Color accentColor;
    IconData icon;

    switch (type) {
      case 'success':
        accentColor = c.exerciseGreen;
        icon = Icons.check_circle_rounded;
        break;
      case 'error':
        accentColor = c.moveRed;
        icon = Icons.error_rounded;
        break;
      case 'warning':
        accentColor = c.energyOrange;
        icon = Icons.warning_rounded;
        break;
      case 'info':
      default:
        accentColor = c.accent;
        icon = Icons.info_rounded;
        break;
    }

    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: duration,
        backgroundColor: Colors.transparent,
        elevation: 0,
        behavior: SnackBarBehavior.floating,
        content: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: c.card,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: accentColor.withValues(alpha: 0.35),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: c.shadow,
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: accentColor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  message,
                  style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
