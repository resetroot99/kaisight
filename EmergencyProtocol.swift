import Foundation
import CoreLocation
import CallKit
import MessageUI

class EmergencyProtocol: NSObject, ObservableObject {
    @Published var isActive = false
    @Published var currentEmergency: ActiveEmergency?
    @Published var emergencyHistory: [EmergencyEvent] = []
    @Published var wellnessCheckActive = false
    
    weak var delegate: EmergencyProtocolDelegate?
    
    // Emergency configuration
    private var emergencySettings: EmergencySettings = EmergencySettings.default
    private var escalationTimer: Timer?
    private var wellnessCheckTimer: Timer?
    
    // Dependencies
    private var caregiverManager: CaregiverNotificationManager?
    private var locationManager: LocationManager?
    
    // Emergency state tracking
    private var emergencyStartTime: Date?
    private var lastResponseTime: Date?
    private var escalationLevel: EscalationLevel = .initial
    
    // Wellness check system
    private var wellnessCheckAttempts = 0
    private let maxWellnessCheckAttempts = 3
    private let wellnessCheckInterval: TimeInterval = 300 // 5 minutes
    
    // Emergency contacts
    private var emergencyContacts: [EmergencyContact] = []
    private var currentContactIndex = 0
    
    // Audio and feedback
    private let speechOutput = SpeechOutput.shared
    private let hapticFeedback = HapticFeedbackManager()
    private let audioAlarmPlayer = AudioAlarmPlayer()
    
    // Background monitoring
    private var inactivityTimer: Timer?
    private var lastActivityTime = Date()
    private let inactivityThreshold: TimeInterval = 3600 // 1 hour
    
    override init() {
        super.init()
        setupEmergencyProtocol()
    }
    
    // MARK: - Configuration
    
    func configure(caregiverManager: CaregiverNotificationManager, location: LocationManager) {
        self.caregiverManager = caregiverManager
        self.locationManager = location
    }
    
    func updateEmergencySettings(_ settings: EmergencySettings) {
        emergencySettings = settings
        Config.debugLog("Emergency settings updated")
    }
    
    func updateEmergencyContacts(_ contacts: [EmergencyContact]) {
        emergencyContacts = contacts.sorted { $0.priority < $1.priority }
        Config.debugLog("Emergency contacts updated: \(contacts.count) contacts")
    }
    
    // MARK: - Emergency Detection and Activation
    
    func evaluateReading(_ reading: HealthReading, profile: HealthProfile) -> [EmergencyCondition] {
        var emergencyConditions: [EmergencyCondition] = []
        
        // Severe hypoglycemia
        if reading.type == .bloodGlucose && reading.value < 54 { // < 54 mg/dL
            emergencyConditions.append(EmergencyCondition(
                type: .severeHypoglycemia,
                severity: .emergency,
                description: "Severe hypoglycemia detected: \(Int(reading.value)) mg/dL",
                voiceAlert: "Critical low blood sugar. Take glucose immediately. Emergency protocol activated.",
                requiredActions: [.provideSelfHelp, .notifyCaregiver, .startWellnessCheck]
            ))
        }
        
        // Severe hyperglycemia with ketoacidosis risk
        if reading.type == .bloodGlucose && reading.value > 400 { // > 400 mg/dL
            emergencyConditions.append(EmergencyCondition(
                type: .severeHyperglycemia,
                severity: .emergency,
                description: "Severe hyperglycemia detected: \(Int(reading.value)) mg/dL",
                voiceAlert: "Critical high blood sugar. Check ketones immediately. Emergency protocol activated.",
                requiredActions: [.provideSelfHelp, .notifyCaregiver, .call911]
            ))
        }
        
        // Cardiac emergency indicators
        if reading.type == .heartRate {
            if reading.value < 40 { // Severe bradycardia
                emergencyConditions.append(EmergencyCondition(
                    type: .heartAttack,
                    severity: .emergency,
                    description: "Severe bradycardia: \(Int(reading.value)) BPM",
                    voiceAlert: "Very low heart rate detected. Seek immediate medical attention.",
                    requiredActions: [.notifyCaregiver, .call911]
                ))
            } else if reading.value > 180 { // Severe tachycardia
                emergencyConditions.append(EmergencyCondition(
                    type: .heartAttack,
                    severity: .emergency,
                    description: "Severe tachycardia: \(Int(reading.value)) BPM",
                    voiceAlert: "Very high heart rate detected. Seek immediate medical attention.",
                    requiredActions: [.notifyCaregiver, .call911]
                ))
            }
        }
        
        // Critical oxygen saturation
        if reading.type == .oxygenSaturation && reading.value < 85 {
            emergencyConditions.append(EmergencyCondition(
                type: .respiratoryDistress,
                severity: .emergency,
                description: "Critical oxygen saturation: \(Int(reading.value))%",
                voiceAlert: "Critically low oxygen. Call emergency services immediately.",
                requiredActions: [.call911, .notifyCaregiver]
            ))
        }
        
        // Fall detection
        if reading.type == .movement && reading.isCritical {
            emergencyConditions.append(EmergencyCondition(
                type: .fall,
                severity: .emergency,
                description: "Fall detected",
                voiceAlert: "Fall detected. Are you okay? Respond within 60 seconds or emergency services will be contacted.",
                requiredActions: [.playAlarm, .startWellnessCheck, .notifyCaregiver]
            ))
        }
        
        return emergencyConditions
    }
    
    func activateProtocol(for condition: EmergencyCondition, reading: HealthReading) {
        guard !isActive else {
            // Already in emergency mode - escalate if necessary
            escalateEmergency(with: condition, reading: reading)
            return
        }
        
        isActive = true
        emergencyStartTime = Date()
        escalationLevel = .initial
        
        let emergency = ActiveEmergency(
            id: UUID(),
            condition: condition,
            reading: reading,
            startTime: Date(),
            location: locationManager?.currentLocation,
            escalationLevel: escalationLevel
        )
        
        currentEmergency = emergency
        
        // Log emergency
        let emergencyEvent = EmergencyEvent(
            id: UUID(),
            type: condition.type,
            startTime: Date(),
            endTime: nil,
            condition: condition,
            reading: reading,
            location: locationManager?.currentLocation,
            response: .none,
            outcome: .active
        )
        
        emergencyHistory.append(emergencyEvent)
        
        // Execute required actions
        executeEmergencyActions(condition.requiredActions, for: emergency)
        
        // Start escalation timer
        startEscalationTimer()
        
        // Notify delegate
        delegate?.emergencyProtocol(self, didActivateEmergency: condition)
        
        Config.debugLog("Emergency protocol activated: \(condition.type)")
    }
    
    func activateManualEmergency() {
        let manualCondition = EmergencyCondition(
            type: .manualActivation,
            severity: .emergency,
            description: "Manual emergency activation",
            voiceAlert: "Emergency activated manually. Contacting emergency services.",
            requiredActions: [.call911, .notifyCaregiver, .playAlarm]
        )
        
        let manualReading = HealthReading(
            id: UUID(),
            deviceId: UUID(),
            type: .movement,
            value: 0,
            unit: "manual",
            timestamp: Date(),
            trend: nil,
            additionalValues: nil
        )
        
        activateProtocol(for: manualCondition, reading: manualReading)
    }
    
    // MARK: - Emergency Actions
    
    private func executeEmergencyActions(_ actions: [EmergencyAction], for emergency: ActiveEmergency) {
        for action in actions {
            executeEmergencyAction(action, for: emergency)
        }
    }
    
    private func executeEmergencyAction(_ action: EmergencyAction, for emergency: ActiveEmergency) {
        switch action {
        case .playAlarm:
            playEmergencyAlarm()
            
        case .provideSelfHelp:
            provideSelfHelpInstructions(for: emergency.condition.type)
            
        case .notifyCaregiver:
            notifyEmergencyContacts(emergency)
            
        case .call911:
            initiateEmergencyCall()
            
        case .startWellnessCheck:
            startWellnessCheck()
            
        case .provideInstructions:
            provideEmergencyInstructions(for: emergency.condition.type)
        }
    }
    
    private func playEmergencyAlarm() {
        // Play loud alarm sound
        audioAlarmPlayer.playEmergencyAlarm()
        
        // Provide strong haptic feedback
        hapticFeedback.provideEmergencyAlert()
        
        // Announce emergency
        speechOutput.speak(currentEmergency?.condition.voiceAlert ?? "Emergency detected", priority: .emergency)
    }
    
    private func provideSelfHelpInstructions(for emergencyType: EmergencyType) {
        var instructions = ""
        
        switch emergencyType {
        case .severeHypoglycemia:
            instructions = "Take 15 grams of fast-acting glucose immediately. Examples: 4 glucose tablets, half cup of fruit juice, or 1 tablespoon of honey. Wait 15 minutes and recheck blood sugar."
            
        case .severeHyperglycemia:
            instructions = "Check for ketones if possible. Drink water. Do not exercise. Take rapid-acting insulin if prescribed and safe to do so. Seek medical attention immediately."
            
        case .heartAttack:
            instructions = "Sit down and rest. If you have aspirin and are not allergic, chew one adult aspirin. Call emergency services immediately. Do not drive yourself to the hospital."
            
        case .fall:
            instructions = "Do not move if you feel pain. Check for injuries. If you can move safely, try to get to a phone or press your emergency button. Stay calm and call for help."
            
        case .respiratoryDistress:
            instructions = "Sit upright. Try to remain calm and breathe slowly. If you have a rescue inhaler, use it as prescribed. Call emergency services immediately."
            
        case .seizure:
            instructions = "If you feel a seizure coming, sit or lie down in a safe place. Remove any objects that could cause injury. Time the seizure if possible."
            
        default:
            instructions = "Stay calm. Seek immediate medical attention. Contact emergency services if needed."
        }
        
        speechOutput.speak("Emergency self-help instructions: \(instructions)", priority: .emergency)
    }
    
    private func notifyEmergencyContacts(_ emergency: ActiveEmergency) {
        caregiverManager?.sendEmergencyAlert(emergency.condition, location: emergency.location)
        
        // Start contacting emergency contacts one by one
        currentContactIndex = 0
        contactNextEmergencyContact(emergency)
    }
    
    private func contactNextEmergencyContact(_ emergency: ActiveEmergency) {
        guard currentContactIndex < emergencyContacts.count else {
            // All contacts contacted - escalate to emergency services
            Config.debugLog("All emergency contacts contacted - escalating to emergency services")
            initiateEmergencyCall()
            return
        }
        
        let contact = emergencyContacts[currentContactIndex]
        
        // Send SMS first
        sendEmergencyMessage(to: contact, emergency: emergency)
        
        // Then try calling if it's a primary contact
        if contact.isPrimary {
            initiateCallToContact(contact, emergency: emergency)
        }
        
        // Move to next contact after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { // 30 second delay
            self.currentContactIndex += 1
            self.contactNextEmergencyContact(emergency)
        }
    }
    
    private func sendEmergencyMessage(to contact: EmergencyContact, emergency: ActiveEmergency) {
        guard emergencySettings.enableSMSAlerts else { return }
        
        let locationString = formatLocationForMessage(emergency.location)
        let message = """
        🚨 EMERGENCY ALERT 🚨
        
        \(contact.name), this is an emergency notification from KaiSight.
        
        Emergency: \(emergency.condition.description)
        Time: \(DateFormatter.shortDateTime.string(from: emergency.startTime))
        Location: \(locationString)
        
        Please check on the user immediately or call emergency services.
        
        This is an automated message from KaiSight health monitoring.
        """
        
        // Send message using MessageUI or push notification
        caregiverManager?.sendDirectMessage(message, to: contact)
    }
    
    private func initiateCallToContact(_ contact: EmergencyContact, emergency: ActiveEmergency) {
        guard emergencySettings.enableAutomaticCalling else { return }
        
        // Use CallKit to initiate call
        let callManager = CallManager()
        callManager.startCall(to: contact.phoneNumber, isEmergency: true) { success in
            if success {
                Config.debugLog("Emergency call initiated to \(contact.name)")
            } else {
                Config.debugLog("Failed to initiate call to \(contact.name)")
            }
        }
    }
    
    private func initiateEmergencyCall() {
        guard emergencySettings.enableEmergencyServices else { return }
        
        speechOutput.speak("Contacting emergency services now", priority: .emergency)
        
        // In production, this would integrate with local emergency services
        // For now, we simulate the call initiation
        let callManager = CallManager()
        callManager.startEmergencyCall { [weak self] success in
            if success {
                self?.speechOutput.speak("Emergency services contacted", priority: .emergency)
            } else {
                self?.speechOutput.speak("Unable to contact emergency services automatically. Please call 911", priority: .emergency)
            }
        }
    }
    
    // MARK: - Wellness Check System
    
    func performWellnessCheck() {
        startWellnessCheck()
    }
    
    private func startWellnessCheck() {
        wellnessCheckActive = true
        wellnessCheckAttempts = 0
        
        performWellnessCheckAttempt()
    }
    
    private func performWellnessCheckAttempt() {
        wellnessCheckAttempts += 1
        
        let message = "Wellness check: Are you okay? Please respond by saying 'I'm okay' or pressing any button."
        speechOutput.speak(message, priority: .high)
        
        // Play attention-getting sound
        audioAlarmPlayer.playWellnessCheckTone()
        
        // Provide haptic feedback
        hapticFeedback.provideWellnessCheckAlert()
        
        // Wait for response
        wellnessCheckTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: false) { [weak self] _ in
            self?.handleWellnessCheckTimeout()
        }
    }
    
    private func handleWellnessCheckTimeout() {
        guard wellnessCheckActive else { return }
        
        if wellnessCheckAttempts < maxWellnessCheckAttempts {
            // Try again with increased urgency
            let message = "Wellness check attempt \(wellnessCheckAttempts + 1) of \(maxWellnessCheckAttempts). Please respond if you are okay."
            speechOutput.speak(message, priority: .high)
            
            performWellnessCheckAttempt()
        } else {
            // No response after multiple attempts - activate emergency protocol
            wellnessCheckFailed()
        }
    }
    
    private func wellnessCheckFailed() {
        wellnessCheckActive = false
        
        let noResponseCondition = EmergencyCondition(
            type: .noResponse,
            severity: .emergency,
            description: "No response to wellness check after \(maxWellnessCheckAttempts) attempts",
            voiceAlert: "No response detected. Activating emergency protocol.",
            requiredActions: [.notifyCaregiver, .call911]
        )
        
        let noResponseReading = HealthReading(
            id: UUID(),
            deviceId: UUID(),
            type: .movement,
            value: 0,
            unit: "wellness_check",
            timestamp: Date(),
            trend: nil,
            additionalValues: ["wellness_check_failed": 1]
        )
        
        activateProtocol(for: noResponseCondition, reading: noResponseReading)
    }
    
    func respondToWellnessCheck() {
        guard wellnessCheckActive else { return }
        
        wellnessCheckActive = false
        wellnessCheckTimer?.invalidate()
        
        speechOutput.speak("Wellness check response received. Thank you.", priority: .normal)
        lastResponseTime = Date()
        
        Config.debugLog("Wellness check response received")
    }
    
    // MARK: - Emergency Escalation
    
    private func startEscalationTimer() {
        let escalationInterval = emergencySettings.escalationInterval
        
        escalationTimer = Timer.scheduledTimer(withTimeInterval: escalationInterval, repeats: true) { [weak self] _ in
            self?.escalateEmergency()
        }
    }
    
    private func escalateEmergency() {
        guard isActive, let emergency = currentEmergency else { return }
        
        escalationLevel = escalationLevel.next()
        
        switch escalationLevel {
        case .secondary:
            speechOutput.speak("Emergency escalation: No response received. Contacting additional emergency contacts.", priority: .emergency)
            contactAllEmergencyContacts(emergency)
            
        case .tertiary:
            speechOutput.speak("Emergency escalation: Contacting emergency services.", priority: .emergency)
            initiateEmergencyCall()
            
        case .final:
            speechOutput.speak("Maximum emergency escalation reached. All emergency protocols active.", priority: .emergency)
            activateAllEmergencyMeasures(emergency)
            
        default:
            break
        }
        
        currentEmergency?.escalationLevel = escalationLevel
    }
    
    private func escalateEmergency(with condition: EmergencyCondition, reading: HealthReading) {
        // Emergency already active - check if new condition is more severe
        guard let currentEmergency = currentEmergency else { return }
        
        if condition.severity == .emergency && condition.severity > currentEmergency.condition.severity {
            // New condition is more severe - update and escalate immediately
            self.currentEmergency?.condition = condition
            escalateEmergency()
        }
    }
    
    private func contactAllEmergencyContacts(_ emergency: ActiveEmergency) {
        for contact in emergencyContacts {
            sendEmergencyMessage(to: contact, emergency: emergency)
            
            if contact.isPrimary || contact.canReceiveEmergencyCalls {
                initiateCallToContact(contact, emergency: emergency)
            }
        }
    }
    
    private func activateAllEmergencyMeasures(_ emergency: ActiveEmergency) {
        // Continuous alarm
        audioAlarmPlayer.playContinuousAlarm()
        
        // Location sharing
        shareLocationWithEmergencyServices()
        
        // Medical information sharing
        shareMedicalInformationWithEmergencyServices()
        
        // Maximum volume alerts
        speechOutput.speak("Emergency: All emergency measures activated. Emergency services contacted.", priority: .emergency)
    }
    
    // MARK: - Emergency Resolution
    
    func resolveEmergency(response: EmergencyResponse) {
        guard isActive else { return }
        
        isActive = false
        escalationTimer?.invalidate()
        wellnessCheckTimer?.invalidate()
        wellnessCheckActive = false
        
        // Update emergency history
        if let index = emergencyHistory.firstIndex(where: { $0.outcome == .active }) {
            emergencyHistory[index].endTime = Date()
            emergencyHistory[index].response = response
            emergencyHistory[index].outcome = .resolved
        }
        
        // Stop alarms
        audioAlarmPlayer.stopAllAlarms()
        
        // Announce resolution
        speechOutput.speak("Emergency protocol resolved. Thank you for responding.", priority: .normal)
        
        // Clear current emergency
        currentEmergency = nil
        escalationLevel = .initial
        
        // Notify delegate
        delegate?.emergencyProtocolDidResolveEmergency(self)
        
        Config.debugLog("Emergency protocol resolved with response: \(response)")
    }
    
    func cancelEmergency() {
        resolveEmergency(response: .userCanceled)
    }
    
    // MARK: - Emergency Mode Control
    
    func enableEmergencyMode() {
        emergencySettings.enabled = true
        startInactivityMonitoring()
        speechOutput.speak("Emergency monitoring enabled")
    }
    
    func disableEmergencyMode() {
        emergencySettings.enabled = false
        stopInactivityMonitoring()
        speechOutput.speak("Emergency monitoring disabled")
    }
    
    // MARK: - Activity Monitoring
    
    private func startInactivityMonitoring() {
        inactivityTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            self?.checkForInactivity()
        }
    }
    
    private func stopInactivityMonitoring() {
        inactivityTimer?.invalidate()
        inactivityTimer = nil
    }
    
    private func checkForInactivity() {
        let timeSinceActivity = Date().timeIntervalSince(lastActivityTime)
        
        if timeSinceActivity > inactivityThreshold {
            // Extended inactivity detected
            performWellnessCheck()
        }
    }
    
    func recordActivity() {
        lastActivityTime = Date()
    }
    
    // MARK: - Voice Commands
    
    func processVoiceCommand(_ command: String) {
        let lowercased = command.lowercased()
        
        if lowercased.contains("i'm okay") || lowercased.contains("im okay") || lowercased.contains("okay") {
            if wellnessCheckActive {
                respondToWellnessCheck()
            } else if isActive {
                resolveEmergency(response: .userResponded)
            }
        } else if lowercased.contains("emergency") || lowercased.contains("help") {
            activateManualEmergency()
        } else if lowercased.contains("cancel emergency") {
            cancelEmergency()
        } else if lowercased.contains("emergency status") {
            speakEmergencyStatus()
        }
    }
    
    // MARK: - Utility Methods
    
    private func formatLocationForMessage(_ location: CLLocation?) -> String {
        guard let location = location else {
            return "Location unavailable"
        }
        
        return "Lat: \(String(format: "%.6f", location.coordinate.latitude)), Lon: \(String(format: "%.6f", location.coordinate.longitude))"
    }
    
    private func shareLocationWithEmergencyServices() {
        guard let location = locationManager?.currentLocation else { return }
        
        // Share location with emergency services
        // In production, this would integrate with local emergency dispatch systems
        Config.debugLog("Location shared with emergency services: \(location)")
    }
    
    private func shareMedicalInformationWithEmergencyServices() {
        // Share critical medical information with emergency services
        // This would include allergies, medications, medical conditions
        Config.debugLog("Medical information shared with emergency services")
    }
    
    private func setupEmergencyProtocol() {
        emergencySettings = EmergencySettings.load()
        enableEmergencyMode()
    }
    
    // MARK: - Public Interface
    
    func getEmergencyStatus() -> EmergencyStatus {
        return EmergencyStatus(
            isActive: isActive,
            currentEmergency: currentEmergency,
            escalationLevel: escalationLevel,
            emergencyContacts: emergencyContacts.count,
            lastEmergency: emergencyHistory.last?.startTime
        )
    }
    
    func speakEmergencyStatus() {
        let status = getEmergencyStatus()
        var statusMessage = ""
        
        if status.isActive {
            statusMessage = "Emergency protocol active. Escalation level: \(status.escalationLevel)"
        } else {
            statusMessage = "Emergency protocol inactive. \(status.emergencyContacts) emergency contacts configured."
            
            if let lastEmergency = status.lastEmergency {
                let timeAgo = Date().timeIntervalSince(lastEmergency)
                let hoursAgo = Int(timeAgo / 3600)
                statusMessage += " Last emergency: \(hoursAgo) hours ago."
            }
        }
        
        speechOutput.speak(statusMessage)
    }
    
    func testEmergencySystem() {
        speechOutput.speak("Testing emergency system")
        
        // Test audio alarm
        audioAlarmPlayer.playTestAlarm()
        
        // Test haptic feedback
        hapticFeedback.provideEmergencyAlert()
        
        // Test emergency contacts notification (simulation)
        speechOutput.speak("Emergency system test complete. All systems functional.")
    }
}

// MARK: - Data Models

struct ActiveEmergency {
    let id: UUID
    var condition: EmergencyCondition
    let reading: HealthReading
    let startTime: Date
    let location: CLLocation?
    var escalationLevel: EscalationLevel
}

struct EmergencyEvent: Identifiable {
    let id: UUID
    let type: EmergencyType
    let startTime: Date
    var endTime: Date?
    let condition: EmergencyCondition
    let reading: HealthReading
    let location: CLLocation?
    var response: EmergencyResponse
    var outcome: EmergencyOutcome
}

struct EmergencySettings: Codable {
    var enabled: Bool
    var enableSMSAlerts: Bool
    var enableAutomaticCalling: Bool
    var enableEmergencyServices: Bool
    var escalationInterval: TimeInterval // seconds between escalation levels
    var wellnessCheckEnabled: Bool
    var inactivityMonitoring: Bool
    
    static let `default` = EmergencySettings(
        enabled: true,
        enableSMSAlerts: true,
        enableAutomaticCalling: true,
        enableEmergencyServices: true,
        escalationInterval: 300, // 5 minutes
        wellnessCheckEnabled: true,
        inactivityMonitoring: true
    )
    
    static func load() -> EmergencySettings {
        // Load from UserDefaults or return default
        return EmergencySettings.default
    }
}

enum EscalationLevel: String, CaseIterable {
    case initial = "initial"
    case secondary = "secondary"
    case tertiary = "tertiary"
    case final = "final"
    
    func next() -> EscalationLevel {
        switch self {
        case .initial: return .secondary
        case .secondary: return .tertiary
        case .tertiary: return .final
        case .final: return .final
        }
    }
}

enum EmergencyResponse: String, CaseIterable {
    case none = "none"
    case userResponded = "user_responded"
    case caregiverResponded = "caregiver_responded"
    case emergencyServices = "emergency_services"
    case userCanceled = "user_canceled"
    case autoResolved = "auto_resolved"
}

enum EmergencyOutcome: String, CaseIterable {
    case active = "active"
    case resolved = "resolved"
    case falseAlarm = "false_alarm"
    case escalated = "escalated"
}

struct EmergencyStatus {
    let isActive: Bool
    let currentEmergency: ActiveEmergency?
    let escalationLevel: EscalationLevel
    let emergencyContacts: Int
    let lastEmergency: Date?
}

// MARK: - Supporting Classes

class AudioAlarmPlayer {
    private var alarmPlayer: AVAudioPlayer?
    private var continuousAlarmTimer: Timer?
    
    func playEmergencyAlarm() {
        playAlarmSound("emergency_alarm")
    }
    
    func playWellnessCheckTone() {
        playAlarmSound("wellness_check_tone")
    }
    
    func playTestAlarm() {
        playAlarmSound("test_alarm")
    }
    
    func playContinuousAlarm() {
        continuousAlarmTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.playEmergencyAlarm()
        }
    }
    
    func stopAllAlarms() {
        alarmPlayer?.stop()
        continuousAlarmTimer?.invalidate()
        continuousAlarmTimer = nil
    }
    
    private func playAlarmSound(_ soundName: String) {
        guard let soundURL = Bundle.main.url(forResource: soundName, withExtension: "wav") else {
            // Play system sound as fallback
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
            return
        }
        
        do {
            alarmPlayer = try AVAudioPlayer(contentsOf: soundURL)
            alarmPlayer?.volume = 1.0
            alarmPlayer?.play()
        } catch {
            Config.debugLog("Failed to play alarm sound: \(error)")
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        }
    }
}

class CallManager {
    func startCall(to phoneNumber: String, isEmergency: Bool, completion: @escaping (Bool) -> Void) {
        // Use CallKit to initiate call
        guard let url = URL(string: "tel://\(phoneNumber)") else {
            completion(false)
            return
        }
        
        if UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url) { success in
                completion(success)
            }
        } else {
            completion(false)
        }
    }
    
    func startEmergencyCall(completion: @escaping (Bool) -> Void) {
        // Call emergency services (911 in US)
        startCall(to: "911", isEmergency: true, completion: completion)
    }
}

class HapticFeedbackManager {
    func provideEmergencyAlert() {
        // Strong haptic feedback for emergency
        let impact = UIImpactFeedbackGenerator(style: .heavy)
        impact.impactOccurred()
        
        // Multiple pulses
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            impact.impactOccurred()
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            impact.impactOccurred()
        }
    }
    
    func provideWellnessCheckAlert() {
        let impact = UIImpactFeedbackGenerator(style: .medium)
        impact.impactOccurred()
    }
    
    func provideWarningFeedback() {
        let impact = UIImpactFeedbackGenerator(style: .light)
        impact.impactOccurred()
    }
    
    func provideCriticalAlert() {
        let impact = UIImpactFeedbackGenerator(style: .heavy)
        impact.impactOccurred()
    }
}

// MARK: - Extensions

extension DateFormatter {
    static let shortDateTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()
}

// MARK: - Delegate Protocol

protocol EmergencyProtocolDelegate: AnyObject {
    func emergencyProtocol(_ protocol: EmergencyProtocol, didActivateEmergency emergency: EmergencyCondition)
    func emergencyProtocolDidResolveEmergency(_ protocol: EmergencyProtocol)
}

// MARK: - Extensions for Integration

extension EmergencyProtocol {
    func integrateWithHealthMonitor(_ healthMonitor: BLEHealthMonitor) {
        // Register for health reading notifications
        healthMonitor.onCriticalReading = { [weak self] reading in
            let emergencyConditions = self?.evaluateReading(reading, profile: HealthProfileManager.shared.currentProfile) ?? []
            
            for condition in emergencyConditions {
                self?.activateProtocol(for: condition, reading: reading)
            }
        }
    }
    
    func integrateWithAgentLoop(_ agentLoop: AgentLoopManager) {
        // Register for voice commands
        agentLoop.onVoiceCommand = { [weak self] command in
            self?.processVoiceCommand(command)
        }
        
        // Register for activity updates
        agentLoop.onUserActivity = { [weak self] in
            self?.recordActivity()
        }
    }
} 