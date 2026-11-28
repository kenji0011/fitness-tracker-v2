package com.tempo.fitness

import android.app.ActivityManager
import android.content.Context
import android.os.Build
import android.view.WindowManager

/**
 * Lightweight, zero-permission Android hardware & chipset inspector used at
 * startup (< 2 ms) to classify the device into Flagship / Balanced / Lite
 * Liquid Glass performance tiers.
 */
class DeviceHardwareHelper(private val context: Context) {

    fun getHardwareProfile(): Map<String, Any> {
        val am = context.getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager
        val memInfo = ActivityManager.MemoryInfo()
        am?.getMemoryInfo(memInfo)
        val totalRamMb = (memInfo.totalMem / (1024L * 1024L)).toInt().coerceAtLeast(0)
        val isLowRam = am?.isLowRamDevice ?: false

        val socModel = readSocModel()
        val socManufacturer = readSocManufacturer()
        val boardPlatform = readSystemProperty("ro.board.platform")
        val chipname = readSystemProperty("ro.hardware.chipname")
        val maxRefreshHz = readMaxRefreshRateHz()

        return mapOf(
            "socModel" to socModel,
            "socManufacturer" to socManufacturer,
            "boardPlatform" to boardPlatform,
            "chipname" to chipname,
            "hardware" to (Build.HARDWARE ?: ""),
            "board" to (Build.BOARD ?: ""),
            "deviceModel" to (Build.MODEL ?: ""),
            "manufacturer" to (Build.MANUFACTURER ?: ""),
            "totalRamMb" to totalRamMb,
            "isLowRamDevice" to isLowRam,
            "cpuCores" to Runtime.getRuntime().availableProcessors(),
            "sdkInt" to Build.VERSION.SDK_INT,
            "maxRefreshRateHz" to maxRefreshHz
        )
    }

    private fun readSocModel(): String {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val m = Build.SOC_MODEL
            if (!m.isNullOrBlank() && !m.equals(Build.UNKNOWN, ignoreCase = true)) {
                return m.trim()
            }
        }
        val prop = readSystemProperty("ro.soc.model")
        if (prop.isNotBlank()) return prop
        val chip = readSystemProperty("ro.hardware.chipname")
        if (chip.isNotBlank()) return chip
        return readSystemProperty("ro.board.platform")
    }

    private fun readSocManufacturer(): String {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val m = Build.SOC_MANUFACTURER
            if (!m.isNullOrBlank() && !m.equals(Build.UNKNOWN, ignoreCase = true)) {
                return m.trim()
            }
        }
        return readSystemProperty("ro.soc.manufacturer")
    }

    private fun readSystemProperty(key: String): String {
        return try {
            val cls = Class.forName("android.os.SystemProperties")
            val get = cls.getMethod("get", String::class.java, String::class.java)
            (get.invoke(null, key, "") as? String)?.trim() ?: ""
        } catch (_: Throwable) {
            ""
        }
    }

    @Suppress("DEPRECATION")
    private fun readMaxRefreshRateHz(): Double {
        return try {
            val display = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                context.display
            } else {
                val wm = context.getSystemService(Context.WINDOW_SERVICE) as? WindowManager
                wm?.defaultDisplay
            }
            if (display == null) return 60.0
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                display.supportedModes.maxOfOrNull { it.refreshRate.toDouble() }
                    ?: display.refreshRate.toDouble()
            } else {
                display.refreshRate.toDouble()
            }
        } catch (_: Throwable) {
            60.0
        }
    }
}
