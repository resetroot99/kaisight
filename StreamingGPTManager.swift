import Foundation
import UIKit
import Combine
import Vision

class StreamingGPTManager: ObservableObject {
    @Published var isStreaming = false
    @Published var currentResponse = ""
    @Published var narrationActive = false
    
    private let apiKey: String
    private let baseURL = "https://api.openai.com/v1"
    private var streamingTask: URLSessionDataTask?
    
    // Streaming configuration
    private let maxTokens = 500
    private let temperature: Double = 0.7
    private let model = "gpt-4o"
    
    // Real-time narration
    private var narrationTimer: Timer?
    private let narrationInterval: TimeInterval = 3.0
    private var lastNarrationTime: Date?
    
    // Context management
    private var environmentalContext = EnvironmentalContext()
    private var narrativeHistory: [NarrativeEntry] = []
    
    // Dependencies
    private let speechOutput = SpeechOutput()
    private let cameraManager = CameraManager()
    
    // Memory-Aware Context Management
    private var sceneMemory: [SceneMemory] = []
    private let maxSceneMemory = 5
    private var lastSceneHash: String?
    private var changeDetector = SceneChangeDetector()
    
    init() {
        self.apiKey = Config.openAIAPIKey
        setupStreamingManager()
    }
    
    // MARK: - Setup
    
    private func setupStreamingManager() {
        environmentalContext.delegate = self
        Config.debugLog("Streaming GPT manager initialized")
    }
    
    // MARK: - Streaming API Integration
    
    func streamResponse(to prompt: String, 
                       partialHandler: @escaping (String) -> Void,
                       completion: @escaping (String) -> Void) {
        guard !isStreaming else {
            completion("I'm currently processing another request. Please wait.")
            return
        }
        
        isStreaming = true
        currentResponse = ""
        
        let request = createStreamingRequest(prompt: prompt)
        
        streamingTask = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            
            if let error = error {
                DispatchQueue.main.async {
                    self.handleStreamingError(error)
                    completion("I'm sorry, I encountered an error processing your request.")
                }
                return
            }
            
            if let data = data {
                self.processStreamingData(data, partialHandler: partialHandler, completion: completion)
            }
        }
        
        streamingTask?.resume()
    }
    
    private func createStreamingRequest(prompt: String) -> URLRequest {
        var request = URLRequest(url: URL(string: "\(baseURL)/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let messages = [
            ["role": "system", "content": createSystemPrompt()],
            ["role": "user", "content": prompt]
        ]
        
        let parameters: [String: Any] = [
            "model": model,
            "messages": messages,
            "max_tokens": maxTokens,
            "temperature": temperature,
            "stream": true
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: parameters)
        return request
    }
    
    private func createSystemPrompt() -> String {
        return """
        You are KaiSight, an advanced AI assistant specifically designed for visually impaired users. 
        
        Key characteristics:
        - Provide clear, concise descriptions optimized for audio consumption
        - Use spatial language (left, right, ahead, behind) for navigation
        - Prioritize safety and accessibility information
        - Be encouraging and supportive
        - Respond quickly for real-time assistance
        
        Current context: Real-time environmental assistance
        Response style: Conversational and immediately actionable
        """
    }
    
    private func processStreamingData(_ data: Data, 
                                    partialHandler: @escaping (String) -> Void,
                                    completion: @escaping (String) -> Void) {
        let dataString = String(data: data, encoding: .utf8) ?? ""
        let lines = dataString.components(separatedBy: "\n")
        
        for line in lines {
            if line.hasPrefix("data: ") {
                let jsonString = String(line.dropFirst(6))
                
                if jsonString.trimmingCharacters(in: .whitespaces) == "[DONE]" {
                    DispatchQueue.main.async {
                        self.isStreaming = false
                        completion(self.currentResponse)
                    }
                    return
                }
                
                if let data = jsonString.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let choices = json["choices"] as? [[String: Any]],
                   let delta = choices.first?["delta"] as? [String: Any],
                   let content = delta["content"] as? String {
                    
                    DispatchQueue.main.async {
                        self.currentResponse += content
                        partialHandler(content)
                    }
                }
            }
        }
    }
    
    private func handleStreamingError(_ error: Error) {
        isStreaming = false
        Config.debugLog("Streaming error: \(error)")
    }
    
    // MARK: - Real-Time Narration
    
    func startRealTimeNarration() {
        guard !narrationActive else { return }
        
        narrationActive = true
        startNarrationTimer()
        speechOutput.speak("Real-time narration activated")
        
        Config.debugLog("Started real-time narration")
    }
    
    func stopRealTimeNarration() {
        narrationActive = false
        narrationTimer?.invalidate()
        narrationTimer = nil
        speechOutput.speak("Real-time narration stopped")
        
        Config.debugLog("Stopped real-time narration")
    }
    
    private func startNarrationTimer() {
        narrationTimer = Timer.scheduledTimer(withTimeInterval: narrationInterval, repeats: true) { [weak self] _ in
            self?.performNarrationCycle()
        }
    }
    
    private func performNarrationCycle() {
        guard narrationActive else { return }
        
        // Capture current scene
        guard let currentImage = cameraManager.captureCurrentFrame() else { return }
        
        // Check if scene has changed significantly
        if hasSceneChanged(currentImage) {
            generateStreamingNarration(for: currentImage)
        }
    }
    
    private func hasSceneChanged(_ currentImage: UIImage) -> Bool {
        // Simple change detection - in production would use more sophisticated methods
        guard let lastTime = lastNarrationTime else {
            lastNarrationTime = Date()
            return true
        }
        
        // Force narration every 10 seconds even if no change detected
        if Date().timeIntervalSince(lastTime) > 10.0 {
            lastNarrationTime = Date()
            return true
        }
        
        return false
    }
    
    private func generateStreamingNarration(for image: UIImage) {
        let currentSceneHash = generateImageHash(image)
        
        // Detect changes since last scene
        let changes = changeDetector.detectChanges(
            currentImage: image,
            previousScenes: sceneMemory,
            currentHash: currentSceneHash
        )
        
        let prompt = createMemoryAwareNarrationPrompt(
            image: image,
            detectedChanges: changes,
            sceneHistory: Array(sceneMemory.suffix(3))
        )
        
        streamResponse(to: prompt) { [weak self] partialContent in
            // Real-time partial narration
        } completion: { [weak self] fullResponse in
            self?.processNarrationResponse(fullResponse, image: image, changes: changes)
        }
    }
    
    private func createMemoryAwareNarrationPrompt(
        image: UIImage,
        detectedChanges: SceneChanges,
        sceneHistory: [SceneMemory]
    ) -> String {
        var prompt = """
        You are KaiSight providing real-time environmental narration. Focus on what's NEW or CHANGED.
        
        PRIORITY RULES:
        1. NEW objects/people/changes get immediate attention
        2. MOVED objects get brief mention
        3. UNCHANGED familiar objects - mention only if user asks
        4. Keep narration under 15 words for real-time delivery
        5. Use spatial language (left, right, ahead, distance)
        
        Current scene analysis:
        """
        
        // Add change detection results
        if !detectedChanges.newObjects.isEmpty {
            prompt += "\nNEW objects detected: \(detectedChanges.newObjects.joined(separator: ", "))"
        }
        
        if !detectedChanges.movedObjects.isEmpty {
            prompt += "\nMOVED objects: \(detectedChanges.movedObjects.joined(separator: ", "))"
        }
        
        if !detectedChanges.removedObjects.isEmpty {
            prompt += "\nREMOVED objects: \(detectedChanges.removedObjects.joined(separator: ", "))"
        }
        
        // Add recent scene context (abbreviated)
        if !sceneHistory.isEmpty {
            prompt += "\n\nRecent scene memory (don't repeat unless changed):"
            for (index, scene) in sceneHistory.enumerated() {
                let timeAgo = Int(Date().timeIntervalSince(scene.timestamp))
                prompt += "\n\(timeAgo)s ago: \(scene.description.prefix(30))..."
            }
        }
        
        prompt += "\n\nImage: \(image.base64EncodedString())"
        
        // Specific instructions based on change level
        if detectedChanges.significantChange {
            prompt += "\n\nSIGNIFICANT CHANGE detected. Provide clear, immediate narration."
        } else if detectedChanges.minorChange {
            prompt += "\n\nMinor change detected. Brief update only."
        } else {
            prompt += "\n\nNo major changes. Only speak if something important requires attention."
        }
        
        return prompt
    }
    
    private func processNarrationResponse(_ response: String, image: UIImage, changes: SceneChanges) {
        // Only deliver narration if there are meaningful changes or user interaction
        let shouldNarrate = changes.significantChange || 
                           changes.newObjects.count > 0 || 
                           Date().timeIntervalSince(lastNarrationTime ?? Date.distantPast) > 30.0
        
        if shouldNarrate && !response.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // Create scene memory entry
            let sceneMemory = SceneMemory(
                id: UUID(),
                description: response,
                timestamp: Date(),
                imageHash: generateImageHash(image),
                keyObjects: changes.allObjects,
                changesSinceLastScene: changes.newObjects + changes.movedObjects
            )
            
            addToSceneMemory(sceneMemory)
            deliverNarration(response)
        }
    }
    
    private func addToSceneMemory(_ memory: SceneMemory) {
        sceneMemory.append(memory)
        
        // Maintain memory limit
        if sceneMemory.count > maxSceneMemory {
            sceneMemory.removeFirst()
        }
        
        lastSceneHash = memory.imageHash
    }
    
    private func generateImageHash(_ image: UIImage) -> String {
        guard let imageData = image.jpegData(compressionQuality: 0.3) else {
            return UUID().uuidString
        }
        
        return String(imageData.hashValue)
    }
    
    private func deliverNarration(_ narration: String) {
        // Add to history
        let entry = NarrativeEntry(
            content: narration,
            timestamp: Date(),
            context: environmentalContext.getCurrentContext()
        )
        narrativeHistory.append(entry)
        
        // Keep only recent entries
        if narrativeHistory.count > 10 {
            narrativeHistory.removeFirst()
        }
        
        // Deliver with appropriate priority
        speechOutput.speak(narration, priority: .medium)
        
        lastNarrationTime = Date()
        Config.debugLog("Delivered narration: \(narration)")
    }
    
    // MARK: - Advanced Vision Analysis
    
    func analyzeImageWithStreaming(_ image: UIImage, 
                                  detailLevel: DetailLevel = .medium,
                                  context: String? = nil,
                                  completion: @escaping (String) -> Void) {
        let prompt = createVisionAnalysisPrompt(image: image, detailLevel: detailLevel, context: context)
        
        streamResponse(to: prompt) { partialContent in
            // Real-time partial content could be used for immediate feedback
        } completion: { fullResponse in
            completion(fullResponse)
        }
    }
    
    private func createVisionAnalysisPrompt(image: UIImage, detailLevel: DetailLevel, context: String?) -> String {
        let base64Image = image.base64EncodedString()
        
        var prompt = """
        As KaiSight, analyze this image for a visually impaired user with \(detailLevel.rawValue) detail level.
        
        Provide information about:
        - Objects and their spatial relationships
        - Text content (OCR)
        - People and their activities
        - Navigation-relevant information
        - Safety considerations
        
        Image: \(base64Image)
        """
        
        if let context = context {
            prompt += "\n\nAdditional context: \(context)"
        }
        
        // Add environmental context
        let envContext = environmentalContext.getCurrentContext()
        prompt += "\n\nEnvironmental context: \(envContext)"
        
        return prompt
    }
    
    // MARK: - Contextual Intelligence
    
    func analyzeObjectRelationships(_ image: UIImage, completion: @escaping ([ObjectRelationship]) -> Void) {
        let prompt = """
        Analyze the spatial relationships between objects in this image. Return structured data about:
        - Object pairs and their spatial relationship (left of, right of, above, below, near, far)
        - Distance estimates (close, medium, far)
        - Navigational relevance (obstacle, landmark, path)
        
        Format as JSON array of relationships.
        
        Image: \(image.base64EncodedString())
        """
        
        streamResponse(to: prompt) { _ in
            // Handle partial response if needed
        } completion: { response in
            let relationships = self.parseObjectRelationships(response)
            completion(relationships)
        }
    }
    
    private func parseObjectRelationships(_ response: String) -> [ObjectRelationship] {
        // Parse JSON response into ObjectRelationship objects
        // Simplified implementation
        return []
    }
    
    // MARK: - Memory and Context
    
    func addContextualMemory(_ memory: ContextualMemory) {
        environmentalContext.addMemory(memory)
    }
    
    func getRelevantMemories(for location: String) -> [ContextualMemory] {
        return environmentalContext.getMemories(for: location)
    }
    
    // MARK: - Public Interface
    
    func cancelStreaming() {
        streamingTask?.cancel()
        isStreaming = false
        currentResponse = ""
    }
    
    func getNarrationStatus() -> String {
        if narrationActive {
            return "Real-time narration active (\(narrativeHistory.count) recent descriptions)"
        } else {
            return "Real-time narration inactive"
        }
    }
    
    // MARK: - Enhanced Context Intelligence
    
    func getSceneMemorySummary() -> String {
        guard !sceneMemory.isEmpty else { return "No scene memory available" }
        
        let recentScenes = sceneMemory.suffix(3)
        var summary = "Recent scenes: "
        
        for scene in recentScenes {
            let timeAgo = Int(Date().timeIntervalSince(scene.timestamp))
            summary += "\(timeAgo)s ago: \(scene.keyObjects.joined(separator: ", ")). "
        }
        
        return summary
    }
    
    func clearSceneMemory() {
        sceneMemory.removeAll()
        lastSceneHash = nil
        changeDetector = SceneChangeDetector()
    }
    
    func hasSignificantSceneChanges() -> Bool {
        guard let lastScene = sceneMemory.last else { return true }
        return Date().timeIntervalSince(lastScene.timestamp) > 5.0
    }
}

// MARK: - EnvironmentalContextDelegate

extension StreamingGPTManager: EnvironmentalContextDelegate {
    func contextDidChange(_ newContext: String) {
        // Respond to environmental context changes
        if narrationActive {
            // Trigger immediate narration update
            performNarrationCycle()
        }
    }
}

// MARK: - Supporting Classes and Data Models

class EnvironmentalContext {
    weak var delegate: EnvironmentalContextDelegate?
    
    private var currentContext: String = "indoor_unknown"
    private var contextMemories: [String: [ContextualMemory]] = [:]
    private var lastLocationUpdate: Date?
    
    func getCurrentContext() -> String {
        return currentContext
    }
    
    func updateContext(_ newContext: String) {
        if newContext != currentContext {
            currentContext = newContext
            delegate?.contextDidChange(newContext)
        }
    }
    
    func addMemory(_ memory: ContextualMemory) {
        let location = memory.location
        if contextMemories[location] == nil {
            contextMemories[location] = []
        }
        contextMemories[location]?.append(memory)
        
        // Keep only recent memories per location
        if let memories = contextMemories[location], memories.count > 20 {
            contextMemories[location] = Array(memories.suffix(20))
        }
    }
    
    func getMemories(for location: String) -> [ContextualMemory] {
        return contextMemories[location] ?? []
    }
}

protocol EnvironmentalContextDelegate: AnyObject {
    func contextDidChange(_ newContext: String)
}

struct NarrativeEntry {
    let content: String
    let timestamp: Date
    let context: String
}

struct ObjectRelationship {
    let object1: String
    let object2: String
    let relationship: SpatialRelationship
    let distance: DistanceCategory
    let navigationRelevance: NavigationRelevance
}

enum SpatialRelationship: String, CaseIterable {
    case leftOf = "left_of"
    case rightOf = "right_of"
    case above = "above"
    case below = "below"
    case near = "near"
    case far = "far"
    case inFrontOf = "in_front_of"
    case behind = "behind"
}

enum DistanceCategory: String, CaseIterable {
    case close = "close"      // Within arm's reach
    case medium = "medium"    // A few steps away
    case far = "far"         // Across the room or beyond
}

enum NavigationRelevance: String, CaseIterable {
    case obstacle = "obstacle"
    case landmark = "landmark"
    case path = "path"
    case neutral = "neutral"
}

struct ContextualMemory {
    let id: UUID
    let location: String
    let content: String
    let timestamp: Date
    let relevance: Double
    let tags: [String]
}

// MARK: - UIImage Extensions

extension UIImage {
    func base64EncodedString() -> String {
        guard let imageData = self.jpegData(compressionQuality: 0.8) else {
            return ""
        }
        return imageData.base64EncodedString()
    }
    
    func resizedForAPI(maxSize: CGSize = CGSize(width: 1024, height: 1024)) -> UIImage {
        let ratio = min(maxSize.width / size.width, maxSize.height / size.height)
        let newSize = CGSize(width: size.width * ratio, height: size.height * ratio)
        
        UIGraphicsBeginImageContextWithOptions(newSize, false, 0)
        draw(in: CGRect(origin: .zero, size: newSize))
        let resizedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return resizedImage ?? self
    }
}

// MARK: - CameraManager Extension

extension CameraManager {
    func captureCurrentFrame() -> UIImage? {
        // This would capture the current camera frame
        // Implementation depends on the existing CameraManager setup
        return nil // Placeholder
    }
}

// MARK: - Scene Change Detection

class SceneChangeDetector {
    private var lastObjects: [DetectedObject] = []
    private var objectTracker = ObjectTracker()
    
    func detectChanges(
        currentImage: UIImage,
        previousScenes: [SceneMemory],
        currentHash: String
    ) -> SceneChanges {
        // Detect objects in current scene
        let currentObjects = detectObjects(in: currentImage)
        let previousObjects = lastObjects
        
        // Compare with previous scene
        let newObjects = findNewObjects(current: currentObjects, previous: previousObjects)
        let removedObjects = findRemovedObjects(current: currentObjects, previous: previousObjects)
        let movedObjects = findMovedObjects(current: currentObjects, previous: previousObjects)
        
        // Determine significance
        let significantChange = newObjects.count > 0 || removedObjects.count > 0 || movedObjects.count > 2
        let minorChange = movedObjects.count > 0 && movedObjects.count <= 2
        
        // Update tracking
        lastObjects = currentObjects
        
        return SceneChanges(
            newObjects: newObjects.map { $0.label },
            removedObjects: removedObjects.map { $0.label },
            movedObjects: movedObjects.map { $0.label },
            allObjects: currentObjects.map { $0.label },
            significantChange: significantChange,
            minorChange: minorChange
        )
    }
    
    private func detectObjects(in image: UIImage) -> [DetectedObject] {
        // Use Vision framework for object detection
        // This is a simplified implementation
        return []
    }
    
    private func findNewObjects(current: [DetectedObject], previous: [DetectedObject]) -> [DetectedObject] {
        return current.filter { currentObj in
            !previous.contains { prevObj in
                currentObj.label == prevObj.label && 
                distance(currentObj.boundingBox.center, prevObj.boundingBox.center) < 0.1
            }
        }
    }
    
    private func findRemovedObjects(current: [DetectedObject], previous: [DetectedObject]) -> [DetectedObject] {
        return previous.filter { prevObj in
            !current.contains { currentObj in
                prevObj.label == currentObj.label &&
                distance(prevObj.boundingBox.center, currentObj.boundingBox.center) < 0.1
            }
        }
    }
    
    private func findMovedObjects(current: [DetectedObject], previous: [DetectedObject]) -> [DetectedObject] {
        return current.filter { currentObj in
            previous.contains { prevObj in
                currentObj.label == prevObj.label &&
                distance(currentObj.boundingBox.center, prevObj.boundingBox.center) > 0.1 &&
                distance(currentObj.boundingBox.center, prevObj.boundingBox.center) < 0.5
            }
        }
    }
    
    private func distance(_ point1: CGPoint, _ point2: CGPoint) -> Double {
        let dx = point1.x - point2.x
        let dy = point1.y - point2.y
        return sqrt(dx * dx + dy * dy)
    }
}

struct SceneChanges {
    let newObjects: [String]
    let removedObjects: [String]
    let movedObjects: [String]
    let allObjects: [String]
    let significantChange: Bool
    let minorChange: Bool
}

class ObjectTracker {
    private var trackedObjects: [String: TrackedObjectState] = [:]
    
    func updateTracking(_ objects: [DetectedObject]) {
        // Update object positions and states
    }
}

struct TrackedObjectState {
    let lastPosition: CGPoint
    let lastSeen: Date
    let stability: Float
}

struct SceneMemory {
    let id: UUID
    let description: String
    let timestamp: Date
    let imageHash: String
    let keyObjects: [String]
    let changesSinceLastScene: [String]
} 