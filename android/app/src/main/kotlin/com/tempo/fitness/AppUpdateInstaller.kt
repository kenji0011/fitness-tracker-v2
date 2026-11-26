package com.tempo.fitness

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import java.io.File

/**
 * Native Android package installer bridge for Tempo's GitHub Releases updater.
 * Uses a scoped FileProvider (`${applicationId}.update_provider`) restricted to
 * `<cache>/updates/` so downloaded APKs hand off cleanly to Android's system
 * Package Installer on Android 8–17 (API 26–37).
 */
class AppUpdateInstaller(private val context: Context) {

    fun canRequestPackageInstalls(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.packageManager.canRequestPackageInstalls()
        } else {
            true
        }
    }

    fun openInstallPermissionSettings(): Boolean {
        return try {
            val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Intent(
                    Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                    Uri.parse("package:${context.packageName}")
                )
            } else {
                Intent(Settings.ACTION_SECURITY_SETTINGS)
            }
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            context.startActivity(intent)
            true
        } catch (_: Exception) {
            false
        }
    }

    fun installApk(filePath: String): Map<String, Any?> {
        val file = File(filePath)
        if (!file.exists() || !file.isFile || file.length() <= 0L) {
            return mapOf(
                "ok" to false,
                "reason" to "missing_file",
                "message" to "Downloaded update file was not found."
            )
        }

        if (!canRequestPackageInstalls()) {
            return mapOf(
                "ok" to false,
                "reason" to "permission_required",
                "message" to "Enable \"Install unknown apps\" for Tempo to install updates."
            )
        }

        return try {
            val authority = "${context.packageName}.update_provider"
            val apkUri = FileProvider.getUriForFile(context, authority, file)
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(apkUri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(intent)
            mapOf("ok" to true)
        } catch (e: Exception) {
            mapOf(
                "ok" to false,
                "reason" to "launch_failed",
                "message" to (e.message ?: "Could not open Android package installer.")
            )
        }
    }
}
