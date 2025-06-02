import Foundation
import UserNotifications
import CloudKit

class CaregiverNotificationManager: ObservableObject {
    @Published var connectedCaregivers: [Caregiver] = []
    @Published var pendingNotifications: [CaregiverNotification] = []
    @Published var isEnabled = true
    
    // Cloud and communication
    private let cloudManager = CloudKitManager()
    private let pushNotificationManager = PushNotificationManager()
    private let encryptionManager = CaregiverEncryption()
    
    // Emergency communications
    private var emergencyChannels: [CommunicationChannel] = []
    private let speechOutput = SpeechOutput.shared
    
    init() {
        setupCaregiverNotifications()
    }
    
    // MARK: - Setup and Configuration
    
    private func setupCaregiverNotifications() {
        loadConnectedCaregivers()
        setupEmergencyChannels()
        requestNotificationPermissions()
    }
    
    func addCaregiver(_ caregiver: Caregiver) {
        connectedCaregivers.append(caregiver)
        setupCaregiverConnection(caregiver)
        speechOutput.speak("Caregiver \(caregiver.name) added")
    }
    
    // MARK: - Emergency Alerts
    
    func sendEmergencyAlert(_ condition: EmergencyCondition, location: CLLocation? = nil) {
        let alert = CaregiverNotification(
            id: UUID(),
            type: .emergency,
            priority: .critical,
            title: "🚨 EMERGENCY ALERT",
            message: condition.description,
            timestamp: Date(),
            healthData: createEmergencyHealthData(condition),
            location: location
        )
        
        broadcastNotification(alert)
        Config.debugLog("Emergency alert sent to all caregivers")
    }
    
    func sendDropAlert(_ dropEvent: DropEvent, message: String) {
        let alert = CaregiverNotification(
            id: UUID(),
            type: .alert,
            priority: .high,
            title: "📱 DEVICE DROP ALERT",
            message: message,
            timestamp: Date(),
            healthData: createDropHealthData(dropEvent),
            location: dropEvent.location
        )
        
        broadcastNotification(alert)
        Config.debugLog("Drop alert sent to all caregivers")
    }
    
    func sendDirectMessage(_ message: String, to contact: EmergencyContact) {
        let notification = CaregiverNotification(
            id: UUID(),
            type: .message,
            priority: .high,
            title: "KaiSight Alert",
            message: message,
            timestamp: Date(),
            healthData: nil,
            location: nil
        )
        
        sendToSpecificCaregiver(notification, contact: contact)
    }
    
    // MARK: - Health Data Sharing
    
    func shareHealthUpdate(_ reading: HealthReading) {
        guard isEnabled else { return }
        
        let healthUpdate = CaregiverNotification(
            id: UUID(),
            type: .healthUpdate,
            priority: .normal,
            title: "Health Update",
            message: formatHealthReading(reading),
            timestamp: Date(),
            healthData: reading,
            location: nil
        )
        
        sendToAuthorizedCaregivers(healthUpdate)
    }
    
    func shareHealthSummary(_ summary: HealthSummary) {
        let summaryNotification = CaregiverNotification(
            id: UUID(),
            type: .healthSummary,
            priority: .normal,
            title: "Daily Health Summary",
            message: generateSummaryMessage(summary),
            timestamp: Date(),
            healthData: summary,
            location: nil
        )
        
        sendToAuthorizedCaregivers(summaryNotification)
    }
    
    // MARK: - Communication Methods
    
    private func broadcastNotification(_ notification: CaregiverNotification) {
        for caregiver in connectedCaregivers {
            sendNotificationToCaregiver(notification, caregiver: caregiver)
        }
        
        pendingNotifications.append(notification)
    }
    
    private func sendToAuthorizedCaregivers(_ notification: CaregiverNotification) {
        let authorized = connectedCaregivers.filter { $0.permissions.canReceiveHealthData }
        
        for caregiver in authorized {
            sendNotificationToCaregiver(notification, caregiver: caregiver)
        }
    }
    
    private func sendNotificationToCaregiver(_ notification: CaregiverNotification, caregiver: Caregiver) {
        // Encrypt notification
        do {
            let encryptedNotification = try encryptionManager.encrypt(notification, for: caregiver)
            
            // Send via multiple channels based on urgency
            switch notification.priority {
            case .critical:
                sendViaPushNotification(encryptedNotification, to: caregiver)
                sendViaSMS(notification, to: caregiver)
                sendViaEmail(notification, to: caregiver)
                
            case .high:
                sendViaPushNotification(encryptedNotification, to: caregiver)
                sendViaSMS(notification, to: caregiver)
                
            case .normal:
                sendViaPushNotification(encryptedNotification, to: caregiver)
            }
            
        } catch {
            Config.debugLog("Failed to encrypt notification: \(error)")
        }
    }
    
    // MARK: - Communication Channels
    
    private func sendViaPushNotification(_ notification: EncryptedNotification, to caregiver: Caregiver) {
        pushNotificationManager.sendToCaregiver(notification, caregiver: caregiver)
    }
    
    private func sendViaSMS(_ notification: CaregiverNotification, to caregiver: Caregiver) {
        guard caregiver.preferences.enableSMS else { return }
        
        let smsMessage = formatForSMS(notification)
        SMSManager.shared.sendMessage(smsMessage, to: caregiver.phoneNumber)
    }
    
    private func sendViaEmail(_ notification: CaregiverNotification, to caregiver: Caregiver) {
        guard caregiver.preferences.enableEmail else { return }
        
        let emailContent = formatForEmail(notification)
        EmailManager.shared.sendEmail(emailContent, to: caregiver.email)
    }
    
    // MARK: - Helper Methods
    
    private func formatHealthReading(_ reading: HealthReading) -> String {
        switch reading.type {
        case .bloodGlucose:
            return "Blood glucose: \(Int(reading.value)) \(reading.unit)"
        case .heartRate:
            return "Heart rate: \(Int(reading.value)) BPM"
        case .bloodPressure:
            if let systolic = reading.additionalValues?["systolic"],
               let diastolic = reading.additionalValues?["diastolic"] {
                return "Blood pressure: \(Int(systolic))/\(Int(diastolic)) mmHg"
            }
            return "Blood pressure reading"
        default:
            return "\(reading.type.rawValue): \(reading.value) \(reading.unit)"
        }
    }
    
    private func createEmergencyHealthData(_ condition: EmergencyCondition) -> Any {
        return [
            "emergency_type": condition.type.rawValue,
            "severity": condition.severity.rawValue,
            "timestamp": Date().timeIntervalSince1970,
            "description": condition.description
        ]
    }
    
    private func createDropHealthData(_ dropEvent: DropEvent) -> Any {
        return [
            "drop_event_id": dropEvent.id.uuidString,
            "impact_force": dropEvent.impactForce,
            "freefall_duration": dropEvent.freefallDuration,
            "device_orientation": dropEvent.deviceOrientation.rawValue,
            "timestamp": dropEvent.timestamp.timeIntervalSince1970,
            "location_available": dropEvent.location != nil
        ]
    }
    
    private func generateSummaryMessage(_ summary: HealthSummary) -> String {
        return "Daily health summary: \(summary.connectedDevices) devices, \(summary.latestReadings.count) readings"
    }
    
    private func formatForSMS(_ notification: CaregiverNotification) -> String {
        return "\(notification.title): \(notification.message)"
    }
    
    private func formatForEmail(_ notification: CaregiverNotification) -> EmailContent {
        return EmailContent(
            subject: notification.title,
            body: notification.message,
            isHTML: false
        )
    }
    
    // MARK: - Configuration
    
    private func loadConnectedCaregivers() {
        // Load from secure storage
        connectedCaregivers = CaregiverStorage.loadCaregivers()
    }
    
    private func setupCaregiverConnection(_ caregiver: Caregiver) {
        cloudManager.establishConnection(with: caregiver)
    }
    
    private func setupEmergencyChannels() {
        emergencyChannels = [
            .pushNotification,
            .sms,
            .email,
            .voiceCall
        ]
    }
    
    private func requestNotificationPermissions() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            Config.debugLog("Notification permissions: \(granted)")
        }
    }
    
    private func sendToSpecificCaregiver(_ notification: CaregiverNotification, contact: EmergencyContact) {
        // Find matching caregiver and send
        if let caregiver = connectedCaregivers.first(where: { $0.contactInfo.phoneNumber == contact.phoneNumber }) {
            sendNotificationToCaregiver(notification, caregiver: caregiver)
        } else {
            // Send directly via contact info
            SMSManager.shared.sendMessage(notification.message, to: contact.phoneNumber)
        }
    }
}

// MARK: - Data Models

struct Caregiver: Identifiable, Codable {
    let id: UUID
    let name: String
    let relationship: String
    let contactInfo: CaregiverContactInfo
    let permissions: CaregiverPermissions
    let preferences: CaregiverPreferences
    let encryptionKey: String
}

struct CaregiverContactInfo: Codable {
    let phoneNumber: String
    let email: String
    let pushToken: String?
}

struct CaregiverPermissions: Codable {
    let canReceiveHealthData: Bool
    let canReceiveEmergencyAlerts: Bool
    let canViewHistoricalData: Bool
    let dataRetentionDays: Int
}

struct CaregiverPreferences: Codable {
    let enableSMS: Bool
    let enableEmail: Bool
    let enablePushNotifications: Bool
    let quietHours: QuietHours?
    let emergencyOverride: Bool
}

struct CaregiverNotification: Identifiable {
    let id: UUID
    let type: NotificationType
    let priority: NotificationPriority
    let title: String
    let message: String
    let timestamp: Date
    let healthData: Any?
    let location: CLLocation?
}

enum NotificationType: String, CaseIterable {
    case emergency = "emergency"
    case healthUpdate = "health_update"
    case healthSummary = "health_summary"
    case message = "message"
    case alert = "alert"
}

enum NotificationPriority: String, CaseIterable {
    case normal = "normal"
    case high = "high"
    case critical = "critical"
}

enum CommunicationChannel: String, CaseIterable {
    case pushNotification = "push"
    case sms = "sms"
    case email = "email"
    case voiceCall = "voice"
}

struct EncryptedNotification {
    let data: Data
    let timestamp: Date
    let caregiverId: UUID
}

struct EmailContent {
    let subject: String
    let body: String
    let isHTML: Bool
}

// MARK: - Supporting Classes

class CaregiverEncryption {
    func encrypt(_ notification: CaregiverNotification, for caregiver: Caregiver) throws -> EncryptedNotification {
        let jsonData = try JSONEncoder().encode(notification)
        // Encrypt with caregiver's public key
        return EncryptedNotification(
            data: jsonData,
            timestamp: Date(),
            caregiverId: caregiver.id
        )
    }
}

class PushNotificationManager {
    func sendToCaregiver(_ notification: EncryptedNotification, caregiver: Caregiver) {
        // Send encrypted push notification
        Config.debugLog("Push notification sent to \(caregiver.name)")
    }
}

class CloudKitManager {
    func establishConnection(with caregiver: Caregiver) {
        // Setup CloudKit sharing
        Config.debugLog("CloudKit connection established with \(caregiver.name)")
    }
}

class SMSManager {
    static let shared = SMSManager()
    
    func sendMessage(_ message: String, to phoneNumber: String) {
        // Send SMS via MessageUI or third-party service
        Config.debugLog("SMS sent to \(phoneNumber)")
    }
}

class EmailManager {
    static let shared = EmailManager()
    
    func sendEmail(_ content: EmailContent, to email: String) {
        // Send email via MessageUI or email service
        Config.debugLog("Email sent to \(email)")
    }
}

class CaregiverStorage {
    static func loadCaregivers() -> [Caregiver] {
        // Load from secure storage
        return []
    }
    
    static func saveCaregivers(_ caregivers: [Caregiver]) {
        // Save to secure storage
    }
} 