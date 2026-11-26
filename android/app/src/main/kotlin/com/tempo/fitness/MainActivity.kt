package com.tempo.fitness

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val LIVE_UPDATES_CHANNEL = "com.tempo.fitness/live_updates"
    private val APP_UPDATER_CHANNEL = "com.tempo.fitness/app_updater"

    private lateinit var liveUpdateManager: WorkoutLiveUpdateManager
    private lateinit var appUpdateInstaller: AppUpdateInstaller
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
        super.onDestroy()
    }
}
