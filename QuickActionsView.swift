import SwiftUI

struct QuickActionsView: View {
    @ObservedObject var cameraManager: CameraManager
    @ObservedObject var speechOutput: SpeechOutput
    @ObservedObject var objectDetectionManager = ObjectDetectionManager()
    @ObservedObject var navigationAssistant = NavigationAssistant()
    
    let gpt: GPTManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var isProcessing = false
    @State private var currentAction = ""
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    
                    // Processing indicator
                    if isProcessing {
                        VStack {
                            ProgressView()
                                .scaleEffect(1.2)
                            Text(currentAction)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(12)
                    }
                    
                    // Quick Description Actions
                    Section {
                        VStack(spacing: 12) {
                            QuickActionButton(
                                title: "What's in front of me?",
                                icon: "eye.fill",
                                color: .blue,
                                action: { describeScene() }
                            )
                            
                            QuickActionButton(
                                title: "Read any text",
                                icon: "text.viewfinder",
                                color: .green,
                                action: { readText() }
                            )
                            
                            QuickActionButton(
                                title: "Quick object scan",
                                icon: "viewfinder",
                                color: .orange,
                                action: { quickObjectScan() }
                            )
                        }
                    } header: {
                        Text("Scene Description")
                            .font(.headline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    
                    // Navigation Actions
                    Section {
                        VStack(spacing: 12) {
                            QuickActionButton(
                                title: "Where am I?",
                                icon: "location.fill",
                                color: .purple,
                                action: { getCurrentLocation() }
                            )
                            
                            QuickActionButton(
                                title: "Return home",
                                icon: "house.fill",
                                color: .blue,
                                action: { returnHome() }
                            )
                            
                            QuickActionButton(
                                title: "Return to starting point",
                                icon: "arrow.uturn.backward.circle.fill",
                                color: .cyan,
                                action: { returnToStart() }
                            )
                            
                            QuickActionButton(
                                title: "Find nearby places",
                                icon: "map.fill",
                                color: .indigo,
                                action: { findNearbyPlaces() }
                            )
                            
                            if navigationAssistant.isNavigating {
                                QuickActionButton(
                                    title: "Navigation status",
                                    icon: "location.north.fill",
                                    color: .red,
                                    action: { getNavigationStatus() }
                                )
                            }
                        }
                    } header: {
                        Text("Navigation")
                            .font(.headline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    
                    // Family & Friends Actions
                    Section {
                        VStack(spacing: 12) {
                            QuickActionButton(
                                title: "Find nearest contact",
                                icon: "person.crop.circle.fill",
                                color: .mint,
                                action: { findNearestContact() }
                            )
                            
                            QuickActionButton(
                                title: "Share my location",
                                icon: "location.circle.fill",
                                color: .teal,
                                action: { shareLocation() }
                            )
                            
                            QuickActionButton(
                                title: "Location history",
                                icon: "clock.arrow.circlepath",
                                color: .brown,
                                action: { getLocationHistory() }
                            )
                        }
                    } header: {
                        Text("Family & Friends")
                            .font(.headline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    
                    // Safety Actions
                    Section {
                        VStack(spacing: 12) {
                            QuickActionButton(
                                title: "Check for obstacles",
                                icon: "exclamationmark.triangle.fill",
                                color: .red,
                                action: { checkObstacles() }
                            )
                            
                            QuickActionButton(
                                title: "Emergency help",
                                icon: "phone.fill",
                                color: .red,
                                action: { requestEmergencyHelp() }
                            )
                            
                            QuickActionButton(
                                title: "Describe colors",
                                icon: "paintpalette.fill",
                                color: .pink,
                                action: { describeColors() }
                            )
                            
                            QuickActionButton(
                                title: "Count people",
                                icon: "person.2.fill",
                                color: .teal,
                                action: { countPeople() }
                            )
                        }
                    } header: {
                        Text("Safety & Emergency")
                            .font(.headline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    
                    Spacer(minLength: 50)
                }
                .padding()
            }
            .navigationTitle("Quick Actions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .accessibilityLabel("Done, close quick actions")
                }
            }
        }
        .disabled(isProcessing)
    }
    
    // MARK: - Action Methods
    
    private func describeScene() {
        executeAction("Describing scene...") {
            cameraManager.capturePhoto()
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                gpt.ask(prompt: "Please describe what you see in detail", image: cameraManager.capturedImage) { response in
                    speechOutput.speak(response)
                    isProcessing = false
                }
            }
        }
    }
    
    private func readText() {
        executeAction("Reading text...") {
            cameraManager.capturePhoto()
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                gpt.ask(prompt: "Please read any text you can see in this image exactly as written", image: cameraManager.capturedImage) { response in
                    speechOutput.speak(response)
                    isProcessing = false
                }
            }
        }
    }
    
    private func quickObjectScan() {
        executeAction("Scanning objects...") {
            cameraManager.capturePhoto()
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if let image = cameraManager.capturedImage {
                    objectDetectionManager.quickScan(image: image) { description in
                        speechOutput.speak(description)
                        isProcessing = false
                    }
                } else {
                    speechOutput.speak("Unable to capture image for scanning")
                    isProcessing = false
                }
            }
        }
    }
    
    private func getCurrentLocation() {
        executeAction("Getting location...") {
            navigationAssistant.getCurrentLocationDescription { description in
                speechOutput.speak(description)
                isProcessing = false
            }
        }
    }
    
    private func returnHome() {
        executeAction("Getting directions home...") {
            navigationAssistant.returnHome { response in
                speechOutput.speak(response)
                isProcessing = false
            }
        }
    }
    
    private func returnToStart() {
        executeAction("Getting directions to starting point...") {
            navigationAssistant.returnToStartingPoint { response in
                speechOutput.speak(response)
                isProcessing = false
            }
        }
    }
    
    private func findNearbyPlaces() {
        executeAction("Finding nearby places...") {
            navigationAssistant.findNearbyPlaces { places in
                if places.isEmpty {
                    speechOutput.speak("No nearby places found.")
                } else {
                    var description = "Nearby places: "
                    for (index, place) in places.enumerated() {
                        description += "\(place.address), \(Int(place.distance)) meters \(place.direction.lowercased())"
                        if index < places.count - 1 {
                            description += "; "
                        }
                    }
                    speechOutput.speak(description)
                }
                isProcessing = false
            }
        }
    }
    
    private func findNearestContact() {
        executeAction("Finding nearest contact...") {
            navigationAssistant.findNearestEmergencyContact { response in
                speechOutput.speak(response)
                isProcessing = false
            }
        }
    }
    
    private func shareLocation() {
        executeAction("Preparing location to share...") {
            let locationMessage = navigationAssistant.shareLocationWithContacts()
            speechOutput.speak(locationMessage)
            isProcessing = false
        }
    }
    
    private func getLocationHistory() {
        executeAction("Getting location history...") {
            let breadcrumbs = navigationAssistant.getLocationBreadcrumbs()
            speechOutput.speak(breadcrumbs)
            isProcessing = false
        }
    }
    
    private func requestEmergencyHelp() {
        executeAction("Preparing emergency message...") {
            navigationAssistant.requestEmergencyHelp { emergencyMessage in
                speechOutput.speak("Emergency message prepared. " + emergencyMessage, priority: .high)
                isProcessing = false
            }
        }
    }
    
    private func getNavigationStatus() {
        let status = navigationAssistant.getNavigationSummary()
        speechOutput.speak(status)
    }
    
    private func checkObstacles() {
        executeAction("Checking for obstacles...") {
            cameraManager.capturePhoto()
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                gpt.ask(prompt: "Please identify any obstacles, hazards, or things I should be careful of in my path", image: cameraManager.capturedImage) { response in
                    speechOutput.speak(response, priority: .high)
                    isProcessing = false
                }
            }
        }
    }
    
    private func describeColors() {
        executeAction("Describing colors...") {
            cameraManager.capturePhoto()
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                gpt.ask(prompt: "Describe the main colors you can see in this image", image: cameraManager.capturedImage) { response in
                    speechOutput.speak(response)
                    isProcessing = false
                }
            }
        }
    }
    
    private func countPeople() {
        executeAction("Counting people...") {
            cameraManager.capturePhoto()
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                gpt.ask(prompt: "How many people can you see in this image? Describe their approximate positions", image: cameraManager.capturedImage) { response in
                    speechOutput.speak(response)
                    isProcessing = false
                }
            }
        }
    }
    
    private func executeAction(_ actionName: String, completion: @escaping () -> Void) {
        isProcessing = true
        currentAction = actionName
        
        // Haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
        
        completion()
    }
}

struct QuickActionButton: View {
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .font(.title2)
                    .frame(width: 30)
                
                Text(title)
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                Spacer()
            }
            .padding()
            .background(color.opacity(0.1))
            .foregroundColor(color)
            .cornerRadius(12)
        }
        .accessibilityLabel(title)
        .accessibilityHint("Double tap to \(title.lowercased())")
    }
} 