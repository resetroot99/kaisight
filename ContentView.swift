import SwiftUI
import AVFoundation

struct ContentView: View {
    @StateObject var cameraManager = CameraManager()
    @StateObject var audioManager = AudioManager()
    @StateObject var speechOutput = SpeechOutput()
    @StateObject var offlineWhisper = OfflineWhisperManager()
    @StateObject var objectDetection = ObjectDetectionManager()
    @StateObject var navigationAssistant = NavigationAssistant()
    
    let gpt = GPTManager()
    
    @State private var isRecording = false
    @State private var isProcessing = false
    @State private var statusMessage = "Ready to help you"
    @State private var showingSettings = false
    @State private var showingQuickActions = false
    @State private var useOfflineMode = false
    @State private var hasStartingPointSaved = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Enhanced status indicator with offline mode
                VStack {
                    HStack {
                        Image(systemName: statusIcon)
                            .font(.system(size: 40))
                            .foregroundColor(statusColor)
                            .accessibilityLabel(statusMessage)
                        
                        if useOfflineMode {
                            Image(systemName: "wifi.slash")
                                .font(.system(size: 20))
                                .foregroundColor(.orange)
                                .accessibilityLabel("Offline mode")
                        }
                    }
                    
                    Text(statusMessage)
                        .font(.headline)
                        .multilineTextAlignment(.center)
                        .accessibilityLiveRegion(.polite)
                }
                .padding()
                
                // Camera preview with object detection overlay
                ZStack {
                    CameraPreview(session: cameraManager.getSession())
                        .frame(height: 200)
                        .cornerRadius(12)
                        .accessibilityHidden(true)
                    
                    // Object detection overlay (visual feedback)
                    if !objectDetection.detectedObjects.isEmpty {
                        VStack {
                            Spacer()
                            HStack {
                                Text("\(objectDetection.detectedObjects.count) objects detected")
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.blue.opacity(0.8))
                                    .foregroundColor(.white)
                                    .cornerRadius(8)
                                Spacer()
                            }
                        }
                        .padding(8)
                    }
                }
                
                // Main action button with enhanced features
                Button(action: handleVoiceQuery) {
                    VStack {
                        Image(systemName: isRecording ? "stop.circle.fill" : "mic.circle.fill")
                            .font(.system(size: 60))
                        Text(isRecording ? "Recording..." : "Start Voice Query")
                            .font(.title2)
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 120)
                    .background(buttonColor)
                    .cornerRadius(20)
                    .scaleEffect(isRecording ? 1.1 : 1.0)
                    .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: isRecording)
                }
                .disabled(isProcessing)
                .accessibilityLabel(isRecording ? "Stop recording" : "Start voice query")
                .accessibilityHint("Double tap to start recording your question")
                
                // Enhanced Quick Actions Row
                HStack(spacing: 12) {
                    // Quick Actions Button
                    Button(action: { showingQuickActions = true }) {
                        VStack {
                            Image(systemName: "bolt.circle.fill")
                                .font(.title)
                            Text("Quick\nActions")
                                .font(.caption)
                                .multilineTextAlignment(.center)
                        }
                        .foregroundColor(.blue)
                        .frame(maxWidth: .infinity)
                        .frame(height: 60)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(12)
                    }
                    .accessibilityLabel("Quick Actions")
                    .accessibilityHint("Access common voice commands")
                    
                    // Object Scan Button
                    Button(action: quickObjectScan) {
                        VStack {
                            Image(systemName: "viewfinder.circle.fill")
                                .font(.title)
                            Text("Quick\nScan")
                                .font(.caption)
                                .multilineTextAlignment(.center)
                        }
                        .foregroundColor(.orange)
                        .frame(maxWidth: .infinity)
                        .frame(height: 60)
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(12)
                    }
                    .accessibilityLabel("Quick Object Scan")
                    .accessibilityHint("Instantly identify objects")
                    
                    // Home Button
                    Button(action: returnHome) {
                        VStack {
                            Image(systemName: "house.circle.fill")
                                .font(.title)
                            Text("Return\nHome")
                                .font(.caption)
                                .multilineTextAlignment(.center)
                        }
                        .foregroundColor(.blue)
                        .frame(maxWidth: .infinity)
                        .frame(height: 60)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(12)
                    }
                    .accessibilityLabel("Return Home")
                    .accessibilityHint("Get directions back home")
                    
                    // Save/Return to Start Button
                    Button(action: handleStartingPoint) {
                        VStack {
                            Image(systemName: hasStartingPointSaved ? "arrow.uturn.backward.circle.fill" : "mappin.circle.fill")
                                .font(.title)
                            Text(hasStartingPointSaved ? "Return to\nStart" : "Save\nStart")
                                .font(.caption)
                                .multilineTextAlignment(.center)
                        }
                        .foregroundColor(hasStartingPointSaved ? .cyan : .purple)
                        .frame(maxWidth: .infinity)
                        .frame(height: 60)
                        .background((hasStartingPointSaved ? Color.cyan : Color.purple).opacity(0.1))
                        .cornerRadius(12)
                    }
                    .accessibilityLabel(hasStartingPointSaved ? "Return to starting point" : "Save starting point")
                    .accessibilityHint(hasStartingPointSaved ? "Get directions back to where you started" : "Mark this location as your starting point")
                }
                .disabled(isProcessing)
                
                // Navigation status (if active)
                if navigationAssistant.isNavigating {
                    Button(action: { 
                        speechOutput.speak(navigationAssistant.getNavigationSummary())
                    }) {
                        HStack {
                            Image(systemName: "location.north.circle.fill")
                                .foregroundColor(.red)
                            Text("Navigation Active")
                                .font(.headline)
                            Spacer()
                            Image(systemName: "speaker.wave.2.fill")
                                .foregroundColor(.red)
                        }
                        .padding()
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(12)
                    }
                    .accessibilityLabel("Navigation active, tap for status")
                }
                
                Spacer()
            }
            .padding()
            .navigationTitle("BlindAssistant")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: { useOfflineMode.toggle() }) {
                        Image(systemName: useOfflineMode ? "wifi.slash" : "wifi")
                            .font(.title2)
                            .foregroundColor(useOfflineMode ? .orange : .blue)
                    }
                    .accessibilityLabel(useOfflineMode ? "Switch to online mode" : "Switch to offline mode")
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { showingSettings = true }) {
                        Image(systemName: "gear")
                            .font(.title2)
                    }
                    .accessibilityLabel("Settings")
                    .accessibilityHint("Opens app settings")
                }
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(speechOutput: speechOutput, audioManager: audioManager)
        }
        .sheet(isPresented: $showingQuickActions) {
            QuickActionsView(
                cameraManager: cameraManager,
                speechOutput: speechOutput,
                gpt: gpt
            )
        }
        .onAppear {
            setupAccessibility()
            updateStatus("Ready to help you")
            checkStartingPointStatus()
        }
        .onChange(of: useOfflineMode) { offline in
            let mode = offline ? "offline" : "online"
            speechOutput.speakStatus("Switched to \(mode) mode")
        }
    }
    
    // MARK: - UI Properties
    
    private var statusIcon: String {
        if isRecording { return "waveform" }
        if isProcessing { return "gear" }
        if useOfflineMode { return "eye.slash" }
        return "eye"
    }
    
    private var statusColor: Color {
        if isRecording { return .red }
        if isProcessing { return .orange }
        if useOfflineMode { return .orange }
        return .blue
    }
    
    private var buttonColor: Color {
        if isRecording { return .red }
        if isProcessing { return .gray }
        return .blue
    }
    
    // MARK: - Action Methods
    
    private func handleVoiceQuery() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }
    
    private func startRecording() {
        isRecording = true
        updateStatus("Listening... Speak now")
        
        // Haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
        
        // Capture photo first
        cameraManager.capturePhoto()
        
        // Choose recording method based on mode
        if useOfflineMode && offlineWhisper.isAvailable {
            // Use offline speech recognition
            offlineWhisper.startRecording { [self] transcription in
                DispatchQueue.main.async {
                    self.isRecording = false
                    self.processTranscription(transcription)
                }
            }
        } else {
            // Use online Whisper API
            audioManager.startRecording { [self] transcription in
                DispatchQueue.main.async {
                    self.isRecording = false
                    self.processTranscription(transcription)
                }
            }
        }
    }
    
    private func stopRecording() {
        if useOfflineMode {
            offlineWhisper.stopRecording()
        } else {
            audioManager.stopRecording()
        }
        isRecording = false
        updateStatus("Processing...")
    }
    
    private func processTranscription(_ transcription: String?) {
        guard let transcription = transcription, !transcription.isEmpty else {
            updateStatus("I couldn't understand. Please try again.")
            speechOutput.speakStatus("I couldn't understand. Please try again.")
            return
        }
        
        isProcessing = true
        updateStatus("Analyzing scene and your question...")
        
        // Enhanced command recognition
        if isReturnHomeRequest(transcription) {
            handleReturnHomeRequest()
            return
        }
        
        if isReturnToStartRequest(transcription) {
            handleReturnToStartRequest()
            return
        }
        
        if isFindContactRequest(transcription) {
            handleFindContactRequest(transcription)
            return
        }
        
        if isEmergencyRequest(transcription) {
            handleEmergencyRequest()
            return
        }
        
        // Check if this is a navigation request
        if isNavigationRequest(transcription) {
            handleNavigationRequest(transcription)
            return
        }
        
        // Regular GPT analysis
        gpt.ask(prompt: transcription, image: cameraManager.capturedImage) { reply in
            DispatchQueue.main.async {
                self.isProcessing = false
                self.updateStatus("Ready to help you")
                self.speechOutput.speak(reply)
                
                // Success haptic
                let notificationFeedback = UINotificationFeedbackGenerator()
                notificationFeedback.notificationOccurred(.success)
            }
        }
    }
    
    private func quickObjectScan() {
        guard !isProcessing else { return }
        
        isProcessing = true
        updateStatus("Scanning objects...")
        
        cameraManager.capturePhoto()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if let image = cameraManager.capturedImage {
                objectDetection.quickScan(image: image) { description in
                    speechOutput.speak(description)
                    isProcessing = false
                    updateStatus("Ready to help you")
                }
            } else {
                speechOutput.speak("Unable to capture image")
                isProcessing = false
                updateStatus("Ready to help you")
            }
        }
    }
    
    private func returnHome() {
        guard !isProcessing else { return }
        
        isProcessing = true
        updateStatus("Getting directions home...")
        
        navigationAssistant.returnHome { response in
            speechOutput.speak(response)
            isProcessing = false
            updateStatus("Ready to help you")
        }
    }
    
    private func handleStartingPoint() {
        guard !isProcessing else { return }
        
        if hasStartingPointSaved {
            // Return to starting point
            isProcessing = true
            updateStatus("Getting directions to starting point...")
            
            navigationAssistant.returnToStartingPoint { response in
                speechOutput.speak(response)
                isProcessing = false
                updateStatus("Ready to help you")
            }
        } else {
            // Save starting point
            navigationAssistant.saveStartingLocation()
            hasStartingPointSaved = true
            speechOutput.speak("Starting point saved. You can now return here anytime.")
            
            // Haptic feedback
            let notificationFeedback = UINotificationFeedbackGenerator()
            notificationFeedback.notificationOccurred(.success)
        }
    }
    
    private func checkStartingPointStatus() {
        // Check if there's a saved starting point
        hasStartingPointSaved = !navigationAssistant.locationHistory.filter { $0.category == .startingPoint }.isEmpty
    }
    
    // MARK: - Enhanced Command Recognition
    
    private func isReturnHomeRequest(_ text: String) -> Bool {
        let homeKeywords = ["go home", "return home", "take me home", "directions home", "navigate home"]
        let lowercased = text.lowercased()
        return homeKeywords.contains { lowercased.contains($0) }
    }
    
    private func isReturnToStartRequest(_ text: String) -> Bool {
        let startKeywords = ["return to start", "go back to start", "starting point", "where I started", "beginning"]
        let lowercased = text.lowercased()
        return startKeywords.contains { lowercased.contains($0) }
    }
    
    private func isFindContactRequest(_ text: String) -> Bool {
        let contactKeywords = ["find", "locate", "where is", "nearest contact", "family", "friend"]
        let lowercased = text.lowercased()
        return contactKeywords.contains { lowercased.contains($0) }
    }
    
    private func isEmergencyRequest(_ text: String) -> Bool {
        let emergencyKeywords = ["emergency", "help", "911", "urgent", "crisis", "danger"]
        let lowercased = text.lowercased()
        return emergencyKeywords.contains { lowercased.contains($0) }
    }
    
    private func isNavigationRequest(_ text: String) -> Bool {
        let navigationKeywords = ["navigate", "directions", "go to", "take me", "find route"]
        let lowercased = text.lowercased()
        return navigationKeywords.contains { lowercased.contains($0) }
    }
    
    // MARK: - Enhanced Command Handlers
    
    private func handleReturnHomeRequest() {
        navigationAssistant.returnHome { result in
            DispatchQueue.main.async {
                self.speechOutput.speak(result)
                self.isProcessing = false
                self.updateStatus("Ready to help you")
            }
        }
    }
    
    private func handleReturnToStartRequest() {
        navigationAssistant.returnToStartingPoint { result in
            DispatchQueue.main.async {
                self.speechOutput.speak(result)
                self.isProcessing = false
                self.updateStatus("Ready to help you")
            }
        }
    }
    
    private func handleFindContactRequest(_ text: String) {
        // Try to extract contact name from the request
        let words = text.components(separatedBy: " ")
        if let findIndex = words.firstIndex(where: { $0.lowercased().contains("find") || $0.lowercased().contains("locate") }),
           findIndex + 1 < words.count {
            let contactName = words[(findIndex + 1)...].joined(separator: " ")
            
            navigationAssistant.navigateToContact(contactName) { result in
                DispatchQueue.main.async {
                    self.speechOutput.speak(result)
                    self.isProcessing = false
                    self.updateStatus("Ready to help you")
                }
            }
        } else {
            // Find nearest contact
            navigationAssistant.findNearestEmergencyContact { result in
                DispatchQueue.main.async {
                    self.speechOutput.speak(result)
                    self.isProcessing = false
                    self.updateStatus("Ready to help you")
                }
            }
        }
    }
    
    private func handleEmergencyRequest() {
        navigationAssistant.requestEmergencyHelp { emergencyMessage in
            DispatchQueue.main.async {
                self.speechOutput.speak("Emergency assistance activated. " + emergencyMessage, priority: .high)
                self.isProcessing = false
                self.updateStatus("Emergency mode")
            }
        }
    }
    
    private func handleNavigationRequest(_ text: String) {
        // Extract destination from text (simplified)
        let components = text.components(separatedBy: " ")
        if let toIndex = components.firstIndex(where: { $0.lowercased() == "to" }),
           toIndex + 1 < components.count {
            let destination = components[(toIndex + 1)...].joined(separator: " ")
            
            navigationAssistant.navigateToAddress(destination) { result in
                DispatchQueue.main.async {
                    self.speechOutput.speak(result)
                    self.isProcessing = false
                    self.updateStatus("Ready to help you")
                }
            }
        } else {
            speechOutput.speak("I couldn't understand the destination. Please say 'navigate to' followed by the address.")
            isProcessing = false
            updateStatus("Ready to help you")
        }
    }
    
    private func updateStatus(_ message: String) {
        statusMessage = message
        // Announce status changes to VoiceOver users
        UIAccessibility.post(notification: .announcement, argument: message)
    }
    
    private func setupAccessibility() {
        // Ensure VoiceOver announces important changes
        UIAccessibility.post(notification: .screenChanged, argument: nil)
    }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.frame = CGRect(x: 0, y: 0, width: 300, height: 200)
        preview.videoGravity = .resizeAspectFill
        preview.cornerRadius = 12
        view.layer.addSublayer(preview)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        if let layer = uiView.layer.sublayers?.first as? AVCaptureVideoPreviewLayer {
            layer.frame = uiView.bounds
        }
    }
} 