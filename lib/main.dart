import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/intro_walkthrough_screen.dart';
import 'screens/profile_switcher_screen.dart';
import 'screens/tempo_shell_screen.dart';
import 'services/active_profile_provider.dart';
import 'theme/app_theme.dart';
import 'theme/theme_provider.dart';
import 'widgets/liquid_glass_surface.dart';
import 'widgets/tempo_jigg_icon.dart';
import 'widgets/tempo_startup_splash.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Keep decoded thumbnails and avatars warm in memory during smooth scrolling.
  PaintingBinding.instance.imageCache
    ..maximumSize = 200
    ..maximumSizeBytes = 120 << 20;

  final activeProfileProvider = ActiveProfileProvider();
  final themeProvider = ThemeProvider(autoLoad: false);
  await Future.wait([
    activeProfileProvider.initialize(),
    themeProvider.initialize(),
    TempoJiggicons.prewarm(),
    TempoLiquidShaderCache.load(),
  ]);

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: themeProvider),
        ChangeNotifierProvider.value(value: activeProfileProvider),
      ],
      child: const TempoApp(),
    ),
  );
}

class TempoApp extends StatelessWidget {
  const TempoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, _) {
        const transitions = PageTransitionsTheme(
          builders: <TargetPlatform, PageTransitionsBuilder>{
            TargetPlatform.android: CupertinoPageTransitionsBuilder(),
            TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
            TargetPlatform.windows: CupertinoPageTransitionsBuilder(),
            TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
            TargetPlatform.linux: CupertinoPageTransitionsBuilder(),
          },
        );

        return MaterialApp(
          title: 'Tempo',
          debugShowCheckedModeBanner: false,
          scrollBehavior: const AppScrollBehavior(),
          themeMode: themeProvider.themeMode,
          theme: AppTheme.lightTheme.copyWith(pageTransitionsTheme: transitions),
          darkTheme: AppTheme.darkTheme.copyWith(pageTransitionsTheme: transitions),
          home: const TempoStartupSplash(
            child: _TempoRootGate(),
          ),
        );
      },
    );
  }
}

class _TempoRootGate extends StatelessWidget {
  const _TempoRootGate();

  @override
  Widget build(BuildContext context) {
    final profileProvider = context.watch<ActiveProfileProvider>();

    if (profileProvider.isLoading) {
      return const Scaffold(
        backgroundColor: kTempoSplashBackground,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TempoDualRingLogo(size: kTempoSplashLogoSize),
              SizedBox(height: 24),
              CupertinoActivityIndicator(
                radius: 13,
                color: Color(0xFFFF7A33),
              ),
            ],
          ),
        ),
      );
    }

    final Widget child;
    if (!profileProvider.hasSeenIntro) {
      child = IntroWalkthroughScreen(
        key: const ValueKey('tempo_intro'),
        onComplete: () => profileProvider.completeIntro(),
      );
    } else if (profileProvider.activeProfile == null) {
      child = const ProfileGateScreen(key: ValueKey('tempo_profile_gate'));
    } else {
      child = const TempoShellScreen(key: ValueKey('tempo_shell'));
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 560),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (c, anim) => FadeTransition(
        opacity: anim,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.03),
            end: Offset.zero,
          ).animate(anim),
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.96, end: 1.0).animate(anim),
            child: c,
          ),
        ),
      ),
      child: child,
    );
  }
}

class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
      };

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    return const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics());
  }
}
