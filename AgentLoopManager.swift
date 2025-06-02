import Foundation
import AVFoundation
import Speech
import Combine

class AgentLoopManager: NSObject, ObservableObject {
    @Published var agentState: AgentState = .idle
    @Published var isListening = false
    @Published var conversationActive = false
    @Published var wakeWordDetected = false
    
    // Core components
    private let audioManager = AudioManager()
    private let speechManager = SpeechManager()
    private let gptManager = GPTManager()
    private let conversationMemory = ConversationMemory()
    
    // Wake word detection
    private let wakeWords = ["hey kaisight", "kaisight", "assistant"]
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    
    // State management
    private var stateTimer: Timer?
    private var listeningTimeout: Timer?
    private let maxListeningDuration: TimeInterval = 30
    private let wakeWordTimeout: TimeInterval = 5
    
    // Voice activity detection
    private var voiceActivityDetector = VoiceActivityDetector()
    private var silenceTimer: Timer?
    private let silenceThreshold: TimeInterval = 2.0
    
    // Enhanced Wake Word Detection with Noise Management
    private var noiseDetector = NoiseDetector()
    private var adaptiveThreshold: Float = 0.75
    private var environmentalNoiseLevel: Float = 0.0
    private var consecutiveWakeWordAttempts = 0
    private let maxFalsePositives = 3
    
    // MARK: - Autonomous Decision Making
    
    private let decisionEngine = AutonomousDecisionEngine()
    private var lastUserMovement: Date?
    private var lastEnvironmentalCheck: Date?
    private let inactivityThreshold: TimeInterval = 7200 // 2 hours
    private let environmentalCheckInterval: TimeInterval = 60 // 1 minute
    
    // MARK: - Proactive Monitoring
    
    private func setupProactiveMonitoring() {
        // Start autonomous monitoring
        decisionEngine.delegate = self
        decisionEngine.startMonitoring()
        
        // Schedule periodic checks
        Timer.scheduledTimer(withTimeInterval: environmentalCheckInterval, repeats: true) { _ in
            self.performAutonomousCheck()
        }
        
        Config.debugLog("Proactive monitoring initialized")
    }
    
    private func performAutonomousCheck() {
        guard agentState != .processing else { return }
        
        let currentTime = Date()
        lastEnvironmentalCheck = currentTime
        
        // Check for various risk factors
        let risks = decisionEngine.assessEnvironmentalRisks()
        
        for risk in risks {
            handleDetectedRisk(risk)
        }
        
        // Check user inactivity
        checkUserInactivity(at: currentTime)
        
        // Check lighting conditions
        checkLightingConditions()
        
        // Check for new obstacles or changes
        checkEnvironmentalChanges()
    }
    
    private func handleDetectedRisk(_ risk: EnvironmentalRisk) {
        switch risk.severity {
        case .critical:
            // Immediate intervention required
            agentState = .activated
            speechManager.speak(risk.message, priority: .critical)
            
            // Log critical risk
            Config.debugLog("CRITICAL RISK: \(risk.description)")
            
            // Consider emergency actions
            if risk.type == .emergencyDetected {
                triggerEmergencyProtocol()
            }
            
        case .high:
            // Proactive warning
            speechManager.speak(risk.message, priority: .high)
            Config.debugLog("HIGH RISK: \(risk.description)")
            
        case .medium:
            // Gentle suggestion
            if shouldProvideGuidance(for: risk) {
                speechManager.speak(risk.message, priority: .medium)
            }
            
        case .low:
            // Silent monitoring or subtle notification
            Config.debugLog("LOW RISK: \(risk.description)")
        }
    }
    
    private func checkUserInactivity(at currentTime: Date) {
        guard let lastMovement = lastUserMovement else {
            lastUserMovement = currentTime
            return
        }
        
        let inactivityDuration = currentTime.timeIntervalSince(lastMovement)
        
        if inactivityDuration > inactivityThreshold {
            let risk = EnvironmentalRisk(
                type: .userInactivity,
                severity: .medium,
                message: "You haven't moved for \(Int(inactivityDuration/3600)) hours. Would you like me to check if you're okay?",
                description: "User inactivity detected",
                location: nil,
                confidence: 0.9
            )
            
            handleDetectedRisk(risk)
            
            // Reset timer after notification
            lastUserMovement = currentTime
        }
    }
    
    private func checkLightingConditions() {
        // This would integrate with camera/light sensor data
        let lightingLevel = getCurrentLightingLevel()
        
        if lightingLevel < 0.2 { // Very dark
            let risk = EnvironmentalRisk(
                type: .poorLighting,
                severity: .medium,
                message: "Lighting is very low. Consider turning on lights for safer navigation.",
                description: "Poor lighting conditions detected",
                location: nil,
                confidence: 0.8
            )
            
            handleDetectedRisk(risk)
        }
    }
    
    private func checkEnvironmentalChanges() {
        // This would integrate with spatial manager for obstacle detection
        let newObstacles = detectNewObstacles()
        
        for obstacle in newObstacles {
            let severity: RiskSeverity = obstacle.isInPath ? .high : .medium
            
            let risk = EnvironmentalRisk(
                type: .obstacleDetected,
                severity: severity,
                message: "New obstacle detected \(obstacle.direction). \(obstacle.description)",
                description: "Environmental obstacle: \(obstacle.description)",
                location: obstacle.position,
                confidence: obstacle.confidence
            )
            
            handleDetectedRisk(risk)
        }
    }
    
    private func shouldProvideGuidance(for risk: EnvironmentalRisk) -> Bool {
        // Rate limiting to avoid overwhelming user
        let timeSinceLastGuidance = Date().timeIntervalSince(lastEnvironmentalCheck ?? Date.distantPast)
        
        return timeSinceLastGuidance > 300 || risk.severity >= .high
    }
    
    private func triggerEmergencyProtocol() {
        // Emergency response protocol
        speechManager.speak("Emergency situation detected. Activating emergency assistance.", priority: .critical)
        
        // Could integrate with emergency contacts or services
        // emergencyContactManager.alertEmergencyContacts()
        
        Config.debugLog("EMERGENCY PROTOCOL ACTIVATED")
    }
    
    // MARK: - User Activity Tracking
    
    func updateUserMovement() {
        lastUserMovement = Date()
    }
    
    func reportUserLocation(_ location: simd_float3) {
        decisionEngine.updateUserLocation(location)
    }
    
    // MARK: - Environmental Data Integration
    
    private func getCurrentLightingLevel() -> Float {
        // Would integrate with camera or light sensor
        return 0.5 // Placeholder
    }
    
    private func detectNewObstacles() -> [ObstacleInfo] {
        // Would integrate with spatial manager
        return [] // Placeholder
    }
    
    // MARK: - Decision Engine Integration
    
    extension AgentLoopManager: AutonomousDecisionEngineDelegate {
        func decisionEngine(_ engine: AutonomousDecisionEngine, detectedRisk risk: EnvironmentalRisk) {
            handleDetectedRisk(risk)
        }
        
        func decisionEngine(_ engine: AutonomousDecisionEngine, recommendsAction action: ProactiveAction) {
            executeProactiveAction(action)
        }
    }
    
    private func executeProactiveAction(_ action: ProactiveAction) {
        switch action.type {
        case .navigationGuidance:
            speechManager.speak(action.message, priority: .medium)
            
        case .environmentalAlert:
            speechManager.speak(action.message, priority: .high)
            
        case .healthCheck:
            speechManager.speak(action.message, priority: .low)
            
        case .emergencyResponse:
            triggerEmergencyProtocol()
        }
    }
    
    // MARK: - Supporting Classes and Protocols
    
    class AutonomousDecisionEngine {
        weak var delegate: AutonomousDecisionEngineDelegate?
        
        private var userLocation: simd_float3?
        private var environmentalData: EnvironmentalData = EnvironmentalData()
        private var riskAssessment = RiskAssessmentEngine()
        
        func startMonitoring() {
            // Initialize continuous monitoring
            Config.debugLog("Autonomous decision engine started")
        }
        
        func updateUserLocation(_ location: simd_float3) {
            userLocation = location
        }
        
        func assessEnvironmentalRisks() -> [EnvironmentalRisk] {
            return riskAssessment.analyzeCurrentConditions(
                location: userLocation,
                environmentalData: environmentalData
            )
        }
    }
    
    protocol AutonomousDecisionEngineDelegate: AnyObject {
        func decisionEngine(_ engine: AutonomousDecisionEngine, detectedRisk risk: EnvironmentalRisk)
        func decisionEngine(_ engine: AutonomousDecisionEngine, recommendsAction action: ProactiveAction)
    }
    
    struct EnvironmentalRisk {
        let type: RiskType
        let severity: RiskSeverity
        let message: String
        let description: String
        let location: simd_float3?
        let confidence: Float
    }
    
    enum RiskType {
        case obstacleDetected
        case userInactivity
        case poorLighting
        case unsafeEnvironment
        case emergencyDetected
        case navigationHazard
    }
    
    enum RiskSeverity: Comparable {
        case low
        case medium
        case high
        case critical
    }
    
    struct ProactiveAction {
        let type: ActionType
        let message: String
        let priority: ActionPriority
    }
    
    enum ActionType {
        case navigationGuidance
        case environmentalAlert
        case healthCheck
        case emergencyResponse
    }
    
    enum ActionPriority {
        case low
        case medium
        case high
        case critical
    }
    
    struct ObstacleInfo {
        let position: simd_float3
        let description: String
        let direction: String
        let isInPath: Bool
        let confidence: Float
    }
    
    class EnvironmentalData {
        var lightingLevel: Float = 0.5
        var noiseLevel: Float = 0.3
        var temperature: Float = 20.0
        var obstacles: [ObstacleInfo] = []
    }
    
    class RiskAssessmentEngine {
        func analyzeCurrentConditions(location: simd_float3?, environmentalData: EnvironmentalData) -> [EnvironmentalRisk] {
            var risks: [EnvironmentalRisk] = []
            
            // Analyze lighting
            if environmentalData.lightingLevel < 0.3 {
                risks.append(EnvironmentalRisk(
                    type: .poorLighting,
                    severity: .medium,
                    message: "Low light detected. Consider additional lighting.",
                    description: "Poor lighting conditions",
                    location: location,
                    confidence: 0.8
                ))
            }
            
            // Analyze obstacles
            for obstacle in environmentalData.obstacles {
                if obstacle.isInPath {
                    risks.append(EnvironmentalRisk(
                        type: .obstacleDetected,
                        severity: .high,
                        message: "Obstacle ahead: \(obstacle.description)",
                        description: "Path obstacle detected",
                        location: obstacle.position,
                        confidence: obstacle.confidence
                    ))
                }
            }
            
            return risks
        }
    }
    
    override init() {
        super.init()
        setupAgentLoop()
    }
    
    // MARK: - Setup
    
    private func setupAgentLoop() {
        setupSpeechRecognition()
        setupVoiceActivityDetection()
        startWakeWordDetection()
        setupProactiveMonitoring()
        
        Config.debugLog("Agent loop manager initialized")
    }
    
    private func setupSpeechRecognition() {
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        speechRecognizer?.delegate = self
        
        // Request speech recognition authorization
        SFSpeechRecognizer.requestAuthorization { [weak self] authStatus in
            DispatchQueue.main.async {
                switch authStatus {
                case .authorized:
                    self?.speechRecognizer?.delegate = self
                case .denied, .restricted, .notDetermined:
                    Config.debugLog("Speech recognition not authorized")
                @unknown default:
                    break
                }
            }
        }
    }
    
    private func setupVoiceActivityDetection() {
        voiceActivityDetector.delegate = self
        voiceActivityDetector.configure(
            silenceThreshold: -30.0, // dB
            voiceThreshold: -20.0,   // dB
            minimumSpeechDuration: 0.5
        )
        
        // Configure noise detection
        noiseDetector = NoiseDetector()
    }
    
    // MARK: - Wake Word Detection
    
    func startWakeWordDetection() {
        guard agentState == .idle else { return }
        
        agentState = .listeningForWakeWord
        startContinuousListening()
        
        Config.debugLog("Started wake word detection")
    }
    
    private func startContinuousListening() {
        guard let speechRecognizer = speechRecognizer, speechRecognizer.isAvailable else {
            Config.debugLog("Speech recognizer not available")
            return
        }
        
        try? startSpeechRecognition()
    }
    
    private func startSpeechRecognition() throws {
        // Cancel any existing recognition
        recognitionTask?.cancel()
        recognitionTask = nil
        
        // Create recognition request
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            throw AgentError.speechRecognitionSetupFailed
        }
        
        recognitionRequest.shouldReportPartialResults = true
        recognitionRequest.requiresOnDeviceRecognition = true // Privacy-first
        
        // Start audio session
        try audioManager.startRecording { [weak self] audioBuffer in
            self?.recognitionRequest?.append(audioBuffer)
            self?.voiceActivityDetector.processAudioBuffer(audioBuffer)
        }
        
        // Start recognition task
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            self?.handleSpeechRecognitionResult(result: result, error: error)
        }
    }
    
    private func handleSpeechRecognitionResult(result: SFSpeechRecognitionResult?, error: Error?) {
        if let result = result {
            let transcript = result.bestTranscription.formattedString.lowercased()
            
            switch agentState {
            case .listeningForWakeWord:
                checkForWakeWord(in: transcript)
            case .listeningForCommand:
                processVoiceCommand(transcript, isFinal: result.isFinal)
            default:
                break
            }
        }
        
        if let error = error {
            Config.debugLog("Speech recognition error: \(error)")
            handleSpeechRecognitionError(error)
        }
    }
    
    private func checkForWakeWord(in transcript: String) {
        // Pre-filter based on environmental conditions
        guard shouldProcessWakeWord() else { return }
        
        let normalizedTranscript = transcript.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        for wakeWord in wakeWords {
            let confidence = calculateWakeWordConfidence(transcript: normalizedTranscript, wakeWord: wakeWord)
            
            if confidence > adaptiveThreshold {
                // Verify with secondary confirmation to reduce false positives
                if verifyWakeWordActivation(transcript: normalizedTranscript, confidence: confidence) {
                    wakeWordDetected = true
                    resetFalsePositiveCounter()
                    activateAgent()
                    break
                } else {
                    handlePotentialFalsePositive()
                }
            }
        }
    }
    
    private func shouldProcessWakeWord() -> Bool {
        // Check noise levels
        if environmentalNoiseLevel > 0.8 {
            Config.debugLog("Skipping wake word processing due to high noise levels")
            return false
        }
        
        // Check recent false positives
        if consecutiveWakeWordAttempts > maxFalsePositives {
            Config.debugLog("Temporarily disabling wake word due to false positives")
            return false
        }
        
        return true
    }
    
    private func calculateWakeWordConfidence(transcript: String, wakeWord: String) -> Float {
        // Fuzzy matching with edit distance
        let editDistance = levenshteinDistance(transcript, wakeWord)
        let maxLength = max(transcript.count, wakeWord.count)
        let similarity = 1.0 - (Float(editDistance) / Float(maxLength))
        
        // Adjust for environmental factors
        let environmentalAdjustment = 1.0 - (environmentalNoiseLevel * 0.3)
        
        return similarity * environmentalAdjustment
    }
    
    private func verifyWakeWordActivation(transcript: String, confidence: Float) -> Bool {
        // Secondary verification using different criteria
        let wordsInTranscript = transcript.components(separatedBy: .whitespacesAndNewlines)
        
        // Check if wake word appears as isolated words (not part of other words)
        for wakeWord in wakeWords {
            let wakeWordComponents = wakeWord.components(separatedBy: " ")
            if containsSequentialWords(wordsInTranscript, wakeWordComponents) {
                return true
            }
        }
        
        return confidence > 0.9 // Higher threshold for less obvious matches
    }
    
    private func containsSequentialWords(_ transcript: [String], _ wakeWords: [String]) -> Bool {
        guard wakeWords.count <= transcript.count else { return false }
        
        for i in 0...(transcript.count - wakeWords.count) {
            let slice = Array(transcript[i..<(i + wakeWords.count)])
            if slice.map({ $0.lowercased() }) == wakeWords.map({ $0.lowercased() }) {
                return true
            }
        }
        
        return false
    }
    
    private func handlePotentialFalsePositive() {
        consecutiveWakeWordAttempts += 1
        
        if consecutiveWakeWordAttempts >= maxFalsePositives {
            // Temporarily increase threshold and add cooling period
            adaptiveThreshold = min(adaptiveThreshold + 0.1, 0.95)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 30.0) {
                self.resetFalsePositiveCounter()
            }
            
            Config.debugLog("Adaptive threshold increased due to false positives")
        }
    }
    
    private func resetFalsePositiveCounter() {
        consecutiveWakeWordAttempts = 0
        adaptiveThreshold = max(adaptiveThreshold - 0.05, 0.75) // Gradually lower threshold
    }
    
    private func levenshteinDistance(_ s1: String, _ s2: String) -> Int {
        let s1Array = Array(s1)
        let s2Array = Array(s2)
        let s1Count = s1Array.count
        let s2Count = s2Array.count
        
        var matrix = Array(repeating: Array(repeating: 0, count: s2Count + 1), count: s1Count + 1)
        
        for i in 0...s1Count {
            matrix[i][0] = i
        }
        
        for j in 0...s2Count {
            matrix[0][j] = j
        }
        
        for i in 1...s1Count {
            for j in 1...s2Count {
                if s1Array[i-1] == s2Array[j-1] {
                    matrix[i][j] = matrix[i-1][j-1]
                } else {
                    matrix[i][j] = min(
                        matrix[i-1][j] + 1,
                        matrix[i][j-1] + 1,
                        matrix[i-1][j-1] + 1
                    )
                }
            }
        }
        
        return matrix[s1Count][s2Count]
    }
    
    // MARK: - Agent Activation
    
    private func activateAgent() {
        agentState = .activated
        conversationActive = true
        
        // Provide activation feedback
        speechManager.speak("Yes, I'm listening.", priority: .high)
        
        // Start command listening
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.startCommandListening()
        }
        
        Config.debugLog("Agent activated by wake word")
    }
    
    private func startCommandListening() {
        agentState = .listeningForCommand
        isListening = true
        
        // Set listening timeout
        listeningTimeout = Timer.scheduledTimer(withTimeInterval: maxListeningDuration, repeats: false) { _ in
            self.deactivateAgent(reason: "Listening timeout")
        }
        
        Config.debugLog("Started command listening")
    }
    
    // MARK: - Command Processing
    
    private func processVoiceCommand(_ transcript: String, isFinal: Bool) {
        if isFinal {
            stopCommandListening()
            processCommand(transcript)
        } else {
            // Process partial results for real-time feedback
            if transcript.count > 10 { // Minimum command length
                providePartialFeedback(transcript)
            }
        }
    }
    
    private func processCommand(_ command: String) {
        agentState = .processing
        
        // Add to conversation memory
        conversationMemory.addUserMessage(command)
        
        // Process with enhanced context
        let contextualPrompt = buildContextualPrompt(userCommand: command)
        
        gptManager.streamResponse(to: contextualPrompt) { [weak self] partialResponse in
            // Handle streaming response
            self?.handlePartialResponse(partialResponse)
        } completion: { [weak self] fullResponse in
            self?.handleCommandResponse(fullResponse, userCommand: command)
        }
    }
    
    private func buildContextualPrompt(userCommand: String) -> String {
        var prompt = "As KaiSight, an AI assistant for visually impaired users, respond to: '\(userCommand)'\n\n"
        
        // Add conversation history
        let recentHistory = conversationMemory.getRecentHistory(limit: 5)
        if !recentHistory.isEmpty {
            prompt += "Recent conversation:\n\(recentHistory)\n\n"
        }
        
        // Add current context
        prompt += "Current context:\n"
        prompt += "- Time: \(DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .short))\n"
        prompt += "- User is using voice commands\n"
        prompt += "- Provide concise, helpful responses optimized for speech\n"
        
        return prompt
    }
    
    private func handlePartialResponse(_ partialResponse: String) {
        // For real-time streaming, we could provide immediate feedback
        // For now, we'll just log progress
        Config.debugLog("Streaming response: \(partialResponse.prefix(50))...")
    }
    
    private func handleCommandResponse(_ response: String, userCommand: String) {
        // Add response to conversation memory
        conversationMemory.addAssistantMessage(response)
        
        // Speak the response
        speechManager.speak(response, priority: .high)
        
        // Check if user wants to continue conversation
        if shouldContinueConversation(response: response) {
            continueConversation()
        } else {
            deactivateAgent(reason: "Command completed")
        }
    }
    
    private func shouldContinueConversation(response: String) -> Bool {
        // Simple heuristics to determine if conversation should continue
        let continuationPhrases = ["what else", "anything else", "tell me more", "do you need"]
        let lowerResponse = response.lowercased()
        
        return continuationPhrases.contains { lowerResponse.contains($0) }
    }
    
    private func continueConversation() {
        // Brief pause, then continue listening
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            if self.conversationActive {
                self.startCommandListening()
            }
        }
    }
    
    // MARK: - Agent Deactivation
    
    func deactivateAgent(reason: String) {
        agentState = .idle
        conversationActive = false
        isListening = false
        wakeWordDetected = false
        
        // Clean up timers
        listeningTimeout?.invalidate()
        listeningTimeout = nil
        
        silenceTimer?.invalidate()
        silenceTimer = nil
        
        // Stop audio processing
        audioManager.stopRecording()
        
        // Restart wake word detection
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.startWakeWordDetection()
        }
        
        Config.debugLog("Agent deactivated: \(reason)")
    }
    
    // MARK: - Voice Activity Detection
    
    private func handleVoiceActivityStart() {
        silenceTimer?.invalidate()
        silenceTimer = nil
    }
    
    private func handleVoiceActivityEnd() {
        // Start silence timer
        silenceTimer = Timer.scheduledTimer(withTimeInterval: silenceThreshold, repeats: false) { _ in
            if self.agentState == .listeningForCommand {
                self.deactivateAgent(reason: "Silence detected")
            }
        }
    }
    
    // MARK: - Error Handling
    
    private func handleSpeechRecognitionError(_ error: Error) {
        Config.debugLog("Speech recognition error: \(error)")
        
        // Restart recognition after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            if self.agentState != .idle {
                try? self.startSpeechRecognition()
            }
        }
    }
    
    private func providePartialFeedback(_ transcript: String) {
        // Could provide visual or haptic feedback for partial recognition
        Config.debugLog("Partial recognition: \(transcript)")
    }
    
    // MARK: - Manual Controls
    
    func manualActivation() {
        if agentState == .listeningForWakeWord {
            activateAgent()
        }
    }
    
    func manualDeactivation() {
        deactivateAgent(reason: "Manual deactivation")
    }
    
    func stopCommandListening() {
        listeningTimeout?.invalidate()
        listeningTimeout = nil
        isListening = false
    }
    
    // MARK: - Public Interface
    
    func getAgentStatus() -> String {
        switch agentState {
        case .idle:
            return "Agent offline"
        case .listeningForWakeWord:
            return "Listening for wake word"
        case .activated:
            return "Agent activated"
        case .listeningForCommand:
            return "Listening for command"
        case .processing:
            return "Processing request"
        }
    }
}

// MARK: - SFSpeechRecognizerDelegate

extension AgentLoopManager: SFSpeechRecognizerDelegate {
    func speechRecognizer(_ speechRecognizer: SFSpeechRecognizer, availabilityDidChange available: Bool) {
        if !available {
            Config.debugLog("Speech recognizer became unavailable")
        }
    }
}

// MARK: - VoiceActivityDetectorDelegate

extension AgentLoopManager: VoiceActivityDetectorDelegate {
    func voiceActivityDidStart() {
        handleVoiceActivityStart()
    }
    
    func voiceActivityDidEnd() {
        handleVoiceActivityEnd()
    }
}

// MARK: - Data Models

enum AgentState {
    case idle
    case listeningForWakeWord
    case activated
    case listeningForCommand
    case processing
}

enum AgentError: Error {
    case speechRecognitionSetupFailed
    case audioSessionSetupFailed
    case permissionDenied
}

// MARK: - Supporting Classes

class ConversationMemory {
    private var messages: [ConversationMessage] = []
    private let maxMessages = 50
    
    func addUserMessage(_ content: String) {
        let message = ConversationMessage(
            role: .user,
            content: content,
            timestamp: Date()
        )
        addMessage(message)
    }
    
    func addAssistantMessage(_ content: String) {
        let message = ConversationMessage(
            role: .assistant,
            content: content,
            timestamp: Date()
        )
        addMessage(message)
    }
    
    private func addMessage(_ message: ConversationMessage) {
        messages.append(message)
        
        // Keep only recent messages
        if messages.count > maxMessages {
            messages.removeFirst(messages.count - maxMessages)
        }
    }
    
    func getRecentHistory(limit: Int = 10) -> String {
        let recentMessages = messages.suffix(limit)
        return recentMessages.map { "\($0.role.rawValue): \($0.content)" }.joined(separator: "\n")
    }
    
    func clearHistory() {
        messages.removeAll()
    }
}

struct ConversationMessage {
    let role: MessageRole
    let content: String
    let timestamp: Date
}

enum MessageRole: String {
    case user = "User"
    case assistant = "Assistant"
}

class VoiceActivityDetector {
    weak var delegate: VoiceActivityDetectorDelegate?
    
    private var silenceThreshold: Float = -30.0
    private var voiceThreshold: Float = -20.0
    private var minimumSpeechDuration: TimeInterval = 0.5
    
    private var isVoiceActive = false
    private var voiceStartTime: Date?
    
    func configure(silenceThreshold: Float, voiceThreshold: Float, minimumSpeechDuration: TimeInterval) {
        self.silenceThreshold = silenceThreshold
        self.voiceThreshold = voiceThreshold
        self.minimumSpeechDuration = minimumSpeechDuration
    }
    
    func adjustForNoise(level: Float) {
        // Dynamically adjust thresholds based on noise level
        let noiseAdjustment = level * 10.0 // Scale noise level
        self.voiceThreshold = min(-15.0, -20.0 + noiseAdjustment)
        self.silenceThreshold = min(-25.0, -30.0 + noiseAdjustment)
    }
    
    func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        let averageLevel = calculateAverageLevel(buffer)
        
        if averageLevel > voiceThreshold {
            if !isVoiceActive {
                voiceStartTime = Date()
                isVoiceActive = true
                delegate?.voiceActivityDidStart()
            }
        } else if averageLevel < silenceThreshold {
            if isVoiceActive {
                if let startTime = voiceStartTime,
                   Date().timeIntervalSince(startTime) >= minimumSpeechDuration {
                    delegate?.voiceActivityDidEnd()
                }
                isVoiceActive = false
                voiceStartTime = nil
            }
        }
    }
    
    private func calculateAverageLevel(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData?[0] else { return -80.0 }
        
        let channelDataValueArray = stride(from: 0, to: Int(buffer.frameLength), by: buffer.stride).map { channelData[$0] }
        
        let rms = sqrt(channelDataValueArray.map { $0 * $0 }.reduce(0, +) / Float(channelDataValueArray.count))
        let avgPower = 20 * log10(rms)
        
        return avgPower.isFinite ? avgPower : -80.0
    }
}

protocol VoiceActivityDetectorDelegate: AnyObject {
    func voiceActivityDidStart()
    func voiceActivityDidEnd()
}

// MARK: - Noise Detection and Environmental Awareness

class NoiseDetector {
    private var recentNoiseReadings: [Float] = []
    private let maxReadings = 10
    
    func updateNoiseLevel(_ level: Float) {
        recentNoiseReadings.append(level)
        
        if recentNoiseReadings.count > maxReadings {
            recentNoiseReadings.removeFirst()
        }
    }
    
    func getCurrentNoiseLevel() -> Float {
        guard !recentNoiseReadings.isEmpty else { return 0.0 }
        return recentNoiseReadings.reduce(0, +) / Float(recentNoiseReadings.count)
    }
    
    func isNoisyEnvironment() -> Bool {
        return getCurrentNoiseLevel() > 0.7
    }
}

// MARK: - Audio Processing Extensions

extension AgentLoopManager {
    func updateEnvironmentalNoise(from audioBuffer: AVAudioPCMBuffer) {
        let noiseLevel = calculateNoiseLevel(audioBuffer)
        noiseDetector.updateNoiseLevel(noiseLevel)
        environmentalNoiseLevel = noiseDetector.getCurrentNoiseLevel()
        
        // Adapt behavior based on noise
        if noiseDetector.isNoisyEnvironment() {
            voiceActivityDetector.adjustForNoise(level: environmentalNoiseLevel)
        }
    }
    
    private func calculateNoiseLevel(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData?[0] else { return 0.0 }
        
        let frameLength = Int(buffer.frameLength)
        var rms: Float = 0.0
        
        for i in 0..<frameLength {
            rms += channelData[i] * channelData[i]
        }
        
        rms = sqrt(rms / Float(frameLength))
        return min(rms * 10, 1.0) // Normalize to 0-1 range
    }
} 