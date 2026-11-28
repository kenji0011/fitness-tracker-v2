import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:jiggicons/jiggicons.dart';
import 'package:provider/provider.dart';

import '../services/animation_speed_service.dart';
import '../services/appearance_service.dart';
import '../services/device_performance_service.dart';
import '../theme/app_colors.dart';
import '../theme/theme_provider.dart';
import '../widgets/bitchord_segmented_slider.dart';
import '../widgets/hyperos_dropdown_menu.dart';
import '../widgets/liquid_glass_surface.dart';
import '../widgets/tempo_jigg_icon.dart';
import '../widgets/tempo_sliver_header.dart';

/// BitChord-inspired Appearance settings screen giving fine-grained control
/// over Theme (`System | Light | Dark`), Animation speed (`Relaxed | Balanced |
/// Fast`), Reduce animation, Reduce Dynamic Blur, Liquid Glass, Better
/// Performance for Glass, and Progressive Blur.
class AppearanceSettingsScreen extends StatefulWidget {
  const AppearanceSettingsScreen({super.key});

  @override
  State<AppearanceSettingsScreen> createState() =>
      _AppearanceSettingsScreenState();
}

class _AppearanceSettingsScreenState extends State<AppearanceSettingsScreen> {
  final GlobalKey _animSpeedRowKey = GlobalKey();
  final JiggIconController _animSpeedJiggController = JiggIconController();
  bool _animSpeedMenuOpen = false;

  @override
  void dispose() {
    _animSpeedJiggController.dispose();
    super.dispose();
  }

  Future<void> _openAnimationSpeedMenu() async {
    final speedService = TempoAnimationSpeedService.instance;
    HapticFeedback.selectionClick();
    _animSpeedJiggController.play();
    setState(() => _animSpeedMenuOpen = true);
    final picked = await showHyperOsDropdownMenu<TempoAnimationSpeed>(
      context: context,
      rowKey: _animSpeedRowKey,
      selectedValue: speedService.speed,
      options: const [
        HyperOsDropdownOption(
          value: TempoAnimationSpeed.relaxed,
          label: 'Relaxed',
        ),
        HyperOsDropdownOption(
          value: TempoAnimationSpeed.balanced,
          label: 'Balanced',
        ),
        HyperOsDropdownOption(
          value: TempoAnimationSpeed.fast,
          label: 'Fast',
        ),
      ],
    );
    if (picked != null) {
      await speedService.setSpeed(picked);
    }
    if (mounted) {
      setState(() => _animSpeedMenuOpen = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final themeProvider = context.watch<ThemeProvider>();

    return Scaffold(
      backgroundColor: c.scaffold,
      body: ValueListenableBuilder<TempoAppearanceSettings>(
        valueListenable: TempoAppearanceService.instance.notifier,
        builder: (context, settings, _) {
          final svc = TempoAppearanceService.instance;
          final glassSubEnabled =
              settings.liquidGlass && !settings.reduceDynamicBlur;

          return CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              const TempoSliverHeader(
                title: 'Appearance',
                showBackButton: true,
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(18, 6, 18, 48),
                sliver: SliverList.list(
                  children: [
                    // 1. Theme (System | Light | Dark)
                    _sectionLabel('THEME', c),
                    AppleCard(
                      borderRadius: 24,
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              _badge(
                                CupertinoIcons.circle_lefthalf_fill,
                                const Color(0xFF7A6FF0),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Text(
                                  'Theme',
                                  style: TextStyle(
                                    color: c.textPrimary,
                                    fontSize: 15.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          BitChordSegmentedSlider(
                            height: 38,
                            labels: const ['System', 'Light', 'Dark'],
                            selectedIndex: switch (themeProvider.themeMode) {
                              ThemeMode.system => 0,
                              ThemeMode.light => 1,
                              ThemeMode.dark => 2,
                            },
                            trackColor: c.searchBg,
                            onChanged: (idx) {
                              const modes = <ThemeMode>[
                                ThemeMode.system,
                                ThemeMode.light,
                                ThemeMode.dark,
                              ];
                              themeProvider.setThemeMode(modes[idx]);
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // 2. Motion & Blur
                    _sectionLabel('MOTION & BLUR', c),
                    _groupedCard(
                      c: c,
                      children: [
                        _animationSpeedRow(
                          c: c,
                          enabled: !settings.reduceAnimation,
                        ),
                        _toggleRow(
                          c: c,
                          icon: CupertinoIcons.bolt_slash_fill,
                          badgeColor: const Color(0xFFFF9F0A),
                          title: 'Reduce animation',
                          subtitle:
                              'Snap tabs and transitions without spring lifts or squashes',
                          value: settings.reduceAnimation,
                          onChanged: (v) {
                            HapticFeedback.selectionClick();
                            svc.setReduceAnimation(v);
                          },
                        ),
                        _toggleRow(
                          c: c,
                          icon: CupertinoIcons.drop_triangle,
                          badgeColor: const Color(0xFF56B7FF),
                          title: 'Reduce Dynamic Blur',
                          subtitle:
                              'Replace live backdrop blurs with solid surfaces for speed',
                          value: settings.reduceDynamicBlur,
                          onChanged: (v) {
                            HapticFeedback.selectionClick();
                            svc.setReduceDynamicBlur(v);
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // 3. Liquid Glass & Sub-options
                    _sectionLabel('GLASS & EFFECTS', c),
                    _groupedCard(
                      c: c,
                      children: [
                        _toggleRow(
                          c: c,
                          icon: CupertinoIcons.sparkles,
                          badgeColor: c.accent,
                          title: 'Liquid Glass',
                          subtitle:
                              'Optical refraction across the navbar and floating controls',
                          value: settings.liquidGlass,
                          enabled: !settings.reduceDynamicBlur,
                          onChanged: (v) {
                            HapticFeedback.selectionClick();
                            svc.setLiquidGlass(v);
                          },
                        ),
                        _toggleRow(
                          c: c,
                          icon: CupertinoIcons.speedometer,
                          badgeColor: const Color(0xFF34C759),
                          title: 'Better Performance for Glass',
                          subtitle:
                              'Use frosted blur without live GPU lens refraction shaders',
                          value: settings.betterGlassPerformance,
                          enabled: glassSubEnabled,
                          onChanged: (v) {
                            HapticFeedback.selectionClick();
                            svc.setBetterGlassPerformance(v);
                          },
                        ),
                        _toggleRow(
                          c: c,
                          icon: CupertinoIcons.layers_alt_fill,
                          badgeColor: const Color(0xFF6B63F6),
                          title: 'Progressive Blur',
                          subtitle:
                              'Softly blur scrolled content fading behind top headers',
                          value: settings.progressiveBlur,
                          enabled: glassSubEnabled,
                          onChanged: (v) {
                            HapticFeedback.selectionClick();
                            svc.setProgressiveBlur(v);
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // 4. Chipset-Aware Device Performance Profile
                    _sectionLabel('DEVICE PROFILE', c),
                    _deviceProfileCard(c: c, settings: settings, svc: svc),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _animationSpeedRow({
    required AppColors c,
    required bool enabled,
  }) {
    return ValueListenableBuilder<TempoAnimationSpeed>(
      valueListenable: TempoAnimationSpeedService.instance.notifier,
      builder: (context, currentSpeed, _) {
        return Opacity(
          opacity: enabled ? 1.0 : 0.45,
          child: AnimatedContainer(
            key: _animSpeedRowKey,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            color: _animSpeedMenuOpen
                ? (c.isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.black.withValues(alpha: 0.045))
                : Colors.transparent,
            child: InkWell(
              onTap: enabled ? _openAnimationSpeedMenu : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: c.accent,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: TempoJiggIcon(
                          'flash',
                          variant: JiggIconVariant.solid,
                          color: Colors.white,
                          size: 16,
                          controller: _animSpeedJiggController,
                          trigger: JiggIconTrigger.none,
                          fallbackIcon: CupertinoIcons.speedometer,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Animation speed',
                            style: TextStyle(
                              color: c.textPrimary,
                              fontSize: 15.5,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Adjust transition tempo across pages, sheets, and popovers',
                            style: TextStyle(
                              color: c.textSecondary,
                              fontSize: 12.5,
                              height: 1.25,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    AnimatedOpacity(
                      opacity: _animSpeedMenuOpen ? 0.0 : 1.0,
                      duration: const Duration(milliseconds: 150),
                      curve: Curves.easeOutCubic,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            currentSpeed.label,
                            style: TextStyle(
                              color: c.textSecondary,
                              fontSize: 14.5,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Icon(
                            CupertinoIcons.chevron_up_chevron_down,
                            color: c.textTertiary,
                            size: 13.5,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _deviceProfileCard({
    required AppColors c,
    required TempoAppearanceSettings settings,
    required TempoAppearanceService svc,
  }) {
    return ValueListenableBuilder<DevicePerformanceRecommendation>(
      valueListenable: DevicePerformanceService.instance.notifier,
      builder: (context, rec, _) {
        final isRecommended = settings == rec.recommendedSettings;
        final tierColor = switch (rec.tier) {
          DevicePerformanceTier.flagship => c.accent,
          DevicePerformanceTier.balanced => const Color(0xFF34C759),
          DevicePerformanceTier.lite => const Color(0xFF56B7FF),
        };
        final ramText = rec.profile.ramLabel;
        final refreshText = rec.profile.maxRefreshRateHz >= 85
            ? '${rec.profile.maxRefreshRateHz.round()} Hz'
            : '';
        final hwMeta = [
          if (ramText.isNotEmpty) ramText,
          if (refreshText.isNotEmpty) refreshText,
        ].join(', ');

        return AppleCard(
          borderRadius: 24,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _badge(CupertinoIcons.device_phone_portrait, tierColor),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          rec.chipsetDisplayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: c.textPrimary,
                            fontSize: 15.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (hwMeta.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            hwMeta,
                            style: TextStyle(
                              color: c.textSecondary,
                              fontSize: 12.5,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: tierColor.withValues(alpha: c.isDark ? 0.22 : 0.13),
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(
                      rec.tier.label,
                      style: TextStyle(
                        color: tierColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                isRecommended
                    ? 'Using recommended defaults for this chipset: ${rec.tier.summary.toLowerCase()}.'
                    : 'Custom appearance settings active. Recommended for this chipset: ${rec.tier.summary.toLowerCase()}.',
                style: TextStyle(
                  color: c.textSecondary,
                  fontSize: 12.5,
                  height: 1.38,
                ),
              ),
              if (!isRecommended) ...[
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: TempoLiquidButton(
                    primary: false,
                    height: 44,
                    onPressed: () {
                      HapticFeedback.selectionClick();
                      svc.resetToDeviceDefaults();
                    },
                    child: const Text(
                      'Restore Recommended',
                      style: TextStyle(fontSize: 14),
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _sectionLabel(String text, AppColors c) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Text(
        text,
        style: TextStyle(
          color: c.textTertiary,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.65,
        ),
      ),
    );
  }

  Widget _badge(IconData icon, Color color) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: Icon(icon, color: Colors.white, size: 16),
    );
  }

  Widget _groupedCard({
    required AppColors c,
    required List<Widget> children,
  }) {
    final items = <Widget>[];
    for (int i = 0; i < children.length; i++) {
      if (i > 0) {
        items.add(
          Divider(
            height: 0.6,
            thickness: 0.6,
            indent: 62,
            endIndent: 16,
            color: c.divider,
          ),
        );
      }
      items.add(children[i]);
    }
    return AppleCard(
      borderRadius: 24,
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(mainAxisSize: MainAxisSize.min, children: items),
    );
  }

  Widget _toggleRow({
    required AppColors c,
    required IconData icon,
    required Color badgeColor,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    bool enabled = true,
  }) {
    return Opacity(
      opacity: enabled ? 1.0 : 0.45,
      child: InkWell(
        onTap: enabled ? () => onChanged(!value) : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          child: Row(
            children: [
              _badge(icon, badgeColor),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: c.textPrimary,
                        fontSize: 15.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: c.textSecondary,
                        fontSize: 12.5,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              CupertinoSwitch(
                activeTrackColor: c.accent,
                value: value,
                onChanged: enabled ? onChanged : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
