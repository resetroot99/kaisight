import Foundation
import ARKit
import SceneKit
import CoreLocation
import Combine

class SpatialMappingManager: NSObject, ObservableObject {
    @Published var isARActive = false
    @Published var spatialAnchors: [SpatialAnchor] = []
    @Published var roomLayout: RoomLayout?
    @Published var detectedSurfaces: [DetectedSurface] = []
    @Published var spatialDescription = ""
    
    private var arSession: ARSession?
    private var arConfiguration: ARWorldTrackingConfiguration?
    private let speechOutput = SpeechOutput()
    
    // Spatial mapping settings
    private var lastSpatialUpdate = Date.distantPast
    private let spatialUpdateInterval: TimeInterval = 2.0
    private var anchorUpdateTimer: Timer?
    
    // Room analysis
    private var walls: [DetectedSurface] = []
    private var floor: DetectedSurface?
    private var ceiling: DetectedSurface?
    private var furniture: [SpatialObject] = []
    
    override init() {
        super.init()
        setupARSession()
    }
    
    deinit {
        stopSpatialMapping()
    }
    
    // MARK: - AR Session Setup
    
    private func setupARSession() {
        guard ARWorldTrackingConfiguration.isSupported else {
            Config.debugLog("ARKit not supported on this device")
            return
        }
        
        arSession = ARSession()
        arSession?.delegate = self
        
        arConfiguration = ARWorldTrackingConfiguration()
        arConfiguration?.planeDetection = [.horizontal, .vertical]
        arConfiguration?.sceneReconstruction = .meshWithClassification
        arConfiguration?.frameSemantics = .sceneDepth
        
        // Enable object detection if available
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification) {
            arConfiguration?.sceneReconstruction = .meshWithClassification
        }
    }
    
    func startSpatialMapping() {
        guard let session = arSession, let config = arConfiguration else {
            speechOutput.speak("Spatial mapping not available on this device")
            return
        }
        
        isARActive = true
        session.run(config, options: [.resetTracking, .removeExistingAnchors])
        
        // Start periodic spatial analysis
        anchorUpdateTimer = Timer.scheduledTimer(withTimeInterval: spatialUpdateInterval, repeats: true) { _ in
            self.analyzeSpatialEnvironment()
        }
        
        speechOutput.speak("Spatial mapping started. I'll describe the 3D layout of your environment.")
        Config.debugLog("ARKit spatial mapping started")
    }
    
    func stopSpatialMapping() {
        guard let session = arSession else { return }
        
        isARActive = false
        session.pause()
        anchorUpdateTimer?.invalidate()
        anchorUpdateTimer = nil
        
        speechOutput.speak("Spatial mapping stopped")
        Config.debugLog("ARKit spatial mapping stopped")
    }
    
    // MARK: - Spatial Analysis
    
    private func analyzeSpatialEnvironment() {
        guard let session = arSession,
              let currentFrame = session.currentFrame else { return }
        
        let now = Date()
        guard now.timeIntervalSince(lastSpatialUpdate) >= spatialUpdateInterval else { return }
        lastSpatialUpdate = now
        
        // Analyze detected planes and objects
        analyzeDetectedPlanes(currentFrame.anchors)
        analyzeRoomGeometry()
        generateSpatialDescription()
    }
    
    private func analyzeDetectedPlanes(_ anchors: [ARAnchor]) {
        var newSurfaces: [DetectedSurface] = []
        var newWalls: [DetectedSurface] = []
        var newFloor: DetectedSurface?
        
        for anchor in anchors {
            if let planeAnchor = anchor as? ARPlaneAnchor {
                let surface = DetectedSurface(
                    id: anchor.identifier,
                    type: classifyPlane(planeAnchor),
                    center: planeAnchor.center,
                    extent: planeAnchor.extent,
                    transform: planeAnchor.transform,
                    confidence: calculatePlaneConfidence(planeAnchor)
                )
                
                newSurfaces.append(surface)
                
                switch surface.type {
                case .wall:
                    newWalls.append(surface)
                case .floor:
                    if newFloor == nil || surface.extent.x * surface.extent.z > (newFloor?.extent.x ?? 0) * (newFloor?.extent.z ?? 0) {
                        newFloor = surface
                    }
                case .ceiling:
                    ceiling = surface
                case .table, .unknown:
                    break
                }
            }
        }
        
        DispatchQueue.main.async {
            self.detectedSurfaces = newSurfaces
            self.walls = newWalls
            self.floor = newFloor
        }
    }
    
    private func classifyPlane(_ planeAnchor: ARPlaneAnchor) -> SurfaceType {
        let normal = planeAnchor.center
        let upVector = simd_float3(0, 1, 0)
        let forwardVector = simd_float3(0, 0, -1)
        
        let dotUp = abs(simd_dot(normal, upVector))
        let dotForward = abs(simd_dot(normal, forwardVector))
        
        if dotUp > 0.8 {
            return planeAnchor.center.y > 0 ? .ceiling : .floor
        } else if dotForward > 0.7 || planeAnchor.alignment == .vertical {
            return .wall
        } else {
            return .table
        }
    }
    
    private func calculatePlaneConfidence(_ planeAnchor: ARPlaneAnchor) -> Float {
        let area = planeAnchor.extent.x * planeAnchor.extent.z
        let minArea: Float = 0.5 // Minimum area to be considered reliable
        let maxArea: Float = 20.0 // Large area gets maximum confidence
        
        return min(1.0, max(0.1, (area - minArea) / (maxArea - minArea)))
    }
    
    private func analyzeRoomGeometry() {
        guard !walls.isEmpty, let floor = floor else { return }
        
        // Calculate room dimensions
        let roomBounds = calculateRoomBounds()
        let roomArea = floor.extent.x * floor.extent.z
        
        // Detect doorways and openings
        let openings = detectOpenings()
        
        // Create room layout
        let layout = RoomLayout(
            bounds: roomBounds,
            area: roomArea,
            walls: walls,
            floor: floor,
            ceiling: ceiling,
            openings: openings,
            furniture: furniture
        )
        
        DispatchQueue.main.async {
            self.roomLayout = layout
        }
    }
    
    private func calculateRoomBounds() -> RoomBounds {
        guard !walls.isEmpty else {
            return RoomBounds(width: 0, length: 0, height: 0)
        }
        
        var minX: Float = Float.greatestFiniteMagnitude
        var maxX: Float = -Float.greatestFiniteMagnitude
        var minZ: Float = Float.greatestFiniteMagnitude
        var maxZ: Float = -Float.greatestFiniteMagnitude
        var maxY: Float = 0
        
        for wall in walls {
            let center = wall.center
            let extent = wall.extent
            
            minX = min(minX, center.x - extent.x/2)
            maxX = max(maxX, center.x + extent.x/2)
            minZ = min(minZ, center.z - extent.z/2)
            maxZ = max(maxZ, center.z + extent.z/2)
            maxY = max(maxY, center.y + extent.y/2)
        }
        
        return RoomBounds(
            width: maxX - minX,
            length: maxZ - minZ,
            height: maxY
        )
    }
    
    private func detectOpenings() -> [RoomOpening] {
        var openings: [RoomOpening] = []
        
        // Analyze gaps between walls to detect doors and windows
        for i in 0..<walls.count {
            for j in (i+1)..<walls.count {
                let wall1 = walls[i]
                let wall2 = walls[j]
                
                if let opening = analyzeWallGap(wall1, wall2) {
                    openings.append(opening)
                }
            }
        }
        
        return openings
    }
    
    private func analyzeWallGap(_ wall1: DetectedSurface, _ wall2: DetectedSurface) -> RoomOpening? {
        let distance = simd_distance(wall1.center, wall2.center)
        let gapThreshold: Float = 1.0 // 1 meter gap suggests an opening
        
        if distance > gapThreshold && distance < 3.0 {
            let midpoint = (wall1.center + wall2.center) / 2
            let width = distance
            
            // Classify opening type based on height and width
            let openingType: OpeningType = width > 1.5 ? .doorway : .window
            
            return RoomOpening(
                type: openingType,
                center: midpoint,
                width: width,
                height: min(wall1.extent.y, wall2.extent.y)
            )
        }
        
        return nil
    }
    
    // MARK: - Spatial Anchoring
    
    func addSpatialAnchor(name: String, description: String, at position: simd_float3) {
        guard let session = arSession else { return }
        
        let anchor = ARAnchor(transform: simd_float4x4(
            simd_float4(1, 0, 0, position.x),
            simd_float4(0, 1, 0, position.y),
            simd_float4(0, 0, 1, position.z),
            simd_float4(0, 0, 0, 1)
        ))
        
        session.add(anchor: anchor)
        
        let spatialAnchor = SpatialAnchor(
            id: anchor.identifier,
            name: name,
            description: description,
            position: position,
            timestamp: Date()
        )
        
        spatialAnchors.append(spatialAnchor)
        speechOutput.speak("Spatial anchor '\(name)' added at current location")
        
        Config.debugLog("Added spatial anchor: \(name) at \(position)")
    }
    
    func findNearestAnchor(to position: simd_float3) -> SpatialAnchor? {
        var nearestAnchor: SpatialAnchor?
        var shortestDistance: Float = Float.greatestFiniteMagnitude
        
        for anchor in spatialAnchors {
            let distance = simd_distance(position, anchor.position)
            if distance < shortestDistance {
                shortestDistance = distance
                nearestAnchor = anchor
            }
        }
        
        return nearestAnchor
    }
    
    func getNavigationToAnchor(_ anchor: SpatialAnchor, from currentPosition: simd_float3) -> String {
        let direction = anchor.position - currentPosition
        let distance = simd_length(direction)
        
        let normalizedDirection = simd_normalize(direction)
        let directionDescription = getDirectionDescription(normalizedDirection)
        
        return "\(anchor.name) is \(formatDistance(distance)) \(directionDescription). \(anchor.description)"
    }
    
    // MARK: - Spatial Description Generation
    
    private func generateSpatialDescription() {
        guard let layout = roomLayout else {
            spatialDescription = "Analyzing room layout..."
            return
        }
        
        var description = "Room layout: "
        
        // Room size
        let bounds = layout.bounds
        description += "You're in a room approximately \(formatDimension(bounds.width)) wide by \(formatDimension(bounds.length)) long"
        
        if bounds.height > 0 {
            description += " with \(formatDimension(bounds.height)) high ceilings"
        }
        
        description += ". "
        
        // Walls and openings
        if layout.walls.count > 0 {
            description += "I detect \(layout.walls.count) walls"
            
            if !layout.openings.isEmpty {
                let doorways = layout.openings.filter { $0.type == .doorway }
                let windows = layout.openings.filter { $0.type == .window }
                
                if !doorways.isEmpty {
                    description += " with \(doorways.count) doorway\(doorways.count == 1 ? "" : "s")"
                }
                
                if !windows.isEmpty {
                    description += " and \(windows.count) window\(windows.count == 1 ? "" : "s")"
                }
            }
            
            description += ". "
        }
        
        // Furniture and objects
        if !layout.furniture.isEmpty {
            description += "Furniture detected: "
            let furnitureNames = layout.furniture.map { $0.name }
            description += furnitureNames.joined(separator: ", ")
            description += ". "
        }
        
        DispatchQueue.main.async {
            self.spatialDescription = description
        }
    }
    
    // MARK: - Utility Methods
    
    private func getDirectionDescription(_ direction: simd_float3) -> String {
        let angle = atan2(direction.x, -direction.z)
        let degrees = angle * 180 / .pi
        
        let normalizedDegrees = degrees < 0 ? degrees + 360 : degrees
        
        switch normalizedDegrees {
        case 0..<22.5, 337.5...360: return "north"
        case 22.5..<67.5: return "northeast"
        case 67.5..<112.5: return "east"
        case 112.5..<157.5: return "southeast"
        case 157.5..<202.5: return "south"
        case 202.5..<247.5: return "southwest"
        case 247.5..<292.5: return "west"
        case 292.5..<337.5: return "northwest"
        default: return "ahead"
        }
    }
    
    private func formatDistance(_ distance: Float) -> String {
        if distance < 1.0 {
            return "\(Int(distance * 100)) centimeters"
        } else {
            return String(format: "%.1f meters", distance)
        }
    }
    
    private func formatDimension(_ dimension: Float) -> String {
        return String(format: "%.1f meters", dimension)
    }
    
    // MARK: - Public Interface
    
    func getCurrentSpatialContext() -> String {
        guard let layout = roomLayout else {
            return "Room layout analysis in progress..."
        }
        
        return spatialDescription
    }
    
    func getAnchorsList() -> String {
        if spatialAnchors.isEmpty {
            return "No spatial anchors saved in this location."
        }
        
        var list = "Saved locations in this room: "
        for anchor in spatialAnchors {
            list += "\(anchor.name), "
        }
        
        return String(list.dropLast(2)) // Remove trailing comma
    }
    
    func speakSpatialContext() {
        let context = getCurrentSpatialContext()
        speechOutput.speak(context)
    }
}

// MARK: - ARSessionDelegate

extension SpatialMappingManager: ARSessionDelegate {
    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        Config.debugLog("ARKit added \(anchors.count) new anchors")
    }
    
    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        // Update spatial analysis when anchors are updated
        DispatchQueue.main.async {
            self.analyzeSpatialEnvironment()
        }
    }
    
    func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {
        Config.debugLog("ARKit removed \(anchors.count) anchors")
    }
    
    func session(_ session: ARSession, didFailWithError error: Error) {
        Config.debugLog("ARKit session failed: \(error)")
        speechOutput.speak("Spatial mapping encountered an error. Restarting...")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.startSpatialMapping()
        }
    }
}

// MARK: - Data Models

struct SpatialAnchor: Identifiable, Codable {
    let id: UUID
    let name: String
    let description: String
    let position: simd_float3
    let timestamp: Date
    
    init(id: UUID, name: String, description: String, position: simd_float3, timestamp: Date) {
        self.id = id
        self.name = name
        self.description = description
        self.position = position
        self.timestamp = timestamp
    }
}

struct DetectedSurface {
    let id: UUID
    let type: SurfaceType
    let center: simd_float3
    let extent: simd_float3
    let transform: simd_float4x4
    let confidence: Float
}

enum SurfaceType {
    case wall
    case floor
    case ceiling
    case table
    case unknown
}

struct RoomLayout {
    let bounds: RoomBounds
    let area: Float
    let walls: [DetectedSurface]
    let floor: DetectedSurface?
    let ceiling: DetectedSurface?
    let openings: [RoomOpening]
    let furniture: [SpatialObject]
}

struct RoomBounds {
    let width: Float
    let length: Float
    let height: Float
}

struct RoomOpening {
    let type: OpeningType
    let center: simd_float3
    let width: Float
    let height: Float
}

enum OpeningType {
    case doorway
    case window
}

struct SpatialObject {
    let name: String
    let type: ObjectType
    let position: simd_float3
    let bounds: simd_float3
}

enum ObjectType {
    case chair
    case table
    case sofa
    case bed
    case cabinet
    case unknown
}

// MARK: - Codable Extensions

extension simd_float3: Codable {
    public func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(x)
        try container.encode(y)
        try container.encode(z)
    }
    
    public init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        let x = try container.decode(Float.self)
        let y = try container.decode(Float.self)
        let z = try container.decode(Float.self)
        self.init(x, y, z)
    }
} 