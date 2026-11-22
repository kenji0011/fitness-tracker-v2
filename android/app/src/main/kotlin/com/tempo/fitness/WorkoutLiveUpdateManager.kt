package com.tempo.fitness

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.graphics.drawable.Icon
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.Settings

/**
 * Manages Android 16+ (API 36) Live Updates (Promoted Ongoing Notifications)
 * for Xiaomi HyperOS 3 HyperIsland and stock Android Live Update capsules:
 * - Tempo Orange (#FF6A24) themed multi-segment ProgressStyle with exercise
 *   milestone points & live progress tracker icon
 * - Rich workout telemetry: live ticking timer, current exercise name,
 *   exercise count, completion %, and live estimated kcal
 * - Interactive Pause / Resume & Open buttons directly inside the expanded Island
 */
class WorkoutLiveUpdateManager(
    private val context: Context,
    private val onRemoteTogglePause: (() -> Unit)? = null
) {
    companion object {
        private const val CHANNEL_ID = "tempo_workout_live_v1"
        private const val CHANNEL_NAME = "Workout Live Updates"
        private const val NOTIFICATION_ID = 4201
        private const val EXTRA_REQUEST_PROMOTED_ONGOING = "android.requestPromotedOngoing"
        private const val ACTION_TOGGLE_PAUSE = "com.tempo.fitness.ACTION_HYPERISLAND_TOGGLE_PAUSE"

        private const val TEMPO_ORANGE = 0xFFFF6A24.toInt()
        private const val TEMPO_CORAL = 0xFFFF9B63.toInt()
        private const val TEMPO_PAUSED = 0xFF8E8E93.toInt()
        private const val TRACK_REMAINING = 0xFF3A3C44.toInt()
    }

    private val notificationManager: NotificationManager =
        context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    private val mainHandler = Handler(Looper.getMainLooper())

    private var isActive = false
    private var receiverRegistered = false
    private var activeTitle = "Tempo Workout"
    private var activeCategory = ""
    private var activeCurrentExercise = ""
    private var activeStartEpochMs = 0L
    private var activeCompletedExercises = 0
    private var activeTotalExercises = 1
    private var activeKcalPerMin = 7.5
    private var activePaused = false

    private val actionReceiver = object : BroadcastReceiver() {
        override fun onReceive(ctx: Context?, intent: Intent?) {
            if (intent?.action == ACTION_TOGGLE_PAUSE) {
                onRemoteTogglePause?.invoke()
            }
        }
    }

    private fun ensureReceiverRegistered() {
        if (receiverRegistered) return
        val filter = IntentFilter(ACTION_TOGGLE_PAUSE)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            context.registerReceiver(actionReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("DEPRECATION")
            context.registerReceiver(actionReceiver, filter)
        }
        receiverRegistered = true
    }

    private val tickRunnable = object : Runnable {
        override fun run() {
            if (!isActive || activePaused) return
            val liveSec = ((System.currentTimeMillis() - activeStartEpochMs) / 1000L)
                .toInt()
                .coerceAtLeast(0)
            postNotification(
                title = activeTitle,
                category = activeCategory,
                currentExercise = activeCurrentExercise,
                elapsedSeconds = liveSec,
                completedExercises = activeCompletedExercises,
                totalExercises = activeTotalExercises,
                kcalPerMin = activeKcalPerMin,
                isPaused = false,
                shortText = formatCompactTime(liveSec)
            )
            val elapsedMs = (System.currentTimeMillis() - activeStartEpochMs).coerceAtLeast(0L)
            val delayMs = (1000L - (elapsedMs % 1000L)).coerceIn(200L, 1000L)
            mainHandler.postDelayed(this, delayMs)
        }
    }

    private fun formatCompactTime(totalSec: Int): String {
        val safe = totalSec.coerceAtLeast(0)
        val hours = safe / 3600
        val mins = (safe % 3600) / 60
        val secs = safe % 60
        return if (hours > 0) {
            String.format("%d:%02d:%02d", hours, mins, secs)
        } else {
            String.format("%02d:%02d", mins, secs)
        }
    }

    private fun ensureChannel() {
        val existing = notificationManager.getNotificationChannel(CHANNEL_ID)
        if (existing != null) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            CHANNEL_NAME,
            NotificationManager.IMPORTANCE_DEFAULT
        ).apply {
            description = "Live workout timer, active exercise, calories, and progress in HyperIsland"
            setSound(null, null)
            enableVibration(false)
            setShowBadge(false)
            lockscreenVisibility = Notification.VISIBILITY_PUBLIC
        }
        notificationManager.createNotificationChannel(channel)
    }

    fun getStatus(): Map<String, Any> {
        val notificationsEnabled = notificationManager.areNotificationsEnabled()
        val isAndroid16Plus = Build.VERSION.SDK_INT >= 36
        val canPostPromoted = if (isAndroid16Plus) {
            notificationManager.canPostPromotedNotifications()
        } else {
            false
        }
        return mapOf(
            "supported" to isAndroid16Plus,
            "notificationsEnabled" to notificationsEnabled,
            "canPostPromoted" to canPostPromoted,
            "sdkInt" to Build.VERSION.SDK_INT
        )
    }

    fun startOrUpdate(
        title: String,
        subtitle: String,
        category: String,
        currentExercise: String,
        elapsedSeconds: Int,
        completedExercises: Int,
        totalExercises: Int,
        kcalPerMin: Double,
        isPaused: Boolean,
        shortText: String
    ): Map<String, Any> {
        ensureReceiverRegistered()
        mainHandler.removeCallbacks(tickRunnable)

        isActive = true
        activeTitle = title
        activeCategory = category
        activeCurrentExercise = currentExercise.ifBlank { subtitle }
        activeCompletedExercises = completedExercises
        activeTotalExercises = totalExercises.coerceAtLeast(1)
        activeKcalPerMin = kcalPerMin.coerceIn(3.0, 20.0)
        activePaused = isPaused
        activeStartEpochMs = System.currentTimeMillis() - (elapsedSeconds.coerceAtLeast(0) * 1000L)

        val effectiveShort = if (isPaused) {
            shortText.ifEmpty { "Paused" }
        } else {
            formatCompactTime(elapsedSeconds)
        }

        val status = postNotification(
            title = title,
            category = activeCategory,
            currentExercise = activeCurrentExercise,
            elapsedSeconds = elapsedSeconds,
            completedExercises = activeCompletedExercises,
            totalExercises = activeTotalExercises,
            kcalPerMin = activeKcalPerMin,
            isPaused = isPaused,
            shortText = effectiveShort
        )

        if (!isPaused) {
            mainHandler.postDelayed(tickRunnable, 1000L)
        }
        return status
    }

    private fun postNotification(
        title: String,
        category: String,
        currentExercise: String,
        elapsedSeconds: Int,
        completedExercises: Int,
        totalExercises: Int,
        kcalPerMin: Double,
        isPaused: Boolean,
        shortText: String
    ): Map<String, Any> {
        ensureChannel()

        val launchIntent = Intent(context, MainActivity::class.java).apply {
            action = Intent.ACTION_MAIN
            addCategory(Intent.CATEGORY_LAUNCHER)
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val contentIntent = PendingIntent.getActivity(
            context,
            0,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val toggleIntent = Intent(ACTION_TOGGLE_PAUSE).apply {
            setPackage(context.packageName)
        }
        val togglePendingIntent = PendingIntent.getBroadcast(
            context,
            101,
            toggleIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val safeTotal = totalExercises.coerceAtLeast(1)
        val safeDone = completedExercises.coerceIn(0, safeTotal)
        val pct = ((safeDone * 100) / safeTotal).coerceIn(0, 100)
        val estKcal = ((elapsedSeconds / 60.0) * kcalPerMin).toInt().coerceAtLeast(0)
        val accentColor = if (isPaused) TEMPO_PAUSED else TEMPO_ORANGE

        val statusTag = if (isPaused) "PAUSED" else "LIVE"
        val headerMeta = buildString {
            append(statusTag)
            append(" · ")
            append("$safeDone/$safeTotal")
            if (estKcal > 0) {
                append(" · ~$estKcal kcal")
            } else if (category.isNotEmpty()) {
                append(" · $category")
            }
        }

        val bodyLine = when {
            safeDone >= safeTotal -> "All $safeTotal exercises complete · ${formatCompactTime(elapsedSeconds)}"
            isPaused && currentExercise.isNotEmpty() -> "Paused · $currentExercise · $pct%"
            currentExercise.isNotEmpty() -> "Now: $currentExercise · $pct%"
            else -> "$safeDone of $safeTotal exercises · $pct%"
        }

        val builder = Notification.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_tempo)
            .setLargeIcon(Icon.createWithResource(context, R.mipmap.launcher_icon))
            .setColor(accentColor)
            .setSubText(headerMeta)
            .setContentTitle(title)
            .setContentText(bodyLine)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setAutoCancel(false)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setContentIntent(contentIntent)

        // Interactive quick actions right inside the expanded HyperIsland card
        val pauseResumeLabel = if (isPaused) "Resume" else "Pause"
        val pauseResumeIcon = if (isPaused) {
            android.R.drawable.ic_media_play
        } else {
            android.R.drawable.ic_media_pause
        }
        builder.addAction(
            Notification.Action.Builder(
                Icon.createWithResource(context, pauseResumeIcon),
                pauseResumeLabel,
                togglePendingIntent
            ).build()
        )
        builder.addAction(
            Notification.Action.Builder(
                Icon.createWithResource(context, R.drawable.ic_stat_tempo),
                "Open",
                contentIntent
            ).build()
        )

        if (!isPaused) {
            builder
                .setWhen(activeStartEpochMs)
                .setShowWhen(true)
                .setUsesChronometer(true)
        } else {
            builder
                .setShowWhen(false)
                .setUsesChronometer(false)
        }

        val extras = Bundle()
        if (Build.VERSION.SDK_INT >= 36) {
            builder.setCategory(Notification.CATEGORY_WORKOUT)
            extras.putBoolean(EXTRA_REQUEST_PROMOTED_ONGOING, true)
            builder.addExtras(extras)

            // Compact live timer text inside the HyperIsland status pill
            val chipText = shortText.take(7)
            if (chipText.isNotEmpty()) {
                builder.setShortCriticalText(chipText)
            }

            // Rich multi-segment Android 16 ProgressStyle with exercise milestones & live tracker icon
            val progressStyle = Notification.ProgressStyle()
                .setStyledByProgress(false)
                .setProgressTrackerIcon(
                    Icon.createWithResource(context, R.drawable.ic_stat_tempo)
                )

            val activeSegmentWeight = (100 / safeTotal).coerceIn(8, 35)
            val completedLen = pct.coerceIn(0, 100)
            val activeLen = if (completedLen < 100) {
                activeSegmentWeight.coerceAtMost(100 - completedLen)
            } else {
                0
            }
            val remainingLen = (100 - completedLen - activeLen).coerceAtLeast(0)

            if (completedLen > 0) {
                progressStyle.addProgressSegment(
                    Notification.ProgressStyle.Segment(completedLen).setColor(accentColor)
                )
            }
            if (activeLen > 0) {
                progressStyle.addProgressSegment(
                    Notification.ProgressStyle.Segment(activeLen).setColor(
                        if (isPaused) TEMPO_PAUSED else TEMPO_CORAL
                    )
                )
            }
            if (remainingLen > 0) {
                progressStyle.addProgressSegment(
                    Notification.ProgressStyle.Segment(remainingLen).setColor(TRACK_REMAINING)
                )
            }

            // Exercise milestone dots along the progress track (capped cleanly at 8)
            val milestoneCount = safeTotal.coerceIn(1, 8)
            for (i in 1 until milestoneCount) {
                val pos = (i * 100) / milestoneCount
                val reached = pos <= completedLen
                progressStyle.addProgressPoint(
                    Notification.ProgressStyle.Point(pos).setColor(
                        if (reached) accentColor else TRACK_REMAINING
                    )
                )
            }

            // Smooth subtle movement along the current exercise segment as seconds tick
            val intraExerciseBoost = if (!isPaused && safeDone < safeTotal) {
                ((elapsedSeconds % 45) * activeLen) / 90
            } else {
                0
            }
            val displayProgress = (completedLen + intraExerciseBoost).coerceIn(0, 100)
            progressStyle.setProgress(displayProgress)

            builder.setStyle(progressStyle)
        } else {
            builder.setCategory(Notification.CATEGORY_PROGRESS)
            builder.setProgress(safeTotal, safeDone, false)
        }

        val notification = builder.build()
        notificationManager.notify(NOTIFICATION_ID, notification)

        val promotable = if (Build.VERSION.SDK_INT >= 36) {
            notification.hasPromotableCharacteristics()
        } else {
            false
        }
        val canPostPromoted = if (Build.VERSION.SDK_INT >= 36) {
            notificationManager.canPostPromotedNotifications()
        } else {
            false
        }

        return mapOf(
            "posted" to true,
            "promotable" to promotable,
            "canPostPromoted" to canPostPromoted
        )
    }

    fun stop() {
        isActive = false
        activePaused = false
        mainHandler.removeCallbacks(tickRunnable)
        notificationManager.cancel(NOTIFICATION_ID)
        if (receiverRegistered) {
            try {
                context.unregisterReceiver(actionReceiver)
            } catch (_: Exception) {
            }
            receiverRegistered = false
        }
    }

    fun openLiveUpdatesSettings(): Boolean {
        val pkg = context.packageName
        if (Build.VERSION.SDK_INT >= 36) {
            try {
                val intent = Intent(Settings.ACTION_APP_NOTIFICATION_PROMOTION_SETTINGS).apply {
                    putExtra(Settings.EXTRA_APP_PACKAGE, pkg)
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                context.startActivity(intent)
                return true
            } catch (_: Exception) {
            }
        }
        return try {
            val fallback = Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
                putExtra(Settings.EXTRA_APP_PACKAGE, pkg)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(fallback)
            true
        } catch (_: Exception) {
            false
        }
    }
}
