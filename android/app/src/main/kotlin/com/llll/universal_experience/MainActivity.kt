package com.llll.universal_experience

import android.content.ContentValues
import android.content.Intent
import android.net.Uri
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val exportChannel = "universal_experience/export"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, exportChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "savePngToPictures" -> savePngToPictures(call.arguments as? Map<*, *>, result)
                    "viewExportedImage" -> viewExportedImage(call.argument<String>("uri"), result)
                    else -> result.notImplemented()
                }
            }
    }

    private fun savePngToPictures(arguments: Map<*, *>?, result: MethodChannel.Result) {
        val bytes = arguments?.get("bytes") as? ByteArray
        val filename = arguments?.get("filename") as? String
        if (bytes == null || filename.isNullOrBlank()) {
            result.error("invalid_arguments", "PNG bytes and filename are required", null)
            return
        }
        val values = ContentValues().apply {
            put(MediaStore.Images.Media.DISPLAY_NAME, filename)
            put(MediaStore.Images.Media.MIME_TYPE, "image/png")
            put(MediaStore.Images.Media.RELATIVE_PATH, "Pictures/Universal Experience")
            put(MediaStore.Images.Media.IS_PENDING, 1)
        }
        val resolver = contentResolver
        val uri = resolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values)
        if (uri == null) {
            result.error("media_store_insert_failed", "Could not create the exported image", null)
            return
        }
        try {
            resolver.openOutputStream(uri)?.use { it.write(bytes) }
                ?: error("Could not open the exported image")
            values.clear()
            values.put(MediaStore.Images.Media.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
            result.success(uri.toString())
        } catch (error: Exception) {
            resolver.delete(uri, null, null)
            result.error("media_store_write_failed", error.message, null)
        }
    }

    private fun viewExportedImage(rawUri: String?, result: MethodChannel.Result) {
        if (rawUri.isNullOrBlank()) { result.success(false); return }
        try {
            startActivity(Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(Uri.parse(rawUri), "image/png")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            })
            result.success(true)
        } catch (_: Exception) {
            result.success(false)
        }
    }
}
