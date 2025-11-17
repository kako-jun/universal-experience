package com.universalexperience.color_vision_filter

import android.content.Context
import android.graphics.ColorMatrix
import android.graphics.ColorMatrixColorFilter
import android.graphics.PixelFormat
import android.view.View
import android.view.WindowManager
import android.widget.FrameLayout
import androidx.annotation.NonNull
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

/**
 * ColorVisionFilterPlugin
 *
 * Platform plugin for applying color vision deficiency filters system-wide on Android
 */
class ColorVisionFilterPlugin: FlutterPlugin, MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var context: Context
    private var windowManager: WindowManager? = null
    private var overlayView: View? = null
    private var currentType: String = "none"
    private var currentIntensity: Float = 1.0f
    private var isActive: Boolean = false

    override fun onAttachedToEngine(@NonNull flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "color_vision_filter")
        channel.setMethodCallHandler(this)
        context = flutterPluginBinding.applicationContext
        windowManager = context.getSystemService(Context.WINDOW_SERVICE) as WindowManager
    }

    override fun onMethodCall(@NonNull call: MethodCall, @NonNull result: Result) {
        when (call.method) {
            "apply" -> {
                val type = call.argument<String>("type") ?: "none"
                val intensity = call.argument<Double>("intensity")?.toFloat() ?: 1.0f
                applyFilter(type, intensity)
                result.success(true)
            }
            "setIntensity" -> {
                val intensity = call.argument<Double>("intensity")?.toFloat() ?: 1.0f
                setIntensity(intensity)
                result.success(true)
            }
            "remove" -> {
                removeFilter()
                result.success(true)
            }
            "getState" -> {
                val state = mapOf(
                    "type" to currentType,
                    "intensity" to currentIntensity.toDouble(),
                    "isActive" to isActive
                )
                result.success(state)
            }
            "hasPermission" -> {
                // TODO: Check for accessibility service permission
                result.success(false)
            }
            "requestPermission" -> {
                // TODO: Request accessibility service permission
                result.success(false)
            }
            else -> {
                result.notImplemented()
            }
        }
    }

    private fun applyFilter(type: String, intensity: Float) {
        currentType = type
        currentIntensity = intensity
        isActive = type != "none"

        if (isActive) {
            createOverlay(type, intensity)
        } else {
            removeFilter()
        }
    }

    private fun setIntensity(intensity: Float) {
        currentIntensity = intensity
        if (isActive && overlayView != null) {
            applyColorMatrix(overlayView!!, currentType, intensity)
        }
    }

    private fun removeFilter() {
        isActive = false
        overlayView?.let {
            windowManager?.removeView(it)
            overlayView = null
        }
    }

    private fun createOverlay(type: String, intensity: Float) {
        // Remove existing overlay
        removeFilter()

        // TODO: Full implementation requires AccessibilityService
        // This is a placeholder that shows the concept
        // Real implementation will be in a separate AccessibilityService

        // For now, just log the intent
        android.util.Log.d("ColorVisionFilter", "Would apply filter: $type at intensity $intensity")

        // Placeholder: Create a simple overlay view (requires SYSTEM_ALERT_WINDOW permission)
        /*
        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
            WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE or
            WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT
        )

        overlayView = FrameLayout(context).apply {
            setBackgroundColor(0x00000000) // Transparent
        }

        applyColorMatrix(overlayView!!, type, intensity)

        try {
            windowManager?.addView(overlayView, params)
            isActive = true
        } catch (e: Exception) {
            android.util.Log.e("ColorVisionFilter", "Failed to create overlay", e)
            isActive = false
        }
        */
    }

    private fun applyColorMatrix(view: View, type: String, intensity: Float) {
        val matrix = getColorMatrix(type, intensity)
        val filter = ColorMatrixColorFilter(matrix)

        // Apply filter to view
        view.setLayerType(View.LAYER_TYPE_HARDWARE, null)
        val paint = view.paint
        paint?.colorFilter = filter
    }

    private fun getColorMatrix(type: String, intensity: Float): ColorMatrix {
        // LMS transformation matrices based on research
        val transform = when (type) {
            "protanopia" -> floatArrayOf(
                0.0f, 2.02344f, -2.52581f,
                0.0f, 1.0f, 0.0f,
                0.0f, 0.0f, 1.0f
            )
            "deuteranopia" -> floatArrayOf(
                1.0f, 0.0f, 0.0f,
                0.494207f, 0.0f, 1.24827f,
                0.0f, 0.0f, 1.0f
            )
            "tritanopia" -> floatArrayOf(
                1.0f, 0.0f, 0.0f,
                0.0f, 1.0f, 0.0f,
                -0.395913f, 0.801109f, 0.0f
            )
            "achromatopsia" -> floatArrayOf(
                0.299f, 0.587f, 0.114f,
                0.299f, 0.587f, 0.114f,
                0.299f, 0.587f, 0.114f
            )
            else -> floatArrayOf(
                1.0f, 0.0f, 0.0f,
                0.0f, 1.0f, 0.0f,
                0.0f, 0.0f, 1.0f
            )
        }

        // Convert 3x3 to 5x4 ColorMatrix with intensity interpolation
        val matrix = FloatArray(20)
        for (i in 0 until 3) {
            for (j in 0 until 3) {
                val identity = if (i == j) 1.0f else 0.0f
                val value = transform[i * 3 + j]
                matrix[i * 5 + j] = identity + (value - identity) * intensity
            }
        }
        matrix[18] = 1.0f // Alpha

        return ColorMatrix(matrix)
    }

    override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        removeFilter()
    }
}
