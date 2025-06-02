import Foundation
import CoreBluetooth
import Combine
import HealthKit
import CryptoKit

class BLEHealthMonitor: NSObject, ObservableObject {
    @Published var isScanning = false
    @Published var connectedDevices: [HealthDevice] = []
    @Published var availableDevices: [HealthDevice] = []
    @Published var bluetoothState: CBManagerState = .unknown
    @Published var latestReadings: [HealthReading] = []
    @Published var emergencyAlert: EmergencyAlert?
    
    // Core Bluetooth
    private var centralManager: CBCentralManager!
    private var connectedPeripherals: [CBPeripheral] = []
    
    // Health Management
    private let healthProfile = HealthProfileManager.shared
    private let alertEngine = HealthAlertEngine()
    private let caregiverNotifications = CaregiverNotificationManager()
    private let healthAnalytics = HealthAnalyticsEngine()
    
    // Data Security
    private let healthEncryption = HealthDataEncryption()
    private let dataStorage = SecureHealthStorage()
    
    // Voice and Audio
    private let speechOutput = SpeechOutput.shared
    private let hapticFeedback = HapticFeedbackManager()
    
    // Background monitoring
    private var monitoringTimer: Timer?
    private let monitoringInterval: TimeInterval = 30.0 // 30 seconds
    
    // Emergency handling
    private var emergencyProtocol = EmergencyProtocol()
    private var lastEmergencyCheck = Date()
    
    // Callback support for integration
    var onHealthReading: ((HealthReading) -> Void)?
    var onCriticalReading: ((HealthReading) -> Void)?
    
    override init() {
        super.init()
        setupBLEHealthMonitor()
    }
    
    // MARK: - Setup and Configuration
    
    private func setupBLEHealthMonitor() {
        centralManager = CBCentralManager(delegate: self, queue: DispatchQueue.global(qos: .userInitiated))
        
        setupHealthProfile()
        setupAlertEngine()
        setupEmergencyProtocol()
        startBackgroundMonitoring()
        
        Config.debugLog("BLE Health Monitor initialized")
    }
    
    private func setupHealthProfile() {
        healthProfile.delegate = self
        healthProfile.loadUserHealthProfile()
    }
    
    private func setupAlertEngine() {
        alertEngine.delegate = self
        alertEngine.configure(speechOutput: speechOutput, hapticFeedback: hapticFeedback)
    }
    
    private func setupEmergencyProtocol() {
        emergencyProtocol.delegate = self
        emergencyProtocol.configure(
            caregiverManager: caregiverNotifications,
            location: LocationManager.shared
        )
    }
    
    // MARK: - Device Discovery and Connection
    
    func startScanning() {
        guard centralManager.state == .poweredOn else {
            speechOutput.speak("Bluetooth is not available")
            return
        }
        
        isScanning = true
        availableDevices.removeAll()
        
        // Scan for health devices with known service UUIDs
        let healthServiceUUIDs = HealthDeviceRegistry.getAllServiceUUIDs()
        
        centralManager.scanForPeripherals(
            withServices: healthServiceUUIDs,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
        
        speechOutput.speak("Scanning for health devices")
        
        // Stop scanning after 30 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 30.0) {
            self.stopScanning()
        }
    }
    
    func stopScanning() {
        guard isScanning else { return }
        
        centralManager.stopScan()
        isScanning = false
        
        let deviceCount = availableDevices.count
        speechOutput.speak("Scan complete. Found \(deviceCount) health device\(deviceCount == 1 ? "" : "s")")
    }
    
    func connectToDevice(_ device: HealthDevice) {
        guard let peripheral = device.peripheral else { return }
        
        centralManager.connect(peripheral, options: nil)
        speechOutput.speak("Connecting to \(device.name)")
    }
    
    func disconnectDevice(_ device: HealthDevice) {
        guard let peripheral = device.peripheral else { return }
        
        centralManager.cancelPeripheralConnection(peripheral)
        speechOutput.speak("Disconnecting \(device.name)")
    }
    
    // MARK: - Health Data Processing
    
    private func processHealthReading(_ reading: HealthReading) {
        // Encrypt and store reading
        do {
            let encryptedReading = try healthEncryption.encrypt(reading)
            dataStorage.store(encryptedReading)
        } catch {
            Config.debugLog("Failed to encrypt health reading: \(error)")
        }
        
        // Add to latest readings
        latestReadings.append(reading)
        
        // Keep only recent readings
        if latestReadings.count > 100 {
            latestReadings.removeFirst(latestReadings.count - 100)
        }
        
        // Call integration callbacks
        onHealthReading?(reading)
        
        if reading.isCritical {
            onCriticalReading?(reading)
        }
        
        // Process with alert engine
        alertEngine.processReading(reading)
        
        // Update health analytics
        healthAnalytics.addReading(reading)
        
        // Check for emergency conditions
        checkForEmergencyConditions(reading)
        
        // Announce critical readings
        if reading.isCritical {
            announceReading(reading)
        }
    }
    
    private func announceReading(_ reading: HealthReading) {
        var announcement = ""
        
        switch reading.type {
        case .bloodGlucose:
            announcement = "Blood glucose: \(Int(reading.value)) \(reading.unit)"
            if reading.isCritical {
                announcement += " - Critical level detected"
            }
            
        case .heartRate:
            announcement = "Heart rate: \(Int(reading.value)) BPM"
            
        case .bloodPressure:
            if let systolic = reading.additionalValues?["systolic"],
               let diastolic = reading.additionalValues?["diastolic"] {
                announcement = "Blood pressure: \(Int(systolic)) over \(Int(diastolic))"
            }
            
        case .temperature:
            announcement = "Body temperature: \(String(format: "%.1f", reading.value)) degrees"
            
        case .oxygenSaturation:
            announcement = "Oxygen saturation: \(Int(reading.value)) percent"
            
        case .movement:
            if reading.isCritical {
                announcement = "Fall detected"
            }
        }
        
        if !announcement.isEmpty {
            speechOutput.speak(announcement, priority: reading.isCritical ? .high : .normal)
        }
    }
    
    // MARK: - Emergency Detection and Response
    
    private func checkForEmergencyConditions(_ reading: HealthReading) {
        let emergencyConditions = emergencyProtocol.evaluateReading(reading, profile: healthProfile.currentProfile)
        
        for condition in emergencyConditions {
            handleEmergencyCondition(condition, reading: reading)
        }
    }
    
    private func handleEmergencyCondition(_ condition: EmergencyCondition, reading: HealthReading) {
        let alert = EmergencyAlert(
            id: UUID(),
            condition: condition,
            reading: reading,
            timestamp: Date(),
            severity: condition.severity,
            location: LocationManager.shared.currentLocation
        )
        
        DispatchQueue.main.async {
            self.emergencyAlert = alert
        }
        
        // Immediate voice alert
        speechOutput.speak(condition.voiceAlert, priority: .emergency)
        
        // Haptic feedback
        hapticFeedback.provideEmergencyAlert()
        
        // Start emergency protocol
        emergencyProtocol.activateProtocol(for: condition, reading: reading)
    }
    
    // MARK: - Background Health Monitoring
    
    private func startBackgroundMonitoring() {
        monitoringTimer = Timer.scheduledTimer(withTimeInterval: monitoringInterval, repeats: true) { _ in
            self.performBackgroundHealthCheck()
        }
    }
    
    private func performBackgroundHealthCheck() {
        // Check device connections
        checkDeviceConnections()
        
        // Analyze recent readings for patterns
        analyzeHealthPatterns()
        
        // Check for missed readings
        checkForMissedReadings()
        
        // Perform emergency wellness check
        performEmergencyWellnessCheck()
    }
    
    private func checkDeviceConnections() {
        for device in connectedDevices {
            if let peripheral = device.peripheral,
               peripheral.state != .connected {
                
                // Attempt reconnection
                centralManager.connect(peripheral, options: nil)
                Config.debugLog("Attempting to reconnect to \(device.name)")
            }
        }
    }
    
    private func analyzeHealthPatterns() {
        let analysis = healthAnalytics.analyzeRecentPatterns(latestReadings)
        
        if let concerningPattern = analysis.concerningPatterns.first {
            speechOutput.speak("Health pattern alert: \(concerningPattern.description)", priority: .normal)
        }
    }
    
    private func checkForMissedReadings() {
        let criticalDevices = connectedDevices.filter { $0.isCriticalForMonitoring }
        
        for device in criticalDevices {
            let timeSinceLastReading = Date().timeIntervalSince(device.lastReadingTime ?? Date.distantPast)
            
            if timeSinceLastReading > device.maxReadingInterval {
                speechOutput.speak("Warning: No recent data from \(device.name)", priority: .normal)
            }
        }
    }
    
    private func performEmergencyWellnessCheck() {
        // If no movement detected for extended period during awake hours
        let timeSinceLastMovement = Date().timeIntervalSince(lastMovementDetection())
        
        if timeSinceLastMovement > 3600 && isAwakeHours() { // 1 hour of no movement
            emergencyProtocol.performWellnessCheck()
        }
    }
    
    private func lastMovementDetection() -> Date {
        return latestReadings
            .filter { $0.type == .movement }
            .max(by: { $0.timestamp < $1.timestamp })?.timestamp ?? Date.distantPast
    }
    
    private func isAwakeHours() -> Bool {
        let hour = Calendar.current.component(.hour, from: Date())
        return hour >= 6 && hour <= 22 // 6 AM to 10 PM
    }
    
    // MARK: - Diabetic-Specific Features
    
    func setupDiabeticMonitoring(cgmType: CGMType, thresholds: GlucoseThresholds) {
        healthProfile.updateGlucoseThresholds(thresholds)
        
        // Configure device-specific settings
        switch cgmType {
        case .dexcomG6, .dexcomG7:
            configureDexcomMonitoring()
        case .libre2, .libre3:
            configureLibreMonitoring()
        case .medtronic:
            configureMedtronicMonitoring()
        }
        
        speechOutput.speak("Diabetic monitoring configured for \(cgmType.description)")
    }
    
    private func configureDexcomMonitoring() {
        // Dexcom-specific BLE configuration
        let dexcomServiceUUID = CBUUID(string: "F8083532-849E-531C-C594-30F1F86A4EA5")
        
        startScanningForService(dexcomServiceUUID, deviceType: .dexcom)
    }
    
    private func configureLibreMonitoring() {
        // Libre-specific configuration (may require bridge device)
        let libreServiceUUID = CBUUID(string: "FFC0")
        
        startScanningForService(libreServiceUUID, deviceType: .libre)
    }
    
    private func configureMedtronicMonitoring() {
        // Medtronic-specific configuration
        let medtronicServiceUUID = CBUUID(string: "00002A18-0000-1000-8000-00805F9B34FB")
        
        startScanningForService(medtronicServiceUUID, deviceType: .medtronic)
    }
    
    private func startScanningForService(_ serviceUUID: CBUUID, deviceType: DeviceType) {
        centralManager.scanForPeripherals(
            withServices: [serviceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
    }
    
    // MARK: - Voice Commands and Interaction
    
    func processVoiceCommand(_ command: String) {
        let lowercased = command.lowercased()
        
        if lowercased.contains("glucose") || lowercased.contains("blood sugar") {
            reportLatestGlucoseReading()
        } else if lowercased.contains("heart rate") || lowercased.contains("pulse") {
            reportLatestHeartRate()
        } else if lowercased.contains("blood pressure") {
            reportLatestBloodPressure()
        } else if lowercased.contains("health status") || lowercased.contains("how am i") {
            reportOverallHealthStatus()
        } else if lowercased.contains("emergency contact") {
            activateEmergencyContact()
        } else if lowercased.contains("scan") || lowercased.contains("find devices") {
            startScanning()
        } else if lowercased.contains("connect") {
            connectToAvailableDevices()
        } else if lowercased.contains("health history") {
            reportRecentHealthHistory()
        }
    }
    
    private func reportLatestGlucoseReading() {
        if let latestGlucose = latestReadings.last(where: { $0.type == .bloodGlucose }) {
            let value = Int(latestGlucose.value)
            let timeAgo = timeAgoDescription(latestGlucose.timestamp)
            
            var report = "Your blood glucose is \(value) \(latestGlucose.unit)"
            report += ", measured \(timeAgo)"
            
            // Add trend information if available
            if let trend = latestGlucose.trend {
                report += ". Trend: \(trend.description)"
            }
            
            // Add contextual advice
            let advice = healthAnalytics.getGlucoseAdvice(latestGlucose, profile: healthProfile.currentProfile)
            if !advice.isEmpty {
                report += ". \(advice)"
            }
            
            speechOutput.speak(report)
        } else {
            speechOutput.speak("No recent glucose readings available")
        }
    }
    
    private func reportLatestHeartRate() {
        if let latestHR = latestReadings.last(where: { $0.type == .heartRate }) {
            let bpm = Int(latestHR.value)
            let timeAgo = timeAgoDescription(latestHR.timestamp)
            
            var report = "Your heart rate is \(bpm) beats per minute, measured \(timeAgo)"
            
            // Add context based on normal ranges
            let normalRange = healthProfile.currentProfile.normalHeartRateRange
            if bpm < normalRange.lowerBound {
                report += ". This is below your normal range"
            } else if bpm > normalRange.upperBound {
                report += ". This is above your normal range"
            } else {
                report += ". This is within your normal range"
            }
            
            speechOutput.speak(report)
        } else {
            speechOutput.speak("No recent heart rate readings available")
        }
    }
    
    private func reportLatestBloodPressure() {
        if let latestBP = latestReadings.last(where: { $0.type == .bloodPressure }) {
            if let systolic = latestBP.additionalValues?["systolic"],
               let diastolic = latestBP.additionalValues?["diastolic"] {
                
                let timeAgo = timeAgoDescription(latestBP.timestamp)
                let report = "Your blood pressure is \(Int(systolic)) over \(Int(diastolic)), measured \(timeAgo)"
                
                speechOutput.speak(report)
            }
        } else {
            speechOutput.speak("No recent blood pressure readings available")
        }
    }
    
    private func reportOverallHealthStatus() {
        var statusReport = "Health status: "
        
        // Check each vital sign
        let vitalSigns = ["glucose", "heart rate", "blood pressure"]
        var normalCount = 0
        var concernCount = 0
        
        for vital in vitalSigns {
            if let status = getVitalSignStatus(vital) {
                if status == "normal" {
                    normalCount += 1
                } else {
                    concernCount += 1
                }
            }
        }
        
        if concernCount == 0 {
            statusReport += "All vital signs are normal"
        } else {
            statusReport += "\(normalCount) vital signs normal, \(concernCount) require attention"
        }
        
        // Add device connection status
        let connectedCount = connectedDevices.count
        statusReport += ". \(connectedCount) health device\(connectedCount == 1 ? "" : "s") connected"
        
        speechOutput.speak(statusReport)
    }
    
    private func activateEmergencyContact() {
        emergencyProtocol.activateManualEmergency()
        speechOutput.speak("Activating emergency contact protocol")
    }
    
    private func connectToAvailableDevices() {
        if availableDevices.isEmpty {
            speechOutput.speak("No devices found. Starting scan")
            startScanning()
        } else {
            for device in availableDevices {
                connectToDevice(device)
            }
        }
    }
    
    private func reportRecentHealthHistory() {
        let history = healthAnalytics.generateHealthSummary(latestReadings, timeRange: .day)
        speechOutput.speak(history)
    }
    
    // MARK: - Utility Methods
    
    private func timeAgoDescription(_ timestamp: Date) -> String {
        let timeInterval = Date().timeIntervalSince(timestamp)
        
        if timeInterval < 60 {
            return "just now"
        } else if timeInterval < 3600 {
            let minutes = Int(timeInterval / 60)
            return "\(minutes) minute\(minutes == 1 ? "" : "s") ago"
        } else {
            let hours = Int(timeInterval / 3600)
            return "\(hours) hour\(hours == 1 ? "" : "s") ago"
        }
    }
    
    private func getVitalSignStatus(_ vitalSign: String) -> String? {
        // Implementation would check latest readings against normal ranges
        return "normal"
    }
    
    // MARK: - Public Interface
    
    func enableEmergencyMode() {
        emergencyProtocol.enableEmergencyMode()
        speechOutput.speak("Emergency mode activated. All caregivers will be notified of critical alerts")
    }
    
    func disableEmergencyMode() {
        emergencyProtocol.disableEmergencyMode()
        speechOutput.speak("Emergency mode disabled")
    }
    
    func getHealthSummary() -> HealthSummary {
        return HealthSummary(
            connectedDevices: connectedDevices.count,
            latestReadings: latestReadings,
            emergencyStatus: emergencyProtocol.isActive,
            healthProfile: healthProfile.currentProfile
        )
    }
    
    func speakHealthSummary() {
        let summary = getHealthSummary()
        let report = generateHealthSummaryReport(summary)
        speechOutput.speak(report)
    }
    
    private func generateHealthSummaryReport(_ summary: HealthSummary) -> String {
        var report = "Health monitoring summary: "
        report += "\(summary.connectedDevices) device\(summary.connectedDevices == 1 ? "" : "s") connected. "
        
        if summary.latestReadings.isEmpty {
            report += "No recent readings"
        } else {
            let readingCount = summary.latestReadings.count
            report += "\(readingCount) recent reading\(readingCount == 1 ? "" : "s")"
        }
        
        if summary.emergencyStatus {
            report += ". Emergency monitoring active"
        }
        
        return report
    }
}

// MARK: - CBCentralManagerDelegate

extension BLEHealthMonitor: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        DispatchQueue.main.async {
            self.bluetoothState = central.state
        }
        
        switch central.state {
        case .poweredOn:
            Config.debugLog("Bluetooth powered on - ready for health device scanning")
            
        case .poweredOff:
            speechOutput.speak("Bluetooth is off. Please enable Bluetooth for health monitoring")
            
        case .unauthorized:
            speechOutput.speak("Bluetooth access denied. Please allow Bluetooth in settings")
            
        case .unsupported:
            speechOutput.speak("Bluetooth Low Energy not supported on this device")
            
        default:
            Config.debugLog("Bluetooth state: \(central.state.rawValue)")
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        
        // Create health device from discovered peripheral
        if let device = HealthDeviceFactory.createDevice(from: peripheral, advertisementData: advertisementData, rssi: RSSI) {
            
            DispatchQueue.main.async {
                // Add to available devices if not already present
                if !self.availableDevices.contains(where: { $0.id == device.id }) {
                    self.availableDevices.append(device)
                    
                    Config.debugLog("Discovered health device: \(device.name)")
                    
                    // Auto-connect to known devices
                    if self.healthProfile.shouldAutoConnect(device) {
                        self.connectToDevice(device)
                    }
                }
            }
        }
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Config.debugLog("Connected to peripheral: \(peripheral.name ?? "Unknown")")
        
        // Set delegate and discover services
        peripheral.delegate = self
        peripheral.discoverServices(nil)
        
        // Update device status
        if let device = availableDevices.first(where: { $0.peripheral?.identifier == peripheral.identifier }) {
            DispatchQueue.main.async {
                device.connectionState = .connected
                
                if !self.connectedDevices.contains(where: { $0.id == device.id }) {
                    self.connectedDevices.append(device)
                }
                
                self.speechOutput.speak("\(device.name) connected")
            }
        }
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        Config.debugLog("Failed to connect to peripheral: \(error?.localizedDescription ?? "Unknown error")")
        
        if let device = availableDevices.first(where: { $0.peripheral?.identifier == peripheral.identifier }) {
            DispatchQueue.main.async {
                device.connectionState = .disconnected
                self.speechOutput.speak("Failed to connect to \(device.name)")
            }
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        Config.debugLog("Disconnected from peripheral: \(peripheral.name ?? "Unknown")")
        
        if let device = connectedDevices.first(where: { $0.peripheral?.identifier == peripheral.identifier }) {
            DispatchQueue.main.async {
                device.connectionState = .disconnected
                self.connectedDevices.removeAll { $0.id == device.id }
                
                if let error = error {
                    self.speechOutput.speak("\(device.name) disconnected unexpectedly")
                } else {
                    self.speechOutput.speak("\(device.name) disconnected")
                }
            }
        }
    }
}

// MARK: - CBPeripheralDelegate

extension BLEHealthMonitor: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        
        for service in services {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else { return }
        
        for characteristic in characteristics {
            // Subscribe to notifications for health data
            if characteristic.properties.contains(.notify) {
                peripheral.setNotifyValue(true, for: characteristic)
            }
            
            // Read initial values
            if characteristic.properties.contains(.read) {
                peripheral.readValue(for: characteristic)
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value else { return }
        
        // Parse health data based on characteristic UUID
        if let reading = HealthDataParser.parseCharacteristicData(data, characteristic: characteristic, peripheral: peripheral) {
            
            DispatchQueue.main.async {
                self.processHealthReading(reading)
            }
        }
    }
}

// MARK: - Delegate Protocols

extension BLEHealthMonitor: HealthProfileManagerDelegate {
    func healthProfileDidUpdate(_ profile: HealthProfile) {
        // Update alert thresholds
        alertEngine.updateThresholds(profile)
        speechOutput.speak("Health profile updated")
    }
}

extension BLEHealthMonitor: HealthAlertEngineDelegate {
    func alertEngine(_ engine: HealthAlertEngine, didTriggerAlert alert: HealthAlert) {
        // Handle health alerts
        switch alert.severity {
        case .info:
            speechOutput.speak(alert.message, priority: .low)
            
        case .warning:
            speechOutput.speak(alert.message, priority: .normal)
            hapticFeedback.provideWarningFeedback()
            
        case .critical:
            speechOutput.speak(alert.message, priority: .high)
            hapticFeedback.provideCriticalAlert()
            
        case .emergency:
            speechOutput.speak(alert.message, priority: .emergency)
            hapticFeedback.provideEmergencyAlert()
            
            // Activate emergency protocol
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

extension BLEHealthMonitor: EmergencyProtocolDelegate {
    func emergencyProtocol(_ protocol: EmergencyProtocol, didActivateEmergency emergency: EmergencyCondition) {
        // Handle emergency activation
        caregiverNotifications.sendEmergencyAlert(emergency)
        
        if emergency.requiredActions.contains(.call911) {
            // Would integrate with emergency services in production
            speechOutput.speak("Emergency services have been notified", priority: .emergency)
        }
    }
    
    func emergencyProtocolDidResolveEmergency(_ protocol: EmergencyProtocol) {
        DispatchQueue.main.async {
            self.emergencyAlert = nil
        }
        
        speechOutput.speak("Emergency condition resolved")
    }
}

// MARK: - Data Models and Supporting Types

struct HealthDevice: Identifiable {
    let id: UUID
    let name: String
    let type: DeviceType
    let manufacturer: String
    var peripheral: CBPeripheral?
    var connectionState: ConnectionState = .disconnected
    var lastReadingTime: Date?
    var batteryLevel: Int?
    var signalStrength: Int
    
    var isCriticalForMonitoring: Bool {
        return type == .glucoseMeter || type == .heartRateMonitor
    }
    
    var maxReadingInterval: TimeInterval {
        switch type {
        case .glucoseMeter:
            return 300 // 5 minutes for CGM
        case .heartRateMonitor:
            return 60 // 1 minute for heart rate
        default:
            return 600 // 10 minutes for others
        }
    }
}

enum DeviceType: String, CaseIterable {
    case glucoseMeter = "glucose_meter"
    case heartRateMonitor = "heart_rate"
    case bloodPressureMonitor = "blood_pressure"
    case thermometer = "thermometer"
    case pulseOximeter = "pulse_oximeter"
    case weightScale = "weight_scale"
    case activityTracker = "activity_tracker"
    
    var description: String {
        switch self {
        case .glucoseMeter: return "Glucose Meter"
        case .heartRateMonitor: return "Heart Rate Monitor"
        case .bloodPressureMonitor: return "Blood Pressure Monitor"
        case .thermometer: return "Thermometer"
        case .pulseOximeter: return "Pulse Oximeter"
        case .weightScale: return "Weight Scale"
        case .activityTracker: return "Activity Tracker"
        }
    }
}

enum ConnectionState {
    case disconnected
    case connecting
    case connected
    case failed
}

struct HealthReading: Identifiable {
    let id: UUID
    let deviceId: UUID
    let type: ReadingType
    let value: Double
    let unit: String
    let timestamp: Date
    let trend: Trend?
    let additionalValues: [String: Double]?
    
    var isCritical: Bool {
        switch type {
        case .bloodGlucose:
            return value < 70 || value > 250 // mg/dL
        case .heartRate:
            return value < 50 || value > 120
        case .oxygenSaturation:
            return value < 90
        default:
            return false
        }
    }
}

enum ReadingType: String, CaseIterable {
    case bloodGlucose = "blood_glucose"
    case heartRate = "heart_rate"
    case bloodPressure = "blood_pressure"
    case temperature = "temperature"
    case oxygenSaturation = "oxygen_saturation"
    case weight = "weight"
    case movement = "movement"
    case sleep = "sleep"
}

enum Trend: String {
    case rapidlyRising = "rapidly_rising"
    case rising = "rising"
    case stable = "stable"
    case falling = "falling"
    case rapidlyFalling = "rapidly_falling"
    
    var description: String {
        switch self {
        case .rapidlyRising: return "rapidly rising"
        case .rising: return "rising"
        case .stable: return "stable"
        case .falling: return "falling"
        case .rapidlyFalling: return "rapidly falling"
        }
    }
}

enum CGMType: String, CaseIterable {
    case dexcomG6 = "dexcom_g6"
    case dexcomG7 = "dexcom_g7"
    case libre2 = "libre_2"
    case libre3 = "libre_3"
    case medtronic = "medtronic"
    
    var description: String {
        switch self {
        case .dexcomG6: return "Dexcom G6"
        case .dexcomG7: return "Dexcom G7"
        case .libre2: return "FreeStyle Libre 2"
        case .libre3: return "FreeStyle Libre 3"
        case .medtronic: return "Medtronic CGM"
        }
    }
}

struct GlucoseThresholds {
    let low: Double
    let veryLow: Double
    let high: Double
    let veryHigh: Double
    let target: Range<Double>
    
    static let standard = GlucoseThresholds(
        low: 80,
        veryLow: 60,
        high: 180,
        veryHigh: 250,
        target: 80..<140
    )
}

struct EmergencyAlert: Identifiable {
    let id: UUID
    let condition: EmergencyCondition
    let reading: HealthReading
    let timestamp: Date
    let severity: EmergencySeverity
    let location: CLLocation?
}

struct EmergencyCondition {
    let type: EmergencyType
    let severity: EmergencySeverity
    let description: String
    let voiceAlert: String
    let requiredActions: [EmergencyAction]
}

enum EmergencyType {
    case severeHypoglycemia
    case severeHyperglycemia
    case heartAttack
    case fall
    case noResponse
    case healthCritical
}

enum EmergencySeverity {
    case warning
    case critical
    case emergency
}

enum EmergencyAction {
    case notifyCaregiver
    case call911
    case playAlarm
    case provideInstructions
}

struct HealthSummary {
    let connectedDevices: Int
    let latestReadings: [HealthReading]
    let emergencyStatus: Bool
    let healthProfile: HealthProfile
}

// MARK: - Supporting Classes (Stubs for now)

class HealthDeviceRegistry {
    static func getAllServiceUUIDs() -> [CBUUID] {
        return [
            // Standard health service UUIDs
            CBUUID(string: "180D"), // Heart Rate Service
            CBUUID(string: "1808"), // Glucose Service
            CBUUID(string: "1810"), // Blood Pressure Service
            CBUUID(string: "1809"), // Health Thermometer Service
            
            // Vendor-specific UUIDs
            CBUUID(string: "F8083532-849E-531C-C594-30F1F86A4EA5"), // Dexcom
            CBUUID(string: "FFC0"), // Libre
        ]
    }
}

class HealthDeviceFactory {
    static func createDevice(from peripheral: CBPeripheral, advertisementData: [String: Any], rssi: NSNumber) -> HealthDevice? {
        
        let name = peripheral.name ?? "Unknown Device"
        let deviceType = inferDeviceType(from: peripheral, advertisementData: advertisementData)
        let manufacturer = extractManufacturer(from: advertisementData)
        
        return HealthDevice(
            id: peripheral.identifier,
            name: name,
            type: deviceType,
            manufacturer: manufacturer,
            peripheral: peripheral,
            signalStrength: rssi.intValue
        )
    }
    
    private static func inferDeviceType(from peripheral: CBPeripheral, advertisementData: [String: Any]) -> DeviceType {
        let name = (peripheral.name ?? "").lowercased()
        
        if name.contains("dexcom") || name.contains("glucose") {
            return .glucoseMeter
        } else if name.contains("heart") || name.contains("hr") {
            return .heartRateMonitor
        } else if name.contains("blood pressure") || name.contains("bp") {
            return .bloodPressureMonitor
        } else {
            return .activityTracker
        }
    }
    
    private static func extractManufacturer(from advertisementData: [String: Any]) -> String {
        if let manufacturerData = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data {
            // Parse manufacturer data to determine vendor
            return "Unknown"
        }
        return "Unknown"
    }
}

class HealthDataParser {
    static func parseCharacteristicData(_ data: Data, characteristic: CBCharacteristic, peripheral: CBPeripheral) -> HealthReading? {
        
        // Parse based on characteristic UUID
        switch characteristic.uuid.uuidString {
        case "2A37": // Heart Rate Measurement
            return parseHeartRateData(data, deviceId: peripheral.identifier)
            
        case "2A18": // Glucose Measurement
            return parseGlucoseData(data, deviceId: peripheral.identifier)
            
        case "2A35": // Blood Pressure Measurement
            return parseBloodPressureData(data, deviceId: peripheral.identifier)
            
        default:
            return nil
        }
    }
    
    private static func parseHeartRateData(_ data: Data, deviceId: UUID) -> HealthReading? {
        guard data.count >= 2 else { return nil }
        
        let flags = data[0]
        let heartRate: UInt16
        
        if flags & 0x01 == 0 {
            // 8-bit heart rate
            heartRate = UInt16(data[1])
        } else {
            // 16-bit heart rate
            heartRate = UInt16(data[1]) | (UInt16(data[2]) << 8)
        }
        
        return HealthReading(
            id: UUID(),
            deviceId: deviceId,
            type: .heartRate,
            value: Double(heartRate),
            unit: "BPM",
            timestamp: Date(),
            trend: nil,
            additionalValues: nil
        )
    }
    
    private static func parseGlucoseData(_ data: Data, deviceId: UUID) -> HealthReading? {
        // Simplified glucose parsing - actual implementation would be device-specific
        guard data.count >= 6 else { return nil }
        
        let glucose = UInt16(data[4]) | (UInt16(data[5]) << 8)
        
        return HealthReading(
            id: UUID(),
            deviceId: deviceId,
            type: .bloodGlucose,
            value: Double(glucose),
            unit: "mg/dL",
            timestamp: Date(),
            trend: nil,
            additionalValues: nil
        )
    }
    
    private static func parseBloodPressureData(_ data: Data, deviceId: UUID) -> HealthReading? {
        guard data.count >= 7 else { return nil }
        
        let systolic = UInt16(data[1]) | (UInt16(data[2]) << 8)
        let diastolic = UInt16(data[3]) | (UInt16(data[4]) << 8)
        
        return HealthReading(
            id: UUID(),
            deviceId: deviceId,
            type: .bloodPressure,
            value: Double(systolic),
            unit: "mmHg",
            timestamp: Date(),
            trend: nil,
            additionalValues: [
                "systolic": Double(systolic),
                "diastolic": Double(diastolic)
            ]
        )
    }
} 