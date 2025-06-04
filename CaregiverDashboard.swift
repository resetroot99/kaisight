import Foundation
import SwiftUI
import Combine
import CoreLocation
import HealthKit
import UserNotifications

class CaregiverDashboard: ObservableObject {
    @Published var clients: [CareRecipient] = []
    @Published var emergencyAlerts: [EmergencyAlert] = []
    @Published var activeMonitoring: [UUID: MonitoringSession] = [:]
    @Published var locationHistory: [LocationEvent] = []
    @Published var healthData: [HealthDataPoint] = []
    @Published var videoSessions: [VideoSession] = []
    @Published var scheduledCheckIns: [ScheduledCheckIn] = []
    @Published var isOnDuty = false
    @Published var connectionStatus: ConnectionStatus = .disconnected
    
    private let cloudSync = CloudSyncManager()
    private let speechOutput = SpeechOutput()
    private let healthStore = HKHealthStore()
    private let notificationCenter = UNUserNotificationCenter.current()
    
    // Video assistance (native iOS video calling functionality)
    private var videoClient: VideoClient?
    private var signaling: SignalingClient?
    
    // Real-time monitoring
    private var monitoringTimer: Timer?
    private var emergencyResponseSystem: EmergencyResponseSystem?
    private var healthMonitor: HealthMonitor?
    
    // Enterprise features
    private var caregiverProfile: CaregiverProfile?
    private var organizationSettings: OrganizationSettings?
    
    init() {
        setupCaregiverDashboard()
        setupHealthKitIntegration()
        setupNotifications()
        setupVideoClient()
    }
    
    deinit {
        stopAllMonitoring()
    }
    
    // MARK: - Setup and Configuration
    
    private func setupCaregiverDashboard() {
        loadCaregiverProfile()
        loadClients()
        setupEmergencyResponse()
        
        Config.debugLog("Caregiver dashboard initialized")
    }
    
    private func loadCaregiverProfile() {
        // Load caregiver profile from local storage or server
        if let profileData = UserDefaults.standard.data(forKey: "CaregiverProfile"),
           let profile = try? JSONDecoder().decode(CaregiverProfile.self, from: profileData) {
            caregiverProfile = profile
        } else {
            createDefaultCaregiverProfile()
        }
    }
    
    private func createDefaultCaregiverProfile() {
        caregiverProfile = CaregiverProfile(
            id: UUID(),
            name: "Healthcare Provider",
            role: .nurse,
            certification: .registered,
            organization: "KaiSight Care",
            contactInfo: ContactInfo(phone: "", email: ""),
            accessLevel: .standard,
            joinDate: Date()
        )
        
        saveCaregiverProfile()
    }
    
    private func saveCaregiverProfile() {
        guard let profile = caregiverProfile,
              let profileData = try? JSONEncoder().encode(profile) else { return }
        
        UserDefaults.standard.set(profileData, forKey: "CaregiverProfile")
    }
    
    private func loadClients() {
        cloudSync.getCareRecipients { [weak self] recipients in
            DispatchQueue.main.async {
                self?.clients = recipients
                self?.startMonitoringActiveClients()
            }
        }
    }
    
    private func setupEmergencyResponse() {
        emergencyResponseSystem = EmergencyResponseSystem()
        emergencyResponseSystem?.delegate = self
    }
    
    // MARK: - Health Kit Integration
    
    private func setupHealthKitIntegration() {
        guard HKHealthStore.isHealthDataAvailable() else {
            Config.debugLog("HealthKit not available")
            return
        }
        
        let typesToRead: Set<HKObjectType> = [
            HKObjectType.quantityType(forIdentifier: .heartRate)!,
            HKObjectType.quantityType(forIdentifier: .stepCount)!,
            HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)!,
            HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!
        ]
        
        healthStore.requestAuthorization(toShare: nil, read: typesToRead) { [weak self] success, error in
            if success {
                self?.setupHealthMonitoring()
            } else {
                Config.debugLog("HealthKit authorization failed: \(error?.localizedDescription ?? "Unknown error")")
            }
        }
    }
    
    private func setupHealthMonitoring() {
        healthMonitor = HealthMonitor(healthStore: healthStore)
        healthMonitor?.delegate = self
        
        // Start monitoring for all clients
        for client in clients {
            if client.settings.healthMonitoring {
                startHealthMonitoring(for: client)
            }
        }
    }
    
    // MARK: - Video Assistance
    
    private func setupVideoClient() {
        videoClient = VideoClient()
        signaling = SignalingClient()
        
        videoClient?.delegate = self
        signaling?.delegate = self
        
        Config.debugLog("Video assistance configured")
    }
    
    // MARK: - Notifications
    
    private func setupNotifications() {
        notificationCenter.requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            if granted {
                Config.debugLog("Notification permission granted")
            } else {
                Config.debugLog("Notification permission denied")
            }
        }
    }
    
    // MARK: - Client Management
    
    func addClient(_ client: CareRecipient) {
        clients.append(client)
        
        // Save to cloud
        cloudSync.addCareRecipient(client) { [weak self] success in
            if success {
                self?.speechOutput.speak("Client \(client.name) added to your care list")
                self?.startMonitoring(client: client)
            }
        }
    }
    
    func removeClient(_ clientID: UUID) {
        stopMonitoring(clientID: clientID)
        clients.removeAll { $0.id == clientID }
        
        cloudSync.removeCareRecipient(clientID) { success in
            // Handle removal result
        }
    }
    
    func updateClientSettings(_ clientID: UUID, settings: CareSettings) {
        if let index = clients.firstIndex(where: { $0.id == clientID }) {
            clients[index].settings = settings
            
            // Update monitoring based on new settings
            if settings.locationTracking {
                startLocationMonitoring(for: clients[index])
            } else {
                stopLocationMonitoring(for: clientID)
            }
            
            if settings.healthMonitoring {
                startHealthMonitoring(for: clients[index])
            } else {
                stopHealthMonitoring(for: clientID)
            }
        }
    }
    
    // MARK: - Real-Time Monitoring
    
    private func startMonitoringActiveClients() {
        for client in clients {
            if client.settings.active {
                startMonitoring(client: client)
            }
        }
    }
    
    func startMonitoring(client: CareRecipient) {
        let session = MonitoringSession(
            clientID: client.id,
            startTime: Date(),
            monitoringTypes: client.settings.getMonitoringTypes(),
            status: .active
        )
        
        activeMonitoring[client.id] = session
        
        // Start specific monitoring types
        if client.settings.locationTracking {
            startLocationMonitoring(for: client)
        }
        
        if client.settings.healthMonitoring {
            startHealthMonitoring(for: client)
        }
        
        if client.settings.activityMonitoring {
            startActivityMonitoring(for: client)
        }
        
        if client.settings.emergencyResponse {
            enableEmergencyResponse(for: client)
        }
        
        Config.debugLog("Started monitoring for client: \(client.name)")
    }
    
    func stopMonitoring(clientID: UUID) {
        guard let session = activeMonitoring[clientID] else { return }
        
        // Stop all monitoring for this client
        stopLocationMonitoring(for: clientID)
        stopHealthMonitoring(for: clientID)
        stopActivityMonitoring(for: clientID)
        
        // Update session
        var updatedSession = session
        updatedSession.status = .stopped
        updatedSession.endTime = Date()
        
        activeMonitoring.removeValue(forKey: clientID)
        
        Config.debugLog("Stopped monitoring for client: \(clientID)")
    }
    
    func stopAllMonitoring() {
        for clientID in activeMonitoring.keys {
            stopMonitoring(clientID: clientID)
        }
        
        monitoringTimer?.invalidate()
        monitoringTimer = nil
    }
    
    // MARK: - Location Monitoring
    
    private func startLocationMonitoring(for client: CareRecipient) {
        // Subscribe to client's location updates
        cloudSync.subscribeToLocationUpdates(clientID: client.id) { [weak self] location in
            self?.handleLocationUpdate(clientID: client.id, location: location)
        }
    }
    
    private func stopLocationMonitoring(for clientID: UUID) {
        cloudSync.unsubscribeFromLocationUpdates(clientID: clientID)
    }
    
    private func handleLocationUpdate(clientID: UUID, location: CLLocation) {
        let event = LocationEvent(
            clientID: clientID,
            location: location,
            timestamp: Date(),
            type: .update
        )
        
        locationHistory.append(event)
        
        // Check for safety zones and alerts
        checkSafetyZones(clientID: clientID, location: location)
        
        // Update client's last known location
        if let index = clients.firstIndex(where: { $0.id == clientID }) {
            clients[index].lastKnownLocation = location
            clients[index].lastLocationUpdate = Date()
        }
    }
    
    private func checkSafetyZones(clientID: UUID, location: CLLocation) {
        guard let client = clients.first(where: { $0.id == clientID }) else { return }
        
        for zone in client.safetyZones {
            let distance = location.distance(from: zone.center)
            
            if zone.type == .safe && distance > zone.radius {
                // Client left safe zone
                triggerSafetyAlert(clientID: clientID, type: .leftSafeZone, location: location)
            } else if zone.type == .restricted && distance < zone.radius {
                // Client entered restricted zone
                triggerSafetyAlert(clientID: clientID, type: .enteredRestrictedZone, location: location)
            }
        }
    }
    
    // MARK: - Health Monitoring
    
    private func startHealthMonitoring(for client: CareRecipient) {
        healthMonitor?.startMonitoring(clientID: client.id, healthProfile: client.healthProfile)
    }
    
    private func stopHealthMonitoring(for clientID: UUID) {
        healthMonitor?.stopMonitoring(clientID: clientID)
    }
    
    // MARK: - Activity Monitoring
    
    private func startActivityMonitoring(for client: CareRecipient) {
        // Monitor app usage and activity patterns
        cloudSync.subscribeToActivityUpdates(clientID: client.id) { [weak self] activity in
            self?.handleActivityUpdate(clientID: client.id, activity: activity)
        }
    }
    
    private func stopActivityMonitoring(for clientID: UUID) {
        cloudSync.unsubscribeFromActivityUpdates(clientID: clientID)
    }
    
    private func handleActivityUpdate(clientID: UUID, activity: ActivityData) {
        // Check for unusual patterns or inactivity
        if activity.type == .noActivity && activity.duration > 7200 { // 2 hours of inactivity
            triggerWellnessCheck(clientID: clientID, reason: "Extended period of inactivity detected")
        }
    }
    
    // MARK: - Emergency Response
    
    private func enableEmergencyResponse(for client: CareRecipient) {
        emergencyResponseSystem?.enableForClient(client.id)
    }
    
    func respondToEmergency(alert: EmergencyAlert) {
        // Update alert status
        if let index = emergencyAlerts.firstIndex(where: { $0.id == alert.id }) {
            emergencyAlerts[index].status = .responding
            emergencyAlerts[index].responderID = caregiverProfile?.id
            emergencyAlerts[index].responseTime = Date()
        }
        
        // Start emergency protocol
        switch alert.severity {
        case .critical:
            initiateEmergencyCall(for: alert)
            startEmergencyVideoSession(with: alert.clientID)
        case .high:
            initiateImmediateContact(for: alert)
        case .medium:
            scheduleUrgentCheckIn(for: alert.clientID)
        case .low:
            addToFollowUpQueue(alert: alert)
        }
        
        // Notify other caregivers if needed
        if alert.severity >= .high {
            notifyOtherCaregivers(alert: alert)
        }
        
        speechOutput.speak("Responding to \(alert.severity.rawValue) emergency for \(getClientName(alert.clientID))")
    }
    
    private func initiateEmergencyCall(for alert: EmergencyAlert) {
        // Start emergency call protocol
        if let client = clients.first(where: { $0.id == alert.clientID }),
           let emergencyContact = client.emergencyContacts.first {
            // Initiate call to emergency services or emergency contact
            Config.debugLog("Initiating emergency call for \(client.name)")
        }
    }
    
    private func startEmergencyVideoSession(with clientID: UUID) {
        // Start emergency video call
        initiateVideoCall(with: clientID, priority: .emergency)
    }
    
    private func triggerSafetyAlert(clientID: UUID, type: SafetyAlertType, location: CLLocation) {
        let alert = EmergencyAlert(
            id: UUID(),
            clientID: clientID,
            type: .safety,
            description: type.description,
            severity: type.severity,
            location: location,
            timestamp: Date(),
            status: .pending
        )
        
        emergencyAlerts.append(alert)
        
        // Send notification
        sendNotification(
            title: "Safety Alert",
            body: "\(getClientName(clientID)): \(type.description)",
            priority: type.severity
        )
        
        speechOutput.speak("Safety alert: \(type.description) for \(getClientName(clientID))", priority: .high)
    }
    
    private func triggerWellnessCheck(clientID: UUID, reason: String) {
        let checkIn = ScheduledCheckIn(
            id: UUID(),
            clientID: clientID,
            scheduledTime: Date(),
            type: .wellness,
            reason: reason,
            status: .pending,
            priority: .medium
        )
        
        scheduledCheckIns.append(checkIn)
        
        // Send notification
        sendNotification(
            title: "Wellness Check Needed",
            body: "\(getClientName(clientID)): \(reason)",
            priority: .medium
        )
    }
    
    // MARK: - Video Assistance
    
    func initiateVideoCall(with clientID: UUID, priority: VideoPriority = .normal) {
        guard let client = clients.first(where: { $0.id == clientID }) else { return }
        
        let session = VideoSession(
            id: UUID(),
            clientID: clientID,
            caregiverID: caregiverProfile?.id ?? UUID(),
            startTime: Date(),
            priority: priority,
            status: .connecting
        )
        
        videoSessions.append(session)
        
        // Initiate video connection
        videoClient?.initiateCall(to: clientID.uuidString) { [weak self] success in
            DispatchQueue.main.async {
                if success {
                    self?.updateVideoSessionStatus(session.id, status: .connected)
                    self?.speechOutput.speak("Video call connected with \(client.name)")
                } else {
                    self?.updateVideoSessionStatus(session.id, status: .failed)
                    self?.speechOutput.speak("Failed to connect video call with \(client.name)")
                }
            }
        }
    }
    
    func endVideoCall(sessionID: UUID) {
        guard let sessionIndex = videoSessions.firstIndex(where: { $0.id == sessionID }) else { return }
        
        var session = videoSessions[sessionIndex]
        session.endTime = Date()
        session.status = .ended
        
        videoSessions[sessionIndex] = session
        
        videoClient?.endCall()
        speechOutput.speak("Video call ended")
    }
    
    private func updateVideoSessionStatus(_ sessionID: UUID, status: VideoSessionStatus) {
        if let index = videoSessions.firstIndex(where: { $0.id == sessionID }) {
            videoSessions[index].status = status
        }
    }
    
    // MARK: - Scheduled Check-ins
    
    func scheduleCheckIn(clientID: UUID, time: Date, type: CheckInType, notes: String = "") {
        let checkIn = ScheduledCheckIn(
            id: UUID(),
            clientID: clientID,
            scheduledTime: time,
            type: type,
            reason: notes,
            status: .scheduled,
            priority: .normal
        )
        
        scheduledCheckIns.append(checkIn)
        
        // Schedule local notification
        scheduleCheckInNotification(checkIn: checkIn)
        
        speechOutput.speak("Check-in scheduled for \(getClientName(clientID)) at \(formatTime(time))")
    }
    
    func completeCheckIn(_ checkInID: UUID, notes: String, outcome: CheckInOutcome) {
        guard let index = scheduledCheckIns.firstIndex(where: { $0.id == checkInID }) else { return }
        
        var checkIn = scheduledCheckIns[index]
        checkIn.status = .completed
        checkIn.completionTime = Date()
        checkIn.outcome = outcome
        checkIn.notes = notes
        
        scheduledCheckIns[index] = checkIn
        
        // Save to cloud
        cloudSync.saveCheckInRecord(checkIn) { success in
            Config.debugLog("Check-in record saved: \(success)")
        }
        
        speechOutput.speak("Check-in completed for \(getClientName(checkIn.clientID))")
    }
    
    private func scheduleCheckInNotification(checkIn: ScheduledCheckIn) {
        let content = UNMutableNotificationContent()
        content.title = "Scheduled Check-in"
        content.body = "Time for check-in with \(getClientName(checkIn.clientID))"
        content.sound = .default
        
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: checkIn.scheduledTime)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        
        let request = UNNotificationRequest(identifier: checkIn.id.uuidString, content: content, trigger: trigger)
        
        notificationCenter.add(request) { error in
            if let error = error {
                Config.debugLog("Failed to schedule notification: \(error)")
            }
        }
    }
    
    // MARK: - Healthcare Integration
    
    func integrateWithEHR(clientID: UUID, ehrSystem: EHRSystem, credentials: EHRCredentials) {
        // Integrate with Electronic Health Records
        ehrSystem.authenticate(credentials: credentials) { [weak self] success in
            if success {
                self?.syncHealthData(clientID: clientID, ehrSystem: ehrSystem)
            }
        }
    }
    
    private func syncHealthData(clientID: UUID, ehrSystem: EHRSystem) {
        ehrSystem.fetchPatientData(clientID: clientID) { [weak self] healthData in
            DispatchQueue.main.async {
                self?.healthData.append(contentsOf: healthData)
                self?.analyzeHealthTrends(for: clientID)
            }
        }
    }
    
    private func analyzeHealthTrends(for clientID: UUID) {
        let clientHealthData = healthData.filter { $0.clientID == clientID }
        
        // Analyze trends and alert if needed
        let healthAnalyzer = HealthTrendAnalyzer()
        let trends = healthAnalyzer.analyzeTrends(data: clientHealthData)
        
        for trend in trends {
            if trend.severity >= .medium {
                createHealthAlert(clientID: clientID, trend: trend)
            }
        }
    }
    
    private func createHealthAlert(clientID: UUID, trend: HealthTrend) {
        let alert = EmergencyAlert(
            id: UUID(),
            clientID: clientID,
            type: .health,
            description: trend.description,
            severity: trend.severity,
            location: nil,
            timestamp: Date(),
            status: .pending
        )
        
        emergencyAlerts.append(alert)
        
        sendNotification(
            title: "Health Alert",
            body: "\(getClientName(clientID)): \(trend.description)",
            priority: trend.severity
        )
    }
    
    // MARK: - Reports and Analytics
    
    func generateCareReport(for clientID: UUID, period: ReportPeriod) -> CareReport {
        let client = clients.first { $0.id == clientID }
        let clientLocationHistory = locationHistory.filter { $0.clientID == clientID }
        let clientHealthData = healthData.filter { $0.clientID == clientID }
        let clientEmergencies = emergencyAlerts.filter { $0.clientID == clientID }
        
        let report = CareReport(
            clientID: clientID,
            clientName: client?.name ?? "Unknown",
            period: period,
            totalMonitoringTime: calculateMonitoringTime(clientID: clientID),
            locationEvents: clientLocationHistory.count,
            healthMetrics: clientHealthData,
            emergencyAlerts: clientEmergencies.count,
            checkInsCompleted: getCompletedCheckIns(clientID: clientID),
            generatedDate: Date()
        )
        
        return report
    }
    
    private func calculateMonitoringTime(clientID: UUID) -> TimeInterval {
        // Calculate total monitoring time for client
        return 0 // Placeholder
    }
    
    private func getCompletedCheckIns(clientID: UUID) -> Int {
        return scheduledCheckIns.filter { 
            $0.clientID == clientID && $0.status == .completed 
        }.count
    }
    
    // MARK: - Utility Methods
    
    private func getClientName(_ clientID: UUID) -> String {
        return clients.first { $0.id == clientID }?.name ?? "Unknown Client"
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    private func sendNotification(title: String, body: String, priority: AlertSeverity) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = priority >= .high ? .defaultCritical : .default
        
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        
        notificationCenter.add(request) { error in
            if let error = error {
                Config.debugLog("Failed to send notification: \(error)")
            }
        }
    }
    
    private func notifyOtherCaregivers(alert: EmergencyAlert) {
        // Notify other caregivers in the organization
        cloudSync.notifyOtherCaregivers(alert: alert) { success in
            Config.debugLog("Notified other caregivers: \(success)")
        }
    }
    
    private func initiateImmediateContact(for alert: EmergencyAlert) {
        // Try to contact client immediately
        initiateVideoCall(with: alert.clientID, priority: .high)
    }
    
    private func scheduleUrgentCheckIn(for clientID: UUID) {
        let urgentTime = Date().addingTimeInterval(300) // 5 minutes from now
        scheduleCheckIn(clientID: clientID, time: urgentTime, type: .urgent, notes: "Emergency response check-in")
    }
    
    private func addToFollowUpQueue(alert: EmergencyAlert) {
        // Add to follow-up queue for later review
        Config.debugLog("Added alert to follow-up queue: \(alert.id)")
    }
    
    // MARK: - Public Interface
    
    func toggleDutyStatus() {
        isOnDuty.toggle()
        
        if isOnDuty {
            startMonitoringActiveClients()
            speechOutput.speak("You are now on duty. Monitoring active clients.")
        } else {
            stopAllMonitoring()
            speechOutput.speak("You are now off duty. Monitoring stopped.")
        }
    }
    
    func getDashboardSummary() -> String {
        let activeClients = clients.filter { $0.settings.active }.count
        let pendingAlerts = emergencyAlerts.filter { $0.status == .pending }.count
        let pendingCheckIns = scheduledCheckIns.filter { $0.status == .scheduled }.count
        
        var summary = "Dashboard: "
        summary += "\(activeClients) active client\(activeClients == 1 ? "" : "s"). "
        
        if pendingAlerts > 0 {
            summary += "\(pendingAlerts) pending alert\(pendingAlerts == 1 ? "" : "s"). "
        }
        
        if pendingCheckIns > 0 {
            summary += "\(pendingCheckIns) scheduled check-in\(pendingCheckIns == 1 ? "" : "s"). "
        }
        
        summary += isOnDuty ? "On duty." : "Off duty."
        
        return summary
    }
    
    func speakDashboardSummary() {
        let summary = getDashboardSummary()
        speechOutput.speak(summary)
    }
}

// MARK: - Delegate Implementations

extension CaregiverDashboard: EmergencyResponseDelegate {
    func didReceiveEmergencyAlert(_ alert: EmergencyAlert) {
        DispatchQueue.main.async {
            self.emergencyAlerts.append(alert)
            
            // Auto-respond to critical emergencies
            if alert.severity == .critical {
                self.respondToEmergency(alert: alert)
            }
            
            // Notify caregiver
            self.sendNotification(
                title: "EMERGENCY ALERT",
                body: "\(self.getClientName(alert.clientID)): \(alert.description)",
                priority: alert.severity
            )
            
            self.speechOutput.speak("Emergency alert received from \(self.getClientName(alert.clientID)): \(alert.description)", priority: .emergency)
        }
    }
}

extension CaregiverDashboard: HealthMonitorDelegate {
    func didReceiveHealthUpdate(_ update: HealthDataPoint) {
        DispatchQueue.main.async {
            self.healthData.append(update)
            
            // Check for health alerts
            if update.isAbnormal {
                self.createHealthAlert(clientID: update.clientID, trend: HealthTrend(
                    type: update.type,
                    severity: update.severity,
                    description: "Abnormal \(update.type.rawValue) detected: \(update.value)"
                ))
            }
        }
    }
}

extension CaregiverDashboard: VideoClientDelegate {
    func didConnectToClient(_ clientID: String) {
        speechOutput.speak("Video call connected")
    }
    
    func didDisconnectFromClient(_ clientID: String) {
        speechOutput.speak("Video call ended")
    }
    
    func didFailToConnect(error: Error) {
        speechOutput.speak("Video call failed to connect")
    }
}

extension CaregiverDashboard: SignalingClientDelegate {
    func didReceiveCallRequest(from clientID: String) {
        // Handle incoming call request from client
        speechOutput.speak("Incoming assistance request from \(getClientName(UUID(uuidString: clientID) ?? UUID()))")
    }
}

// MARK: - Data Models

struct CareRecipient: Identifiable, Codable {
    let id: UUID
    var name: String
    var age: Int
    var healthProfile: HealthProfile
    var settings: CareSettings
    var safetyZones: [SafetyZone]
    var emergencyContacts: [EmergencyContact]
    var lastKnownLocation: CLLocation?
    var lastLocationUpdate: Date?
    let enrollmentDate: Date
}

struct CareSettings: Codable {
    var active: Bool
    var locationTracking: Bool
    var healthMonitoring: Bool
    var activityMonitoring: Bool
    var emergencyResponse: Bool
    var videoAssistance: Bool
    var checkInFrequency: CheckInFrequency
    
    func getMonitoringTypes() -> [MonitoringType] {
        var types: [MonitoringType] = []
        if locationTracking { types.append(.location) }
        if healthMonitoring { types.append(.health) }
        if activityMonitoring { types.append(.activity) }
        return types
    }
}

struct MonitoringSession: Identifiable, Codable {
    let id = UUID()
    let clientID: UUID
    let startTime: Date
    var endTime: Date?
    let monitoringTypes: [MonitoringType]
    var status: MonitoringStatus
}

struct LocationEvent: Identifiable, Codable {
    let id = UUID()
    let clientID: UUID
    let location: CLLocation
    let timestamp: Date
    let type: LocationEventType
}

struct HealthDataPoint: Identifiable, Codable {
    let id = UUID()
    let clientID: UUID
    let type: HealthMetricType
    let value: String
    let unit: String
    let timestamp: Date
    let isAbnormal: Bool
    let severity: AlertSeverity
}

struct VideoSession: Identifiable, Codable {
    let id: UUID
    let clientID: UUID
    let caregiverID: UUID
    let startTime: Date
    var endTime: Date?
    let priority: VideoPriority
    var status: VideoSessionStatus
}

struct ScheduledCheckIn: Identifiable, Codable {
    let id: UUID
    let clientID: UUID
    let scheduledTime: Date
    var completionTime: Date?
    let type: CheckInType
    let reason: String
    var status: CheckInStatus
    let priority: CheckInPriority
    var outcome: CheckInOutcome?
    var notes: String = ""
}

struct EmergencyAlert: Identifiable, Codable {
    let id: UUID
    let clientID: UUID
    let type: EmergencyType
    let description: String
    let severity: AlertSeverity
    let location: CLLocation?
    let timestamp: Date
    var status: EmergencyStatus
    var responderID: UUID?
    var responseTime: Date?
}

struct CaregiverProfile: Identifiable, Codable {
    let id: UUID
    var name: String
    let role: CaregiverRole
    let certification: CertificationLevel
    let organization: String
    let contactInfo: ContactInfo
    let accessLevel: AccessLevel
    let joinDate: Date
}

struct ContactInfo: Codable {
    let phone: String
    let email: String
}

struct HealthProfile: Codable {
    let conditions: [String]
    let medications: [String]
    let allergies: [String]
    let emergencyContacts: [EmergencyContact]
    let preferences: HealthPreferences
}

struct SafetyZone: Identifiable, Codable {
    let id = UUID()
    let name: String
    let center: CLLocation
    let radius: CLLocationDistance
    let type: SafetyZoneType
}

struct EmergencyContact: Identifiable, Codable {
    let id = UUID()
    let name: String
    let relationship: String
    let phone: String
    let isPrimary: Bool
}

struct CareReport: Identifiable, Codable {
    let id = UUID()
    let clientID: UUID
    let clientName: String
    let period: ReportPeriod
    let totalMonitoringTime: TimeInterval
    let locationEvents: Int
    let healthMetrics: [HealthDataPoint]
    let emergencyAlerts: Int
    let checkInsCompleted: Int
    let generatedDate: Date
}

struct ActivityData: Codable {
    let type: ActivityType
    let duration: TimeInterval
    let timestamp: Date
}

struct HealthTrend: Codable {
    let type: HealthMetricType
    let severity: AlertSeverity
    let description: String
}

struct OrganizationSettings: Codable {
    let name: String
    let policies: [CarePolicy]
    let emergencyProtocols: [EmergencyProtocol]
    let reportingRequirements: ReportingRequirements
}

struct HealthPreferences: Codable {
    let preferredLanguage: String
    let communicationMethod: CommunicationMethod
    let accessibilityNeeds: [String]
}

// MARK: - Enums

enum MonitoringType: String, Codable, CaseIterable {
    case location = "location"
    case health = "health"
    case activity = "activity"
    case emergency = "emergency"
}

enum MonitoringStatus: String, Codable {
    case active = "active"
    case paused = "paused"
    case stopped = "stopped"
}

enum LocationEventType: String, Codable {
    case update = "update"
    case safeZoneEntry = "safe_zone_entry"
    case safeZoneExit = "safe_zone_exit"
    case emergency = "emergency"
}

enum HealthMetricType: String, Codable, CaseIterable {
    case heartRate = "heart_rate"
    case bloodPressure = "blood_pressure"
    case temperature = "temperature"
    case oxygenSaturation = "oxygen_saturation"
    case bloodSugar = "blood_sugar"
    case steps = "steps"
    case sleep = "sleep"
}

enum VideoPriority: String, Codable {
    case normal = "normal"
    case high = "high"
    case emergency = "emergency"
}

enum VideoSessionStatus: String, Codable {
    case connecting = "connecting"
    case connected = "connected"
    case ended = "ended"
    case failed = "failed"
}

enum CheckInType: String, Codable, CaseIterable {
    case routine = "routine"
    case wellness = "wellness"
    case urgent = "urgent"
    case emergency = "emergency"
}

enum CheckInStatus: String, Codable {
    case scheduled = "scheduled"
    case pending = "pending"
    case completed = "completed"
    case missed = "missed"
}

enum CheckInPriority: String, Codable {
    case low = "low"
    case normal = "normal"
    case medium = "medium"
    case high = "high"
}

enum CheckInOutcome: String, Codable {
    case successful = "successful"
    case needsFollowUp = "needs_follow_up"
    case escalateToEmergency = "escalate_to_emergency"
    case noResponse = "no_response"
}

enum CheckInFrequency: String, Codable, CaseIterable {
    case daily = "daily"
    case twiceDaily = "twice_daily"
    case weekly = "weekly"
    case asNeeded = "as_needed"
}

enum EmergencyType: String, Codable {
    case safety = "safety"
    case health = "health"
    case technical = "technical"
    case assistance = "assistance"
}

enum EmergencyStatus: String, Codable {
    case pending = "pending"
    case responding = "responding"
    case resolved = "resolved"
    case escalated = "escalated"
}

enum CaregiverRole: String, Codable, CaseIterable {
    case nurse = "nurse"
    case doctor = "doctor"
    case therapist = "therapist"
    case aide = "aide"
    case familyMember = "family_member"
    case volunteer = "volunteer"
}

enum CertificationLevel: String, Codable {
    case registered = "registered"
    case licensed = "licensed"
    case certified = "certified"
    case trainee = "trainee"
}

enum AccessLevel: String, Codable {
    case standard = "standard"
    case elevated = "elevated"
    case administrator = "administrator"
}

enum SafetyZoneType: String, Codable {
    case safe = "safe"
    case restricted = "restricted"
}

enum SafetyAlertType {
    case leftSafeZone
    case enteredRestrictedZone
    
    var description: String {
        switch self {
        case .leftSafeZone: return "Left safe zone"
        case .enteredRestrictedZone: return "Entered restricted area"
        }
    }
    
    var severity: AlertSeverity {
        switch self {
        case .leftSafeZone: return .medium
        case .enteredRestrictedZone: return .high
        }
    }
}

enum ReportPeriod: String, Codable, CaseIterable {
    case daily = "daily"
    case weekly = "weekly"
    case monthly = "monthly"
    case quarterly = "quarterly"
}

enum ActivityType: String, Codable {
    case appUsage = "app_usage"
    case movement = "movement"
    case voiceCommand = "voice_command"
    case noActivity = "no_activity"
}

enum ConnectionStatus: String, Codable {
    case connected = "connected"
    case disconnected = "disconnected"
    case connecting = "connecting"
}

enum CommunicationMethod: String, Codable {
    case voice = "voice"
    case text = "text"
    case video = "video"
    case tactile = "tactile"
}

// MARK: - Protocol Definitions

protocol EmergencyResponseDelegate: AnyObject {
    func didReceiveEmergencyAlert(_ alert: EmergencyAlert)
}

protocol HealthMonitorDelegate: AnyObject {
    func didReceiveHealthUpdate(_ update: HealthDataPoint)
}

protocol VideoClientDelegate: AnyObject {
    func didConnectToClient(_ clientID: String)
    func didDisconnectFromClient(_ clientID: String)
    func didFailToConnect(error: Error)
}

protocol SignalingClientDelegate: AnyObject {
    func didReceiveCallRequest(from clientID: String)
}

// MARK: - Network Classes

class VideoClient {
    weak var delegate: VideoClientDelegate?
    
    func initiateCall(to clientID: String, completion: @escaping (Bool) -> Void) {
        // Video call implementation
        completion(true) // Placeholder
    }
    
    func endCall() {
        // End video call
    }
}

class SignalingClient {
    weak var delegate: SignalingClientDelegate?
    
    // Video signaling implementation
}

class HealthMonitor {
    weak var delegate: HealthMonitorDelegate?
    private let healthStore: HKHealthStore
    
    init(healthStore: HKHealthStore) {
        self.healthStore = healthStore
    }
    
    func startMonitoring(clientID: UUID, healthProfile: HealthProfile) {
        // Start health monitoring
    }
    
    func stopMonitoring(clientID: UUID) {
        // Stop health monitoring
    }
}

class HealthTrendAnalyzer {
    func analyzeTrends(data: [HealthDataPoint]) -> [HealthTrend] {
        // Analyze health trends
        return [] // Placeholder
    }
}

class EHRSystem {
    func authenticate(credentials: EHRCredentials, completion: @escaping (Bool) -> Void) {
        // EHR authentication
        completion(true) // Placeholder
    }
    
    func fetchPatientData(clientID: UUID, completion: @escaping ([HealthDataPoint]) -> Void) {
        // Fetch patient data from EHR
        completion([]) // Placeholder
    }
}

struct EHRCredentials {
    let username: String
    let password: String
    let apiKey: String
}

struct CarePolicy {
    let name: String
    let requirements: [String]
}

struct EmergencyProtocol {
    let severity: AlertSeverity
    let steps: [String]
}

struct ReportingRequirements {
    let frequency: ReportPeriod
    let requiredMetrics: [String]
}

// MARK: - CloudSync Extensions

extension CloudSyncManager {
    func getCareRecipients(completion: @escaping ([CareRecipient]) -> Void) {
        // Fetch care recipients
        completion([]) // Placeholder
    }
    
    func addCareRecipient(_ recipient: CareRecipient, completion: @escaping (Bool) -> Void) {
        // Add care recipient
        completion(true) // Placeholder
    }
    
    func removeCareRecipient(_ recipientID: UUID, completion: @escaping (Bool) -> Void) {
        // Remove care recipient
        completion(true) // Placeholder
    }
    
    func subscribeToLocationUpdates(clientID: UUID, handler: @escaping (CLLocation) -> Void) {
        // Subscribe to location updates
    }
    
    func unsubscribeFromLocationUpdates(clientID: UUID) {
        // Unsubscribe from location updates
    }
    
    func subscribeToActivityUpdates(clientID: UUID, handler: @escaping (ActivityData) -> Void) {
        // Subscribe to activity updates
    }
    
    func unsubscribeFromActivityUpdates(clientID: UUID) {
        // Unsubscribe from activity updates
    }
    
    func saveCheckInRecord(_ checkIn: ScheduledCheckIn, completion: @escaping (Bool) -> Void) {
        // Save check-in record
        completion(true) // Placeholder
    }
    
    func notifyOtherCaregivers(alert: EmergencyAlert, completion: @escaping (Bool) -> Void) {
        // Notify other caregivers
        completion(true) // Placeholder
    }
} 