import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../models/local_profile.dart';
import '../services/active_profile_provider.dart';
import '../services/local_media_service.dart';
import '../theme/app_colors.dart';
import '../widgets/ios_stretch_sheet.dart';
import '../widgets/liquid_glass_surface.dart';
import '../widgets/pin_pad_sheet.dart';

/// Opens the Liquid Glass Profile Switcher modal sheet.
/// Users double-tap any profile to verify its 4-digit PIN and switch, or create a new local profile.
Future<void> showProfileSwitcherSheet(BuildContext context) {
  return showTempoSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (ctx) => const _ProfileSwitcherSheet(),
  );
}

/// Full-screen Apple-style Profile Gate shown on first launch or when locked.
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
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              Center(
                child: Text(
                  'Tempo',
                  style: TextStyle(
                    color: c.textTertiary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.4,
                  ),
                ),
              ),
              const SizedBox(height: 18),
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
                        ? c.textPrimary
                        : c.textSecondary,
                    fontSize: 14.5,
                    height: 1.4,
                  ),
                ),
              ),
              const SizedBox(height: 36),
              Expanded(
                child: profiles.isEmpty
                    ? _EmptyOnboardingCard(
                        onCreate: () => showCreateProfileModal(context),
                      )
                    : GridView.builder(
                        padding: const EdgeInsets.only(bottom: 24),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisSpacing: 16,
                          crossAxisSpacing: 16,
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
                            isActive: false,
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
                SizedBox(
                  height: 54,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: c.accent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    onPressed: () => showCreateProfileModal(context),
                    child: const Text(
                      'Create First Profile',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
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

class _AddProfileTileCard extends StatefulWidget {
  final VoidCallback onTap;

  const _AddProfileTileCard({required this.onTap});

  @override
  State<_AddProfileTileCard> createState() => _AddProfileTileCardState();
}

class _AddProfileTileCardState extends State<_AddProfileTileCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        HapticFeedback.selectionClick();
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.94 : 1.0,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOutCubic,
        child: AppleCard(
          borderRadius: 28,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  color: c.searchBg,
                  shape: BoxShape.circle,
                  border: Border.all(color: c.divider, width: 1.2),
                ),
                child: Icon(
                  CupertinoIcons.add,
                  color: c.textPrimary,
                  size: 34,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Add Profile',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: c.textSecondary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.2,
                ),
              ),
            ],
          ),
        ),
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
      child: AppleCard(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              CupertinoIcons.person_2,
              size: 38,
              color: c.textSecondary,
            ),
            const SizedBox(height: 16),
            Text(
              '100% On-Device & Private',
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
    final provider = context.watch<ActiveProfileProvider>();
    final profiles = provider.profiles;
    final activeId = provider.activeProfileId;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.78,
          ),
          padding: EdgeInsets.fromLTRB(
            20,
            14,
            20,
            MediaQuery.of(context).padding.bottom + 20,
          ),
          decoration: BoxDecoration(
            color: c.isDark
                ? const Color(0xFF1C1C1E).withValues(alpha: 0.92)
                : const Color(0xFFF2F2F7).withValues(alpha: 0.94),
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
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Switch Profile',
                        style: TextStyle(
                          color: c.textPrimary,
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Double-tap a profile to switch',
                        style: TextStyle(
                          color: c.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                  FilledButton.tonalIcon(
                    onPressed: () async {
                      Navigator.of(context).pop();
                      await showCreateProfileModal(context);
                    },
                    icon: const Icon(CupertinoIcons.add, size: 18),
                    label: const Text('New'),
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
                          subtitle: 'Enter 4-digit PIN',
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
        ),
      ),
    );
  }
}

class _ProfileTileCard extends StatefulWidget {
  final LocalProfile profile;
  final bool isActive;
  final VoidCallback onSingleTap;
  final VoidCallback onDoubleTapSwitch;

  const _ProfileTileCard({
    required this.profile,
    required this.isActive,
    required this.onSingleTap,
    required this.onDoubleTapSwitch,
  });

  @override
  State<_ProfileTileCard> createState() => _ProfileTileCardState();
}

class _ProfileTileCardState extends State<_ProfileTileCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: () {
        setState(() => _pressed = false);
        widget.onSingleTap();
      },
      onDoubleTap: () {
        setState(() => _pressed = false);
        HapticFeedback.mediumImpact();
        widget.onDoubleTapSwitch();
      },
      child: AnimatedScale(
        scale: _pressed ? 0.94 : 1.0,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOutCubic,
        child: AppleCard(
          borderRadius: 28,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              LocalProfileAvatar(
                name: widget.profile.displayName,
                avatarPath: widget.profile.avatarPath,
                size: 96,
              ),
              const SizedBox(height: 16),
              Text(
                widget.profile.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: c.textPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.2,
                ),
              ),
            ],
          ),
        ),
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
    return AppleCard(
      borderRadius: 20,
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
            size: 56,
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
                    fontSize: 16.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (widget.isActive || _showDoubleTapPrompt) ...[
                  const SizedBox(height: 2),
                  Text(
                    widget.isActive ? 'Active' : 'Double-tap to switch',
                    style: TextStyle(
                      color: widget.isActive ? c.textSecondary : c.accent,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (widget.isActive)
            Icon(
              CupertinoIcons.checkmark_alt,
              color: c.textPrimary,
              size: 18,
            ),
        ],
      ),
    );
  }
}

/// Modal to create a brand-new local profile with Name, optional Avatar, Body stats, and 4-digit PIN.
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
  String _gender = 'Prefer not to say';
  String _goal = 'general_fitness';
  String _pickedImagePath = '';
  bool _saving = false;

  static const _goals = <MapEntry<String, String>>[
    MapEntry('general_fitness', 'General Health & Wellness'),
    MapEntry('weight_loss', 'Weight Loss'),
    MapEntry('strength_power', 'Strength & Power'),
    MapEntry('cardio', 'Cardio Fitness'),
    MapEntry('muscular_endurance', 'Muscular Endurance'),
  ];

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
      imageQuality: 85,
      maxWidth: 600,
    );
    if (xfile != null && mounted) {
      setState(() => _pickedImagePath = xfile.path);
    }
  }

  Future<void> _continueToPin() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a profile name')),
      );
      return;
    }

    // Step 1: Enter 4-digit PIN
    final pin1 = await showApplePinPadSheet(
      context: context,
      title: 'Create 4-Digit PIN',
      subtitle: 'Protects $name\'s local profile',
    );
    if (pin1 == null || !mounted) return;

    // Step 2: Confirm 4-digit PIN
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not create profile: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
          child: Container(
            padding: EdgeInsets.fromLTRB(
              22,
              14,
              22,
              MediaQuery.of(context).padding.bottom + 20,
            ),
            decoration: BoxDecoration(
              color: c.isDark
                  ? const Color(0xFF1C1C1E).withValues(alpha: 0.94)
                  : const Color(0xFFF2F2F7).withValues(alpha: 0.96),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(32)),
              border: Border(top: BorderSide(color: c.glassBorder, width: 1)),
            ),
            child: SingleChildScrollView(
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
                  Text(
                    'New Local Profile',
                    style: TextStyle(
                      color: c.textPrimary,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Center(
                    child: GestureDetector(
                      onTap: _pickAvatar,
                      child: Stack(
                        children: [
                          LocalProfileAvatar(
                            name: _nameCtrl.text.isEmpty
                                ? 'Tempo'
                                : _nameCtrl.text,
                            avatarPath: _pickedImagePath,
                            size: 76,
                          ),
                          Positioned(
                            right: 0,
                            bottom: 0,
                            child: Container(
                              padding: const EdgeInsets.all(6),
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
                                size: 14,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  _label('Name', c),
                  TextField(
                    controller: _nameCtrl,
                    onChanged: (_) => setState(() {}),
                    style: TextStyle(color: c.textPrimary),
                    decoration: InputDecoration(
                      hintText: 'e.g. Alex',
                      hintStyle: TextStyle(color: c.textHint),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _label('Height (cm)', c),
                            TextField(
                              controller: _heightCtrl,
                              keyboardType: TextInputType.number,
                              style: TextStyle(color: c.textPrimary),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _label('Weight (kg)', c),
                            TextField(
                              controller: _weightCtrl,
                              keyboardType: TextInputType.number,
                              style: TextStyle(color: c.textPrimary),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _label('Age', c),
                            TextField(
                              controller: _ageCtrl,
                              keyboardType: TextInputType.number,
                              style: TextStyle(color: c.textPrimary),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _label('Fitness Goal', c),
                  DropdownButtonFormField<String>(
                    initialValue: _goal,
                    dropdownColor: c.card,
                    style: TextStyle(color: c.textPrimary, fontSize: 15),
                    items: _goals
                        .map(
                          (g) => DropdownMenuItem(
                            value: g.key,
                            child: Text(g.value),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setState(() => _goal = v);
                    },
                  ),
                  const SizedBox(height: 14),
                  _label('Gender', c),
                  DropdownButtonFormField<String>(
                    initialValue: _gender,
                    dropdownColor: c.card,
                    style: TextStyle(color: c.textPrimary, fontSize: 15),
                    items: const [
                      DropdownMenuItem(value: 'Male', child: Text('Male')),
                      DropdownMenuItem(value: 'Female', child: Text('Female')),
                      DropdownMenuItem(
                        value: 'Prefer not to say',
                        child: Text('Prefer not to say'),
                      ),
                    ],
                    onChanged: (v) {
                      if (v != null) setState(() => _gender = v);
                    },
                  ),
                  const SizedBox(height: 22),
                  SizedBox(
                    height: 52,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: c.accent,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      onPressed: _saving ? null : _continueToPin,
                      child: _saving
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.2,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              'Set 4-Digit PIN & Create',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _label(String text, AppColors c) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6, left: 2),
      child: Text(
        text,
        style: TextStyle(
          color: c.textSecondary,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
