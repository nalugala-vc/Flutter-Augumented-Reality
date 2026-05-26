package com.nalugala.ar_volume_scanner

import android.app.Activity
import android.content.Context
import android.opengl.GLES30
import android.os.Handler
import android.os.Looper
import android.view.View
import com.google.ar.core.*
import com.google.ar.core.exceptions.UnavailableException
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.*
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import kotlinx.coroutines.*
import java.nio.ByteOrder
import java.nio.ShortBuffer
import kotlin.math.*

// ─────────────────────────────────────────────────────────────────────────────
// Plugin registration
// ─────────────────────────────────────────────────────────────────────────────

class ArVolumeScannerPlugin : FlutterPlugin, MethodChannel.MethodCallHandler, ActivityAware {

    private lateinit var methodChannel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private var eventSink: EventChannel.EventSink? = null
    private var currentSession: ArCoreVolumeSession? = null
    private var activity: Activity? = null
    private var context: Context? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext

        methodChannel = MethodChannel(
            binding.binaryMessenger,
            "com.nalugala.ar_volume_scanner/methods"
        )
        methodChannel.setMethodCallHandler(this)

        eventChannel = EventChannel(
            binding.binaryMessenger,
            "com.nalugala.ar_volume_scanner/events"
        )
        eventChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(args: Any?, sink: EventChannel.EventSink?) {
                eventSink = sink
            }
            override fun onCancel(args: Any?) {
                eventSink = null
            }
        })

        binding.platformViewRegistry.registerViewFactory(
            "com.nalugala.ar_volume_scanner/ar_view",
            ArViewFactory(binding.binaryMessenger)
        )
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isSupported" -> {
                val ctx = context ?: return result.success(false)
                result.success(ArCoreApk.getInstance().checkAvailability(ctx).isSupported)
            }
            "hasLidar" -> result.success(false) // Android doesn't expose LiDAR via ARCore

            "startScan" -> {
                val ctx = context ?: return result.error("NO_CONTEXT", "No context", null)
                val act = activity ?: return result.error("NO_ACTIVITY", "No activity", null)
                @Suppress("UNCHECKED_CAST")
                val args = call.arguments as? Map<String, Any> ?: emptyMap()
                currentSession = ArCoreVolumeSession(ctx, act, args)
                currentSession?.start(
                    onEvent = { event -> Handler(Looper.getMainLooper()).post { eventSink?.success(event) } },
                    onResult = { map -> Handler(Looper.getMainLooper()).post { result.success(map) } },
                    onError = { msg -> Handler(Looper.getMainLooper()).post { result.error("SCAN_ERROR", msg, null) } }
                )
            }

            "stopScan" -> {
                currentSession?.stop()
                currentSession = null
                result.success(null)
            }

            else -> result.notImplemented()
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel.setMethodCallHandler(null)
        currentSession?.stop()
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) { activity = binding.activity }
    override fun onDetachedFromActivityForConfigChanges() { activity = null }
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) { activity = binding.activity }
    override fun onDetachedFromActivity() { activity = null }
}

// ─────────────────────────────────────────────────────────────────────────────
// ARCore scan session
// ─────────────────────────────────────────────────────────────────────────────

class ArCoreVolumeSession(
    private val context: Context,
    private val activity: Activity,
    private val args: Map<String, Any>
) {
    private var arSession: Session? = null
    private val scope = CoroutineScope(Dispatchers.Default + SupervisorJob())
    private val collectedPoints = mutableListOf<FloatArray>() // [x, y, z]
    private var maxScanSeconds: Int = 10
    private var minConfidence: Float = 0.5f
    private var preferredAlgorithm: String = "convexHull"

    fun start(
        onEvent: (Map<String, Any>) -> Unit,
        onResult: (Map<String, Any>) -> Unit,
        onError: (String) -> Unit
    ) {
        maxScanSeconds = (args["maxScanSeconds"] as? Int) ?: 10
        minConfidence = ((args["minDepthConfidence"] as? Double)?.toFloat()) ?: 0.5f
        preferredAlgorithm = (args["preferredAlgorithm"] as? String) ?: "convexHull"

        try {
            arSession = Session(context, setOf(Session.Feature.SHARED_CAMERA))
        } catch (e: UnavailableException) {
            onError("ARCore unavailable: ${e.message}")
            return
        }

        val config = Config(arSession).apply {
            depthMode = Config.DepthMode.AUTOMATIC
            updateMode = Config.UpdateMode.LATEST_CAMERA_IMAGE
            planeFindingMode = Config.PlaneFindingMode.HORIZONTAL_AND_VERTICAL
            focusMode = Config.FocusMode.AUTO
        }
        arSession?.configure(config)

        onEvent(mapOf("phase" to "initialising", "progress" to 0.0f))

        scope.launch {
            arSession?.resume()
            onEvent(mapOf("phase" to "detecting", "progress" to 0.0f,
                "message" to "Move around the object slowly"))

            val startTime = System.currentTimeMillis()
            val maxMs = maxScanSeconds * 1000L

            while (isActive) {
                val elapsed = System.currentTimeMillis() - startTime
                if (elapsed >= maxMs) break

                val frame = try { arSession?.update() } catch (e: Exception) { null }
                if (frame != null) {
                    processFrame(frame)
                    val progress = (elapsed.toFloat() / maxMs).coerceIn(0f, 1f)
                    onEvent(mapOf("phase" to "scanning", "progress" to progress,
                        "message" to "Captured ${collectedPoints.size} points"))
                }
                delay(33) // ~30 fps
            }

            onEvent(mapOf("phase" to "processing", "progress" to 0.9f))

            if (collectedPoints.isEmpty()) {
                onError("No depth data captured. Ensure object is within 0.5–5 m.")
                return@launch
            }

            val result = when (preferredAlgorithm) {
                "convexHull" -> VolumeCalculator.convexHullVolume(collectedPoints)
                else -> VolumeCalculator.boundingBoxVolume(collectedPoints)
            }

            onEvent(mapOf("phase" to "complete", "progress" to 1.0f))
            onResult(result)
            stop()
        }
    }

    private fun processFrame(frame: Frame) {
        if (frame.camera.trackingState != TrackingState.TRACKING) return

        // Use raw depth image if available
        val depthImage: Image? = try { frame.acquireDepthImage16Bits() } catch (e: Exception) { null }
        if (depthImage != null) {
            try {
                extractDepthPoints(depthImage, frame)
            } finally {
                depthImage.close()
            }
            return
        }

        // Fall back to point cloud
        val pointCloud = frame.acquirePointCloud()
        try {
            val buf = pointCloud.points // xyzc format
            while (buf.hasRemaining()) {
                val x = buf.get()
                val y = buf.get()
                val z = buf.get()
                val confidence = buf.get()
                if (confidence >= minConfidence) {
                    collectedPoints.add(floatArrayOf(x, y, z))
                }
            }
        } finally {
            pointCloud.close()
        }
    }

    private fun extractDepthPoints(depthImage: Image, frame: Frame) {
        val width = depthImage.width
        val height = depthImage.height
        val plane = depthImage.planes[0]
        val buffer = plane.buffer.order(ByteOrder.nativeOrder()).asShortBuffer()

        val intrinsics = frame.camera.imageIntrinsics
        val fx = intrinsics.focalLength[0]
        val fy = intrinsics.focalLength[1]
        val cx = intrinsics.principalPoint[0]
        val cy = intrinsics.principalPoint[1]

        val step = 8
        for (row in 0 until height step step) {
            for (col in 0 until width step step) {
                val raw = buffer.get(row * width + col).toInt() and 0xFFFF
                val depthM = raw / 1000f // mm → m
                if (depthM < 0.1f || depthM > 5f) continue

                val xCam = (col - cx) * depthM / fx
                val yCam = (row - cy) * depthM / fy
                collectedPoints.add(floatArrayOf(xCam, yCam, -depthM))
            }
        }
    }

    fun stop() {
        scope.cancel()
        try { arSession?.pause() } catch (_: Exception) {}
        arSession = null
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Volume algorithms
// ─────────────────────────────────────────────────────────────────────────────

object VolumeCalculator {

    fun boundingBoxVolume(points: List<FloatArray>): Map<String, Any> {
        var minX = Float.MAX_VALUE; var minY = Float.MAX_VALUE; var minZ = Float.MAX_VALUE
        var maxX = -Float.MAX_VALUE; var maxY = -Float.MAX_VALUE; var maxZ = -Float.MAX_VALUE
        for (p in points) {
            if (p[0] < minX) minX = p[0]; if (p[0] > maxX) maxX = p[0]
            if (p[1] < minY) minY = p[1]; if (p[1] > maxY) maxY = p[1]
            if (p[2] < minZ) minZ = p[2]; if (p[2] > maxZ) maxZ = p[2]
        }
        val w = (maxX - minX) * 100.0
        val h = (maxY - minY) * 100.0
        val d = (maxZ - minZ) * 100.0
        return buildResult(w * h * d, w, h, d, points.size, "boundingBox")
    }

    fun convexHullVolume(points: List<FloatArray>): Map<String, Any> {
        // Approximate convex hull by selecting extreme points on each axis
        val sortedX = points.sortedBy { it[0] }
        val trim = max(1, (points.size * 0.02).toInt())
        val hull = mutableListOf<FloatArray>()
        hull.addAll(sortedX.take(trim))
        hull.addAll(sortedX.takeLast(trim))
        hull.addAll(points.sortedBy { it[1] }.let { it.take(trim) + it.takeLast(trim) })
        hull.addAll(points.sortedBy { it[2] }.let { it.take(trim) + it.takeLast(trim) })

        var minX = Float.MAX_VALUE; var minY = Float.MAX_VALUE; var minZ = Float.MAX_VALUE
        var maxX = -Float.MAX_VALUE; var maxY = -Float.MAX_VALUE; var maxZ = -Float.MAX_VALUE
        for (p in hull) {
            if (p[0] < minX) minX = p[0]; if (p[0] > maxX) maxX = p[0]
            if (p[1] < minY) minY = p[1]; if (p[1] > maxY) maxY = p[1]
            if (p[2] < minZ) minZ = p[2]; if (p[2] > maxZ) maxZ = p[2]
        }
        val w = (maxX - minX) * 100.0
        val h = (maxY - minY) * 100.0
        val d = (maxZ - minZ) * 100.0
        val correction = 0.6  // sphericity approximation
        return buildResult(w * h * d * correction, w, h, d, points.size, "convexHull")
    }

    private fun buildResult(
        volumeCm3: Double, w: Double, h: Double, d: Double,
        count: Int, algo: String
    ): Map<String, Any> = mapOf(
        "volumeCm3" to volumeCm3,
        "widthCm" to w,
        "heightCm" to h,
        "depthCm" to d,
        "pointCount" to count,
        "algorithm" to algo,
        "timestampMs" to System.currentTimeMillis().toInt()
    )
}

// ─────────────────────────────────────────────────────────────────────────────
// Platform View (AR camera surface)
// ─────────────────────────────────────────────────────────────────────────────

class ArViewFactory(messenger: BinaryMessenger) :
    PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        return ArPlatformView(context)
    }
}

class ArPlatformView(private val ctx: Context) : PlatformView {
    private val surfaceView = android.opengl.GLSurfaceView(ctx).apply {
        setEGLContextClientVersion(3)
        preserveEGLContextOnPause = true
    }
    override fun getView(): View = surfaceView
    override fun dispose() {}
}
