package com.tempo.fitness

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val LIVE_UPDATES_CHANNEL = "com.tempo.fitness/live_updates"

    private lateinit var liveUpdateManager: WorkoutLiveUpdateManager

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        liveUpdateManager = WorkoutLiveUpdateManager(applicationContext)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, LIVE_UPDATES_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getStatus" -> {
                        result.success(liveUpdateManager.getStatus())
                    }
                    "startOrUpdate" -> {
                        try {
                            val title = call.argument<String>("title") ?: "Tempo Workout"
                            val subtitle = call.argument<String>("subtitle") ?: ""
                            val elapsedSeconds = call.argument<Int>("elapsedSeconds") ?: 0
                            val completedExercises = call.argument<Int>("completedExercises") ?: 0
                            val totalExercises = call.argument<Int>("totalExercises") ?: 1
                            val isPaused = call.argument<Boolean>("isPaused") ?: false
                            val shortText = call.argument<String>("shortText") ?: ""
                            val status = liveUpdateManager.startOrUpdate(
                                title = title,
                                subtitle = subtitle,
                                elapsedSeconds = elapsedSeconds,
                                completedExercises = completedExercises,
                                totalExercises = totalExercises,
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
