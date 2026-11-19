import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'theme_provider.dart';

/// Centralized Apple-inspired semantic color tokens for Tempo (Light & Dark Mode).
/// Use `AppColors.of(context)` everywhere so all screens react cleanly to Light/Dark switching.
class AppColors {
  final bool isDark;

  const AppColors._(this.isDark);

  factory AppColors.of(BuildContext context, {bool listen = true}) {
    final isDark = Provider.of<ThemeProvider>(context, listen: listen).isDarkMode;
    return AppColors._(isDark);
  }

  // --- Scaffolds & Grouped Surfaces (Apple Health / iOS 26-27) ---
  Color get scaffold => isDark ? const Color(0xFF000000) : const Color(0xFFF2F2F7);
  Color get appBar => isDark ? const Color(0xFF000000) : const Color(0xFFF2F2F7);

  // --- Cards & Elevated Surfaces ---
  Color get card => isDark ? const Color(0xFF1C1C1E) : const Color(0xFFFFFFFF);
  Color get cardAlt => isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF7F7FA);
  Color get cardBorder => isDark
      ? Colors.white.withValues(alpha: 0.10)
      : Colors.black.withValues(alpha: 0.06);

  // --- Primary & Semantic Apple Accents ---
  Color get accent => isDark ? const Color(0xFF0A84FF) : const Color(0xFF007AFF);
  Color get accentSoft => accent.withValues(alpha: isDark ? 0.18 : 0.12);
  Color get moveRed => isDark ? const Color(0xFFFF453A) : const Color(0xFFFF3B30);
  Color get exerciseGreen => isDark ? const Color(0xFF30D158) : const Color(0xFF34C759);
  Color get energyOrange => isDark ? const Color(0xFFFF9F0A) : const Color(0xFFFF9500);
  Color get sleepPurple => isDark ? const Color(0xFFBF5AF2) : const Color(0xFFAF52DE);
  Color get bodyCyan => isDark ? const Color(0xFF64D2FF) : const Color(0xFF32ADE6);

  // --- Typography ---
  Color get textPrimary => isDark ? const Color(0xFFFFFFFF) : const Color(0xFF1C1C1E);
  Color get textSecondary => isDark ? const Color(0xFFAEAEB2) : const Color(0xFF636366);
  Color get textTertiary => isDark ? const Color(0xFF8E8E93) : const Color(0xFF8E8E93);
  Color get textHint => isDark ? const Color(0xFF636366) : const Color(0xFFAEAEB2);

  // --- Icons ---
  Color get icon => isDark ? const Color(0xFFFFFFFF) : const Color(0xFF1C1C1E);
  Color get iconSecondary => isDark ? const Color(0xFFAEAEB2) : const Color(0xFF636366);

  // --- Liquid Glass / Soft Glass Tokens ---
  Color get glassBg => isDark
      ? const Color(0xFF1C1C1E).withValues(alpha: 0.72)
      : Colors.white.withValues(alpha: 0.72);
  Color get glassPillBg => isDark
      ? Colors.white.withValues(alpha: 0.16)
      : Colors.white.withValues(alpha: 0.90);
  Color get glassBorder => isDark
      ? Colors.white.withValues(alpha: 0.18)
      : Colors.black.withValues(alpha: 0.08);
  Color get glassHighlight => isDark
      ? Colors.white.withValues(alpha: 0.22)
      : Colors.white.withValues(alpha: 0.95);

  // --- Dividers & Shadows ---
  Color get divider => isDark
      ? Colors.white.withValues(alpha: 0.10)
      : Colors.black.withValues(alpha: 0.07);
  Color get shadow => isDark
      ? Colors.black.withValues(alpha: 0.45)
      : Colors.black.withValues(alpha: 0.08);

  // --- Inputs & Search ---
  Color get inputFill => isDark
      ? const Color(0xFF2C2C2E)
      : const Color(0xFFE9E9EE);
  Color get inputBorder => isDark
      ? Colors.white.withValues(alpha: 0.12)
      : Colors.black.withValues(alpha: 0.08);
  Color get searchBg => isDark
      ? const Color(0xFF2C2C2E)
      : const Color(0xFFE5E5EA);

  // --- Navigation ---
  Color get navBar => isDark ? const Color(0xFF161618) : const Color(0xFFFFFFFF);
  Color get navInactive => isDark ? const Color(0xFFD1D1D6) : const Color(0xFF1C1C1E);

  // --- Subtle Card Gradient ---
  LinearGradient get cardGradient => isDark
      ? const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF222226), Color(0xFF171719)],
        )
      : const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFFFFF), Color(0xFFFBFBFD)],
        );
}
