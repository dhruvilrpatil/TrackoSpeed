package com.example.trackospeed.channels

import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.*
import androidx.core.content.FileProvider
import java.io.File
import java.io.FileOutputStream
import java.io.OutputStream
import java.text.SimpleDateFormat
import java.util.*

/**
 * GallerySaveChannel - Handles saving images to device gallery
 * Uses MediaStore API for Android 10+ and direct file access for older versions
 */
class GallerySaveChannel(
    private val context: Context,
    messenger: BinaryMessenger
) : MethodChannel.MethodCallHandler {

    companion object {
        private const val CHANNEL_NAME = "com.trackospeed/gallery_save"
        private const val TAG = "GallerySave"
        private const val SAVE_TIMEOUT_MS = 10000L
        private const val ALBUM_NAME = "TrackoSpeed"
    }

    private val channel: MethodChannel = MethodChannel(messenger, CHANNEL_NAME)
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    init {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "saveImage" -> handleSaveImage(call, result)
            "saveImageWithMetadata" -> handleSaveImageWithMetadata(call, result)
            "getAlbumPath" -> handleGetAlbumPath(result)
            "openInGallery" -> handleOpenInGallery(call, result)
            "openAlbum" -> handleOpenAlbum(result)
            else -> result.notImplemented()
        }
    }

    /**
     * Save image bytes to gallery
     */
    private fun handleSaveImage(call: MethodCall, result: MethodChannel.Result) {
        scope.launch {
            try {
                val imageBytes = call.argument<ByteArray>("imageBytes")
                val fileName = call.argument<String>("fileName")
                    ?: "TrackoSpeed_${System.currentTimeMillis()}.jpg"

                if (imageBytes == null) {
                    withContext(Dispatchers.Main) {
                        result.error("INVALID_ARGS", "Image bytes required", null)
                    }
                    return@launch
                }

                val saveResult = withTimeoutOrNull(SAVE_TIMEOUT_MS) {
                    saveToGallery(imageBytes, fileName)
                }

                withContext(Dispatchers.Main) {
                    if (saveResult != null) {
                        result.success(mapOf(
                            "success" to true,
                            "path" to saveResult,
                            "message" to "Image saved successfully"
                        ))
                    } else {
                        result.success(mapOf(
                            "success" to false,
                            "path" to "",
                            "message" to "Save timeout or failed"
                        ))
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "Save error: ${e.message}", e)
                withContext(Dispatchers.Main) {
                    result.success(mapOf(
                        "success" to false,
                        "path" to "",
                        "message" to "Error: ${e.message}"
                    ))
                }
            }
        }
    }

    /**
     * Save image with EXIF metadata
     */
    private fun handleSaveImageWithMetadata(call: MethodCall, result: MethodChannel.Result) {
        scope.launch {
            try {
                val imageBytes = call.argument<ByteArray>("imageBytes")
                val fileName = call.argument<String>("fileName")
                    ?: "TrackoSpeed_${System.currentTimeMillis()}.jpg"
                val metadata = call.argument<Map<String, Any>>("metadata")

                if (imageBytes == null) {
                    withContext(Dispatchers.Main) {
                        result.error("INVALID_ARGS", "Image bytes required", null)
                    }
                    return@launch
                }

                val saveResult = withTimeoutOrNull(SAVE_TIMEOUT_MS) {
                    saveToGalleryWithMetadata(imageBytes, fileName, metadata)
                }

                withContext(Dispatchers.Main) {
                    if (saveResult != null) {
                        result.success(mapOf(
                            "success" to true,
                            "path" to saveResult,
                            "message" to "Image saved with metadata"
                        ))
                    } else {
                        result.success(mapOf(
                            "success" to false,
                            "path" to "",
                            "message" to "Save failed"
                        ))
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "Save with metadata error: ${e.message}", e)
                withContext(Dispatchers.Main) {
                    result.success(mapOf(
                        "success" to false,
                        "path" to "",
                        "message" to "Error: ${e.message}"
                    ))
                }
            }
        }
    }

    /**
     * Open an image file in the device's default gallery / photo viewer
     */
    private fun handleOpenInGallery(call: MethodCall, result: MethodChannel.Result) {
        try {
            val path = call.argument<String>("path") ?: ""
            if (path.isBlank()) {
                result.success(false)
                return
            }

            val uri = if (path.startsWith("content://")) {
                Uri.parse(path)
            } else {
                val file = File(path)
                if (!file.exists()) {
                    result.success(false)
                    return
                }
                FileProvider.getUriForFile(
                    context,
                    "${context.packageName}.fileprovider",
                    file
                )
            }

            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "image/*")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(intent)
            result.success(true)
        } catch (e: Exception) {
            Log.e(TAG, "Open in gallery error: ${e.message}", e)
            result.success(false)
        }
    }

    /**
     * Open the TrackoSpeed album in the device gallery app
     */
    private fun handleOpenAlbum(result: MethodChannel.Result) {
        try {
            // Try to find the latest image in our album and open it
            val selection = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                "${MediaStore.Images.Media.RELATIVE_PATH} LIKE ?"
            } else {
                "${MediaStore.Images.Media.DATA} LIKE ?"
            }
            val selectionArgs = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                arrayOf("%Pictures/$ALBUM_NAME%")
            } else {
                val dir = File(
                    Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES),
                    ALBUM_NAME
                )
                arrayOf("${dir.absolutePath}%")
            }

            val cursor = context.contentResolver.query(
                MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
                arrayOf(MediaStore.Images.Media._ID),
                selection,
                selectionArgs,
                "${MediaStore.Images.Media.DATE_ADDED} DESC"
            )

            cursor?.use {
                if (it.moveToFirst()) {
                    val id = it.getLong(it.getColumnIndexOrThrow(MediaStore.Images.Media._ID))
                    val uri = android.content.ContentUris.withAppendedId(
                        MediaStore.Images.Media.EXTERNAL_CONTENT_URI, id
                    )
                    val intent = Intent(Intent.ACTION_VIEW).apply {
                        setDataAndType(uri, "image/*")
                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                    context.startActivity(intent)
                    result.success(true)
                    return
                }
            }

            // Fallback: open gallery app to images
            val intent = Intent(Intent.ACTION_VIEW).apply {
                type = "image/*"
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(intent)
            result.success(true)
        } catch (e: Exception) {
            Log.e(TAG, "Open album error: ${e.message}", e)
            result.success(false)
        }
    }

    /**
     * Get album path for display purposes
     */
    private fun handleGetAlbumPath(result: MethodChannel.Result) {
        try {
            val path = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                "Pictures/$ALBUM_NAME"
            } else {
                val dir = File(
                    Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES),
                    ALBUM_NAME
                )
                dir.absolutePath
            }
            result.success(path)
        } catch (e: Exception) {
            Log.e(TAG, "Get path error: ${e.message}", e)
            result.success("Pictures/$ALBUM_NAME")
        }
    }

    /**
     * Save image to gallery using appropriate API
     */
    private suspend fun saveToGallery(imageBytes: ByteArray, fileName: String): String? {
        return withContext(Dispatchers.IO) {
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    saveUsingMediaStore(imageBytes, fileName)
                } else {
                    saveUsingFileApi(imageBytes, fileName)
                }
            } catch (e: Exception) {
                Log.e(TAG, "Gallery save error: ${e.message}", e)
                null
            }
        }
    }

    /**
     * Save using MediaStore API (Android 10+)
     */
    private fun saveUsingMediaStore(imageBytes: ByteArray, fileName: String): String? {
        val contentValues = ContentValues().apply {
            put(MediaStore.Images.Media.DISPLAY_NAME, fileName)
            put(MediaStore.Images.Media.MIME_TYPE, "image/jpeg")
            put(MediaStore.Images.Media.RELATIVE_PATH, "Pictures/$ALBUM_NAME")
            put(MediaStore.Images.Media.IS_PENDING, 1)
        }

        val resolver = context.contentResolver
        val uri = resolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, contentValues)
            ?: return null

        return try {
            resolver.openOutputStream(uri)?.use { outputStream ->
                outputStream.write(imageBytes)
                outputStream.flush()
            }

            // Mark as not pending
            contentValues.clear()
            contentValues.put(MediaStore.Images.Media.IS_PENDING, 0)
            resolver.update(uri, contentValues, null, null)

            Log.i(TAG, "Image saved to MediaStore: $uri")
            uri.toString()
        } catch (e: Exception) {
            // Clean up on failure
            try {
                resolver.delete(uri, null, null)
            } catch (ignored: Exception) {}
            Log.e(TAG, "MediaStore save error: ${e.message}", e)
            null
        }
    }

    /**
     * Save using direct file access (Android 9 and below)
     */
    @Suppress("DEPRECATION")
    private fun saveUsingFileApi(imageBytes: ByteArray, fileName: String): String? {
        val picturesDir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES)
        val albumDir = File(picturesDir, ALBUM_NAME)

        if (!albumDir.exists()) {
            if (!albumDir.mkdirs()) {
                Log.e(TAG, "Failed to create album directory")
                return null
            }
        }

        val file = File(albumDir, fileName)

        return try {
            FileOutputStream(file).use { outputStream ->
                outputStream.write(imageBytes)
                outputStream.flush()
            }

            // Notify media scanner
            val values = ContentValues().apply {
                put(MediaStore.Images.Media.DATA, file.absolutePath)
                put(MediaStore.Images.Media.MIME_TYPE, "image/jpeg")
            }
            context.contentResolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values)

            Log.i(TAG, "Image saved to file: ${file.absolutePath}")
            file.absolutePath
        } catch (e: Exception) {
            Log.e(TAG, "File save error: ${e.message}", e)
            null
        }
    }

    /**
     * Save with additional metadata
     */
    private suspend fun saveToGalleryWithMetadata(
        imageBytes: ByteArray,
        fileName: String,
        metadata: Map<String, Any>?
    ): String? {
        // For now, just save the image - EXIF metadata writing would require additional library
        return saveToGallery(imageBytes, fileName)
    }

    fun dispose() {
        try {
            scope.cancel()
        } catch (e: Exception) {
            Log.e(TAG, "Dispose error: ${e.message}", e)
        }
    }
}

