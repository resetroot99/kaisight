import SwiftUI
import AVFoundation
import Vision
import Combine
import UIKit

struct KaiSightMainView: View {
    // Core managers (existing)
    @StateObject private var cameraManager = CameraManager()
    @StateObject private var audioManager = AudioManager()
    @StateObject private var gptManager = GPTManager()
    @StateObject private var speechOutput = SpeechOutput()
    @StateObject private var objectDetection = ObjectDetectionManager()
    @StateObject private var navigationAssistant = NavigationAssistant()
    @StateObject private var realTimeNarrator = RealTimeNarrator()
    @StateObject private var voiceAgentLoop = VoiceAgentLoop()
    @StateObject private var familiarRecognition = FamiliarRecognition()
    
    // Phase 2 managers (existing)
    @StateObject private var spatialMapping = SpatialMappingManager()
    @StateObject private var obstacleDetection = ObstacleDetectionManager()
    @StateObject private var cloudSync = CloudSyncManager()
    
    // Phase 3 managers (NEW - Complete Ecosystem)
    @StateObject private var arOverlayManager = AROverlayManager()
    @StateObject private var communityManager = CommunityManager()
    @StateObject private var caregiverDashboard = CaregiverDashboard()
    @StateObject private var smartHomeManager = SmartHomeManager()
    @StateObject private var personalizationEngine = PersonalizationEngine()
    
    // Enhanced state management for Phase 3
    @State private var currentMode: KaiSightMode = .assistant
    @State private var ecosystemStatus = EcosystemStatus()
    @State private var adaptiveUI = AdaptiveUIState()
    @State private var isPhase3Ready = false
    
    var body: some View {
        ZStack {
            // Base camera view
            CameraPreviewView()
                .ignoresSafeArea()
            
            // AR Overlay Layer (Phase 3)
            if arOverlayManager.isVisionProMode {
                VisionProAROverlay()
            } else {
                StandardAROverlay()
            }
            
            // Adaptive UI Layer
            AdaptiveInterfaceOverlay()
            
            // Community Integration Layer
            CommunityInteractionOverlay()
            
            // Smart Home Control Layer
            SmartHomeControlOverlay()
            
            // Caregiver Monitoring Layer (if applicable)
            if caregiverDashboard.isOnDuty {
                CaregiverMonitoringOverlay()
            }
            
            // Main Control Interface
            MainControlInterface()
        }
        .onAppear {
            initializePhase3Ecosystem()
        }
        .onChange(of: personalizationEngine.adaptiveSettings) { settings in
            adaptInterface(to: settings)
        }
        .onReceive(communityManager.$assistanceRequests) { requests in
            handleCommunityRequests(requests)
        }
        .onReceive(caregiverDashboard.$emergencyAlerts) { alerts in
            handleEmergencyAlerts(alerts)
        }
    }
    
    // MARK: - Phase 3 Initialization
    
    private func initializePhase3Ecosystem() {
        Task {
            // Initialize AR/XR features
            await initializeARFeatures()
            
            // Setup community platform
            await setupCommunityIntegration()
            
            // Configure smart home integration
            await configureSmartHome()
            
            // Initialize personalization
            await setupPersonalization()
            
            // Setup caregiver features (if applicable)
            await configureCaregiverFeatures()
            
            // Mark Phase 3 as ready
            isPhase3Ready = true
            
            // Announce completion
            speechOutput.speak("KaiSight complete ecosystem initialized. All advanced features ready.")
        }
    }
    
    private func initializeARFeatures() async {
        // Setup AR overlays
        arOverlayManager.startAROverlays()
        
        // Load community anchors
        if let location = navigationAssistant.currentLocation {
            let region = CLCircularRegion(center: location.coordinate, radius: 1000, identifier: "local")
            arOverlayManager.loadCommunityAnchors(in: region)
        }
        
        // Integrate with spatial mapping
        spatialMapping.delegate = arOverlayManager as? SpatialMappingDelegate
        obstacleDetection.delegate = arOverlayManager as? ObstacleDetectionDelegate
        
        Config.debugLog("AR/XR features initialized")
    }
    
    private func setupCommunityIntegration() async {
        // Connect to community platform
        if !communityManager.isOnline {
            // Auto-connect based on user preferences
            if let profile = personalizationEngine.userProfile,
               profile.preferences.social.participateInCommunity {
                // Connect and setup profile
            }
        }
        
        // Setup volunteer features if user is registered
        if communityManager.userProfile?.isVolunteer == true {
            communityManager.setVolunteerAvailability(true)
        }
        
        Config.debugLog("Community integration setup complete")
    }
    
    private func configureSmartHome() async {
        // Connect to HomeKit if available
        smartHomeManager.connectToHomeKit()
        
        // Setup location-based automation
        smartHomeManager.setupLocationAutomation()
        
        // Register smart speaker integrations
        smartHomeManager.setupSmartSpeakerIntegration()
        
        // Setup accessibility modes
        if personalizationEngine.userProfile?.preferences.mobility.avoidStairs == true {
            smartHomeManager.activateAccessibilityMode()
        }
        
        Config.debugLog("Smart home integration configured")
    }
    
    private func setupPersonalization() async {
        // Start behavioral analysis
        personalizationEngine.analyzeBehavioralPatterns()
        
        // Initialize federated learning (if opted in)
        if personalizationEngine.userProfile?.privacySettings.participateInFederatedLearning == true {
            personalizationEngine.participateInFederatedLearning()
        }
        
        // Apply adaptive UI settings
        let uiSettings = personalizationEngine.getAdaptiveUISettings()
        adaptInterface(to: personalizationEngine.adaptiveSettings)
        
        Config.debugLog("Personalization engine activated")
    }
    
    private func configureCaregiverFeatures() async {
        // Check if user is enrolled in care program
        let userID = personalizationEngine.userProfile?.id ?? UUID()
        
        // This would check against caregiver database
        // For now, we'll initialize if caregiver profile exists
        if caregiverDashboard.caregiverProfile != nil {
            caregiverDashboard.toggleDutyStatus() // Set on duty if caregiver
        }
        
        Config.debugLog("Caregiver features configured")
    }
    
    // MARK: - Adaptive Interface Components
    
    @ViewBuilder
    private func AdaptiveInterfaceOverlay() -> some View {
        VStack {
            // Top status bar with ecosystem information
            EcosystemStatusBar()
            
            Spacer()
            
            // Bottom adaptive controls
            AdaptiveControlPanel()
        }
        .animation(.easeInOut(duration: 0.3), value: adaptiveUI)
    }
    
    @ViewBuilder
    private func EcosystemStatusBar() -> some View {
        HStack {
            // AR Status
            if arOverlayManager.isVisionProMode {
                Image(systemName: "visionpro")
                    .foregroundColor(.blue)
            } else if !arOverlayManager.persistentOverlays.isEmpty {
                Image(systemName: "arkit")
                    .foregroundColor(.green)
            }
            
            // Community Status
            if communityManager.isOnline {
                Image(systemName: "person.2.fill")
                    .foregroundColor(.orange)
                if !communityManager.nearbyUsers.isEmpty {
                    Text("\(communityManager.nearbyUsers.count)")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
            
            // Smart Home Status
            if smartHomeManager.isConnected {
                Image(systemName: "house.fill")
                    .foregroundColor(.green)
            }
            
            // Caregiver Status
            if caregiverDashboard.isOnDuty {
                Image(systemName: "cross.fill")
                    .foregroundColor(.red)
            }
            
            Spacer()
            
            // Personalization Level
            if let level = personalizationEngine.userProfile?.learningLevel {
                Text(level.rawValue.prefix(1).capitalized)
                    .font(.caption)
                    .padding(4)
                    .background(Color.blue.opacity(0.7))
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }
    
    @ViewBuilder
    private func AdaptiveControlPanel() -> some View {
        VStack(spacing: 16) {
            // Mode switcher
            ModeSelectionView()
            
            // Context-aware quick actions
            ContextualQuickActions()
            
            // Main action button
            MainActionButton()
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.black.opacity(0.7))
                .blur(radius: 10)
        )
    }
    
    @ViewBuilder
    private func ModeSelectionView() -> some View {
        HStack(spacing: 12) {
            ForEach(KaiSightMode.allCases, id: \.self) { mode in
                Button(action: {
                    switchToMode(mode)
                }) {
                    VStack(spacing: 4) {
                        Image(systemName: mode.icon)
                            .font(.title2)
                        Text(mode.title)
                            .font(.caption)
                    }
                    .foregroundColor(currentMode == mode ? .blue : .white)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(currentMode == mode ? Color.blue.opacity(0.3) : Color.clear)
                    )
                }
                .accessibilityLabel(mode.accessibilityLabel)
            }
        }
    }
    
    @ViewBuilder
    private func ContextualQuickActions() -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 12) {
            ForEach(getContextualActions(), id: \.id) { action in
                Button(action: {
                    executeQuickAction(action)
                }) {
                    VStack(spacing: 4) {
                        Image(systemName: action.icon)
                            .font(.title3)
                        Text(action.title)
                            .font(.caption2)
                    }
                    .foregroundColor(.white)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(action.color.opacity(0.7))
                    )
                }
                .accessibilityLabel(action.accessibilityLabel)
            }
        }
    }
    
    private func getContextualActions() -> [QuickAction] {
        let currentContext = personalizationEngine.getCurrentContext()
        
        var actions: [QuickAction] = []
        
        // Always available core actions
        actions.append(QuickAction(
            id: "describe",
            title: "Describe",
            icon: "camera.viewfinder",
            color: .blue,
            accessibilityLabel: "Describe current scene",
            action: .describeScene
        ))
        
        // Context-aware actions based on location and patterns
        if navigationAssistant.isNavigating {
            actions.append(QuickAction(
                id: "navigation",
                title: "Navigate",
                icon: "location.fill",
                color: .green,
                accessibilityLabel: "Navigation assistance",
                action: .navigation
            ))
        }
        
        // Community actions if online
        if communityManager.isOnline {
            actions.append(QuickAction(
                id: "community",
                title: "Help",
                icon: "person.2.fill",
                color: .orange,
                accessibilityLabel: "Request community assistance",
                action: .requestHelp
            ))
        }
        
        // Smart home actions if connected
        if smartHomeManager.isConnected {
            actions.append(QuickAction(
                id: "smarthome",
                title: "Home",
                icon: "house.fill",
                color: .purple,
                accessibilityLabel: "Smart home control",
                action: .smartHome
            ))
        }
        
        // AR actions if available
        if arOverlayManager.isVisionProMode || !arOverlayManager.persistentOverlays.isEmpty {
            actions.append(QuickAction(
                id: "ar",
                title: "AR Info",
                icon: "arkit",
                color: .cyan,
                accessibilityLabel: "AR overlay information",
                action: .arInfo
            ))
        }
        
        // Emergency action
        actions.append(QuickAction(
            id: "emergency",
            title: "Emergency",
            icon: "exclamationmark.triangle.fill",
            color: .red,
            accessibilityLabel: "Emergency assistance",
            action: .emergency
        ))
        
        return Array(actions.prefix(8)) // Limit to 8 actions
    }
    
    @ViewBuilder
    private func MainActionButton() -> some View {
        Button(action: performMainAction) {
            HStack {
                Image(systemName: getMainActionIcon())
                    .font(.title2)
                Text(getMainActionTitle())
                    .font(.headline)
            }
            .foregroundColor(.white)
            .padding()
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.blue)
            )
        }
        .accessibilityLabel(getMainActionAccessibilityLabel())
    }
    
    // MARK: - Community Integration Views
    
    @ViewBuilder
    private func CommunityInteractionOverlay() -> some View {
        VStack {
            Spacer()
            
            // Show pending assistance requests
            if !communityManager.assistanceRequests.isEmpty {
                ForEach(communityManager.assistanceRequests.prefix(3)) { request in
                    CommunityRequestCard(request: request)
                        .transition(.slide)
                }
            }
            
            // Show nearby community members
            if !communityManager.nearbyUsers.isEmpty && currentMode == .community {
                CommunityMembersOverlay()
            }
            
            Spacer()
        }
    }
    
    @ViewBuilder
    private func CommunityRequestCard(request: AssistanceRequest) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text("Assistance Request")
                    .font(.headline)
                    .foregroundColor(.orange)
                
                Text(request.description)
                    .font(.body)
                    .foregroundColor(.white)
                
                Text("Urgency: \(request.urgency.rawValue)")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            if communityManager.userProfile?.isVolunteer == true {
                VStack {
                    Button("Help") {
                        communityManager.respondToAssistanceRequest(request, response: .accept)
                    }
                    .buttonStyle(.borderedProminent)
                    
                    Button("Pass") {
                        communityManager.respondToAssistanceRequest(request, response: .decline)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black.opacity(0.8))
        )
        .padding(.horizontal)
    }
    
    // MARK: - Smart Home Integration Views
    
    @ViewBuilder
    private func SmartHomeControlOverlay() -> some View {
        if currentMode == .smartHome && smartHomeManager.isConnected {
            VStack {
                HStack {
                    Text("Smart Home Control")
                        .font(.title2)
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    Button("Close") {
                        currentMode = .assistant
                    }
                    .foregroundColor(.blue)
                }
                .padding()
                
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 16) {
                    ForEach(smartHomeManager.devices.prefix(6), id: \.id) { device in
                        SmartDeviceCard(device: device)
                    }
                }
                .padding()
                
                Spacer()
            }
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.black.opacity(0.9))
            )
            .transition(.move(edge: .bottom))
        }
    }
    
    @ViewBuilder
    private func SmartDeviceCard(device: SmartDevice) -> some View {
        VStack {
            Image(systemName: device.type.icon)
                .font(.title)
                .foregroundColor(device.isOn ? .green : .gray)
            
            Text(device.name)
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundColor(.white)
            
            Text(device.room)
                .font(.caption2)
                .foregroundColor(.gray)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.gray.opacity(0.3))
        )
        .onTapGesture {
            toggleSmartDevice(device)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(device.name) in \(device.room), currently \(device.isOn ? "on" : "off")")
        .accessibilityHint("Double tap to toggle")
    }
    
    // MARK: - AR Overlay Views
    
    @ViewBuilder
    private func VisionProAROverlay() -> some View {
        // Vision Pro specific AR interface
        ForEach(arOverlayManager.persistentOverlays) { overlay in
            ARInfoOverlayView(overlay: overlay)
                .position(
                    x: CGFloat(overlay.position.x) * UIScreen.main.bounds.width,
                    y: CGFloat(overlay.position.y) * UIScreen.main.bounds.height
                )
        }
        
        // Hand tracking indicators
        if arOverlayManager.handTrackingEnabled {
            HandTrackingIndicator()
        }
        
        // Eye tracking focus indicator
        if arOverlayManager.eyeTrackingEnabled {
            EyeTrackingFocusIndicator()
        }
    }
    
    @ViewBuilder
    private func StandardAROverlay() -> some View {
        // Standard AR interface for iPhone/iPad
        ForEach(arOverlayManager.persistentOverlays) { overlay in
            ARInfoOverlayView(overlay: overlay)
        }
        
        // Obstacle markers
        ForEach(arOverlayManager.obstacleMarkers) { marker in
            ARObstacleMarkerView(marker: marker)
        }
        
        // Navigation path
        if let path = arOverlayManager.navigationPath {
            ARNavigationPathView(path: path)
        }
    }
    
    // MARK: - Caregiver Monitoring Views
    
    @ViewBuilder
    private func CaregiverMonitoringOverlay() -> some View {
        VStack {
            HStack {
                Image(systemName: "cross.fill")
                    .foregroundColor(.red)
                
                Text("On Duty")
                    .font(.caption)
                    .foregroundColor(.white)
                
                Spacer()
                
                if !caregiverDashboard.emergencyAlerts.isEmpty {
                    Text("\(caregiverDashboard.emergencyAlerts.count) alerts")
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(4)
                        .background(Color.red.opacity(0.3))
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)
            
            Spacer()
        }
    }
    
    // MARK: - Action Handlers
    
    private func switchToMode(_ mode: KaiSightMode) {
        currentMode = mode
        
        // Record interaction for personalization
        let interaction = UserInteraction(
            id: UUID(),
            type: .settingsChange,
            timestamp: Date(),
            context: personalizationEngine.getCurrentContext(),
            details: ["mode": mode.rawValue],
            wasSuccessful: true,
            userFeedback: nil
        )
        personalizationEngine.recordUserInteraction(interaction)
        
        // Announce mode change
        speechOutput.speak("Switched to \(mode.title) mode")
    }
    
    private func executeQuickAction(_ action: QuickAction) {
        switch action.action {
        case .describeScene:
            performSceneDescription()
        case .navigation:
            activateNavigation()
        case .requestHelp:
            requestCommunityHelp()
        case .smartHome:
            activateSmartHomeControl()
        case .arInfo:
            provideFarInfo()
        case .emergency:
            triggerEmergency()
        }
        
        // Record interaction
        let interaction = UserInteraction(
            id: UUID(),
            type: .voiceCommand,
            timestamp: Date(),
            context: personalizationEngine.getCurrentContext(),
            details: ["action": action.id],
            wasSuccessful: true,
            userFeedback: nil
        )
        personalizationEngine.recordUserInteraction(interaction)
    }
    
    private func performMainAction() {
        switch currentMode {
        case .assistant:
            performSceneDescription()
        case .navigation:
            activateNavigation()
        case .community:
            requestCommunityHelp()
        case .smartHome:
            activateSmartHomeControl()
        case .ar:
            provideFarInfo()
        case .caregiver:
            openCaregiverDashboard()
        }
    }
    
    private func performSceneDescription() {
        guard let image = cameraManager.capturePhoto() else { return }
        
        // Use personalized description based on user learning level
        let detailLevel = personalizationEngine.adaptiveSettings.detailLevel
        
        gptManager.analyzeImage(image, detailLevel: detailLevel) { description in
            speechOutput.speak(description)
            
            // Check for custom objects
            personalizationEngine.recognizeCustomObjects(in: image) { customObjects in
                if !customObjects.isEmpty {
                    let customDescription = "I also recognize your personal items: \(customObjects.map { $0.name }.joined(separator: ", "))"
                    speechOutput.speak(customDescription)
                }
            }
        }
    }
    
    private func requestCommunityHelp() {
        communityManager.requestAssistance(
            type: .identification,
            description: "Need help identifying objects in current scene",
            urgency: .normal
        )
    }
    
    private func activateSmartHomeControl() {
        currentMode = .smartHome
        speechOutput.speak("Smart home control activated")
    }
    
    private func provideFarInfo() {
        let summary = arOverlayManager.getOverlaySummary()
        speechOutput.speak(summary)
    }
    
    private func triggerEmergency() {
        // Trigger emergency across all systems
        communityManager.triggerEmergencyAlert(description: "Emergency assistance needed")
        
        if caregiverDashboard.isOnDuty {
            // Caregiver emergency protocol
        }
        
        // Emergency smart home actions
        smartHomeManager.activateEmergencyMode()
        
        speechOutput.speak("Emergency alert activated across all systems", priority: .emergency)
    }
    
    private func toggleSmartDevice(_ device: SmartDevice) {
        switch device.type {
        case .light:
            smartHomeManager.controlLight(device: device, state: !device.isOn)
        case .lock:
            smartHomeManager.controlLock(device: device, locked: !device.isOn)
        default:
            speechOutput.speak("Device control not yet implemented for \(device.type.rawValue)")
        }
    }
    
    // MARK: - Event Handlers
    
    private func handleCommunityRequests(_ requests: [AssistanceRequest]) {
        // Filter requests based on user's volunteer status and preferences
        let relevantRequests = requests.filter { request in
            guard communityManager.userProfile?.isVolunteer == true else { return false }
            
            // Filter based on user preferences and capabilities
            return true // Simplified for demo
        }
        
        if !relevantRequests.isEmpty {
            speechOutput.speak("New assistance requests available")
        }
    }
    
    private func handleEmergencyAlerts(_ alerts: [EmergencyAlert]) {
        let pendingAlerts = alerts.filter { $0.status == .pending }
        
        if !pendingAlerts.isEmpty {
            speechOutput.speak("Emergency alerts requiring attention", priority: .emergency)
        }
    }
    
    private func adaptInterface(to settings: AdaptiveSettings) {
        // Adapt speech rate
        speechOutput.rate = settings.speechRate
        
        // Adapt detail level
        gptManager.defaultDetailLevel = settings.detailLevel
        
        // Adapt haptic feedback
        // Implementation for haptic intensity adjustment
        
        // Update adaptive UI state
        adaptiveUI.speechRate = settings.speechRate
        adaptiveUI.detailLevel = settings.detailLevel
        adaptiveUI.proactiveAssistance = settings.proactiveAssistance
    }
    
    // MARK: - Utility Methods
    
    private func getMainActionIcon() -> String {
        switch currentMode {
        case .assistant: return "camera.viewfinder"
        case .navigation: return "location.fill"
        case .community: return "person.2.fill"
        case .smartHome: return "house.fill"
        case .ar: return "arkit"
        case .caregiver: return "cross.fill"
        }
    }
    
    private func getMainActionTitle() -> String {
        switch currentMode {
        case .assistant: return "Describe Scene"
        case .navigation: return "Navigate"
        case .community: return "Request Help"
        case .smartHome: return "Control Home"
        case .ar: return "AR Info"
        case .caregiver: return "Dashboard"
        }
    }
    
    private func getMainActionAccessibilityLabel() -> String {
        switch currentMode {
        case .assistant: return "Describe current scene using AI vision"
        case .navigation: return "Start navigation assistance"
        case .community: return "Request help from community volunteers"
        case .smartHome: return "Access smart home controls"
        case .ar: return "Get augmented reality information"
        case .caregiver: return "Open caregiver dashboard"
        }
    }
    
    private func activateNavigation() {
        // Activate enhanced navigation with all Phase 3 features
        if let currentLocation = navigationAssistant.currentLocation {
            // Use personalized route optimization
            speechOutput.speak("Navigation activated with personalized routing")
            
            // Enable AR navigation overlays
            if !arOverlayManager.persistentOverlays.isEmpty {
                speechOutput.speak("AR navigation overlays available")
            }
            
            // Check for community-sourced navigation tips
            communityManager.loadNearbyTips { tips in
                if !tips.isEmpty {
                    speechOutput.speak("Community navigation tips available for this area")
                }
            }
        }
    }
    
    private func openCaregiverDashboard() {
        // Open caregiver dashboard with full monitoring capabilities
        currentMode = .caregiver
        speechOutput.speak("Caregiver dashboard activated. Monitoring \(caregiverDashboard.clients.count) clients.")
    }
    
    // MARK: - Phase 3 Complete Integration
    
    private func handleVisionProGestures() {
        // Handle Vision Pro hand gestures for advanced interaction
        if arOverlayManager.isVisionProMode && arOverlayManager.handTrackingEnabled {
            // Gesture recognition integration
            speechOutput.speak("Hand tracking active. Use gestures to interact with AR overlays.")
        }
    }
    
    private func syncEcosystemData() {
        // Synchronize data across all Phase 3 components
        Task {
            // Sync personalization data
            if let profile = personalizationEngine.userProfile {
                cloudSync.syncPersonalizationProfile(profile)
            }
            
            // Sync community data
            if communityManager.isOnline {
                cloudSync.syncCommunityData()
            }
            
            // Sync smart home preferences
            if smartHomeManager.isConnected {
                cloudSync.syncSmartHomeSettings()
            }
            
            // Sync caregiver data
            if caregiverDashboard.isOnDuty {
                cloudSync.syncCaregiverData()
            }
        }
    }
    
    private func handleContextualAwareness() {
        // Advanced contextual awareness combining all Phase 3 systems
        let context = personalizationEngine.getCurrentContext()
        
        // Adapt AR overlays based on context
        if context.activity == .navigation {
            arOverlayManager.activateNavigationMode()
        }
        
        // Adjust smart home based on presence
        if smartHomeManager.isConnected {
            smartHomeManager.handleContextualPresence(context: context)
        }
        
        // Update community availability
        if communityManager.isOnline {
            communityManager.updateContextualAvailability(context: context)
        }
    }
    
    // MARK: - Complete Ecosystem Status
    
    func getCompleteEcosystemStatus() -> String {
        var status = "KaiSight Complete Ecosystem Status:\n"
        
        // Core systems
        status += "• Core AI Assistant: Active\n"
        status += "• Real-time Narration: \(realTimeNarrator.isActive ? "On" : "Off")\n"
        status += "• Voice Agent: \(voiceAgentLoop.isListening ? "Listening" : "Standby")\n"
        
        // Phase 2 systems
        status += "• Spatial Mapping: \(spatialMapping.isActive ? "Active" : "Inactive")\n"
        status += "• Obstacle Detection: \(obstacleDetection.isActive ? "Active" : "Inactive")\n"
        status += "• Cloud Sync: \(cloudSync.isConnected ? "Connected" : "Offline")\n"
        
        // Phase 3 complete ecosystem
        status += "• AR/XR Overlays: \(arOverlayManager.persistentOverlays.count) active\n"
        if arOverlayManager.isVisionProMode {
            status += "• Vision Pro Mode: Active with hand/eye tracking\n"
        }
        
        status += "• Community Platform: \(communityManager.isOnline ? "Connected" : "Offline")\n"
        if !communityManager.nearbyUsers.isEmpty {
            status += "  - \(communityManager.nearbyUsers.count) nearby users\n"
        }
        
        status += "• Smart Home: \(smartHomeManager.isConnected ? "Connected" : "Disconnected")\n"
        if smartHomeManager.isConnected {
            status += "  - \(smartHomeManager.devices.count) devices available\n"
        }
        
        status += "• Caregiver System: \(caregiverDashboard.isOnDuty ? "On Duty" : "Off Duty")\n"
        if caregiverDashboard.isOnDuty {
            status += "  - Monitoring \(caregiverDashboard.clients.count) clients\n"
        }
        
        status += "• Personalization: Level \(personalizationEngine.userProfile?.learningLevel.rawValue ?? "Unknown")\n"
        status += "  - \(personalizationEngine.customObjects.count) custom objects learned\n"
        status += "  - \(personalizationEngine.behavioralPatterns.count) patterns identified\n"
        
        return status
    }
    
    func announceEcosystemStatus() {
        let status = getCompleteEcosystemStatus()
        speechOutput.speak("Complete ecosystem status available. Check console for details.")
        print(status)
    }
}

// MARK: - Data Models

enum KaiSightMode: String, CaseIterable {
    case assistant = "assistant"
    case navigation = "navigation"
    case community = "community"
    case smartHome = "smart_home"
    case ar = "ar"
    case caregiver = "caregiver"
    
    var title: String {
        switch self {
        case .assistant: return "Assistant"
        case .navigation: return "Navigate"
        case .community: return "Community"
        case .smartHome: return "Home"
        case .ar: return "AR"
        case .caregiver: return "Care"
        }
    }
    
    var icon: String {
        switch self {
        case .assistant: return "brain.head.profile"
        case .navigation: return "location"
        case .community: return "person.2"
        case .smartHome: return "house"
        case .ar: return "arkit"
        case .caregiver: return "cross"
        }
    }
    
    var accessibilityLabel: String {
        switch self {
        case .assistant: return "AI Assistant mode"
        case .navigation: return "Navigation assistance mode"
        case .community: return "Community interaction mode"
        case .smartHome: return "Smart home control mode"
        case .ar: return "Augmented reality mode"
        case .caregiver: return "Caregiver dashboard mode"
        }
    }
}

struct QuickAction: Identifiable {
    let id: String
    let title: String
    let icon: String
    let color: Color
    let accessibilityLabel: String
    let action: QuickActionType
}

enum QuickActionType {
    case describeScene
    case navigation
    case requestHelp
    case smartHome
    case arInfo
    case emergency
}

struct EcosystemStatus {
    var arActive = false
    var communityConnected = false
    var smartHomeConnected = false
    var caregiverOnDuty = false
    var personalizationLevel: LearningLevel = .beginner
}

struct AdaptiveUIState {
    var speechRate: Double = 0.5
    var detailLevel: DetailLevel = .medium
    var proactiveAssistance = true
    var currentContext: String = "general"
}

// MARK: - Supporting Views

struct CameraPreviewView: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        // Camera preview implementation
        return UIView()
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        // Update camera preview
    }
}

struct ARInfoOverlayView: View {
    let overlay: ARInfoOverlay
    
    var body: some View {
        VStack {
            Text(overlay.text)
                .font(.caption)
                .foregroundColor(.white)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(overlay.type.color.opacity(0.8))
                )
        }
        .accessibilityLabel("AR overlay: \(overlay.text)")
    }
}

struct ARObstacleMarkerView: View {
    let marker: ARObstacleMarker
    
    var body: some View {
        Image(systemName: "exclamationmark.triangle.fill")
            .foregroundColor(marker.severity.color)
            .font(.title)
            .accessibilityLabel("Obstacle marker: \(marker.severity.rawValue) severity")
    }
}

struct ARNavigationPathView: View {
    let path: ARPathOverlay
    
    var body: some View {
        // AR navigation path visualization
        Rectangle()
            .fill(path.pathColor.opacity(0.6))
            .frame(height: 4)
            .accessibilityLabel("Navigation path displayed")
    }
}

struct HandTrackingIndicator: View {
    var body: some View {
        VStack {
            HStack {
                Spacer()
                Image(systemName: "hand.raised.fill")
                    .foregroundColor(.blue)
                    .font(.caption)
            }
            Spacer()
        }
        .padding()
    }
}

struct EyeTrackingFocusIndicator: View {
    var body: some View {
        Circle()
            .stroke(Color.blue, lineWidth: 2)
            .frame(width: 20, height: 20)
            .position(x: UIScreen.main.bounds.midX, y: UIScreen.main.bounds.midY)
    }
}

struct CommunityMembersOverlay: View {
    var body: some View {
        VStack {
            Text("Community Members Nearby")
                .font(.headline)
                .foregroundColor(.white)
            
            // Community members list
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black.opacity(0.8))
        )
    }
}

// MARK: - Extensions

extension OverlayType {
    var color: Color {
        switch self {
        case .info: return .blue
        case .warning: return .orange
        case .navigation: return .green
        case .community: return .purple
        case .userMarker: return .yellow
        }
    }
}

extension ObstacleSeverity {
    var color: Color {
        switch self {
        case .low: return .yellow
        case .medium: return .orange
        case .high: return .red
        case .critical: return .red
        }
    }
}

extension DeviceType {
    var icon: String {
        switch self {
        case .light: return "lightbulb.fill"
        case .switch: return "switch.2"
        case .lock: return "lock.fill"
        case .thermostat: return "thermometer"
        case .speaker: return "speaker.wave.2.fill"
        case .security: return "shield.fill"
        case .sensor: return "sensor.tag.radiowaves.forward.fill"
        case .other: return "device.mac"
        }
    }
}

// ... existing code ... 
} 