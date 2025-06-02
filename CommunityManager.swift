import Foundation
import Combine
import CoreLocation
import CloudKit
import SwiftUI

class CommunityManager: NSObject, ObservableObject {
    @Published var nearbyUsers: [CommunityUser] = []
    @Published var sharedLocations: [CommunityLocation] = []
    @Published var accessibilityTips: [AccessibilityTip] = []
    @Published var assistanceRequests: [AssistanceRequest] = []
    @Published var communityEvents: [CommunityEvent] = []
    @Published var businessRatings: [BusinessRating] = []
    @Published var isOnline = false
    @Published var currentLocation: CLLocation?
    
    private let cloudSync = CloudSyncManager()
    private let speechOutput = SpeechOutput()
    private let locationManager = CLLocationManager()
    private var userProfile: UserProfile?
    
    // Real-time communication
    private var webSocket: URLSessionWebSocketTask?
    private var volunteerNetwork: VolunteerNetwork?
    private var emergencyResponse: EmergencyResponseSystem?
    
    // Community settings
    private let maxNearbyDistance: Double = 1000 // 1km radius
    private let assistanceTimeout: TimeInterval = 300 // 5 minutes
    private var backgroundSyncTimer: Timer?
    
    override init() {
        super.init()
        setupCommunityPlatform()
        setupLocationServices()
        setupRealTimeCommunication()
    }
    
    deinit {
        disconnectFromCommunity()
    }
    
    // MARK: - Setup and Configuration
    
    private func setupCommunityPlatform() {
        volunteerNetwork = VolunteerNetwork()
        emergencyResponse = EmergencyResponseSystem()
        
        // Load user profile
        loadUserProfile()
        
        Config.debugLog("Community platform initialized")
    }
    
    private func setupLocationServices() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.requestWhenInUseAuthorization()
        
        if CLLocationManager.locationServicesEnabled() {
            locationManager.startUpdatingLocation()
        }
    }
    
    private func setupRealTimeCommunication() {
        connectToCommunityServer()
        startBackgroundSync()
    }
    
    private func loadUserProfile() {
        // Load user profile from local storage or create new one
        if let profileData = UserDefaults.standard.data(forKey: "UserProfile"),
           let profile = try? JSONDecoder().decode(UserProfile.self, from: profileData) {
            userProfile = profile
        } else {
            createNewUserProfile()
        }
    }
    
    private func createNewUserProfile() {
        userProfile = UserProfile(
            id: UUID(),
            name: "KaiSight User",
            isVolunteer: false,
            skillLevel: .beginner,
            preferredLanguages: ["en"],
            accessibilityNeeds: [],
            trustScore: 0.0,
            joinDate: Date()
        )
        
        saveUserProfile()
    }
    
    private func saveUserProfile() {
        guard let profile = userProfile,
              let profileData = try? JSONEncoder().encode(profile) else { return }
        
        UserDefaults.standard.set(profileData, forKey: "UserProfile")
    }
    
    // MARK: - Location & Tip Sharing
    
    func shareLocationTip(at location: CLLocation, title: String, description: String, category: TipCategory) {
        let tip = AccessibilityTip(
            id: UUID(),
            title: title,
            description: description,
            location: location,
            category: category,
            submittedBy: userProfile?.id ?? UUID(),
            rating: 0.0,
            votes: 0,
            timestamp: Date()
        )
        
        // Save locally
        accessibilityTips.append(tip)
        
        // Share with community
        cloudSync.shareAccessibilityTip(tip) { [weak self] success in
            DispatchQueue.main.async {
                if success {
                    self?.speechOutput.speak("Location tip shared with community")
                } else {
                    self?.speechOutput.speak("Failed to share tip. Will try again later.")
                }
            }
        }
        
        Config.debugLog("Shared accessibility tip: \(title)")
    }
    
    func loadNearbyTips(completion: @escaping ([AccessibilityTip]) -> Void) {
        guard let location = currentLocation else {
            completion([])
            return
        }
        
        let region = CLCircularRegion(center: location.coordinate, radius: maxNearbyDistance, identifier: "nearby")
        
        cloudSync.getAccessibilityTips(in: region) { [weak self] tips in
            DispatchQueue.main.async {
                self?.accessibilityTips = tips
                completion(tips)
            }
        }
    }
    
    func rateTip(_ tip: AccessibilityTip, rating: Double) {
        cloudSync.rateTip(tip.id, rating: rating) { [weak self] success in
            if success {
                self?.speechOutput.speak("Thank you for rating this tip")
            }
        }
    }
    
    // MARK: - Business Accessibility Ratings
    
    func rateBusiness(name: String, location: CLLocation, overallRating: Double, features: [AccessibilityFeature]) {
        let rating = BusinessRating(
            id: UUID(),
            businessName: name,
            location: location,
            overallRating: overallRating,
            accessibilityFeatures: features,
            submittedBy: userProfile?.id ?? UUID(),
            timestamp: Date()
        )
        
        businessRatings.append(rating)
        
        cloudSync.shareBusinessRating(rating) { [weak self] success in
            DispatchQueue.main.async {
                if success {
                    self?.speechOutput.speak("Business rating submitted. Thank you for helping the community!")
                } else {
                    self?.speechOutput.speak("Failed to submit rating. Will try again later.")
                }
            }
        }
    }
    
    func getBusinessRatings(near location: CLLocation, completion: @escaping ([BusinessRating]) -> Void) {
        let region = CLCircularRegion(center: location.coordinate, radius: maxNearbyDistance, identifier: "business")
        
        cloudSync.getBusinessRatings(in: region) { ratings in
            DispatchQueue.main.async {
                completion(ratings)
            }
        }
    }
    
    // MARK: - Peer-to-Peer Assistance
    
    func requestAssistance(type: AssistanceType, description: String, urgency: UrgencyLevel = .normal) {
        guard let location = currentLocation, let userID = userProfile?.id else {
            speechOutput.speak("Unable to request assistance. Location not available.")
            return
        }
        
        let request = AssistanceRequest(
            id: UUID(),
            requesterID: userID,
            location: location,
            type: type,
            description: description,
            urgency: urgency,
            status: .pending,
            timestamp: Date()
        )
        
        assistanceRequests.append(request)
        
        // Broadcast to nearby volunteers
        broadcastAssistanceRequest(request)
        
        // Start timeout timer
        startAssistanceTimeout(for: request)
        
        speechOutput.speak("Assistance request sent to nearby volunteers")
        Config.debugLog("Assistance request broadcast: \(type)")
    }
    
    func respondToAssistanceRequest(_ request: AssistanceRequest, response: VolunteerResponse) {
        guard let userID = userProfile?.id else { return }
        
        let volunteerResponse = VolunteerResponseData(
            requestID: request.id,
            volunteerID: userID,
            response: response,
            estimatedArrival: calculateArrivalTime(to: request.location),
            timestamp: Date()
        )
        
        sendVolunteerResponse(volunteerResponse)
        
        switch response {
        case .accept:
            speechOutput.speak("Assistance accepted. Notifying requester.")
            startVolunteerNavigation(to: request.location)
        case .decline:
            speechOutput.speak("Assistance declined.")
        case .busy:
            speechOutput.speak("Marked as busy.")
        }
    }
    
    func cancelAssistanceRequest(_ requestID: UUID) {
        assistanceRequests.removeAll { $0.id == requestID }
        broadcastCancellation(requestID)
        speechOutput.speak("Assistance request cancelled")
    }
    
    // MARK: - Community Events
    
    func createCommunityEvent(title: String, description: String, location: CLLocation, startTime: Date, type: EventType) {
        guard let userID = userProfile?.id else { return }
        
        let event = CommunityEvent(
            id: UUID(),
            title: title,
            description: description,
            location: location,
            startTime: startTime,
            type: type,
            organizerID: userID,
            attendees: [userID],
            maxAttendees: 20,
            timestamp: Date()
        )
        
        communityEvents.append(event)
        
        cloudSync.createCommunityEvent(event) { [weak self] success in
            DispatchQueue.main.async {
                if success {
                    self?.speechOutput.speak("Community event created successfully")
                } else {
                    self?.speechOutput.speak("Failed to create event")
                }
            }
        }
    }
    
    func joinCommunityEvent(_ event: CommunityEvent) {
        guard let userID = userProfile?.id else { return }
        
        cloudSync.joinEvent(event.id, userID: userID) { [weak self] success in
            DispatchQueue.main.async {
                if success {
                    self?.speechOutput.speak("Successfully joined \(event.title)")
                    self?.scheduleEventReminder(for: event)
                } else {
                    self?.speechOutput.speak("Failed to join event")
                }
            }
        }
    }
    
    func loadNearbyEvents(completion: @escaping ([CommunityEvent]) -> Void) {
        guard let location = currentLocation else {
            completion([])
            return
        }
        
        let region = CLCircularRegion(center: location.coordinate, radius: maxNearbyDistance * 5, identifier: "events")
        
        cloudSync.getCommunityEvents(in: region) { [weak self] events in
            DispatchQueue.main.async {
                self?.communityEvents = events
                completion(events)
            }
        }
    }
    
    // MARK: - Volunteer Network
    
    func registerAsVolunteer(skills: [VolunteerSkill], availabilityHours: [Int]) {
        guard var profile = userProfile else { return }
        
        profile.isVolunteer = true
        profile.volunteerSkills = skills
        profile.availabilityHours = availabilityHours
        
        self.userProfile = profile
        saveUserProfile()
        
        volunteerNetwork?.registerVolunteer(profile)
        
        speechOutput.speak("Thank you for volunteering! You're now part of the KaiSight community support network.")
        Config.debugLog("User registered as volunteer with skills: \(skills)")
    }
    
    func setVolunteerAvailability(_ available: Bool) {
        guard var profile = userProfile else { return }
        
        profile.isAvailable = available
        self.userProfile = profile
        saveUserProfile()
        
        volunteerNetwork?.updateAvailability(profile.id, available: available)
        
        speechOutput.speak(available ? "You're now available for assistance requests" : "Volunteer availability turned off")
    }
    
    func findNearbyVolunteers(completion: @escaping ([CommunityUser]) -> Void) {
        guard let location = currentLocation else {
            completion([])
            return
        }
        
        volunteerNetwork?.findNearbyVolunteers(location: location, radius: maxNearbyDistance) { volunteers in
            DispatchQueue.main.async {
                completion(volunteers)
            }
        }
    }
    
    // MARK: - Real-Time Communication
    
    private func connectToCommunityServer() {
        guard let url = URL(string: "wss://community.kaisight.com/live") else { return }
        
        let request = URLRequest(url: url)
        webSocket = URLSession.shared.webSocketTask(with: request)
        webSocket?.resume()
        
        setupWebSocketMessageHandling()
        
        isOnline = true
        Config.debugLog("Connected to community server")
    }
    
    private func setupWebSocketMessageHandling() {
        webSocket?.receive { [weak self] result in
            switch result {
            case .success(let message):
                self?.handleWebSocketMessage(message)
            case .failure(let error):
                Config.debugLog("WebSocket error: \(error)")
                self?.reconnectToCommunityServer()
            }
            
            // Continue listening
            self?.setupWebSocketMessageHandling()
        }
    }
    
    private func handleWebSocketMessage(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .string(let text):
            if let data = text.data(using: .utf8),
               let communityMessage = try? JSONDecoder().decode(CommunityMessage.self, from: data) {
                processCommunityMessage(communityMessage)
            }
        case .data(let data):
            if let communityMessage = try? JSONDecoder().decode(CommunityMessage.self, from: data) {
                processCommunityMessage(communityMessage)
            }
        @unknown default:
            break
        }
    }
    
    private func processCommunityMessage(_ message: CommunityMessage) {
        DispatchQueue.main.async {
            switch message.type {
            case .assistanceRequest:
                self.handleIncomingAssistanceRequest(message)
            case .assistanceResponse:
                self.handleAssistanceResponse(message)
            case .locationUpdate:
                self.handleLocationUpdate(message)
            case .emergencyAlert:
                self.handleEmergencyAlert(message)
            case .tipUpdate:
                self.handleTipUpdate(message)
            }
        }
    }
    
    private func broadcastAssistanceRequest(_ request: AssistanceRequest) {
        let message = CommunityMessage(
            id: UUID(),
            type: .assistanceRequest,
            senderID: userProfile?.id ?? UUID(),
            content: try? JSONEncoder().encode(request),
            timestamp: Date()
        )
        
        sendWebSocketMessage(message)
    }
    
    private func sendVolunteerResponse(_ response: VolunteerResponseData) {
        let message = CommunityMessage(
            id: UUID(),
            type: .assistanceResponse,
            senderID: userProfile?.id ?? UUID(),
            content: try? JSONEncoder().encode(response),
            timestamp: Date()
        )
        
        sendWebSocketMessage(message)
    }
    
    private func sendWebSocketMessage(_ message: CommunityMessage) {
        guard let webSocket = webSocket,
              let messageData = try? JSONEncoder().encode(message),
              let messageString = String(data: messageData, encoding: .utf8) else { return }
        
        webSocket.send(.string(messageString)) { error in
            if let error = error {
                Config.debugLog("Failed to send message: \(error)")
            }
        }
    }
    
    // MARK: - Message Handlers
    
    private func handleIncomingAssistanceRequest(_ message: CommunityMessage) {
        guard let data = message.content,
              let request = try? JSONDecoder().decode(AssistanceRequest.self, from: data),
              userProfile?.isVolunteer == true,
              userProfile?.isAvailable == true else { return }
        
        // Check if user is nearby and can help
        if let currentLocation = currentLocation,
           currentLocation.distance(from: request.location) <= maxNearbyDistance {
            
            assistanceRequests.append(request)
            
            // Notify volunteer of request
            let urgencyText = request.urgency == .emergency ? "EMERGENCY " : ""
            speechOutput.speak("\(urgencyText)Assistance request nearby: \(request.description). Say 'help' to respond.", priority: .high)
            
            // Show visual notification if needed
            showAssistanceNotification(request)
        }
    }
    
    private func handleAssistanceResponse(_ message: CommunityMessage) {
        guard let data = message.content,
              let response = try? JSONDecoder().decode(VolunteerResponseData.self, from: data) else { return }
        
        // Find matching request
        if let requestIndex = assistanceRequests.firstIndex(where: { $0.id == response.requestID }) {
            var request = assistanceRequests[requestIndex]
            
            switch response.response {
            case .accept:
                request.status = .accepted
                speechOutput.speak("A volunteer is coming to help you! Estimated arrival: \(formatTime(response.estimatedArrival))")
            case .decline, .busy:
                // Continue looking for other volunteers
                break
            }
            
            assistanceRequests[requestIndex] = request
        }
    }
    
    private func handleLocationUpdate(_ message: CommunityMessage) {
        // Handle real-time location updates from other community members
        Config.debugLog("Received location update")
    }
    
    private func handleEmergencyAlert(_ message: CommunityMessage) {
        guard let data = message.content,
              let alert = try? JSONDecoder().decode(EmergencyAlert.self, from: data) else { return }
        
        speechOutput.speak("EMERGENCY ALERT: \(alert.description) nearby. Volunteers needed.", priority: .emergency)
        
        // Auto-respond if user is volunteer and available
        if userProfile?.isVolunteer == true && userProfile?.isAvailable == true {
            speechOutput.speak("Do you want to respond to this emergency? Say 'respond' to help.")
        }
    }
    
    private func handleTipUpdate(_ message: CommunityMessage) {
        // Handle new accessibility tips from community
        loadNearbyTips { _ in
            // Tips updated
        }
    }
    
    // MARK: - Emergency Response System
    
    func triggerEmergencyAlert(description: String) {
        guard let location = currentLocation, let userID = userProfile?.id else { return }
        
        let alert = EmergencyAlert(
            id: UUID(),
            userID: userID,
            location: location,
            description: description,
            severity: .high,
            timestamp: Date()
        )
        
        emergencyResponse?.broadcastEmergencyAlert(alert)
        
        speechOutput.speak("Emergency alert sent to nearby volunteers and emergency services")
        Config.debugLog("Emergency alert triggered: \(description)")
    }
    
    // MARK: - Utility Methods
    
    private func startBackgroundSync() {
        backgroundSyncTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
            self.syncCommunityData()
        }
    }
    
    private func syncCommunityData() {
        loadNearbyTips { _ in }
        loadNearbyEvents { _ in }
        findNearbyVolunteers { volunteers in
            self.nearbyUsers = volunteers
        }
    }
    
    private func disconnectFromCommunity() {
        webSocket?.cancel()
        backgroundSyncTimer?.invalidate()
        isOnline = false
    }
    
    private func reconnectToCommunityServer() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            self.connectToCommunityServer()
        }
    }
    
    private func calculateArrivalTime(to location: CLLocation) -> TimeInterval {
        guard let currentLocation = currentLocation else { return 900 } // 15 minutes default
        
        let distance = currentLocation.distance(from: location)
        let walkingSpeed: Double = 1.4 // m/s average walking speed
        
        return distance / walkingSpeed
    }
    
    private func startAssistanceTimeout(for request: AssistanceRequest) {
        DispatchQueue.main.asyncAfter(deadline: .now() + assistanceTimeout) {
            // Check if request is still pending
            if let index = self.assistanceRequests.firstIndex(where: { $0.id == request.id && $0.status == .pending }) {
                self.assistanceRequests[index].status = .timeout
                self.speechOutput.speak("Assistance request timed out. You may want to try again or contact emergency services.")
            }
        }
    }
    
    private func startVolunteerNavigation(to location: CLLocation) {
        // Start navigation to assistance location
        // This would integrate with NavigationAssistant
        Config.debugLog("Starting navigation to assistance location")
    }
    
    private func scheduleEventReminder(for event: CommunityEvent) {
        // Schedule local notification for event
        Config.debugLog("Scheduled reminder for event: \(event.title)")
    }
    
    private func showAssistanceNotification(_ request: AssistanceRequest) {
        // Show visual notification for assistance request
        Config.debugLog("Showing assistance notification")
    }
    
    private func formatTime(_ timeInterval: TimeInterval) -> String {
        let minutes = Int(timeInterval / 60)
        return "\(minutes) minute\(minutes == 1 ? "" : "s")"
    }
    
    private func broadcastCancellation(_ requestID: UUID) {
        let cancellation = AssistanceCancellation(requestID: requestID, timestamp: Date())
        
        let message = CommunityMessage(
            id: UUID(),
            type: .assistanceResponse,
            senderID: userProfile?.id ?? UUID(),
            content: try? JSONEncoder().encode(cancellation),
            timestamp: Date()
        )
        
        sendWebSocketMessage(message)
    }
    
    // MARK: - Public Interface
    
    func getCommunityStatus() -> String {
        var status = ""
        
        if isOnline {
            status += "Connected to community. "
        } else {
            status += "Offline. "
        }
        
        if !nearbyUsers.isEmpty {
            status += "\(nearbyUsers.count) community members nearby. "
        }
        
        if !assistanceRequests.isEmpty {
            let pendingRequests = assistanceRequests.filter { $0.status == .pending }.count
            if pendingRequests > 0 {
                status += "\(pendingRequests) assistance request\(pendingRequests == 1 ? "" : "s") active. "
            }
        }
        
        if userProfile?.isVolunteer == true {
            status += "Volunteer mode \(userProfile?.isAvailable == true ? "active" : "inactive"). "
        }
        
        return status.isEmpty ? "Community features ready" : status
    }
    
    func speakCommunityStatus() {
        let status = getCommunityStatus()
        speechOutput.speak(status)
    }
}

// MARK: - CLLocationManagerDelegate

extension CommunityManager: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        currentLocation = location
        
        // Update community with new location if sharing is enabled
        if userProfile?.sharesLocation == true {
            updateLocationWithCommunity(location)
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Config.debugLog("Location update failed: \(error)")
    }
    
    private func updateLocationWithCommunity(_ location: CLLocation) {
        let locationUpdate = LocationUpdate(
            userID: userProfile?.id ?? UUID(),
            location: location,
            timestamp: Date()
        )
        
        let message = CommunityMessage(
            id: UUID(),
            type: .locationUpdate,
            senderID: userProfile?.id ?? UUID(),
            content: try? JSONEncoder().encode(locationUpdate),
            timestamp: Date()
        )
        
        sendWebSocketMessage(message)
    }
}

// MARK: - Data Models

struct CommunityUser: Identifiable, Codable {
    let id: UUID
    let name: String
    let isVolunteer: Bool
    let isAvailable: Bool
    let location: CLLocation?
    let skillLevel: SkillLevel
    let trustScore: Double
    let volunteerSkills: [VolunteerSkill]?
    
    enum CodingKeys: String, CodingKey {
        case id, name, isVolunteer, isAvailable, skillLevel, trustScore, volunteerSkills
    }
}

struct UserProfile: Codable {
    let id: UUID
    var name: String
    var isVolunteer: Bool
    var isAvailable: Bool = false
    var sharesLocation: Bool = false
    var skillLevel: SkillLevel
    var preferredLanguages: [String]
    var accessibilityNeeds: [AccessibilityNeed]
    var trustScore: Double
    var volunteerSkills: [VolunteerSkill] = []
    var availabilityHours: [Int] = []
    let joinDate: Date
}

struct CommunityLocation: Identifiable, Codable {
    let id: UUID
    let name: String
    let location: CLLocation
    let description: String
    let category: LocationCategory
    let accessibilityFeatures: [AccessibilityFeature]
    let sharedBy: UUID
    let rating: Double
    let timestamp: Date
}

struct AccessibilityTip: Identifiable, Codable {
    let id: UUID
    let title: String
    let description: String
    let location: CLLocation
    let category: TipCategory
    let submittedBy: UUID
    var rating: Double
    var votes: Int
    let timestamp: Date
}

struct AssistanceRequest: Identifiable, Codable {
    let id: UUID
    let requesterID: UUID
    let location: CLLocation
    let type: AssistanceType
    let description: String
    let urgency: UrgencyLevel
    var status: RequestStatus
    let timestamp: Date
}

struct CommunityEvent: Identifiable, Codable {
    let id: UUID
    let title: String
    let description: String
    let location: CLLocation
    let startTime: Date
    let type: EventType
    let organizerID: UUID
    var attendees: [UUID]
    let maxAttendees: Int
    let timestamp: Date
}

struct BusinessRating: Identifiable, Codable {
    let id: UUID
    let businessName: String
    let location: CLLocation
    let overallRating: Double
    let accessibilityFeatures: [AccessibilityFeature]
    let submittedBy: UUID
    let timestamp: Date
}

struct VolunteerResponseData: Codable {
    let requestID: UUID
    let volunteerID: UUID
    let response: VolunteerResponse
    let estimatedArrival: TimeInterval
    let timestamp: Date
}

struct CommunityMessage: Identifiable, Codable {
    let id: UUID
    let type: MessageType
    let senderID: UUID
    let content: Data?
    let timestamp: Date
}

struct EmergencyAlert: Identifiable, Codable {
    let id: UUID
    let userID: UUID
    let location: CLLocation
    let description: String
    let severity: AlertSeverity
    let timestamp: Date
}

struct LocationUpdate: Codable {
    let userID: UUID
    let location: CLLocation
    let timestamp: Date
}

struct AssistanceCancellation: Codable {
    let requestID: UUID
    let timestamp: Date
}

// MARK: - Enums

enum SkillLevel: String, Codable, CaseIterable {
    case beginner = "beginner"
    case intermediate = "intermediate"
    case advanced = "advanced"
    case expert = "expert"
}

enum TipCategory: String, Codable, CaseIterable {
    case navigation = "navigation"
    case transportation = "transportation"
    case shopping = "shopping"
    case dining = "dining"
    case safety = "safety"
    case accessibility = "accessibility"
}

enum AssistanceType: String, Codable, CaseIterable {
    case navigation = "navigation"
    case reading = "reading"
    case identification = "identification"
    case emergency = "emergency"
    case shopping = "shopping"
    case technology = "technology"
}

enum UrgencyLevel: String, Codable, CaseIterable {
    case low = "low"
    case normal = "normal"
    case high = "high"
    case emergency = "emergency"
}

enum RequestStatus: String, Codable {
    case pending = "pending"
    case accepted = "accepted"
    case inProgress = "in_progress"
    case completed = "completed"
    case cancelled = "cancelled"
    case timeout = "timeout"
}

enum EventType: String, Codable, CaseIterable {
    case social = "social"
    case educational = "educational"
    case navigation = "navigation"
    case support = "support"
}

enum VolunteerResponse: String, Codable {
    case accept = "accept"
    case decline = "decline"
    case busy = "busy"
}

enum MessageType: String, Codable {
    case assistanceRequest = "assistance_request"
    case assistanceResponse = "assistance_response"
    case locationUpdate = "location_update"
    case emergencyAlert = "emergency_alert"
    case tipUpdate = "tip_update"
}

enum AlertSeverity: String, Codable {
    case low = "low"
    case medium = "medium"
    case high = "high"
    case critical = "critical"
}

enum LocationCategory: String, Codable, CaseIterable {
    case restaurant = "restaurant"
    case store = "store"
    case transportation = "transportation"
    case medical = "medical"
    case government = "government"
    case recreation = "recreation"
}

enum AccessibilityFeature: String, Codable, CaseIterable {
    case wheelchairAccessible = "wheelchair_accessible"
    case audioDescription = "audio_description"
    case brailleMenu = "braille_menu"
    case guideDogFriendly = "guide_dog_friendly"
    case tactileIndicators = "tactile_indicators"
    case accessibleParking = "accessible_parking"
    case audioSignals = "audio_signals"
}

enum AccessibilityNeed: String, Codable, CaseIterable {
    case blindness = "blindness"
    case lowVision = "low_vision"
    case deafBlind = "deaf_blind"
    case mobility = "mobility"
    case cognitive = "cognitive"
}

enum VolunteerSkill: String, Codable, CaseIterable {
    case navigation = "navigation"
    case reading = "reading"
    case technology = "technology"
    case emergency = "emergency"
    case translation = "translation"
    case shopping = "shopping"
}

// MARK: - Network Classes

class VolunteerNetwork {
    func registerVolunteer(_ profile: UserProfile) {
        Config.debugLog("Volunteer registered: \(profile.name)")
    }
    
    func updateAvailability(_ userID: UUID, available: Bool) {
        Config.debugLog("Volunteer availability updated: \(available)")
    }
    
    func findNearbyVolunteers(location: CLLocation, radius: Double, completion: @escaping ([CommunityUser]) -> Void) {
        // Find volunteers within radius
        completion([]) // Placeholder
    }
}

class EmergencyResponseSystem {
    func broadcastEmergencyAlert(_ alert: EmergencyAlert) {
        Config.debugLog("Emergency alert broadcast: \(alert.description)")
    }
}

// MARK: - CloudSync Extensions

extension CloudSyncManager {
    func shareAccessibilityTip(_ tip: AccessibilityTip, completion: @escaping (Bool) -> Void) {
        // Share tip with community
        completion(true) // Placeholder
    }
    
    func getAccessibilityTips(in region: CLCircularRegion, completion: @escaping ([AccessibilityTip]) -> Void) {
        // Get tips in region
        completion([]) // Placeholder
    }
    
    func rateTip(_ tipID: UUID, rating: Double, completion: @escaping (Bool) -> Void) {
        // Submit tip rating
        completion(true) // Placeholder
    }
    
    func shareBusinessRating(_ rating: BusinessRating, completion: @escaping (Bool) -> Void) {
        // Share business rating
        completion(true) // Placeholder
    }
    
    func getBusinessRatings(in region: CLCircularRegion, completion: @escaping ([BusinessRating]) -> Void) {
        // Get business ratings in region
        completion([]) // Placeholder
    }
    
    func createCommunityEvent(_ event: CommunityEvent, completion: @escaping (Bool) -> Void) {
        // Create community event
        completion(true) // Placeholder
    }
    
    func joinEvent(_ eventID: UUID, userID: UUID, completion: @escaping (Bool) -> Void) {
        // Join community event
        completion(true) // Placeholder
    }
    
    func getCommunityEvents(in region: CLCircularRegion, completion: @escaping ([CommunityEvent]) -> Void) {
        // Get events in region
        completion([]) // Placeholder
    }
}

// MARK: - CLLocation Codable Extension

extension CLLocation: Codable {
    enum CodingKeys: String, CodingKey {
        case latitude, longitude, altitude, horizontalAccuracy, verticalAccuracy, timestamp
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(coordinate.latitude, forKey: .latitude)
        try container.encode(coordinate.longitude, forKey: .longitude)
        try container.encode(altitude, forKey: .altitude)
        try container.encode(horizontalAccuracy, forKey: .horizontalAccuracy)
        try container.encode(verticalAccuracy, forKey: .verticalAccuracy)
        try container.encode(timestamp, forKey: .timestamp)
    }
    
    public convenience init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let latitude = try container.decode(CLLocationDegrees.self, forKey: .latitude)
        let longitude = try container.decode(CLLocationDegrees.self, forKey: .longitude)
        let altitude = try container.decode(CLLocationDistance.self, forKey: .altitude)
        let horizontalAccuracy = try container.decode(CLLocationAccuracy.self, forKey: .horizontalAccuracy)
        let verticalAccuracy = try container.decode(CLLocationAccuracy.self, forKey: .verticalAccuracy)
        let timestamp = try container.decode(Date.self, forKey: .timestamp)
        
        self.init(
            coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            altitude: altitude,
            horizontalAccuracy: horizontalAccuracy,
            verticalAccuracy: verticalAccuracy,
            timestamp: timestamp
        )
    }
} 