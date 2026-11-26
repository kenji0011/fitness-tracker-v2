package com.tempo.fitness

import android.app.NotificationManager
import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack
import android.os.Build
import java.util.concurrent.Executors
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.exp
import kotlin.math.sin

/**
 * Synthesizes clean Apple Fitness-style 3-2-1-GO countdown tones using AudioTrack
 * without stealing music audio focus, while strictly respecting Android Silent,
 * Vibrate, and Do Not Disturb modes (even when media volume is turned up).
 */
class WorkoutSoundHelper(private val context: Context) {

    companion object {
        private const val SAMPLE_RATE = 44100
    }

    private val executor = Executors.newSingleThreadExecutor { r ->
        Thread(r, "tempo-workout-sound").apply { isDaemon = true }
    }

    @Volatile
    private var activeTrack: AudioTrack? = null

    private val tickPcm: ShortArray by lazy {
        // Crisp 115ms warm bell ping (A5 880 Hz + soft 2nd harmonic)
        synthesizeTone(
            durationMs = 115,
            baseFreqHz = 880.0,
            harmonicFreqHz = 1760.0,
            harmonicGain = 0.14,
            decayRate = 26.0,
            amplitude = 0.56
        )
    }

    private val goPcm: ShortArray by lazy {
        // Uplifting 280ms bright "GO!" chime (D6 1174.66 Hz + A6 1760 Hz harmonic)
        synthesizeTone(
            durationMs = 280,
            baseFreqHz = 1174.66,
            harmonicFreqHz = 1760.0,
            harmonicGain = 0.34,
            decayRate = 11.0,
            amplitude = 0.64
        )
    }

    fun isDeviceSilent(): Boolean {
        val am = context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager ?: return true

        // Strictly mute when phone is in Silent or Vibrate mode, even if media volume is up.
        if (am.ringerMode != AudioManager.RINGER_MODE_NORMAL) {
            return true
        }

        // Also treat zero ringer volume as silent on OEMs (e.g. HyperOS/MIUI) where
        // silent toggles drop STREAM_RING to 0 while leaving media volume up.
        if (am.getStreamVolume(AudioManager.STREAM_RING) <= 0) {
            return true
        }

        // Also respect Do Not Disturb Total Silence / Alarms-only filters.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
            val filter = nm?.currentInterruptionFilter ?: NotificationManager.INTERRUPTION_FILTER_ALL
            if (filter == NotificationManager.INTERRUPTION_FILTER_NONE ||
                filter == NotificationManager.INTERRUPTION_FILTER_ALARMS
            ) {
                return true
            }
        }

        // Respect muted media volume slider as well.
        if (am.getStreamVolume(AudioManager.STREAM_MUSIC) <= 0) {
            return true
        }

        return false
    }

    fun playCountdownTick(): Boolean {
        if (isDeviceSilent()) return false
        playPcmAsync(tickPcm)
        return true
    }

    fun playCountdownGo(): Boolean {
        if (isDeviceSilent()) return false
        playPcmAsync(goPcm)
        return true
    }

    fun stop() {
        executor.execute {
            releaseActiveTrack()
        }
    }

    private fun playPcmAsync(samples: ShortArray) {
        executor.execute {
            try {
                if (isDeviceSilent()) return@execute
                releaseActiveTrack()

                val bufferSizeBytes = samples.size * 2
                val attrs = AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build()

                val format = AudioFormat.Builder()
                    .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                    .setSampleRate(SAMPLE_RATE)
                    .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                    .build()

                val track = AudioTrack.Builder()
                    .setAudioAttributes(attrs)
                    .setAudioFormat(format)
                    .setBufferSizeInBytes(bufferSizeBytes)
                    .setTransferMode(AudioTrack.MODE_STATIC)
                    .build()

                track.write(samples, 0, samples.size)
                activeTrack = track
                track.play()
            } catch (_: Throwable) {
                // Never crash workout flow if audio output is unavailable.
            }
        }
    }

    private fun releaseActiveTrack() {
        val current = activeTrack ?: return
        activeTrack = null
        try {
            if (current.playState == AudioTrack.PLAYSTATE_PLAYING) {
                current.stop()
            }
        } catch (_: Throwable) {
        }
        try {
            current.release()
        } catch (_: Throwable) {
        }
    }

    private fun synthesizeTone(
        durationMs: Int,
        baseFreqHz: Double,
        harmonicFreqHz: Double,
        harmonicGain: Double,
        decayRate: Double,
        amplitude: Double
    ): ShortArray {
        val totalSamples = (SAMPLE_RATE * durationMs) / 1000
        val attackSamples = (SAMPLE_RATE * 6) / 1000 // 6ms smooth raised-cosine attack
        val releaseSamples = (SAMPLE_RATE * 14) / 1000 // 14ms tail fade to zero (no click)
        val out = ShortArray(totalSamples)

        for (i in 0 until totalSamples) {
            val t = i.toDouble() / SAMPLE_RATE.toDouble()
            val attackEnv = if (i < attackSamples) {
                0.5 * (1.0 - cos(PI * i.toDouble() / attackSamples.toDouble()))
            } else {
                1.0
            }
            val tailIndex = totalSamples - 1 - i
            val tailEnv = if (tailIndex < releaseSamples) {
                0.5 * (1.0 - cos(PI * tailIndex.toDouble() / releaseSamples.toDouble()))
            } else {
                1.0
            }
            val decay = exp(-t * decayRate)
            val wave = sin(2.0 * PI * baseFreqHz * t) +
                harmonicGain * sin(2.0 * PI * harmonicFreqHz * t)
            val norm = 1.0 / (1.0 + harmonicGain)
            val sample = (wave * norm * amplitude * attackEnv * tailEnv * decay * Short.MAX_VALUE)
                .toInt()
                .coerceIn(Short.MIN_VALUE.toInt(), Short.MAX_VALUE.toInt())
            out[i] = sample.toShort()
        }
        return out
    }
}
