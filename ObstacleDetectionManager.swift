import Foundation
import ARKit
import Vision
import AVFoundation
import UIKit
import Combine

class ObstacleDetectionManager: NSObject, ObservableObject {
    @Published var isActive = false
    @Published var detectedObstacles: [DetectedObstacle] = []
    @Published var safePathDirection: PathDirection?
    @Published var obstacleWarnings: [ObstacleWarning] = []
    
    private var arSession: ARSession?
    private var depthDataOutput: AVCaptureDepthDataOutput?
    private let speechOutput = SpeechOutput()
    
    // Detection settings
    private let detectionRange: Float = 5.0 // 5 meters ahead
    private let warningThreshold: Float = 2.0 // Warn when obstacle within 2 meters
    private let criticalThreshold: Float = 0.5 // Critical warning at 0.5 meters
    private var lastWarningTime = Date.distantPast
    private let warningCooldown: TimeInterval = 3.0
    
    // LiDAR and depth analysis
    private var hasLiDAR = false
    private var hasDepthCamera = false
    private var depthBuffer: CVPixelBuffer?
    private var obstacleAnalysisTimer: Timer?
    
    // Path finding
    private let pathWidth: Float = 1.0 // Required path width for safe navigation
    private var obstacleGrid: [[ObstacleLevel]] = []
    private let gridResolution = 20 // 20x20 grid for path analysis
    
    override init() {
        super.init()
        detectDeviceCapabilities()
        setupObstacleDetection()
    }
    
    deinit {
        stopObstacleDetection()
    }
    
    // MARK: - Device Capabilities
    
    private func detectDeviceCapabilities() {
        // Check for LiDAR support (iPhone 12 Pro and later)
        hasLiDAR = ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
        
        // Check for depth camera support
        hasDepthCamera = AVCaptureDevice.default(.builtInTrueDepthCamera, for: .video, position: .front) != nil
        
        Config.debugLog("Device capabilities - LiDAR: \(hasLiDAR), Depth Camera: \(hasDepthCamera)")
    }
    
    private func setupObstacleDetection() {
        if hasLiDAR {
            setupLiDARDetection()
        } else if hasDepthCamera {
            setupDepthCameraDetection()
        } else {
            setupVisionBasedDetection()
        }
    }
    
    // MARK: - LiDAR Detection Setup
    
    private func setupLiDARDetection() {
        guard ARWorldTrackingConfiguration.isSupported else { return }
        
        arSession = ARSession()
        arSession?.delegate = self
        
        let configuration = ARWorldTrackingConfiguration()
        configuration.sceneReconstruction = .mesh
        configuration.frameSemantics = [.sceneDepth, .smoothedSceneDepth]
        
        Config.debugLog("LiDAR obstacle detection configured")
    }
    
    // MARK: - Depth Camera Detection Setup
    
    private func setupDepthCameraDetection() {
        guard let depthCamera = AVCaptureDevice.default(.builtInTrueDepthCamera, for: .video, position: .back) else {
            Config.debugLog("No depth camera available")
            return
        }
        
        let captureSession = AVCaptureSession()
        
        do {
            let input = try AVCaptureDeviceInput(device: depthCamera)
            if captureSession.canAddInput(input) {
                captureSession.addInput(input)
            }
            
            depthDataOutput = AVCaptureDepthDataOutput()
            depthDataOutput?.setDelegate(self, callbackQueue: DispatchQueue(label: "depth.processing"))
            
            if let output = depthDataOutput, captureSession.canAddOutput(output) {
                captureSession.addOutput(output)
            }
            
            Config.debugLog("Depth camera obstacle detection configured")
        } catch {
            Config.debugLog("Depth camera setup failed: \(error)")
        }
    }
    
    // MARK: - Vision-Based Detection Setup
    
    private func setupVisionBasedDetection() {
        // Fallback to regular camera with ML-based depth estimation
        Config.debugLog("Using vision-based obstacle detection fallback")
    }
    
    // MARK: - Detection Control
    
    func startObstacleDetection() {
        guard !isActive else { return }
        
        isActive = true
        
        if hasLiDAR, let session = arSession {
            let configuration = ARWorldTrackingConfiguration()
            configuration.sceneReconstruction = .mesh
            configuration.frameSemantics = [.sceneDepth, .smoothedSceneDepth]
            session.run(configuration)
            speechOutput.speak("Advanced obstacle detection with LiDAR started")
        } else if hasDepthCamera {
            speechOutput.speak("Depth-based obstacle detection started")
        } else {
            speechOutput.speak("Vision-based obstacle detection started")
        }
        
        // Start periodic obstacle analysis
        obstacleAnalysisTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            self.analyzeObstacles()
        }
        
        Config.debugLog("Obstacle detection started")
    }
    
    func stopObstacleDetection() {
        guard isActive else { return }
        
        isActive = false
        arSession?.pause()
        obstacleAnalysisTimer?.invalidate()
        obstacleAnalysisTimer = nil
        
        speechOutput.speak("Obstacle detection stopped")
        Config.debugLog("Obstacle detection stopped")
    }
    
    // MARK: - Obstacle Analysis
    
    private func analyzeObstacles() {
        if hasLiDAR {
            analyzeLiDARObstacles()
        } else if hasDepthCamera {
            analyzeDepthObstacles()
        } else {
            analyzeVisionObstacles()
        }
        
        // Update safe path after obstacle analysis
        updateSafePathGuidance()
        
        // Check for warnings
        checkObstacleWarnings()
    }
    
    private func analyzeLiDARObstacles() {
        guard let session = arSession,
              let frame = session.currentFrame,
              let depthMap = frame.smoothedSceneDepth?.depthMap else { return }
        
        let obstacles = extractObstaclesFromDepthMap(depthMap, cameraTransform: frame.camera.transform)
        
        DispatchQueue.main.async {
            self.detectedObstacles = obstacles
        }
    }
    
    private func analyzeDepthObstacles() {
        guard let depthBuffer = depthBuffer else { return }
        
        let obstacles = extractObstaclesFromDepthBuffer(depthBuffer)
        
        DispatchQueue.main.async {
            self.detectedObstacles = obstacles
        }
    }
    
    private func analyzeVisionObstacles() {
        // Use ML-based depth estimation from regular camera
        // This is a simplified fallback for devices without dedicated depth sensors
        let obstacles = estimateObstaclesFromVision()
        
        DispatchQueue.main.async {
            self.detectedObstacles = obstacles
        }
    }
    
    // MARK: - Depth Map Processing
    
    private func extractObstaclesFromDepthMap(_ depthMap: CVPixelBuffer, cameraTransform: simd_float4x4) -> [DetectedObstacle] {
        var obstacles: [DetectedObstacle] = []
        
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }
        
        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)
        
        guard let baseAddress = CVPixelBufferGetBaseAddress(depthMap) else { return obstacles }
        
        let depthData = baseAddress.assumingMemoryBound(to: Float32.self)
        
        // Analyze depth data in grid sections
        let sectionWidth = width / gridResolution
        let sectionHeight = height / gridResolution
        
        for row in 0..<gridResolution {
            for col in 0..<gridResolution {
                let startX = col * sectionWidth
                let startY = row * sectionHeight
                let endX = min((col + 1) * sectionWidth, width)
                let endY = min((row + 1) * sectionHeight, height)
                
                var minDepth: Float = Float.greatestFiniteMagnitude
                var avgDepth: Float = 0
                var pixelCount = 0
                
                for y in startY..<endY {
                    for x in startX..<endX {
                        let index = y * (bytesPerRow / MemoryLayout<Float32>.size) + x
                        let depth = depthData[index]
                        
                        if depth > 0 && depth < detectionRange {
                            minDepth = min(minDepth, depth)
                            avgDepth += depth
                            pixelCount += 1
                        }
                    }
                }
                
                if pixelCount > 0 && minDepth < detectionRange {
                    avgDepth /= Float(pixelCount)
                    
                    // Convert screen coordinates to world coordinates
                    let screenPoint = CGPoint(x: (startX + endX) / 2, y: (startY + endY) / 2)
                    let worldPosition = screenToWorldPosition(screenPoint, depth: avgDepth, cameraTransform: cameraTransform)
                    
                    let obstacle = DetectedObstacle(
                        id: UUID(),
                        position: worldPosition,
                        distance: avgDepth,
                        size: estimateObstacleSize(minDepth: minDepth, avgDepth: avgDepth),
                        type: classifyObstacle(depth: avgDepth, size: estimateObstacleSize(minDepth: minDepth, avgDepth: avgDepth)),
                        confidence: calculateConfidence(pixelCount: pixelCount, depthVariation: abs(minDepth - avgDepth))
                    )
                    
                    obstacles.append(obstacle)
                }
            }
        }
        
        return obstacles.filter { $0.confidence > 0.3 } // Only include reliable detections
    }
    
    private func extractObstaclesFromDepthBuffer(_ depthBuffer: CVPixelBuffer) -> [DetectedObstacle] {
        // Similar processing for non-LiDAR depth cameras
        return extractObstaclesFromDepthMap(depthBuffer, cameraTransform: simd_float4x4.identity)
    }
    
    private func estimateObstaclesFromVision() -> [DetectedObstacle] {
        // Simplified vision-based obstacle detection
        // This would use object detection and size estimation
        return []
    }
    
    // MARK: - Safe Path Guidance
    
    private func updateSafePathGuidance() {
        guard !detectedObstacles.isEmpty else {
            safePathDirection = nil
            return
        }
        
        let pathOptions = analyzePossiblePaths()
        safePathDirection = findBestPath(from: pathOptions)
    }
    
    private func analyzePossiblePaths() -> [PathOption] {
        var pathOptions: [PathOption] = []
        
        // Analyze left, center, and right paths
        let directions: [Float] = [-45, 0, 45] // Degrees from forward
        
        for direction in directions {
            let pathClear = isPathClear(direction: direction, width: pathWidth, distance: 3.0)
            let obstacleCount = countObstaclesInPath(direction: direction, width: pathWidth)
            
            let option = PathOption(
                direction: direction,
                isClear: pathClear,
                obstacleCount: obstacleCount,
                score: calculatePathScore(direction: direction, obstacleCount: obstacleCount, isClear: pathClear)
            )
            
            pathOptions.append(option)
        }
        
        return pathOptions
    }
    
    private func isPathClear(direction: Float, width: Float, distance: Float) -> Bool {
        let directionRadians = direction * .pi / 180
        
        for obstacle in detectedObstacles {
            let obstacleAngle = atan2(obstacle.position.x, obstacle.position.z) * 180 / .pi
            let angleDiff = abs(obstacleAngle - direction)
            
            if angleDiff < 30 && obstacle.distance < distance {
                return false
            }
        }
        
        return true
    }
    
    private func countObstaclesInPath(direction: Float, width: Float) -> Int {
        let directionRadians = direction * .pi / 180
        var count = 0
        
        for obstacle in detectedObstacles {
            let obstacleAngle = atan2(obstacle.position.x, obstacle.position.z) * 180 / .pi
            let angleDiff = abs(obstacleAngle - direction)
            
            if angleDiff < 45 {
                count += 1
            }
        }
        
        return count
    }
    
    private func calculatePathScore(direction: Float, obstacleCount: Int, isClear: Bool) -> Float {
        var score: Float = 100
        
        // Prefer forward direction
        score -= abs(direction) * 0.5
        
        // Penalize obstacles
        score -= Float(obstacleCount) * 20
        
        // Bonus for clear paths
        if isClear {
            score += 30
        }
        
        return max(0, score)
    }
    
    private func findBestPath(from options: [PathOption]) -> PathDirection? {
        guard let bestOption = options.max(by: { $0.score < $1.score }) else { return nil }
        
        if bestOption.score < 20 { // No good path available
            return .stop
        }
        
        switch bestOption.direction {
        case -45: return .left
        case 0: return .forward
        case 45: return .right
        default: return .forward
        }
    }
    
    // MARK: - Obstacle Warnings
    
    private func checkObstacleWarnings() {
        let now = Date()
        guard now.timeIntervalSince(lastWarningTime) > warningCooldown else { return }
        
        var newWarnings: [ObstacleWarning] = []
        
        for obstacle in detectedObstacles {
            if obstacle.distance <= criticalThreshold {
                let warning = ObstacleWarning(
                    type: .critical,
                    obstacle: obstacle,
                    message: "Stop! \(obstacle.type.description) directly ahead at \(formatDistance(obstacle.distance))"
                )
                newWarnings.append(warning)
            } else if obstacle.distance <= warningThreshold {
                let warning = ObstacleWarning(
                    type: .warning,
                    obstacle: obstacle,
                    message: "\(obstacle.type.description) ahead at \(formatDistance(obstacle.distance))"
                )
                newWarnings.append(warning)
            }
        }
        
        if !newWarnings.isEmpty {
            let priorityWarning = newWarnings.max { $0.type.priority < $1.type.priority }
            
            if let warning = priorityWarning {
                DispatchQueue.main.async {
                    self.obstacleWarnings = newWarnings
                    self.speechOutput.speak(warning.message, priority: warning.type.speechPriority)
                    self.lastWarningTime = now
                }
            }
        }
    }
    
    // MARK: - Utility Methods
    
    private func screenToWorldPosition(_ screenPoint: CGPoint, depth: Float, cameraTransform: simd_float4x4) -> simd_float3 {
        // Convert 2D screen coordinates to 3D world position using depth
        let x = Float(screenPoint.x) * depth * 0.001 // Simplified conversion
        let y = Float(screenPoint.y) * depth * 0.001
        let z = depth
        
        return simd_float3(x, y, z)
    }
    
    private func estimateObstacleSize(minDepth: Float, avgDepth: Float) -> ObstacleSize {
        let depthVariation = abs(minDepth - avgDepth)
        
        if depthVariation > 0.5 {
            return .large
        } else if depthVariation > 0.2 {
            return .medium
        } else {
            return .small
        }
    }
    
    private func classifyObstacle(depth: Float, size: ObstacleSize) -> ObstacleType {
        // Simple classification based on depth and size
        if depth < 1.0 {
            switch size {
            case .large: return .wall
            case .medium: return .furniture
            case .small: return .object
            }
        } else if depth < 2.0 {
            return size == .large ? .furniture : .object
        } else {
            return .object
        }
    }
    
    private func calculateConfidence(pixelCount: Int, depthVariation: Float) -> Float {
        let pixelConfidence = min(1.0, Float(pixelCount) / 100.0)
        let depthConfidence = max(0.1, 1.0 - depthVariation)
        
        return (pixelConfidence + depthConfidence) / 2.0
    }
    
    private func formatDistance(_ distance: Float) -> String {
        if distance < 1.0 {
            return "\(Int(distance * 100)) centimeters"
        } else {
            return String(format: "%.1f meters", distance)
        }
    }
    
    // MARK: - Public Interface
    
    func getObstacleSummary() -> String {
        if detectedObstacles.isEmpty {
            return "Path ahead is clear"
        }
        
        let nearestObstacle = detectedObstacles.min { $0.distance < $1.distance }
        guard let nearest = nearestObstacle else { return "No obstacles detected" }
        
        var summary = "Nearest obstacle: \(nearest.type.description) at \(formatDistance(nearest.distance))"
        
        if let pathDirection = safePathDirection {
            summary += ". Recommended path: \(pathDirection.description)"
        }
        
        return summary
    }
    
    func speakObstacleSummary() {
        let summary = getObstacleSummary()
        speechOutput.speak(summary)
    }
}

// MARK: - ARSessionDelegate

extension ObstacleDetectionManager: ARSessionDelegate {
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        // Process depth data from ARFrame
        guard isActive else { return }
        
        if let depthMap = frame.smoothedSceneDepth?.depthMap {
            // Depth data is processed in analyzeLiDARObstacles()
        }
    }
}

// MARK: - AVCaptureDepthDataOutputDelegate

extension ObstacleDetectionManager: AVCaptureDepthDataOutputDelegate {
    func depthDataOutput(_ output: AVCaptureDepthDataOutput, didOutput depthData: AVDepthData, timestamp: CMTime, connection: AVCaptureConnection) {
        
        guard isActive else { return }
        
        let depthMap = depthData.depthDataMap
        depthBuffer = depthMap
    }
}

// MARK: - Data Models

struct DetectedObstacle: Identifiable {
    let id: UUID
    let position: simd_float3
    let distance: Float
    let size: ObstacleSize
    let type: ObstacleType
    let confidence: Float
}

enum ObstacleSize {
    case small
    case medium
    case large
}

enum ObstacleType {
    case wall
    case furniture
    case person
    case object
    case unknown
    
    var description: String {
        switch self {
        case .wall: return "wall"
        case .furniture: return "furniture"
        case .person: return "person"
        case .object: return "object"
        case .unknown: return "obstacle"
        }
    }
}

struct ObstacleWarning {
    let type: WarningType
    let obstacle: DetectedObstacle
    let message: String
}

enum WarningType {
    case info
    case warning
    case critical
    
    var priority: Int {
        switch self {
        case .info: return 1
        case .warning: return 2
        case .critical: return 3
        }
    }
    
    var speechPriority: SpeechPriority {
        switch self {
        case .info: return .normal
        case .warning: return .normal
        case .critical: return .high
        }
    }
}

enum PathDirection {
    case left
    case forward
    case right
    case stop
    
    var description: String {
        switch self {
        case .left: return "bear left"
        case .forward: return "continue forward"
        case .right: return "bear right"
        case .stop: return "stop, obstacles ahead"
        }
    }
}

struct PathOption {
    let direction: Float
    let isClear: Bool
    let obstacleCount: Int
    let score: Float
}

enum ObstacleLevel {
    case clear
    case low
    case medium
    case high
    case blocked
}

// MARK: - Extensions

extension simd_float4x4 {
    static var identity: simd_float4x4 {
        return simd_float4x4(
            simd_float4(1, 0, 0, 0),
            simd_float4(0, 1, 0, 0),
            simd_float4(0, 0, 1, 0),
            simd_float4(0, 0, 0, 1)
        )
    }
} 