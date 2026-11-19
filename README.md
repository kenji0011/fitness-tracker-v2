# Tempo

A fast, lightweight, **100% offline-first** personal fitness tracker built with **Flutter** and an embedded **Rust + SQLite (`rusqlite`)** native core, styled with an Apple-inspired UI and a floating **Liquid Glass** navigation bar.

## Highlights

- **Rust + SQLite Local Core (`rust/tempo_core`)**: All profiles, workouts, exercise logs, body measurements, daily activity, and progress photo records run natively in Rust via `dart:ffi` (`libtempo_core.so`). Zero cloud accounts, zero Firebase, zero Supabase.
- **Multiple Local Profiles + 4-Digit PIN**: Create isolated profiles on the same device protected by SHA-256 salted 4-digit PINs. **Double-tap the Profile tab** (or profile avatar/card) anytime to switch profiles.
- **Apple-Style Light & Dark Mode**: Defaults to crisp iOS Light Mode with a full toggle to OLED Dark Mode across every screen and widget.
- **Floating Liquid Glass Navigation Bar**: 4-tab floating frosted glass dock (`Summary`, `Workout`, `Progress`, `Profile`) with a smoothly gliding liquid-glass active lens.
- **On-Device Media & Videos**: Avatars and progress photos are stored privately in local app storage (`path_provider`); guided workouts and exercise videos work completely offline.

## Project Structure

- `rust/tempo_core/` — Native Rust SQLite database & analytics engine (`cdylib`).
- `scripts/build_rust_android.ps1` — Builds `libtempo_core.so` for `arm64-v8a`, `armeabi-v7a`, and `x86_64` into `android/app/src/main/jniLibs/`.
- `lib/services/tempo_rust_db.dart` — Typed Dart FFI gateway to the Rust core.
- `lib/widgets/liquid_glass_nav_bar.dart` — Floating iOS 26/27-style Liquid Glass tab bar.
- `lib/widgets/pin_pad_sheet.dart` — Apple-style 4-digit PIN keypad.
- `lib/screens/` — `Summary` (`health_dashboard.dart`), `Workout` (`workout_screen.dart`), `Progress` (`progress_tracking_screen.dart`), `Profile` (`my_profile.dart`), and `ProfileGateScreen` (`profile_switcher_screen.dart`).

## Building & Running

1. Install Flutter dependencies:
   ```powershell
   flutter pub get
   ```
2. (Whenever you modify `rust/tempo_core/`) Rebuild the Android Rust native libraries:
   ```powershell
   .\scripts\build_rust_android.ps1
   ```
3. Run on a connected Android phone or emulator:
   ```powershell
   flutter run
   ```
4. Build an Android APK:
   ```powershell
   flutter build apk --release
   ```
