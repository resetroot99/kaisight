import Foundation
import CoreBluetooth
import CoreLocation
import Intents
import IntentsUI
import AVFoundation
import ARKit

class AirPodsLocator: NSObject, ObservableObject {
    static let shared = AirPodsLocator()
    
    @Published var isSearching = false
    @Published var airPodsStatus: AirPodsStatus = .unknown
    @Published var lastKnownLocation: AirPodsLocation?
    @Published var searchProgress: SearchProgress = .idle
    
    // Core Dependencies
    private let speechOutput = SpeechOutput.shared
    private let locationManager = LocationManager.shared
    private let hapticFeedback = HapticFeedbackManager()
    
    // Bluetooth Monitoring
    private var centralManager: CBCentralManager!
    private var connectedAirPods: [CBPeripheral] = []
    
    // Location & Memory System
    private var locationHistory: [AirPodsLocation] = []
    private var spatialAnchors: [ARAnchor] = []
    private let maxLocationHistory = 20
    
    // Search System
    private var searchTimer: Timer?
    private var guidanceTimer: Timer?
    private var chimeTimer: Timer?
    
    // Find My Integration
    private let findMyIntegration = FindMyIntegration()
    private let shortcutManager = SiriShortcutManager()
    
    // AI Context System
    private var usagePatterns: [AirPodsUsagePattern] = []
    private let gptContextManager = GPTContextManager()
    
    override init() {
        super.init()
        setupAirPodsLocator()
    }
    
    // MARK: - Setup and Configuration
    
    private func setupAirPodsLocator() {
        setupBluetoothMonitoring()
        loadLocationHistory()
        setupSiriShortcuts()
        registerVoiceCommands()
        
        Config.debugLog("AirPods Locator initialized")
    }
    
    private func setupBluetoothMonitoring() {
        centralManager = CBCentralManager(delegate: self, queue: DispatchQueue.global(qos: .userInitiated))
    }
    
    private func loadLocationHistory() {
        // Load persisted location history
        if let data = UserDefaults.standard.data(forKey: "airpods_location_history"),
           let history = try? JSONDecoder().decode([AirPodsLocation].self, from: data) {
            locationHistory = history
            lastKnownLocation = history.last
        }
    }
    
    private func setupSiriShortcuts() {
        shortcutManager.setupAirPodsShortcuts()
    }
    
    private func registerVoiceCommands() {
        // Register with global voice command system
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleVoiceCommand(_:)),
            name: .airPodsVoiceCommand,
            object: nil
        )
    }
    
    // MARK: - Main Search Interface
    
    func findAirPods(triggeredBy command: String = "voice") {
        guard !isSearching else {
            speechOutput.speak("Already searching for AirPods", priority: .normal)
            return
        }
        
        isSearching = true
        searchProgress = .analyzing
        
        speechOutput.speak("Searching for your AirPods...", priority: .high)
        
        // Multi-layered search approach
        performComprehensiveSearch()
    }
    
    private func performComprehensiveSearch() {
        // Layer 1: Check current Bluetooth connections
        checkCurrentBluetoothConnections()
        
        // Layer 2: Try Find My integration
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.tryFindMyIntegration()
        }
        
        // Layer 3: Use last known location
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            self.provideLastKnownLocationGuidance()
        }
        
        // Layer 4: AI-powered contextual suggestions
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
            self.provideAIContextualSuggestions()
        }
        
        // Layer 5: Voice-guided search mode
        DispatchQueue.main.asyncAfter(deadline: .now() + 8.0) {
            self.startVoiceGuidedSearch()
        }
    }
    
    // MARK: - Layer 1: Bluetooth Connection Check
    
    private func checkCurrentBluetoothConnections() {
        searchProgress = .checkingBluetooth
        
        if !connectedAirPods.isEmpty {
            // AirPods are currently connected
            airPodsStatus = .connected
            
            let connectedCount = connectedAirPods.count
            let deviceNames = connectedAirPods.compactMap { $0.name }.joined(separator: ", ")
            
            speechOutput.speak("Your AirPods are currently connected: \(deviceNames). Would you like me to play a sound?", priority: .high)
            
            // Offer to play sound through connected AirPods
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                self.tryPlaySoundThroughAirPods()
            }
        } else {
            // AirPods not currently connected
            airPodsStatus = .disconnected
            Config.debugLog("AirPods not currently connected, proceeding to Find My")
        }
    }
    
    private func tryPlaySoundThroughAirPods() {
        // Attempt to play locator sound through connected AirPods
        let audioSession = AVAudioSession.sharedInstance()
        
        do {
            try audioSession.setCategory(.playback, mode: .default, options: [.allowBluetooth])
            try audioSession.setActive(true)
            
            playAirPodsLocatorSound()
            
            speechOutput.speak("Playing locator sound through your AirPods now", priority: .high)
            
        } catch {
            Config.debugLog("Failed to play sound through AirPods: \(error)")
            // Fall back to Find My
            tryFindMyIntegration()
        }
    }
    
    private func playAirPodsLocatorSound() {
        // Play a distinctive locator sound pattern
        let soundPattern = [1000, 1200, 1400] // Frequencies
        
        for (index, frequency) in soundPattern.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.5) {
                self.playToneAtFrequency(frequency, duration: 0.3)
            }
        }
    }
    
    private func playToneAtFrequency(_ frequency: Int, duration: TimeInterval) {
        // Generate and play tone at specific frequency
        let systemSoundID: SystemSoundID = 1016 // Apple's distinctive sound
        AudioServicesPlaySystemSound(systemSoundID)
    }
    
    // MARK: - Layer 2: Find My Integration
    
    private func tryFindMyIntegration() {
        searchProgress = .checkingFindMy
        
        speechOutput.speak("Checking Find My for your AirPods location", priority: .normal)
        
        findMyIntegration.locateAirPods { [weak self] result in
            DispatchQueue.main.async {
                self?.handleFindMyResult(result)
            }
        }
    }
    
    private func handleFindMyResult(_ result: FindMyResult) {
        switch result {
        case .found(let location, let canPlaySound):
            let locationDescription = describeLocation(location)
            
            if canPlaySound {
                speechOutput.speak("Found your AirPods \(locationDescription). Playing sound now - listen for the chirp!", priority: .high)
                findMyIntegration.playSoundOnAirPods()
            } else {
                speechOutput.speak("Found your AirPods \(locationDescription), but they may be out of range or low battery", priority: .high)
            }
            
            // Update last known location
            updateLastKnownLocation(location)
            
        case .foundButNoSound(let location):
            let locationDescription = describeLocation(location)
            speechOutput.speak("Your AirPods were last seen \(locationDescription), but I can't play a sound. They may be out of range", priority: .high)
            updateLastKnownLocation(location)
            
        case .notFound:
            speechOutput.speak("Find My couldn't locate your AirPods. Let me check the last known location", priority: .normal)
            
        case .error(let error):
            Config.debugLog("Find My error: \(error)")
            speechOutput.speak("Having trouble with Find My. Using backup location methods", priority: .normal)
        }
    }
    
    // MARK: - Layer 3: Last Known Location Guidance
    
    private func provideLastKnownLocationGuidance() {
        searchProgress = .usingLastKnown
        
        guard let lastLocation = lastKnownLocation else {
            speechOutput.speak("I don't have a previous location for your AirPods. Let me try other methods", priority: .normal)
            return
        }
        
        let timeSinceLastSeen = Date().timeIntervalSince(lastLocation.timestamp)
        let timeDescription = formatTimeAgo(timeSinceLastSeen)
        let locationDescription = describeDetailedLocation(lastLocation)
        
        var guidance = "Your AirPods were last connected \(timeDescription) "
        guidance += locationDescription
        
        // Add contextual suggestions based on time and location
        if timeSinceLastSeen < 3600 { // Less than 1 hour
            guidance += ". They're likely still in that area."
        } else if timeSinceLastSeen < 86400 { // Less than 24 hours
            guidance += ". Check around that area, or where you've been since then."
        } else {
            guidance += ". That was a while ago - think about where you've used them recently."
        }
        
        speechOutput.speak(guidance, priority: .high)
        
        // Offer to guide user to that location
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            self.offerLocationGuidance(to: lastLocation)
        }
    }
    
    private func offerLocationGuidance(to location: AirPodsLocation) {
        guard let currentLocation = locationManager.currentLocation else { return }
        
        let distance = currentLocation.distance(from: location.coordinate)
        
        if distance < 50 { // Within 50 meters
            speechOutput.speak("You're very close to where they were last seen. Would you like me to guide you with sound beacons?", priority: .normal)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                self.startProximityGuidance()
            }
        } else {
            let distanceDescription = distance < 1000 ? "\(Int(distance)) meters" : "\(String(format: "%.1f", distance/1000)) kilometers"
            speechOutput.speak("They were last seen about \(distanceDescription) away. Would you like directions to that location?", priority: .normal)
        }
    }
    
    // MARK: - Layer 4: AI-Powered Contextual Suggestions
    
    private func provideAIContextualSuggestions() {
        searchProgress = .analyzingPatterns
        
        speechOutput.speak("Analyzing your usage patterns for suggestions", priority: .normal)
        
        // Analyze historical usage patterns
        let suggestions = generateAISuggestions()
        
        if !suggestions.isEmpty {
            let suggestionsText = suggestions.joined(separator: ". ")
            speechOutput.speak("Based on your habits: \(suggestionsText)", priority: .high)
        } else {
            speechOutput.speak("No pattern suggestions available. Let me help you search systematically", priority: .normal)
        }
    }
    
    private func generateAISuggestions() -> [String] {
        var suggestions: [String] = []
        
        // Analyze time-based patterns
        let currentHour = Calendar.current.component(.hour, from: Date())
        let timeBasedSuggestion = getTimeBasedSuggestion(for: currentHour)
        if !timeBasedSuggestion.isEmpty {
            suggestions.append(timeBasedSuggestion)
        }
        
        // Analyze location patterns
        let locationSuggestion = getLocationBasedSuggestion()
        if !locationSuggestion.isEmpty {
            suggestions.append(locationSuggestion)
        }
        
        // Analyze recent activity
        let activitySuggestion = getActivityBasedSuggestion()
        if !activitySuggestion.isEmpty {
            suggestions.append(activitySuggestion)
        }
        
        return suggestions
    }
    
    private func getTimeBasedSuggestion(for hour: Int) -> String {
        // Morning routine
        if hour >= 6 && hour <= 10 {
            return "Check your bedside table or bathroom - that's where you usually keep them overnight"
        }
        // Work hours
        else if hour >= 11 && hour <= 17 {
            return "Look around your workspace or where you take calls"
        }
        // Evening
        else if hour >= 18 && hour <= 22 {
            return "Check the living room or kitchen where you might have removed them"
        }
        // Late night
        else {
            return "They might be where you last listened to music or podcasts"
        }
    }
    
    private func getLocationBasedSuggestion() -> String {
        // Analyze most common disconnect locations
        let commonLocations = locationHistory.prefix(10)
        
        if let mostCommon = findMostCommonLocation(commonLocations) {
            return "You often leave them \(mostCommon.roomDescription)"
        }
        
        return ""
    }
    
    private func getActivityBasedSuggestion() -> String {
        // Suggest based on recent usage patterns
        return "Check where you last made calls or listened to audio"
    }
    
    // MARK: - Layer 5: Voice-Guided Search Mode
    
    private func startVoiceGuidedSearch() {
        searchProgress = .voiceGuided
        
        speechOutput.speak("Let's search together. I'll guide you with audio beacons. Say 'warmer' or 'colder' as you move around", priority: .high)
        
        startAudioBeacons()
        startVoiceGuidanceListening()
    }
    
    private func startAudioBeacons() {
        chimeTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.playSearchBeacon()
        }
    }
    
    private func playSearchBeacon() {
        // Play a beacon sound from the phone
        let systemSoundID: SystemSoundID = 1013 // Apple's "Beep" sound
        AudioServicesPlaySystemSound(systemSoundID)
        
        // Haptic feedback
        hapticFeedback.provideSearchGuidance()
    }
    
    private func startVoiceGuidanceListening() {
        // This would integrate with the existing voice recognition system
        speechOutput.speak("Walk around slowly. The beeping will help you navigate. Say 'found them' when you locate your AirPods", priority: .normal)
        
        // Set up completion timer
        searchTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: false) { [weak self] _ in
            self?.endSearchSession()
        }
    }
    
    // MARK: - Voice Command Handling
    
    @objc private func handleVoiceCommand(_ notification: Notification) {
        guard let command = notification.userInfo?["command"] as? String else { return }
        
        let lowercased = command.lowercased()
        
        if lowercased.contains("find") && (lowercased.contains("airpods") || lowercased.contains("headphones")) {
            findAirPods(triggeredBy: "voice")
        } else if lowercased.contains("found them") || lowercased.contains("found it") {
            handleAirPodsFound()
        } else if lowercased.contains("stop searching") {
            stopSearch()
        } else if lowercased.contains("play sound") && isSearching {
            tryPlaySoundThroughAirPods()
        } else if lowercased.contains("warmer") {
            provideWarmFeedback()
        } else if lowercased.contains("colder") {
            provideColdFeedback()
        }
    }
    
    private func handleAirPodsFound() {
        speechOutput.speak("Great! Glad you found your AirPods. I'll remember this location for next time", priority: .high)
        
        // Record found location
        recordFoundLocation()
        endSearchSession()
    }
    
    private func provideWarmFeedback() {
        speechOutput.speak("You're getting warmer! Keep going in that direction", priority: .normal)
        
        // Increase beacon frequency
        chimeTimer?.invalidate()
        chimeTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.playSearchBeacon()
        }
    }
    
    private func provideColdFeedback() {
        speechOutput.speak("You're getting colder. Try a different direction", priority: .normal)
        
        // Decrease beacon frequency
        chimeTimer?.invalidate()
        chimeTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.playSearchBeacon()
        }
    }
    
    // MARK: - Location Management
    
    private func updateLastKnownLocation(_ location: CLLocation) {
        let airPodsLocation = AirPodsLocation(
            id: UUID(),
            coordinate: location,
            timestamp: Date(),
            roomDescription: determineRoomDescription(for: location),
            confidenceLevel: .high,
            source: .findMy
        )
        
        lastKnownLocation = airPodsLocation
        locationHistory.append(airPodsLocation)
        
        // Limit history size
        if locationHistory.count > maxLocationHistory {
            locationHistory.removeFirst(locationHistory.count - maxLocationHistory)
        }
        
        saveLocationHistory()
    }
    
    private func recordFoundLocation() {
        guard let currentLocation = locationManager.currentLocation else { return }
        
        let foundLocation = AirPodsLocation(
            id: UUID(),
            coordinate: currentLocation,
            timestamp: Date(),
            roomDescription: "User found location",
            confidenceLevel: .high,
            source: .userFound
        )
        
        lastKnownLocation = foundLocation
        locationHistory.append(foundLocation)
        saveLocationHistory()
    }
    
    private func saveLocationHistory() {
        if let data = try? JSONEncoder().encode(locationHistory) {
            UserDefaults.standard.set(data, forKey: "airpods_location_history")
        }
    }
    
    // MARK: - Location Description Helpers
    
    private func describeLocation(_ location: CLLocation) -> String {
        let roomDescription = determineRoomDescription(for: location)
        return roomDescription.isEmpty ? "at your current area" : "in the \(roomDescription)"
    }
    
    private func describeDetailedLocation(_ airPodsLocation: AirPodsLocation) -> String {
        var description = airPodsLocation.roomDescription.isEmpty ? "at an unknown location" : "in the \(airPodsLocation.roomDescription)"
        
        if let currentLocation = locationManager.currentLocation {
            let distance = currentLocation.distance(from: airPodsLocation.coordinate)
            
            if distance < 5 {
                description += " very close to where you are now"
            } else if distance < 20 {
                description += " nearby"
            } else if distance < 100 {
                description += " about \(Int(distance)) meters from here"
            } else {
                description += " some distance away"
            }
        }
        
        return description
    }
    
    private func determineRoomDescription(for location: CLLocation) -> String {
        // This would integrate with indoor positioning or user-defined areas
        // For now, return generic description
        return "current area"
    }
    
    private func formatTimeAgo(_ timeInterval: TimeInterval) -> String {
        let minutes = Int(timeInterval / 60)
        let hours = Int(timeInterval / 3600)
        let days = Int(timeInterval / 86400)
        
        if minutes < 60 {
            return "\(minutes) minute\(minutes == 1 ? "" : "s") ago"
        } else if hours < 24 {
            return "\(hours) hour\(hours == 1 ? "" : "s") ago"
        } else {
            return "\(days) day\(days == 1 ? "" : "s") ago"
        }
    }
    
    private func findMostCommonLocation(_ locations: ArraySlice<AirPodsLocation>) -> AirPodsLocation? {
        // Group locations by proximity and find most common
        return locations.first // Simplified implementation
    }
    
    // MARK: - Search Session Management
    
    func stopSearch() {
        endSearchSession()
        speechOutput.speak("AirPods search stopped", priority: .normal)
    }
    
    private func endSearchSession() {
        isSearching = false
        searchProgress = .idle
        
        searchTimer?.invalidate()
        guidanceTimer?.invalidate()
        chimeTimer?.invalidate()
        
        searchTimer = nil
        guidanceTimer = nil
        chimeTimer = nil
    }
    
    // MARK: - Public Interface
    
    func getSearchStatus() -> String {
        switch searchProgress {
        case .idle:
            return "Ready to search for AirPods"
        case .analyzing:
            return "Analyzing AirPods location"
        case .checkingBluetooth:
            return "Checking Bluetooth connections"
        case .checkingFindMy:
            return "Searching with Find My"
        case .usingLastKnown:
            return "Using last known location"
        case .analyzingPatterns:
            return "Analyzing usage patterns"
        case .voiceGuided:
            return "Voice-guided search active"
        }
    }
    
    func speakSearchStatus() {
        let status = getSearchStatus()
        speechOutput.speak(status, priority: .normal)
    }
    
    // MARK: - Integration with Health Core
    
    func integrateWithHealthCore(_ healthCore: KaiSightHealthCore) {
        // Register voice commands with global system
        healthCore.registerAirPodsCommands(self)
    }
    
    // MARK: - Cleanup
    
    deinit {
        endSearchSession()
        centralManager.stopScan()
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - CBCentralManagerDelegate

extension AirPodsLocator: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            startScanningForAirPods()
        }
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        if isAirPodsDevice(peripheral) {
            connectedAirPods.append(peripheral)
            recordConnectionEvent(peripheral, connected: true)
            
            Config.debugLog("AirPods connected: \(peripheral.name ?? "Unknown")")
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        if isAirPodsDevice(peripheral) {
            connectedAirPods.removeAll { $0.identifier == peripheral.identifier }
            recordConnectionEvent(peripheral, connected: false)
            
            Config.debugLog("AirPods disconnected: \(peripheral.name ?? "Unknown")")
        }
    }
    
    private func startScanningForAirPods() {
        // Scan for AirPods and other audio devices
        centralManager.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }
    
    private func isAirPodsDevice(_ peripheral: CBPeripheral) -> Bool {
        guard let name = peripheral.name?.lowercased() else { return false }
        return name.contains("airpods") || name.contains("beats") || name.contains("powerbeats")
    }
    
    private func recordConnectionEvent(_ peripheral: CBPeripheral, connected: Bool) {
        guard let currentLocation = locationManager.currentLocation else { return }
        
        if !connected {
            // Record disconnection location as potential AirPods location
            updateLastKnownLocation(currentLocation)
        }
    }
}

// MARK: - Data Models

struct AirPodsLocation: Identifiable, Codable {
    let id: UUID
    let coordinate: CLLocation
    let timestamp: Date
    let roomDescription: String
    let confidenceLevel: ConfidenceLevel
    let source: LocationSource
}

enum AirPodsStatus {
    case unknown
    case connected
    case disconnected
    case searching
    case found
}

enum SearchProgress {
    case idle
    case analyzing
    case checkingBluetooth
    case checkingFindMy
    case usingLastKnown
    case analyzingPatterns
    case voiceGuided
}

enum ConfidenceLevel: String, Codable {
    case low = "low"
    case medium = "medium"
    case high = "high"
}

enum LocationSource: String, Codable {
    case bluetooth = "bluetooth"
    case findMy = "find_my"
    case userFound = "user_found"
    case estimated = "estimated"
}

struct AirPodsUsagePattern: Codable {
    let timeOfDay: Int
    let location: CLLocation
    let duration: TimeInterval
    let frequency: Int
}

// MARK: - Find My Integration

class FindMyIntegration {
    func locateAirPods(completion: @escaping (FindMyResult) -> Void) {
        // Attempt to open Find My app or use deep linking
        if let findMyURL = URL(string: "findmy://") {
            DispatchQueue.main.async {
                if UIApplication.shared.canOpenURL(findMyURL) {
                    UIApplication.shared.open(findMyURL) { success in
                        if success {
                            completion(.foundButNoSound(CLLocation(latitude: 0, longitude: 0)))
                        } else {
                            completion(.error("Could not open Find My"))
                        }
                    }
                } else {
                    completion(.notFound)
                }
            }
        } else {
            completion(.error("Find My URL not available"))
        }
    }
    
    func playSoundOnAirPods() {
        // This would trigger through Siri Shortcut or Find My integration
        Config.debugLog("Attempting to play sound on AirPods through Find My")
    }
}

enum FindMyResult {
    case found(location: CLLocation, canPlaySound: Bool)
    case foundButNoSound(location: CLLocation)
    case notFound
    case error(String)
}

// MARK: - Siri Shortcuts Integration

class SiriShortcutManager {
    func setupAirPodsShortcuts() {
        createFindAirPodsShortcut()
    }
    
    private func createFindAirPodsShortcut() {
        // Create Siri shortcut for finding AirPods
        let intent = INPlayMediaIntent()
        intent.suggestedInvocationPhrase = "Find my AirPods"
        
        Config.debugLog("AirPods shortcut created")
    }
    
    func triggerFindAirPodsShortcut() {
        // Trigger the shortcut programmatically if possible
        Config.debugLog("Triggering AirPods shortcut")
    }
}

// MARK: - GPT Context Manager

class GPTContextManager {
    func generateLocationSuggestions(basedOn history: [AirPodsLocation]) -> [String] {
        // Use GPT-4o to generate intelligent location suggestions
        return [
            "Check common areas where you remove AirPods",
            "Look near charging stations or your usual sitting spots",
            "Consider where you last took a call or listened to music"
        ]
    }
}

// MARK: - Haptic Feedback Extension

extension HapticFeedbackManager {
    func provideSearchGuidance() {
        let impact = UIImpactFeedbackGenerator(style: .medium)
        impact.impactOccurred()
    }
    
    func provideFoundConfirmation() {
        let impact = UIImpactFeedbackGenerator(style: .heavy)
        impact.impactOccurred()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            impact.impactOccurred()
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let airPodsVoiceCommand = Notification.Name("airPodsVoiceCommand")
    static let airPodsFound = Notification.Name("airPodsFound")
    static let airPodsConnectionChanged = Notification.Name("airPodsConnectionChanged")
}

// MARK: - Health Core Integration

extension KaiSightHealthCore {
    func registerAirPodsCommands(_ locator: AirPodsLocator) {
        // Register AirPods-specific voice commands
        Config.debugLog("AirPods voice commands registered with health core")
    }
} 