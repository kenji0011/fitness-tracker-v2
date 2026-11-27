# Tempo Fluid Motion — Spring Presets, Recipes & Diagnostics

## 1. Calibrated Spring Presets (`lib/widgets/tempo_spring_physics.dart`)

All durations below are **Balanced (`1.00×`)** baselines and scale automatically via `TempoAnimationSpeedService.instance.scale(...)` (`Relaxed = 1.32×`, `Fast = 0.65×`).

| Preset | Stiffness | Damping | `ζ` | Duration | Purpose & Feel |
| :--- | :---: | :---: | :---: | :---: | :--- |
| `morphOpen` | `225` | `29.6` | `0.99` | `460 ms` | Card-to-page open (monotonic, lush settle) |
| `morphClose` | `185` | `19.0` | `0.70` | `470 ms` | Page-to-card close (`~2.2%` soft dock cushion) |
| `dropletOpenSize` | `220` | `29.4` | `0.99` | `460 ms` | Circular/squircle icon expansion (trails center slightly) |
| `dropletOpenCenter` | `290` | `33.4` | `0.98` | `460 ms` | Circular/squircle center launch (floating lift-off) |
| `dropletCloseSize` | `190` | `17.6` | `0.64` | `540 ms` | Slow creamy icon collapse + liquid dock squish (`~38 dp → 42 dp`) |
| `dropletCloseCenter` | `155` | `16.0` | `0.64` | `540 ms` | Trailing glide + smooth `~3.8 px` parabolic dock bounce |
| `popoverOpenCenter` | `460` | `33.4` | `0.78` | `460 ms` | HyperOS 4 detached arc launch (`~1.2%` elastic bloom) |
| `popoverOpenSize` | `220` | `24.6` | `0.83` | `460 ms` | Popover surface bloom |
| `popoverCloseSize` | `240` | `19.6` | `0.63` | `470 ms` | Unhurried popover droplet collapse + soft squish |
| `popoverCloseCenter` | `190` | `17.6` | `0.64` | `470 ms` | Smooth return + soft parabolic dock settle |
| `dropdownUnfold` | `340` | `29.0` | `0.79` | `340 ms` | Settings dropdown vertical unfold (`~1.4%` settle) |
| `dropdownFoldClose` | `255` | `23.0` | `0.72` | `340 ms` | Smooth cushioned fold-back |
| `sheetOpen` | `300` | `28.5` | `0.82` | `440 ms` | iOS bottom sheet glide up |
| `sheetClose` | `340` | `36.8` | `1.00` | `260 ms` | Crisp sheet dismissal over true `_sheetHeight` |
| `photoOpen` / `photoClose` | `260` / `275` | `31.8` / `32.8` | `0.99` | `420` / `360 ms` | Progress Album `BoxFit.contain` orientation-exact flight |

---

## 2. Copy-Paste Wiring Recipes

### A. Circular Glass Header Button → Full Screen
```dart
final GlobalKey _actionKey = GlobalKey();

TempoGlassCircleButton(
  key: _actionKey,
  tooltip: 'Share progress',
  icon: Icon(CupertinoIcons.share, size: 19, color: c.textPrimary),
  onPressed: () async {
    await pushTempoMorphRoute<void>(
      context: context,
      sourceKey: _actionKey,
      sourceBorderRadius: 999,
      builder: (_) => const MyTargetScreen(),
    );
    // Runs cleanly AFTER close animation finishes (waitForCloseAnimation: true).
    if (mounted) _reloadData();
  },
);
```

### B. Squircle App-Icon Launcher (`56×56`, `borderRadius: 18`) → Full Screen
Keep `GestureDetector` outside `AnimatedBuilder(activeTempoMorphAnchorKey)` and place `RepaintBoundary(key: iconKey)` strictly around the **unscaled** `56×56` squircle container (never around the text label or an outer `AnimatedScale`):

```dart
SizedBox.square(
  dimension: 56,
  child: AnimatedBuilder(
    animation: activeTempoMorphAnchorKey,
    builder: (_, __) {
      if (identical(activeTempoMorphAnchorKey.value, iconKey)) {
        return const SizedBox.square(dimension: 56);
      }
      return RepaintBoundary(
        key: iconKey,
        child: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: tileColor,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Icon(iconData, color: Colors.white, size: 28),
        ),
      );
    },
  ),
);
```

Then push with:
```dart
await pushTempoMorphRoute<void>(
  context: context,
  sourceKey: iconKey,
  sourceBorderRadius: 18,
  sourceColor: tileColor,
  builder: (_) => const DestinationScreen(),
);
```

### C. Header Popover Menu (`+` or `⋮`)
```dart
showTempoPopoverMenu(
  context: context,
  anchorKey: _moreButtonKey,
  anchorIcon: CupertinoIcons.add, // automatically uses 22 dp; ⋮ uses 19 dp
  actions: [
    TempoPopoverAction(label: 'Add data', onTap: _openAddSheet),
    TempoPopoverAction(label: 'All data', onTap: _openAllData),
  ],
);
```

### D. Zero-Delay Modal Barrier Override (For Any New Custom Route)
```dart
@override
Widget buildModalBarrier() {
  final anim = animation;
  if (anim == null) return const SizedBox.shrink();
  return AnimatedBuilder(
    animation: anim,
    builder: (context, _) {
      if (anim.status == AnimationStatus.reverse ||
          anim.status == AnimationStatus.dismissed) {
        return const SizedBox.shrink();
      }
      return super.buildModalBarrier();
    },
  );
}
```
Also wrap the closing transition root in `IgnorePointer(ignoring: isClosing)`.

---

## 3. Forensic Stutter Audit & Windows Release Build Commands

### Release APK Build with Windows Gradle Bind-Error Retry Guard
```powershell
$ok = $false
for ($i = 1; $i -le 5; $i++) {
  flutter build apk --release
  if ($LASTEXITCODE -eq 0) { $ok = $true; break }
  Start-Sleep -Seconds 3
}
```

### Diagnosing Screen-Recorded Video Stutters (Python + OpenCV)
Check frame-to-frame pixel diffs (`d < 0.3` mid-motion = freeze/stall; `dt > 24 ms` = dropped frame; `d > 35` = velocity cliff):
```python
import cv2, numpy as np
cap = cv2.VideoCapture("recording.mp4")
prev, prev_t, idx = None, 0.0, 0
while True:
    ret, f = cap.read()
    if not ret: break
    t = cap.get(cv2.CAP_PROP_POS_MSEC)
    if prev is not None:
        d = float(np.mean(np.abs(f.astype(np.float32) - prev.astype(np.float32))))
        dt = t - prev_t
        if dt > 24 or (d < 0.3 and idx > 1):
            print(f"f={idx} t={t:.1f}ms dt={dt:.1f}ms d={d:.2f}")
    prev, prev_t, idx = f, t, idx + 1
```
