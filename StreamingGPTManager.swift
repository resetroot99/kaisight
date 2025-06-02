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
        
        // TODO: Implement actual image comparison
        return false
    }
    
    private func generateStreamingNarration(for image: UIImage) {
        let prompt = createNarrationPrompt(for: image)
        
        streamResponse(to: prompt) { [weak self] partialContent in
            // Could provide real-time audio feedback here
            // For now, just accumulate the response
        } completion: { [weak self] fullResponse in
            self?.deliverNarration(fullResponse)
        }
    }
    
    private func createNarrationPrompt(for image: UIImage) -> String {
        let base64Image = image.base64EncodedString()
        
        var prompt = """
        Analyze this scene and provide a brief, clear description for a visually impaired user. Focus on:
        - Important objects and their locations
        - Potential navigation hazards or aids
        - Changes from previous descriptions
        - Spatial relationships (left, right, ahead, distance)
        
        Keep the description under 30 words for quick audio delivery.
        
        Image: \(base64Image)
        """
        
        // Add context from recent narrations
        if let recentNarration = narrativeHistory.last {
            prompt += "\n\nPrevious description: \(recentNarration.content)"
        }
        
        return prompt
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