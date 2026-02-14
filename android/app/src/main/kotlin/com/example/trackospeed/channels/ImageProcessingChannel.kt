package com.example.trackospeed.channels

import android.content.Context
import android.graphics.*
import android.media.ExifInterface
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.*
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream

/**
 * ImageProcessingChannel - Handles image overlay rendering
 * Draws bounding boxes, speed text, and plate numbers on images using Canvas
 */
class ImageProcessingChannel(
    private val context: Context,
    messenger: BinaryMessenger
) : MethodChannel.MethodCallHandler {

    companion object {
        private const val CHANNEL_NAME = "com.trackospeed/image_processing"
        private const val TAG = "ImageProcessing"
        private const val PROCESSING_TIMEOUT_MS = 5000L
    }

    private val channel: MethodChannel = MethodChannel(messenger, CHANNEL_NAME)
    private val scope = CoroutineScope(Dispatchers.Default + SupervisorJob())

    // Pre-configured paints for overlay drawing
    private val boxPaint = Paint().apply {
        color = Color.parseColor("#FF4444")
        style = Paint.Style.STROKE
        strokeWidth = 6f
        isAntiAlias = true
    }

    private val boxFillPaint = Paint().apply {
        color = Color.parseColor("#33FF4444")
        style = Paint.Style.FILL
    }

    private val textBackgroundPaint = Paint().apply {
        color = Color.parseColor("#DD000000")
        style = Paint.Style.FILL
    }

    private val speedTextPaint = Paint().apply {
        color = Color.WHITE
        textSize = 48f
        typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
        isAntiAlias = true
    }

    private val plateTextPaint = Paint().apply {
        color = Color.parseColor("#FFFF00")
        textSize = 36f
        typeface = Typeface.create(Typeface.MONOSPACE, Typeface.BOLD)
        isAntiAlias = true
    }

    private val infoTextPaint = Paint().apply {
        color = Color.WHITE
        textSize = 28f
        typeface = Typeface.DEFAULT
        isAntiAlias = true
    }

    init {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "renderOverlay" -> handleRenderOverlay(call, result)
            "renderMultipleOverlays" -> handleRenderMultipleOverlays(call, result)
            else -> result.notImplemented()
        }
    }

    /**
     * Render overlay on single image with vehicle data
     */
    private fun handleRenderOverlay(call: MethodCall, result: MethodChannel.Result) {
        scope.launch {
            try {
                val imageBytes = call.argument<ByteArray>("imageBytes")
                val boundingBox = call.argument<Map<String, Double>>("boundingBox")
                val speed = call.argument<Double>("speed") ?: 0.0
                val plateNumber = call.argument<String>("plateNumber")
                val userSpeed = call.argument<Double>("userSpeed") ?: 0.0
                val timestamp = call.argument<String>("timestamp") ?: ""
                val confidence = call.argument<Double>("confidence") ?: 0.0

                if (imageBytes == null || boundingBox == null) {
                    withContext(Dispatchers.Main) {
                        result.error("INVALID_ARGS", "Missing required arguments", null)
                    }
                    return@launch
                }

                val processedImage = withTimeoutOrNull(PROCESSING_TIMEOUT_MS) {
                    processImage(imageBytes, boundingBox, speed, plateNumber,
                                 userSpeed, timestamp, confidence)
                }

                withContext(Dispatchers.Main) {
                    if (processedImage != null) {
                        result.success(processedImage)
                    } else {
                        // Return original image if processing fails
                        result.success(imageBytes)
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "Render error: ${e.message}", e)
                withContext(Dispatchers.Main) {
                    // Return original if available, empty array otherwise
                    val original = call.argument<ByteArray>("imageBytes")
                    result.success(original ?: ByteArray(0))
                }
            }
        }
    }

    /**
     * Render multiple vehicle overlays on single image
     */
    private fun handleRenderMultipleOverlays(call: MethodCall, result: MethodChannel.Result) {
        scope.launch {
            try {
                val imageBytes = call.argument<ByteArray>("imageBytes")
                val vehicles = call.argument<List<Map<String, Any>>>("vehicles")
                val userSpeed = call.argument<Double>("userSpeed") ?: 0.0
                val timestamp = call.argument<String>("timestamp") ?: ""

                if (imageBytes == null) {
                    withContext(Dispatchers.Main) {
                        result.error("INVALID_ARGS", "Image bytes required", null)
                    }
                    return@launch
                }

                val processedImage = withTimeoutOrNull(PROCESSING_TIMEOUT_MS) {
                    processMultipleVehicles(imageBytes, vehicles ?: emptyList(),
                                           userSpeed, timestamp)
                }

                withContext(Dispatchers.Main) {
                    result.success(processedImage ?: imageBytes)
                }
            } catch (e: Exception) {
                Log.e(TAG, "Multi-render error: ${e.message}", e)
                withContext(Dispatchers.Main) {
                    result.success(call.argument<ByteArray>("imageBytes") ?: ByteArray(0))
                }
            }
        }
    }

    /**
     * Process single vehicle overlay
     */
    private suspend fun processImage(
        imageBytes: ByteArray,
        boundingBox: Map<String, Double>,
        speed: Double,
        plateNumber: String?,
        userSpeed: Double,
        timestamp: String,
        confidence: Double
    ): ByteArray? {
        return withContext(Dispatchers.Default) {
            val bitmap = try {
                decodeWithExifRotation(imageBytes) ?: return@withContext null
            } catch (e: Exception) {
                Log.e(TAG, "Decode error: ${e.message}")
                return@withContext null
            }

            try {
                val canvas = Canvas(bitmap)

                // Extract bounding box coordinates
                val left = boundingBox["left"]?.toFloat() ?: 0f
                val top = boundingBox["top"]?.toFloat() ?: 0f
                val right = boundingBox["right"]?.toFloat() ?: 100f
                val bottom = boundingBox["bottom"]?.toFloat() ?: 100f
                val rect = RectF(left, top, right, bottom)

                // Draw bounding box
                canvas.drawRect(rect, boxFillPaint)
                canvas.drawRect(rect, boxPaint)

                // Draw speed label above bounding box
                val speedText = "${speed.toInt()} km/h"
                val speedBounds = Rect()
                speedTextPaint.getTextBounds(speedText, 0, speedText.length, speedBounds)

                val labelPadding = 12f
                val labelLeft = left
                val labelTop = top - speedBounds.height() - labelPadding * 3
                val labelRight = left + speedBounds.width() + labelPadding * 2
                val labelBottom = top - labelPadding

                // Background for speed text
                canvas.drawRoundRect(
                    labelLeft, labelTop, labelRight, labelBottom,
                    8f, 8f, textBackgroundPaint
                )
                canvas.drawText(speedText, left + labelPadding,
                               top - labelPadding * 2, speedTextPaint)

                // Draw plate number if available
                if (!plateNumber.isNullOrBlank()) {
                    val plateBounds = Rect()
                    plateTextPaint.getTextBounds(plateNumber, 0, plateNumber.length, plateBounds)

                    val plateLeft = left
                    val plateTop = bottom + labelPadding
                    val plateRight = left + plateBounds.width() + labelPadding * 2
                    val plateBottom = bottom + plateBounds.height() + labelPadding * 3

                    canvas.drawRoundRect(
                        plateLeft, plateTop, plateRight, plateBottom,
                        8f, 8f, textBackgroundPaint
                    )
                    canvas.drawText(plateNumber, left + labelPadding,
                                   bottom + plateBounds.height() + labelPadding * 2, plateTextPaint)
                }

                // Draw info overlay at top of image
                drawInfoOverlay(canvas, bitmap.width, bitmap.height, userSpeed, timestamp, confidence)

                // Convert to bytes
                val outputStream = ByteArrayOutputStream()
                bitmap.compress(Bitmap.CompressFormat.JPEG, 95, outputStream)
                outputStream.toByteArray()
            } catch (e: Exception) {
                Log.e(TAG, "Canvas error: ${e.message}", e)
                null
            } finally {
                bitmap.recycle()
            }
        }
    }

    /**
     * Process multiple vehicle overlays
     */
    private suspend fun processMultipleVehicles(
        imageBytes: ByteArray,
        vehicles: List<Map<String, Any>>,
        userSpeed: Double,
        timestamp: String
    ): ByteArray? {
        return withContext(Dispatchers.Default) {
            val bitmap = try {
                decodeWithExifRotation(imageBytes) ?: return@withContext null
            } catch (e: Exception) {
                return@withContext null
            }

            try {
                val canvas = Canvas(bitmap)

                // Draw each vehicle
                vehicles.forEachIndexed { index, vehicle ->
                    try {
                        val box = vehicle["boundingBox"] as? Map<*, *> ?: return@forEachIndexed
                        val speed = (vehicle["speed"] as? Number)?.toDouble() ?: 0.0
                        val plate = vehicle["plateNumber"] as? String
                        val confidence = (vehicle["confidence"] as? Number)?.toDouble() ?: 0.0

                        val left = (box["left"] as? Number)?.toFloat() ?: 0f
                        val top = (box["top"] as? Number)?.toFloat() ?: 0f
                        val right = (box["right"] as? Number)?.toFloat() ?: 100f
                        val bottom = (box["bottom"] as? Number)?.toFloat() ?: 100f
                        val rect = RectF(left, top, right, bottom)

                        // Alternate colors for different vehicles
                        val color = when (index % 4) {
                            0 -> Color.parseColor("#FF4444")
                            1 -> Color.parseColor("#44FF44")
                            2 -> Color.parseColor("#4444FF")
                            else -> Color.parseColor("#FFAA00")
                        }
                        boxPaint.color = color
                        boxFillPaint.color = Color.argb(51, Color.red(color),
                                                        Color.green(color), Color.blue(color))

                        canvas.drawRect(rect, boxFillPaint)
                        canvas.drawRect(rect, boxPaint)

                        // Speed label
                        val speedText = "${speed.toInt()} km/h"
                        val labelPadding = 10f
                        canvas.drawRoundRect(
                            left, top - 50f, left + 120f, top - 5f,
                            6f, 6f, textBackgroundPaint
                        )
                        canvas.drawText(speedText, left + labelPadding, top - 15f, speedTextPaint)

                        // Plate if available
                        if (!plate.isNullOrBlank()) {
                            canvas.drawRoundRect(
                                left, bottom + 5f, left + 150f, bottom + 45f,
                                6f, 6f, textBackgroundPaint
                            )
                            canvas.drawText(plate, left + labelPadding, bottom + 35f, plateTextPaint)
                        }
                    } catch (e: Exception) {
                        Log.e(TAG, "Vehicle $index draw error: ${e.message}")
                    }
                }

                // Reset paint colors
                boxPaint.color = Color.parseColor("#FF4444")
                boxFillPaint.color = Color.parseColor("#33FF4444")

                // Draw info overlay
                drawInfoOverlay(canvas, bitmap.width, bitmap.height, userSpeed, timestamp, 0.0)

                val outputStream = ByteArrayOutputStream()
                bitmap.compress(Bitmap.CompressFormat.JPEG, 95, outputStream)
                outputStream.toByteArray()
            } catch (e: Exception) {
                Log.e(TAG, "Multi-vehicle draw error: ${e.message}", e)
                null
            } finally {
                bitmap.recycle()
            }
        }
    }

    /**
     * Draw info overlay at top of image.
     * Scales bar height, text size, and padding relative to the shorter
     * dimension so the overlay looks consistent regardless of orientation.
     */
    private fun drawInfoOverlay(
        canvas: Canvas,
        imageWidth: Int,
        imageHeight: Int,
        userSpeed: Double,
        timestamp: String,
        confidence: Double
    ) {
        // Scale relative to shorter edge (portrait-width or landscape-height)
        val refDim = minOf(imageWidth, imageHeight).toFloat()
        val scale = (refDim / 1080f).coerceIn(0.5f, 3f)   // 1080px reference

        val barHeight = 80f * scale
        val textSize  = 22f * scale
        val padding   = 20f * scale
        val lineGap   = 30f * scale

        // Semi-transparent background at top
        val infoPaint = Paint().apply {
            color = Color.parseColor("#AA000000")
            style = Paint.Style.FILL
        }
        canvas.drawRect(0f, 0f, imageWidth.toFloat(), barHeight, infoPaint)

        // Scaled info text paint
        val scaledInfoPaint = Paint(infoTextPaint).apply {
            this.textSize = textSize
        }

        // User speed
        canvas.drawText("Your Speed: ${userSpeed.toInt()} km/h", padding, padding + textSize * 0.4f, scaledInfoPaint)

        // Timestamp
        canvas.drawText(timestamp, padding, padding + textSize * 0.4f + lineGap, scaledInfoPaint)

        // TrackoSpeed watermark
        val watermarkPaint = Paint().apply {
            color = Color.parseColor("#88FFFFFF")
            this.textSize = textSize
            textAlign = Paint.Align.RIGHT
            isAntiAlias = true
        }
        canvas.drawText("TrackoSpeed", imageWidth - padding, padding + textSize * 0.4f, watermarkPaint)

        if (confidence > 0) {
            canvas.drawText("Confidence: ${(confidence * 100).toInt()}%",
                           imageWidth - padding, padding + textSize * 0.4f + lineGap, watermarkPaint)
        }
    }

    /**
     * Decode JPEG bytes and apply EXIF rotation so the bitmap matches
     * the orientation used by VehicleDetectionChannel (whose bounding-box
     * coordinates are in the post-rotation pixel space).
     */
    private fun decodeWithExifRotation(imageBytes: ByteArray): Bitmap? {
        var bitmap = BitmapFactory.decodeByteArray(imageBytes, 0, imageBytes.size)
            ?: return null
        bitmap = bitmap.copy(Bitmap.Config.ARGB_8888, true)

        try {
            val exifStream = ByteArrayInputStream(imageBytes)
            val exif = ExifInterface(exifStream)
            val orientation = exif.getAttributeInt(
                ExifInterface.TAG_ORIENTATION,
                ExifInterface.ORIENTATION_NORMAL
            )
            val rotationDegrees = when (orientation) {
                ExifInterface.ORIENTATION_ROTATE_90  -> 90f
                ExifInterface.ORIENTATION_ROTATE_180 -> 180f
                ExifInterface.ORIENTATION_ROTATE_270 -> 270f
                else -> 0f
            }
            if (rotationDegrees != 0f) {
                val matrix = Matrix()
                matrix.postRotate(rotationDegrees)
                val rotated = Bitmap.createBitmap(
                    bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true
                )
                if (rotated != bitmap) {
                    bitmap.recycle()
                    bitmap = rotated
                    // Make mutable for Canvas drawing
                    if (!bitmap.isMutable) {
                        val mutable = bitmap.copy(Bitmap.Config.ARGB_8888, true)
                        bitmap.recycle()
                        bitmap = mutable
                    }
                }
                Log.d(TAG, "Applied EXIF rotation: ${rotationDegrees}° → ${bitmap.width}x${bitmap.height}")
            }
        } catch (e: Exception) {
            Log.w(TAG, "EXIF rotation skipped: ${e.message}")
        }

        return bitmap
    }

    fun dispose() {
        try {
            scope.cancel()
        } catch (e: Exception) {
            Log.e(TAG, "Dispose error: ${e.message}", e)
        }
    }
}

