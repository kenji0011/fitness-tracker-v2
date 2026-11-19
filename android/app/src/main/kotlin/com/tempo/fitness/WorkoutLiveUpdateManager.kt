package com.tempo.fitness

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.Settings

/**
 * Manages Android 16+ (API 36) Live Updates (Promoted Ongoing Notifications)
 * for Xiaomi HyperOS 3 HyperIsland and stock Android Live Update capsules,
 * including a native 1-second ticker so compact HyperIsland pills tick in real time.
 */
class WorkoutLiveUpdateManager(private val context: Context) {
    companion object {
        private const val CHANNEL_ID = "tempo_workout_live_v1"
        private const val CHANNEL_NAME = "Workout Live Updates"
        private const val NOTIFICATION_ID = 4201
        private const val EXTRA_REQUEST_PROMOTED_ONGOING = "android.requestPromotedOngoing"
    }

    private val notificationManager: NotificationManager =
        context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    private val mainHandler = Handler(Looper.getMainLooper())

    private var isActive = false
    private var activeTitle = "Tempo Workout"
    private var activeSubtitle = ""
    private var activeStartEpochMs = 0L
    private var activeCompletedExercises = 0
    private var activeTotalExercises = 1
    private var activePaused = false

    private val tickRunnable = object : Runnable {
        override fun run() {
            if (!isActive || activePaused) return
            val liveSec = ((System.currentTimeMillis() - activeStartEpochMs) / 1000L)
                .toInt()
                .coerceAtLeast(0)
            postNotification(
                title = activeTitle,
                subtitle = activeSubtitle,
                elapsedSeconds = liveSec,
                completedExercises = activeCompletedExercises,
                totalExercises = activeTotalExercises,
                isPaused = false,
                shortText = formatCompactTime(liveSec)
            )
            // Align next tick neatly to the next second boundary
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
            description = "Live workout timer and exercise progress in HyperIsland & status bar"
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
        elapsedSeconds: Int,
        completedExercises: Int,
        totalExercises: Int,
        isPaused: Boolean,
        shortText: String
    ): Map<String, Any> {
        mainHandler.removeCallbacks(tickRunnable)

        isActive = true
        activeTitle = title
        activeSubtitle = subtitle
        activeCompletedExercises = completedExercises
        activeTotalExercises = totalExercises
        activePaused = isPaused
        activeStartEpochMs = System.currentTimeMillis() - (elapsedSeconds.coerceAtLeast(0) * 1000L)

        val effectiveShort = if (isPaused) {
            shortText.ifEmpty { "Paused" }
        } else {
            formatCompactTime(elapsedSeconds)
        }

        val status = postNotification(
            title = title,
            subtitle = subtitle,
            elapsedSeconds = elapsedSeconds,
            completedExercises = completedExercises,
            totalExercises = totalExercises,
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
        subtitle: String,
        elapsedSeconds: Int,
        completedExercises: Int,
        totalExercises: Int,
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

        val builder = Notification.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_tempo)
            .setContentTitle(title)
            .setContentText(subtitle)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setAutoCancel(false)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setContentIntent(contentIntent)

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

            // Compact live timer text displayed inside HyperIsland pill / status chip
            val chipText = shortText.take(7)
            if (chipText.isNotEmpty()) {
                builder.setShortCriticalText(chipText)
            }

            // Native Android 16 ProgressStyle bar for live exercise completion
            val safeTotal = totalExercises.coerceAtLeast(1)
            val pct = ((completedExercises.coerceIn(0, safeTotal) * 100) / safeTotal)
                .coerceIn(0, 100)
            val accentColor = if (isPaused) 0xFF8E8E93.toInt() else 0xFF0A84FF.toInt()

            val progressStyle = Notification.ProgressStyle()
                .setStyledByProgress(false)
                .addProgressSegment(
                    Notification.ProgressStyle.Segment(100).setColor(accentColor)
                )
                .setProgress(pct)
            builder.setStyle(progressStyle)
        } else {
            builder.setCategory(Notification.CATEGORY_PROGRESS)
            if (totalExercises > 0) {
                builder.setProgress(
                    totalExercises,
                    completedExercises.coerceIn(0, totalExercises),
                    false
                )
            }
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
                // Fall back to standard app notification settings below
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
