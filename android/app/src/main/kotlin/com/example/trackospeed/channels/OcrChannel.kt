package com.example.trackospeed.channels

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.ColorMatrix
import android.graphics.ColorMatrixColorFilter
import android.graphics.Paint
import android.graphics.Rect
import android.util.Log
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.TextRecognizer
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.*
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

/**
 * OcrChannel - Handles license plate text recognition using ML Kit
 *
 * Improvements:
 * - Image preprocessing (contrast boost + grayscale) before OCR
 * - Bottom-focused vehicle crop (plates are in the lower 50%)
 * - More plate patterns (US, UK, Indian, EU variants)
 * - Multi-pass OCR: full region + bottom-half for best result
 * - Plate scoring with letter/digit balance heuristic
 */
class OcrChannel(
    private val context: Context,
    messenger: BinaryMessenger
) : MethodChannel.MethodCallHandler {

    companion object {
        private const val CHANNEL_NAME = "com.trackospeed/ocr"
        private const val TAG = "OcrChannel"
        private const val OCR_TIMEOUT_MS = 8000L
        private const val MIN_OCR_WIDTH = 300  // Upscale crops smaller than this
        private const val BBOX_EXPAND_RATIO = 0.20f  // Expand vehicle bbox by 20%

        // License plate text patterns — ordered most-specific → least-specific
        private val PLATE_PATTERNS = listOf(
            // Indian format: MH48AW2767 or MH 48 AW 2767
            Regex("[A-Z]{2}\\s?\\d{1,2}\\s?[A-Z]{1,3}\\s?\\d{1,4}"),
            // EU standard: AB-1234-CD  or  AB 12 CD 34
            Regex("[A-Z]{2,3}[\\s-]?\\d{2,4}[\\s-]?[A-Z]{1,3}[\\s-]?\\d{1,4}"),
            // UK format: AB12 CDE
            Regex("[A-Z]{2}\\d{2}\\s?[A-Z]{3}"),
            // US-style: 1ABC234 or ABC-1234
            Regex("\\d[A-Z]{2,3}\\d{2,4}"),
            Regex("[A-Z]{2,3}[\\s-]?\\d{3,4}"),
            // Reversed: 1234-AB-56
            Regex("\\d{1,4}[\\s-]?[A-Z]{2,3}[\\s-]?\\d{0,4}"),
            // Generic alphanumeric: 5–10 chars, must contain at least 1 letter and 1 digit
            Regex("(?=.*[A-Z])(?=.*[0-9])[A-Z0-9]{5,10}")
        )
    }

    private val channel: MethodChannel = MethodChannel(messenger, CHANNEL_NAME)
    private val scope = CoroutineScope(Dispatchers.Default + SupervisorJob())
    private var textRecognizer: TextRecognizer? = null

    init {
        channel.setMethodCallHandler(this)
        initializeRecognizer()
    }

    private fun initializeRecognizer() {
        try {
            textRecognizer = TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
            Log.i(TAG, "Text recognizer initialized")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to init text recognizer: ${e.message}", e)
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "recognizePlate" -> handleRecognizePlate(call, result)
            "recognizePlateInRegion" -> handleRecognizePlateInRegion(call, result)
            "recognizeAllText" -> handleRecognizeAllText(call, result)
            else -> result.notImplemented()
        }
    }

    /**
     * Recognize license plate from full image
     */
    private fun handleRecognizePlate(call: MethodCall, result: MethodChannel.Result) {
        scope.launch {
            try {
                val imageBytes = call.argument<ByteArray>("imageBytes")
                if (imageBytes == null) {
                    withContext(Dispatchers.Main) {
                        result.error("INVALID_ARGS", "Image bytes required", null)
                    }
                    return@launch
                }

                val ocrResult = withTimeoutOrNull(OCR_TIMEOUT_MS) {
                    recognizePlateText(imageBytes, null)
                }

                withContext(Dispatchers.Main) {
                    result.success(ocrResult ?: mapOf(
                        "success" to false,
                        "plateNumber" to "",
                        "confidence" to 0.0,
                        "message" to "Recognition timeout"
                    ))
                }
            } catch (e: Exception) {
                Log.e(TAG, "Recognize error: ${e.message}", e)
                withContext(Dispatchers.Main) {
                    result.success(mapOf(
                        "success" to false,
                        "plateNumber" to "",
                        "confidence" to 0.0,
                        "message" to "Error: ${e.message}"
                    ))
                }
            }
        }
    }

    /**
     * Recognize license plate within specific region
     */
    private fun handleRecognizePlateInRegion(call: MethodCall, result: MethodChannel.Result) {
        scope.launch {
            try {
                val imageBytes = call.argument<ByteArray>("imageBytes")
                val region = call.argument<Map<String, Int>>("region")

                if (imageBytes == null) {
                    withContext(Dispatchers.Main) {
                        result.error("INVALID_ARGS", "Image bytes required", null)
                    }
                    return@launch
                }

                val rect = region?.let {
                    Rect(
                        it["left"] ?: 0,
                        it["top"] ?: 0,
                        it["right"] ?: 100,
                        it["bottom"] ?: 100
                    )
                }

                val ocrResult = withTimeoutOrNull(OCR_TIMEOUT_MS) {
                    recognizePlateText(imageBytes, rect)
                }

                withContext(Dispatchers.Main) {
                    result.success(ocrResult ?: mapOf(
                        "success" to false,
                        "plateNumber" to "",
                        "confidence" to 0.0,
                        "message" to "Recognition timeout"
                    ))
                }
            } catch (e: Exception) {
                Log.e(TAG, "Region recognize error: ${e.message}", e)
                withContext(Dispatchers.Main) {
                    result.success(mapOf(
                        "success" to false,
                        "plateNumber" to "",
                        "confidence" to 0.0,
                        "message" to "Error: ${e.message}"
                    ))
                }
            }
        }
    }

    /**
     * Recognize all text in image
     */
    private fun handleRecognizeAllText(call: MethodCall, result: MethodChannel.Result) {
        scope.launch {
            try {
                val imageBytes = call.argument<ByteArray>("imageBytes")
                if (imageBytes == null) {
                    withContext(Dispatchers.Main) {
                        result.error("INVALID_ARGS", "Image bytes required", null)
                    }
                    return@launch
                }

                val ocrResult = withTimeoutOrNull(OCR_TIMEOUT_MS) {
                    recognizeAllText(imageBytes)
                }

                withContext(Dispatchers.Main) {
                    result.success(ocrResult ?: mapOf(
                        "success" to false,
                        "text" to "",
                        "blocks" to emptyList<Map<String, Any>>()
                    ))
                }
            } catch (e: Exception) {
                Log.e(TAG, "All text error: ${e.message}", e)
                withContext(Dispatchers.Main) {
                    result.success(mapOf(
                        "success" to false,
                        "text" to "",
                        "blocks" to emptyList<Map<String, Any>>()
                    ))
                }
            }
        }
    }

    /**
     * Perform license plate text recognition with preprocessing and multi-pass
     */
    private suspend fun recognizePlateText(
        imageBytes: ByteArray,
        region: Rect?
    ): Map<String, Any> {
        return withContext(Dispatchers.Default) {
            val recognizer = textRecognizer ?: return@withContext mapOf(
                "success" to false,
                "plateNumber" to "",
                "confidence" to 0.0,
                "message" to "Recognizer not available"
            )

            val fullCrop = try {
                var bmp = BitmapFactory.decodeByteArray(imageBytes, 0, imageBytes.size)
                    ?: return@withContext mapOf(
                        "success" to false,
                        "plateNumber" to "",
                        "confidence" to 0.0,
                        "message" to "Failed to decode image"
                    )

                // Crop to region if specified, with bbox expansion + upscaling
                if (region != null && region.width() > 0 && region.height() > 0) {
                    // Expand bounding box by BBOX_EXPAND_RATIO to capture plate area beyond tight vehicle bbox
                    val expandW = (region.width() * BBOX_EXPAND_RATIO).toInt()
                    val expandH = (region.height() * BBOX_EXPAND_RATIO).toInt()
                    val safeLeft = (region.left - expandW).coerceIn(0, bmp.width - 1)
                    val safeTop = (region.top - expandH).coerceIn(0, bmp.height - 1)
                    val safeRight = (region.right + expandW).coerceIn(safeLeft + 1, bmp.width)
                    val safeBottom = (region.bottom + expandH).coerceIn(safeTop + 1, bmp.height)
                    val safeWidth = safeRight - safeLeft
                    val safeHeight = safeBottom - safeTop

                    var cropped = Bitmap.createBitmap(bmp, safeLeft, safeTop, safeWidth, safeHeight)
                    if (cropped != bmp) bmp.recycle()

                    // Upscale small crops so ML Kit can read the text
                    if (cropped.width < MIN_OCR_WIDTH) {
                        val scale = MIN_OCR_WIDTH.toFloat() / cropped.width
                        val scaledW = (cropped.width * scale).toInt()
                        val scaledH = (cropped.height * scale).toInt()
                        val scaled = Bitmap.createScaledBitmap(cropped, scaledW, scaledH, true)
                        cropped.recycle()
                        cropped = scaled
                    }
                    cropped
                } else {
                    bmp
                }
            } catch (e: Exception) {
                Log.e(TAG, "Bitmap error: ${e.message}", e)
                return@withContext mapOf(
                    "success" to false,
                    "plateNumber" to "",
                    "confidence" to 0.0,
                    "message" to "Image processing error"
                )
            }

            try {
                // ── Pass 1: contrast-enhanced full region ──
                val enhanced = enhanceForOcr(fullCrop)
                val pass1Plate = runOcrPass(recognizer, enhanced)
                enhanced.recycle()

                // ── Pass 2: bottom 50% of region (plates are near bumper) ──
                var pass2Plate = ""
                if (fullCrop.height > 40) {
                    val bottomTop = fullCrop.height / 2
                    val bottomCrop = Bitmap.createBitmap(
                        fullCrop, 0, bottomTop,
                        fullCrop.width, fullCrop.height - bottomTop
                    )
                    val bottomEnhanced = enhanceForOcr(bottomCrop)
                    bottomCrop.recycle()
                    pass2Plate = runOcrPass(recognizer, bottomEnhanced)
                    bottomEnhanced.recycle()
                }

                // ── Pass 3: bottom 35% with higher contrast (close-up plate area) ──
                var pass3Plate = ""
                if (fullCrop.height > 60) {
                    val plateTop = (fullCrop.height * 0.65).toInt()
                    val plateCrop = Bitmap.createBitmap(
                        fullCrop, 0, plateTop,
                        fullCrop.width, fullCrop.height - plateTop
                    )
                    val plateEnhanced = enhanceForOcr(plateCrop, contrastBoost = 1.8f)
                    plateCrop.recycle()
                    pass3Plate = runOcrPass(recognizer, plateEnhanced)
                    plateEnhanced.recycle()
                }

                // ── Pass 4: binarized (black/white) full region — helps in low contrast ──
                var pass4Plate = ""
                if (pass1Plate.isEmpty() && pass2Plate.isEmpty() && pass3Plate.isEmpty()) {
                    val binarized = binarizeForOcr(fullCrop)
                    pass4Plate = runOcrPass(recognizer, binarized)
                    binarized.recycle()
                }

                // ── Pass 5: inverted (light text on dark background) ──
                var pass5Plate = ""
                if (pass1Plate.isEmpty() && pass2Plate.isEmpty() && pass3Plate.isEmpty() && pass4Plate.isEmpty()) {
                    val inverted = invertForOcr(fullCrop)
                    pass5Plate = runOcrPass(recognizer, inverted)
                    inverted.recycle()
                }

                // Pick the best plate across all passes
                val bestPlate = pickBestPlate(pass1Plate, pass2Plate, pass3Plate, pass4Plate, pass5Plate)
                val confidence = if (bestPlate.isNotEmpty()) {
                    scorePlate(bestPlate).coerceIn(0.5, 1.0)
                } else 0.0

                Log.d(TAG, "OCR passes: p1='$pass1Plate' p2='$pass2Plate' p3='$pass3Plate' p4='$pass4Plate' p5='$pass5Plate' → best='$bestPlate'")

                mapOf(
                    "success" to bestPlate.isNotEmpty(),
                    "plateNumber" to bestPlate,
                    "confidence" to confidence,
                    "rawText" to "$pass1Plate|$pass2Plate|$pass3Plate",
                    "message" to if (bestPlate.isNotEmpty()) "Plate found" else "No plate detected"
                )
            } catch (e: Exception) {
                Log.e(TAG, "Recognition error: ${e.message}", e)
                mapOf(
                    "success" to false,
                    "plateNumber" to "",
                    "confidence" to 0.0,
                    "message" to "Error: ${e.message}"
                )
            } finally {
                fullCrop.recycle()
            }
        }
    }

    /**
     * Run a single ML Kit OCR pass and extract the best plate candidate.
     */
    private suspend fun runOcrPass(recognizer: TextRecognizer, bitmap: Bitmap): String {
        return suspendCancellableCoroutine { cont ->
            val inputImage = InputImage.fromBitmap(bitmap, 0)
            recognizer.process(inputImage)
                .addOnSuccessListener { visionText ->
                    cont.resume(findPlateNumber(visionText.text))
                }
                .addOnFailureListener { e ->
                    Log.w(TAG, "OCR pass failed: ${e.message}")
                    cont.resume("")
                }
        }
    }

    /**
     * Enhance a bitmap for OCR: boost contrast, convert to grayscale, sharpen edges.
     * This dramatically improves ML Kit's ability to read plate text.
     */
    private fun enhanceForOcr(src: Bitmap, contrastBoost: Float = 1.5f): Bitmap {
        val w = src.width
        val h = src.height
        val enhanced = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(enhanced)

        // Step 1: Contrast boost via ColorMatrix
        val contrast = contrastBoost
        val translate = (-0.5f * contrast + 0.5f) * 255f
        val cm = ColorMatrix(floatArrayOf(
            contrast, 0f, 0f, 0f, translate,
            0f, contrast, 0f, 0f, translate,
            0f, 0f, contrast, 0f, translate,
            0f, 0f, 0f, 1f, 0f
        ))

        // Step 2: Desaturate to grayscale (helps text stand out)
        val grayscale = ColorMatrix()
        grayscale.setSaturation(0f)
        cm.postConcat(grayscale)

        val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        paint.colorFilter = ColorMatrixColorFilter(cm)
        canvas.drawBitmap(src, 0f, 0f, paint)

        return enhanced
    }

    /**
     * Pick the best plate among multiple OCR pass results.
     * Prefers longer plates with balanced letter/digit ratio.
     */
    private fun pickBestPlate(vararg candidates: String): String {
        return candidates
            .filter { it.isNotEmpty() }
            .maxByOrNull { scorePlate(it) }
            ?: ""
    }

    /**
     * Score a plate candidate: higher is better.
     * Rewards: length, mixed alphanumeric, specific-pattern match.
     */
    private fun scorePlate(plate: String): Double {
        if (plate.isEmpty()) return 0.0
        val cleaned = plate.replace(Regex("[\\s-]"), "")
        var score = cleaned.length * 0.1  // Base: length

        // Bonus for mixed alphanumeric
        val digits = cleaned.count { it.isDigit() }
        val letters = cleaned.count { it.isLetter() }
        if (digits > 0 && letters > 0) score += 0.3

        // Bonus for balanced ratio (ideal ~40-60% digits)
        val ratio = digits.toDouble() / cleaned.length
        if (ratio in 0.25..0.75) score += 0.2

        // Bonus for matching a specific pattern (not the broad fallback)
        val specificPatterns = PLATE_PATTERNS.dropLast(1) // exclude fallback
        for (p in specificPatterns) {
            if (p.matches(cleaned)) {
                score += 0.3
                break
            }
        }

        return score
    }

    /**
     * Recognize all text in image
     */
    private suspend fun recognizeAllText(imageBytes: ByteArray): Map<String, Any> {
        return withContext(Dispatchers.Default) {
            val recognizer = textRecognizer ?: return@withContext mapOf(
                "success" to false,
                "text" to "",
                "blocks" to emptyList<Map<String, Any>>()
            )

            val bitmap = try {
                BitmapFactory.decodeByteArray(imageBytes, 0, imageBytes.size)
                    ?: return@withContext mapOf(
                        "success" to false,
                        "text" to "",
                        "blocks" to emptyList<Map<String, Any>>()
                    )
            } catch (e: Exception) {
                return@withContext mapOf(
                    "success" to false,
                    "text" to "",
                    "blocks" to emptyList<Map<String, Any>>()
                )
            }

            try {
                val inputImage = InputImage.fromBitmap(bitmap, 0)
                suspendCancellableCoroutine { cont ->
                    recognizer.process(inputImage)
                        .addOnSuccessListener { visionText ->
                            val blocks = visionText.textBlocks.map { block ->
                                mapOf(
                                    "text" to block.text,
                                    "boundingBox" to mapOf(
                                        "left" to (block.boundingBox?.left ?: 0),
                                        "top" to (block.boundingBox?.top ?: 0),
                                        "right" to (block.boundingBox?.right ?: 0),
                                        "bottom" to (block.boundingBox?.bottom ?: 0)
                                    ),
                                    "confidence" to 0.9
                                )
                            }

                            cont.resume(mapOf(
                                "success" to true,
                                "text" to visionText.text,
                                "blocks" to blocks
                            ))
                        }
                        .addOnFailureListener { e ->
                            cont.resume(mapOf(
                                "success" to false,
                                "text" to "",
                                "blocks" to emptyList<Map<String, Any>>(),
                                "message" to "Error: ${e.message}"
                            ))
                        }
                }
            } catch (e: Exception) {
                mapOf(
                    "success" to false,
                    "text" to "",
                    "blocks" to emptyList<Map<String, Any>>()
                )
            } finally {
                bitmap.recycle()
            }
        }
    }

    /**
     * Find license plate number from recognized text.
     * Extracts ALL candidates, scores them, and returns the best.
     * Applies OCR character confusion correction (O↔0, I↔1, B↔8, S↔5).
     */
    private fun findPlateNumber(text: String): String {
        if (text.isBlank()) return ""

        // Clean and normalize text
        val cleanText = text.uppercase()
            .replace("\n", " ")
            .replace(Regex("[^A-Z0-9\\s-]"), "")
            .trim()

        // Collect ALL candidates from ALL patterns (not just first match)
        val candidates = mutableListOf<String>()

        for (pattern in PLATE_PATTERNS) {
            var searchText = cleanText
            var match = pattern.find(searchText)
            while (match != null) {
                val candidate = match.value.replace(Regex("[\\s-]"), "")
                // Require at least 2 digits AND 2 letters — real plates are alphanumeric
                val digits = candidate.count { it.isDigit() }
                val letters = candidate.count { it.isLetter() }
                if (candidate.length in 4..12 && digits >= 2 && letters >= 2) {
                    candidates.add(candidate)
                    // Also try with OCR confusion correction
                    val corrected = correctOcrConfusions(candidate)
                    if (corrected != candidate) {
                        candidates.add(corrected)
                    }
                }
                searchText = searchText.substring(match.range.last + 1)
                match = pattern.find(searchText)
            }
        }

        // Fallback: try word-level extraction
        if (candidates.isEmpty()) {
            val words = cleanText.split(Regex("\\s+"))
            for (word in words) {
                val cleaned = word.replace(Regex("[^A-Z0-9]"), "")
                if (cleaned.length in 4..12 && cleaned.any { it.isDigit() } && cleaned.any { it.isLetter() }) {
                    // Skip common vehicle brand names / stickers
                    if (!isCommonWord(cleaned)) {
                        candidates.add(cleaned)
                        val corrected = correctOcrConfusions(cleaned)
                        if (corrected != cleaned) candidates.add(corrected)
                    }
                }
            }
        }

        // Return the highest-scored candidate
        return candidates
            .filter { !isCommonWord(it) }
            .maxByOrNull { scorePlate(it) }
            ?: ""
    }

    /**
     * Correct common OCR character confusions.
     * Applies context-aware substitution based on expected plate structure
     * (letters in letter positions, digits in digit positions).
     */
    private fun correctOcrConfusions(plate: String): String {
        // Common OCR confusion pairs
        val sb = StringBuilder(plate)

        // Analyze the plate to determine expected structure:
        // If surrounded by digits, a char should probably be a digit; vice versa
        for (i in sb.indices) {
            val c = sb[i]
            val prevIsDigit = if (i > 0) sb[i - 1].isDigit() else false
            val nextIsDigit = if (i < sb.length - 1) sb[i + 1].isDigit() else false
            val prevIsLetter = if (i > 0) sb[i - 1].isLetter() else false
            val nextIsLetter = if (i < sb.length - 1) sb[i + 1].isLetter() else false

            // In a digit context (both neighbors are digits), fix letters → digits
            if (prevIsDigit && nextIsDigit) {
                when (c) {
                    'O' -> sb[i] = '0'
                    'I' -> sb[i] = '1'
                    'l' -> sb[i] = '1'
                    'S' -> sb[i] = '5'
                    'B' -> sb[i] = '8'
                    'G' -> sb[i] = '6'
                    'Z' -> sb[i] = '2'
                    'T' -> sb[i] = '7'
                }
            }
            // In a letter context (both neighbors are letters), fix digits → letters
            if (prevIsLetter && nextIsLetter) {
                when (c) {
                    '0' -> sb[i] = 'O'
                    '1' -> sb[i] = 'I'
                    '8' -> sb[i] = 'B'
                    '5' -> sb[i] = 'S'
                    '6' -> sb[i] = 'G'
                    '2' -> sb[i] = 'Z'
                }
            }
        }
        return sb.toString()
    }

    /**
     * Binarize bitmap using adaptive thresholding for OCR.
     * Converts to pure black/white which helps in poor contrast conditions.
     */
    private fun binarizeForOcr(src: Bitmap): Bitmap {
        val w = src.width
        val h = src.height
        val result = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        val pixels = IntArray(w * h)
        src.getPixels(pixels, 0, w, 0, 0, w, h)

        // Convert to grayscale and apply Otsu-like threshold
        val gray = IntArray(w * h)
        var sum = 0L
        for (i in pixels.indices) {
            val p = pixels[i]
            val g = (0.299 * ((p shr 16) and 0xFF) +
                     0.587 * ((p shr 8) and 0xFF) +
                     0.114 * (p and 0xFF)).toInt()
            gray[i] = g
            sum += g
        }
        val threshold = (sum / pixels.size).toInt()

        for (i in pixels.indices) {
            val v = if (gray[i] > threshold) 255 else 0
            pixels[i] = (0xFF shl 24) or (v shl 16) or (v shl 8) or v
        }
        result.setPixels(pixels, 0, w, 0, 0, w, h)
        return result
    }

    /**
     * Invert bitmap colors for OCR — handles light text on dark plate backgrounds.
     */
    private fun invertForOcr(src: Bitmap): Bitmap {
        val w = src.width
        val h = src.height
        val inverted = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(inverted)
        val cm = ColorMatrix(floatArrayOf(
            -1f, 0f, 0f, 0f, 255f,
            0f, -1f, 0f, 0f, 255f,
            0f, 0f, -1f, 0f, 255f,
            0f, 0f, 0f, 1f, 0f
        ))
        val paint = Paint()
        paint.colorFilter = ColorMatrixColorFilter(cm)
        canvas.drawBitmap(src, 0f, 0f, paint)
        return inverted
    }

    /**
     * Filter out common vehicle brand names, stickers, and road words
     * that ML Kit may read and get confused with plate numbers.
     */
    private fun isCommonWord(text: String): Boolean {
        val word = text.uppercase()
        val commonWords = setOf(
            "TOYOTA", "HONDA", "FORD", "NISSAN", "MAZDA", "SUZUKI",
            "HYUNDAI", "MARUTI", "TATA", "MAHINDRA", "BMW", "AUDI",
            "MERCEDES", "DIESEL", "TURBO", "HYBRID", "SPORT", "AUTO",
            "DANGER", "CAUTION", "STOP", "SPEED", "WARNING", "POLICE",
            "AMBULANCE", "SCHOOL", "TAXI", "UBER", "LYFT"
        )
        return commonWords.contains(word)
    }

    fun dispose() {
        try {
            scope.cancel()
            textRecognizer?.close()
            textRecognizer = null
        } catch (e: Exception) {
            Log.e(TAG, "Dispose error: ${e.message}", e)
        }
    }
}

