package com.tempo.fitness

import android.content.ClipData
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.media.MediaScannerConnection
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import androidx.core.content.FileProvider
import java.io.File

/**
 * Native Android helper for saving exported Tempo progress posters to the
 * device Gallery (`Pictures/Tempo`) via MediaStore (zero legacy storage
 * permissions needed on Android 10+) and launching Android's native Share Sheet
 * with a scoped FileProvider content URI.
 */
class ShareImageHelper(private val context: Context) {

    fun saveImageToGallery(sourcePath: String, displayName: String): Map<String, Any?> {
        val src = File(sourcePath)
        if (!src.exists() || !src.isFile) {
            return mapOf("ok" to false, "error" to "Image file not found")
        }

        val safeName = if (displayName.endsWith(".png", ignoreCase = true)) {
            displayName
        } else {
            "$displayName.png"
        }

        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val values = ContentValues().apply {
                    put(MediaStore.Images.Media.DISPLAY_NAME, safeName)
                    put(MediaStore.Images.Media.MIME_TYPE, "image/png")
                    put(
                        MediaStore.Images.Media.RELATIVE_PATH,
                        "${Environment.DIRECTORY_PICTURES}/Tempo"
                    )
                    put(MediaStore.Images.Media.IS_PENDING, 1)
                }
                val resolver = context.contentResolver
                val uri = resolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values)
                    ?: return mapOf("ok" to false, "error" to "Could not create gallery entry")

                resolver.openOutputStream(uri)?.use { out ->
                    src.inputStream().use { input -> input.copyTo(out) }
                } ?: return mapOf("ok" to false, "error" to "Could not open output stream")

                val doneValues = ContentValues().apply {
                    put(MediaStore.Images.Media.IS_PENDING, 0)
                }
                resolver.update(uri, doneValues, null, null)
                mapOf("ok" to true, "uri" to uri.toString(), "location" to "Pictures/Tempo/$safeName")
            } else {
                @Suppress("DEPRECATION")
                val picturesDir = File(
                    Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES),
                    "Tempo"
                )
                if (!picturesDir.exists()) picturesDir.mkdirs()
                val dest = File(picturesDir, safeName)
                src.copyTo(dest, overwrite = true)
                MediaScannerConnection.scanFile(
                    context,
                    arrayOf(dest.absolutePath),
                    arrayOf("image/png"),
                    null
                )
                mapOf("ok" to true, "path" to dest.absolutePath, "location" to "Pictures/Tempo/$safeName")
            }
        } catch (e: Exception) {
            mapOf("ok" to false, "error" to (e.message ?: "Failed to save image"))
        }
    }

    fun shareImage(sourcePath: String, text: String?): Map<String, Any?> {
        val file = File(sourcePath)
        if (!file.exists() || !file.isFile) {
            return mapOf("ok" to false, "error" to "Share image file not found")
        }

        return try {
            val authority = "${context.packageName}.update_provider"
            val contentUri = FileProvider.getUriForFile(context, authority, file)

            val sendIntent = Intent(Intent.ACTION_SEND).apply {
                type = "image/png"
                putExtra(Intent.EXTRA_STREAM, contentUri)
                if (!text.isNullOrBlank()) {
                    putExtra(Intent.EXTRA_TEXT, text)
                }
                clipData = ClipData.newUri(context.contentResolver, "Tempo Progress", contentUri)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }

            val chooser = Intent.createChooser(sendIntent, "Share progress").apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            context.startActivity(chooser)
            mapOf("ok" to true)
        } catch (e: Exception) {
            mapOf("ok" to false, "error" to (e.message ?: "Could not open share sheet"))
        }
    }
}
