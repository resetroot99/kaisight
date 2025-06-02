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
    
    override init() {
        super.init()
        setupAgentLoop()
    }
    
    // MARK: - Setup
    
    private func setupAgentLoop() {
        setupSpeechRecognition()
        setupVoiceActivityDetection()
        startWakeWordDetection()
        
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
        for wakeWord in wakeWords {
            if transcript.contains(wakeWord) {
                wakeWordDetected = true
                activateAgent()
                break
            }
        }
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