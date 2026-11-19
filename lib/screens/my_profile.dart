import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../models/local_profile.dart';
import '../services/active_profile_provider.dart';
import '../services/local_media_service.dart';
import '../services/tempo_rust_db.dart';
import '../theme/app_colors.dart';
import '../theme/theme_provider.dart';
import '../widgets/ios_stretch_sheet.dart';
import '../widgets/liquid_glass_surface.dart';
import '../widgets/pin_pad_sheet.dart';
import '../widgets/tempo_sliver_header.dart';
import 'about_app_screen.dart';
import 'intro_walkthrough_screen.dart';
import 'permissions_screen.dart';
import 'profile_switcher_screen.dart';
import 'progress_album_screen.dart';
import 'terms_and_conditions_screen.dart';

class MyProfile extends StatefulWidget {
  final int refreshVersion;
  final bool showChatbot;
  final VoidCallback? onOpenProfileSwitcher;

  const MyProfile({
    super.key,
    this.refreshVersion = 0,
    this.showChatbot = false,
    this.onOpenProfileSwitcher,
  });

  @override
  State<MyProfile> createState() => _MyProfileState();
}

class _MyProfileState extends State<MyProfile> {
  final ImagePicker _imagePicker = ImagePicker();

  Future<void> _changeAvatar(LocalProfile profile) async {
    final picked = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 600,
    );
    if (picked == null || !mounted) return;

    final savedPath = await LocalMediaService.saveProfileAvatar(
      profileId: profile.id,
      sourcePath: picked.path,
    );
    if (!mounted) return;
    await context.read<ActiveProfileProvider>().updateActiveProfile(
          avatarPath: savedPath,
        );
  }

  Future<void> _editProfileDetails(LocalProfile profile) async {
    final nameCtrl = TextEditingController(text: profile.displayName);
    final heightCtrl = TextEditingController(
      text: profile.heightCm > 0 ? profile.heightCm.toStringAsFixed(0) : '',
    );
    final weightCtrl = TextEditingController(
      text: profile.weightKg > 0 ? profile.weightKg.toStringAsFixed(1) : '',
    );
    final calGoalCtrl =
        TextEditingController(text: profile.dailyCaloriesGoal.toString());
    final minGoalCtrl =
        TextEditingController(text: profile.dailyMinutesGoal.toString());
    final stepsGoalCtrl =
        TextEditingController(text: profile.dailyStepsGoal.toString());

    final c = AppColors.of(context, listen: false);
    final saved = await showTempoSheet<bool>(
      context: context,
      backgroundColor: c.card,
      borderRadius: 28,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          12,
          20,
          MediaQuery.of(ctx).viewInsets.bottom + 24,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Edit Profile & Daily Goals',
                style: TextStyle(
                  color: c.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 16),
              _dialogField('Display Name', nameCtrl, c, numeric: false),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: _dialogField('Height (cm)', heightCtrl, c)),
                  const SizedBox(width: 10),
                  Expanded(child: _dialogField('Weight (kg)', weightCtrl, c)),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: _dialogField('Calorie Goal', calGoalCtrl, c)),
                  const SizedBox(width: 10),
                  Expanded(child: _dialogField('Minutes Goal', minGoalCtrl, c)),
                ],
              ),
              const SizedBox(height: 12),
              _dialogField('Daily Steps Goal', stepsGoalCtrl, c),
              const SizedBox(height: 20),
              SizedBox(
                height: 50,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: c.accent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: const Text(
                    'Save Changes',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (saved == true && mounted) {
      await context.read<ActiveProfileProvider>().updateActiveProfile(
            displayName: nameCtrl.text.trim().isNotEmpty
                ? nameCtrl.text.trim()
                : null,
            heightCm: double.tryParse(heightCtrl.text.trim()),
            weightKg: double.tryParse(weightCtrl.text.trim()),
            dailyCaloriesGoal: int.tryParse(calGoalCtrl.text.trim()),
            dailyMinutesGoal: int.tryParse(minGoalCtrl.text.trim()),
            dailyStepsGoal: int.tryParse(stepsGoalCtrl.text.trim()),
          );
    }

    nameCtrl.dispose();
    heightCtrl.dispose();
    weightCtrl.dispose();
    calGoalCtrl.dispose();
    minGoalCtrl.dispose();
    stepsGoalCtrl.dispose();
  }

  Widget _dialogField(
    String label,
    TextEditingController ctrl,
    AppColors c, {
    bool numeric = true,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: c.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 5),
        TextField(
          controller: ctrl,
          keyboardType: numeric
              ? const TextInputType.numberWithOptions(decimal: true)
              : TextInputType.text,
          style: TextStyle(color: c.textPrimary),
        ),
      ],
    );
  }

  Future<void> _changePin(LocalProfile profile) async {
    final provider = context.read<ActiveProfileProvider>();

    final currentPin = await showApplePinPadSheet(
      context: context,
      title: 'Current PIN',
      subtitle: 'Verify your existing 4-digit PIN',
      onVerify: (pin) => TempoRustDb.instance.verifyPin(profile.id, pin),
    );
    if (currentPin == null || !mounted) return;

    final newPin = await showApplePinPadSheet(
      context: context,
      title: 'New 4-Digit PIN',
      subtitle: 'Choose a new 4-digit PIN',
    );
    if (newPin == null || !mounted) return;

    final confirmed = await showApplePinPadSheet(
      context: context,
      title: 'Confirm New PIN',
      subtitle: 'Re-enter your new 4-digit PIN',
      onVerify: (p) async => p == newPin,
    );
    if (confirmed == null || !mounted) return;

    try {
      await provider.changePin(
        profileId: profile.id,
        currentPin: currentPin,
        newPin: newPin,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('4-digit PIN updated successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not update PIN: $e')),
        );
      }
    }
  }

  Future<void> _confirmDeleteProfile(LocalProfile profile) async {
    final pin = await showApplePinPadSheet(
      context: context,
      title: 'Delete ${profile.displayName}?',
      subtitle: 'Enter 4-digit PIN to permanently delete local data',
      onVerify: (entered) =>
          TempoRustDb.instance.verifyPin(profile.id, entered),
    );
    if (pin == null || !mounted) return;

    await context.read<ActiveProfileProvider>().deleteProfile(profile.id);
  }

  String _profileMetaLine(LocalProfile profile) {
    final parts = <String>[];
    if (profile.gender.trim().isNotEmpty &&
        profile.gender.toLowerCase() != 'prefer not to say') {
      parts.add(profile.gender.trim());
    }
    if (profile.heightCm > 0) {
      parts.add('${profile.heightCm.toStringAsFixed(0)}cm');
    }
    if (profile.weightKg > 0) {
      parts.add('${profile.weightKg.toStringAsFixed(1)}kg');
    }
    if (profile.age > 0) {
      parts.add('${profile.age}');
    } else if (profile.bmi > 0) {
      parts.add('BMI ${profile.bmi.toStringAsFixed(1)}');
    }
    return parts.isEmpty ? 'Tap to complete profile details' : parts.join(' | ');
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final themeProvider = context.watch<ThemeProvider>();
    final profileProvider = context.watch<ActiveProfileProvider>();
    final profile = profileProvider.activeProfile;

    if (profile == null) {
      return Scaffold(
        backgroundColor: c.scaffold,
        body: Center(child: CupertinoActivityIndicator(color: c.accent)),
      );
    }

    return Scaffold(
      backgroundColor: c.scaffold,
      body: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          const TempoSliverHeader(title: 'Profile'),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(18, 6, 18, 128),
            sliver: SliverList.list(
              children: [
                // --- Clean Identity Header (Avatar, Name, Inline Bio/Metrics, Edit) ---
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _editProfileDetails(profile),
                  onDoubleTap: () {
                    HapticFeedback.mediumImpact();
                    widget.onOpenProfileSwitcher?.call();
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 6,
                    ),
                    child: Row(
                      children: [
                        GestureDetector(
                          onTap: () => _changeAvatar(profile),
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: c.cardBorder,
                                width: 1.5,
                              ),
                            ),
                            child: LocalProfileAvatar(
                              name: profile.displayName,
                              avatarPath: profile.avatarPath,
                              size: 64,
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                profile.displayName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: c.textPrimary,
                                  fontSize: 23,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -0.4,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _profileMetaLine(profile),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: c.textSecondary,
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w500,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: () => _editProfileDetails(profile),
                          child: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: c.card,
                              shape: BoxShape.circle,
                              border: Border.all(color: c.cardBorder),
                            ),
                            child: Icon(
                              CupertinoIcons.pencil,
                              size: 16,
                              color: c.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 22),

                // --- Single Unified Settings Card (Mi Fitness / HyperOS 3 Reference) ---
                AppleCard(
                  borderRadius: 26,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    children: [
                      // Dark Mode toggle row
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 11,
                        ),
                        child: Row(
                          children: [
                            _circleIcon(
                              c.isDark
                                  ? CupertinoIcons.moon_fill
                                  : CupertinoIcons.sun_max_fill,
                              const Color(0xFF7A6FF0),
                            ),
                            const SizedBox(width: 15),
                            Expanded(
                              child: Text(
                                'Dark mode',
                                style: TextStyle(
                                  color: c.textPrimary,
                                  fontSize: 15.5,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            CupertinoSwitch(
                              activeTrackColor: c.accent,
                              value: themeProvider.isDarkMode,
                              onChanged: (v) {
                                HapticFeedback.selectionClick();
                                themeProvider.toggleTheme(v);
                              },
                            ),
                          ],
                        ),
                      ),
                      _settingTile(
                        icon: CupertinoIcons.person_2_fill,
                        badgeColor: const Color(0xFF3D9CF6),
                        title: 'Switch profile',
                        c: c,
                        onTap: () => widget.onOpenProfileSwitcher?.call(),
                      ),
                      _settingTile(
                        icon: CupertinoIcons.person_badge_plus_fill,
                        badgeColor: const Color(0xFF4AC9A5),
                        title: 'Add profile',
                        c: c,
                        onTap: () => showCreateProfileModal(context),
                      ),
                      _settingTile(
                        icon: CupertinoIcons.photo_fill,
                        badgeColor: const Color(0xFF4B9EF7),
                        title: 'Progress photos',
                        c: c,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const ProgressAlbumScreen(),
                          ),
                        ),
                      ),
                      _settingTile(
                        icon: CupertinoIcons.lock_rotation,
                        badgeColor: const Color(0xFF4BD166),
                        title: 'Change 4-digit PIN',
                        c: c,
                        onTap: () => _changePin(profile),
                      ),
                      _settingTile(
                        icon: CupertinoIcons.lock_fill,
                        badgeColor: const Color(0xFF4BD166),
                        title: 'Lock profile',
                        c: c,
                        onTap: () => profileProvider.lockSession(),
                      ),
                      _settingTile(
                        icon: CupertinoIcons.shield_fill,
                        badgeColor: const Color(0xFFF4BD3E),
                        title: 'Device permissions',
                        c: c,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const PermissionsScreen(),
                          ),
                        ),
                      ),
                      _settingTile(
                        icon: CupertinoIcons.doc_text_fill,
                        badgeColor: const Color(0xFF7A6FF0),
                        title: 'Privacy & terms',
                        c: c,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const TermsAndConditionsScreen(),
                          ),
                        ),
                      ),
                      _settingTile(
                        icon: CupertinoIcons.arrow_up_circle_fill,
                        badgeColor: const Color(0xFF7A6FF0),
                        title: 'App version',
                        trailingText: 'V2.0.0',
                        showChevron: false,
                        c: c,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const AboutAppScreen(),
                          ),
                        ),
                      ),
                      _settingTile(
                        icon: CupertinoIcons.book_fill,
                        badgeColor: const Color(0xFF4AC9A5),
                        title: 'App guide',
                        c: c,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => IntroWalkthroughScreen(
                              isReplay: true,
                              onComplete: () => Navigator.of(context).pop(),
                            ),
                          ),
                        ),
                      ),
                      _settingTile(
                        icon: CupertinoIcons.info,
                        badgeColor: const Color(0xFF3D9CF6),
                        title: 'About Tempo',
                        c: c,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const AboutAppScreen(),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 4,
                        ),
                        child: Divider(height: 1, color: c.divider),
                      ),
                      _settingTile(
                        icon: CupertinoIcons.trash_fill,
                        badgeColor: const Color(0xFFEF5350),
                        title: 'Delete local profile',
                        titleColor: c.moveRed,
                        c: c,
                        onTap: () => _confirmDeleteProfile(profile),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _circleIcon(IconData icon, Color color) {
    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: Colors.white, size: 16),
    );
  }

  Widget _settingTile({
    required IconData icon,
    required Color badgeColor,
    required String title,
    required AppColors c,
    required VoidCallback onTap,
    Color? titleColor,
    String? trailingText,
    bool showChevron = true,
  }) {
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        child: Row(
          children: [
            _circleIcon(icon, badgeColor),
            const SizedBox(width: 15),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  color: titleColor ?? c.textPrimary,
                  fontSize: 15.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            if (trailingText != null)
              Text(
                trailingText,
                style: TextStyle(
                  color: c.textTertiary,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            if (showChevron)
              Icon(
                CupertinoIcons.chevron_right,
                color: c.textTertiary,
                size: 15,
              ),
          ],
        ),
      ),
    );
  }
}
