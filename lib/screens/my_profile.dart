import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:jiggicons/jiggicons.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../config/app_version.dart';
import '../models/local_profile.dart';
import '../services/active_profile_provider.dart';
import '../services/app_update_service.dart';
import '../services/local_backup_service.dart';
import '../services/local_media_service.dart';
import '../services/step_counter_sync.dart';
import '../services/tempo_rust_db.dart';
import '../services/weight_unit_helper.dart';
import '../theme/app_colors.dart';
import '../theme/theme_provider.dart';
import '../widgets/ios_stretch_sheet.dart';
import '../widgets/liquid_glass_surface.dart';
import '../widgets/pin_pad_sheet.dart';
import '../widgets/step_accuracy_warning_sheet.dart';
import '../widgets/tempo_jigg_icon.dart';
import '../widgets/tempo_morph_route.dart';
import '../widgets/tempo_sliver_header.dart';
import '../widgets/tempo_spotlight_tour.dart';
import '../widgets/tempo_toast.dart';
import '../widgets/tempo_update_sheet.dart';
import 'about_app_screen.dart';
import 'appearance_settings_screen.dart';
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
  bool _liveStepsEnabled = false;
  bool _autoUpdateEnabled = true;
  bool _checkingUpdates = false;
  bool _wasTickerEnabled = false;
  bool _needsRefresh = false;
  final GlobalKey _avatarHintKey = GlobalKey();
  final GlobalKey _identityHintKey = GlobalKey();
  final JiggIconController _autoUpdateJiggController = JiggIconController();
  final Map<String, JiggIconController> _settingJiggControllers = {};

  JiggIconController _settingController(String key) =>
      _settingJiggControllers.putIfAbsent(key, JiggIconController.new);

  @override
  void initState() {
    super.initState();
    _loadProfilePrefs();
  }

  @override
  void dispose() {
    _autoUpdateJiggController.dispose();
    for (final ctrl in _settingJiggControllers.values) {
      ctrl.dispose();
    }
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final enabled = TickerMode.of(context);
    if (enabled && !_wasTickerEnabled) {
      if (_needsRefresh) {
        _needsRefresh = false;
        _loadProfilePrefs();
      }
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
      if (TickerMode.of(context)) {
        _needsRefresh = false;
        _loadProfilePrefs();
      } else {
        _needsRefresh = true;
      }
    }
  }

  Future<void> _loadProfilePrefs() async {
    final pid = context.read<ActiveProfileProvider>().activeProfileId;
    final unit = await WeightUnitHelper.loadUnit(pid);
    final liveSteps =
        pid != null ? await StepCounterSync.isLiveEnabled(pid) : false;
    final autoUpdate = await AppUpdateService.isAutoUpdateEnabled();
    if (mounted &&
        (unit != _weightUnit ||
            liveSteps != _liveStepsEnabled ||
            autoUpdate != _autoUpdateEnabled)) {
      setState(() {
        _weightUnit = unit;
        _liveStepsEnabled = liveSteps;
        _autoUpdateEnabled = autoUpdate;
      });
    }
  }

  Future<void> _toggleAutoUpdates(bool enabled) async {
    HapticFeedback.selectionClick();
    _autoUpdateJiggController.play();
    setState(() => _autoUpdateEnabled = enabled);
    await AppUpdateService.setAutoUpdateEnabled(enabled);
    if (!mounted) return;
    showTempoToast(
      context,
      enabled ? 'Auto-updates enabled' : 'Auto-updates paused',
    );
  }

  Future<void> _checkForUpdatesManually() async {
    if (_checkingUpdates) return;
    HapticFeedback.selectionClick();
    setState(() => _checkingUpdates = true);
    final res = await AppUpdateService.checkForUpdate(manual: true);
    if (!mounted) return;
    setState(() => _checkingUpdates = false);

    switch (res.status) {
      case TempoUpdateCheckStatus.updateAvailable:
        if (res.release != null) {
          await showTempoUpdateSheet(context, res.release!);
        }
        break;
      case TempoUpdateCheckStatus.upToDate:
        showTempoToast(context, 'Tempo is up to date ($kTempoDisplayVersion)');
        break;
      case TempoUpdateCheckStatus.offlineOrError:
        showTempoToast(
          context,
          'Could not check for updates — verify internet connection',
          isError: true,
        );
        break;
      case TempoUpdateCheckStatus.skipped:
      case TempoUpdateCheckStatus.throttled:
        if (res.release != null) {
          await showTempoUpdateSheet(context, res.release!);
        }
        break;
    }
  }

  Future<void> _toggleLiveSteps(bool wantEnabled) async {
    final profileProvider = context.read<ActiveProfileProvider>();
    final pid = profileProvider.activeProfileId;
    if (pid == null) return;
    HapticFeedback.selectionClick();

    if (wantEnabled && await StepCounterSync.shouldShowAccuracyWarning(pid)) {
      if (!mounted) return;
      final choice = await showStepAccuracyWarningSheet(context);
      if (!mounted || choice == null || !choice.proceed) return;
      if (choice.suppressForToday) {
        await StepCounterSync.dismissAccuracyWarningForToday(pid);
      }
    }

    final res = await StepCounterSync.requestAndToggleLiveSteps(pid, wantEnabled);
    if (!mounted) return;
    setState(() => _liveStepsEnabled = res.enabled);
    profileProvider.notifyDataChanged();
    if (res.enabled) {
      showTempoToast(context, 'Live step counter enabled');
    } else if (wantEnabled && res.deniedPermanently) {
      showTempoToast(
        context,
        'Enable Physical Activity in phone settings',
        isError: true,
      );
      await openAppSettings();
    } else if (wantEnabled) {
      showTempoToast(
        context,
        'Physical Activity permission is needed for live steps',
        isError: true,
      );
    } else {
      showTempoToast(context, 'Live step counter paused');
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
        final bottomPad = MediaQuery.paddingOf(ctx).bottom;
        return Padding(
          padding: EdgeInsets.fromLTRB(20, 10, 20, bottomPad + 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: mc.accent.withValues(
                        alpha: mc.isDark ? 0.22 : 0.13,
                      ),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      CupertinoIcons.camera_fill,
                      color: mc.accent,
                      size: 19,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Update profile photo',
                          style: TextStyle(
                            color: mc.textPrimary,
                            fontSize: 19,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Stored privately on this device',
                          style: TextStyle(
                            color: mc.textSecondary,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TempoGlassCircleButton(
                    size: 34,
                    enableBlur: false,
                    enableRefraction: false,
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(ctx).pop(),
                    icon: Icon(
                      CupertinoIcons.xmark,
                      size: 15,
                      color: mc.textSecondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              TempoLiquidButton(
                primary: false,
                borderRadius: 20,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 13,
                ),
                onPressed: () => Navigator.of(ctx).pop(ImageSource.gallery),
                child: Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: const BoxDecoration(
                        color: Color(0xFF4B9EF7),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        CupertinoIcons.photo_fill,
                        color: Colors.white,
                        size: 17,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Choose from gallery',
                            style: TextStyle(
                              color: mc.textPrimary,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            'Pick an existing photo and crop',
                            style: TextStyle(
                              color: mc.textSecondary,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      CupertinoIcons.chevron_right,
                      size: 15,
                      color: mc.textTertiary,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              TempoLiquidButton(
                primary: false,
                borderRadius: 20,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 13,
                ),
                onPressed: () => Navigator.of(ctx).pop(ImageSource.camera),
                child: Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: mc.accent,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        CupertinoIcons.camera_fill,
                        color: Colors.white,
                        size: 17,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Take photo',
                            style: TextStyle(
                              color: mc.textPrimary,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            'Capture a fresh portrait with camera',
                            style: TextStyle(
                              color: mc.textSecondary,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      CupertinoIcons.chevron_right,
                      size: 15,
                      color: mc.textTertiary,
                    ),
                  ],
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
      builder: (ctx) {
        final mc = AppColors.of(ctx);
        final bottomInset = MediaQuery.viewInsetsOf(ctx).bottom > 0
            ? MediaQuery.viewInsetsOf(ctx).bottom
            : MediaQuery.paddingOf(ctx).bottom;
        return Padding(
          padding: EdgeInsets.fromLTRB(20, 10, 20, bottomInset + 22),
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Modal Header
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: mc.accent.withValues(
                          alpha: mc.isDark ? 0.22 : 0.13,
                        ),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        CupertinoIcons.person_crop_circle_fill,
                        color: mc.accent,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Edit Profile & Daily Goals',
                            style: TextStyle(
                              color: mc.textPrimary,
                              fontSize: 19,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.35,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Personal details and daily ring targets',
                            style: TextStyle(
                              color: mc.textSecondary,
                              fontSize: 12.8,
                            ),
                          ),
                        ],
                      ),
                    ),
                    TempoGlassCircleButton(
                      size: 34,
                      enableBlur: false,
                      enableRefraction: false,
                      tooltip: 'Close',
                      onPressed: () => Navigator.of(ctx).pop(false),
                      icon: Icon(
                        CupertinoIcons.xmark,
                        size: 15,
                        color: mc.textSecondary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),

                // Section 1: Profile Details
                _modalSectionLabel('PROFILE', mc),
                _modalGroupedTray(
                  mc,
                  children: [
                    _sheetInputRow(
                      label: 'Display Name',
                      ctrl: nameCtrl,
                      c: mc,
                      icon: CupertinoIcons.person_fill,
                      badgeColor: const Color(0xFF7A6FF0),
                      numeric: false,
                    ),
                    _sheetSplitRow(
                      left: _sheetCompactField(
                        label: 'Height',
                        unit: 'cm',
                        ctrl: heightCtrl,
                        c: mc,
                      ),
                      right: _sheetCompactField(
                        label: 'Weight',
                        unit: _weightUnit,
                        ctrl: weightCtrl,
                        c: mc,
                      ),
                      c: mc,
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Section 2: Daily Goals
                _modalSectionLabel('DAILY GOALS', mc),
                _modalGroupedTray(
                  mc,
                  children: [
                    _sheetInputRow(
                      label: 'Calories',
                      unit: 'kcal',
                      ctrl: calGoalCtrl,
                      c: mc,
                      icon: CupertinoIcons.flame_fill,
                      badgeColor: const Color(0xFFF36432),
                    ),
                    _sheetInputRow(
                      label: 'Activity time',
                      unit: 'min',
                      ctrl: minGoalCtrl,
                      c: mc,
                      icon: CupertinoIcons.clock_fill,
                      badgeColor: const Color(0xFF56B7FF),
                    ),
                    _sheetInputRow(
                      label: 'Daily steps',
                      unit: 'steps',
                      ctrl: stepsGoalCtrl,
                      c: mc,
                      icon: Icons.directions_walk_rounded,
                      badgeColor: const Color(0xFF93DC2A),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                Row(
                  children: [
                    Expanded(
                      child: TempoLiquidButton(
                        primary: false,
                        height: 50,
                        borderRadius: 999,
                        onPressed: () => Navigator.of(ctx).pop(false),
                        child: Text(
                          'Cancel',
                          style: TextStyle(
                            color: mc.textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: TempoBouncyButton(
                        height: 50,
                        onPressed: () {
                          HapticFeedback.lightImpact();
                          Navigator.of(ctx).pop(true);
                        },
                        child: const Text('Save Changes'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
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

  Widget _modalSectionLabel(String text, AppColors c) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 0, 6, 7),
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

  Widget _modalGroupedTray(
    AppColors c, {
    required List<Widget> children,
  }) {
    final items = <Widget>[];
    for (int i = 0; i < children.length; i++) {
      if (i > 0) {
        items.add(
          Divider(
            height: 0.6,
            thickness: 0.6,
            indent: 14,
            endIndent: 14,
            color: c.divider,
          ),
        );
      }
      items.add(children[i]);
    }
    return Container(
      decoration: BoxDecoration(
        color: c.searchBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: c.isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.045),
          width: 0.8,
        ),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: items),
    );
  }

  Widget _sheetInputRow({
    required String label,
    required TextEditingController ctrl,
    required AppColors c,
    required IconData icon,
    required Color badgeColor,
    String? unit,
    bool numeric = true,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: badgeColor,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.white, size: 15),
          ),
          const SizedBox(width: 12),
          Text(
            label,
            style: TextStyle(
              color: c.textPrimary,
              fontSize: 14.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: ctrl,
              textAlign: TextAlign.right,
              keyboardType: numeric
                  ? const TextInputType.numberWithOptions(decimal: true)
                  : TextInputType.text,
              style: TextStyle(
                color: c.textPrimary,
                fontSize: 15.5,
                fontWeight: FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
              decoration: InputDecoration(
                isDense: true,
                filled: false,
                border: InputBorder.none,
                focusedBorder: InputBorder.none,
                enabledBorder: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 4),
                hintText: numeric ? '0' : 'Enter name',
                hintStyle: TextStyle(color: c.textTertiary),
              ),
            ),
          ),
          if (unit != null) ...[
            const SizedBox(width: 6),
            Text(
              unit,
              style: TextStyle(
                color: c.textTertiary,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _sheetSplitRow({
    required Widget left,
    required Widget right,
    required AppColors c,
  }) {
    return IntrinsicHeight(
      child: Row(
        children: [
          Expanded(child: left),
          Container(
            width: 0.7,
            margin: const EdgeInsets.symmetric(vertical: 10),
            color: c.divider,
          ),
          Expanded(child: right),
        ],
      ),
    );
  }

  Widget _sheetCompactField({
    required String label,
    required String unit,
    required TextEditingController ctrl,
    required AppColors c,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Column(
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
          const SizedBox(height: 3),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: ctrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 16.5,
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                  decoration: const InputDecoration(
                    isDense: true,
                    filled: false,
                    border: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 2),
                  ),
                ),
              ),
              Text(
                unit,
                style: TextStyle(
                  color: c.textTertiary,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
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
                  Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: mc.accent.withValues(
                            alpha: mc.isDark ? 0.22 : 0.13,
                          ),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          CupertinoIcons.tray_arrow_down_fill,
                          color: mc.accent,
                          size: 19,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Local Backup & Restore',
                          style: TextStyle(
                            color: mc.textPrimary,
                            fontSize: 19,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.35,
                          ),
                        ),
                      ),
                      TempoGlassCircleButton(
                        size: 34,
                        enableBlur: false,
                        enableRefraction: false,
                        tooltip: 'Close',
                        onPressed: () => Navigator.of(ctx).pop(),
                        icon: Icon(
                          CupertinoIcons.xmark,
                          size: 15,
                          color: mc.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Export your offline workouts, body metrics, hydration, and custom routines to a local JSON file on this device.',
                    style: TextStyle(
                      color: mc.textSecondary,
                      fontSize: 13.5,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TempoBouncyButton(
                    height: 50,
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
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const TempoJiggIcon(
                          'download',
                          variant: JiggIconVariant.solid,
                          color: Colors.white,
                          size: 18,
                          trigger: JiggIconTrigger.appear,
                          fallbackIcon: CupertinoIcons.tray_arrow_down_fill,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          busy ? 'Working...' : 'Create local backup',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'SAVED BACKUPS (${backups.length})',
                    style: TextStyle(
                      color: mc.textTertiary,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.65,
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
                        borderRadius: BorderRadius.circular(18),
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
                          final dateStr = DateFormat('MMM d, yyyy, HH:mm')
                              .format(entry.modifiedAt.toLocal());
                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 11,
                            ),
                            decoration: BoxDecoration(
                              color: mc.searchBg,
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: mc.isDark
                                    ? Colors.white.withValues(alpha: 0.08)
                                    : Colors.black.withValues(alpha: 0.045),
                              ),
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
                                        '$dateStr ($kb KB)',
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
                                            await _loadProfilePrefs();
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
                                  child: TempoTouchLightEffect(
                                    borderRadius: 999,
                                    intensity: 0.9,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 7,
                                      ),
                                      decoration: BoxDecoration(
                                        color: mc.accent.withValues(
                                          alpha: mc.isDark ? 0.22 : 0.13,
                                        ),
                                        borderRadius: BorderRadius.circular(999),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          TempoJiggIcon(
                                            'upload',
                                            variant: JiggIconVariant.outline,
                                            size: 13,
                                            color: mc.accent,
                                            trigger: JiggIconTrigger.none,
                                            fallbackIcon:
                                                CupertinoIcons.arrow_up_circle,
                                          ),
                                          const SizedBox(width: 5),
                                          Text(
                                            'Restore',
                                            style: TextStyle(
                                              color: mc.accent,
                                              fontSize: 12.5,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ],
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
                        TempoGlassCircleButton(
                          size: 38,
                          tooltip: 'Edit profile',
                          onPressed: () => _editProfileDetails(profile),
                          icon: Icon(
                            CupertinoIcons.pencil,
                            size: 16,
                            color: c.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // --- 1. Preferences ---
                _sectionHeader('Preferences', c),
                _groupedSettingsCard(
                  c: c,
                  children: [
                    _settingTile(
                      icon: CupertinoIcons.sparkles,
                      jiggIconName: 'palette',
                      badgeColor: const Color(0xFF7A6FF0),
                      title: 'Appearance',
                      trailingText: switch (themeProvider.themeMode) {
                        ThemeMode.system => 'System',
                        ThemeMode.dark => 'Dark',
                        ThemeMode.light => 'Light',
                      },
                      c: c,
                      onTapWithContext: (rowCtx) => pushTempoMorphRoute<void>(
                        context: context,
                        sourceContext: rowCtx,
                        sourceBorderRadius: 18,
                        builder: (_) => const AppearanceSettingsScreen(),
                      ),
                    ),
                    _switchTile(
                      c: c,
                      icon: Icons.directions_walk_rounded,
                      badgeColor: const Color(0xFF4CD964),
                      title: 'Live step counter',
                      value: _liveStepsEnabled,
                      onChanged: _toggleLiveSteps,
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // --- 2. Data & Media ---
                _sectionHeader('Data & Media', c),
                _groupedSettingsCard(
                  c: c,
                  children: [
                    _settingTile(
                      icon: CupertinoIcons.photo_fill,
                      jiggIconName: 'camera',
                      badgeColor: const Color(0xFF4B9EF7),
                      title: 'Progress photos',
                      c: c,
                      onTapWithContext: (rowCtx) => pushTempoMorphRoute<void>(
                        context: context,
                        sourceContext: rowCtx,
                        sourceBorderRadius: 18,
                        builder: (_) => const ProgressAlbumScreen(),
                      ),
                    ),
                    _settingTile(
                      icon: CupertinoIcons.tray_arrow_down_fill,
                      jiggIconName: 'download',
                      badgeColor: c.accent,
                      title: 'Backup & restore',
                      c: c,
                      onTap: () => _openBackupSheet(profile),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // --- 3. Security & Privacy ---
                _sectionHeader('Security & Privacy', c),
                _groupedSettingsCard(
                  c: c,
                  children: [
                    _settingTile(
                      icon: CupertinoIcons.lock_rotation,
                      jiggIconName: 'key',
                      badgeColor: const Color(0xFF4BD166),
                      title: 'Change 4-digit PIN',
                      c: c,
                      onTap: () => _changePin(profile),
                    ),
                    _settingTile(
                      icon: CupertinoIcons.lock_fill,
                      jiggIconName: 'lock',
                      badgeColor: const Color(0xFF34C759),
                      title: 'Lock profile',
                      c: c,
                      onTap: () => profileProvider.lockSession(),
                    ),
                    _settingTile(
                      icon: CupertinoIcons.shield_fill,
                      jiggIconName: 'bell',
                      badgeColor: const Color(0xFFF4BD3E),
                      title: 'Device permissions',
                      c: c,
                      onTapWithContext: (rowCtx) => pushTempoMorphRoute<void>(
                        context: context,
                        sourceContext: rowCtx,
                        sourceBorderRadius: 18,
                        builder: (_) => const PermissionsScreen(),
                      ),
                    ),
                    _settingTile(
                      icon: CupertinoIcons.doc_text_fill,
                      badgeColor: const Color(0xFF7A6FF0),
                      title: 'Privacy & terms',
                      c: c,
                      onTapWithContext: (rowCtx) => pushTempoMorphRoute<void>(
                        context: context,
                        sourceContext: rowCtx,
                        sourceBorderRadius: 18,
                        builder: (_) => const TermsAndConditionsScreen(),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // --- 4. Updates & Support ---
                _sectionHeader('Updates & Support', c),
                _groupedSettingsCard(
                  c: c,
                  children: [
                    _switchTile(
                      c: c,
                      icon: CupertinoIcons.arrow_up_circle_fill,
                      jiggIconName: 'rocket',
                      jiggController: _autoUpdateJiggController,
                      badgeColor: c.accent,
                      title: 'Auto-updates',
                      value: _autoUpdateEnabled,
                      onChanged: _toggleAutoUpdates,
                    ),
                    ValueListenableBuilder<TempoReleaseInfo?>(
                      valueListenable: AppUpdateService.availableRelease,
                      builder: (context, pendingRelease, _) {
                        final hasUpdate = pendingRelease != null;
                        return _settingTile(
                          icon: CupertinoIcons.arrow_up_circle_fill,
                          jiggIconName: 'download',
                          badgeColor: const Color(0xFF7A6FF0),
                          title: 'App version',
                          trailingText: _checkingUpdates
                              ? 'Checking...'
                              : kTempoDisplayVersion,
                          trailingWidget: _checkingUpdates
                              ? CupertinoActivityIndicator(
                                  radius: 9,
                                  color: c.accent,
                                )
                              : (hasUpdate
                                  ? Container(
                                      width: 8,
                                      height: 8,
                                      margin: const EdgeInsets.only(right: 6),
                                      decoration: BoxDecoration(
                                        color: c.accent,
                                        shape: BoxShape.circle,
                                      ),
                                    )
                                  : null),
                          showChevron: true,
                          c: c,
                          onTap: _checkForUpdatesManually,
                        );
                      },
                    ),
                    _settingTile(
                      icon: CupertinoIcons.book_fill,
                      jiggIconName: 'book',
                      badgeColor: const Color(0xFF4AC9A5),
                      title: 'App guide',
                      c: c,
                      onTapWithContext: (rowCtx) => pushTempoMorphRoute<void>(
                        context: context,
                        sourceContext: rowCtx,
                        sourceBorderRadius: 18,
                        builder: (_) => IntroWalkthroughScreen(
                          isReplay: true,
                          onComplete: () => Navigator.of(context).pop(),
                        ),
                      ),
                    ),
                    _settingTile(
                      icon: CupertinoIcons.sparkles,
                      jiggIconName: 'star',
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
                      onTapWithContext: (rowCtx) => pushTempoMorphRoute<void>(
                        context: context,
                        sourceContext: rowCtx,
                        sourceBorderRadius: 18,
                        builder: (_) => const AboutAppScreen(),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // --- 5. Account Danger Zone (Safely Separated) ---
                _groupedSettingsCard(
                  c: c,
                  children: [
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
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title, AppColors c) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          color: c.textTertiary,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.65,
        ),
      ),
    );
  }

  Widget _groupedSettingsCard({
    required AppColors c,
    required List<Widget> children,
  }) {
    final separated = <Widget>[];
    for (int i = 0; i < children.length; i++) {
      if (i > 0) {
        separated.add(
          Divider(
            height: 0.6,
            thickness: 0.6,
            indent: 62,
            endIndent: 16,
            color: c.divider,
          ),
        );
      }
      separated.add(children[i]);
    }

    return AppleCard(
      borderRadius: 24,
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Material(
          type: MaterialType.transparency,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: separated,
          ),
        ),
      ),
    );
  }

  Widget _switchTile({
    required AppColors c,
    required IconData icon,
    String? jiggIconName,
    JiggIconController? jiggController,
    required Color badgeColor,
    required String title,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10.5),
      child: Row(
        children: [
          _circleIcon(
            icon,
            badgeColor,
            jiggIconName: jiggIconName,
            jiggController: jiggController,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                color: c.textPrimary,
                fontSize: 15.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 10),
          CupertinoSwitch(
            activeTrackColor: c.accent,
            value: value,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  Widget _circleIcon(
    IconData icon,
    Color color, {
    String? jiggIconName,
    JiggIconController? jiggController,
  }) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
      child: Center(
        child: jiggIconName != null
            ? TempoJiggIcon(
                jiggIconName,
                variant: JiggIconVariant.solid,
                color: Colors.white,
                size: 16,
                controller: jiggController,
                trigger: JiggIconTrigger.none,
                fallbackIcon: icon,
              )
            : Icon(icon, color: Colors.white, size: 16),
      ),
    );
  }

  Widget _settingTile({
    required IconData icon,
    String? jiggIconName,
    required Color badgeColor,
    required String title,
    required AppColors c,
    VoidCallback? onTap,
    void Function(BuildContext rowContext)? onTapWithContext,
    Color? titleColor,
    String? trailingText,
    Widget? trailingWidget,
    bool showChevron = true,
  }) {
    final ctrl = jiggIconName != null ? _settingController(title) : null;
    final hasTap = onTap != null || onTapWithContext != null;
    final content = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 13.5,
      ),
      child: Row(
        children: [
          _circleIcon(
            icon,
            badgeColor,
            jiggIconName: jiggIconName,
            jiggController: ctrl,
          ),
          const SizedBox(width: 14),
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
          if (trailingWidget != null) trailingWidget,
          if (trailingText != null) ...[
            if (trailingWidget != null) const SizedBox(width: 4),
            Text(
              trailingText,
              style: TextStyle(
                color: c.textTertiary,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
          if (showChevron && hasTap) ...[
            if (trailingText != null || trailingWidget != null)
              const SizedBox(width: 6),
            Icon(
              CupertinoIcons.chevron_right,
              color: c.textTertiary,
              size: 15,
            ),
          ],
        ],
      ),
    );

    if (!hasTap) return content;

    return Builder(
      builder: (rowCtx) => InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          ctrl?.play();
          if (onTapWithContext != null) {
            onTapWithContext(rowCtx);
          } else {
            onTap?.call();
          }
        },
        child: content,
      ),
    );
  }
}
