import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../services/animation_speed_service.dart';
import '../services/appearance_service.dart';
import '../theme/app_colors.dart';
import '../theme/theme_provider.dart';
import '../widgets/liquid_glass_surface.dart';
import '../widgets/tempo_sliver_header.dart';
import '../widgets/tempo_spring_physics.dart';

/// BitChord-inspired Appearance settings screen giving fine-grained control
/// over Theme (`System | Light | Dark`), Reduce animation, Reduce Dynamic Blur,
/// Liquid Glass, Better Performance for Glass, and Progressive Blur.
class AppearanceSettingsScreen extends StatelessWidget {
  const AppearanceSettingsScreen({super.key});

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
                          _ThemeSegmentedControl(
                            selected: themeProvider.themeMode,
                            onSelect: (mode) {
                              HapticFeedback.selectionClick();
                              themeProvider.setThemeMode(mode);
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
                  ],
                ),
              ),
            ],
          );
        },
      ),
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

class _ThemeSegmentedControl extends StatelessWidget {
  final ThemeMode selected;
  final ValueChanged<ThemeMode> onSelect;

  const _ThemeSegmentedControl({
    required this.selected,
    required this.onSelect,
  });

  static const _modes = <ThemeMode>[
    ThemeMode.system,
    ThemeMode.light,
    ThemeMode.dark,
  ];

  static String _label(ThemeMode m) => switch (m) {
        ThemeMode.system => 'System',
        ThemeMode.light => 'Light',
        ThemeMode.dark => 'Dark',
      };

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final activeIdx = _modes.indexOf(selected).clamp(0, _modes.length - 1);
    final alignX = -1.0 + (2.0 * activeIdx / (_modes.length - 1));
    final dur = TempoAppearanceService.instance.reduceAnimation
        ? Duration.zero
        : TempoAnimationSpeedService.instance.scale(
            const Duration(milliseconds: 260),
          );

    return Container(
      height: 38,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: c.searchBg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Stack(
        children: [
          AnimatedAlign(
            duration: dur,
            curve: TempoSpringCurves.morphOpen,
            alignment: Alignment(alignX, 0.0),
            child: FractionallySizedBox(
              widthFactor: 1.0 / _modes.length,
              heightFactor: 1.0,
              child: Container(
                decoration: BoxDecoration(
                  color: c.isDark ? const Color(0xFF2C2C34) : Colors.white,
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(
                        alpha: c.isDark ? 0.28 : 0.08,
                      ),
                      blurRadius: 6,
                      offset: const Offset(0, 1.5),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Row(
            children: List.generate(_modes.length, (i) {
              final mode = _modes[i];
              final isSelected = i == activeIdx;
              return Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onSelect(mode),
                  child: Center(
                    child: Text(
                      _label(mode),
                      style: TextStyle(
                        color: isSelected ? c.textPrimary : c.textSecondary,
                        fontSize: 13.5,
                        fontWeight:
                            isSelected ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}
