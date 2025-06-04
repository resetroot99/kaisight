import Foundation
import Speech
import AVFoundation
import Combine

class VoiceAgentLoop: NSObject, ObservableObject {
    @Published var isListening = false
    @Published var isProcessingCommand = false
    @Published var lastCommand = ""
    @Published var conversationHistory: [ConversationTurn] = []
    @Published var agentMode: AgentMode = .pushToTalk
    
    private let speechRecognizer = SFSpeechRecognizer()
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    
    private let whisperAPI = WhisperAPI()
    private let gptManager = GPTManager()
    private let speechOutput = SpeechOutput()
    private let cameraManager = CameraManager()
    private let navigationAssistant = NavigationAssistant()
    
    // Wake word detection
    private let wakeWords = ["hey assistant", "kai sight", "blind assistant"]
    private var isWakeWordDetected = false
    private var backgroundListeningTimer: Timer?
    
    // Conversation context
    private var conversationContext: String = ""
    private var lastInteractionTime = Date()
    private let contextTimeoutInterval: TimeInterval = 300 // 5 minutes
    
    // Command categories
    private let commandProcessor = CommandProcessor()
    
    override init() {
        super.init()
        setupAudioSession()
        requestPermissions()
    }
    
    private func setupAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playAndRecord, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
        }
    }
    
    private func requestPermissions() {
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                switch status {
                case .authorized:
                    ProductionConfig.log("Speech recognition authorized")
                case .denied:
                    break
                case .restricted, .notDetermined:
                    break
                @unknown default:
                    break
                }
            }
        }
    }
    
    func setAgentMode(_ mode: AgentMode) {
        agentMode = mode
        
        switch mode {
        case .pushToTalk:
            stopBackgroundListening()
            speechOutput.speak("Push to talk mode activated")
        case .wakeWord:
            startBackgroundListening()
            speechOutput.speak("Wake word mode activated. Say 'Hey Assistant' to start")
        case .continuous:
            startContinuousListening()
            speechOutput.speak("Continuous listening mode activated")
        }
    }
    
    // MARK: - Push to Talk Mode
    
    func startListening() {
        guard agentMode == .pushToTalk else { return }
        
        isListening = true
        captureAudioAndProcess()
    }
    
    func stopListening() {
        guard agentMode == .pushToTalk else { return }
        
        isListening = false
        stopAudioRecognition()
    }
    
    // MARK: - Wake Word Mode
    
    private func startBackgroundListening() {
        guard agentMode == .wakeWord else { return }
        
        backgroundListeningTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            self.listenForWakeWord()
        }
    }
    
    private func stopBackgroundListening() {
        backgroundListeningTimer?.invalidate()
        backgroundListeningTimer = nil
        stopAudioRecognition()
    }
    
    private func listenForWakeWord() {
        guard !isListening && !isProcessingCommand else { return }
        
        startAudioRecognition { [weak self] text in
            guard let self = self else { return }
            
            let lowercasedText = text.lowercased()
            let wakeWordDetected = self.wakeWords.contains { wakeWord in
                lowercasedText.contains(wakeWord)
            }
            
            if wakeWordDetected {
                self.isWakeWordDetected = true
                self.handleWakeWordDetection()
            }
        }
    }
    
    private func handleWakeWordDetection() {
        speechOutput.speak("Yes, I'm listening")
        
        // Start full command listening
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.captureAudioAndProcess()
        }
    }
    
    // MARK: - Continuous Mode
    
    private func startContinuousListening() {
        guard agentMode == .continuous else { return }
        
        // Implement continuous listening with voice activity detection
        startAudioRecognition { [weak self] text in
            guard let self = self else { return }
            
            // Process any speech longer than 3 words
            if text.split(separator: " ").count >= 3 {
                self.processVoiceCommand(text)
            }
        }
    }
    
    // MARK: - Audio Recognition
    
    private func startAudioRecognition(completion: @escaping (String) -> Void) {
        guard let speechRecognizer = speechRecognizer, speechRecognizer.isAvailable else {
            return
        }
        
        stopAudioRecognition()
        
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            self.recognitionRequest?.append(buffer)
        }
        
        audioEngine.prepare()
        
        do {
            try audioEngine.start()
        } catch {
            return
        }
        
        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest!) { result, error in
            if let result = result {
                let transcript = result.bestTranscription.formattedString
                
                if result.isFinal {
                    completion(transcript)
                }
            }
            
            if error != nil {
                self.stopAudioRecognition()
            }
        }
    }
    
    private func stopAudioRecognition() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        
        recognitionTask?.cancel()
        recognitionTask = nil
    }
    
    private func captureAudioAndProcess() {
        isListening = true
        
        // Use WhisperAPI for better accuracy
        whisperAPI.transcribeAudio { [weak self] transcription in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                self.isListening = false
                
                if let text = transcription, !text.isEmpty {
                    self.processVoiceCommand(text)
                } else {
                    self.speechOutput.speak("I didn't catch that. Please try again.")
                }
            }
        }
    }
    
    // MARK: - Command Processing
    
    private func processVoiceCommand(_ command: String) {
        guard !isProcessingCommand else { return }
        
        isProcessingCommand = true
        lastCommand = command
        lastInteractionTime = Date()
        
        // Add to conversation history
        let turn = ConversationTurn(
            userInput: command,
            timestamp: Date(),
            context: getCurrentContext()
        )
        conversationHistory.append(turn)
        
        // Process command through intelligent routing
        commandProcessor.processCommand(command, context: getFullContext()) { [weak self] response in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                // Update conversation history with response
                if var lastTurn = self.conversationHistory.last {
                    lastTurn.assistantResponse = response.text
                    lastTurn.actionTaken = response.action
                    self.conversationHistory[self.conversationHistory.count - 1] = lastTurn
                }
                
                // Execute response
                self.executeResponse(response)
                self.isProcessingCommand = false
                
                // Continue listening in continuous mode
                if self.agentMode == .continuous {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        self.startContinuousListening()
                    }
                }
            }
        }
    }
    
    private func executeResponse(_ response: CommandResponse) {
        // Speak the response
        speechOutput.speak(response.text, priority: response.priority)
        
        // Execute any associated actions
        switch response.action {
        case .none:
            break
        case .captureImage:
            cameraManager.capturePhoto()
        case .startNavigation(let destination):
            navigationAssistant.navigateToAddress(destination) { result in
                self.speechOutput.speak(result)
            }
        case .emergency:
            navigationAssistant.requestEmergencyHelp { emergencyMessage in
                self.speechOutput.speak(emergencyMessage, priority: .high)
            }
        case .startNarration:
            // Would integrate with RealTimeNarrator
            break
        }
    }
    
    private func getCurrentContext() -> String {
        // Check if previous context is still relevant
        if Date().timeIntervalSince(lastInteractionTime) > contextTimeoutInterval {
            conversationContext = ""
        }
        
        return conversationContext
    }
    
    private func getFullContext() -> ConversationContext {
        return ConversationContext(
            recentHistory: Array(conversationHistory.suffix(3)),
            currentLocation: navigationAssistant.currentLocation,
            timeOfDay: getCurrentTimeContext(),
            userPreferences: getUserPreferences()
        )
    }
    
    private func getCurrentTimeContext() -> String {
        let hour = Calendar.current.component(.hour, from: Date())
        
        switch hour {
        case 5..<12: return "morning"
        case 12..<17: return "afternoon"
        case 17..<21: return "evening"
        default: return "night"
        }
    }
    
    private func getUserPreferences() -> [String: Any] {
        // Load user preferences from UserDefaults or other storage
        return [
            "speechRate": 0.5,
            "preferredUnits": "metric",
            "navigationStyle": "detailed"
        ]
    }
}

// MARK: - Supporting Types

enum AgentMode: String, CaseIterable {
    case pushToTalk = "Push to Talk"
    case wakeWord = "Wake Word"
    case continuous = "Continuous"
}

struct ConversationTurn {
    let userInput: String
    var assistantResponse: String?
    var actionTaken: CommandAction?
    let timestamp: Date
    let context: String
}

struct ConversationContext {
    let recentHistory: [ConversationTurn]
    let currentLocation: CLLocation?
    let timeOfDay: String
    let userPreferences: [String: Any]
}

struct CommandResponse {
    let text: String
    let action: CommandAction
    let priority: SpeechPriority
}

enum CommandAction {
    case none
    case captureImage
    case startNavigation(destination: String)
    case emergency
    case startNarration
}

// MARK: - Command Processor

class CommandProcessor {
    private let gptManager = GPTManager()
    private let navigationAssistant = NavigationAssistant()
    
    func processCommand(_ command: String, context: ConversationContext, completion: @escaping (CommandResponse) -> Void) {
        
        // Quick pattern matching for common commands
        if let quickResponse = processQuickCommands(command) {
            completion(quickResponse)
            return
        }
        
        // Use GPT for complex command understanding
        let prompt = createCommandPrompt(command, context: context)
        
        gptManager.ask(prompt: prompt, image: nil) { response in
            let commandResponse = self.parseGPTResponse(response, originalCommand: command)
            completion(commandResponse)
        }
    }
    
    private func processQuickCommands(_ command: String) -> CommandResponse? {
        let lowercased = command.lowercased()
        
        // Navigation commands
        if lowercased.contains("take me home") || lowercased.contains("go home") {
            return CommandResponse(
                text: "Starting navigation to home",
                action: .startNavigation(destination: "home"),
                priority: .normal
            )
        }
        
        // Emergency commands
        if lowercased.contains("emergency") || lowercased.contains("help") {
            return CommandResponse(
                text: "Activating emergency assistance",
                action: .emergency,
                priority: .high
            )
        }
        
        // Description commands
        if lowercased.contains("what do you see") || lowercased.contains("describe") {
            return CommandResponse(
                text: "Let me describe what I see",
                action: .captureImage,
                priority: .normal
            )
        }
        
        return nil
    }
    
    private func createCommandPrompt(_ command: String, context: ConversationContext) -> String {
        var prompt = "You are a voice assistant for blind users. "
        prompt += "Analyze this command and respond appropriately: '\(command)'. "
        
        if !context.recentHistory.isEmpty {
            prompt += "Recent conversation: "
            for turn in context.recentHistory {
                prompt += "User: \(turn.userInput). Assistant: \(turn.assistantResponse ?? ""). "
            }
        }
        
        prompt += "Time of day: \(context.timeOfDay). "
        prompt += "Keep responses helpful, concise, and natural. "
        prompt += "If navigation is needed, mention the destination. "
        prompt += "For emergencies, be calm and clear."
        
        return prompt
    }
    
    private func parseGPTResponse(_ response: String, originalCommand: String) -> CommandResponse {
        // Simple parsing logic - in production, use more sophisticated NLP
        let lowercased = response.lowercased()
        
        var action: CommandAction = .none
        var priority: SpeechPriority = .normal
        
        if lowercased.contains("navigation") || lowercased.contains("directions") {
            action = .startNavigation(destination: extractDestination(from: originalCommand))
        } else if lowercased.contains("emergency") {
            action = .emergency
            priority = .high
        } else if lowercased.contains("describe") || lowercased.contains("see") {
            action = .captureImage
        }
        
        return CommandResponse(text: response, action: action, priority: priority)
    }
    
    private func extractDestination(from command: String) -> String {
        // Simple destination extraction
        if command.lowercased().contains("home") {
            return "home"
        }
        
        let words = command.components(separatedBy: " ")
        if let toIndex = words.firstIndex(where: { $0.lowercased() == "to" }),
           toIndex + 1 < words.count {
            return words[(toIndex + 1)...].joined(separator: " ")
        }
        
        return "unknown destination"
    }
} 