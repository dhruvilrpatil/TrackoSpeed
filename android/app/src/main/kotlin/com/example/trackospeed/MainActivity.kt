package com.example.trackospeed

import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.example.trackospeed.channels.VehicleDetectionChannel
import com.example.trackospeed.channels.ImageProcessingChannel
import com.example.trackospeed.channels.GallerySaveChannel
import com.example.trackospeed.channels.OcrChannel

/**
 * MainActivity - Entry point for the Flutter Android application
 *
 * This activity sets up platform channels for native Kotlin functionality:
 * - Vehicle Detection (TensorFlow Lite)
 * - Image Processing (Canvas overlay drawing)
 * - Gallery Saving (MediaStore API)
 * - OCR Processing (ML Kit Text Recognition)
 *
 * All native operations are crash-resistant with proper error handling.
 */
class MainActivity : FlutterActivity() {

    companion object {
        private const val TAG = "TrackoSpeed_MainActivity"
    }

    // Platform channel handlers - initialized lazily to prevent crashes
    private var vehicleDetectionChannel: VehicleDetectionChannel? = null
    private var imageProcessingChannel: ImageProcessingChannel? = null
    private var gallerySaveChannel: GallerySaveChannel? = null
    private var ocrChannel: OcrChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        try {
            // Initialize all platform channels with error handling
            initializeChannels(flutterEngine)
        } catch (e: Exception) {
            // Log error but don't crash - channels will gracefully degrade
            android.util.Log.e(TAG, "Error initializing platform channels: ${e.message}", e)
        }
    }

    /**
     * Initialize all platform channels for Flutter communication
     * Each channel is wrapped in try-catch to prevent cascade failures
     */
    private fun initializeChannels(flutterEngine: FlutterEngine) {
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        // Vehicle Detection Channel - TensorFlow Lite inference
        try {
            vehicleDetectionChannel = VehicleDetectionChannel(this, messenger)
        } catch (e: Exception) {
            android.util.Log.e(TAG, "Failed to init VehicleDetectionChannel: ${e.message}", e)
        }

        // Image Processing Channel - Canvas overlay drawing
        try {
            imageProcessingChannel = ImageProcessingChannel(this, messenger)
        } catch (e: Exception) {
            android.util.Log.e(TAG, "Failed to init ImageProcessingChannel: ${e.message}", e)
        }

        // Gallery Save Channel - MediaStore integration
        try {
            gallerySaveChannel = GallerySaveChannel(this, messenger)
        } catch (e: Exception) {
            android.util.Log.e(TAG, "Failed to init GallerySaveChannel: ${e.message}", e)
        }

        // OCR Channel - License plate recognition
        try {
            ocrChannel = OcrChannel(this, messenger)
        } catch (e: Exception) {
            android.util.Log.e(TAG, "Failed to init OcrChannel: ${e.message}", e)
        }
    }

    override fun onDestroy() {
        // Clean up native resources safely
        try {
            vehicleDetectionChannel?.dispose()
            imageProcessingChannel?.dispose()
            gallerySaveChannel?.dispose()
            ocrChannel?.dispose()
        } catch (e: Exception) {
            android.util.Log.e(TAG, "Error during cleanup: ${e.message}", e)
        }

        super.onDestroy()
    }
}
