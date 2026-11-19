package com.tempo.fitness

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
    private val CHANNEL = "rockies_fitness/asset_copy"
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

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "copyAssetToFile" -> {
                        val assetKey = call.argument<String>("assetKey")
                        val destPath = call.argument<String>("destPath")
                        if (assetKey == null || destPath == null) {
                            result.error("INVALID_ARGS", "assetKey and destPath are required", null)
                            return@setMethodCallHandler
                        }
                        Thread {
                            try {
                                copyAssetToFile(assetKey, destPath)
                                runOnUiThread { result.success(true) }
                            } catch (e: Exception) {
                                runOnUiThread {
                                    result.error("COPY_FAILED", e.message, null)
                                }
                            }
                        }.start()
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

    private fun copyAssetToFile(assetKey: String, destPath: String) {
        val destFile = File(destPath)
        destFile.parentFile?.mkdirs()

        val assetManager = assets
        assetManager.open("flutter_assets/$assetKey").use { input ->
            FileOutputStream(destFile).use { output ->
                val buffer = ByteArray(65536)
                var bytesRead: Int
                while (input.read(buffer).also { bytesRead = it } != -1) {
                    output.write(buffer, 0, bytesRead)
                }
                output.flush()
            }
        }
    }
}
