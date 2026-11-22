import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../config/app_version.dart';
import '../models/local_profile.dart';
import '../services/active_profile_provider.dart';
import '../services/local_backup_service.dart';
import '../services/local_media_service.dart';
import '../services/tempo_rust_db.dart';
import '../services/weight_unit_helper.dart';
import '../theme/app_colors.dart';
import '../theme/theme_provider.dart';
import '../widgets/ios_stretch_sheet.dart';
import '../widgets/liquid_glass_surface.dart';
import '../widgets/pin_pad_sheet.dart';
import '../widgets/tempo_sliver_header.dart';
import '../widgets/tempo_spotlight_tour.dart';
import '../widgets/tempo_toast.dart';
import 'about_app_screen.dart';
import 'avatar_crop_screen.dart';
import 'intro_walkthrough_screen.dart';
import 'permissions_screen.dart';
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
  String _weightUnit = 'kg';
  bool _wasTickerEnabled = false;
  final GlobalKey _avatarHintKey = GlobalKey();
  final GlobalKey _identityHintKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _loadWeightUnit();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final enabled = TickerMode.of(context);
    if (enabled && !_wasTickerEnabled) {
      _maybeShowSpotlight();
    }
    _wasTickerEnabled = enabled;
  }

  Future<void> _replayFeatureHints(LocalProfile profile) async {
    await TempoSpotlightTour.resetAllTours(profile.id);
    if (!mounted) return;
    showTempoToast(
      context,
      'Feature hints reset — visit any tab to preview',
    );
    _maybeShowSpotlight(forceShow: true);
  }

  void _maybeShowSpotlight({bool forceShow = false}) {
    final pid = context.read<ActiveProfileProvider>().activeProfileId;
    if (pid == null || pid.isEmpty) return;
    TempoSpotlightTour.showIfNeeded(
      context: context,
      profileId: pid,
      screenId: 'profile',
      forceShow: forceShow,
      delay: forceShow
          ? const Duration(milliseconds: 120)
          : const Duration(milliseconds: 520),
      steps: [
        TempoSpotlightStep(
          targetKey: _avatarHintKey,
          title: 'Crop your profile photo',
          description:
              'Tap your avatar anytime to upload from gallery or camera with pinch-to-zoom circular cropping.',
          borderRadius: 999,
          padding: const EdgeInsets.all(6),
        ),
        TempoSpotlightStep(
          targetKey: _identityHintKey,
          title: 'Quick profile switcher',
          description:
              'Double-tap your profile header or the Profile tab icon to switch between local profiles.',
          borderRadius: 20,
        ),
      ],
    );
  }

  @override
  void didUpdateWidget(covariant MyProfile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.refreshVersion != oldWidget.refreshVersion) {
      _loadWeightUnit();
    }
  }

  Future<void> _loadWeightUnit() async {
    final pid = context.read<ActiveProfileProvider>().activeProfileId;
    final unit = await WeightUnitHelper.loadUnit(pid);
    if (mounted && unit != _weightUnit) {
      setState(() => _weightUnit = unit);
    }
  }

  Future<void> _changeAvatar(LocalProfile profile) async {
    final c = AppColors.of(context, listen: false);
    final source = await showTempoSheet<ImageSource>(
      context: context,
      backgroundColor: c.card,
      borderRadius: 28,
      showDragHandle: true,
      builder: (ctx) {
        final mc = AppColors.of(ctx);
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Update profile photo',
                style: TextStyle(
                  color: mc.textPrimary,
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                height: 48,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: mc.accent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: () => Navigator.of(ctx).pop(ImageSource.gallery),
                  icon: const Icon(CupertinoIcons.photo_fill, size: 18),
                  label: const Text(
                    'Choose from gallery',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 48,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: mc.textPrimary,
                    side: BorderSide(color: mc.cardBorder),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: () => Navigator.of(ctx).pop(ImageSource.camera),
                  icon: const Icon(CupertinoIcons.camera_fill, size: 18),
                  label: const Text(
                    'Take photo',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
    if (source == null || !mounted) return;

    final picked = await _imagePicker.pickImage(
      source: source,
      imageQuality: 92,
      maxWidth: 1600,
    );
    if (picked == null || !mounted) return;

    final croppedBytes = await Navigator.of(context).push<Uint8List?>(
      MaterialPageRoute(
        builder: (_) => AvatarCropScreen(imagePath: picked.path),
      ),
    );
    if (croppedBytes == null || !mounted) return;

    final savedPath = await LocalMediaService.saveProfileAvatarBytes(
      profileId: profile.id,
      bytes: croppedBytes,
    );
    if (!mounted) return;
    await context.read<ActiveProfileProvider>().updateActiveProfile(
          avatarPath: savedPath,
        );
    if (mounted) {
      showTempoToast(context, 'Profile photo updated');
    }
  }

  Future<void> _editProfileDetails(LocalProfile profile) async {
    final nameCtrl = TextEditingController(text: profile.displayName);
    final heightCtrl = TextEditingController(
      text: profile.heightCm > 0 ? profile.heightCm.toStringAsFixed(0) : '',
    );
    final weightCtrl = TextEditingController(
      text: profile.weightKg > 0
          ? WeightUnitHelper.toDisplay(profile.weightKg, _weightUnit)
              .toStringAsFixed(1)
          : '',
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
                  Expanded(
                    child: _dialogField('Weight ($_weightUnit)', weightCtrl, c),
                  ),
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
      final parsedWeight = double.tryParse(weightCtrl.text.trim());
      final weightKg = parsedWeight != null
          ? WeightUnitHelper.fromDisplay(parsedWeight, _weightUnit)
          : null;
      await context.read<ActiveProfileProvider>().updateActiveProfile(
            displayName: nameCtrl.text.trim().isNotEmpty
                ? nameCtrl.text.trim()
                : null,
            heightCm: double.tryParse(heightCtrl.text.trim()),
            weightKg: weightKg,
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
        showTempoToast(context, '4-digit PIN updated');
      }
    } catch (e) {
      if (mounted) {
        showTempoToast(context, 'Could not update PIN: $e', isError: true);
      }
    }
  }

  Future<void> _openBackupSheet(LocalProfile profile) async {
    final c = AppColors.of(context, listen: false);
    final profileProvider = context.read<ActiveProfileProvider>();
    List<LocalBackupEntry> backups = await LocalBackupService.listBackups();
    bool busy = false;
    if (!mounted) return;

    await showTempoSheet<void>(
      context: context,
      backgroundColor: c.card,
      borderRadius: 28,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final mc = AppColors.of(ctx);
          final maxH = MediaQuery.sizeOf(ctx).height * 0.68;
          return ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxH),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Local Backup & Restore',
                    style: TextStyle(
                      color: mc.textPrimary,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Export your offline workouts, body metrics, hydration, and custom routines to a local JSON file on this device.',
                    style: TextStyle(
                      color: mc.textSecondary,
                      fontSize: 13.5,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 48,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: mc.accent,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: busy
                          ? null
                          : () async {
                              setSheetState(() => busy = true);
                              try {
                                final res = await LocalBackupService
                                    .exportProfileBackup(profile);
                                final updated =
                                    await LocalBackupService.listBackups();
                                if (ctx.mounted) {
                                  setSheetState(() {
                                    backups = updated;
                                    busy = false;
                                  });
                                }
                                if (mounted) {
                                  showTempoToast(
                                    context,
                                    'Saved ${res.fileName} (${res.recordCount} records)',
                                  );
                                }
                              } catch (e) {
                                if (ctx.mounted) {
                                  setSheetState(() => busy = false);
                                }
                                if (mounted) {
                                  showTempoToast(
                                    context,
                                    'Backup failed: $e',
                                    isError: true,
                                  );
                                }
                              }
                            },
                      icon: const Icon(
                        CupertinoIcons.tray_arrow_down_fill,
                        size: 18,
                      ),
                      label: Text(
                        busy ? 'Working...' : 'Create local backup',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Saved backups (${backups.length})',
                    style: TextStyle(
                      color: mc.textSecondary,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (backups.isEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 16,
                      ),
                      decoration: BoxDecoration(
                        color: mc.searchBg,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        'No local backups yet. Tap above to save your first snapshot.',
                        style: TextStyle(
                          color: mc.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                    )
                  else
                    Flexible(
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: backups.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (_, i) {
                          final entry = backups[i];
                          final kb = (entry.sizeBytes / 1024).toStringAsFixed(1);
                          final dateStr = DateFormat('MMM d, yyyy · HH:mm')
                              .format(entry.modifiedAt.toLocal());
                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 11,
                            ),
                            decoration: BoxDecoration(
                              color: mc.searchBg,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: mc.cardBorder),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        entry.fileName,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: mc.textPrimary,
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '$dateStr · $kb KB',
                                        style: TextStyle(
                                          color: mc.textSecondary,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 10),
                                GestureDetector(
                                  onTap: busy
                                      ? null
                                      : () async {
                                          setSheetState(() => busy = true);
                                          try {
                                            final count = await LocalBackupService
                                                .restoreBackupFile(
                                              profileId: profile.id,
                                              filePath: entry.filePath,
                                            );
                                            await profileProvider.refreshProfiles();
                                            await _loadWeightUnit();
                                            if (ctx.mounted) {
                                              Navigator.of(ctx).pop();
                                            }
                                            if (mounted) {
                                              showTempoToast(
                                                context,
                                                'Restored $count local records',
                                              );
                                            }
                                          } catch (e) {
                                            if (ctx.mounted) {
                                              setSheetState(() => busy = false);
                                            }
                                            if (mounted) {
                                              showTempoToast(
                                                context,
                                                'Restore failed: $e',
                                                isError: true,
                                              );
                                            }
                                          }
                                        },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 7,
                                    ),
                                    decoration: BoxDecoration(
                                      color: mc.accent.withValues(
                                        alpha: mc.isDark ? 0.20 : 0.12,
                                      ),
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: Text(
                                      'Restore',
                                      style: TextStyle(
                                        color: mc.accent,
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
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
      parts.add(
        WeightUnitHelper.format(
          profile.weightKg,
          _weightUnit,
          decimals: 1,
          includeSpace: false,
        ),
      );
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
                  key: _identityHintKey,
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
                          key: _avatarHintKey,
                          onTap: () => _changeAvatar(profile),
                          child: LocalProfileAvatar(
                            name: profile.displayName,
                            avatarPath: profile.avatarPath,
                            size: 64,
                            showBorder: false,
                            showShadow: false,
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
                        icon: CupertinoIcons.tray_arrow_down_fill,
                        badgeColor: c.accent,
                        title: 'Backup & restore',
                        c: c,
                        onTap: () => _openBackupSheet(profile),
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
                        trailingText: kTempoDisplayVersion,
                        showChevron: false,
                        c: c,
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
                        icon: CupertinoIcons.sparkles,
                        badgeColor: c.accent,
                        title: 'Replay feature hints',
                        c: c,
                        onTap: () => _replayFeatureHints(profile),
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
    VoidCallback? onTap,
    Color? titleColor,
    String? trailingText,
    bool showChevron = true,
  }) {
    final content = Padding(
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
          if (showChevron && onTap != null)
            Icon(
              CupertinoIcons.chevron_right,
              color: c.textTertiary,
              size: 15,
            ),
        ],
      ),
    );

    if (onTap == null) return content;

    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: content,
    );
  }
}
