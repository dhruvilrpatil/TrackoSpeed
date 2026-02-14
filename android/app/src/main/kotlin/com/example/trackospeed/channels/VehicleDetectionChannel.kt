package com.example.trackospeed.channels

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.media.ExifInterface
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.*
import org.tensorflow.lite.Interpreter
import java.io.ByteArrayInputStream
import java.io.FileInputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.MappedByteBuffer
import java.nio.channels.FileChannel

/**
 * VehicleDetectionChannel – real TFLite inference using COCO SSD MobileNet V1.
 *
 * Model input : [1, 300, 300, 3] uint8
 * Model output:
 *   0 – locations [1, 10, 4]  (top, left, bottom, right) normalised 0‥1
 *   1 – classes   [1, 10]     COCO class index (float)
 *   2 – scores    [1, 10]     confidence (float)
 *   3 – count     [1]         number of valid detections
 *
 * Bounding‐box coordinates returned to Flutter are **normalised (0–1)**
 * so the Dart overlay can simply multiply by its container dimensions.
 */
class VehicleDetectionChannel(
    private val context: Context,
    messenger: BinaryMessenger
) : MethodChannel.MethodCallHandler {

    companion object {
        private const val CHANNEL_NAME = "com.trackospeed/vehicle_detection"
        private const val TAG = "VehicleDetection"
        private const val MODEL_FILE = "vehicle_detect.tflite"
        private const val INPUT_SIZE = 300
        private const val MAX_DETECTIONS = 10
        private const val CONFIDENCE_THRESHOLD = 0.30f
        private const val INFERENCE_TIMEOUT_MS = 3000L

        // COCO SSD MobileNet V1 outputs 1-indexed class IDs.
        // Label file: 0=???, 1=person, 2=bicycle, 3=car, 4=motorcycle,
        //             5=airplane, 6=bus, 7=train, 8=truck
        // We accept class IDs that represent vehicles:
        private val VEHICLE_CLASS_IDS = setOf(2, 3, 4, 6, 7, 8)
        //  2 = bicycle, 3 = car, 4 = motorcycle, 6 = bus, 7 = train, 8 = truck

        private val CLASS_NAMES = mapOf(
            2 to "bicycle",
            3 to "car",
            4 to "motorcycle",
            6 to "bus",
            7 to "train",
            8 to "truck"
        )

        // NMS IoU threshold – suppress duplicate detections overlapping > 50%
        private const val NMS_IOU_THRESHOLD = 0.45f
    }

    private val channel: MethodChannel = MethodChannel(messenger, CHANNEL_NAME)
    private val scope = CoroutineScope(Dispatchers.Default + SupervisorJob())
    private var interpreter: Interpreter? = null
    private var isModelLoaded = false
    private var labels: List<String> = emptyList()

    // Pre‐allocated output arrays (reused across calls to avoid GC pressure)
    private val outLocations = Array(1) { Array(MAX_DETECTIONS) { FloatArray(4) } }
    private val outClasses   = Array(1) { FloatArray(MAX_DETECTIONS) }
    private val outScores    = Array(1) { FloatArray(MAX_DETECTIONS) }
    private val outCount     = FloatArray(1)

    init {
        channel.setMethodCallHandler(this)
        scope.launch { loadModel() }
    }

    // ── Method‐channel dispatch ─────────────────────────────────

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "detectVehicles" -> handleDetectVehicles(call, result)
            "isModelLoaded"  -> result.success(isModelLoaded)
            "reloadModel"    -> handleReloadModel(result)
            else             -> result.notImplemented()
        }
    }

    private fun handleDetectVehicles(call: MethodCall, result: MethodChannel.Result) {
        scope.launch {
            try {
                val imageBytes = call.argument<ByteArray>("imageBytes")
                if (imageBytes == null) {
                    withContext(Dispatchers.Main) {
                        result.error("INVALID_ARGUMENT", "Image bytes required", null)
                    }
                    return@launch
                }

                val detectionOutput = withTimeoutOrNull(INFERENCE_TIMEOUT_MS) {
                    detectVehiclesInImage(imageBytes)
                }

                withContext(Dispatchers.Main) {
                    result.success(detectionOutput ?: hashMapOf(
                        "detections" to emptyList<Map<String, Any>>(),
                        "imageWidth" to 0,
                        "imageHeight" to 0
                    ))
                }
            } catch (e: Exception) {
                Log.e(TAG, "Detection error: ${e.message}", e)
                withContext(Dispatchers.Main) {
                    result.success(hashMapOf(
                        "detections" to emptyList<Map<String, Any>>(),
                        "imageWidth" to 0,
                        "imageHeight" to 0
                    ))
                }
            }
        }
    }

    private fun handleReloadModel(result: MethodChannel.Result) {
        scope.launch {
            val success = loadModel()
            withContext(Dispatchers.Main) { result.success(success) }
        }
    }

    // ── Model loading ───────────────────────────────────────────

    private suspend fun loadModel(): Boolean {
        return withContext(Dispatchers.IO) {
            try {
                val modelBuffer = loadModelFile()
                val options = Interpreter.Options().apply {
                    setNumThreads(4)
                }
                interpreter = Interpreter(modelBuffer, options)

                // Load labels
                labels = try {
                    context.assets.open("vehicle_labels.txt")
                        .bufferedReader()
                        .readLines()
                } catch (e: Exception) {
                    Log.w(TAG, "Could not load labels file: ${e.message}")
                    emptyList()
                }

                isModelLoaded = true
                Log.i(TAG, "TFLite model loaded successfully, ${labels.size} labels")
                true
            } catch (e: Exception) {
                Log.e(TAG, "Model load failed: ${e.message}", e)
                isModelLoaded = false
                false
            }
        }
    }

    private fun loadModelFile(): MappedByteBuffer {
        val fd = context.assets.openFd(MODEL_FILE)
        val stream = FileInputStream(fd.fileDescriptor)
        return stream.channel.map(
            FileChannel.MapMode.READ_ONLY,
            fd.startOffset,
            fd.declaredLength
        )
    }

    // ── Inference ───────────────────────────────────────────────

    private suspend fun detectVehiclesInImage(
        imageBytes: ByteArray
    ): Map<String, Any> = withContext(Dispatchers.Default) {
        val tflite = interpreter
            ?: return@withContext hashMapOf<String, Any>(
                "detections" to emptyList<Map<String, Any>>(),
                "imageWidth" to 0,
                "imageHeight" to 0
            )

        // Decode camera frame
        var bitmap = try {
            BitmapFactory.decodeByteArray(imageBytes, 0, imageBytes.size)
                ?: return@withContext hashMapOf<String, Any>(
                    "detections" to emptyList<Map<String, Any>>(),
                    "imageWidth" to 0,
                    "imageHeight" to 0
                )
        } catch (e: Exception) {
            Log.e(TAG, "Bitmap decode failed: ${e.message}")
            return@withContext hashMapOf<String, Any>(
                "detections" to emptyList<Map<String, Any>>(),
                "imageWidth" to 0,
                "imageHeight" to 0
            )
        }

        try {
            // ── Apply EXIF rotation so coordinates match the camera preview ──
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
                    }
                    Log.d(TAG, "Applied EXIF rotation: ${rotationDegrees}°")
                }
            } catch (e: Exception) {
                Log.w(TAG, "EXIF rotation skipped: ${e.message}")
            }

            val imgWidth  = bitmap.width
            val imgHeight = bitmap.height

            // Resize to 300×300
            val resized = Bitmap.createScaledBitmap(bitmap, INPUT_SIZE, INPUT_SIZE, true)

            // Fill input ByteBuffer (uint8 RGB)
            val inputBuffer = ByteBuffer.allocateDirect(INPUT_SIZE * INPUT_SIZE * 3)
            inputBuffer.order(ByteOrder.nativeOrder())
            inputBuffer.rewind()

            val pixels = IntArray(INPUT_SIZE * INPUT_SIZE)
            resized.getPixels(pixels, 0, INPUT_SIZE, 0, 0, INPUT_SIZE, INPUT_SIZE)
            for (pixel in pixels) {
                inputBuffer.put(((pixel shr 16) and 0xFF).toByte()) // R
                inputBuffer.put(((pixel shr 8)  and 0xFF).toByte()) // G
                inputBuffer.put(( pixel          and 0xFF).toByte()) // B
            }
            if (resized != bitmap) resized.recycle()

            // CRITICAL: rewind buffer so TFLite reads from position 0
            inputBuffer.rewind()

            // Prepare output map
            val outputMap = HashMap<Int, Any>()
            outputMap[0] = outLocations
            outputMap[1] = outClasses
            outputMap[2] = outScores
            outputMap[3] = outCount

            // Run inference
            tflite.runForMultipleInputsOutputs(arrayOf(inputBuffer), outputMap)

            val count = outCount[0].toInt().coerceIn(0, MAX_DETECTIONS)
            val results = mutableListOf<Map<String, Any>>()

            for (i in 0 until count) {
                val confidence = outScores[0][i]
                if (confidence < CONFIDENCE_THRESHOLD) continue

                val classId = outClasses[0][i].toInt()
                if (!VEHICLE_CLASS_IDS.contains(classId)) continue

                // Model outputs normalised coords [top, left, bottom, right]
                // Convert to pixel coordinates in the original image so the
                // speed calculator and IoU tracker keep working as before.
                val top    = (outLocations[0][i][0] * imgHeight).toDouble().coerceIn(0.0, imgHeight.toDouble())
                val left   = (outLocations[0][i][1] * imgWidth ).toDouble().coerceIn(0.0, imgWidth.toDouble())
                val bottom = (outLocations[0][i][2] * imgHeight).toDouble().coerceIn(0.0, imgHeight.toDouble())
                val right  = (outLocations[0][i][3] * imgWidth ).toDouble().coerceIn(0.0, imgWidth.toDouble())

                // Sanity: width & height must be positive
                if (right <= left || bottom <= top) continue

                val boxW = right - left
                val boxH = bottom - top
                val aspectRatio = boxW / boxH.coerceAtLeast(1.0)  // width / height
                val boxArea = boxW * boxH
                val frameArea = imgWidth.toDouble() * imgHeight.toDouble()
                val areaFraction = boxArea / frameArea.coerceAtLeast(1.0)

                // ── Reject unrealistic detections ──────────────────────
                // Extreme aspect ratios (slivers) or tiny boxes are noise
                if (aspectRatio > 6.0 || aspectRatio < 0.15) continue
                if (areaFraction < 0.005) continue  // too small to be a real vehicle

                // ── Heuristic class-confusion fix ──────────────────────
                // COCO SSD MobileNet V1 sometimes confuses bicycle (2) ↔
                // car (3). Use bounding-box geometry to correct obvious
                // mis-classifications without touching the detection logic.
                var correctedClassId = classId

                if (classId == 2) { // model says "bicycle"
                    // Cars are wider-than-tall; bicycles are taller-than-wide.
                    // A "bicycle" with wide aspect ratio or large area is almost
                    // certainly a car.
                    if (aspectRatio > 1.2 || areaFraction > 0.08) {
                        correctedClassId = 3  // → car
                        Log.d(TAG, "Reclassified bicycle→car (AR=${String.format("%.2f", aspectRatio)}, area=${String.format("%.3f", areaFraction)})")
                    }
                } else if (classId == 3) { // model says "car"
                    // A very narrow & tall "car" with tiny area may be a bicycle
                    if (aspectRatio < 0.6 && areaFraction < 0.03) {
                        correctedClassId = 2  // → bicycle
                        Log.d(TAG, "Reclassified car→bicycle (AR=${String.format("%.2f", aspectRatio)}, area=${String.format("%.3f", areaFraction)})")
                    }
                }

                // Look up class name from labels file first, then fallback map
                val className = if (correctedClassId in labels.indices && labels[correctedClassId] != "???") {
                    labels[correctedClassId]
                } else {
                    CLASS_NAMES[correctedClassId] ?: "vehicle"
                }

                results.add(mapOf(
                    "classId"     to correctedClassId,
                    "className"   to className,
                    "confidence"  to confidence.toDouble(),
                    "boundingBox" to mapOf(
                        "left"   to left,
                        "top"    to top,
                        "right"  to right,
                        "bottom" to bottom
                    ),
                    "isFallback" to false
                ))
            }

            results.sortByDescending { it["confidence"] as Double }

            // ── Non-Maximum Suppression (NMS) ──────────────────────────
            // Remove duplicate detections that overlap significantly.
            val nmsResults = applyNMS(results, NMS_IOU_THRESHOLD)

            if (nmsResults.isEmpty() && count > 0) {
                // Log all classes seen to help debug filtering
                val classes = (0 until count).map { outClasses[0][it].toInt() }
                val scores  = (0 until count).map { outScores[0][it] }
                Log.d(TAG, "No vehicles passed filter. Classes: $classes, Scores: $scores")
            } else {
                Log.d(TAG, "Detected ${nmsResults.size} vehicles from $count total objects (img: ${imgWidth}x${imgHeight})")
            }
            hashMapOf<String, Any>(
                "detections" to nmsResults,
                "imageWidth" to imgWidth,
                "imageHeight" to imgHeight
            )
        } finally {
            bitmap.recycle()
        }
    }

    // ── Non-Maximum Suppression ───────────────────────────────

    /**
     * Apply greedy NMS: keep the highest-confidence detection for each
     * cluster of heavily overlapping boxes.  Already-sorted desc by confidence.
     */
    private fun applyNMS(
        detections: List<Map<String, Any>>,
        iouThreshold: Float
    ): List<Map<String, Any>> {
        if (detections.size <= 1) return detections

        val kept = mutableListOf<Map<String, Any>>()
        val suppressed = BooleanArray(detections.size)

        for (i in detections.indices) {
            if (suppressed[i]) continue
            kept.add(detections[i])

            val boxI = detections[i]["boundingBox"] as Map<*, *>
            val l1 = (boxI["left"] as Number).toDouble()
            val t1 = (boxI["top"] as Number).toDouble()
            val r1 = (boxI["right"] as Number).toDouble()
            val b1 = (boxI["bottom"] as Number).toDouble()

            for (j in i + 1 until detections.size) {
                if (suppressed[j]) continue

                val boxJ = detections[j]["boundingBox"] as Map<*, *>
                val l2 = (boxJ["left"] as Number).toDouble()
                val t2 = (boxJ["top"] as Number).toDouble()
                val r2 = (boxJ["right"] as Number).toDouble()
                val b2 = (boxJ["bottom"] as Number).toDouble()

                val interL = maxOf(l1, l2)
                val interT = maxOf(t1, t2)
                val interR = minOf(r1, r2)
                val interB = minOf(b1, b2)
                val interW = maxOf(0.0, interR - interL)
                val interH = maxOf(0.0, interB - interT)
                val interArea = interW * interH

                val area1 = (r1 - l1) * (b1 - t1)
                val area2 = (r2 - l2) * (b2 - t2)
                val unionArea = area1 + area2 - interArea

                if (unionArea > 0 && interArea / unionArea > iouThreshold) {
                    suppressed[j] = true
                }
            }
        }
        return kept
    }

    // ── Cleanup ─────────────────────────────────────────────────

    fun dispose() {
        try {
            scope.cancel()
            interpreter?.close()
            interpreter = null
            isModelLoaded = false
        } catch (e: Exception) {
            Log.e(TAG, "Dispose error: ${e.message}", e)
        }
    }
}
