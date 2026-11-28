import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../models/local_profile.dart';
import '../services/active_profile_provider.dart';
import '../services/appearance_service.dart';
import '../services/local_media_service.dart';
import '../theme/app_colors.dart';
import '../widgets/bitchord_segmented_slider.dart';
import '../widgets/hyperos_dropdown_menu.dart';
import '../widgets/ios_stretch_sheet.dart';
import '../widgets/liquid_glass_surface.dart';
import '../widgets/pin_pad_sheet.dart';
import '../widgets/tempo_sliver_header.dart';
import '../widgets/tempo_startup_splash.dart';
import '../widgets/tempo_toast.dart';
import 'avatar_crop_screen.dart';

/// Opens the Liquid Glass Profile Switcher modal sheet.
/// Users double-tap any profile to verify its 4-digit PIN and switch, or create a new local profile.
Future<void> showProfileSwitcherSheet(BuildContext context) {
  return showTempoSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (ctx) => const _ProfileSwitcherSheet(),
  );
}

/// Full-screen Liquid Glass Profile Gate shown on first launch or when switching users.
class ProfileGateScreen extends StatefulWidget {
  const ProfileGateScreen({super.key});

  @override
  State<ProfileGateScreen> createState() => _ProfileGateScreenState();
}

class _ProfileGateScreenState extends State<ProfileGateScreen> {
  String? _hintProfileName;

  void _showDoubleTapHint(String name) {
    HapticFeedback.selectionClick();
    setState(() => _hintProfileName = name);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted && _hintProfileName == name) {
        setState(() => _hintProfileName = null);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final profileProvider = context.watch<ActiveProfileProvider>();
    final profiles = profileProvider.profiles;

    return Scaffold(
      backgroundColor: c.scaffold,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 6),
              // Unified Tempo Dual-Ring Brand Pill
              Center(
                child: LiquidGlassSurface(
                  borderRadius: 999,
                  blurEnabled: false,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 7,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const TempoDualRingLogo(size: 22, glowIntensity: 0.40),
                      const SizedBox(width: 8),
                      Text(
                        'Tempo',
                        style: TextStyle(
                          color: c.textPrimary,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.1,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                profiles.isEmpty ? 'Welcome to Tempo' : 'Choose Your Profile',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: c.textPrimary,
                  fontSize: 30,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.8,
                ),
              ),
              const SizedBox(height: 8),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: Text(
                  profiles.isEmpty
                      ? 'Private, on-device fitness tracking stored locally on your phone.'
                      : (_hintProfileName != null
                          ? 'Double-tap $_hintProfileName to sign in'
                          : 'Double-tap a profile to continue'),
                  key: ValueKey(_hintProfileName ?? 'default'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _hintProfileName != null
                        ? c.accent
                        : c.textSecondary,
                    fontSize: 14.5,
                    fontWeight: _hintProfileName != null
                        ? FontWeight.w600
                        : FontWeight.w500,
                    height: 1.4,
                  ),
                ),
              ),
              const SizedBox(height: 30),
              Expanded(
                child: profiles.isEmpty
                    ? _EmptyOnboardingCard(
                        onCreate: () => showCreateProfileModal(context),
                      )
                    : GridView.builder(
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.only(bottom: 24),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisSpacing: 14,
                          crossAxisSpacing: 14,
                          childAspectRatio: 0.86,
                        ),
                        itemCount: profiles.length + 1,
                        itemBuilder: (ctx, idx) {
                          if (idx == profiles.length) {
                            return _AddProfileTileCard(
                              onTap: () => showCreateProfileModal(context),
                            );
                          }

                          final profile = profiles[idx];
                          return _ProfileTileCard(
                            profile: profile,
                            onSingleTap: () =>
                                _showDoubleTapHint(profile.displayName),
                            onDoubleTapSwitch: () =>
                                _unlockProfile(context, profile),
                          );
                        },
                      ),
              ),
              if (profiles.isEmpty) ...[
                const SizedBox(height: 16),
                TempoBouncyButton(
                  height: 54,
                  onPressed: () => showCreateProfileModal(context),
                  child: const Text('Create First Profile'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _unlockProfile(
    BuildContext context,
    LocalProfile profile,
  ) async {
    final provider = context.read<ActiveProfileProvider>();
    await showApplePinPadSheet(
      context: context,
      title: profile.displayName,
      subtitle: 'Enter passcode',
      onVerify: (pin) => provider.switchProfileWithPin(profile.id, pin),
    );
  }
}

class _AddProfileTileCard extends StatelessWidget {
  final VoidCallback onTap;

  const _AddProfileTileCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return LiquidGlassSurface(
      borderRadius: 28,
      blurEnabled: false,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 20),
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              color: c.accent.withValues(alpha: c.isDark ? 0.18 : 0.11),
              shape: BoxShape.circle,
              border: Border.all(
                color: c.accent.withValues(alpha: 0.32),
                width: 1.2,
              ),
            ),
            child: Icon(
              CupertinoIcons.add,
              color: c.accent,
              size: 32,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Add Profile',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: c.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyOnboardingCard extends StatelessWidget {
  final VoidCallback onCreate;

  const _EmptyOnboardingCard({required this.onCreate});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Center(
      child: LiquidGlassSurface(
        borderRadius: 28,
        blurEnabled: false,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: c.accent.withValues(alpha: c.isDark ? 0.22 : 0.12),
              ),
              child: Icon(
                CupertinoIcons.person_2_fill,
                size: 28,
                color: c.accent,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'On-Device & Private',
              style: TextStyle(
                color: c.textPrimary,
                fontSize: 19,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Create separate local profiles on your phone. Double-tap the Profile tab anytime to switch users.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: c.textSecondary,
                fontSize: 14,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileSwitcherSheet extends StatelessWidget {
  const _ProfileSwitcherSheet();

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final allowBlur = TempoAppearanceService.instance.value.allowDynamicBlur;
    final provider = context.watch<ActiveProfileProvider>();
    final profiles = provider.profiles;
    final activeId = provider.activeProfileId;

    final inner = Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.78,
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        MediaQuery.of(context).padding.bottom + 20,
      ),
      decoration: BoxDecoration(
        color: c.isDark
            ? const Color(0xFF1C1C1E).withValues(alpha: allowBlur ? 0.90 : 0.98)
            : const Color(0xFFF2F2F7).withValues(alpha: allowBlur ? 0.92 : 0.99),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        border: Border(top: BorderSide(color: c.glassBorder, width: 1)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 38,
              height: 5,
              decoration: BoxDecoration(
                color: c.textTertiary.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: c.accent.withValues(alpha: c.isDark ? 0.22 : 0.13),
                ),
                child: Icon(
                  CupertinoIcons.person_2_fill,
                  color: c.accent,
                  size: 19,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Switch Profile',
                      style: TextStyle(
                        color: c.textPrimary,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.4,
                      ),
                    ),
                    Text(
                      'Double-tap a profile to switch',
                      style: TextStyle(
                        color: c.textSecondary,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
              TempoLiquidButton(
                primary: false,
                height: 38,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                onPressed: () async {
                  Navigator.of(context).pop();
                  await showCreateProfileModal(context);
                },
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(CupertinoIcons.add, size: 16),
                    SizedBox(width: 5),
                    Text('New', style: TextStyle(fontSize: 13.5)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: profiles.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (ctx, i) {
                final profile = profiles[i];
                final isCurrent = profile.id == activeId;
                return _ProfileRowCard(
                  profile: profile,
                  isActive: isCurrent,
                  onDoubleTapSwitch: () async {
                    if (isCurrent) {
                      Navigator.of(context).pop();
                      return;
                    }
                    final pin = await showApplePinPadSheet(
                      context: context,
                      title: 'Switch to ${profile.displayName}',
                      subtitle: 'Enter passcode',
                      onVerify: (enteredPin) =>
                          provider.switchProfileWithPin(
                        profile.id,
                        enteredPin,
                      ),
                    );
                    if (pin != null && context.mounted) {
                      Navigator.of(context).pop();
                    }
                  },
                );
              },
            ),
          ),
        ],
      ),
    );

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
      child: allowBlur
          ? BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
              child: inner,
            )
          : inner,
    );
  }
}

class _ProfileTileCard extends StatelessWidget {
  final LocalProfile profile;
  final VoidCallback onSingleTap;
  final VoidCallback onDoubleTapSwitch;

  const _ProfileTileCard({
    required this.profile,
    required this.onSingleTap,
    required this.onDoubleTapSwitch,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return LiquidGlassSurface(
      borderRadius: 28,
      blurEnabled: false,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 20),
      onTap: onSingleTap,
      onDoubleTap: () {
        HapticFeedback.mediumImpact();
        onDoubleTapSwitch();
      },
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: c.isDark
                    ? Colors.white.withValues(alpha: 0.16)
                    : Colors.black.withValues(alpha: 0.06),
                width: 1.2,
              ),
            ),
            child: LocalProfileAvatar(
              name: profile.displayName,
              avatarPath: profile.avatarPath,
              size: 88,
            ),
          ),
          const SizedBox(height: 15),
          Text(
            profile.displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: c.textPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.25,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileRowCard extends StatefulWidget {
  final LocalProfile profile;
  final bool isActive;
  final VoidCallback onDoubleTapSwitch;

  const _ProfileRowCard({
    required this.profile,
    required this.isActive,
    required this.onDoubleTapSwitch,
  });

  @override
  State<_ProfileRowCard> createState() => _ProfileRowCardState();
}

class _ProfileRowCardState extends State<_ProfileRowCard> {
  bool _showDoubleTapPrompt = false;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return LiquidGlassSurface(
      borderRadius: 22,
      blurEnabled: false,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      onTap: () {
        if (widget.isActive) return;
        HapticFeedback.selectionClick();
        setState(() => _showDoubleTapPrompt = true);
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) setState(() => _showDoubleTapPrompt = false);
        });
      },
      onDoubleTap: () {
        HapticFeedback.mediumImpact();
        widget.onDoubleTapSwitch();
      },
      child: Row(
        children: [
          LocalProfileAvatar(
            name: widget.profile.displayName,
            avatarPath: widget.profile.avatarPath,
            size: 52,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.profile.displayName,
                  style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (widget.isActive || _showDoubleTapPrompt) ...[
                  const SizedBox(height: 2),
                  Text(
                    widget.isActive ? 'Currently signed in' : 'Double-tap to switch',
                    style: TextStyle(
                      color: widget.isActive ? c.textSecondary : c.accent,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (widget.isActive)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: c.accent.withValues(alpha: c.isDark ? 0.22 : 0.13),
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(
                'Active',
                style: TextStyle(
                  color: c.accent,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Modal to create a brand-new local profile with Name, optional Avatar, Body stats,
/// Fitness Goal (HyperOS dropdown), Gender (`BitChordSegmentedSlider`), and 4-digit PIN.
Future<void> showCreateProfileModal(BuildContext context) {
  return showTempoSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (ctx) => const _CreateProfileSheet(),
  );
}

class _CreateProfileSheet extends StatefulWidget {
  const _CreateProfileSheet();

  @override
  State<_CreateProfileSheet> createState() => _CreateProfileSheetState();
}

class _CreateProfileSheetState extends State<_CreateProfileSheet> {
  final _nameCtrl = TextEditingController();
  final _heightCtrl = TextEditingController(text: '170');
  final _weightCtrl = TextEditingController(text: '68');
  final _ageCtrl = TextEditingController(text: '24');
  final GlobalKey _goalRowKey = GlobalKey();

  String _gender = 'Male';
  String _goal = 'general_fitness';
  String _pickedImagePath = '';
  bool _goalMenuOpen = false;
  bool _saving = false;

  static const _genderLabels = ['Male', 'Female', 'Other'];
  static const _genderValues = ['Male', 'Female', 'Prefer not to say'];

  static const _goals = <MapEntry<String, String>>[
    MapEntry('general_fitness', 'General Health & Wellness'),
    MapEntry('weight_loss', 'Weight Loss'),
    MapEntry('strength_power', 'Strength & Power'),
    MapEntry('cardio', 'Cardio Fitness'),
    MapEntry('muscular_endurance', 'Muscular Endurance'),
  ];

  String get _goalLabel => _goals
      .firstWhere((e) => e.key == _goal, orElse: () => _goals.first)
      .value;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _heightCtrl.dispose();
    _weightCtrl.dispose();
    _ageCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    final picker = ImagePicker();
    final xfile = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 92,
      maxWidth: 1600,
    );
    if (xfile == null || !mounted) return;
    final croppedBytes = await Navigator.of(context).push<Uint8List?>(
      MaterialPageRoute(
        builder: (_) => AvatarCropScreen(imagePath: xfile.path),
      ),
    );
    if (croppedBytes == null || !mounted) return;
    final tempPath = await LocalMediaService.saveTempAvatarBytes(croppedBytes);
    if (tempPath.isNotEmpty && mounted) {
      setState(() => _pickedImagePath = tempPath);
    }
  }

  Future<void> _openGoalMenu() async {
    FocusScope.of(context).unfocus();
    HapticFeedback.selectionClick();
    setState(() => _goalMenuOpen = true);
    final picked = await showHyperOsDropdownMenu<String>(
      context: context,
      rowKey: _goalRowKey,
      selectedValue: _goal,
      options: _goals
          .map((e) => HyperOsDropdownOption(value: e.key, label: e.value))
          .toList(),
    );
    if (mounted) {
      setState(() {
        if (picked != null) _goal = picked;
        _goalMenuOpen = false;
      });
    }
  }

  Future<void> _continueToPin() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      showTempoToast(context, 'Please enter a profile name', isError: true);
      return;
    }

    final pin1 = await showApplePinPadSheet(
      context: context,
      title: 'Create 4-Digit PIN',
      subtitle: 'Protects $name\'s local profile',
    );
    if (pin1 == null || !mounted) return;

    final pin2 = await showApplePinPadSheet(
      context: context,
      title: 'Confirm 4-Digit PIN',
      subtitle: 'Re-enter your 4-digit PIN',
      onVerify: (entered) async => entered == pin1,
    );
    if (pin2 == null || !mounted) return;

    setState(() => _saving = true);
    try {
      final provider = context.read<ActiveProfileProvider>();
      final created = await provider.createProfile(
        displayName: name,
        pin: pin1,
        gender: _gender,
        age: int.tryParse(_ageCtrl.text.trim()) ?? 0,
        heightCm: double.tryParse(_heightCtrl.text.trim()) ?? 170.0,
        weightKg: double.tryParse(_weightCtrl.text.trim()) ?? 68.0,
        fitnessGoal: _goal,
      );

      if (_pickedImagePath.isNotEmpty) {
        final localPath = await LocalMediaService.saveProfileAvatar(
          profileId: created.id,
          sourcePath: _pickedImagePath,
        );
        await provider.updateActiveProfile(avatarPath: localPath);
      }

      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showTempoToast(context, 'Could not create profile: $e', isError: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final allowBlur = TempoAppearanceService.instance.value.allowDynamicBlur;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final genderIdx = _genderValues.indexOf(_gender).clamp(0, 2);

    final inner = Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.90,
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        MediaQuery.of(context).padding.bottom + 20,
      ),
      decoration: BoxDecoration(
        color: c.isDark
            ? const Color(0xFF1C1C1E).withValues(alpha: allowBlur ? 0.92 : 0.98)
            : const Color(0xFFF2F2F7).withValues(alpha: allowBlur ? 0.94 : 0.99),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        border: Border(top: BorderSide(color: c.glassBorder, width: 1)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 38,
              height: 5,
              decoration: BoxDecoration(
                color: c.textTertiary.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Unified Modal Header (badge + title + Liquid Glass close circle)
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: c.accent.withValues(alpha: c.isDark ? 0.22 : 0.13),
                ),
                child: Icon(
                  CupertinoIcons.person_add_solid,
                  color: c.accent,
                  size: 19,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'New Local Profile',
                  style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.4,
                  ),
                ),
              ),
              TempoGlassCircleButton(
                size: 36,
                enableBlur: false,
                tooltip: 'Close',
                icon: Icon(
                  CupertinoIcons.xmark,
                  size: 16,
                  color: c.textPrimary,
                ),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Scrollable Form Body
          Flexible(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Avatar Picker with Liquid Glass specular ring
                  Center(
                    child: GestureDetector(
                      onTap: _pickAvatar,
                      child: Stack(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(3),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: c.accent.withValues(alpha: 0.45),
                                width: 1.5,
                              ),
                            ),
                            child: LocalProfileAvatar(
                              name: _nameCtrl.text.isEmpty
                                  ? 'Tempo'
                                  : _nameCtrl.text,
                              avatarPath: _pickedImagePath,
                              size: 76,
                            ),
                          ),
                          Positioned(
                            right: 0,
                            bottom: 0,
                            child: Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                color: c.accent,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: c.card,
                                  width: 2,
                                ),
                              ),
                              child: const Icon(
                                CupertinoIcons.camera_fill,
                                size: 13,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),

                  // Name & Body Metrics Card
                  _sectionLabel('PROFILE DETAILS', c),
                  LiquidGlassSurface(
                    borderRadius: 24,
                    blurEnabled: false,
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _fieldLabel('Name', c),
                        const SizedBox(height: 6),
                        _cleanInput(
                          controller: _nameCtrl,
                          hintText: 'Your name',
                          onChanged: (_) => setState(() {}),
                          c: c,
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _fieldLabel('Height (cm)', c),
                                  const SizedBox(height: 6),
                                  _cleanInput(
                                    controller: _heightCtrl,
                                    keyboardType: TextInputType.number,
                                    tabular: true,
                                    c: c,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _fieldLabel('Weight (kg)', c),
                                  const SizedBox(height: 6),
                                  _cleanInput(
                                    controller: _weightCtrl,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                    tabular: true,
                                    c: c,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _fieldLabel('Age', c),
                                  const SizedBox(height: 6),
                                  _cleanInput(
                                    controller: _ageCtrl,
                                    keyboardType: TextInputType.number,
                                    tabular: true,
                                    c: c,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Fitness Goal (HyperOS Liquid Glass Dropdown)
                  _sectionLabel('FITNESS GOAL', c),
                  LiquidGlassSurface(
                    key: _goalRowKey,
                    borderRadius: 20,
                    blurEnabled: false,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    onTap: _openGoalMenu,
                    child: Row(
                      children: [
                        Expanded(
                          child: AnimatedOpacity(
                            opacity: _goalMenuOpen ? 0.0 : 1.0,
                            duration: const Duration(milliseconds: 140),
                            child: Text(
                              _goalLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: c.textPrimary,
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          CupertinoIcons.chevron_up_chevron_down,
                          size: 14,
                          color: c.textTertiary,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Gender (Liquid Glass BitChordSegmentedSlider)
                  _sectionLabel('GENDER', c),
                  BitChordSegmentedSlider(
                    height: 42,
                    showTrackBorder: true,
                    labels: _genderLabels,
                    selectedIndex: genderIdx,
                    onChanged: (idx) {
                      setState(() => _gender = _genderValues[idx]);
                    },
                  ),
                  const SizedBox(height: 18),
                ],
              ),
            ),
          ),

          // Pinned Bouncy Primary CTA
          const SizedBox(height: 6),
          TempoBouncyButton(
            height: 52,
            onPressed: _saving ? null : _continueToPin,
            child: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('Set 4-Digit PIN & Create'),
          ),
        ],
      ),
    );

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        child: allowBlur
            ? BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                child: inner,
              )
            : inner,
      ),
    );
  }

  Widget _sectionLabel(String text, AppColors c) {
    return Padding(
      padding: const EdgeInsets.only(left: 6, bottom: 7),
      child: Text(
        text,
        style: TextStyle(
          color: c.textTertiary,
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.65,
        ),
      ),
    );
  }

  Widget _fieldLabel(String text, AppColors c) {
    return Padding(
      padding: const EdgeInsets.only(left: 2),
      child: Text(
        text,
        style: TextStyle(
          color: c.textSecondary,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _cleanInput({
    required TextEditingController controller,
    required AppColors c,
    String? hintText,
    TextInputType? keyboardType,
    bool tabular = false,
    ValueChanged<String>? onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 2),
      decoration: BoxDecoration(
        color: c.isDark
            ? Colors.white.withValues(alpha: 0.065)
            : Colors.black.withValues(alpha: 0.045),
        borderRadius: BorderRadius.circular(14),
      ),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        onChanged: onChanged,
        style: TextStyle(
          color: c.textPrimary,
          fontSize: 15,
          fontWeight: FontWeight.w600,
          fontFeatures: tabular ? const [FontFeature.tabularFigures()] : null,
        ),
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: TextStyle(color: c.textHint),
          isDense: true,
          filled: false,
          fillColor: Colors.transparent,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 11),
        ),
      ),
    );
  }
}
