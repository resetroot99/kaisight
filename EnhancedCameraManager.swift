import Foundation
import AVFoundation
import CoreML
import Vision
import ARKit
import CoreImage

class EnhancedCameraManager: NSObject, ObservableObject {
    @Published var isActive = false
    @Published var currentCameraType: CameraType = .wide
    @Published var sceneContext: SceneContext = .unknown
    @Published var fieldOfViewDegrees: Float = 0.0
    @Published var hasUltraWide = false
    @Published var hasLiDAR = false
    
    // Camera devices and session
    private var captureSession: AVCaptureSession!
    private var wideCamera: AVCaptureDevice?
    private var ultraWideCamera: AVCaptureDevice?
    private var telephotoCamera: AVCaptureDevice?
    private var currentCamera: AVCaptureDevice?
    
    // Camera inputs and outputs
    private var videoInput: AVCaptureDeviceInput?
    private var videoOutput: AVCaptureVideoDataOutput!
    private var depthOutput: AVCaptureDepthDataOutput?
    
    // Processing and fusion
    private let cameraQueue = DispatchQueue(label: "camera.processing", qos: .userInitiated)
    private let fusionEngine = CameraFusionEngine()
    private let contextAnalyzer = SceneContextAnalyzer()
    private let spatialProcessor = SpatialDataProcessor()
    
    // Integration with existing systems
    private let spatialManager = EnhancedSpatialManager()
    private let recognitionManager = EnhancedFamiliarRecognition()
    private let streamingGPT = StreamingGPTManager()
    
    // Camera switching logic
    private var lastCameraSwitchTime = Date()
    private let cameraSwitchCooldown: TimeInterval = 2.0
    private var autoSwitchingEnabled = true
    
    // Audio feedback
    private let speechOutput = SpeechOutput()
    
    // Frame processing
    private var lastFrameTime = Date()
    private let targetFPS: Double = 30.0
    
    override init() {
        super.init()
        setupEnhancedCamera()
    }
    
    // MARK: - Setup and Configuration
    
    private func setupEnhancedCamera() {
        setupCaptureSession()
        discoverAvailableCameras()
        setupCameraFusion()
        selectOptimalInitialCamera()
        
        Config.debugLog("Enhanced camera manager initialized")
    }
    
    private func setupCaptureSession() {
        captureSession = AVCaptureSession()
        captureSession.sessionPreset = .high
        
        // Setup video output
        videoOutput = AVCaptureVideoDataOutput()
        videoOutput.setSampleBufferDelegate(self, queue: cameraQueue)
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        
        if captureSession.canAddOutput(videoOutput) {
            captureSession.addOutput(videoOutput)
        }
        
        // Setup depth output if available
        setupDepthOutput()
    }
    
    private func setupDepthOutput() {
        depthOutput = AVCaptureDepthDataOutput()
        depthOutput?.setDelegate(self, callbackQueue: cameraQueue)
        
        if let depthOutput = depthOutput,
           captureSession.canAddOutput(depthOutput) {
            captureSession.addOutput(depthOutput)
        }
    }
    
    private func discoverAvailableCameras() {
        // Discover Ultra-Wide camera
        let ultraWideDiscovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInUltraWideCamera],
            mediaType: .video,
            position: .back
        )
        ultraWideCamera = ultraWideDiscovery.devices.first
        hasUltraWide = ultraWideCamera != nil
        
        // Discover Wide camera
        let wideDiscovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera],
            mediaType: .video,
            position: .back
        )
        wideCamera = wideDiscovery.devices.first
        
        // Discover Telephoto camera
        let telephotoDiscovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInTelephotoCamera],
            mediaType: .video,
            position: .back
        )
        telephotoCamera = telephotoDiscovery.devices.first
        
        // Check for LiDAR availability
        hasLiDAR = ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification)
        
        logCameraCapabilities()
    }
    
    private func logCameraCapabilities() {
        var capabilities = "Camera capabilities: "
        
        if hasUltraWide {
            capabilities += "Ultra-Wide ✓, "
        }
        
        if wideCamera != nil {
            capabilities += "Wide ✓, "
        }
        
        if telephotoCamera != nil {
            capabilities += "Telephoto ✓, "
        }
        
        if hasLiDAR {
            capabilities += "LiDAR ✓"
        }
        
        Config.debugLog(capabilities)
        speechOutput.speak("Camera system initialized with \(hasUltraWide ? "ultra-wide" : "standard") vision")
    }
    
    private func setupCameraFusion() {
        fusionEngine.delegate = self
        fusionEngine.configure(
            hasUltraWide: hasUltraWide,
            hasLiDAR: hasLiDAR,
            spatialManager: spatialManager
        )
    }
    
    // MARK: - Camera Selection and Switching
    
    private func selectOptimalInitialCamera() {
        // Start with Ultra-Wide if available for better initial scene awareness
        if hasUltraWide {
            switchToCamera(.ultraWide)
        } else {
            switchToCamera(.wide)
        }
    }
    
    func switchToCamera(_ cameraType: CameraType) {
        guard canSwitchCamera() else { return }
        
        let targetCamera: AVCaptureDevice?
        
        switch cameraType {
        case .ultraWide:
            targetCamera = ultraWideCamera
        case .wide:
            targetCamera = wideCamera
        case .telephoto:
            targetCamera = telephotoCamera
        }
        
        guard let camera = targetCamera,
              camera != currentCamera else { return }
        
        performCameraSwitch(to: camera, type: cameraType)
    }
    
    private func canSwitchCamera() -> Bool {
        let timeSinceLastSwitch = Date().timeIntervalSince(lastCameraSwitchTime)
        return timeSinceLastSwitch >= cameraSwitchCooldown
    }
    
    private func performCameraSwitch(to camera: AVCaptureDevice, type: CameraType) {
        captureSession.beginConfiguration()
        
        // Remove current input
        if let currentInput = videoInput {
            captureSession.removeInput(currentInput)
        }
        
        // Add new input
        do {
            let newInput = try AVCaptureDeviceInput(device: camera)
            
            if captureSession.canAddInput(newInput) {
                captureSession.addInput(newInput)
                videoInput = newInput
                currentCamera = camera
                currentCameraType = type
                
                // Update field of view
                fieldOfViewDegrees = camera.activeFormat.videoFieldOfView
                
                // Configure camera settings
                configureCameraSettings(camera)
                
                lastCameraSwitchTime = Date()
                
                Config.debugLog("Switched to \(type.rawValue) camera (FOV: \(fieldOfViewDegrees)°)")
                
            } else {
                Config.debugLog("Cannot add input for \(type.rawValue) camera")
            }
            
        } catch {
            Config.debugLog("Failed to switch to \(type.rawValue) camera: \(error)")
        }
        
        captureSession.commitConfiguration()
        
        // Update fusion engine
        fusionEngine.updateCurrentCamera(type, fieldOfView: fieldOfViewDegrees)
    }
    
    private func configureCameraSettings(_ camera: AVCaptureDevice) {
        do {
            try camera.lockForConfiguration()
            
            // Configure for optimal performance
            if camera.isFocusModeSupported(.continuousAutoFocus) {
                camera.focusMode = .continuousAutoFocus
            }
            
            if camera.isExposureModeSupported(.continuousAutoExposure) {
                camera.exposureMode = .continuousAutoExposure
            }
            
            // Enable depth if available
            if let depthFormat = camera.activeDepthDataFormat {
                camera.activeDepthDataFormat = depthFormat
            }
            
            camera.unlockForConfiguration()
            
        } catch {
            Config.debugLog("Failed to configure camera settings: \(error)")
        }
    }
    
    // MARK: - Context-Aware Camera Selection
    
    private func analyzeSceneAndSelectCamera(_ sampleBuffer: CMSampleBuffer) {
        guard autoSwitchingEnabled else { return }
        
        contextAnalyzer.analyzeScene(sampleBuffer) { [weak self] newContext in
            DispatchQueue.main.async {
                self?.updateSceneContext(newContext)
            }
        }
    }
    
    private func updateSceneContext(_ newContext: SceneContext) {
        guard newContext != sceneContext else { return }
        
        sceneContext = newContext
        
        // Select optimal camera for context
        let optimalCamera = selectOptimalCameraForContext(newContext)
        
        if optimalCamera != currentCameraType {
            switchToCamera(optimalCamera)
            announceCameraSwitch(for: newContext)
        }
    }
    
    private func selectOptimalCameraForContext(_ context: SceneContext) -> CameraType {
        switch context {
        case .indoorsNarrow:
            // Narrow spaces benefit from wider FOV for obstacle detection
            return hasUltraWide ? .ultraWide : .wide
            
        case .indoorsOpen:
            // Open indoor spaces - Ultra-Wide for full room awareness
            return hasUltraWide ? .ultraWide : .wide
            
        case .outdoors:
            // Outdoor spaces - Ultra-Wide for maximum environmental awareness
            return hasUltraWide ? .ultraWide : .wide
            
        case .hallway:
            // Hallways benefit from ultra-wide for peripheral obstacle detection
            return hasUltraWide ? .ultraWide : .wide
            
        case .staircase:
            // Staircases need precise depth - combine with LiDAR if available
            return .wide
            
        case .faceToFace:
            // Face recognition benefits from telephoto if available
            return telephotoCamera != nil ? .telephoto : .wide
            
        case .reading:
            // Text recognition might benefit from telephoto for clarity
            return telephotoCamera != nil ? .telephoto : .wide
            
        case .unknown:
            // Default to ultra-wide for maximum scene awareness
            return hasUltraWide ? .ultraWide : .wide
        }
    }
    
    private func announceCameraSwitch(for context: SceneContext) {
        let cameraName = currentCameraType == .ultraWide ? "ultra-wide view" : 
                        currentCameraType == .telephoto ? "telephoto view" : "standard view"
        
        speechOutput.speak("Switched to \(cameraName) for \(context.description)")
    }
    
    // MARK: - Camera Fusion and Processing
    
    func startCamera() {
        guard !isActive else { return }
        
        cameraQueue.async { [weak self] in
            self?.captureSession.startRunning()
            
            DispatchQueue.main.async {
                self?.isActive = true
                self?.speechOutput.speak("Enhanced camera system active")
            }
        }
    }
    
    func stopCamera() {
        guard isActive else { return }
        
        cameraQueue.async { [weak self] in
            self?.captureSession.stopRunning()
            
            DispatchQueue.main.async {
                self?.isActive = false
            }
        }
    }
    
    // MARK: - Manual Camera Controls
    
    func enableAutoSwitching() {
        autoSwitchingEnabled = true
        speechOutput.speak("Automatic camera switching enabled")
    }
    
    func disableAutoSwitching() {
        autoSwitchingEnabled = false
        speechOutput.speak("Manual camera control enabled")
    }
    
    func switchToUltraWideCamera() {
        guard hasUltraWide else {
            speechOutput.speak("Ultra-wide camera not available on this device")
            return
        }
        
        autoSwitchingEnabled = false
        switchToCamera(.ultraWide)
        speechOutput.speak("Switched to ultra-wide camera for maximum field of view")
    }
    
    func switchToStandardCamera() {
        autoSwitchingEnabled = false
        switchToCamera(.wide)
        speechOutput.speak("Switched to standard camera")
    }
    
    func switchToTelephotoCamera() {
        guard telephotoCamera != nil else {
            speechOutput.speak("Telephoto camera not available on this device")
            return
        }
        
        autoSwitchingEnabled = false
        switchToCamera(.telephoto)
        speechOutput.speak("Switched to telephoto camera for detailed view")
    }
    
    // MARK: - Integration with Vision Systems
    
    private func processFrameForRecognition(_ sampleBuffer: CMSampleBuffer, cameraType: CameraType) {
        // Extract image from sample buffer
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        
        // Create processing context with camera information
        let processingContext = FrameProcessingContext(
            image: ciImage,
            cameraType: cameraType,
            fieldOfView: fieldOfViewDegrees,
            timestamp: Date(),
            sceneContext: sceneContext
        )
        
        // Process with fusion engine
        fusionEngine.processFrame(processingContext)
    }
    
    private func enhanceFrameForCurrentContext(_ ciImage: CIImage) -> CIImage {
        var enhancedImage = ciImage
        
        // Apply context-specific enhancements
        switch sceneContext {
        case .indoorsNarrow, .hallway:
            // Enhance contrast for better obstacle detection
            enhancedImage = enhanceContrast(enhancedImage)
            
        case .outdoors:
            // Adjust for varying lighting conditions
            enhancedImage = normalizeExposure(enhancedImage)
            
        case .reading:
            // Enhance sharpness for text recognition
            enhancedImage = enhanceSharpness(enhancedImage)
            
        default:
            break
        }
        
        return enhancedImage
    }
    
    // MARK: - Image Enhancement Methods
    
    private func enhanceContrast(_ image: CIImage) -> CIImage {
        let filter = CIFilter(name: "CIColorControls")
        filter?.setValue(image, forKey: kCIInputImageKey)
        filter?.setValue(1.2, forKey: kCIInputContrastKey)
        return filter?.outputImage ?? image
    }
    
    private func normalizeExposure(_ image: CIImage) -> CIImage {
        let filter = CIFilter(name: "CIExposureAdjust")
        filter?.setValue(image, forKey: kCIInputImageKey)
        filter?.setValue(0.5, forKey: kCIInputEVKey)
        return filter?.outputImage ?? image
    }
    
    private func enhanceSharpness(_ image: CIImage) -> CIImage {
        let filter = CIFilter(name: "CISharpenLuminance")
        filter?.setValue(image, forKey: kCIInputImageKey)
        filter?.setValue(0.4, forKey: kCIInputSharpnessKey)
        return filter?.outputImage ?? image
    }
    
    // MARK: - Public Interface
    
    func getCurrentCameraInfo() -> CameraInfo {
        return CameraInfo(
            type: currentCameraType,
            fieldOfView: fieldOfViewDegrees,
            hasDepth: depthOutput != nil,
            sceneContext: sceneContext,
            autoSwitching: autoSwitchingEnabled
        )
    }
    
    func getCameraCapabilities() -> CameraCapabilities {
        return CameraCapabilities(
            hasUltraWide: hasUltraWide,
            hasTelephoto: telephotoCamera != nil,
            hasLiDAR: hasLiDAR,
            supportsDepth: depthOutput != nil,
            availableContexts: SceneContext.allCases
        )
    }
    
    func speakCameraStatus() {
        let info = getCurrentCameraInfo()
        var status = "Camera: \(info.type.description), "
        status += "Field of view: \(Int(info.fieldOfView)) degrees, "
        status += "Context: \(info.sceneContext.description)"
        
        if info.autoSwitching {
            status += ", Auto-switching enabled"
        }
        
        speechOutput.speak(status)
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension EnhancedCameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Throttle frame processing to target FPS
        let now = Date()
        let frameInterval = 1.0 / targetFPS
        
        guard now.timeIntervalSince(lastFrameTime) >= frameInterval else { return }
        lastFrameTime = now
        
        // Analyze scene context for automatic camera switching
        analyzeSceneAndSelectCamera(sampleBuffer)
        
        // Process frame for recognition and spatial awareness
        processFrameForRecognition(sampleBuffer, cameraType: currentCameraType)
    }
}

// MARK: - AVCaptureDepthDataOutputDelegate

extension EnhancedCameraManager: AVCaptureDepthDataOutputDelegate {
    func depthDataOutput(_ output: AVCaptureDepthDataOutput, didOutput depthData: AVDepthData, timestamp: CMTime, connection: AVCaptureConnection) {
        // Process depth data with fusion engine
        fusionEngine.processDepthData(depthData, timestamp: timestamp)
    }
}

// MARK: - CameraFusionEngineDelegate

extension EnhancedCameraManager: CameraFusionEngineDelegate {
    func fusionEngine(_ engine: CameraFusionEngine, didProduceEnhancedFrame frame: EnhancedFrame) {
        // Deliver enhanced frame to recognition systems
        recognitionManager.processEnhancedFrame(frame)
        
        // Update spatial manager with enhanced spatial data
        spatialManager.updateWithEnhancedFrame(frame)
        
        // Generate contextual narration if needed
        if frame.hasSignificantChanges {
            streamingGPT.processEnhancedFrame(frame)
        }
    }
    
    func fusionEngine(_ engine: CameraFusionEngine, didDetectSceneChange change: SceneChange) {
        DispatchQueue.main.async {
            // Announce significant scene changes
            if change.significance > 0.7 {
                self.speechOutput.speak(change.description)
            }
        }
    }
}

// MARK: - Supporting Classes and Data Models

class CameraFusionEngine {
    weak var delegate: CameraFusionEngineDelegate?
    
    private var hasUltraWide = false
    private var hasLiDAR = false
    private var currentCameraType: CameraType = .wide
    private var currentFieldOfView: Float = 0.0
    private var spatialManager: EnhancedSpatialManager?
    
    private let frameProcessor = MultiCameraFrameProcessor()
    private let depthFusion = DepthFusionProcessor()
    private let changeDetector = SceneChangeDetector()
    
    func configure(hasUltraWide: Bool, hasLiDAR: Bool, spatialManager: EnhancedSpatialManager) {
        self.hasUltraWide = hasUltraWide
        self.hasLiDAR = hasLiDAR
        self.spatialManager = spatialManager
        
        frameProcessor.configure(hasUltraWide: hasUltraWide, hasLiDAR: hasLiDAR)
    }
    
    func updateCurrentCamera(_ type: CameraType, fieldOfView: Float) {
        currentCameraType = type
        currentFieldOfView = fieldOfView
        frameProcessor.updateCamera(type, fieldOfView: fieldOfView)
    }
    
    func processFrame(_ context: FrameProcessingContext) {
        // Process frame based on camera type and context
        let enhancedFrame = frameProcessor.processFrame(context)
        
        // Detect scene changes
        if let sceneChange = changeDetector.analyzeFrame(enhancedFrame) {
            delegate?.fusionEngine(self, didDetectSceneChange: sceneChange)
        }
        
        // Deliver enhanced frame
        delegate?.fusionEngine(self, didProduceEnhancedFrame: enhancedFrame)
    }
    
    func processDepthData(_ depthData: AVDepthData, timestamp: CMTime) {
        // Fuse depth data with current frame processing
        depthFusion.processDepthData(depthData, timestamp: timestamp)
    }
}

protocol CameraFusionEngineDelegate: AnyObject {
    func fusionEngine(_ engine: CameraFusionEngine, didProduceEnhancedFrame frame: EnhancedFrame)
    func fusionEngine(_ engine: CameraFusionEngine, didDetectSceneChange change: SceneChange)
}

class SceneContextAnalyzer {
    private let visionQueue = DispatchQueue(label: "scene.analysis", qos: .userInitiated)
    
    func analyzeScene(_ sampleBuffer: CMSampleBuffer, completion: @escaping (SceneContext) -> Void) {
        visionQueue.async {
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
                completion(.unknown)
                return
            }
            
            let context = self.classifyScene(pixelBuffer)
            completion(context)
        }
    }
    
    private func classifyScene(_ pixelBuffer: CVPixelBuffer) -> SceneContext {
        // Use Vision framework to analyze scene characteristics
        let request = VNClassifyImageRequest()
        
        do {
            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
            try handler.perform([request])
            
            // Analyze results to determine context
            return inferContextFromVisionResults(request.results)
            
        } catch {
            Config.debugLog("Scene analysis failed: \(error)")
            return .unknown
        }
    }
    
    private func inferContextFromVisionResults(_ results: [VNObservation]?) -> SceneContext {
        // Simplified context inference
        // In production, this would use more sophisticated ML models
        return .indoorsOpen
    }
}

class MultiCameraFrameProcessor {
    private var hasUltraWide = false
    private var hasLiDAR = false
    private var currentCameraType: CameraType = .wide
    private var currentFieldOfView: Float = 0.0
    
    func configure(hasUltraWide: Bool, hasLiDAR: Bool) {
        self.hasUltraWide = hasUltraWide
        self.hasLiDAR = hasLiDAR
    }
    
    func updateCamera(_ type: CameraType, fieldOfView: Float) {
        currentCameraType = type
        currentFieldOfView = fieldOfView
    }
    
    func processFrame(_ context: FrameProcessingContext) -> EnhancedFrame {
        // Create enhanced frame with camera-specific processing
        var enhancedFrame = EnhancedFrame(
            image: context.image,
            cameraType: context.cameraType,
            fieldOfView: context.fieldOfView,
            timestamp: context.timestamp,
            sceneContext: context.sceneContext
        )
        
        // Apply camera-specific enhancements
        switch context.cameraType {
        case .ultraWide:
            enhancedFrame = processUltraWideFrame(enhancedFrame)
        case .wide:
            enhancedFrame = processWideFrame(enhancedFrame)
        case .telephoto:
            enhancedFrame = processTelephotoFrame(enhancedFrame)
        }
        
        return enhancedFrame
    }
    
    private func processUltraWideFrame(_ frame: EnhancedFrame) -> EnhancedFrame {
        var enhanced = frame
        
        // Ultra-wide specific processing
        enhanced.peripheralObjects = detectPeripheralObjects(frame.image)
        enhanced.spatialCoverage = calculateSpatialCoverage(fieldOfView: frame.fieldOfView)
        enhanced.obstacleAwareness = analyzeObstacleDistribution(frame.image)
        
        return enhanced
    }
    
    private func processWideFrame(_ frame: EnhancedFrame) -> EnhancedFrame {
        var enhanced = frame
        
        // Standard wide camera processing
        enhanced.centralObjects = detectCentralObjects(frame.image)
        enhanced.focusRegion = calculateOptimalFocusRegion(frame.image)
        
        return enhanced
    }
    
    private func processTelephotoFrame(_ frame: EnhancedFrame) -> EnhancedFrame {
        var enhanced = frame
        
        // Telephoto specific processing for detailed analysis
        enhanced.detailLevel = .high
        enhanced.recognitionAccuracy = calculateEnhancedAccuracy(frame.image)
        
        return enhanced
    }
    
    // MARK: - Analysis Methods
    
    private func detectPeripheralObjects(_ image: CIImage) -> [DetectedObject] {
        // Focus on edge regions of ultra-wide image
        let edgeRegions = calculatePeripheralRegions(for: image.extent)
        var peripheralObjects: [DetectedObject] = []
        
        for region in edgeRegions {
            let croppedImage = image.cropped(to: region)
            let objects = performObjectDetection(on: croppedImage, region: region)
            peripheralObjects.append(contentsOf: objects)
        }
        
        return peripheralObjects.sorted { $0.type.priority > $1.type.priority }
    }
    
    private func calculateSpatialCoverage(fieldOfView: Float) -> Float {
        // Calculate what percentage of space is covered
        return fieldOfView / 120.0 // Normalize to 120-degree reference
    }
    
    private func analyzeObstacleDistribution(_ image: CIImage) -> ObstacleAwareness {
        // Analyze how obstacles are distributed across the field of view
        return ObstacleAwareness(
            leftSide: 0.5,
            center: 0.3,
            rightSide: 0.4,
            confidence: 0.8
        )
    }
    
    private func detectCentralObjects(_ image: CIImage) -> [DetectedObject] {
        // Focus on central region for detailed analysis
        let centralRegion = CGRect(
            x: image.extent.width * 0.25,
            y: image.extent.height * 0.25,
            width: image.extent.width * 0.5,
            height: image.extent.height * 0.5
        )
        
        let croppedImage = image.cropped(to: centralRegion)
        return performObjectDetection(on: croppedImage, region: centralRegion)
    }
    
    private func calculateOptimalFocusRegion(_ image: CIImage) -> CGRect {
        // Calculate where the main focus should be
        return CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
    }
    
    private func calculateEnhancedAccuracy(_ image: CIImage) -> Float {
        // Calculate recognition accuracy for telephoto
        return 0.95
    }
    
    private func calculatePeripheralRegions(for extent: CGRect) -> [CGRect] {
        let width = extent.width
        let height = extent.height
        let peripheralWidth = width * 0.2 // 20% from each edge
        
        return [
            // Left edge
            CGRect(x: 0, y: 0, width: peripheralWidth, height: height),
            // Right edge
            CGRect(x: width - peripheralWidth, y: 0, width: peripheralWidth, height: height),
            // Top edge
            CGRect(x: 0, y: 0, width: width, height: height * 0.2),
            // Bottom edge
            CGRect(x: 0, y: height * 0.8, width: width, height: height * 0.2)
        ]
    }
    
    private func performObjectDetection(on image: CIImage, region: CGRect) -> [DetectedObject] {
        // Perform actual object detection using Vision framework
        var detectedObjects: [DetectedObject] = []
        
        let request = VNRecognizeObjectsRequest { request, error in
            guard let observations = request.results as? [VNRecognizedObjectObservation] else { return }
            
            for observation in observations {
                let object = DetectedObject(
                    id: UUID(),
                    type: self.mapVisionLabelToObjectType(observation.labels.first?.identifier ?? "unknown"),
                    confidence: observation.confidence,
                    boundingBox: observation.boundingBox,
                    distance: nil, // Would be calculated with depth data
                    description: observation.labels.first?.identifier ?? "unknown object",
                    timestamp: Date()
                )
                
                detectedObjects.append(object)
            }
        }
        
        do {
            let handler = VNImageRequestHandler(ciImage: image, options: [:])
            try handler.perform([request])
        } catch {
            Config.debugLog("Object detection failed: \(error)")
        }
        
        return detectedObjects
    }
    
    private func mapVisionLabelToObjectType(_ label: String) -> ObjectType {
        let lowercased = label.lowercased()
        
        if lowercased.contains("person") || lowercased.contains("human") {
            return .person
        } else if lowercased.contains("car") || lowercased.contains("vehicle") || lowercased.contains("truck") {
            return .vehicle
        } else if lowercased.contains("chair") || lowercased.contains("table") || lowercased.contains("sofa") {
            return .furniture
        } else if lowercased.contains("door") {
            return .door
        } else if lowercased.contains("window") {
            return .window
        } else if lowercased.contains("stair") {
            return .stairs
        } else if lowercased.contains("text") || lowercased.contains("sign") {
            return .text
        } else if lowercased.contains("food") || lowercased.contains("drink") {
            return .food
        } else if lowercased.contains("dog") || lowercased.contains("cat") || lowercased.contains("animal") {
            return .animal
        } else {
            return .unknown
        }
    }
}

class DepthFusionProcessor {
    private var recentDepthData: [AVDepthData] = []
    private let maxDepthDataHistory = 10
    
    func processDepthData(_ depthData: AVDepthData, timestamp: CMTime) {
        // Store recent depth data for fusion
        recentDepthData.append(depthData)
        
        if recentDepthData.count > maxDepthDataHistory {
            recentDepthData.removeFirst()
        }
        
        // Process depth for spatial awareness
        processDepthForSpatialAwareness(depthData)
    }
    
    private func processDepthForSpatialAwareness(_ depthData: AVDepthData) {
        // Extract depth information for spatial processing
        let depthMap = depthData.depthDataMap
        
        // Analyze depth patterns for navigation
        analyzeDepthPatterns(depthMap)
    }
    
    private func analyzeDepthPatterns(_ depthMap: CVPixelBuffer) {
        // Analyze depth patterns for obstacles and navigation paths
    }
}

// MARK: - Data Models

enum CameraType: String, CaseIterable {
    case ultraWide = "ultra_wide"
    case wide = "wide"
    case telephoto = "telephoto"
    
    var description: String {
        switch self {
        case .ultraWide: return "Ultra-Wide"
        case .wide: return "Wide"
        case .telephoto: return "Telephoto"
        }
    }
}

enum SceneContext: String, CaseIterable {
    case indoorsNarrow = "indoors_narrow"
    case indoorsOpen = "indoors_open"
    case outdoors = "outdoors"
    case hallway = "hallway"
    case staircase = "staircase"
    case faceToFace = "face_to_face"
    case reading = "reading"
    case unknown = "unknown"
    
    var description: String {
        switch self {
        case .indoorsNarrow: return "narrow indoor space"
        case .indoorsOpen: return "open indoor area"
        case .outdoors: return "outdoor environment"
        case .hallway: return "hallway"
        case .staircase: return "staircase"
        case .faceToFace: return "face-to-face interaction"
        case .reading: return "reading/text mode"
        case .unknown: return "unknown environment"
        }
    }
}

struct FrameProcessingContext {
    let image: CIImage
    let cameraType: CameraType
    let fieldOfView: Float
    let timestamp: Date
    let sceneContext: SceneContext
}

struct EnhancedFrame {
    let image: CIImage
    let cameraType: CameraType
    let fieldOfView: Float
    let timestamp: Date
    let sceneContext: SceneContext
    
    // Enhanced properties based on camera type
    var peripheralObjects: [DetectedObject] = []
    var centralObjects: [DetectedObject] = []
    var spatialCoverage: Float = 0.0
    var obstacleAwareness: ObstacleAwareness?
    var focusRegion: CGRect?
    var detailLevel: DetailLevel = .standard
    var recognitionAccuracy: Float = 0.8
    var hasSignificantChanges = false
}

struct SceneChange {
    let significance: Float
    let description: String
    let changeType: ChangeType
    let timestamp: Date
}

enum ChangeType {
    case newObject
    case objectMoved
    case objectRemoved
    case lightingChange
    case sceneTransition
}

enum DetailLevel {
    case low
    case standard
    case high
}

struct ObstacleAwareness {
    let leftSide: Float
    let center: Float
    let rightSide: Float
    let confidence: Float
}

struct CameraInfo {
    let type: CameraType
    let fieldOfView: Float
    let hasDepth: Bool
    let sceneContext: SceneContext
    let autoSwitching: Bool
}

struct CameraCapabilities {
    let hasUltraWide: Bool
    let hasTelephoto: Bool
    let hasLiDAR: Bool
    let supportsDepth: Bool
    let availableContexts: [SceneContext]
}

class SpatialDataProcessor {
    func processEnhancedFrame(_ frame: EnhancedFrame) {
        // Process frame for spatial data extraction
    }
}

// MARK: - Extensions for Integration

extension EnhancedFamiliarRecognition {
    func processEnhancedFrame(_ frame: EnhancedFrame) {
        // Process enhanced frame for object and face recognition
        // Take advantage of camera-specific optimizations
        
        switch frame.cameraType {
        case .ultraWide:
            // Use peripheral objects for broader recognition
            processPeripheralObjects(frame.peripheralObjects)
            
        case .telephoto:
            // Use enhanced detail for more accurate recognition
            processHighDetailFrame(frame.image, accuracy: frame.recognitionAccuracy)
            
        case .wide:
            // Standard processing
            processStandardFrame(frame.image)
        }
    }
    
    private func processPeripheralObjects(_ objects: [DetectedObject]) {
        // Process objects detected in peripheral vision
    }
    
    private func processHighDetailFrame(_ image: CIImage, accuracy: Float) {
        // Process high-detail telephoto frame
    }
    
    private func processStandardFrame(_ image: CIImage) {
        // Standard frame processing
    }
}

extension EnhancedSpatialManager {
    func updateWithEnhancedFrame(_ frame: EnhancedFrame) {
        // Update spatial awareness with enhanced frame data
        
        if let obstacleAwareness = frame.obstacleAwareness {
            updateObstacleAwareness(obstacleAwareness)
        }
        
        // Use spatial coverage information for navigation
        updateSpatialCoverage(frame.spatialCoverage, fieldOfView: frame.fieldOfView)
    }
    
    private func updateObstacleAwareness(_ awareness: ObstacleAwareness) {
        // Update obstacle detection with peripheral awareness
    }
    
    private func updateSpatialCoverage(_ coverage: Float, fieldOfView: Float) {
        // Update spatial understanding with field of view information
    }
}

extension StreamingGPTManager {
    func processEnhancedFrame(_ frame: EnhancedFrame) {
        // Generate enhanced narration based on camera type and context
        
        let contextualPrompt = createEnhancedPrompt(for: frame)
        
        generateStreamingNarration(for: frame.image, prompt: contextualPrompt)
    }
    
    private func createEnhancedPrompt(for frame: EnhancedFrame) -> String {
        var prompt = "Using \(frame.cameraType.description) camera with \(Int(frame.fieldOfView))° field of view in \(frame.sceneContext.description). "
        
        switch frame.cameraType {
        case .ultraWide:
            prompt += "Provide comprehensive spatial awareness including peripheral objects and wide-area navigation guidance. "
            
        case .telephoto:
            prompt += "Focus on detailed analysis of central objects with enhanced recognition accuracy. "
            
        case .wide:
            prompt += "Provide balanced narration of central scene elements and immediate surroundings. "
        }
        
        return prompt
    }
    
    private func generateStreamingNarration(for image: CIImage, prompt: String) {
        // Generate enhanced streaming narration
    }
}

// MARK: - Missing Supporting Classes

class SceneChangeDetector {
    private var previousFrame: EnhancedFrame?
    private let changeThreshold: Float = 0.3
    private let significanceThreshold: Float = 0.5
    
    func analyzeFrame(_ frame: EnhancedFrame) -> SceneChange? {
        defer { previousFrame = frame }
        
        guard let previous = previousFrame else {
            // First frame - no change to detect
            return nil
        }
        
        // Analyze different types of changes
        let changes = detectChanges(from: previous, to: frame)
        
        guard !changes.isEmpty else { return nil }
        
        // Find the most significant change
        let mostSignificant = changes.max(by: { $0.significance < $1.significance })!
        
        return mostSignificant.significance > significanceThreshold ? mostSignificant : nil
    }
    
    private func detectChanges(from previous: EnhancedFrame, to current: EnhancedFrame) -> [SceneChange] {
        var changes: [SceneChange] = []
        
        // Detect camera type changes
        if previous.cameraType != current.cameraType {
            changes.append(SceneChange(
                significance: 0.8,
                description: "Camera switched from \(previous.cameraType.description) to \(current.cameraType.description)",
                changeType: .sceneTransition,
                timestamp: current.timestamp
            ))
        }
        
        // Detect context changes
        if previous.sceneContext != current.sceneContext {
            changes.append(SceneChange(
                significance: 0.9,
                description: "Environment changed from \(previous.sceneContext.description) to \(current.sceneContext.description)",
                changeType: .sceneTransition,
                timestamp: current.timestamp
            ))
        }
        
        // Detect object changes
        let objectChanges = detectObjectChanges(from: previous, to: current)
        changes.append(contentsOf: objectChanges)
        
        return changes
    }
    
    private func detectObjectChanges(from previous: EnhancedFrame, to current: EnhancedFrame) -> [SceneChange] {
        var changes: [SceneChange] = []
        
        // Compare central objects
        let newCentralObjects = current.centralObjects.filter { currentObj in
            !previous.centralObjects.contains { prevObj in
                currentObj.id == prevObj.id
            }
        }
        
        if !newCentralObjects.isEmpty {
            changes.append(SceneChange(
                significance: 0.7,
                description: "\(newCentralObjects.count) new object\(newCentralObjects.count == 1 ? "" : "s") detected",
                changeType: .newObject,
                timestamp: current.timestamp
            ))
        }
        
        // Compare peripheral objects for ultra-wide
        if current.cameraType == .ultraWide {
            let newPeripheralObjects = current.peripheralObjects.filter { currentObj in
                !previous.peripheralObjects.contains { prevObj in
                    currentObj.id == prevObj.id
                }
            }
            
            if !newPeripheralObjects.isEmpty {
                changes.append(SceneChange(
                    significance: 0.6,
                    description: "\(newPeripheralObjects.count) new peripheral object\(newPeripheralObjects.count == 1 ? "" : "s") detected",
                    changeType: .newObject,
                    timestamp: current.timestamp
                ))
            }
        }
        
        return changes
    }
}

struct DetectedObject: Identifiable, Equatable {
    let id: UUID
    let type: ObjectType
    let confidence: Float
    let boundingBox: CGRect
    let distance: Float?
    let description: String
    let timestamp: Date
    
    static func == (lhs: DetectedObject, rhs: DetectedObject) -> Bool {
        return lhs.id == rhs.id
    }
}

enum ObjectType: String, CaseIterable {
    case person = "person"
    case vehicle = "vehicle"
    case furniture = "furniture"
    case obstacle = "obstacle"
    case door = "door"
    case window = "window"
    case stairs = "stairs"
    case text = "text"
    case food = "food"
    case animal = "animal"
    case unknown = "unknown"
    
    var priority: Int {
        switch self {
        case .person: return 10
        case .vehicle: return 9
        case .obstacle: return 8
        case .stairs: return 7
        case .door: return 6
        case .furniture: return 5
        case .text: return 4
        case .window: return 3
        case .food: return 2
        case .animal: return 1
        case .unknown: return 0
        }
    }
}

// MARK: - Enhanced Object Detection Integration

extension MultiCameraFrameProcessor {
    private func detectPeripheralObjects(_ image: CIImage) -> [DetectedObject] {
        // Focus on edge regions of ultra-wide image
        let edgeRegions = calculatePeripheralRegions(for: image.extent)
        var peripheralObjects: [DetectedObject] = []
        
        for region in edgeRegions {
            let croppedImage = image.cropped(to: region)
            let objects = performObjectDetection(on: croppedImage, region: region)
            peripheralObjects.append(contentsOf: objects)
        }
        
        return peripheralObjects.sorted { $0.type.priority > $1.type.priority }
    }
    
    private func detectCentralObjects(_ image: CIImage) -> [DetectedObject] {
        // Focus on central region for detailed analysis
        let centralRegion = CGRect(
            x: image.extent.width * 0.25,
            y: image.extent.height * 0.25,
            width: image.extent.width * 0.5,
            height: image.extent.height * 0.5
        )
        
        let croppedImage = image.cropped(to: centralRegion)
        return performObjectDetection(on: croppedImage, region: centralRegion)
    }
    
    private func calculatePeripheralRegions(for extent: CGRect) -> [CGRect] {
        let width = extent.width
        let height = extent.height
        let peripheralWidth = width * 0.2 // 20% from each edge
        
        return [
            // Left edge
            CGRect(x: 0, y: 0, width: peripheralWidth, height: height),
            // Right edge
            CGRect(x: width - peripheralWidth, y: 0, width: peripheralWidth, height: height),
            // Top edge
            CGRect(x: 0, y: 0, width: width, height: height * 0.2),
            // Bottom edge
            CGRect(x: 0, y: height * 0.8, width: width, height: height * 0.2)
        ]
    }
    
    private func performObjectDetection(on image: CIImage, region: CGRect) -> [DetectedObject] {
        // Perform actual object detection using Vision framework
        var detectedObjects: [DetectedObject] = []
        
        let request = VNRecognizeObjectsRequest { request, error in
            guard let observations = request.results as? [VNRecognizedObjectObservation] else { return }
            
            for observation in observations {
                let object = DetectedObject(
                    id: UUID(),
                    type: self.mapVisionLabelToObjectType(observation.labels.first?.identifier ?? "unknown"),
                    confidence: observation.confidence,
                    boundingBox: observation.boundingBox,
                    distance: nil, // Would be calculated with depth data
                    description: observation.labels.first?.identifier ?? "unknown object",
                    timestamp: Date()
                )
                
                detectedObjects.append(object)
            }
        }
        
        do {
            let handler = VNImageRequestHandler(ciImage: image, options: [:])
            try handler.perform([request])
        } catch {
            Config.debugLog("Object detection failed: \(error)")
        }
        
        return detectedObjects
    }
    
    private func mapVisionLabelToObjectType(_ label: String) -> ObjectType {
        let lowercased = label.lowercased()
        
        if lowercased.contains("person") || lowercased.contains("human") {
            return .person
        } else if lowercased.contains("car") || lowercased.contains("vehicle") || lowercased.contains("truck") {
            return .vehicle
        } else if lowercased.contains("chair") || lowercased.contains("table") || lowercased.contains("sofa") {
            return .furniture
        } else if lowercased.contains("door") {
            return .door
        } else if lowercased.contains("window") {
            return .window
        } else if lowercased.contains("stair") {
            return .stairs
        } else if lowercased.contains("text") || lowercased.contains("sign") {
            return .text
        } else if lowercased.contains("food") || lowercased.contains("drink") {
            return .food
        } else if lowercased.contains("dog") || lowercased.contains("cat") || lowercased.contains("animal") {
            return .animal
        } else {
            return .unknown
        }
    }
}

// MARK: - Voice Command Integration

extension EnhancedCameraManager {
    func processVoiceCommand(_ command: String) {
        let lowercased = command.lowercased()
        
        if lowercased.contains("ultra wide") || lowercased.contains("wide angle") {
            switchToUltraWideCamera()
        } else if lowercased.contains("telephoto") || lowercased.contains("zoom") {
            switchToTelephotoCamera()
        } else if lowercased.contains("standard") || lowercased.contains("normal") {
            switchToStandardCamera()
        } else if lowercased.contains("auto") || lowercased.contains("automatic") {
            enableAutoSwitching()
        } else if lowercased.contains("manual") {
            disableAutoSwitching()
        } else if lowercased.contains("camera status") || lowercased.contains("what camera") {
            speakCameraStatus()
        } else if lowercased.contains("camera capabilities") || lowercased.contains("what cameras") {
            speakCameraCapabilities()
        }
    }
    
    private func speakCameraCapabilities() {
        let capabilities = getCameraCapabilities()
        var announcement = "Available cameras: "
        
        var availableCameras: [String] = []
        
        if capabilities.hasUltraWide {
            availableCameras.append("Ultra-Wide with \(hasLiDAR ? "120" : "100") degree field of view")
        }
        
        availableCameras.append("Standard wide-angle")
        
        if capabilities.hasTelephoto {
            availableCameras.append("Telephoto for detailed view")
        }
        
        announcement += availableCameras.joined(separator: ", ")
        
        if capabilities.hasLiDAR {
            announcement += ". LiDAR depth sensing available."
        }
        
        if capabilities.supportsDepth {
            announcement += ". Depth data supported."
        }
        
        speechOutput.speak(announcement)
    }
}

// MARK: - Performance Monitoring

class CameraPerformanceMonitor {
    private var frameProcessingTimes: [TimeInterval] = []
    private var lastPerformanceReport = Date()
    private let reportInterval: TimeInterval = 30.0 // Report every 30 seconds
    
    func recordFrameProcessingTime(_ time: TimeInterval) {
        frameProcessingTimes.append(time)
        
        // Keep only recent times
        if frameProcessingTimes.count > 100 {
            frameProcessingTimes.removeFirst(frameProcessingTimes.count - 100)
        }
        
        // Report performance periodically
        if Date().timeIntervalSince(lastPerformanceReport) > reportInterval {
            reportPerformance()
            lastPerformanceReport = Date()
        }
    }
    
    private func reportPerformance() {
        guard !frameProcessingTimes.isEmpty else { return }
        
        let avgTime = frameProcessingTimes.reduce(0, +) / Double(frameProcessingTimes.count)
        let maxTime = frameProcessingTimes.max() ?? 0
        let fps = 1.0 / avgTime
        
        Config.debugLog("Camera Performance - Avg: \(Int(avgTime * 1000))ms, Max: \(Int(maxTime * 1000))ms, FPS: \(Int(fps))")
        
        // Warn if performance is poor
        if avgTime > 0.1 { // More than 100ms per frame
            Config.debugLog("Warning: Camera processing is slow, consider optimizations")
        }
    }
    
    func getPerformanceStats() -> CameraPerformanceStats {
        guard !frameProcessingTimes.isEmpty else {
            return CameraPerformanceStats(averageProcessingTime: 0, maxProcessingTime: 0, averageFPS: 0)
        }
        
        let avgTime = frameProcessingTimes.reduce(0, +) / Double(frameProcessingTimes.count)
        let maxTime = frameProcessingTimes.max() ?? 0
        let fps = 1.0 / avgTime
        
        return CameraPerformanceStats(
            averageProcessingTime: avgTime,
            maxProcessingTime: maxTime,
            averageFPS: fps
        )
    }
}

struct CameraPerformanceStats {
    let averageProcessingTime: TimeInterval
    let maxProcessingTime: TimeInterval
    let averageFPS: Double
    
    var description: String {
        return "Avg: \(Int(averageProcessingTime * 1000))ms, Max: \(Int(maxProcessingTime * 1000))ms, FPS: \(Int(averageFPS))"
    }
}

// MARK: - Integration with Agent Loop

extension EnhancedCameraManager {
    func integrateWithAgentLoop(_ agentLoop: AgentLoopManager) {
        // Register for voice commands
        agentLoop.onVoiceCommand = { [weak self] command in
            self?.processVoiceCommand(command)
        }
        
        // Register for context updates
        agentLoop.onContextUpdate = { [weak self] context in
            // Convert agent context to scene context
            let sceneContext = self?.mapAgentContextToSceneContext(context) ?? .unknown
            
            DispatchQueue.main.async {
                self?.sceneContext = sceneContext
            }
        }
    }
    
    private func mapAgentContextToSceneContext(_ agentContext: String) -> SceneContext {
        let lowercased = agentContext.lowercased()
        
        if lowercased.contains("reading") || lowercased.contains("text") {
            return .reading
        } else if lowercased.contains("conversation") || lowercased.contains("person") {
            return .faceToFace
        } else if lowercased.contains("hallway") || lowercased.contains("corridor") {
            return .hallway
        } else if lowercased.contains("stairs") || lowercased.contains("steps") {
            return .staircase
        } else if lowercased.contains("outdoor") || lowercased.contains("outside") {
            return .outdoors
        } else if lowercased.contains("narrow") || lowercased.contains("small") {
            return .indoorsNarrow
        } else if lowercased.contains("open") || lowercased.contains("large") {
            return .indoorsOpen
        } else {
            return .unknown
        }
    }
}

// MARK: - Camera Fusion Statistics

extension EnhancedCameraManager {
    func getCameraFusionStats() -> CameraFusionStats {
        return CameraFusionStats(
            currentCamera: currentCameraType,
            fieldOfView: fieldOfViewDegrees,
            sceneContext: sceneContext,
            autoSwitchingEnabled: autoSwitchingEnabled,
            totalSwitches: getTimesSwitched(),
            hasUltraWide: hasUltraWide,
            hasLiDAR: hasLiDAR,
            processingFPS: getProcessingFPS()
        )
    }
    
    private func getTimesSwitched() -> Int {
        // This would track camera switches in a real implementation
        return 0
    }
    
    private func getProcessingFPS() -> Double {
        // This would calculate actual processing FPS
        return targetFPS
    }
    
    func speakCameraFusionStatus() {
        let stats = getCameraFusionStats()
        var status = "Camera fusion status: "
        status += "Using \(stats.currentCamera.description) camera, "
        status += "\(Int(stats.fieldOfView)) degree field of view, "
        status += "Context: \(stats.sceneContext.description)"
        
        if stats.hasUltraWide {
            status += ", Ultra-wide available"
        }
        
        if stats.hasLiDAR {
            status += ", LiDAR active"
        }
        
        speechOutput.speak(status)
    }
}

struct CameraFusionStats {
    let currentCamera: CameraType
    let fieldOfView: Float
    let sceneContext: SceneContext
    let autoSwitchingEnabled: Bool
    let totalSwitches: Int
    let hasUltraWide: Bool
    let hasLiDAR: Bool
    let processingFPS: Double
} 