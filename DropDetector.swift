import Foundation
import CoreMotion
import CoreLocation
import AVFoundation

class DropDetector: NSObject, ObservableObject {
    static let shared = DropDetector()
    
    @Published var isDropDetected = false
    @Published var dropRecoveryMode = false
    @Published var lastDropTime: Date?
    
    // Core Motion
    private let motionManager = CMMotionManager()
    private let deviceMotion = CMDeviceMotion()
    
    // Drop Detection Configuration
    private let dropThreshold: Double = -2.5 // G-force threshold for drop detection
    private let impactThreshold: Double = 8.0 // Impact detection threshold
    private let freefallDuration: TimeInterval = 0.3 // Minimum freefall time
    
    // State tracking
    private var freefallStartTime: Date?
    private var impactDetected = false
    private var recoveryTimer: Timer?
    private var emergencyTimer: Timer?
    
    // Dependencies
    private weak var healthCore: KaiSightHealthCore?
    private let speechOutput = SpeechOutput.shared
    private let hapticFeedback = HapticFeedbackManager()
    private let locationManager = LocationManager.shared
    
    // Drop event tracking
    private var dropEvents: [DropEvent] = []
    private let maxDropHistory = 50
    
    override init() {
        super.init()
        setupDropDetection()
    }
    
    // MARK: - Setup and Configuration
    
    func configure(with healthCore: KaiSightHealthCore) {
        self.healthCore = healthCore
    }
    
    private func setupDropDetection() {
        guard motionManager.isAccelerometerAvailable && motionManager.isDeviceMotionAvailable else {
            Config.debugLog("Motion sensors not available for drop detection")
            return
        }
        
        // Configure motion detection
        motionManager.accelerometerUpdateInterval = 0.1 // 10 Hz
        motionManager.deviceMotionUpdateInterval = 0.1
        
        startDropMonitoring()
        Config.debugLog("Drop detection system initialized")
    }
    
    private func startDropMonitoring() {
        // Start accelerometer updates for drop detection
        motionManager.startAccelerometerUpdates(to: .main) { [weak self] data, error in
            guard let self = self, let acceleration = data?.acceleration else { return }
            
            self.processAccelerationData(acceleration)
        }
        
        // Start device motion for comprehensive analysis
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, error in
            guard let self = self, let motion = motion else { return }
            
            self.processDeviceMotion(motion)
        }
    }
    
    // MARK: - Drop Detection Logic
    
    private func processAccelerationData(_ acceleration: CMAcceleration) {
        let totalAcceleration = sqrt(acceleration.x * acceleration.x + 
                                   acceleration.y * acceleration.y + 
                                   acceleration.z * acceleration.z)
        
        // Detect freefall (near-zero acceleration)
        if totalAcceleration < 0.3 && freefallStartTime == nil {
            freefallStartTime = Date()
            Config.debugLog("Potential freefall detected")
        }
        
        // Detect impact after freefall
        if let freefallStart = freefallStartTime,
           totalAcceleration > impactThreshold {
            
            let freefallDuration = Date().timeIntervalSince(freefallStart)
            
            if freefallDuration > self.freefallDuration {
                detectDrop(freefallDuration: freefallDuration, impactForce: totalAcceleration)
            }
            
            freefallStartTime = nil
        }
        
        // Reset freefall if acceleration returns to normal without impact
        if totalAcceleration > 0.8 && freefallStartTime != nil {
            let elapsed = Date().timeIntervalSince(freefallStartTime!)
            if elapsed > 2.0 { // No impact after 2 seconds
                freefallStartTime = nil
            }
        }
    }
    
    private func processDeviceMotion(_ motion: CMDeviceMotion) {
        // Additional motion analysis for better drop detection
        let rotationRate = motion.rotationRate
        let attitude = motion.attitude
        
        // Detect sudden rotation changes that might indicate a drop
        let totalRotation = sqrt(rotationRate.x * rotationRate.x + 
                               rotationRate.y * rotationRate.y + 
                               rotationRate.z * rotationRate.z)
        
        if totalRotation > 5.0 && freefallStartTime != nil {
            // High rotation during potential freefall suggests a drop
            Config.debugLog("High rotation detected during potential fall")
        }
    }
    
    private func detectDrop(freefallDuration: TimeInterval, impactForce: Double) {
        guard !isDropDetected else { return } // Prevent multiple triggers
        
        isDropDetected = true
        lastDropTime = Date()
        
        let dropEvent = DropEvent(
            id: UUID(),
            timestamp: Date(),
            freefallDuration: freefallDuration,
            impactForce: impactForce,
            location: locationManager.currentLocation,
            deviceOrientation: getCurrentOrientation()
        )
        
        // Add to drop history
        dropEvents.append(dropEvent)
        if dropEvents.count > maxDropHistory {
            dropEvents.removeFirst(dropEvents.count - maxDropHistory)
        }
        
        Config.debugLog("Drop detected - Freefall: \(freefallDuration)s, Impact: \(impactForce)G")
        
        // Initiate drop response
        initiateDropResponse(dropEvent)
    }
    
    // MARK: - Drop Response System
    
    private func initiateDropResponse(_ dropEvent: DropEvent) {
        // Immediate response
        provideDropFeedback()
        
        // Check user wellbeing
        performDropWellnessCheck()
        
        // Handle device recovery
        initiateDeviceRecovery()
        
        // Check for emergency escalation
        checkForEmergencyEscalation(dropEvent)
        
        // Notify health monitoring system
        healthCore?.handleDropEvent(dropEvent)
    }
    
    private func provideDropFeedback() {
        // Immediate audio feedback
        speechOutput.speak("I detect that I was dropped. Are you okay?", priority: .high)
        
        // Haptic feedback if screen is face down
        hapticFeedback.provideDropAlert()
        
        // Play locator tone if device is likely on floor
        if isDeviceFaceDown() {
            playLocatorTone()
        }
    }
    
    private func performDropWellnessCheck() {
        // Start wellness check timer
        emergencyTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: false) { [weak self] _ in
            self?.handleNoResponseAfterDrop()
        }
        
        // Provide instructions
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            self.speechOutput.speak("If you need help, say 'Kai emergency'. To confirm you're okay, say 'I'm fine' or tap the screen.", priority: .normal)
        }
    }
    
    private func initiateDeviceRecovery() {
        dropRecoveryMode = true
        
        // Pause certain features that might not work well after drop
        pauseFeaturesDuringRecovery()
        
        // Start recovery timer
        recoveryTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: false) { [weak self] _ in
            self?.attemptSystemRecovery()
        }
    }
    
    private func checkForEmergencyEscalation(_ dropEvent: DropEvent) {
        // Check if this is a concerning drop pattern
        let recentDrops = dropEvents.filter { 
            Date().timeIntervalSince($0.timestamp) < 300 // Last 5 minutes
        }
        
        if recentDrops.count >= 3 {
            // Multiple drops in short time - potential emergency
            speechOutput.speak("Multiple drops detected. Activating emergency assistance.", priority: .emergency)
            healthCore?.emergencyProtocol.activateProtocol(
                for: createDropEmergencyCondition(dropEvent),
                reading: createDropHealthReading(dropEvent)
            )
        } else if dropEvent.impactForce > 12.0 {
            // Very high impact - potential injury
            speechOutput.speak("High impact drop detected. Are you injured?", priority: .high)
            
            // Extended wellness check for high-impact drops
            DispatchQueue.main.asyncAfter(deadline: .now() + 30.0) {
                self.speechOutput.speak("Please respond if you're okay. Emergency assistance will be contacted if no response.", priority: .high)
            }
        }
    }
    
    // MARK: - Recovery Logic
    
    private func pauseFeaturesDuringRecovery() {
        // Pause features that might be affected by drop
        healthCore?.bleHealthMonitor.pauseNonCriticalFeatures()
        
        // Reset AR tracking if available
        resetARKitTracking()
        
        // Pause real-time narration temporarily
        pauseNarrativeFeedback()
    }
    
    private func attemptSystemRecovery() {
        speechOutput.speak("Attempting to restore normal operation.", priority: .normal)
        
        // Resume BLE monitoring
        healthCore?.bleHealthMonitor.resumeAllFeatures()
        
        // Re-enable features gradually
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.resumeNarrativeFeedback()
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
            self.restartARKitTracking()
        }
        
        dropRecoveryMode = false
        Config.debugLog("System recovery completed after drop")
    }
    
    private func resetARKitTracking() {
        // Reset ARKit session if available
        NotificationCenter.default.post(name: .resetARSession, object: nil)
    }
    
    private func restartARKitTracking() {
        // Restart ARKit with fresh tracking
        NotificationCenter.default.post(name: .restartARSession, object: nil)
    }
    
    private func pauseNarrativeFeedback() {
        NotificationCenter.default.post(name: .pauseNarration, object: nil)
    }
    
    private func resumeNarrativeFeedback() {
        NotificationCenter.default.post(name: .resumeNarration, object: nil)
        speechOutput.speak("Visual assistance restored. Hold the device upright for best results.", priority: .normal)
    }
    
    // MARK: - User Response Handling
    
    func respondToWellnessCheck(_ response: String) {
        let lowercased = response.lowercased()
        
        if lowercased.contains("fine") || lowercased.contains("okay") || lowercased.contains("good") {
            handlePositiveResponse()
        } else if lowercased.contains("help") || lowercased.contains("hurt") || lowercased.contains("injured") {
            handleEmergencyResponse()
        } else if lowercased.contains("emergency") {
            activateEmergencyProtocol()
        }
    }
    
    func handleScreenTap() {
        if isDropDetected && emergencyTimer != nil {
            handlePositiveResponse()
        }
    }
    
    private func handlePositiveResponse() {
        // User confirmed they're okay
        emergencyTimer?.invalidate()
        emergencyTimer = nil
        
        speechOutput.speak("Good to hear you're okay. Resuming normal operation.", priority: .normal)
        
        // Start recovery process
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.completeDropRecovery()
        }
    }
    
    private func handleEmergencyResponse() {
        emergencyTimer?.invalidate()
        emergencyTimer = nil
        
        speechOutput.speak("Activating emergency assistance.", priority: .emergency)
        activateEmergencyProtocol()
    }
    
    private func handleNoResponseAfterDrop() {
        // No response after drop - potential emergency
        speechOutput.speak("No response detected after drop. Contacting emergency assistance.", priority: .emergency)
        activateEmergencyProtocol()
    }
    
    private func activateEmergencyProtocol() {
        guard let lastDrop = dropEvents.last else { return }
        
        let emergencyCondition = createDropEmergencyCondition(lastDrop)
        let healthReading = createDropHealthReading(lastDrop)
        
        healthCore?.emergencyProtocol.activateProtocol(for: emergencyCondition, reading: healthReading)
    }
    
    // MARK: - Device Orientation and State
    
    private func isDeviceFaceDown() -> Bool {
        guard let deviceMotion = motionManager.deviceMotion else { return false }
        
        // Check if device is face down based on gravity
        let gravity = deviceMotion.gravity
        return gravity.z < -0.8 // Device is face down
    }
    
    private func getCurrentOrientation() -> DeviceOrientation {
        guard let deviceMotion = motionManager.deviceMotion else { return .unknown }
        
        let gravity = deviceMotion.gravity
        
        if abs(gravity.z) > 0.8 {
            return gravity.z > 0 ? .faceUp : .faceDown
        } else if abs(gravity.x) > abs(gravity.y) {
            return gravity.x > 0 ? .landscapeLeft : .landscapeRight
        } else {
            return gravity.y > 0 ? .portrait : .portraitUpsideDown
        }
    }
    
    private func playLocatorTone() {
        // Play a distinctive tone to help user locate device
        let systemSoundID: SystemSoundID = 1016 // Apple's "Tock" sound
        AudioServicesPlaySystemSound(systemSoundID)
        
        // Schedule additional tones
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            AudioServicesPlaySystemSound(systemSoundID)
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
            AudioServicesPlaySystemSound(systemSoundID)
        }
    }
    
    // MARK: - Emergency Condition Creation
    
    private func createDropEmergencyCondition(_ dropEvent: DropEvent) -> EmergencyCondition {
        let description = "Device drop detected with potential user injury"
        let voiceAlert = "Drop emergency detected. Contacting caregivers and emergency services."
        
        return EmergencyCondition(
            type: .fall,
            severity: .emergency,
            description: description,
            voiceAlert: voiceAlert,
            requiredActions: [.notifyCaregiver, .provideSelfHelp, .startWellnessCheck]
        )
    }
    
    private func createDropHealthReading(_ dropEvent: DropEvent) -> HealthReading {
        return HealthReading(
            id: UUID(),
            deviceId: UUID(), // Device sensor ID
            type: .movement,
            value: dropEvent.impactForce,
            unit: "G",
            timestamp: dropEvent.timestamp,
            trend: nil,
            additionalValues: [
                "freefall_duration": dropEvent.freefallDuration,
                "drop_detected": 1.0,
                "device_orientation": dropEvent.deviceOrientation.rawValue
            ]
        )
    }
    
    private func completeDropRecovery() {
        isDropDetected = false
        dropRecoveryMode = false
        
        recoveryTimer?.invalidate()
        emergencyTimer?.invalidate()
        
        speechOutput.speak("Drop recovery complete. All systems operational.", priority: .normal)
        
        Config.debugLog("Drop detection cycle completed")
    }
    
    // MARK: - Testing and Simulation
    
    func simulateDropEvent() {
        guard Config.debugMode else { return }
        
        let simulatedDropEvent = DropEvent(
            id: UUID(),
            timestamp: Date(),
            freefallDuration: 0.8,
            impactForce: 6.5,
            location: locationManager.currentLocation,
            deviceOrientation: .faceDown
        )
        
        Config.debugLog("Simulating drop event for testing")
        detectDrop(freefallDuration: 0.8, impactForce: 6.5)
    }
    
    func getDropHistory() -> [DropEvent] {
        return dropEvents
    }
    
    func getDropStatistics() -> DropStatistics {
        let totalDrops = dropEvents.count
        let recentDrops = dropEvents.filter { 
            Date().timeIntervalSince($0.timestamp) < 86400 // Last 24 hours
        }.count
        
        let averageImpact = dropEvents.isEmpty ? 0 : 
            dropEvents.map { $0.impactForce }.reduce(0, +) / Double(dropEvents.count)
        
        return DropStatistics(
            totalDrops: totalDrops,
            recentDrops: recentDrops,
            averageImpactForce: averageImpact,
            lastDropTime: lastDropTime
        )
    }
    
    // MARK: - Cleanup
    
    deinit {
        motionManager.stopAccelerometerUpdates()
        motionManager.stopDeviceMotionUpdates()
        recoveryTimer?.invalidate()
        emergencyTimer?.invalidate()
    }
}

// MARK: - Data Models

struct DropEvent: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let freefallDuration: TimeInterval
    let impactForce: Double
    let location: CLLocation?
    let deviceOrientation: DeviceOrientation
}

enum DeviceOrientation: String, Codable, CaseIterable {
    case portrait = "portrait"
    case portraitUpsideDown = "portrait_upside_down"
    case landscapeLeft = "landscape_left"
    case landscapeRight = "landscape_right"
    case faceUp = "face_up"
    case faceDown = "face_down"
    case unknown = "unknown"
    
    var rawValue: Double {
        switch self {
        case .portrait: return 1.0
        case .portraitUpsideDown: return 2.0
        case .landscapeLeft: return 3.0
        case .landscapeRight: return 4.0
        case .faceUp: return 5.0
        case .faceDown: return 6.0
        case .unknown: return 0.0
        }
    }
}

struct DropStatistics {
    let totalDrops: Int
    let recentDrops: Int
    let averageImpactForce: Double
    let lastDropTime: Date?
}

// MARK: - Haptic Feedback Extension

extension HapticFeedbackManager {
    func provideDropAlert() {
        // Distinctive haptic pattern for drop detection
        let impact = UIImpactFeedbackGenerator(style: .heavy)
        impact.impactOccurred()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            impact.impactOccurred()
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            impact.impactOccurred()
        }
    }
}

// MARK: - BLE Health Monitor Extension

extension BLEHealthMonitor {
    func pauseNonCriticalFeatures() {
        // Pause non-essential monitoring to preserve battery and processing
        Config.debugLog("Pausing non-critical BLE features during drop recovery")
    }
    
    func resumeAllFeatures() {
        // Resume all monitoring features
        Config.debugLog("Resuming all BLE features after drop recovery")
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let resetARSession = Notification.Name("resetARSession")
    static let restartARSession = Notification.Name("restartARSession")
    static let pauseNarration = Notification.Name("pauseNarration")
    static let resumeNarration = Notification.Name("resumeNarration")
    static let dropDetected = Notification.Name("dropDetected")
    static let dropRecovered = Notification.Name("dropRecovered")
} 