---
name: tempo-fluid-motion
description: >-
  Tempo's official 120Hz Impeller-native fluid motion & HyperOS 4 / iOS 26
  spring animation engineering skill. Use this skill whenever building,
  updating, debugging, or optimizing any route transition, container morph,
  app-icon launcher, circular header button, popover menu, dropdown, bottom
  sheet, photo viewer, or spring curve in the Tempo Fitness app.
---

# Tempo Fluid Motion (Locked-120Hz Impeller & HyperOS 4 Physics)

Tempo's animations are engineered for **locked 120Hz (`8.33 ms` frame budget)** on Flutter Impeller with **0 ms tap-to-interrupt responsiveness**, **zero black-bezel leaks**, and **real `SpringSimulation` dock bounce**. Never improvise custom `Cubic` routes or `Hero` flights when a Tempo primitive already exists.

---

## 1. Choose the Right Primitive First

| UI Pattern | Required API / File | Key Wiring Requirement |
| :--- | :--- | :--- |
| **Card → Page** (Summary/Stats/Library cards) | `pushTempoMorphRoute` (`lib/widgets/tempo_morph_route.dart`) | Pass `sourceContext`, `sourceBorderRadius`, optional `sourceColor`. Keep `waitForCloseAnimation: true` (default) so post-pop DB reloads run after close lands. |
| **Circular Header Button → Page** (`+`, Share, Camera) | `pushTempoMorphRoute` + `TempoGlassCircleButton(key: key)` | Pass `sourceKey: key`, `sourceBorderRadius: 999`. Anchor hides automatically via `activeTempoMorphAnchorKey` while staying clickable. |
| **Squircle App-Icon → Page** (Workout HIIT Burn / Strength / Cardio) | `pushTempoMorphRoute` + unscaled `56×56` `RepaintBoundary(key: iconKey)` | Pass `sourceKey: iconKey`, `sourceBorderRadius: 18`, `sourceColor: color`. Hide only the inner squircle via `activeTempoMorphAnchorKey`; keep outer `GestureDetector` & label untouched. |
| **Header Action Popover** (`+` / `⋮`) | `showTempoPopoverMenu` (`lib/widgets/ios_popover_menu.dart`) | Pass `anchorKey` and `anchorIcon`. Exact resting sizes (`22 dp` for `+`, `19 dp` for `⋮`) and glass gradient match `TempoGlassCircleButton` automatically. |
| **Settings Preference Dropdown** | `showHyperOsDropdownMenu` (`lib/widgets/hyperos_dropdown_menu.dart`) | Pass `rowKey` and `HyperOsDropdownOption<T>` list. |
| **Modal Bottom Sheet** | `showTempoSheet` (`lib/widgets/ios_stretch_sheet.dart`) | Never use raw `showModalBottomSheet` or Cupertino dialogs. |
| **Custom Spring Curves** | `TempoSpringCurve` / `TempoSpringCurves` (`lib/widgets/tempo_spring_physics.dart`) | Scale every duration with `TempoAnimationSpeedService.instance.scale(...)`. |

See [references/physics_and_recipes.md](./references/physics_and_recipes.md) for calibrated spring constants, copy-paste wiring recipes, and forensic debugging commands.

---

## 2. The 9 Non-Negotiable 120Hz Impeller Rules

1. **Invariant Keyed Widget Spine (Zero `GlobalKey` Reparenting):**
   Never switch between `return child;` (settled) and `return Stack(children: [..., child]);` (animating), and never swap sibling widget types around an unkeyed `child` inside a `Stack`. Always return the **exact same keyed slot structure** (`ValueKey` on every sibling, constant widget types) across `open → settled → close` so `Element.updateChildren` calls `deactivate()` **0 times** during transitions.
2. **Synchronous GPU Page Snapshot on Close (`didPop`):**
   Keep full-screen route children inside a permanent `RepaintBoundary`. Snapshot `boundary.toImageSync(pixelRatio: cappedDpr)` (longest edge capped at `1080 px`) inside `didPop()`, flip the live page `Offstage(offstage: true)`, and paint scrim + shadow + `BoxFit.cover` page snapshot ↔ source snapshot in **one paint-only `CustomPainter` pass** (zero live `BackdropFilter`, `CustomScrollView`, or `CustomPaint` rasterization during close).
   - Always guard `debugNeedsPaint` inside `assert(() { needsPaint = boundary.debugNeedsPaint; return true; }())` (reading it directly crashes release builds with `LateInitializationError`).
   - Track `_disposed` manually on `ui.Image` wrappers (never read `image.debugDisposed` in release builds).
3. **Paint-Only Geometry (Zero Per-Frame Relayout):**
   For full-screen morphs, drive clip & transform with `ClipRRect(clipper: ...)` + `Transform(transform: Matrix4)` + `CustomPaint` instead of animating `Positioned.fromRect` + `OverflowBox` (which marks `Stack` dirty for layout 120×/sec).
4. **Never Use `Cubic` with `x2 < x1`:**
   Use `TempoSpringCurve` (`SpringSimulation` + C1 Hermite smoothstep tail blend). Keep single-frame 120Hz step `< 0.095` and never flat-clamp a spring overshoot peak (scale overshoot proportionally along the approach vector instead).
5. **Zero `Opacity` Around `BackdropFilter` & Constant Blur Sigmas:**
   Never wrap a `BackdropFilter` in `Opacity` (forces per-frame `saveLayer` on Impeller). Keep `BackdropFilter` sigma constant (`22–24`) during motion so Impeller never recompiles blur kernels every 8.33 ms. Quantize any small-target (`< 115 dp`) `ImageFilter.blur` sigma to `0.5` steps; never apply `ImageFiltered` blur to full-screen widgets. Keep shadow `MaskFilter.blur` sigma constant (`14.0`) and skip drawing shadows when container inset `<= 2 px`.
6. **Option A Clean Pinned Background (Zero `#000000` Bezel):**
   Never apply unbacked `Transform.scale(0.96)` via `secondaryAnimation` on stacked routes — it leaks Flutter's raw `#000000` canvas around Light Mode edges and doubles GPU fill-rate. Use the top route's airy scrim only.
7. **0 ms Rapid Interruptibility & Stale-Droplet Yielding:**
   - Override `buildModalBarrier()` on every custom `ModalRoute` / `PopupRoute` to return `const SizedBox.shrink()` the instant `animation.status` enters `reverse` or `dismissed`, and wrap closing visuals in `IgnorePointer(ignoring: isClosing)`.
   - Keep `GestureDetector` mounted on hidden anchor slots while flying.
   - Track per-key route/popover ownership (`Map<Key, Owner>`): when a rapid re-tap pushes a newer route for the same `Key` mid-close, clone the previous route's GPU snapshot (`image.clone()`), claim ownership, immediately yield the stale closing droplet, and only clear the anchor notifier if `identical(owner, this)`.
8. **Defer Post-Pop Database Reloads Until `route.completed`:**
   `Navigator.pop()` resolves `route.popped` on **Frame 0** of close. Always await `route.completed` (`waitForCloseAnimation: true` in `pushTempoMorphRoute`) before running SQLite queries or `setState()` on the underlying screen.
9. **Pixel-Exact Handoff Parity & Speed Scaling:**
   - Match floating glyph size (`22 dp` `+`, `19 dp` `⋮`), resting glass gradient colors, and corner radius ratio (`startRadius / sourceSize`) 1:1 with the resting button/squircle, reaching full glyph crispness **before** the droplet arrives at its slot.
   - Scale all `transitionDuration` and `reverseTransitionDuration` values through `TempoAnimationSpeedService.instance.scale(...)` so **Relaxed (`1.32×`)**, **Balanced (`1.00×`)**, and **Fast (`0.65×`)** stay unified across the app.

---

## 3. Mandatory Verification Workflow

After adding or modifying any animation in Tempo:

1. **Static & Automated Regression Checks:**
   ```powershell
   flutter analyze --no-pub
   flutter test --no-pub
   ```
   Verify all tests in `test/tempo_morph_route_test.dart` and `test/widget_test.dart` pass, including:
   - Exact spring endpoints (`0.0 → 0.0`, `1.0 → 1.0`) and bounded 120Hz step (`< 0.095`).
   - `deactivateCount == 0` across `open → settled → close` (zero reparenting).
   - `80 ms` mid-close single-tap interruption (0 ms re-open responsiveness).
2. **Real-Device 120Hz Release Verification (when phone is connected via ADB):**
   Build with the Windows Gradle 5-try retry guard, install onto the connected device, and inspect frame percentiles if debugging jank:
   ```powershell
   adb shell dumpsys gfxinfo com.tempo.fitness reset
   # exercise open/close transitions on device, then:
   adb shell dumpsys gfxinfo com.tempo.fitness | Select-String "Total frames|Janky frames|percentile"
   ```
   See [references/physics_and_recipes.md](./references/physics_and_recipes.md) for the full release-build retry snippet and video frame-diff audit recipe.
