package com.tempo.fitness

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val LIVE_UPDATES_CHANNEL = "com.tempo.fitness/live_updates"
    private val APP_UPDATER_CHANNEL = "com.tempo.fitness/app_updater"
    private val PROGRESS_SHARE_CHANNEL = "com.tempo.fitness/progress_share"
    private val WORKOUT_SOUND_CHANNEL = "com.tempo.fitness/workout_sound"
    private val DEVICE_HARDWARE_CHANNEL = "com.tempo.fitness/device_hardware"

    private lateinit var liveUpdateManager: WorkoutLiveUpdateManager
    private lateinit var appUpdateInstaller: AppUpdateInstaller
    private lateinit var shareImageHelper: ShareImageHelper
    private lateinit var workoutSoundHelper: WorkoutSoundHelper
    private lateinit var deviceHardwareHelper: DeviceHardwareHelper
    private var liveChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, LIVE_UPDATES_CHANNEL)
        liveChannel = channel

        liveUpdateManager = WorkoutLiveUpdateManager(
            context = applicationContext,
            onRemoteTogglePause = {
                runOnUiThread {
                    liveChannel?.invokeMethod("onTogglePause", null)
                }
            }
        )

        appUpdateInstaller = AppUpdateInstaller(applicationContext)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, APP_UPDATER_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "canInstallPackages" -> {
                        result.success(appUpdateInstaller.canRequestPackageInstalls())
                    }
                    "openInstallPermissionSettings" -> {
                        result.success(appUpdateInstaller.openInstallPermissionSettings())
                    }
                    "installApk" -> {
                        val filePath = call.argument<String>("filePath") ?: ""
                        result.success(appUpdateInstaller.installApk(filePath))
                    }
                    else -> result.notImplemented()
                }
            }

        shareImageHelper = ShareImageHelper(applicationContext)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PROGRESS_SHARE_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "saveToGallery" -> {
                        val filePath = call.argument<String>("filePath") ?: ""
                        val displayName = call.argument<String>("displayName") ?: "Tempo_Progress.png"
                        result.success(shareImageHelper.saveImageToGallery(filePath, displayName))
                    }
                    "shareImage" -> {
                        val filePath = call.argument<String>("filePath") ?: ""
                        val text = call.argument<String>("text")
                        result.success(shareImageHelper.shareImage(filePath, text))
                    }
                    else -> result.notImplemented()
                }
            }

        workoutSoundHelper = WorkoutSoundHelper(applicationContext)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, WORKOUT_SOUND_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "playCountdownTick" -> result.success(workoutSoundHelper.playCountdownTick())
                    "playCountdownGo" -> result.success(workoutSoundHelper.playCountdownGo())
                    "isSilent" -> result.success(workoutSoundHelper.isDeviceSilent())
                    "stop" -> {
                        workoutSoundHelper.stop()
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }

        deviceHardwareHelper = DeviceHardwareHelper(applicationContext)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, DEVICE_HARDWARE_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getHardwareProfile" -> {
                        try {
                            result.success(deviceHardwareHelper.getHardwareProfile())
                        } catch (e: Exception) {
                            result.error("HARDWARE_PROFILE_ERROR", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "getStatus" -> {
                    result.success(liveUpdateManager.getStatus())
                }
                "startOrUpdate" -> {
                    try {
                        val title = call.argument<String>("title") ?: "Tempo Workout"
                        val subtitle = call.argument<String>("subtitle") ?: ""
                        val category = call.argument<String>("category") ?: ""
                        val currentExercise = call.argument<String>("currentExercise") ?: ""
                        val elapsedSeconds = call.argument<Int>("elapsedSeconds") ?: 0
                        val completedExercises = call.argument<Int>("completedExercises") ?: 0
                        val totalExercises = call.argument<Int>("totalExercises") ?: 1
                        val kcalPerMin = call.argument<Double>("kcalPerMin") ?: 7.5
                        val isPaused = call.argument<Boolean>("isPaused") ?: false
                        val shortText = call.argument<String>("shortText") ?: ""
                        val status = liveUpdateManager.startOrUpdate(
                            title = title,
                            subtitle = subtitle,
                            category = category,
                            currentExercise = currentExercise,
                            elapsedSeconds = elapsedSeconds,
                            completedExercises = completedExercises,
                            totalExercises = totalExercises,
                            kcalPerMin = kcalPerMin,
                            isPaused = isPaused,
                            shortText = shortText
                        )
                        result.success(status)
                    } catch (e: Exception) {
                        result.error("LIVE_UPDATE_ERROR", e.message, null)
                    }
                }
                "stop" -> {
                    liveUpdateManager.stop()
                    result.success(true)
                }
                "openLiveUpdatesSettings" -> {
                    result.success(liveUpdateManager.openLiveUpdatesSettings())
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        if (::liveUpdateManager.isInitialized) {
            liveUpdateManager.stop()
        }
        if (::workoutSoundHelper.isInitialized) {
            workoutSoundHelper.stop()
        }
        super.onDestroy()
    }
}
