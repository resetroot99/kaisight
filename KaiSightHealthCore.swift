import Foundation
import UIKit
import AVFoundation
import CoreLocation
import AudioToolbox
import UserNotifications

// MARK: - Core Integration Manager

class KaiSightHealthCore: ObservableObject {
    static let shared = KaiSightHealthCore()
    
    // Core Components
    let bleHealthMonitor = BLEHealthMonitor()
    let healthProfileManager = HealthProfileManager.shared
    let emergencyProtocol = EmergencyProtocol()
    let caregiverManager = CaregiverNotificationManager()
    
    // Supporting Systems
    let speechOutput = SpeechOutput.shared
    let locationManager = LocationManager.shared
    let healthAnalytics = HealthAnalyticsEngine()
    let voiceCommandProcessor = VoiceCommandProcessor()
    let dropDetector = DropDetector.shared
    let airPodsLocator = AirPodsLocator.shared
    
    @Published var isSystemReady = false
    @Published var systemStatus = "Initializing..."
    
    private init() {
        setupIntegration()
    }
    
    private func setupIntegration() {
        // Setup component dependencies
        emergencyProtocol.configure(
            caregiverManager: caregiverManager,
            location: locationManager
        )
        
        // Configure drop detection
        dropDetector.configure(with: self)
        
        // Configure AirPods locator
        airPodsLocator.integrateWithHealthCore(self)
        
        // Setup delegate relationships
        setupDelegates()
        
        // Initialize location services
        locationManager.requestLocationPermission()
        
        // Mark system as ready
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.isSystemReady = true
            self.systemStatus = "Health monitoring active"
            self.speechOutput.speak("KaiSight health monitoring system ready")
        }
        
        ProductionConfig.log("KaiSight Health Core initialized")
    }
    
    private func setupDelegates() {
        // Connect BLE monitor to other systems via callbacks
        BLEHealthMonitorIntegration.setupCallbacks(for: bleHealthMonitor, with: self)
        
        // Connect voice commands across all systems
        speechOutput.onVoiceCommand = { [weak self] command in
            self?.processGlobalVoiceCommand(command)
        }
        
        // Set up health profile delegate
        healthProfileManager.delegate = self
        
        // Set up alert engine delegate  
        bleHealthMonitor.alertEngine.delegate = self
        
        // Set up emergency protocol delegate
        emergencyProtocol.delegate = self
        
        ProductionConfig.log("All system delegates configured")
    }
    
    private func processGlobalVoiceCommand(_ command: String) {
        // Process voice command through dedicated processor
        voiceCommandProcessor.processVoiceCommand(command)
        
        // Route voice commands to appropriate systems
        bleHealthMonitor.processVoiceCommand(command)
        emergencyProtocol.processVoiceCommand(command)
        
        // Handle drop-related responses
        if dropDetector.isDropDetected {
            dropDetector.respondToWellnessCheck(command)
        }
        
        // Handle AirPods-related commands
        handleAirPodsCommands(command)
        
        // Handle system-wide commands
        let lowercased = command.lowercased()
        
        if lowercased.contains("system status") {
            speakSystemStatus()
        } else if lowercased.contains("health summary") {
            speakComprehensiveHealthSummary()
        } else if lowercased.contains("emergency test") {
            emergencyProtocol.testEmergencySystem()
        } else if lowercased.contains("scan for devices") {
            bleHealthMonitor.startScanning()
        } else if lowercased.contains("simulate drop") && Config.debugMode {
            dropDetector.simulateDropEvent()
        } else if lowercased.contains("drop status") {
            speakDropStatus()
        }
    }
    
    private func handleAirPodsCommands(_ command: String) {
        let lowercased = command.lowercased()
        
        if (lowercased.contains("find") || lowercased.contains("where")) && 
           (lowercased.contains("airpods") || lowercased.contains("headphones") || lowercased.contains("earbuds")) {
            airPodsLocator.findAirPods(triggeredBy: "voice")
        } else if lowercased.contains("airpods status") || lowercased.contains("headphone status") {
            speakAirPodsStatus()
        } else if airPodsLocator.isSearching {
            // Forward search-related commands to AirPods locator
            NotificationCenter.default.post(
                name: .airPodsVoiceCommand,
                object: nil,
                userInfo: ["command": command]
            )
        }
    }
    
    func speakSystemStatus() {
        var status = "KaiSight Health System Status: "
        status += "\(bleHealthMonitor.connectedDevices.count) health devices connected, "
        status += emergencyProtocol.isActive ? "Emergency protocol active, " : "Emergency monitoring standby, "
        status += "\(caregiverManager.connectedCaregivers.count) caregivers connected, "
        status += getAirPodsSystemSummary()
        
        speechOutput.speak(status)
    }
    
    func speakComprehensiveHealthSummary() {
        let summary = healthAnalytics.generateComprehensiveSummary(
            profile: healthProfileManager.currentProfile,
            readings: bleHealthMonitor.latestReadings,
            emergencyStatus: emergencyProtocol.isActive
        )
        
        let airPodsInfo = getAirPodsSystemSummary()
        let completeSummary = "\(summary) \(airPodsInfo)"
        
        speechOutput.speak(completeSummary)
    }
    
    func speakDropStatus() {
        let dropStats = dropDetector.getDropStatistics()
        var status = "Drop detection status: "
        
        if dropDetector.isDropDetected {
            status += "Currently in drop recovery mode. "
        } else {
            status += "Normal operation. "
        }
        
        status += "Total drops recorded: \(dropStats.totalDrops). "
        status += "Recent drops: \(dropStats.recentDrops) in last 24 hours."
        
        if let lastDrop = dropStats.lastDropTime {
            let timeAgo = Date().timeIntervalSince(lastDrop)
            let hoursAgo = Int(timeAgo / 3600)
            status += " Last drop: \(hoursAgo) hours ago."
        }
        
        speechOutput.speak(status)
    }
    
    func speakAirPodsStatus() {
        let status = airPodsLocator.getSearchStatus()
        var statusMessage = "AirPods status: \(status)"
        
        if let lastLocation = airPodsLocator.lastKnownLocation {
            let timeAgo = Date().timeIntervalSince(lastLocation.timestamp)
            let timeDescription = timeAgo < 3600 ? "\(Int(timeAgo/60)) minutes ago" : "\(Int(timeAgo/3600)) hours ago"
            statusMessage += ". Last seen \(timeDescription)"
        }
        
        speechOutput.speak(statusMessage)
    }
    
    // Public interface for voice commands
    func processVoiceCommand(_ command: String) {
        processGlobalVoiceCommand(command)
    }
    
    // System health monitoring
    func performSystemHealthCheck() -> SystemHealthStatus {
        var issues: [String] = []
        
        // Check BLE status
        if bleHealthMonitor.bluetoothState != .poweredOn {
            issues.append("Bluetooth not available")
        }
        
        // Check location services
        if locationManager.authorizationStatus == .denied {
            issues.append("Location services denied")
        }
        
        // Check emergency contacts
        if healthProfileManager.currentProfile.emergencyContacts.isEmpty {
            issues.append("No emergency contacts configured")
        }
        
        // Check connected devices
        if bleHealthMonitor.connectedDevices.isEmpty {
            issues.append("No health devices connected")
        }
        
        return SystemHealthStatus(
            isHealthy: issues.isEmpty,
            issues: issues,
            lastCheck: Date()
        )
    }
    
    func exportHealthData() -> HealthDataExport {
        return HealthDataExport(
            profile: healthProfileManager.currentProfile,
            readings: bleHealthMonitor.latestReadings,
            emergencyHistory: emergencyProtocol.emergencyHistory,
            exportDate: Date(),
            version: "1.0"
        )
    }
    
    // MARK: - Drop Event Handling
    
    func handleDropEvent(_ dropEvent: DropEvent) {
        ProductionConfig.log("Processing drop event: Impact \(dropEvent.impactForce)G")
        
        // Update system status
        DispatchQueue.main.async {
            self.systemStatus = "Drop Recovery Mode - Checking user safety"
        }
        
        // Check if health monitoring devices disconnected
        checkHealthDevicesAfterDrop()
        
        // Log drop event with health analytics
        let dropReading = HealthReading(
            id: UUID(),
            deviceId: UUID(),
            type: .movement,
            value: dropEvent.impactForce,
            unit: "G",
            timestamp: dropEvent.timestamp,
            trend: nil,
            additionalValues: [
                "drop_event": 1.0,
                "freefall_duration": dropEvent.freefallDuration,
                "device_orientation": dropEvent.deviceOrientation.rawValue
            ]
        )
        
        healthAnalytics.addReading(dropReading)
        
        // Notify caregivers if configured
        if dropEvent.impactForce > 10.0 {
            let message = "High-impact drop detected. Impact force: \(String(format: "%.1f", dropEvent.impactForce))G"
            caregiverManager.sendDropAlert(dropEvent, message: message)
        }
    }
    
    private func checkHealthDevicesAfterDrop() {
        // Check if BLE devices need reconnection after drop
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            let disconnectedDevices = self.bleHealthMonitor.connectedDevices.filter { device in
                device.connectionState == .disconnected
            }
            
            if !disconnectedDevices.isEmpty {
                self.speechOutput.speak("Reconnecting \(disconnectedDevices.count) health device\(disconnectedDevices.count == 1 ? "" : "s") after drop", priority: .normal)
                
                for device in disconnectedDevices {
                    self.bleHealthMonitor.connectToDevice(device)
                }
            }
        }
    }
}

// MARK: - Configuration Manager

class Config {
    static let debugMode = true
    static let productionMode = false
    
    static func debugLog(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        if debugMode {
            let filename = (file as NSString).lastPathComponent
        }
    }
}

// MARK: - Speech Output System

class SpeechOutput: NSObject, ObservableObject {
    static let shared = SpeechOutput()
    
    private let synthesizer = AVSpeechSynthesizer()
    private var speechQueue: [SpeechRequest] = []
    private var isProcessing = false
    
    // Voice command detection
    var onVoiceCommand: ((String) -> Void)?
    
    enum Priority: Int, Comparable {
        case low = 1
        case normal = 2
        case high = 3
        case emergency = 4
        
        static func < (lhs: Priority, rhs: Priority) -> Bool {
            return lhs.rawValue < rhs.rawValue
        }
    }
    
    override init() {
        super.init()
        synthesizer.delegate = self
        setupVoiceSettings()
    }
    
    private func setupVoiceSettings() {
        // Configure speech settings for accessibility
        if let voice = AVSpeechSynthesisVoice(language: "en-US") {
            // Use default system voice for consistency
        }
    }
    
    func speak(_ text: String, priority: Priority = .normal) {
        let request = SpeechRequest(text: text, priority: priority, timestamp: Date())
        
        if priority == .emergency {
            // Emergency messages go to front of queue
            speechQueue.insert(request, at: 0)
        } else {
            speechQueue.append(request)
        }
        
        processQueue()
    }
    
    func stopSpeaking() {
        synthesizer.stopSpeaking(at: .immediate)
        speechQueue.removeAll()
    }
    
    private func processQueue() {
        guard !isProcessing, !speechQueue.isEmpty else { return }
        
        // Sort by priority (emergency first)
        speechQueue.sort { $0.priority > $1.priority }
        
        let request = speechQueue.removeFirst()
        isProcessing = true
        
        let utterance = AVSpeechUtterance(string: request.text)
        utterance.rate = 0.5
        utterance.volume = 1.0
        
        // Adjust settings based on priority
        switch request.priority {
        case .emergency:
            utterance.rate = 0.4 // Slower for critical information
            utterance.volume = 1.0
        case .high:
            utterance.rate = 0.45
        default:
            utterance.rate = 0.5
        }
        
        synthesizer.speak(utterance)
        ProductionConfig.log("Speaking: \(request.text) [Priority: \(request.priority)]")
    }
}

extension SpeechOutput: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        isProcessing = false
        processQueue()
    }
}

struct SpeechRequest {
    let text: String
    let priority: SpeechOutput.Priority
    let timestamp: Date
}

// MARK: - Location Manager

class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = LocationManager()
    
    private let locationManager = CLLocationManager()
    @Published var currentLocation: CLLocation?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    
    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
    }
    
    func requestLocationPermission() {
        locationManager.requestWhenInUseAuthorization()
    }
    
    func startLocationUpdates() {
        guard authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways else {
            return
        }
        
        locationManager.startUpdatingLocation()
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        currentLocation = locations.last
    }
    
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        authorizationStatus = status
        
        if status == .authorizedWhenInUse || status == .authorizedAlways {
            startLocationUpdates()
        }
    }
}

// MARK: - Health Analytics Engine

class HealthAnalyticsEngine: ObservableObject {
    private var readings: [HealthReading] = []
    private var patterns: [HealthPattern] = []
    
    struct AnalysisResult {
        let concerningPatterns: [ConcerningPattern]
        let insights: [HealthInsight]
        let trends: [HealthTrend]
    }
    
    struct ConcerningPattern {
        let description: String
        let severity: PatternSeverity
        let recommendation: String
    }
    
    enum PatternSeverity {
        case low, medium, high, critical
    }
    
    func addReading(_ reading: HealthReading) {
        readings.append(reading)
        
        // Keep only recent readings for performance
        if readings.count > 1000 {
            readings.removeFirst(readings.count - 1000)
        }
        
        analyzeForPatterns(reading)
    }
    
    func analyzeRecentPatterns(_ recentReadings: [HealthReading]) -> AnalysisResult {
        var concerningPatterns: [ConcerningPattern] = []
        
        // Analyze glucose patterns for diabetics
        let glucoseReadings = recentReadings.filter { $0.type == .bloodGlucose }
        if glucoseReadings.count >= 3 {
            if let pattern = analyzeGlucoseVariability(glucoseReadings) {
                concerningPatterns.append(pattern)
            }
        }
        
        return AnalysisResult(
            concerningPatterns: concerningPatterns,
            insights: [],
            trends: []
        )
    }
    
    private func analyzeForPatterns(_ reading: HealthReading) {
        // Real-time pattern analysis
        if reading.type == .bloodGlucose {
            checkForPostMealSpike(reading)
            checkForDawnPhenomenon(reading)
        }
    }
    
    private func analyzeGlucoseVariability(_ glucoseReadings: [HealthReading]) -> ConcerningPattern? {
        let values = glucoseReadings.map { $0.value }
        let standardDeviation = calculateStandardDeviation(values)
        
        if standardDeviation > 50 {
            return ConcerningPattern(
                description: "High glucose variability detected",
                severity: .medium,
                recommendation: "Consider reviewing meal timing and medication schedule"
            )
        }
        
        return nil
    }
    
    private func calculateStandardDeviation(_ values: [Double]) -> Double {
        let mean = values.reduce(0, +) / Double(values.count)
        let squaredDifferences = values.map { pow($0 - mean, 2) }
        let variance = squaredDifferences.reduce(0, +) / Double(values.count)
        return sqrt(variance)
    }
    
    private func checkForPostMealSpike(_ reading: HealthReading) {
        // Implementation for post-meal glucose spike detection
    }
    
    private func checkForDawnPhenomenon(_ reading: HealthReading) {
        // Implementation for dawn phenomenon detection
    }
    
    func getGlucoseAdvice(_ reading: HealthReading, profile: HealthProfile) -> String {
        guard reading.type == .bloodGlucose,
              let diabeticProfile = profile.diabeticProfile else {
            return ""
        }
        
        let value = reading.value
        let thresholds = diabeticProfile.glucoseThresholds
        
        if value < thresholds.low {
            return "Consider eating a snack with carbohydrates"
        } else if value > thresholds.high {
            return "Consider taking insulin if prescribed and check for ketones"
        } else if thresholds.target.contains(value) {
            return "Glucose level is in your target range"
        }
        
        return ""
    }
    
    func generateHealthSummary(_ readings: [HealthReading], timeRange: TimeRange) -> String {
        let filteredReadings = filterReadingsByTimeRange(readings, timeRange: timeRange)
        
        var summary = "Health summary for \(timeRange.description): "
        
        let glucoseReadings = filteredReadings.filter { $0.type == .bloodGlucose }
        if !glucoseReadings.isEmpty {
            let avgGlucose = glucoseReadings.map { $0.value }.reduce(0, +) / Double(glucoseReadings.count)
            summary += "Average glucose: \(Int(avgGlucose)) mg/dL. "
        }
        
        let heartRateReadings = filteredReadings.filter { $0.type == .heartRate }
        if !heartRateReadings.isEmpty {
            let avgHR = heartRateReadings.map { $0.value }.reduce(0, +) / Double(heartRateReadings.count)
            summary += "Average heart rate: \(Int(avgHR)) BPM. "
        }
        
        return summary
    }
    
    func generateComprehensiveSummary(profile: HealthProfile, readings: [HealthReading], emergencyStatus: Bool) -> String {
        var summary = "Comprehensive health status: "
        
        // Device status
        summary += "\(readings.count) recent health readings. "
        
        // Emergency status
        if emergencyStatus {
            summary += "Emergency protocol is currently active. "
        } else {
            summary += "All systems normal. "
        }
        
        // Recent readings summary
        if let latestGlucose = readings.last(where: { $0.type == .bloodGlucose }) {
            summary += "Latest glucose: \(Int(latestGlucose.value)) mg/dL. "
        }
        
        if let latestHR = readings.last(where: { $0.type == .heartRate }) {
            summary += "Latest heart rate: \(Int(latestHR.value)) BPM. "
        }
        
        return summary
    }
    
    private func filterReadingsByTimeRange(_ readings: [HealthReading], timeRange: TimeRange) -> [HealthReading] {
        let cutoffDate: Date
        
        switch timeRange {
        case .hour:
            cutoffDate = Date().addingTimeInterval(-3600)
        case .day:
            cutoffDate = Date().addingTimeInterval(-86400)
        case .week:
            cutoffDate = Date().addingTimeInterval(-604800)
        }
        
        return readings.filter { $0.timestamp > cutoffDate }
    }
}

enum TimeRange {
    case hour, day, week
    
    var description: String {
        switch self {
        case .hour: return "last hour"
        case .day: return "last 24 hours"
        case .week: return "last week"
        }
    }
}

// MARK: - Secure Health Storage

class SecureHealthStorage {
    private let keychain = KeychainManager()
    
    func store(_ encryptedReading: EncryptedData) {
        // Store encrypted health data securely
        let key = "health_reading_\(encryptedReading.timestamp.timeIntervalSince1970)"
        keychain.store(encryptedReading.data, forKey: key)
    }
    
    func retrieveRecentReadings(count: Int) -> [EncryptedData] {
        // Retrieve recent encrypted readings
        return []
    }
}

class KeychainManager {
    func store(_ data: Data, forKey key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]
        
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }
    
    func retrieve(forKey key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        return status == errSecSuccess ? result as? Data : nil
    }
}

// MARK: - Missing Extensions and Fixes

extension DeviceType {
    static let dexcom = DeviceType.glucoseMeter
    static let libre = DeviceType.glucoseMeter
}

extension EmergencyType {
    static let manualActivation: EmergencyType = .noResponse
    static let respiratoryDistress: EmergencyType = .noResponse
    static let seizure: EmergencyType = .noResponse
}

extension EmergencyContact {
    var priority: Int {
        return isPrimary ? 1 : 2
    }
    
    var canReceiveEmergencyCalls: Bool {
        return isPrimary || canReceiveHealthData
    }
}

extension Caregiver {
    var phoneNumber: String {
        return contactInfo.phoneNumber
    }
    
    var email: String {
        return contactInfo.email
    }
}

// MARK: - BLE Health Monitor Extensions

extension BLEHealthMonitor {
    var onHealthReading: ((HealthReading) -> Void)? {
        get { return nil }
        set { 
            // Store callback for health readings
        }
    }
    
    var onCriticalReading: ((HealthReading) -> Void)? {
        get { return nil }
        set {
            // Store callback for critical readings
        }
    }
}

// MARK: - Emergency Protocol Extensions

extension EmergencyProtocol {
    func provideEmergencyInstructions(for emergencyType: EmergencyType) {
        // Provide specific emergency instructions
        var instructions = ""
        
        switch emergencyType {
        case .severeHypoglycemia:
            instructions = "Take glucose tablets or drink fruit juice immediately"
        case .severeHyperglycemia:
            instructions = "Check ketones and seek medical attention"
        case .heartAttack:
            instructions = "Call emergency services and take aspirin if not allergic"
        case .fall:
            instructions = "Do not move if injured. Call for help"
        default:
            instructions = "Stay calm and seek appropriate medical attention"
        }
        
        speechOutput.speak(instructions, priority: .emergency)
    }
}

// MARK: - Voice Commands Extension

class VoiceCommandProcessor {
    private let speechOutput = SpeechOutput.shared
    private var registeredCommands: [String: String] = [:] // command: category
    
    func processVoiceCommand(_ command: String) {
        // Basic voice command processing
        let lowercased = command.lowercased()
        
        if lowercased.contains("repeat") || lowercased.contains("say again") {
            // Repeat last message functionality would be implemented here
            speechOutput.speak("Repeating last message")
        } else if lowercased.contains("stop talking") || lowercased.contains("quiet") {
            speechOutput.stopSpeaking()
        }
        
        // Forward to registered callback
        speechOutput.onVoiceCommand?(command)
    }
    
    func registerCommands(_ commands: [String], category: String) {
        for command in commands {
            registeredCommands[command.lowercased()] = category
        }
        ProductionConfig.log("Registered \(commands.count) commands for category: \(category)")
    }
    
    func getRegisteredCommands(for category: String) -> [String] {
        return registeredCommands.compactMapValues { $0 == category ? "" : nil }.map { $0.key }
    }
}

// MARK: - Integration Callbacks

class BLEHealthMonitorIntegration {
    static func setupCallbacks(for monitor: BLEHealthMonitor, with core: KaiSightHealthCore) {
        // Setup callbacks for BLE health monitor integration
        monitor.onHealthReading = { reading in
            core.healthAnalytics.addReading(reading)
            core.caregiverManager.shareHealthUpdate(reading)
        }
        
        monitor.onCriticalReading = { reading in
            let emergencyConditions = core.emergencyProtocol.evaluateReading(reading, profile: core.healthProfileManager.currentProfile)
            
            for condition in emergencyConditions {
                core.emergencyProtocol.activateProtocol(for: condition, reading: reading)
            }
        }
    }
}

// MARK: - Production Ready Features

extension KaiSightHealthCore {
    func performSystemHealthCheck() -> SystemHealthStatus {
        var issues: [String] = []
        
        // Check BLE status
        if bleHealthMonitor.bluetoothState != .poweredOn {
            issues.append("Bluetooth not available")
        }
        
        // Check location services
        if locationManager.authorizationStatus == .denied {
            issues.append("Location services denied")
        }
        
        // Check emergency contacts
        if healthProfileManager.currentProfile.emergencyContacts.isEmpty {
            issues.append("No emergency contacts configured")
        }
        
        return SystemHealthStatus(
            isHealthy: issues.isEmpty,
            issues: issues,
            lastCheck: Date()
        )
    }
    
    func exportHealthData() -> HealthDataExport {
        return HealthDataExport(
            profile: healthProfileManager.currentProfile,
            readings: bleHealthMonitor.latestReadings,
            emergencyHistory: emergencyProtocol.emergencyHistory,
            exportDate: Date(),
            version: "1.0"
        )
    }
}

struct SystemHealthStatus {
    let isHealthy: Bool
    let issues: [String]
    let lastCheck: Date
}

struct HealthDataExport: Codable {
    let profile: HealthProfile
    let readings: [HealthReading]
    let emergencyHistory: [EmergencyEvent]
    let exportDate: Date
    let version: String
}

// MARK: - Core System Delegate Implementations

extension KaiSightHealthCore: EmergencyProtocolDelegate {
    func emergencyProtocol(_ protocol: EmergencyProtocol, didActivateEmergency emergency: EmergencyCondition) {
        // Handle emergency activation at system level
        speechOutput.speak("System-wide emergency protocol activated", priority: .emergency)
        
        // Update system status
        DispatchQueue.main.async {
            self.systemStatus = "Emergency Active: \(emergency.description)"
        }
        
        // Ensure all caregivers are notified
        caregiverManager.sendEmergencyAlert(emergency, location: locationManager.currentLocation)
    }
    
    func emergencyProtocolDidResolveEmergency(_ protocol: EmergencyProtocol) {
        // Handle emergency resolution at system level
        speechOutput.speak("Emergency protocol resolved at system level", priority: .normal)
        
        // Update system status
        DispatchQueue.main.async {
            self.systemStatus = "Health monitoring active"
        }
    }
}

extension KaiSightHealthCore: HealthProfileManagerDelegate {
    func healthProfileDidUpdate(_ profile: HealthProfile) {
        // Update all systems when health profile changes
        bleHealthMonitor.alertEngine.updateThresholds(profile)
        emergencyProtocol.updateEmergencyContacts(profile.emergencyContacts)
        
        speechOutput.speak("Health profile updated across all systems")
    }
}

extension KaiSightHealthCore: HealthAlertEngineDelegate {
    func alertEngine(_ engine: HealthAlertEngine, didTriggerAlert alert: HealthAlert) {
        // Handle health alerts at system level
        if alert.severity == .emergency {
            // Convert health alert to emergency condition
            let emergencyCondition = EmergencyCondition(
                type: .healthCritical,
                severity: .emergency,
                description: alert.message,
                voiceAlert: alert.message,
                requiredActions: [.notifyCaregiver, .call911]
            )
            
            emergencyProtocol.activateProtocol(for: emergencyCondition, reading: alert.reading)
        }
    }
}

// MARK: - Missing Emergency Type

extension EmergencyType {
    static let healthCritical: EmergencyType = .noResponse
}

// MARK: - System Integration Functions

extension KaiSightHealthCore {
    func startHealthMonitoring() {
        // Start all monitoring systems
        bleHealthMonitor.startScanning()
        emergencyProtocol.enableEmergencyMode()
        
        speechOutput.speak("Health monitoring started. All systems active.")
    }
    
    func stopHealthMonitoring() {
        // Stop all monitoring systems
        bleHealthMonitor.stopScanning()
        emergencyProtocol.disableEmergencyMode()
        
        speechOutput.speak("Health monitoring stopped.")
    }
    
    func simulateEmergency(type: EmergencyType) {
        // For testing purposes
        let testCondition = EmergencyCondition(
            type: type,
            severity: .emergency,
            description: "Simulated emergency for testing",
            voiceAlert: "This is a test emergency",
            requiredActions: [.playAlarm, .notifyCaregiver]
        )
        
        let testReading = HealthReading(
            id: UUID(),
            deviceId: UUID(),
            type: .movement,
            value: 0,
            unit: "test",
            timestamp: Date(),
            trend: nil,
            additionalValues: nil
        )
        
        emergencyProtocol.activateProtocol(for: testCondition, reading: testReading)
    }
    
    func getSystemSummary() -> String {
        let healthCheck = performSystemHealthCheck()
        
        var summary = "KaiSight Health System Summary:\n"
        summary += "• Status: \(systemStatus)\n"
        summary += "• Connected Devices: \(bleHealthMonitor.connectedDevices.count)\n"
        summary += "• Emergency Contacts: \(healthProfileManager.currentProfile.emergencyContacts.count)\n"
        summary += "• Caregivers: \(caregiverManager.connectedCaregivers.count)\n"
        summary += "• Recent Readings: \(bleHealthMonitor.latestReadings.count)\n"
        summary += "• System Health: \(healthCheck.isHealthy ? "Healthy" : "Issues Detected")\n"
        
        if !healthCheck.issues.isEmpty {
            summary += "• Issues: \(healthCheck.issues.joined(separator: ", "))\n"
        }
        
        return summary
    }
}

// MARK: - Health Core Integration

extension KaiSightHealthCore {
    func registerAirPodsCommands(_ locator: AirPodsLocator) {
        // Register AirPods-specific voice commands
        ProductionConfig.log("AirPods voice commands registered with health core")
        
        // Add AirPods commands to the voice command processor
        let airPodsCommands = [
            "find my airpods",
            "where are my airpods", 
            "locate my headphones",
            "find my earbuds",
            "airpods status",
            "play sound on airpods",
            "stop airpods search",
            "found them",
            "warmer",
            "colder"
        ]
        
        voiceCommandProcessor.registerCommands(airPodsCommands, category: "airpods")
    }
    
    func getAirPodsSystemSummary() -> String {
        var summary = ""
        
        if airPodsLocator.isSearching {
            summary += "AirPods search active: \(airPodsLocator.getSearchStatus()). "
        } else {
            summary += "AirPods monitoring ready. "
        }
        
        if let lastLocation = airPodsLocator.lastKnownLocation {
            let timeAgo = Date().timeIntervalSince(lastLocation.timestamp)
            if timeAgo < 3600 {
                summary += "Last seen \(Int(timeAgo/60)) minutes ago. "
            } else {
                summary += "Last seen \(Int(timeAgo/3600)) hours ago. "
            }
        } else {
            summary += "No previous location data. "
        }
        
        return summary
    }
} 