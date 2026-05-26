import Flutter
import UIKit
import ARKit

// MARK: - Plugin entry point

public class ArVolumeScannerPlugin: NSObject, FlutterPlugin {

    private static var eventSink: FlutterEventSink?
    private static var arSession: ARVolumeSession?

    public static func register(with registrar: FlutterPluginRegistrar) {
        let methodChannel = FlutterMethodChannel(
            name: "com.nalugala.ar_volume_scanner/methods",
            binaryMessenger: registrar.messenger()
        )
        let eventChannel = FlutterEventChannel(
            name: "com.nalugala.ar_volume_scanner/events",
            binaryMessenger: registrar.messenger()
        )

        let instance = ArVolumeScannerPlugin()
        registrar.addMethodCallDelegate(instance, channel: methodChannel)

        let streamHandler = ScanStateStreamHandler()
        eventChannel.setStreamHandler(streamHandler)
        ArVolumeScannerPlugin.eventSink = nil

        registrar.register(
            ARViewFactory(messenger: registrar.messenger()),
            withId: "com.nalugala.ar_volume_scanner/ar_view"
        )
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {

        case "isSupported":
            result(ARWorldTrackingConfiguration.isSupported)

        case "hasLidar":
            if #available(iOS 14.0, *) {
                result(ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh))
            } else {
                result(false)
            }

        case "startScan":
            guard let args = call.arguments as? [String: Any] else {
                result(FlutterError(code: "BAD_ARGS", message: "Expected map", details: nil))
                return
            }
            let config = ScanConfig(from: args)
            let session = ARVolumeSession(config: config) { [weak self] event in
                ArVolumeScannerPlugin.eventSink?(event)
            }
            ArVolumeScannerPlugin.arSession = session
            session.start { volumeResult in
                result(volumeResult)
            } onError: { error in
                result(FlutterError(code: "SCAN_ERROR", message: error, details: nil))
            }

        case "stopScan":
            ArVolumeScannerPlugin.arSession?.stop()
            ArVolumeScannerPlugin.arSession = nil
            result(nil)

        default:
            result(FlutterMethodNotImplemented)
        }
    }
}

// MARK: - Stream handler

class ScanStateStreamHandler: NSObject, FlutterStreamHandler {
    private var sink: FlutterEventSink?

    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        sink = events
        ArVolumeScannerPlugin.setEventSink(events)
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        sink = nil
        ArVolumeScannerPlugin.setEventSink(nil)
        return nil
    }
}

extension ArVolumeScannerPlugin {
    static func setEventSink(_ sink: FlutterEventSink?) {
        eventSink = sink
    }
}

// MARK: - Scan configuration model

struct ScanConfig {
    let preferredAlgorithm: String
    let maxScanSeconds: Int
    let minDepthConfidence: Float
    let showPointCloud: Bool

    init(from map: [String: Any]) {
        preferredAlgorithm = map["preferredAlgorithm"] as? String ?? "convexHull"
        maxScanSeconds = map["maxScanSeconds"] as? Int ?? 10
        minDepthConfidence = (map["minDepthConfidence"] as? Double).map { Float($0) } ?? 0.5
        showPointCloud = map["showPointCloud"] as? Bool ?? false
    }
}

// MARK: - AR Volume Session

class ARVolumeSession: NSObject, ARSessionDelegate {

    private let config: ScanConfig
    private let onEvent: ([String: Any]) -> Void
    private var onComplete: (([String: Any]) -> Void)?
    private var onError: ((String) -> Void)?
    private var arSession: ARSession?
    private var scanTimer: Timer?
    private var collectedPoints: [SIMD3<Float>] = []
    private var meshVertices: [SIMD3<Float>] = []
    private var meshFaces: [(Int, Int, Int)] = []
    private var isScanning = false

    init(config: ScanConfig, onEvent: @escaping ([String: Any]) -> Void) {
        self.config = config
        self.onEvent = onEvent
    }

    func start(onComplete: @escaping ([String: Any]) -> Void,
               onError: @escaping (String) -> Void) {
        self.onComplete = onComplete
        self.onError = onError

        guard ARWorldTrackingConfiguration.isSupported else {
            onError("AR not supported on this device")
            return
        }

        sendEvent(phase: "initialising", progress: 0)

        let arConfig = ARWorldTrackingConfiguration()
        arConfig.frameSemantics = []

        if #available(iOS 14.0, *),
           ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            arConfig.sceneReconstruction = .mesh
        }

        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            arConfig.frameSemantics.insert(.sceneDepth)
        } else if ARWorldTrackingConfiguration.supportsFrameSemantics(.smoothedSceneDepth) {
            arConfig.frameSemantics.insert(.smoothedSceneDepth)
        }

        arConfig.planeDetection = [.horizontal, .vertical]

        arSession = ARSession()
        arSession?.delegate = self
        arSession?.run(arConfig)

        isScanning = true
        collectedPoints.removeAll()
        meshVertices.removeAll()
        meshFaces.removeAll()

        sendEvent(phase: "detecting", progress: 0,
                  message: "Move around the object slowly")

        let maxTime = TimeInterval(config.maxScanSeconds)
        scanTimer = Timer.scheduledTimer(withTimeInterval: maxTime, repeats: false) { [weak self] _ in
            self?.finaliseScan()
        }
    }

    func stop() {
        scanTimer?.invalidate()
        arSession?.pause()
        isScanning = false
    }

    // MARK: ARSessionDelegate

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard isScanning else { return }

        let elapsed = frame.timestamp
        let fraction = min(Float(elapsed) / Float(config.maxScanSeconds), 1.0)
        sendEvent(phase: "scanning", progress: fraction,
                  message: "Captured \(collectedPoints.count) points")

        // Collect depth-based point cloud
        collectDepthPoints(from: frame)
    }

    @available(iOS 14.0, *)
    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        collectMeshAnchors(anchors)
    }

    @available(iOS 14.0, *)
    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        collectMeshAnchors(anchors)
    }

    // MARK: - Depth point collection

    private func collectDepthPoints(from frame: ARFrame) {
        guard let depthMap = frame.sceneDepth?.depthMap ??
              frame.smoothedSceneDepth?.depthMap else { return }

        let intrinsics = frame.camera.intrinsics
        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)
        let step = 8

        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }

        guard let base = CVPixelBufferGetBaseAddress(depthMap) else { return }
        let floatBuffer = base.assumingMemoryBound(to: Float32.self)

        for row in stride(from: 0, to: height, by: step) {
            for col in stride(from: 0, to: width, by: step) {
                let depth = floatBuffer[row * width + col]
                guard depth > 0.05 && depth < 5.0 else { continue }

                let xCam = (Float(col) - intrinsics[2][0]) * depth / intrinsics[0][0]
                let yCam = (Float(row) - intrinsics[2][1]) * depth / intrinsics[1][1]
                let point = SIMD3<Float>(xCam, yCam, -depth)

                let worldPoint = frame.camera.transform * SIMD4<Float>(point, 1)
                collectedPoints.append(SIMD3<Float>(worldPoint.x, worldPoint.y, worldPoint.z))
            }
        }
    }

    // MARK: - LiDAR mesh collection

    @available(iOS 14.0, *)
    private func collectMeshAnchors(_ anchors: [ARAnchor]) {
        for anchor in anchors {
            guard let meshAnchor = anchor as? ARMeshAnchor else { continue }
            let geometry = meshAnchor.geometry
            let transform = meshAnchor.transform

            let vertexCount = geometry.vertices.count
            for i in 0..<vertexCount {
                let v = geometry.vertices.vertex(at: UInt32(i))
                let local = SIMD4<Float>(v.0, v.1, v.2, 1)
                let world = transform * local
                meshVertices.append(SIMD3<Float>(world.x, world.y, world.z))
            }

            let faceCount = geometry.faces.count
            for i in 0..<faceCount {
                let idx0 = Int(geometry.faces.buffer.contents()
                    .assumingMemoryBound(to: UInt32.self)[i * 3])
                let idx1 = Int(geometry.faces.buffer.contents()
                    .assumingMemoryBound(to: UInt32.self)[i * 3 + 1])
                let idx2 = Int(geometry.faces.buffer.contents()
                    .assumingMemoryBound(to: UInt32.self)[i * 3 + 2])
                meshFaces.append((idx0, idx1, idx2))
            }
        }
    }

    // MARK: - Finalise & calculate

    private func finaliseScan() {
        guard isScanning else { return }
        isScanning = false
        scanTimer?.invalidate()
        arSession?.pause()

        sendEvent(phase: "processing", progress: 0.9)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            let result: [String: Any]

            // Prefer mesh-based tetrahedra volume when LiDAR data is available
            if #available(iOS 14.0, *), !self.meshVertices.isEmpty {
                result = VolumeCalculator.meshTetrahedraVolume(
                    vertices: self.meshVertices,
                    faces: self.meshFaces
                )
            } else if !self.collectedPoints.isEmpty {
                let algo = self.config.preferredAlgorithm
                if algo == "convexHull" {
                    result = VolumeCalculator.convexHullVolume(points: self.collectedPoints)
                } else {
                    result = VolumeCalculator.boundingBoxVolume(points: self.collectedPoints)
                }
            } else {
                DispatchQueue.main.async {
                    self.onError?("No depth data was captured. Ensure the object is within 0.1–5 m.")
                }
                return
            }

            DispatchQueue.main.async {
                self.sendEvent(phase: "complete", progress: 1.0)
                self.onComplete?(result)
            }
        }
    }

    // MARK: - Helpers

    private func sendEvent(phase: String, progress: Float, message: String? = nil) {
        var event: [String: Any] = ["phase": phase, "progress": progress]
        if let msg = message { event["message"] = msg }
        onEvent(event)
    }
}

// MARK: - Volume calculation algorithms

struct VolumeCalculator {

    /// Axis-aligned bounding box: width × height × depth (fast, rough).
    static func boundingBoxVolume(points: [SIMD3<Float>]) -> [String: Any] {
        var minP = points[0], maxP = points[0]
        for p in points {
            minP = SIMD3<Float>(min(minP.x, p.x), min(minP.y, p.y), min(minP.z, p.z))
            maxP = SIMD3<Float>(max(maxP.x, p.x), max(maxP.y, p.y), max(maxP.z, p.z))
        }
        let size = maxP - minP
        let w = Double(size.x) * 100, h = Double(size.y) * 100, d = Double(size.z) * 100
        return buildResult(volumeCm3: w * h * d, w: w, h: h, d: d,
                           count: points.count, algo: "boundingBox")
    }

    /// Convex hull bounding volume — better for convex objects.
    /// Uses the O(n) AABB of a trimmed set of extreme points as an approximation
    /// since a full 3-D convex hull is expensive to implement in Swift without SceneKit meshes.
    static func convexHullVolume(points: [SIMD3<Float>]) -> [String: Any] {
        // Select only extreme points along each axis (approximate convex hull extent)
        let sorted = points.sorted { $0.x < $1.x }
        let trimCount = max(1, Int(Double(sorted.count) * 0.02))
        var hull = Array(sorted.prefix(trimCount)) + Array(sorted.suffix(trimCount))

        let sortedY = points.sorted { $0.y < $1.y }
        hull += Array(sortedY.prefix(trimCount)) + Array(sortedY.suffix(trimCount))

        let sortedZ = points.sorted { $0.z < $1.z }
        hull += Array(sortedZ.prefix(trimCount)) + Array(sortedZ.suffix(trimCount))

        // Compute AABB of the hull subset — approximates convex hull volume
        var minP = hull[0], maxP = hull[0]
        for p in hull {
            minP = SIMD3<Float>(min(minP.x, p.x), min(minP.y, p.y), min(minP.z, p.z))
            maxP = SIMD3<Float>(max(maxP.x, p.x), max(maxP.y, p.y), max(maxP.z, p.z))
        }
        let size = maxP - minP

        // Apply a sphericity correction factor (~0.524 for a sphere-like object)
        let correction = 0.6
        let w = Double(size.x) * 100, h = Double(size.y) * 100, d = Double(size.z) * 100
        return buildResult(volumeCm3: w * h * d * correction, w: w, h: h, d: d,
                           count: points.count, algo: "convexHull")
    }

    /// Signed-tetrahedra method on a closed mesh — most accurate, requires LiDAR.
    @available(iOS 14.0, *)
    static func meshTetrahedraVolume(vertices: [SIMD3<Float>],
                                     faces: [(Int, Int, Int)]) -> [String: Any] {
        var volume = Double(0)
        for (i0, i1, i2) in faces {
            guard i0 < vertices.count, i1 < vertices.count, i2 < vertices.count else { continue }
            let v0 = vertices[i0], v1 = vertices[i1], v2 = vertices[i2]
            volume += signedTetraVolume(v0: v0, v1: v1, v2: v2)
        }
        volume = abs(volume) * 1_000_000 // m³ → cm³

        // Derive bounding box from all mesh vertices for dimension display
        var minP = vertices[0], maxP = vertices[0]
        for v in vertices {
            minP = SIMD3<Float>(min(minP.x, v.x), min(minP.y, v.y), min(minP.z, v.z))
            maxP = SIMD3<Float>(max(maxP.x, v.x), max(maxP.y, v.y), max(maxP.z, v.z))
        }
        let size = maxP - minP
        let w = Double(size.x) * 100, h = Double(size.y) * 100, d = Double(size.z) * 100
        return buildResult(volumeCm3: volume, w: w, h: h, d: d,
                           count: vertices.count, algo: "meshTetrahedra")
    }

    private static func signedTetraVolume(v0: SIMD3<Float>,
                                           v1: SIMD3<Float>,
                                           v2: SIMD3<Float>) -> Double {
        let x = Double(dot(v0, cross(v1, v2))) / 6.0
        return x
    }

    private static func buildResult(volumeCm3: Double,
                                    w: Double, h: Double, d: Double,
                                    count: Int,
                                    algo: String) -> [String: Any] {
        return [
            "volumeCm3": volumeCm3,
            "widthCm": w,
            "heightCm": h,
            "depthCm": d,
            "pointCount": count,
            "algorithm": algo,
            "timestampMs": Int(Date().timeIntervalSince1970 * 1000),
        ]
    }
}

// MARK: - Platform View Factory

class ARViewFactory: NSObject, FlutterPlatformViewFactory {
    private let messenger: FlutterBinaryMessenger

    init(messenger: FlutterBinaryMessenger) {
        self.messenger = messenger
    }

    func create(withFrame frame: CGRect,
                viewIdentifier viewId: Int64,
                arguments args: Any?) -> FlutterPlatformView {
        return ARFlutterView(frame: frame, viewId: viewId, args: args)
    }

    func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
        return FlutterStandardMessageCodec.sharedInstance()
    }
}

class ARFlutterView: NSObject, FlutterPlatformView {
    private var arView: UIView

    init(frame: CGRect, viewId: Int64, args: Any?) {
        if ARWorldTrackingConfiguration.isSupported {
            let sceneView = ARSCNView(frame: frame)
            sceneView.automaticallyUpdatesLighting = true
            arView = sceneView
        } else {
            // Fallback for simulator / unsupported devices
            let fallback = UIView(frame: frame)
            fallback.backgroundColor = UIColor.black
            let label = UILabel(frame: fallback.bounds)
            label.text = "AR not supported on this device"
            label.textColor = .white
            label.textAlignment = .center
            fallback.addSubview(label)
            arView = fallback
        }
        super.init()
    }

    func view() -> UIView { arView }
}
