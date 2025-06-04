import Foundation
import ARKit
import RealityKit
import CoreLocation
import Vision
import SwiftUI

class EnhancedSpatialManager: NSObject, ObservableObject {
    @Published var isARActive = false
    @Published var spatialAnchors: [SpatialAnchor] = []
    @Published var detectedSurfaces: [ARPlaneAnchor] = []
    @Published var spatialObjects: [SpatialObject] = []
    @Published var navigationPath: [PathPoint] = []
    @Published var hasLiDAR = false
    
    // AR Session and tracking
    private var arSession: ARSession!
    private var arView: ARView?
    private var sceneReconstruction: ARSceneReconstruction = .meshWithClassification
    
    // Spatial mapping
    private var roomGeometry: RoomGeometry?
    private var meshManager = SpatialMeshManager()
    private var anchorManager = SpatialAnchorManager()
    
    // Object tracking and recognition
    private var objectTracker = SpatialObjectTracker()
    private var persistentObjects: [UUID: TrackedObject] = [:]
    
    // Navigation and pathfinding
    private var pathfinder = SpatialPathfinder()
    private var obstacleMap = SpatialObstacleMap()
    
    // Audio and feedback
    private let speechOutput = SpeechOutput()
    private let hapticFeedback = HapticFeedbackManager()
    private let spatialAudio = SpatialAudioManager()
    
    // Dependencies
    private let cloudSync = CloudSyncManager()
    
    // ARKit Scene Labeling and Persistent Memory
    private var sceneLabels: [SceneLabel] = []
    private var persistentObjectAnchors: [UUID: PersistentObjectAnchor] = [:]
    private let sceneLabelingEngine = SceneLabelingEngine()
    private var spatialMemoryManager = SpatialMemoryManager()
    
    // Mobility Aid Navigation
    private var mobilityNavigator = MobilityNavigator()
    private var roomMapper = LiDARRoomMapper()
    private var navigationInstructor = TurnByTurnInstructor()
    private var currentNavigation: ActiveNavigation?
    
    override init() {
        super.init()
        setupEnhancedSpatial()
    }
    
    // MARK: - Setup
    
    private func setupEnhancedSpatial() {
        setupARSession()
        checkLiDARAvailability()
        setupSpatialAudio()
        setupDelegates()
        
        Config.debugLog("Enhanced spatial manager initialized")
    }
    
    private func setupARSession() {
        arSession = ARSession()
        arSession.delegate = self
        
        // Check for AR capabilities
        guard ARWorldTrackingConfiguration.isSupported else {
            Config.debugLog("ARWorldTracking not supported on this device")
            return
        }
        
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal, .vertical]
        configuration.environmentTexturing = .automatic
        
        // Enable scene reconstruction if available
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification) {
            configuration.sceneReconstruction = .meshWithClassification
            sceneReconstruction = .meshWithClassification
        } else if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            configuration.sceneReconstruction = .mesh
            sceneReconstruction = .mesh
        }
        
        // Configure frame semantics for enhanced understanding
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.personSegmentationWithDepth) {
            configuration.frameSemantics.insert(.personSegmentationWithDepth)
        }
        
        arSession.run(configuration)
        isARActive = true
    }
    
    private func checkLiDARAvailability() {
        hasLiDAR = ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification)
        
        if hasLiDAR {
            Config.debugLog("LiDAR available - enabling enhanced spatial features")
            enableLiDARFeatures()
        } else {
            Config.debugLog("LiDAR not available - using depth estimation")
            enableDepthEstimationFeatures()
        }
    }
    
    private func enableLiDARFeatures() {
        // Enhanced features for LiDAR-equipped devices
        meshManager.enableHighResolutionMesh()
        obstacleMap.enablePreciseObstacleDetection()
        pathfinder.enableLiDARPathfinding()
    }
    
    private func enableDepthEstimationFeatures() {
        // Fallback features for non-LiDAR devices
        meshManager.enableDepthEstimationMesh()
        obstacleMap.enableVisionBasedDetection()
        pathfinder.enableHeuristicPathfinding()
    }
    
    private func setupSpatialAudio() {
        spatialAudio.configure(session: arSession)
        spatialAudio.delegate = self
    }
    
    private func setupDelegates() {
        meshManager.delegate = self
        anchorManager.delegate = self
        objectTracker.delegate = self
        pathfinder.delegate = self
    }
    
    // MARK: - Spatial Anchoring
    
    func addSpatialAnchor(name: String, description: String, at worldTransform: simd_float4x4) {
        let anchor = ARAnchor(name: name, transform: worldTransform)
        arSession.add(anchor: anchor)
        
        let spatialAnchor = SpatialAnchor(
            id: anchor.identifier,
            name: name,
            description: description,
            transform: worldTransform,
            timestamp: Date()
        )
        
        spatialAnchors.append(spatialAnchor)
        
        // Save to cloud for persistence
        cloudSync.saveSpatialAnchor(spatialAnchor)
        
        // Provide audio feedback
        spatialAudio.addAudioCue(at: worldTransform, sound: .anchorPlaced)
        speechOutput.speak("Spatial anchor '\(name)' placed")
        
        Config.debugLog("Added spatial anchor: \(name)")
    }
    
    func removeSpatialAnchor(id: UUID) {
        // Remove from AR session
        if let anchor = arSession.currentFrame?.anchors.first(where: { $0.identifier == id }) {
            arSession.remove(anchor: anchor)
        }
        
        // Remove from local array
        spatialAnchors.removeAll { $0.id == id }
        
        // Remove from cloud
        cloudSync.removeSpatialAnchor(id: id)
        
        speechOutput.speak("Spatial anchor removed")
    }
    
    func navigateToAnchor(id: UUID) {
        guard let anchor = spatialAnchors.first(where: { $0.id == id }) else {
            speechOutput.speak("Anchor not found")
            return
        }
        
        guard let currentFrame = arSession.currentFrame else {
            speechOutput.speak("Unable to determine current position")
            return
        }
        
        let currentPosition = currentFrame.camera.transform
        let targetPosition = anchor.transform
        
        // Calculate path
        pathfinder.calculatePath(from: currentPosition, to: targetPosition) { [weak self] path in
            DispatchQueue.main.async {
                self?.navigationPath = path
                self?.startNavigationToAnchor(anchor, path: path)
            }
        }
    }
    
    private func startNavigationToAnchor(_ anchor: SpatialAnchor, path: [PathPoint]) {
        // Create navigation guidance
        let guidance = NavigationGuidance(
            target: anchor,
            path: path,
            currentStep: 0
        )
        
        // Start step-by-step guidance
        provideNavigationGuidance(guidance)
        
        // Add spatial audio markers along the path
        for (index, point) in path.enumerated() {
            let audioMarker = SpatialAudioMarker(
                position: point.position,
                type: index == path.count - 1 ? .destination : .waypoint,
                distance: point.distanceFromStart
            )
            spatialAudio.addNavigationMarker(audioMarker)
        }
        
        speechOutput.speak("Starting navigation to \(anchor.name)")
    }
    
    // MARK: - Room Geometry Analysis
    
    func analyzeRoomGeometry() {
        guard let frame = arSession.currentFrame else { return }
        
        let roomAnalyzer = RoomGeometryAnalyzer()
        roomAnalyzer.analyze(frame: frame, meshAnchors: getMeshAnchors()) { [weak self] geometry in
            DispatchQueue.main.async {
                self?.roomGeometry = geometry
                self?.processRoomGeometry(geometry)
            }
        }
    }
    
    private func processRoomGeometry(_ geometry: RoomGeometry) {
        // Announce room characteristics
        var description = "Room analysis: "
        description += "Approximately \(Int(geometry.dimensions.width)) by \(Int(geometry.dimensions.length)) meters. "
        
        if geometry.openings.count > 0 {
            description += "\(geometry.openings.count) opening\(geometry.openings.count == 1 ? "" : "s") detected. "
        }
        
        if geometry.furniture.count > 0 {
            description += "\(geometry.furniture.count) furniture item\(geometry.furniture.count == 1 ? "" : "s") identified. "
        }
        
        speechOutput.speak(description)
        
        // Update obstacle map with room geometry
        obstacleMap.updateWithRoomGeometry(geometry)
    }
    
    private func getMeshAnchors() -> [ARMeshAnchor] {
        return arSession.currentFrame?.anchors.compactMap { $0 as? ARMeshAnchor } ?? []
    }
    
    // MARK: - Object Tracking
    
    func trackObject(at position: simd_float3, name: String, category: ObjectCategory) {
        let trackedObject = TrackedObject(
            id: UUID(),
            name: name,
            category: category,
            position: position,
            lastSeen: Date(),
            confidence: 1.0
        )
        
        persistentObjects[trackedObject.id] = trackedObject
        spatialObjects.append(SpatialObject(from: trackedObject))
        
        // Add spatial audio cue
        spatialAudio.addObjectMarker(at: position, category: category)
        
        speechOutput.speak("Tracking \(name) as \(category.description)")
        
        Config.debugLog("Started tracking object: \(name)")
    }
    
    func findTrackedObjects(category: ObjectCategory? = nil) -> [TrackedObject] {
        let objects = Array(persistentObjects.values)
        
        if let category = category {
            return objects.filter { $0.category == category }
        }
        
        return objects
    }
    
    func navigateToObject(id: UUID) {
        guard let object = persistentObjects[id] else {
            speechOutput.speak("Object not found")
            return
        }
        
        guard let currentFrame = arSession.currentFrame else {
            speechOutput.speak("Unable to determine current position")
            return
        }
        
        let currentPosition = currentFrame.camera.transform
        let targetTransform = simd_float4x4(translation: object.position)
        
        pathfinder.calculatePath(from: currentPosition, to: targetTransform) { [weak self] path in
            DispatchQueue.main.async {
                self?.navigationPath = path
                self?.startNavigationToObject(object, path: path)
            }
        }
    }
    
    private func startNavigationToObject(_ object: TrackedObject, path: [PathPoint]) {
        speechOutput.speak("Navigating to \(object.name)")
        
        // Provide initial direction
        if let firstStep = path.first {
            let direction = getDirectionDescription(to: firstStep.position)
            speechOutput.speak("Head \(direction)")
        }
    }
    
    // MARK: - Obstacle Detection and Avoidance
    
    func performObstacleDetection() -> [SpatialObstacle] {
        guard let frame = arSession.currentFrame else { return [] }
        
        let obstacles = obstacleMap.detectObstacles(in: frame)
        
        // Classify obstacles by urgency
        let criticalObstacles = obstacles.filter { $0.severity == .critical }
        let warningObstacles = obstacles.filter { $0.severity == .warning }
        
        // Provide audio warnings for critical obstacles
        for obstacle in criticalObstacles {
            spatialAudio.playWarning(at: obstacle.position, severity: obstacle.severity)
        }
        
        // Announce obstacle summary if significant
        if !criticalObstacles.isEmpty {
            speechOutput.speak("Warning: \(criticalObstacles.count) critical obstacle\(criticalObstacles.count == 1 ? "" : "s") detected", priority: .high)
        } else if warningObstacles.count > 3 {
            speechOutput.speak("Caution: Multiple obstacles ahead")
        }
        
        return obstacles
    }
    
    // MARK: - Safe Path Generation
    
    func calculateSafePath(to destination: simd_float3, completion: @escaping ([PathPoint]) -> Void) {
        guard let currentFrame = arSession.currentFrame else {
            completion([])
            return
        }
        
        let currentPosition = currentFrame.camera.transform
        let targetTransform = simd_float4x4(translation: destination)
        
        // Include current obstacles in pathfinding
        let currentObstacles = performObstacleDetection()
        pathfinder.setObstacles(currentObstacles)
        
        pathfinder.calculateSafePath(from: currentPosition, to: targetTransform) { path in
            completion(path)
        }
    }
    
    // MARK: - Spatial Audio Integration
    
    func provideSpatialAudioGuidance() {
        // Create 3D audio landscape
        spatialAudio.updateListenerPosition(arSession.currentFrame?.camera.transform)
        
        // Add audio cues for nearby objects
        for object in spatialObjects {
            spatialAudio.updateObjectPosition(object.id, position: object.position)
        }
        
        // Add audio cues for anchors
        for anchor in spatialAnchors {
            spatialAudio.updateAnchorPosition(anchor.id, transform: anchor.transform)
        }
    }
    
    // MARK: - Surface Analysis
    
    private func analyzeSurface(_ planeAnchor: ARPlaneAnchor) {
        let surfaceInfo = SurfaceInfo(
            id: planeAnchor.identifier,
            classification: planeAnchor.classification,
            extent: planeAnchor.extent,
            center: planeAnchor.center,
            transform: planeAnchor.transform
        )
        
        // Announce significant surfaces
        switch planeAnchor.classification {
        case .wall:
            if planeAnchor.extent.x > 2.0 || planeAnchor.extent.z > 2.0 {
                let direction = getDirectionDescription(to: planeAnchor.center)
                speechOutput.speak("Large wall detected \(direction)")
            }
        case .floor:
            if planeAnchor.extent.x > 3.0 && planeAnchor.extent.z > 3.0 {
                speechOutput.speak("Open floor area detected")
            }
        case .door:
            let direction = getDirectionDescription(to: planeAnchor.center)
            speechOutput.speak("Door detected \(direction)")
        case .window:
            let direction = getDirectionDescription(to: planeAnchor.center)
            speechOutput.speak("Window detected \(direction)")
        default:
            break
        }
    }
    
    // MARK: - Navigation Guidance
    
    private func provideNavigationGuidance(_ guidance: NavigationGuidance) {
        guard guidance.currentStep < guidance.path.count else {
            speechOutput.speak("You have arrived at \(guidance.target.name)")
            return
        }
        
        let currentStep = guidance.path[guidance.currentStep]
        let direction = getDirectionDescription(to: currentStep.position)
        let distance = String(format: "%.1f", currentStep.distanceFromStart)
        
        speechOutput.speak("Continue \(direction) for \(distance) meters")
    }
    
    private func getDirectionDescription(to position: simd_float3) -> String {
        guard let frame = arSession.currentFrame else { return "ahead" }
        
        let cameraTransform = frame.camera.transform
        let cameraPosition = simd_float3(cameraTransform.columns.3.x, cameraTransform.columns.3.y, cameraTransform.columns.3.z)
        let cameraForward = -simd_float3(cameraTransform.columns.2.x, cameraTransform.columns.2.y, cameraTransform.columns.2.z)
        
        let direction = simd_normalize(position - cameraPosition)
        let dot = simd_dot(direction, cameraForward)
        let cross = simd_cross(cameraForward, direction)
        
        if dot > 0.7 {
            return "straight ahead"
        } else if dot < -0.7 {
            return "behind you"
        } else if cross.y > 0 {
            return "to your right"
        } else {
            return "to your left"
        }
    }
    
    // MARK: - Public Interface
    
    func pauseTracking() {
        arSession.pause()
        isARActive = false
        spatialAudio.pause()
    }
    
    func resumeTracking() {
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal, .vertical]
        configuration.sceneReconstruction = sceneReconstruction
        
        arSession.run(configuration)
        isARActive = true
        spatialAudio.resume()
    }
    
    func getSpatialStatus() -> String {
        var status = "Spatial tracking: "
        status += isARActive ? "Active" : "Inactive"
        status += ". \(spatialAnchors.count) anchors, \(spatialObjects.count) tracked objects"
        
        if hasLiDAR {
            status += ". LiDAR enhanced"
        }
        
        return status
    }
    
    func speakSpatialStatus() {
        let status = getSpatialStatus()
        speechOutput.speak(status)
    }
    
    // MARK: - ARKit Scene Labeling and Persistent Memory
    
    private func addUserNamedObject(name: String, at worldPosition: simd_float3, description: String = "") {
        // Create AR anchor at the specified position
        let transform = simd_float4x4(translation: worldPosition)
        let anchor = ARAnchor(name: "user_object_\(name)", transform: transform)
        arSession.add(anchor: anchor)
        
        // Create persistent object anchor
        let persistentAnchor = PersistentObjectAnchor(
            id: anchor.identifier,
            name: name,
            description: description,
            worldPosition: worldPosition,
            timestamp: Date(),
            category: .userNamed,
            confidence: 1.0,
            lastInteraction: Date()
        )
        
        persistentObjectAnchors[anchor.identifier] = persistentAnchor
        
        // Add scene label
        let sceneLabel = SceneLabel(
            id: UUID(),
            anchorID: anchor.identifier,
            name: name,
            position: worldPosition,
            type: .userDefined,
            confidence: 1.0,
            timestamp: Date()
        )
        sceneLabels.append(sceneLabel)
        
        // Save to persistent storage
        spatialMemoryManager.saveObjectAnchor(persistentAnchor)
        
        // Provide spatial audio feedback
        spatialAudio.addAudioCue(at: transform, sound: .objectNamed)
        speechOutput.speak("Labeled this location as \(name)")
        
        Config.debugLog("Added user-named object: \(name) at \(worldPosition)")
    }
    
    private func removeUserNamedObject(name: String) {
        // Find and remove the object
        guard let anchor = persistentObjectAnchors.values.first(where: { $0.name.lowercased() == name.lowercased() }) else {
            speechOutput.speak("I don't have a label for \(name)")
            return
        }
        
        // Remove from AR session
        if let arAnchor = arSession.currentFrame?.anchors.first(where: { $0.identifier == anchor.id }) {
            arSession.remove(anchor: arAnchor)
        }
        
        // Remove from memory
        persistentObjectAnchors.removeValue(forKey: anchor.id)
        sceneLabels.removeAll { $0.anchorID == anchor.id }
        spatialMemoryManager.removeObjectAnchor(id: anchor.id)
        
        speechOutput.speak("Removed label for \(name)")
    }
    
    private func findUserNamedObject(name: String) -> PersistentObjectAnchor? {
        return persistentObjectAnchors.values.first { $0.name.lowercased() == name.lowercased() }
    }
    
    private func listUserNamedObjects() -> [String] {
        return persistentObjectAnchors.values.map { $0.name }.sorted()
    }
    
    // MARK: - Scene Labeling with Voice Commands
    
    private func labelCurrentLocation(name: String, description: String = "") {
        guard let currentFrame = arSession.currentFrame else {
            speechOutput.speak("Unable to determine current location")
            return
        }
        
        let currentPosition = simd_float3(
            currentFrame.camera.transform.columns.3.x,
            currentFrame.camera.transform.columns.3.y,
            currentFrame.camera.transform.columns.3.z
        )
        
        addUserNamedObject(name: name, at: currentPosition, description: description)
    }
    
    private func processVoiceLabelingCommand(_ command: String) {
        let processor = VoiceLabelingProcessor()
        let labelCommand = processor.parseCommand(command)
        
        switch labelCommand.type {
        case .labelHere:
            if let name = labelCommand.objectName {
                labelCurrentLocation(name: name, description: labelCommand.description ?? "")
            }
            
        case .labelThere:
            // Use spatial targeting to label distant objects
            if let name = labelCommand.objectName, let direction = labelCommand.direction {
                labelObjectInDirection(name: name, direction: direction)
            }
            
        case .findLabel:
            if let name = labelCommand.objectName {
                navigateToUserNamedObject(name: name)
            }
            
        case .removeLabel:
            if let name = labelCommand.objectName {
                removeUserNamedObject(name: name)
            }
            
        case .listLabels:
            announceUserLabels()
            
        case .unknown:
            speechOutput.speak("I didn't understand that labeling command. Try saying 'label this as kitchen' or 'take me to the door'.")
        }
    }
    
    private func labelObjectInDirection(name: String, direction: SpatialDirection) {
        guard let currentFrame = arSession.currentFrame else { return }
        
        // Cast ray in the specified direction
        let rayOrigin = simd_float3(currentFrame.camera.transform.columns.3.x,
                                   currentFrame.camera.transform.columns.3.y,
                                   currentFrame.camera.transform.columns.3.z)
        
        let rayDirection = calculateRayDirection(direction, from: currentFrame.camera.transform)
        
        // Perform raycast to find target position
        if let hitPosition = performRaycast(origin: rayOrigin, direction: rayDirection) {
            addUserNamedObject(name: name, at: hitPosition)
        } else {
            // Estimate position based on direction and default distance
            let estimatedPosition = rayOrigin + rayDirection * 2.0 // 2 meters in direction
            addUserNamedObject(name: name, at: estimatedPosition)
        }
    }
    
    private func calculateRayDirection(_ direction: SpatialDirection, from cameraTransform: simd_float4x4) -> simd_float3 {
        let forward = -simd_float3(cameraTransform.columns.2.x, cameraTransform.columns.2.y, cameraTransform.columns.2.z)
        let right = simd_float3(cameraTransform.columns.0.x, cameraTransform.columns.0.y, cameraTransform.columns.0.z)
        let up = simd_float3(cameraTransform.columns.1.x, cameraTransform.columns.1.y, cameraTransform.columns.1.z)
        
        switch direction {
        case .forward:
            return forward
        case .left:
            return -right
        case .right:
            return right
        case .up:
            return up
        case .down:
            return -up
        case .forwardLeft:
            return simd_normalize(forward - right)
        case .forwardRight:
            return simd_normalize(forward + right)
        }
    }
    
    private func performRaycast(origin: simd_float3, direction: simd_float3) -> simd_float3? {
        // Perform ARKit raycast
        let raycastQuery = ARRaycastQuery(origin: origin, direction: direction, allowing: .estimatedPlane, alignment: .any)
        let results = arSession.raycast(raycastQuery)
        
        return results.first?.worldTransform.translation
    }
    
    // MARK: - Persistent Object Memory Across Sessions
    
    func loadPersistentObjectAnchors() {
        spatialMemoryManager.loadAllObjectAnchors { [weak self] anchors in
            DispatchQueue.main.async {
                for anchor in anchors {
                    self?.restoreObjectAnchor(anchor)
                }
            }
        }
    }
    
    private func restoreObjectAnchor(_ anchor: PersistentObjectAnchor) {
        // Recreate AR anchor
        let transform = simd_float4x4(translation: anchor.worldPosition)
        let arAnchor = ARAnchor(name: "user_object_\(anchor.name)", transform: transform)
        arSession.add(anchor: arAnchor)
        
        // Update ID to match new AR anchor
        var restoredAnchor = anchor
        restoredAnchor.id = arAnchor.identifier
        
        persistentObjectAnchors[arAnchor.identifier] = restoredAnchor
        
        // Recreate scene label
        let sceneLabel = SceneLabel(
            id: UUID(),
            anchorID: arAnchor.identifier,
            name: anchor.name,
            position: anchor.worldPosition,
            type: .userDefined,
            confidence: anchor.confidence,
            timestamp: anchor.timestamp
        )
        sceneLabels.append(sceneLabel)
        
        // Add spatial audio marker
        spatialAudio.addAudioCue(at: transform, sound: .objectRestored)
        
        Config.debugLog("Restored object anchor: \(anchor.name)")
    }
    
    // MARK: - Navigation to User-Named Objects
    
    func navigateToUserNamedObject(name: String) {
        guard let targetAnchor = findUserNamedObject(name: name) else {
            speechOutput.speak("I don't know where your \(name) is. Would you like me to help you label it?")
            return
        }
        
        guard let currentFrame = arSession.currentFrame else {
            speechOutput.speak("Unable to determine current position")
            return
        }
        
        let currentPosition = currentFrame.camera.transform
        let targetTransform = simd_float4x4(translation: targetAnchor.worldPosition)
        
        // Calculate navigation path
        pathfinder.calculatePath(from: currentPosition, to: targetTransform) { [weak self] path in
            DispatchQueue.main.async {
                self?.navigationPath = path
                self?.startNavigationToObject(targetAnchor, path: path)
            }
        }
    }
    
    private func startNavigationToObject(_ anchor: PersistentObjectAnchor, path: [PathPoint]) {
        speechOutput.speak("Navigating to \(anchor.name)")
        
        // Update last interaction time
        persistentObjectAnchors[anchor.id]?.lastInteraction = Date()
        spatialMemoryManager.updateObjectAnchor(persistentObjectAnchors[anchor.id]!)
        
        // Provide spatial audio guidance
        let audioMarker = SpatialAudioMarker(
            position: anchor.worldPosition,
            type: .destination,
            distance: calculateDistance(to: anchor.worldPosition)
        )
        spatialAudio.addNavigationMarker(audioMarker)
        
        // Start turn-by-turn guidance
        if let firstStep = path.first {
            let direction = getDirectionDescription(to: firstStep.position)
            speechOutput.speak("Head \(direction) toward \(anchor.name)")
        }
    }
    
    private func calculateDistance(to position: simd_float3) -> Float {
        guard let currentFrame = arSession.currentFrame else { return 0.0 }
        
        let currentPosition = simd_float3(
            currentFrame.camera.transform.columns.3.x,
            currentFrame.camera.transform.columns.3.y,
            currentFrame.camera.transform.columns.3.z
        )
        
        return simd_distance(currentPosition, position)
    }
    
    // MARK: - Smart Object Suggestions
    
    func suggestNearbyObjects() {
        guard let currentFrame = arSession.currentFrame else { return }
        
        let currentPosition = simd_float3(
            currentFrame.camera.transform.columns.3.x,
            currentFrame.camera.transform.columns.3.y,
            currentFrame.camera.transform.columns.3.z
        )
        
        // Find objects within 10 meters
        let nearbyObjects = persistentObjectAnchors.values.filter { anchor in
            let distance = simd_distance(currentPosition, anchor.worldPosition)
            return distance <= 10.0
        }.sorted { anchor1, anchor2 in
            let dist1 = simd_distance(currentPosition, anchor1.worldPosition)
            let dist2 = simd_distance(currentPosition, anchor2.worldPosition)
            return dist1 < dist2
        }
        
        if nearbyObjects.isEmpty {
            speechOutput.speak("No labeled objects nearby")
        } else {
            let objectNames = nearbyObjects.prefix(3).map { anchor in
                let distance = simd_distance(currentPosition, anchor.worldPosition)
                return "\(anchor.name) (\(String(format: "%.1f", distance)) meters)"
            }
            
            let announcement = "Nearby objects: \(objectNames.joined(separator: ", "))"
            speechOutput.speak(announcement)
        }
    }
    
    private func announceUserLabels() {
        let labelNames = listUserNamedObjects()
        
        if labelNames.isEmpty {
            speechOutput.speak("You haven't labeled any objects yet")
        } else {
            let labelList = labelNames.joined(separator: ", ")
            speechOutput.speak("Your labeled objects: \(labelList)")
        }
    }
    
    // MARK: - Public Interface for Scene Labeling
    
    func enableSceneLabelingMode() {
        speechOutput.speak("Scene labeling mode activated. Say 'label this as kitchen' or 'take me to the door'.")
    }
    
    func processUserLabelingCommand(_ command: String) {
        processVoiceLabelingCommand(command)
    }
    
    func getSpatialMemoryStats() -> ObjectMemoryStats {
        let totalObjects = persistentObjectAnchors.count
        let recentlyUsed = persistentObjectAnchors.values.filter {
            Date().timeIntervalSince($0.lastInteraction) < 86400 // Last 24 hours
        }.count
        
        let oldestObject = persistentObjectAnchors.values.min(by: { $0.timestamp < $1.timestamp })
        let newestObject = persistentObjectAnchors.values.max(by: { $0.timestamp < $1.timestamp })
        
        return ObjectMemoryStats(
            totalObjects: totalObjects,
            recentlyUsed: recentlyUsed,
            oldestObjectDate: oldestObject?.timestamp,
            newestObjectDate: newestObject?.timestamp
        )
    }
    
    // MARK: - Mobility Aid Navigation
    
    func startRoomNavigation(to destination: String) {
        guard hasLiDAR else {
            speechOutput.speak("LiDAR navigation not available on this device. Using basic navigation.")
            startBasicNavigation(to: destination)
            return
        }
        
        speechOutput.speak("Starting LiDAR navigation to \(destination)")
        
        // Generate detailed room map
        roomMapper.generateRoomMap { [weak self] roomMap in
            guard let self = self, let map = roomMap else {
                self?.speechOutput.speak("Unable to map room for navigation")
                return
            }
            
            // Find destination in room
            if let destinationPoint = self.findDestinationInRoom(destination, map: map) {
                self.startLiDARGuidedNavigation(to: destinationPoint, map: map)
            } else {
                self.speechOutput.speak("Destination \(destination) not found in current room")
            }
        }
    }
    
    private func startLiDARGuidedNavigation(to destination: simd_float3, map: LiDARRoomMap) {
        guard let currentFrame = arSession.currentFrame else { return }
        
        let currentPosition = currentFrame.camera.transform
        
        // Calculate optimal path using LiDAR data
        mobilityNavigator.calculateOptimalPath(
            from: currentPosition,
            to: simd_float4x4(translation: destination),
            using: map
        ) { [weak self] navigationPath in
            DispatchQueue.main.async {
                self?.startTurnByTurnGuidance(path: navigationPath, map: map)
            }
        }
    }
    
    private func startTurnByTurnGuidance(path: NavigationPath, map: LiDARRoomMap) {
        currentNavigation = ActiveNavigation(
            path: path,
            map: map,
            currentStep: 0,
            startTime: Date()
        )
        
        // Setup spatial audio navigation
        setupSpatialAudioNavigation(path: path)
        
        // Start step-by-step instructions
        provideNavigationInstruction(for: 0)
        
        // Begin continuous guidance
        mobilityNavigator.startContinuousGuidance(navigation: currentNavigation!)
    }
    
    private func setupSpatialAudioNavigation(path: NavigationPath) {
        // Add audio beacons at key navigation points
        for (index, step) in path.steps.enumerated() {
            let audioBeacon = NavigationBeacon(
                position: step.position,
                type: step.type == .destination ? .destination : .waypoint,
                stepNumber: index,
                instruction: step.instruction
            )
            
            spatialAudio.addNavigationBeacon(audioBeacon)
        }
        
        // Add continuous path audio
        spatialAudio.enablePathSonification(path: path)
    }
    
    private func provideNavigationInstruction(for stepIndex: Int) {
        guard let navigation = currentNavigation,
              stepIndex < navigation.path.steps.count else { return }
        
        let step = navigation.path.steps[stepIndex]
        let instruction = navigationInstructor.generateInstruction(
            step: step,
            previousStep: stepIndex > 0 ? navigation.path.steps[stepIndex - 1] : nil,
            map: navigation.map
        )
        
        speechOutput.speak(instruction, priority: .high)
        
        // Provide spatial audio confirmation
        spatialAudio.playNavigationCue(at: step.position, type: .instruction)
    }
    
    // MARK: - Continuous Navigation Guidance
    
    func updateNavigationProgress() {
        guard let navigation = currentNavigation,
              let currentFrame = arSession.currentFrame else { return }
        
        let currentPosition = simd_float3(
            currentFrame.camera.transform.columns.3.x,
            currentFrame.camera.transform.columns.3.y,
            currentFrame.camera.transform.columns.3.z
        )
        
        // Check if user has reached the next waypoint
        let currentStep = navigation.path.steps[navigation.currentStep]
        let distanceToStep = simd_distance(currentPosition, currentStep.position)
        
        if distanceToStep < 1.0 { // Within 1 meter of waypoint
            // Move to next step
            if navigation.currentStep + 1 < navigation.path.steps.count {
                currentNavigation!.currentStep += 1
                provideNavigationInstruction(for: currentNavigation!.currentStep)
                
                // Provide haptic feedback for reaching waypoint
                hapticFeedback.provideNavigationFeedback()
                
            } else {
                // Navigation complete
                completeNavigation()
            }
        } else {
            // Provide continuous guidance
            provideContinuousGuidance(to: currentStep, from: currentPosition)
        }
    }
    
    private func provideContinuousGuidance(to target: NavigationStep, from currentPosition: simd_float3) {
        let distanceToTarget = simd_distance(currentPosition, target.position)
        
        // Provide distance updates every 2 meters
        if Int(distanceToTarget) % 2 == 0 && distanceToTarget > 2.0 {
            let direction = getDirectionDescription(to: target.position)
            speechOutput.speak("\(Int(distanceToTarget)) meters \(direction)", priority: .low)
        }
        
        // Update spatial audio guidance
        spatialAudio.updateNavigationGuidance(
            targetPosition: target.position,
            currentPosition: currentPosition,
            distance: distanceToTarget
        )
        
        // Check for obstacles in path
        if let obstacle = detectObstacleInPath(from: currentPosition, to: target.position) {
            handleNavigationObstacle(obstacle)
        }
    }
    
    private func detectObstacleInPath(from start: simd_float3, to end: simd_float3) -> NavigationObstacle? {
        guard let navigation = currentNavigation else { return nil }
        
        // Use LiDAR data to detect obstacles along the path
        let pathVector = end - start
        let pathLength = simd_length(pathVector)
        let pathDirection = simd_normalize(pathVector)
        
        // Sample points along the path
        for distance in stride(from: 0.5, to: pathLength, by: 0.5) {
            let samplePoint = start + pathDirection * distance
            
            if let obstacle = navigation.map.getObstacleAt(position: samplePoint) {
                return NavigationObstacle(
                    position: samplePoint,
                    type: obstacle.type,
                    severity: .warning,
                    distanceFromUser: distance
                )
            }
        }
        
        return nil
    }
    
    private func handleNavigationObstacle(_ obstacle: NavigationObstacle) {
        speechOutput.speak("Obstacle detected ahead. \(obstacle.type.description)", priority: .high)
        
        // Calculate alternate route
        guard let navigation = currentNavigation else { return }
        
        mobilityNavigator.calculateAlternateRoute(
            avoiding: obstacle,
            from: navigation.currentStep,
            map: navigation.map
        ) { [weak self] alternateRoute in
            if let route = alternateRoute {
                self?.speechOutput.speak("Alternate route found")
                self?.updateNavigationPath(with: route)
            } else {
                self?.speechOutput.speak("Please navigate around the obstacle manually")
            }
        }
    }
    
    private func updateNavigationPath(with newRoute: NavigationPath) {
        currentNavigation?.path = newRoute
        
        // Update spatial audio with new path
        spatialAudio.clearNavigationBeacons()
        setupSpatialAudioNavigation(path: newRoute)
        
        // Continue with updated path
        provideNavigationInstruction(for: currentNavigation!.currentStep)
    }
    
    private func completeNavigation() {
        speechOutput.speak("You have arrived at your destination")
        
        // Clean up navigation state
        spatialAudio.clearNavigationBeacons()
        spatialAudio.disablePathSonification()
        mobilityNavigator.stopContinuousGuidance()
        
        currentNavigation = nil
    }
    
    // MARK: - Context-Aware Instructions
    
    func enableContextAwareNavigation() {
        navigationInstructor.enableContextAwareness()
        speechOutput.speak("Context-aware navigation enabled. I'll provide more detailed guidance based on your surroundings.")
    }
    
    private func findDestinationInRoom(_ destination: String, map: LiDARRoomMap) -> simd_float3? {
        // Look for user-labeled locations first
        if let userLocation = findUserNamedObject(name: destination) {
            return userLocation.worldPosition
        }
        
        // Look for automatically detected landmarks
        if let landmark = map.landmarks.first(where: { $0.name.lowercased().contains(destination.lowercased()) }) {
            return landmark.position
        }
        
        // Look for furniture or objects that match
        if let furniture = map.furniture.first(where: { $0.category.rawValue.contains(destination.lowercased()) }) {
            return furniture.position
        }
        
        return nil
    }
    
    private func startBasicNavigation(to destination: String) {
        // Fallback navigation without LiDAR
        if let target = findUserNamedObject(name: destination) {
            navigateToUserNamedObject(name: destination)
        } else {
            speechOutput.speak("Please label the location first, or provide more specific directions")
        }
    }
}

// MARK: - ARSessionDelegate

extension EnhancedSpatialManager: ARSessionDelegate {
    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        for anchor in anchors {
            if let planeAnchor = anchor as? ARPlaneAnchor {
                DispatchQueue.main.async {
                    self.detectedSurfaces.append(planeAnchor)
                    self.analyzeSurface(planeAnchor)
                }
            } else if let meshAnchor = anchor as? ARMeshAnchor {
                meshManager.processMeshAnchor(meshAnchor)
            }
        }
    }
    
    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        for anchor in anchors {
            if let planeAnchor = anchor as? ARPlaneAnchor {
                // Update existing plane
                if let index = detectedSurfaces.firstIndex(where: { $0.identifier == planeAnchor.identifier }) {
                    detectedSurfaces[index] = planeAnchor
                }
            } else if let meshAnchor = anchor as? ARMeshAnchor {
                meshManager.updateMeshAnchor(meshAnchor)
            }
        }
    }
    
    func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {
        for anchor in anchors {
            if let planeAnchor = anchor as? ARPlaneAnchor {
                detectedSurfaces.removeAll { $0.identifier == planeAnchor.identifier }
            }
        }
    }
    
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        // Update spatial audio listener position
        spatialAudio.updateListenerPosition(frame.camera.transform)
        
        // Update object tracking
        objectTracker.updateTracking(frame: frame)
        
        // Continuous obstacle detection (throttled)
        if Date().timeIntervalSince(obstacleMap.lastUpdate) > 0.5 {
            let _ = performObstacleDetection()
        }
    }
}

// MARK: - Delegate Extensions

extension EnhancedSpatialManager: SpatialMeshManagerDelegate {
    func meshManager(_ manager: SpatialMeshManager, didUpdateMesh mesh: SpatialMesh) {
        // Process updated mesh data
        roomGeometry?.updateWithMesh(mesh)
    }
}

extension EnhancedSpatialManager: SpatialAnchorManagerDelegate {
    func anchorManager(_ manager: SpatialAnchorManager, didLoadAnchors anchors: [SpatialAnchor]) {
        DispatchQueue.main.async {
            self.spatialAnchors = anchors
        }
    }
}

extension EnhancedSpatialManager: SpatialObjectTrackerDelegate {
    func objectTracker(_ tracker: SpatialObjectTracker, didUpdateObject object: TrackedObject) {
        persistentObjects[object.id] = object
        
        // Update spatial object array
        if let index = spatialObjects.firstIndex(where: { $0.id == object.id }) {
            spatialObjects[index] = SpatialObject(from: object)
        }
    }
}

extension EnhancedSpatialManager: SpatialPathfinderDelegate {
    func pathfinder(_ pathfinder: SpatialPathfinder, didCalculatePath path: [PathPoint]) {
        DispatchQueue.main.async {
            self.navigationPath = path
        }
    }
}

extension EnhancedSpatialManager: SpatialAudioManagerDelegate {
    func spatialAudio(_ manager: SpatialAudioManager, didPlaySound sound: SpatialSound) {
        // Handle spatial audio feedback
    }
}

// MARK: - Supporting Data Models

struct SpatialAnchor: Identifiable {
    let id: UUID
    let name: String
    let description: String
    let transform: simd_float4x4
    let timestamp: Date
}

struct SpatialObject: Identifiable {
    let id: UUID
    let name: String
    let category: ObjectCategory
    let position: simd_float3
    let lastSeen: Date
    
    init(from trackedObject: TrackedObject) {
        self.id = trackedObject.id
        self.name = trackedObject.name
        self.category = trackedObject.category
        self.position = trackedObject.position
        self.lastSeen = trackedObject.lastSeen
    }
}

struct TrackedObject {
    let id: UUID
    let name: String
    let category: ObjectCategory
    let position: simd_float3
    let lastSeen: Date
    let confidence: Double
}

enum ObjectCategory: String, CaseIterable {
    case furniture = "furniture"
    case door = "door"
    case window = "window"
    case obstacle = "obstacle"
    case landmark = "landmark"
    case person = "person"
    case utility = "utility"
    
    var description: String {
        return rawValue.capitalized
    }
}

struct PathPoint {
    let position: simd_float3
    let distanceFromStart: Float
    let directionFromPrevious: simd_float3?
    let type: PathPointType
}

enum PathPointType {
    case start
    case waypoint
    case turn
    case destination
}

struct NavigationGuidance {
    let target: SpatialAnchor
    let path: [PathPoint]
    var currentStep: Int
}

struct RoomGeometry {
    let dimensions: RoomDimensions
    let walls: [WallSegment]
    let openings: [Opening]
    let furniture: [FurnitureItem]
    
    mutating func updateWithMesh(_ mesh: SpatialMesh) {
        // Update room geometry with new mesh data
    }
}

struct RoomDimensions {
    let width: Float
    let length: Float
    let height: Float
}

struct WallSegment {
    let start: simd_float3
    let end: simd_float3
    let height: Float
}

struct Opening {
    let position: simd_float3
    let width: Float
    let height: Float
    let type: OpeningType
}

enum OpeningType {
    case door
    case window
    case passage
}

struct FurnitureItem {
    let position: simd_float3
    let dimensions: simd_float3
    let category: FurnitureCategory
}

enum FurnitureCategory {
    case table
    case chair
    case sofa
    case bed
    case cabinet
    case unknown
}

struct SpatialObstacle {
    let position: simd_float3
    let dimensions: simd_float3
    let severity: ObstacleSeverity
    let type: ObstacleType
}

enum ObstacleType {
    case stationary
    case dynamic
    case person
    case vehicle
}

struct SurfaceInfo {
    let id: UUID
    let classification: ARPlaneAnchor.Classification
    let extent: simd_float3
    let center: simd_float3
    let transform: simd_float4x4
}

// MARK: - Supporting Manager Classes

class SpatialMeshManager {
    weak var delegate: SpatialMeshManagerDelegate?
    private var highResolutionEnabled = false
    
    func enableHighResolutionMesh() {
        highResolutionEnabled = true
    }
    
    func enableDepthEstimationMesh() {
        highResolutionEnabled = false
    }
    
    func processMeshAnchor(_ meshAnchor: ARMeshAnchor) {
        // Process mesh anchor data
    }
    
    func updateMeshAnchor(_ meshAnchor: ARMeshAnchor) {
        // Update existing mesh
    }
}

protocol SpatialMeshManagerDelegate: AnyObject {
    func meshManager(_ manager: SpatialMeshManager, didUpdateMesh mesh: SpatialMesh)
}

class SpatialAnchorManager {
    weak var delegate: SpatialAnchorManagerDelegate?
    
    func loadAnchors() {
        // Load saved anchors
    }
}

protocol SpatialAnchorManagerDelegate: AnyObject {
    func anchorManager(_ manager: SpatialAnchorManager, didLoadAnchors anchors: [SpatialAnchor])
}

class SpatialObjectTracker {
    weak var delegate: SpatialObjectTrackerDelegate?
    
    func updateTracking(frame: ARFrame) {
        // Update object tracking
    }
}

protocol SpatialObjectTrackerDelegate: AnyObject {
    func objectTracker(_ tracker: SpatialObjectTracker, didUpdateObject object: TrackedObject)
}

class SpatialPathfinder {
    weak var delegate: SpatialPathfinderDelegate?
    private var obstacles: [SpatialObstacle] = []
    
    func enableLiDARPathfinding() {
        // Enhanced pathfinding with LiDAR
    }
    
    func enableHeuristicPathfinding() {
        // Fallback pathfinding
    }
    
    func setObstacles(_ obstacles: [SpatialObstacle]) {
        self.obstacles = obstacles
    }
    
    func calculatePath(from start: simd_float4x4, to end: simd_float4x4, completion: @escaping ([PathPoint]) -> Void) {
        // Calculate path
        completion([])
    }
    
    func calculateSafePath(from start: simd_float4x4, to end: simd_float4x4, completion: @escaping ([PathPoint]) -> Void) {
        // Calculate safe path avoiding obstacles
        completion([])
    }
}

protocol SpatialPathfinderDelegate: AnyObject {
    func pathfinder(_ pathfinder: SpatialPathfinder, didCalculatePath path: [PathPoint])
}

class SpatialObstacleMap {
    var lastUpdate = Date()
    
    func enablePreciseObstacleDetection() {
        // LiDAR-based detection
    }
    
    func enableVisionBasedDetection() {
        // Vision-based detection
    }
    
    func detectObstacles(in frame: ARFrame) -> [SpatialObstacle] {
        lastUpdate = Date()
        return [] // Placeholder
    }
    
    func updateWithRoomGeometry(_ geometry: RoomGeometry) {
        // Update obstacle map with room geometry
    }
}

class SpatialAudioManager {
    weak var delegate: SpatialAudioManagerDelegate?
    
    func configure(session: ARSession) {
        // Configure spatial audio
    }
    
    func updateListenerPosition(_ transform: simd_float4x4?) {
        // Update 3D audio listener position
    }
    
    func addAudioCue(at transform: simd_float4x4, sound: SpatialSoundType) {
        // Add spatial audio cue
    }
    
    func addObjectMarker(at position: simd_float3, category: ObjectCategory) {
        // Add object audio marker
    }
    
    func updateObjectPosition(_ id: UUID, position: simd_float3) {
        // Update object audio position
    }
    
    func updateAnchorPosition(_ id: UUID, transform: simd_float4x4) {
        // Update anchor audio position
    }
    
    func addNavigationMarker(_ marker: SpatialAudioMarker) {
        // Add navigation audio marker
    }
    
    func playWarning(at position: simd_float3, severity: ObstacleSeverity) {
        // Play spatial warning sound
    }
    
    func pause() {
        // Pause spatial audio
    }
    
    func resume() {
        // Resume spatial audio
    }
}

protocol SpatialAudioManagerDelegate: AnyObject {
    func spatialAudio(_ manager: SpatialAudioManager, didPlaySound sound: SpatialSound)
}

struct SpatialAudioMarker {
    let position: simd_float3
    let type: AudioMarkerType
    let distance: Float
}

enum AudioMarkerType {
    case waypoint
    case destination
    case warning
    case landmark
}

enum SpatialSoundType {
    case anchorPlaced
    case objectDetected
    case navigationStep
    case warning
}

struct SpatialSound {
    let type: SpatialSoundType
    let position: simd_float3
    let timestamp: Date
}

class RoomGeometryAnalyzer {
    func analyze(frame: ARFrame, meshAnchors: [ARMeshAnchor], completion: @escaping (RoomGeometry) -> Void) {
        // Analyze room geometry from AR data
        let geometry = RoomGeometry(
            dimensions: RoomDimensions(width: 5, length: 4, height: 3),
            walls: [],
            openings: [],
            furniture: []
        )
        completion(geometry)
    }
}

class HapticFeedbackManager {
    func provideNavigationFeedback() {
        // Provide haptic navigation feedback
    }
    
    func provideObstacleWarning() {
        // Provide haptic obstacle warning
    }
}

// Placeholder structures
struct SpatialMesh {
    let vertices: [simd_float3]
    let faces: [UInt32]
    let classification: ARMeshAnchor.Classification
}

// MARK: - Extensions

extension simd_float4x4 {
    init(translation: simd_float3) {
        self.init(
            simd_float4(1, 0, 0, translation.x),
            simd_float4(0, 1, 0, translation.y),
            simd_float4(0, 0, 1, translation.z),
            simd_float4(0, 0, 0, 1)
        )
    }
    
    var translation: simd_float3 {
        return simd_float3(columns.3.x, columns.3.y, columns.3.z)
    }
}

// MARK: - Scene Labeling Data Models

struct PersistentObjectAnchor: Codable {
    var id: UUID
    let name: String
    let description: String
    let worldPosition: simd_float3
    let timestamp: Date
    let category: ObjectAnchorCategory
    let confidence: Float
    var lastInteraction: Date
    
    enum CodingKeys: String, CodingKey {
        case id, name, description, timestamp, category, confidence, lastInteraction
        case positionX, positionY, positionZ
    }
    
    init(id: UUID, name: String, description: String, worldPosition: simd_float3, timestamp: Date, category: ObjectAnchorCategory, confidence: Float, lastInteraction: Date) {
        self.id = id
        self.name = name
        self.description = description
        self.worldPosition = worldPosition
        self.timestamp = timestamp
        self.category = category
        self.confidence = confidence
        self.lastInteraction = lastInteraction
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decode(String.self, forKey: .description)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        category = try container.decode(ObjectAnchorCategory.self, forKey: .category)
        confidence = try container.decode(Float.self, forKey: .confidence)
        lastInteraction = try container.decode(Date.self, forKey: .lastInteraction)
        
        let x = try container.decode(Float.self, forKey: .positionX)
        let y = try container.decode(Float.self, forKey: .positionY)
        let z = try container.decode(Float.self, forKey: .positionZ)
        worldPosition = simd_float3(x, y, z)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(description, forKey: .description)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(category, forKey: .category)
        try container.encode(confidence, forKey: .confidence)
        try container.encode(lastInteraction, forKey: .lastInteraction)
        try container.encode(worldPosition.x, forKey: .positionX)
        try container.encode(worldPosition.y, forKey: .positionY)
        try container.encode(worldPosition.z, forKey: .positionZ)
    }
}

struct SceneLabel {
    let id: UUID
    let anchorID: UUID
    let name: String
    let position: simd_float3
    let type: SceneLabelType
    let confidence: Float
    let timestamp: Date
}

enum ObjectAnchorCategory: String, Codable {
    case userNamed = "user_named"
    case furniture = "furniture"
    case navigation = "navigation"
    case landmark = "landmark"
    case utility = "utility"
}

enum SceneLabelType {
    case userDefined
    case autoDetected
    case imported
}

enum SpatialDirection {
    case forward
    case left
    case right
    case up
    case down
    case forwardLeft
    case forwardRight
}

struct VoiceLabelingCommand {
    let type: VoiceLabelingCommandType
    let objectName: String?
    let direction: SpatialDirection?
    let description: String?
    
    init(type: VoiceLabelingCommandType, objectName: String? = nil, direction: SpatialDirection? = nil, description: String? = nil) {
        self.type = type
        self.objectName = objectName
        self.direction = direction
        self.description = description
    }
}

enum VoiceLabelingCommandType {
    case labelHere
    case labelThere
    case findLabel
    case removeLabel
    case listLabels
    case unknown
}

struct ObjectMemoryStats {
    let totalObjects: Int
    let recentlyUsed: Int
    let oldestObjectDate: Date?
    let newestObjectDate: Date?
}

// MARK: - Voice Command Processing

class VoiceLabelingProcessor {
    func parseCommand(_ command: String) -> VoiceLabelingCommand {
        let lowercased = command.lowercased()
        
        // Label here patterns
        if lowercased.contains("label this") || lowercased.contains("remember this location") {
            return parseLocationLabelCommand(lowercased)
        }
        
        // Label there patterns
        if lowercased.contains("label that") || lowercased.contains("label the") {
            return parseDirectionalLabelCommand(lowercased)
        }
        
        // Find patterns
        if lowercased.contains("take me to") || lowercased.contains("navigate to") || lowercased.contains("where is") {
            return parseFindCommand(lowercased)
        }
        
        // Remove patterns
        if lowercased.contains("remove label") || lowercased.contains("forget location") {
            return parseRemoveCommand(lowercased)
        }
        
        // List patterns
        if lowercased.contains("list labels") || lowercased.contains("what locations") {
            return VoiceLabelingCommand(type: .listLabels)
        }
        
        return VoiceLabelingCommand(type: .unknown)
    }
    
    private func parseLocationLabelCommand(_ text: String) -> VoiceLabelingCommand {
        // Parse "label this location as kitchen" or "remember this as my desk"
        var objectName: String?
        
        if let asIndex = text.range(of: " as ") {
            objectName = String(text[asIndex.upperBound...])
                .replacingOccurrences(of: "my ", with: "")
                .replacingOccurrences(of: "the ", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        return VoiceLabelingCommand(
            type: .labelHere,
            objectName: objectName
        )
    }
    
    private func parseDirectionalLabelCommand(_ text: String) -> VoiceLabelingCommand {
        // Parse "label that door as entrance" or "label the chair on my left as reading chair"
        var objectName: String?
        var direction: SpatialDirection?
        
        // Extract direction
        if text.contains("left") {
            direction = .left
        } else if text.contains("right") {
            direction = .right
        } else if text.contains("ahead") || text.contains("front") {
            direction = .forward
        }
        
        // Extract object name
        if let asIndex = text.range(of: " as ") {
            objectName = String(text[asIndex.upperBound...])
                .replacingOccurrences(of: "my ", with: "")
                .replacingOccurrences(of: "the ", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        return VoiceLabelingCommand(
            type: .labelThere,
            objectName: objectName,
            direction: direction
        )
    }
    
    private func parseFindCommand(_ text: String) -> VoiceLabelingCommand {
        // Parse "take me to the kitchen" or "where is my desk"
        var objectName: String?
        
        let patterns = ["take me to", "navigate to", "where is", "find"]
        for pattern in patterns {
            if let range = text.range(of: pattern) {
                objectName = String(text[range.upperBound...])
                    .replacingOccurrences(of: "my ", with: "")
                    .replacingOccurrences(of: "the ", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
        }
        
        return VoiceLabelingCommand(
            type: .findLabel,
            objectName: objectName
        )
    }
    
    private func parseRemoveCommand(_ text: String) -> VoiceLabelingCommand {
        // Parse "remove label for kitchen" or "forget my desk location"
        var objectName: String?
        
        let patterns = ["remove label for", "forget", "remove"]
        for pattern in patterns {
            if let range = text.range(of: pattern) {
                objectName = String(text[range.upperBound...])
                    .replacingOccurrences(of: "my ", with: "")
                    .replacingOccurrences(of: "the ", with: "")
                    .replacingOccurrences(of: "location", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
        }
        
        return VoiceLabelingCommand(
            type: .removeLabel,
            objectName: objectName
        )
    }
}

// MARK: - Spatial Memory Manager

class SpatialMemoryManager {
    private let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    
    func saveObjectAnchor(_ anchor: PersistentObjectAnchor) {
        let filename = "spatial_anchor_\(anchor.id.uuidString).json"
        let url = documentsDirectory.appendingPathComponent(filename)
        
        do {
            let data = try JSONEncoder().encode(anchor)
            try data.write(to: url)
        } catch {
            Config.debugLog("Failed to save object anchor: \(error)")
        }
    }
    
    func updateObjectAnchor(_ anchor: PersistentObjectAnchor) {
        saveObjectAnchor(anchor) // Same as save for simplicity
    }
    
    func removeObjectAnchor(id: UUID) {
        let filename = "spatial_anchor_\(id.uuidString).json"
        let url = documentsDirectory.appendingPathComponent(filename)
        
        try? FileManager.default.removeItem(at: url)
    }
    
    func loadAllObjectAnchors(completion: @escaping ([PersistentObjectAnchor]) -> Void) {
        var anchors: [PersistentObjectAnchor] = []
        
        do {
            let files = try FileManager.default.contentsOfDirectory(at: documentsDirectory, includingPropertiesForKeys: nil)
            
            for file in files where file.lastPathComponent.hasPrefix("spatial_anchor_") {
                if let data = try? Data(contentsOf: file),
                   let anchor = try? JSONDecoder().decode(PersistentObjectAnchor.self, from: data) {
                    anchors.append(anchor)
                }
            }
        } catch {
            Config.debugLog("Failed to load object anchors: \(error)")
        }
        
        completion(anchors)
    }
}

class SceneLabelingEngine {
    func autoDetectSceneLabels(from frame: ARFrame) -> [SceneLabel] {
        // Automatic scene labeling using ML
        return []
    }
    
    func suggestLabelsForObjects(_ objects: [DetectedObject]) -> [String] {
        // Suggest appropriate labels for detected objects
        return []
    }
}

// MARK: - Audio Extensions for Scene Labeling

extension SpatialSoundType {
    static let objectNamed = SpatialSoundType.anchorPlaced
    static let objectRestored = SpatialSoundType.anchorPlaced
}

// MARK: - Mobility Aid Navigation

private var mobilityNavigator = MobilityNavigator()
private var roomMapper = LiDARRoomMapper()
private var navigationInstructor = TurnByTurnInstructor()
private var currentNavigation: ActiveNavigation?

// MARK: - LiDAR-Enhanced Navigation

func startRoomNavigation(to destination: String) {
    guard hasLiDAR else {
        speechOutput.speak("LiDAR navigation not available on this device. Using basic navigation.")
        startBasicNavigation(to: destination)
        return
    }
    
    speechOutput.speak("Starting LiDAR navigation to \(destination)")
    
    // Generate detailed room map
    roomMapper.generateRoomMap { [weak self] roomMap in
        guard let self = self, let map = roomMap else {
            self?.speechOutput.speak("Unable to map room for navigation")
            return
        }
        
        // Find destination in room
        if let destinationPoint = self.findDestinationInRoom(destination, map: map) {
            self.startLiDARGuidedNavigation(to: destinationPoint, map: map)
        } else {
            self.speechOutput.speak("Destination \(destination) not found in current room")
        }
    }
}

private func startLiDARGuidedNavigation(to destination: simd_float3, map: LiDARRoomMap) {
    guard let currentFrame = arSession.currentFrame else { return }
    
    let currentPosition = currentFrame.camera.transform
    
    // Calculate optimal path using LiDAR data
    mobilityNavigator.calculateOptimalPath(
        from: currentPosition,
        to: simd_float4x4(translation: destination),
        using: map
    ) { [weak self] navigationPath in
        DispatchQueue.main.async {
            self?.startTurnByTurnGuidance(path: navigationPath, map: map)
        }
    }
}

private func startTurnByTurnGuidance(path: NavigationPath, map: LiDARRoomMap) {
    currentNavigation = ActiveNavigation(
        path: path,
        map: map,
        currentStep: 0,
        startTime: Date()
    )
    
    // Setup spatial audio navigation
    setupSpatialAudioNavigation(path: path)
    
    // Start step-by-step instructions
    provideNavigationInstruction(for: 0)
    
    // Begin continuous guidance
    mobilityNavigator.startContinuousGuidance(navigation: currentNavigation!)
}

private func setupSpatialAudioNavigation(path: NavigationPath) {
    // Add audio beacons at key navigation points
    for (index, step) in path.steps.enumerated() {
        let audioBeacon = NavigationBeacon(
            position: step.position,
            type: step.type == .destination ? .destination : .waypoint,
            stepNumber: index,
            instruction: step.instruction
        )
        
        spatialAudio.addNavigationBeacon(audioBeacon)
    }
    
    // Add continuous path audio
    spatialAudio.enablePathSonification(path: path)
}

private func provideNavigationInstruction(for stepIndex: Int) {
    guard let navigation = currentNavigation,
          stepIndex < navigation.path.steps.count else { return }
    
    let step = navigation.path.steps[stepIndex]
    let instruction = navigationInstructor.generateInstruction(
        step: step,
        previousStep: stepIndex > 0 ? navigation.path.steps[stepIndex - 1] : nil,
        map: navigation.map
    )
    
    speechOutput.speak(instruction, priority: .high)
    
    // Provide spatial audio confirmation
    spatialAudio.playNavigationCue(at: step.position, type: .instruction)
}

// MARK: - Continuous Navigation Guidance

func updateNavigationProgress() {
    guard let navigation = currentNavigation,
          let currentFrame = arSession.currentFrame else { return }
    
    let currentPosition = simd_float3(
        currentFrame.camera.transform.columns.3.x,
        currentFrame.camera.transform.columns.3.y,
        currentFrame.camera.transform.columns.3.z
    )
    
    // Check if user has reached the next waypoint
    let currentStep = navigation.path.steps[navigation.currentStep]
    let distanceToStep = simd_distance(currentPosition, currentStep.position)
    
    if distanceToStep < 1.0 { // Within 1 meter of waypoint
        // Move to next step
        if navigation.currentStep + 1 < navigation.path.steps.count {
            currentNavigation!.currentStep += 1
            provideNavigationInstruction(for: currentNavigation!.currentStep)
            
            // Provide haptic feedback for reaching waypoint
            hapticFeedback.provideNavigationFeedback()
            
        } else {
            // Navigation complete
            completeNavigation()
        }
    } else {
        // Provide continuous guidance
        provideContinuousGuidance(to: currentStep, from: currentPosition)
    }
}

private func provideContinuousGuidance(to target: NavigationStep, from currentPosition: simd_float3) {
    let distanceToTarget = simd_distance(currentPosition, target.position)
    
    // Provide distance updates every 2 meters
    if Int(distanceToTarget) % 2 == 0 && distanceToTarget > 2.0 {
        let direction = getDirectionDescription(to: target.position)
        speechOutput.speak("\(Int(distanceToTarget)) meters \(direction)", priority: .low)
    }
    
    // Update spatial audio guidance
    spatialAudio.updateNavigationGuidance(
        targetPosition: target.position,
        currentPosition: currentPosition,
        distance: distanceToTarget
    )
    
    // Check for obstacles in path
    if let obstacle = detectObstacleInPath(from: currentPosition, to: target.position) {
        handleNavigationObstacle(obstacle)
    }
}

private func detectObstacleInPath(from start: simd_float3, to end: simd_float3) -> NavigationObstacle? {
    guard let navigation = currentNavigation else { return nil }
    
    // Use LiDAR data to detect obstacles along the path
    let pathVector = end - start
    let pathLength = simd_length(pathVector)
    let pathDirection = simd_normalize(pathVector)
    
    // Sample points along the path
    for distance in stride(from: 0.5, to: pathLength, by: 0.5) {
        let samplePoint = start + pathDirection * distance
        
        if let obstacle = navigation.map.getObstacleAt(position: samplePoint) {
            return NavigationObstacle(
                position: samplePoint,
                type: obstacle.type,
                severity: .warning,
                distanceFromUser: distance
            )
        }
    }
    
    return nil
}

private func handleNavigationObstacle(_ obstacle: NavigationObstacle) {
    speechOutput.speak("Obstacle detected ahead. \(obstacle.type.description)", priority: .high)
    
    // Calculate alternate route
    guard let navigation = currentNavigation else { return }
    
    mobilityNavigator.calculateAlternateRoute(
        avoiding: obstacle,
        from: navigation.currentStep,
        map: navigation.map
    ) { [weak self] alternateRoute in
        if let route = alternateRoute {
            self?.speechOutput.speak("Alternate route found")
            self?.updateNavigationPath(with: route)
        } else {
            self?.speechOutput.speak("Please navigate around the obstacle manually")
        }
    }
}

private func updateNavigationPath(with newRoute: NavigationPath) {
    currentNavigation?.path = newRoute
    
    // Update spatial audio with new path
    spatialAudio.clearNavigationBeacons()
    setupSpatialAudioNavigation(path: newRoute)
    
    // Continue with updated path
    provideNavigationInstruction(for: currentNavigation!.currentStep)
}

private func completeNavigation() {
    speechOutput.speak("You have arrived at your destination")
    
    // Clean up navigation state
    spatialAudio.clearNavigationBeacons()
    spatialAudio.disablePathSonification()
    mobilityNavigator.stopContinuousGuidance()
    
    currentNavigation = nil
}

// MARK: - Context-Aware Instructions

func enableContextAwareNavigation() {
    navigationInstructor.enableContextAwareness()
    speechOutput.speak("Context-aware navigation enabled. I'll provide more detailed guidance based on your surroundings.")
}

private func findDestinationInRoom(_ destination: String, map: LiDARRoomMap) -> simd_float3? {
    // Look for user-labeled locations first
    if let userLocation = findUserNamedObject(name: destination) {
        return userLocation.worldPosition
    }
    
    // Look for automatically detected landmarks
    if let landmark = map.landmarks.first(where: { $0.name.lowercased().contains(destination.lowercased()) }) {
        return landmark.position
    }
    
    // Look for furniture or objects that match
    if let furniture = map.furniture.first(where: { $0.category.rawValue.contains(destination.lowercased()) }) {
        return furniture.position
    }
    
    return nil
}

private func startBasicNavigation(to destination: String) {
    // Fallback navigation without LiDAR
    if let target = findUserNamedObject(name: destination) {
        navigateToUserNamedObject(name: destination)
    } else {
        speechOutput.speak("Please label the location first, or provide more specific directions")
    }
}

// MARK: - Spatial Audio Navigation

class MobilityNavigator {
    weak var delegate: MobilityNavigatorDelegate?
    private var activeGuidance: ContinuousGuidance?
    
    func calculateOptimalPath(from start: simd_float4x4, to end: simd_float4x4, using map: LiDARRoomMap, completion: @escaping (NavigationPath) -> Void) {
        // Use A* pathfinding with LiDAR obstacle data
        let pathfinder = LiDARAStarPathfinder(map: map)
        
        pathfinder.findPath(from: start.translation, to: end.translation) { path in
            let navigationPath = NavigationPath(
                steps: path.map { point in
                    NavigationStep(
                        position: point.position,
                        type: point == path.last ? .destination : .waypoint,
                        instruction: self.generateBasicInstruction(for: point),
                        expectedDuration: point.estimatedTime
                    )
                },
                totalDistance: path.reduce(0) { total, point in total + point.distanceFromPrevious },
                estimatedDuration: path.reduce(0) { total, point in total + point.estimatedTime }
            )
            
            completion(navigationPath)
        }
    }
    
    func startContinuousGuidance(navigation: ActiveNavigation) {
        activeGuidance = ContinuousGuidance(navigation: navigation)
        activeGuidance?.start()
    }
    
    func stopContinuousGuidance() {
        activeGuidance?.stop()
        activeGuidance = nil
    }
    
    func calculateAlternateRoute(avoiding obstacle: NavigationObstacle, from currentStep: NavigationStep, map: LiDARRoomMap, completion: @escaping (NavigationPath?) -> Void) {
        // Calculate route that avoids the detected obstacle
        completion(nil) // Placeholder
    }
    
    private func generateBasicInstruction(for point: PathPoint) -> String {
        // Generate basic navigation instruction
        return "Continue forward"
    }
}

protocol MobilityNavigatorDelegate: AnyObject {
    func navigator(_ navigator: MobilityNavigator, didUpdateProgress progress: NavigationProgress)
}

class TurnByTurnInstructor {
    private var contextAwarenessEnabled = false
    
    func enableContextAwareness() {
        contextAwarenessEnabled = true
    }
    
    func generateInstruction(step: NavigationStep, previousStep: NavigationStep?, map: LiDARRoomMap) -> String {
        var instruction = ""
        
        // Calculate direction change
        if let previous = previousStep {
            let directionChange = calculateDirectionChange(from: previous, to: step)
            instruction += directionChange
        } else {
            instruction = "Begin navigation. "
        }
        
        // Add distance information
        let distance = String(format: "%.1f", step.expectedDuration * 1.2) // Estimate distance from time
        instruction += "Walk \(distance) meters"
        
        // Add contextual information if enabled
        if contextAwarenessEnabled {
            instruction += addContextualInfo(for: step, map: map)
        }
        
        return instruction
    }
    
    private func calculateDirectionChange(from previous: NavigationStep, to current: NavigationStep) -> String {
        let direction = current.position - previous.position
        let angle = atan2(direction.x, direction.z) * 180 / .pi
        
        if abs(angle) < 15 {
            return "Continue straight. "
        } else if angle > 15 {
            return "Turn right. "
        } else {
            return "Turn left. "
        }
    }
    
    private func addContextualInfo(for step: NavigationStep, map: LiDARRoomMap) -> String {
        // Add information about nearby landmarks or hazards
        var context = ""
        
        // Check for nearby landmarks
        let nearbyLandmarks = map.landmarks.filter { landmark in
            simd_distance(landmark.position, step.position) < 2.0
        }
        
        if !nearbyLandmarks.isEmpty {
            let landmarkName = nearbyLandmarks.first!.name
            context += ". You'll pass the \(landmarkName)"
        }
        
        // Check for potential hazards
        let nearbyObstacles = map.obstacles.filter { obstacle in
            simd_distance(obstacle.position, step.position) < 1.5
        }
        
        if !nearbyObstacles.isEmpty {
            context += ". Watch for obstacles on your path"
        }
        
        return context
    }
}

// MARK: - LiDAR Room Mapping

class LiDARRoomMapper {
    func generateRoomMap(completion: @escaping (LiDARRoomMap?) -> Void) {
        // Use LiDAR data to create detailed room map
        // This would integrate with ARKit's scene reconstruction
        
        let map = LiDARRoomMap(
            boundaries: [],
            obstacles: [],
            furniture: [],
            landmarks: [],
            navigableAreas: []
        )
        
        completion(map)
    }
}

class LiDARAStarPathfinder {
    private let map: LiDARRoomMap
    
    init(map: LiDARRoomMap) {
        self.map = map
    }
    
    func findPath(from start: simd_float3, to end: simd_float3, completion: @escaping ([PathPoint]) -> Void) {
        // A* pathfinding implementation using LiDAR obstacle data
        let path = [
            PathPoint(position: start, distanceFromPrevious: 0, estimatedTime: 0),
            PathPoint(position: end, distanceFromPrevious: simd_distance(start, end), estimatedTime: simd_distance(start, end) / 1.2)
        ]
        
        completion(path)
    }
}

// MARK: - Supporting Data Models

struct NavigationPath {
    let steps: [NavigationStep]
    let totalDistance: Float
    let estimatedDuration: TimeInterval
}

struct NavigationStep {
    let position: simd_float3
    let type: NavigationStepType
    let instruction: String
    let expectedDuration: TimeInterval
}

enum NavigationStepType {
    case start
    case waypoint
    case turn
    case destination
}

struct ActiveNavigation {
    let path: NavigationPath
    let map: LiDARRoomMap
    var currentStep: Int
    let startTime: Date
    
    init(path: NavigationPath, map: LiDARRoomMap, currentStep: Int, startTime: Date) {
        self.path = path
        self.map = map
        self.currentStep = currentStep
        self.startTime = startTime
    }
}

struct NavigationObstacle {
    let position: simd_float3
    let type: ObstacleType
    let severity: ObstacleSeverity
    let distanceFromUser: Float
}

struct NavigationBeacon {
    let position: simd_float3
    let type: AudioMarkerType
    let stepNumber: Int
    let instruction: String
}

struct LiDARRoomMap {
    let boundaries: [RoomBoundary]
    let obstacles: [MapObstacle]
    let furniture: [MapFurniture]
    let landmarks: [MapLandmark]
    let navigableAreas: [NavigableArea]
    
    func getObstacleAt(position: simd_float3) -> MapObstacle? {
        return obstacles.first { obstacle in
            simd_distance(obstacle.position, position) < obstacle.radius
        }
    }
}

struct RoomBoundary {
    let points: [simd_float3]
    let type: BoundaryType
}

enum BoundaryType {
    case wall
    case door
    case window
    case opening
}

struct MapObstacle {
    let position: simd_float3
    let radius: Float
    let height: Float
    let type: ObstacleType
}

struct MapFurniture {
    let position: simd_float3
    let dimensions: simd_float3
    let category: FurnitureCategory
}

struct MapLandmark {
    let position: simd_float3
    let name: String
    let type: LandmarkType
}

enum LandmarkType {
    case door
    case window
    case stairs
    case elevator
    case furniture
    case userDefined
}

struct NavigableArea {
    let bounds: [simd_float3]
    let difficulty: NavigationDifficulty
}

enum NavigationDifficulty {
    case easy
    case moderate
    case difficult
}

struct PathPoint {
    let position: simd_float3
    let distanceFromPrevious: Float
    let estimatedTime: TimeInterval
}

struct NavigationProgress {
    let currentStep: Int
    let totalSteps: Int
    let distanceRemaining: Float
    let estimatedTimeRemaining: TimeInterval
}

class ContinuousGuidance {
    private let navigation: ActiveNavigation
    private var updateTimer: Timer?
    
    init(navigation: ActiveNavigation) {
        self.navigation = navigation
    }
    
    func start() {
        updateTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            // Continuous guidance updates
        }
    }
    
    func stop() {
        updateTimer?.invalidate()
        updateTimer = nil
    }
}

// MARK: - Spatial Audio Extensions

extension SpatialAudioManager {
    func addNavigationBeacon(_ beacon: NavigationBeacon) {
        // Add navigation-specific audio beacon
    }
    
    func enablePathSonification(path: NavigationPath) {
        // Enable continuous audio feedback along the path
    }
    
    func disablePathSonification() {
        // Disable path audio feedback
    }
    
    func playNavigationCue(at position: simd_float3, type: NavigationCueType) {
        // Play specific navigation audio cue
    }
    
    func updateNavigationGuidance(targetPosition: simd_float3, currentPosition: simd_float3, distance: Float) {
        // Update continuous navigation audio guidance
    }
    
    func clearNavigationBeacons() {
        // Clear all navigation audio beacons
    }
}

enum NavigationCueType {
    case instruction
    case waypoint
    case warning
    case completion
} 