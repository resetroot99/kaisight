import SwiftUI
import AVFoundation
import Vision
import Combine
import UIKit

struct KaiSightMainView: View {
    // Core Managers
    @StateObject var cameraManager = CameraManager()
    @StateObject var audioManager = AudioManager()
    @StateObject var gptManager = GPTManager()
    @StateObject var speechOutput = SpeechOutput()
    @StateObject var objectDetection = ObjectDetectionManager()
    @StateObject var navigationAssistant = NavigationAssistant()
    
    // Enhanced Features
    @StateObject var realTimeNarrator = RealTimeNarrator()
    @StateObject var voiceAgent = VoiceAgentLoop()
    @StateObject var familiarRecognition = FamiliarRecognition()
    
    // Phase 2 advanced managers
    @StateObject var spatialMapping = SpatialMappingManager()
    @StateObject var obstacleDetection = ObstacleDetectionManager()
    @StateObject var cloudSync = CloudSyncManager()
    
    // UI State
    @State private var currentMode: KaiSightMode = .standard
    @State private var showingSettings = false
    @State private var showingFamiliarPeople = false
    @State private var statusMessage = "KaiSight ready"
    @State private var isProcessing = false
    
    // Phase 2 UI state
    @State private var showSpatialMapping = false
    @State private var showObstacleDetection = false
    @State private var showCloudSync = false
    @State private var spatialMappingActive = false
    @State private var obstacleDetectionActive = false
    
    var body: some View {
        NavigationView {
            GeometryReader { geometry in
                ZStack {
                    // Camera preview
                    CameraPreviewView(session: cameraManager.session)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                        .accessibilityHidden(true)
                    
                    // Main overlay
                    VStack {
                        // Top status bar with Phase 2 indicators
                        topStatusBar
                        
                        Spacer()
                        
                        // Quick actions with Phase 2 features
                        quickActionsPanel
                        
                        Spacer()
                        
                        // Main control buttons
                        mainControlButtons
                        
                        // Phase 2 advanced controls
                        phase2ControlButtons
                        
                        Spacer()
                        
                        // Bottom status with sync indicator
                        bottomStatusWithSync
                    }
                    .padding()
                    
                    // Phase 2 overlay panels
                    if showSpatialMapping {
                        spatialMappingPanel
                    }
                    
                    if showObstacleDetection {
                        obstacleDetectionPanel
                    }
                    
                    if showCloudSync {
                        cloudSyncPanel
                    }
                }
            }
            .navigationTitle("KaiSight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                toolbarContent
            }
        }
        .sheet(isPresented: $showingSettings) {
            EnhancedSettingsView(
                speechOutput: speechOutput,
                realTimeNarrator: realTimeNarrator,
                voiceAgent: voiceAgent,
                familiarRecognition: familiarRecognition
            )
        }
        .sheet(isPresented: $showingFamiliarPeople) {
            FamiliarPeopleView(familiarRecognition: familiarRecognition)
        }
        .onAppear {
            setupKaiSight()
        }
        .onChange(of: currentMode) { mode in
            handleModeChange(mode)
        }
        .onChange(of: spatialMappingActive) { active in
            if active {
                spatialMapping.startSpatialMapping()
            } else {
                spatialMapping.stopSpatialMapping()
            }
        }
        .onChange(of: obstacleDetectionActive) { active in
            if active {
                obstacleDetection.startObstacleDetection()
            } else {
                obstacleDetection.stopObstacleDetection()
            }
        }
    }
    
    // MARK: - UI Components
    
    private var statusHeader: some View {
        VStack(spacing: 8) {
            HStack {
                // Mode Indicator
                Image(systemName: modeIcon)
                    .font(.system(size: 24))
                    .foregroundColor(modeColor)
                    .accessibilityLabel("Current mode: \(currentMode.rawValue)")
                
                Spacer()
                
                // Real-time Info
                if realTimeNarrator.isNarrating {
                    VStack(alignment: .trailing) {
                        Text("Live Narration")
                            .font(.caption)
                            .foregroundColor(.green)
                        
                        Text("\(realTimeNarrator.detectedObjects.count) objects")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                
                // Voice Agent Status
                if voiceAgent.isListening {
                    Image(systemName: "mic.fill")
                        .font(.title2)
                        .foregroundColor(.red)
                        .pulsating()
                }
            }
            .padding(.horizontal)
            
            // Status Message
            Text(statusMessage)
                .font(.title3)
                .fontWeight(.medium)
                .multilineTextAlignment(.center)
                .accessibilityLiveRegion(.polite)
            
            // Current Narration
            if !realTimeNarrator.currentNarration.isEmpty {
                Text(realTimeNarrator.currentNarration)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.horizontal)
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(12)
        .padding(.horizontal)
    }
    
    private var mainContentArea: some View {
        HStack(spacing: 16) {
            // Camera Preview
            ZStack {
                CameraPreview(session: cameraManager.getSession())
                    .aspectRatio(4/3, contentMode: .fit)
                    .cornerRadius(12)
                    .accessibilityHidden(true)
                
                // Recognition Overlays
                if !familiarRecognition.recognitionResults.isEmpty {
                    recognitionOverlay
                }
            }
            
            // Information Panel
            informationPanel
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal)
    }
    
    private var recognitionOverlay: some View {
        VStack {
            ForEach(Array(familiarRecognition.recognitionResults.enumerated()), id: \.offset) { index, result in
                HStack {
                    Image(systemName: result.type == .person ? "person.fill" : "cube.fill")
                        .foregroundColor(result.type == .person ? .blue : .orange)
                    
                    Text(result.name)
                        .font(.caption)
                        .fontWeight(.semibold)
                    
                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.black.opacity(0.7))
                .foregroundColor(.white)
                .cornerRadius(8)
            }
            Spacer()
        }
        .padding(8)
    }
    
    private var informationPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Navigation Status
            if navigationAssistant.isNavigating {
                VStack(alignment: .leading) {
                    Text("Navigation Active")
                        .font(.headline)
                        .foregroundColor(.red)
                    
                    Text(navigationAssistant.getNavigationSummary())
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color.red.opacity(0.1))
                .cornerRadius(8)
            }
            
            // Recent Conversation
            if let lastCommand = voiceAgent.conversationHistory.last {
                VStack(alignment: .leading) {
                    Text("Last Command")
                        .font(.headline)
                    
                    Text(lastCommand.userInput)
                        .font(.caption)
                        .italic()
                    
                    if let response = lastCommand.assistantResponse {
                        Text(response)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
                .background(Color.blue.opacity(0.1))
                .cornerRadius(8)
            }
            
            // Familiar Faces Detected
            let familiarPeople = familiarRecognition.recognitionResults.filter { $0.type == .person }
            if !familiarPeople.isEmpty {
                VStack(alignment: .leading) {
                    Text("People Nearby")
                        .font(.headline)
                    
                    ForEach(Array(familiarPeople.enumerated()), id: \.offset) { index, person in
                        HStack {
                            Image(systemName: "person.circle.fill")
                                .foregroundColor(.blue)
                            Text(person.name)
                                .font(.caption)
                            Spacer()
                            Text("\(Int(person.confidence * 100))%")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding()
                .background(Color.green.opacity(0.1))
                .cornerRadius(8)
            }
            
            Spacer()
        }
    }
    
    private var quickActionsGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 12) {
            // Mode Controls
            KaiSightActionButton(
                title: "Standard",
                icon: "eye.fill",
                color: currentMode == .standard ? .blue : .gray,
                isSelected: currentMode == .standard
            ) {
                currentMode = .standard
            }
            
            KaiSightActionButton(
                title: "Narration",
                icon: "speaker.wave.2.fill",
                color: currentMode == .narration ? .green : .gray,
                isSelected: currentMode == .narration
            ) {
                currentMode = .narration
            }
            
            KaiSightActionButton(
                title: "Recognition",
                icon: "person.2.fill",
                color: currentMode == .recognition ? .purple : .gray,
                isSelected: currentMode == .recognition
            ) {
                currentMode = .recognition
            }
            
            // Quick Actions
            KaiSightActionButton(
                title: "Describe",
                icon: "eye.circle.fill",
                color: .orange
            ) {
                describeScene()
            }
            
            KaiSightActionButton(
                title: "Find People",
                icon: "person.crop.circle.fill",
                color: .mint
            ) {
                findFamiliarPeople()
            }
            
            KaiSightActionButton(
                title: "Navigate",
                icon: "location.circle.fill",
                color: .indigo
            ) {
                showNavigationOptions()
            }
            
            KaiSightActionButton(
                title: "Emergency",
                icon: "phone.circle.fill",
                color: .red
            ) {
                activateEmergency()
            }
            
            KaiSightActionButton(
                title: "Add Person",
                icon: "person.badge.plus.fill",
                color: .teal
            ) {
                showingFamiliarPeople = true
            }
            
            KaiSightActionButton(
                title: "Settings",
                icon: "gear.circle.fill",
                color: .secondary
            ) {
                showingSettings = true
            }
        }
        .padding(.horizontal)
    }
    
    private var voiceControlsArea: some View {
        HStack(spacing: 20) {
            // Voice Agent Mode Selector
            Picker("Voice Mode", selection: $voiceAgent.agentMode) {
                ForEach(AgentMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
            .frame(maxWidth: .infinity)
            
            // Main Voice Button
            Button(action: handleVoiceInput) {
                VStack {
                    Image(systemName: voiceAgent.isListening ? "stop.circle.fill" : "mic.circle.fill")
                        .font(.system(size: 40))
                    Text(voiceAgent.isListening ? "Stop" : "Talk")
                        .font(.caption)
                }
                .foregroundColor(.white)
                .frame(width: 80, height: 80)
                .background(voiceAgent.isListening ? Color.red : Color.blue)
                .cornerRadius(40)
                .scaleEffect(voiceAgent.isListening ? 1.1 : 1.0)
                .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: voiceAgent.isListening)
            }
            .disabled(isProcessing)
            .accessibilityLabel(voiceAgent.isListening ? "Stop listening" : "Start voice command")
        }
        .padding(.horizontal)
    }
    
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            HStack {
                Text("KaiSight")
                    .font(.title2)
                    .fontWeight(.bold)
                
                if isProcessing {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }
        }
        
        ToolbarItem(placement: .topBarTrailing) {
            HStack {
                // Battery status for awareness
                if UIDevice.current.batteryLevel > 0 {
                    Text("\(Int(UIDevice.current.batteryLevel * 100))%")
                        .font(.caption)
                        .foregroundColor(UIDevice.current.batteryLevel < 0.2 ? .red : .secondary)
                }
                
                Button(action: { showingSettings = true }) {
                    Image(systemName: "gear")
                        .font(.title2)
                }
                .accessibilityLabel("Settings")
            }
        }
    }
    
    // MARK: - UI Properties
    
    private var modeIcon: String {
        switch currentMode {
        case .standard: return "eye.fill"
        case .narration: return "speaker.wave.2.fill"
        case .recognition: return "person.2.fill"
        }
    }
    
    private var modeColor: Color {
        switch currentMode {
        case .standard: return .blue
        case .narration: return .green
        case .recognition: return .purple
        }
    }
    
    // MARK: - Actions
    
    private func setupKaiSight() {
        statusMessage = "KaiSight ready - Choose your mode"
        speechOutput.speak("Welcome to KaiSight. Your enhanced vision assistant is ready.")
        
        // Enable battery monitoring
        UIDevice.current.isBatteryMonitoringEnabled = true
        
        setupCoreFeatures()
        setupPhase2Features()
    }
    
    private func setupCoreFeatures() {
        // Initialize spatial mapping if supported
        if ARWorldTrackingConfiguration.isSupported {
            spatialMapping.startSpatialMapping()
            spatialMappingActive = true
        }
        
        // Initialize advanced obstacle detection
        obstacleDetection.startObstacleDetection()
        obstacleDetectionActive = true
        
        // Initialize cloud sync
        if cloudSync.cloudAccountStatus == .available {
            cloudSync.startManualSync()
        }
        
        Config.debugLog("KaiSight core features initialized")
    }
    
    private func setupPhase2Features() {
        // Initialize spatial mapping if supported
        if ARWorldTrackingConfiguration.isSupported {
            spatialMapping.startSpatialMapping()
            spatialMappingActive = true
        }
        
        // Initialize advanced obstacle detection
        obstacleDetection.startObstacleDetection()
        obstacleDetectionActive = true
        
        // Initialize cloud sync
        if cloudSync.cloudAccountStatus == .available {
            cloudSync.startManualSync()
        }
        
        Config.debugLog("KaiSight Phase 2 features initialized")
    }
    
    private func handleModeChange(_ mode: KaiSightMode) {
        switch mode {
        case .standard:
            realTimeNarrator.stopNarration()
            statusMessage = "Standard mode - Tap actions or use voice"
            speechOutput.speak("Standard mode activated")
            
        case .narration:
            realTimeNarrator.startNarration()
            statusMessage = "Live narration mode - Describing surroundings"
            speechOutput.speak("Real-time narration mode activated")
            
        case .recognition:
            statusMessage = "Recognition mode - Identifying familiar faces and objects"
            speechOutput.speak("Familiar recognition mode activated")
            startContinuousRecognition()
        }
    }
    
    private func handleVoiceInput() {
        switch voiceAgent.agentMode {
        case .pushToTalk:
            if voiceAgent.isListening {
                voiceAgent.stopListening()
            } else {
                voiceAgent.startListening()
            }
        case .wakeWord, .continuous:
            // Mode is managed automatically by the agent
            break
        }
    }
    
    private func describeScene() {
        isProcessing = true
        statusMessage = "Analyzing scene..."
        
        cameraManager.capturePhoto()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            // Combine regular description with familiar recognition
            let group = DispatchGroup()
            var sceneDescription = ""
            var familiarEntities: [String] = []
            
            // Get regular scene description
            group.enter()
            let gpt = GPTManager()
            gpt.ask(prompt: "Describe this scene in detail for a blind user", image: cameraManager.capturedImage) { description in
                sceneDescription = description
                group.leave()
            }
            
            // Get familiar recognition
            group.enter()
            if let image = cameraManager.capturedImage {
                familiarRecognition.recognizeFamiliarEntities(in: image) { results in
                    familiarEntities = results.map { "\($0.name) (\($0.details))" }
                    group.leave()
                }
            } else {
                group.leave()
            }
            
            group.notify(queue: .main) {
                var fullDescription = sceneDescription
                
                if !familiarEntities.isEmpty {
                    fullDescription += " I recognize: \(familiarEntities.joined(separator: ", "))"
                }
                
                speechOutput.speak(fullDescription)
                statusMessage = "Scene described"
                isProcessing = false
            }
        }
    }
    
    private func findFamiliarPeople() {
        guard let image = cameraManager.capturedImage else {
            speechOutput.speak("Please wait for camera to be ready")
            return
        }
        
        isProcessing = true
        statusMessage = "Looking for familiar people..."
        
        familiarRecognition.recognizeFamiliarEntities(in: image) { results in
            let people = results.filter { $0.type == .person }
            
            if people.isEmpty {
                speechOutput.speak("No familiar people detected in view")
            } else {
                let descriptions = people.map { "\($0.name), \($0.details)" }
                speechOutput.speak("I can see: \(descriptions.joined(separator: ", "))")
            }
            
            statusMessage = "KaiSight ready"
            isProcessing = false
        }
    }
    
    private func showNavigationOptions() {
        let alert = UIAlertController(title: "Navigation", message: "Choose navigation option", preferredStyle: .actionSheet)
        
        alert.addAction(UIAlertAction(title: "Go Home", style: .default) { _ in
            navigationAssistant.returnHome { result in
                speechOutput.speak(result)
            }
        })
        
        alert.addAction(UIAlertAction(title: "Find Nearest Contact", style: .default) { _ in
            navigationAssistant.findNearestEmergencyContact { result in
                speechOutput.speak(result)
            }
        })
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first {
            window.rootViewController?.present(alert, animated: true)
        }
    }
    
    private func activateEmergency() {
        navigationAssistant.requestEmergencyHelp { emergencyMessage in
            speechOutput.speak("Emergency assistance activated. \(emergencyMessage)", priority: .high)
        }
    }
    
    private func startContinuousRecognition() {
        Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { timer in
            guard currentMode == .recognition else {
                timer.invalidate()
                return
            }
            
            guard let image = cameraManager.capturedImage else { return }
            
            familiarRecognition.recognizeFamiliarEntities(in: image) { results in
                // Update UI with recognition results
                // Results are automatically published via @Published
            }
        }
    }
    
    // MARK: - Phase 2 UI Components
    
    private var topStatusBar: some View {
        HStack {
            // Mode Indicator
            Image(systemName: modeIcon)
                .font(.system(size: 24))
                .foregroundColor(modeColor)
                .accessibilityLabel("Current mode: \(currentMode.rawValue)")
            
            Spacer()
            
            // Phase 2 status indicators
            if spatialMapping.isARActive {
                Label("AR", systemImage: "arkit")
                    .font(.caption)
                    .foregroundColor(.blue)
                    .accessibilityLabel("Spatial mapping active")
            }
            
            if obstacleDetection.isActive {
                Label("LiDAR", systemImage: "sensor.fill")
                    .font(.caption)
                    .foregroundColor(.green)
                    .accessibilityLabel("Advanced obstacle detection active")
            }
            
            // Cloud sync status
            syncStatusIndicator
            
            Spacer()
            
            // Real-time Info
            if realTimeNarrator.isNarrating {
                VStack(alignment: .trailing) {
                    Text("Live Narration")
                        .font(.caption)
                        .foregroundColor(.green)
                    
                    Text("\(realTimeNarrator.detectedObjects.count) objects")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            // Voice Agent Status
            if voiceAgent.isListening {
                Image(systemName: "mic.fill")
                    .font(.title2)
                    .foregroundColor(.red)
                    .pulsating()
            }
        }
        .padding(.horizontal)
        .padding(.top)
    }
    
    private var syncStatusIndicator: some View {
        Group {
            switch cloudSync.syncStatus {
            case .syncing:
                Label("\(Int(cloudSync.syncProgress * 100))%", systemImage: "icloud.and.arrow.up")
                    .font(.caption)
                    .foregroundColor(.orange)
            case .completed:
                Label("Synced", systemImage: "icloud.fill")
                    .font(.caption)
                    .foregroundColor(.green)
            case .failed:
                Label("Sync Failed", systemImage: "icloud.slash")
                    .font(.caption)
                    .foregroundColor(.red)
            case .idle:
                if cloudSync.cloudAccountStatus == .available {
                    Label("Cloud", systemImage: "icloud")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
        }
        .accessibilityLabel(cloudSync.getSyncStatusDescription())
    }
    
    private var phase2ControlButtons: some View {
        HStack(spacing: 20) {
            // Spatial mapping toggle
            Button(action: {
                spatialMappingActive.toggle()
                provideFeedback()
            }) {
                VStack {
                    Image(systemName: spatialMappingActive ? "arkit" : "arkit")
                        .font(.title2)
                        .foregroundColor(spatialMappingActive ? .blue : .white)
                    Text("Spatial Map")
                        .font(.caption)
                }
            }
            .frame(width: 80, height: 60)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(spatialMappingActive ? Color.blue.opacity(0.3) : Color.black.opacity(0.6))
            )
            .accessibilityLabel("Spatial mapping")
            .accessibilityHint("Toggle 3D room mapping and navigation anchors")
            .onTapGesture {
                showSpatialMapping = true
            }
            
            // Advanced obstacle detection toggle
            Button(action: {
                obstacleDetectionActive.toggle()
                provideFeedback()
            }) {
                VStack {
                    Image(systemName: obstacleDetectionActive ? "sensor.fill" : "sensor")
                        .font(.title2)
                        .foregroundColor(obstacleDetectionActive ? .green : .white)
                    Text("LiDAR Nav")
                        .font(.caption)
                }
            }
            .frame(width: 80, height: 60)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(obstacleDetectionActive ? Color.green.opacity(0.3) : Color.black.opacity(0.6))
            )
            .accessibilityLabel("Advanced obstacle detection")
            .accessibilityHint("Toggle LiDAR-based obstacle detection and path guidance")
            .onTapGesture {
                showObstacleDetection = true
            }
            
            // Cloud sync button
            Button(action: {
                showCloudSync = true
                provideFeedback()
            }) {
                VStack {
                    Image(systemName: "icloud.and.arrow.up.and.down")
                        .font(.title2)
                        .foregroundColor(.white)
                    Text("Sync")
                        .font(.caption)
                }
            }
            .frame(width: 80, height: 60)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.black.opacity(0.6))
            )
            .accessibilityLabel("Cloud sync")
            .accessibilityHint("Manage cloud synchronization and backup")
        }
        .padding(.horizontal)
    }
    
    // MARK: - Phase 2 Overlay Panels
    
    private var spatialMappingPanel: some View {
        VStack(spacing: 20) {
            Text("Spatial Mapping")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)
            
            // Room layout description
            if let layout = spatialMapping.roomLayout {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Room: \(String(format: "%.1f", layout.bounds.width))m × \(String(format: "%.1f", layout.bounds.length))m")
                        .foregroundColor(.white)
                    
                    Text("Walls: \(layout.walls.count)")
                        .foregroundColor(.white)
                    
                    if !layout.openings.isEmpty {
                        Text("Openings: \(layout.openings.count)")
                            .foregroundColor(.white)
                    }
                }
            } else {
                Text("Analyzing room layout...")
                    .foregroundColor(.gray)
            }
            
            // Spatial anchors
            VStack(alignment: .leading, spacing: 10) {
                Text("Saved Anchors: \(spatialMapping.spatialAnchors.count)")
                    .foregroundColor(.white)
                
                if !spatialMapping.spatialAnchors.isEmpty {
                    ForEach(spatialMapping.spatialAnchors.prefix(3)) { anchor in
                        Text("• \(anchor.name)")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                }
            }
            
            HStack(spacing: 15) {
                Button("Add Anchor") {
                    // Add spatial anchor at current position
                    let position = simd_float3(0, 0, 0) // Get from current camera position
                    spatialMapping.addSpatialAnchor(
                        name: "Location \(spatialMapping.spatialAnchors.count + 1)",
                        description: "Saved location",
                        at: position
                    )
                    provideFeedback()
                }
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(8)
                
                Button("Speak Layout") {
                    spatialMapping.speakSpatialContext()
                    provideFeedback()
                }
                .padding()
                .background(Color.green)
                .foregroundColor(.white)
                .cornerRadius(8)
            }
            
            Button("Close") {
                showSpatialMapping = false
                provideFeedback()
            }
            .padding()
            .background(Color.gray)
            .foregroundColor(.white)
            .cornerRadius(8)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.black.opacity(0.9))
        )
        .accessibilityElement(children: .combine)
    }
    
    private var obstacleDetectionPanel: some View {
        VStack(spacing: 20) {
            Text("Advanced Navigation")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)
            
            // Obstacle summary
            Text(obstacleDetection.getObstacleSummary())
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
            
            // Path guidance
            if let pathDirection = obstacleDetection.safePathDirection {
                VStack {
                    Image(systemName: pathDirectionIcon(pathDirection))
                        .font(.title)
                        .foregroundColor(pathDirectionColor(pathDirection))
                    
                    Text(pathDirection.description.capitalized)
                        .font(.headline)
                        .foregroundColor(.white)
                }
            }
            
            // Obstacle warnings
            if !obstacleDetection.obstacleWarnings.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Warnings:")
                        .font(.headline)
                        .foregroundColor(.orange)
                    
                    ForEach(obstacleDetection.obstacleWarnings.prefix(3), id: \.obstacle.id) { warning in
                        Text("• \(warning.message)")
                            .font(.caption)
                            .foregroundColor(warningColor(warning.type))
                    }
                }
            }
            
            HStack(spacing: 15) {
                Button("Speak Status") {
                    obstacleDetection.speakObstacleSummary()
                    provideFeedback()
                }
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(8)
                
                Button("Toggle Mode") {
                    obstacleDetectionActive.toggle()
                    provideFeedback()
                }
                .padding()
                .background(obstacleDetectionActive ? Color.red : Color.green)
                .foregroundColor(.white)
                .cornerRadius(8)
            }
            
            Button("Close") {
                showObstacleDetection = false
                provideFeedback()
            }
            .padding()
            .background(Color.gray)
            .foregroundColor(.white)
            .cornerRadius(8)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.black.opacity(0.9))
        )
        .accessibilityElement(children: .combine)
    }
    
    private var cloudSyncPanel: some View {
        VStack(spacing: 20) {
            Text("Cloud Sync")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)
            
            // Account status
            VStack {
                Text(cloudSync.getCloudAccountDescription())
                    .foregroundColor(cloudSync.cloudAccountStatus == .available ? .green : .orange)
                
                Text(cloudSync.getSyncStatusDescription())
                    .foregroundColor(.white)
                    .font(.caption)
            }
            
            // Sync progress
            if cloudSync.syncStatus == .syncing {
                ProgressView(value: cloudSync.syncProgress)
                    .progressViewStyle(LinearProgressViewStyle(tint: .blue))
                    .frame(height: 4)
            }
            
            // Last sync info
            if let lastSync = cloudSync.lastSyncDate {
                Text("Last sync: \(formatSyncDate(lastSync))")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            
            VStack(spacing: 10) {
                Button("Manual Sync") {
                    cloudSync.startManualSync()
                    provideFeedback()
                }
                .padding()
                .background(cloudSync.cloudAccountStatus == .available ? Color.blue : Color.gray)
                .foregroundColor(.white)
                .cornerRadius(8)
                .disabled(cloudSync.cloudAccountStatus != .available)
                
                Text("Syncs: Settings, Familiar faces, Spatial anchors, Saved locations")
                    .font(.caption)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
            }
            
            Button("Close") {
                showCloudSync = false
                provideFeedback()
            }
            .padding()
            .background(Color.gray)
            .foregroundColor(.white)
            .cornerRadius(8)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.black.opacity(0.9))
        )
        .accessibilityElement(children: .combine)
    }
    
    // MARK: - Phase 2 Helper Methods
    
    private func pathDirectionIcon(_ direction: PathDirection) -> String {
        switch direction {
        case .left: return "arrow.turn.up.left"
        case .forward: return "arrow.up"
        case .right: return "arrow.turn.up.right"
        case .stop: return "hand.raised.fill"
        }
    }
    
    private func pathDirectionColor(_ direction: PathDirection) -> Color {
        switch direction {
        case .left, .right: return .yellow
        case .forward: return .green
        case .stop: return .red
        }
    }
    
    private func warningColor(_ warningType: WarningType) -> Color {
        switch warningType {
        case .info: return .blue
        case .warning: return .orange
        case .critical: return .red
        }
    }
    
    private func formatSyncDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .named
        return formatter.localizedString(for: date, relativeTo: Date())
    }
    
    private func provideFeedback() {
        // Implement feedback mechanism
    }
}

// MARK: - Supporting Types

enum KaiSightMode: String, CaseIterable {
    case standard = "Standard"
    case narration = "Live Narration"
    case recognition = "Face Recognition"
}

// MARK: - Custom Views

struct KaiSightActionButton: View {
    let title: String
    let icon: String
    let color: Color
    var isSelected: Bool = false
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(isSelected ? .white : color)
                
                Text(title)
                    .font(.caption)
                    .foregroundColor(isSelected ? .white : color)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 60)
            .background(isSelected ? color : color.opacity(0.1))
            .cornerRadius(12)
        }
        .accessibilityLabel(title)
        .accessibilityHint("Double tap to \(title.lowercased())")
    }
}

// MARK: - Extensions

extension View {
    func pulsating() -> some View {
        self.opacity(0.8)
            .scaleEffect(1.0)
            .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: UUID())
    }
} 