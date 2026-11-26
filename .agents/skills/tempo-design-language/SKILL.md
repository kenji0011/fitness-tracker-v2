---
name: tempo-design-language
description: >-
  Tempo's official iOS 27 / HyperOS 3 Liquid Glass & Motion Design Language
  (calibrated with BitChord's optical glass & spring physics). Read this skill
  before designing, building, or updating any screen, button, sheet, popover,
  navigation bar, or animation in the Tempo Fitness app.
---

# Tempo Design Language (Liquid Glass & Motion System)

Tempo uses an **iOS 27 / HyperOS 3 inspired Liquid Glass** aesthetic paired with **Apple Health / Mi Fitness** data clarity and **BitChord-calibrated spring physics** (`kushagrasinghx/BitChord`). Every screen must support both **Light Mode (default)** and **Dark Mode** cleanly at **120Hz**.

---

## 1. Brand Identity & Color Tokens (`lib/theme/app_colors.dart`)

Always read colors via `final c = AppColors.of(context);` — never hardcode page backgrounds or light-only colors.

| Token | Light Mode | Dark Mode | Usage |
| :--- | :--- | :--- | :--- |
| `c.accent` (**Tempo Orange**) | `#FF6A24` | `#FF7A33` | Unified brand accent: primary CTAs, active nav tab, toggles, focus borders, active chips, heatmap intensity, spotlight rings |
| `c.scaffold` | `#F4F5F7` | `#0B0B0D` | Page canvas |
| `c.card` | `#FFFFFF` | `#16161A` | Grouped `AppleCard` surfaces (`borderRadius: 22–26`) |
| `c.searchBg` | `#EFEFF3` | `#232329` | Recessed input bars, secondary pills, steppers |
| `c.moveRed` | `#FF3B30` | `#FF453A` | Destructive actions & error toasts |
| Ring / Metric Accents | Calories `#F36432`, Steps `#93DC2A`, Activity `#56B7FF`, Weight `#4CD964`, Sleep `#6B63F6`, Waist `#3CC29E`, Water `#38BDF8` | Same high-contrast accents | Per-metric circular icon badges & sparklines only |

---

## 2. Liquid Glass Material Spec

- **Crystal-Clear iOS 26/27 Backdrop Blur:** `BackdropFilter(filter: ImageFilter.blur(sigmaX: 20–26, sigmaY: 20–26))` inside `ClipRRect` / `ClipOval` with translucent neutral fills (`LiquidGlassPalette.surfaceGradient`: ~`48–64%` Light / `46–54%` Dark) so cards & colors softly shimmer behind floating docks and top action circles.
- **Dual-Lobe Directional Specular Rim (`LiquidGlassRimPainter`):** Always use `LiquidGlassRimPainter` (in `liquid_glass_surface.dart`) aligned with `shaders/liquid_glass_lens.frag` (`lightDir = (0.62, 0.78)`): bright top-left specular caustic + counter bottom-right reflection (`SweepGradient` `1.2px`), curved top inner meniscus glint, and a subtle `0.7px` outer hairline contour so crystal glass stays razor-sharp even on pure white cards.
- **3D Domed Navbar Active Pill & GPU Refraction Droplet:** The floating navbar uses `LiquidGlassPalette.activeLensGradient` + `LiquidGlassRimPainter` for an elevated pure-neutral domed glass pill at rest, seamlessly morphing into `shaders/liquid_glass_lens.frag` (`ui.FragmentProgram`) with screen-space SDF refraction & chromatic dispersion on tap/drag/hover.
- **Always-On Top Header Glass Bubbles (`TempoGlassCircleButton`):** All top circular action buttons (`+`, `⋮`, `<` Back, Camera, Calendar, Search, Compare, Edit) render as crisp floating Liquid Glass bubbles even at `scrollOffset == 0` (`glassOpacity` defaults to `1.0`), deepening frost and specular rim sheen on scroll or droplet squish press.
- **Neutral Transparent Glass (No Blue Tint):** The floating navbar, active pill, and glass controls stay optically neutral — never apply a blue glass wash.
- **Critical Performance Rule (No `Opacity` Around `BackdropFilter`):** Never wrap a `BackdropFilter` in an `Opacity` widget during animations — Impeller allocates a `saveLayer` per frame and causes blur pop/stutter on close. Instead, animate `sigmaX/sigmaY`, surface fill alpha, rim intensity, shadow alpha, and inner content `Opacity` directly.

---

## 3. BitChord-Calibrated Motion & Spring Physics

| Interaction | Curve / Spring | Timing | Exact Behavior |
| :--- | :--- | :--- | :--- |
| **Liquid Glass Button Press** (`TempoLiquidButton`, `TempoGlassCircleButton`) | Down: `easeOutCubic` (`105–110ms`) / Up: `easeOutBack` (`280–290ms`) | Volume-preserving droplet squish | Press squishes `scaleX: 1.045–1.09, scaleY: 0.92–0.945`, boosts glass rim sheen, and springs smoothly back on release with `HapticFeedback.selectionClick()`. |
| **Navbar Liquid Droplet Slide** (`LiquidGlassNavBar`) | `easeOutCubic` + `STRETCH = 0.16`, `SQUASH = 0.50` | `340ms` | Elongates horizontally along travel (`+16%`), counter-squashes vertically (`-50%` of stretch) so icons stay crisp. |
| **Navbar Scroll Minimize** (`TempoShellScreen` → `LiquidGlassNavBar.minimized`) | `easeOutCubic` | `300ms` / `320ms` | Scrolling down `>= 48px` morphs the navbar into a compact centered **icons-only liquid capsule** (`maxWidth: 460 → 272`, `height: 64 → 52`, labels fade & collapse). Stays minimized across tab switches; expands only when the user manually scrolls up `>= 36px` (`UserScrollNotification` / active upward drag, ignoring bottom overscroll bounce-back). |
| **3-Dots Liquid Popover** (`showTempoPopoverMenu` in `ios_popover_menu.dart`) | Open: Critically damped spring (`stiffness: 600, damping: 49`) / Close: `fastOutSlowIn` | `300ms` open / `220ms` close | Anchored directly over the 3-dots circle (`Alignment.topRight`), liquid-morphing from `scaleX: 0.28, scaleY: 0.24, radius: 30` into the frosted panel (`radius: 24`) and retracting seamlessly back into the circle. Menu rows fade slightly ahead on close so text never crunches. |
| **Bottom Sheets & Modals** (`showTempoSheet` in `ios_stretch_sheet.dart`) | iOS spring + upward rubber-band stretch | Native spring | Standardized across **all** modals (Weight, Sleep, Profile, Progress Album, Backup, Custom Workout actions, Completion summaries). Never mix raw Material bottom sheets or Cupertino dialogs. |
| **Tab Transitions** (`TempoShellScreen._AnimatedTabPane`) | `easeOutCubic` | `180ms` | `AnimatedOpacity` (`0 ↔ 1`) + `AnimatedScale` (`0.985 ↔ 1.0`). **Always place `TickerMode(enabled: active)` INSIDE `AnimatedOpacity`/`AnimatedScale`** so inactive tabs finish fading out cleanly instead of freezing on top of the stack. |
| **Card Tap Feedback** (`AppleCard`) | `easeOutCubic` | `110ms` | Subtle `0.978` tactile press scale on interactive cards. |
| **Summary Grid Reorder** (`ReorderableSummaryGrid`) | `AnimatedPositioned` `easeOutCubic` (`240ms`) | Hold + drag | Long-press lifts tile (`scale: 1.045`, shadow + Tempo Orange drop frame); neighboring tiles glide smoothly into new slots with haptic ticks; persists order per profile. |
| **Startup Splash Screen** (`TempoStartupSplash` in `tempo_startup_splash.dart`) | Beat 0 hold (`100ms`) → Beat 1 dip `easeInOutCubic` (`168ms`, `1.0x → 0.82x`) → Beat 2 optical logarithmic zoom `Cubic(0.68, 0.0, 0.24, 1.0)` (`572ms`, `0.82x → screen clear`) | `840ms` total (`220ms` fade if reduced-motion) | Midnight Obsidian (`#0B101A`) canvas with pure vector `116dp` Tempo Dual-Ring matching Android 12+ `ic_tempo_splash.xml`. Uses persistent `Stack` + `ScaleTransition` (never reparenting `child` on completion so `State` & shaders never re-init), per-ring off-screen culling, and a single-pass `PathFillType.evenOdd` portal. |

---

## 4. Core Component & Pattern Library

- **Headers (`TempoSliverHeader`):** Collapsing large left-aligned title → centered compact title with `TempoGlassCircleButton` back/action bubbles (always translucent glass, deepening on scroll).
- **Primary & Secondary Glass CTAs (`TempoLiquidButton`):** Use `primary: true` (Tempo Orange frosted glass) for primary save/start actions and `primary: false` (clear frosted glass) for secondary actions (`+ Custom`, `Manage health features`, etc.).
- **Feedback Toasts (`showTempoToast`):** Frosted floating top pill below the status bar (`tempo_toast.dart`). **Never use bottom `SnackBar`** — it collides with the floating Liquid Glass navbar.
- **Metric Detail Pages (`WeightDetailScreen`, `SleepDetailScreen`, `WaterDetailScreen`, `MetricDetailScreen`):** Unified layout with top date selector → `HistoryCalendarScreen`, `⋮` liquid popover (`All data`, `Add data`, `Unit` / `Daily goal`), `Latest | Week | M | Y` tabs, and `280ms` morphing trend charts.
- **Global Unit Sync (`WeightUnitHelper`):** Always format & parse weights using `WeightUnitHelper` (`kg` / `lb` stored per profile in local SQLite).
- **Drum-Wheel Pickers (`AddDataScreen` / `TempoWheelColumn` & `TempoWheelStage`):** Use HyperOS 3 Clock-inspired 5-row vertical drum wheels (`FixedExtentScrollPhysics` + `BouncingScrollPhysics`, top/bottom `ShaderMask` fade, haptic click per tick) with metric-accurate units (`hrs : min` for Sleep & Activity, whole `.` decimal for Weight `kg`/`lb` and Waist `cm`, thousands `,` hundreds for `steps`, `kcal` for Calories, `ml` for Water, `cm` for Height). Always show live measurement units permanently.
- **First-Time Hints (`TempoSpotlightTour`):** Use `TempoSpotlightTour.showIfNeeded(...)` for one-time contextual coach marks per screen/profile (auto-skipped in widget tests unless `ignoreTestGuard: true`).

---

## 5. Verification Checklist for Any UI Update

1. Verify **Light Mode** and **Dark Mode** contrast & specular rim legibility.
2. Check **zero** `BackdropFilter` inside `Opacity` and **zero** `AnimatedOpacity` inside `TickerMode`.
3. Run `flutter analyze` (**0 issues**) and `flutter test` (**all green**).
4. Bump version via `scripts/bump_version.ps1` (`+0.0.1`) before building verified `release/Tempo.apk`.
