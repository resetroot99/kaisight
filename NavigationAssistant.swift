import Foundation
import CoreLocation
import MapKit
import Contacts

class NavigationAssistant: NSObject, ObservableObject {
    private let locationManager = CLLocationManager()
    private let geocoder = CLGeocoder()
    
    @Published var currentLocation: CLLocation?
    @Published var currentAddress: String = ""
    @Published var heading: CLLocationDirection = 0
    @Published var isNavigating = false
    @Published var navigationInstructions: [String] = []
    @Published var emergencyContacts: [EmergencyContact] = []
    @Published var locationHistory: [SavedLocation] = []
    
    private var destination: CLLocation?
    private var lastAnnouncedDistance: Double = 0
    private var startingLocation: CLLocation? // Where user began their journey
    private var homeLocation: CLLocation? // User's home address
    
    struct LocationInfo {
        let address: String
        let landmark: String?
        let distance: Double
        let direction: String
    }
    
    struct EmergencyContact {
        let id = UUID()
        let name: String
        let phoneNumber: String
        let relationship: String
        var lastKnownLocation: CLLocation?
        var isLocationShared: Bool = false
    }
    
    struct SavedLocation {
        let id = UUID()
        let name: String
        let location: CLLocation
        let timestamp: Date
        let category: LocationCategory
    }
    
    enum LocationCategory {
        case home
        case work
        case frequentPlace
        case startingPoint
        case emergency
    }
    
    override init() {
        super.init()
        setupLocationManager()
        loadSavedData()
    }
    
    private func setupLocationManager() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 1.0 // Update every meter
        
        // Request permission
        locationManager.requestWhenInUseAuthorization()
        
        // Start location updates if authorized
        if CLLocationManager.locationServicesEnabled() {
            locationManager.startUpdatingLocation()
            locationManager.startUpdatingHeading()
        }
    }
    
    private func loadSavedData() {
        // Load saved contacts and locations from UserDefaults
        loadEmergencyContacts()
        loadSavedLocations()
        loadHomeLocation()
    }
    
    // MARK: - Return/Home Navigation
    
    func saveStartingLocation() {
        guard let location = currentLocation else { return }
        startingLocation = location
        
        let savedLocation = SavedLocation(
            name: "Starting Point",
            location: location,
            timestamp: Date(),
            category: .startingPoint
        )
        locationHistory.insert(savedLocation, at: 0)
        
        // Keep only last 10 locations
        if locationHistory.count > 10 {
            locationHistory.removeLast()
        }
        
        saveSavedLocations()
    }
    
    func returnToStartingPoint(completion: @escaping (String) -> Void) {
        guard let startingPoint = startingLocation else {
            completion("No starting point saved. Please save your starting location first.")
            return
        }
        
        startNavigation(to: startingPoint, destinationName: "your starting point", completion: completion)
    }
    
    func returnHome(completion: @escaping (String) -> Void) {
        guard let home = homeLocation else {
            completion("Home location not set. Please set your home address in settings.")
            return
        }
        
        startNavigation(to: home, destinationName: "home", completion: completion)
    }
    
    func setHomeLocation(_ address: String, completion: @escaping (String) -> Void) {
        geocoder.geocodeAddressString(address) { [weak self] placemarks, error in
            guard let placemark = placemarks?.first,
                  let location = placemark.location else {
                completion("Could not find location for: \(address)")
                return
            }
            
            self?.homeLocation = location
            self?.saveHomeLocation()
            
            let savedLocation = SavedLocation(
                name: "Home",
                location: location,
                timestamp: Date(),
                category: .home
            )
            
            // Remove any existing home location
            self?.locationHistory.removeAll { $0.category == .home }
            self?.locationHistory.insert(savedLocation, at: 0)
            self?.saveSavedLocations()
            
            completion("Home location set to \(address)")
        }
    }
    
    // MARK: - Family/Friend Location Features
    
    func addEmergencyContact(name: String, phoneNumber: String, relationship: String) {
        let contact = EmergencyContact(
            name: name,
            phoneNumber: phoneNumber,
            relationship: relationship
        )
        emergencyContacts.append(contact)
        saveEmergencyContacts()
    }
    
    func findNearestEmergencyContact(completion: @escaping (String) -> Void) {
        guard let currentLocation = currentLocation else {
            completion("Current location not available.")
            return
        }
        
        let contactsWithLocation = emergencyContacts.filter { $0.isLocationShared && $0.lastKnownLocation != nil }
        
        guard !contactsWithLocation.isEmpty else {
            completion("No emergency contacts are sharing their location. Please ask them to enable location sharing.")
            return
        }
        
        var nearestContact: EmergencyContact?
        var shortestDistance: Double = Double.infinity
        
        for contact in contactsWithLocation {
            if let contactLocation = contact.lastKnownLocation {
                let distance = currentLocation.distance(from: contactLocation)
                if distance < shortestDistance {
                    shortestDistance = distance
                    nearestContact = contact
                }
            }
        }
        
        guard let nearest = nearestContact, let location = nearest.lastKnownLocation else {
            completion("Could not find location for any contacts.")
            return
        }
        
        let distance = formatDistance(shortestDistance)
        let direction = getDirectionDescription(
            from: currentLocation.coordinate,
            to: location.coordinate
        )
        
        completion("Nearest contact is \(nearest.name) (\(nearest.relationship)), \(distance) \(direction.lowercased()). Would you like directions?")
    }
    
    func navigateToContact(_ contactName: String, completion: @escaping (String) -> Void) {
        guard let contact = emergencyContacts.first(where: { $0.name.lowercased().contains(contactName.lowercased()) }),
              let contactLocation = contact.lastKnownLocation else {
            completion("Contact \(contactName) not found or location not available.")
            return
        }
        
        startNavigation(to: contactLocation, destinationName: "\(contact.name) (\(contact.relationship))", completion: completion)
    }
    
    func shareLocationWithContacts() -> String {
        guard let location = currentLocation else {
            return "Current location not available to share."
        }
        
        // In a real app, this would integrate with Messages or other sharing apps
        let coordinates = "\(location.coordinate.latitude),\(location.coordinate.longitude)"
        let message = "I'm at: \(currentAddress). GPS: \(coordinates). Sent from BlindAssistant."
        
        return "Location ready to share: \(message)"
    }
    
    // MARK: - Emergency Features
    
    func requestEmergencyHelp(completion: @escaping (String) -> Void) {
        guard let location = currentLocation else {
            completion("Location not available for emergency services.")
            return
        }
        
        var emergencyMessage = "EMERGENCY: I need help. "
        emergencyMessage += "My location: \(currentAddress). "
        emergencyMessage += "GPS coordinates: \(location.coordinate.latitude), \(location.coordinate.longitude). "
        emergencyMessage += "Please assist. Sent from BlindAssistant app."
        
        // Save emergency location
        let emergencyLocation = SavedLocation(
            name: "Emergency Location",
            location: location,
            timestamp: Date(),
            category: .emergency
        )
        locationHistory.insert(emergencyLocation, at: 0)
        saveSavedLocations()
        
        completion(emergencyMessage)
    }
    
    func getLocationBreadcrumbs() -> String {
        guard !locationHistory.isEmpty else {
            return "No location history available."
        }
        
        var breadcrumbs = "Recent locations: "
        let recentLocations = Array(locationHistory.prefix(3))
        
        for (index, savedLocation) in recentLocations.enumerated() {
            let timeAgo = formatTimeAgo(savedLocation.timestamp)
            breadcrumbs += "\(savedLocation.name) (\(timeAgo))"
            
            if index < recentLocations.count - 1 {
                breadcrumbs += ", "
            }
        }
        
        return breadcrumbs
    }
    
    // MARK: - Enhanced Navigation
    
    func getDetailedDirections(to destinationName: String, completion: @escaping (String) -> Void) {
        guard let currentLocation = currentLocation else {
            completion("Current location not available.")
            return
        }
        
        // Check saved locations first
        if let savedLocation = locationHistory.first(where: { $0.name.lowercased().contains(destinationName.lowercased()) }) {
            let distance = currentLocation.distance(from: savedLocation.location)
            let direction = getDirectionDescription(
                from: currentLocation.coordinate,
                to: savedLocation.location.coordinate
            )
            
            completion("Directions to \(savedLocation.name): \(formatDistance(distance)) \(direction.lowercased()). Would you like to start navigation?")
            return
        }
        
        // Fallback to regular geocoding
        navigateToAddress(destinationName, completion: completion)
    }
    
    // MARK: - Existing Methods (Enhanced)
    
    func getCurrentLocationDescription(completion: @escaping (String) -> Void) {
        guard let location = currentLocation else {
            completion("Location not available. Please ensure location services are enabled.")
            return
        }
        
        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, error in
            guard let placemark = placemarks?.first else {
                completion("Unable to determine current location.")
                return
            }
            
            var description = "You are currently "
            
            if let name = placemark.name {
                description += "at \(name), "
            }
            
            if let thoroughfare = placemark.thoroughfare {
                description += "on \(thoroughfare), "
            }
            
            if let locality = placemark.locality {
                description += "in \(locality), "
            }
            
            if let administrativeArea = placemark.administrativeArea {
                description += "\(administrativeArea)."
            }
            
            // Add heading information
            let headingDescription = self?.getHeadingDescription() ?? ""
            if !headingDescription.isEmpty {
                description += " You are facing \(headingDescription)."
            }
            
            // Add distance from home if available
            if let home = self?.homeLocation {
                let distanceFromHome = location.distance(from: home)
                if distanceFromHome > 100 { // Only mention if more than 100m from home
                    description += " You are \(self?.formatDistance(distanceFromHome) ?? "") from home."
                }
            }
            
            DispatchQueue.main.async {
                self?.currentAddress = description
                completion(description)
            }
        }
    }
    
    func findNearbyPlaces(completion: @escaping ([LocationInfo]) -> Void) {
        guard let location = currentLocation else {
            completion([])
            return
        }
        
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = "restaurants, stores, banks, pharmacies"
        request.region = MKCoordinateRegion(
            center: location.coordinate,
            latitudinalMeters: 500,
            longitudinalMeters: 500
        )
        
        let search = MKLocalSearch(request: request)
        search.start { [weak self] response, error in
            guard let response = response else {
                completion([])
                return
            }
            
            let places = response.mapItems.prefix(5).compactMap { item -> LocationInfo? in
                guard let location = self?.currentLocation else { return nil }
                
                let distance = location.distance(from: CLLocation(
                    latitude: item.placemark.coordinate.latitude,
                    longitude: item.placemark.coordinate.longitude
                ))
                
                let direction = self?.getDirectionDescription(
                    from: location.coordinate,
                    to: item.placemark.coordinate
                ) ?? ""
                
                return LocationInfo(
                    address: item.placemark.name ?? "Unknown location",
                    landmark: item.placemark.thoroughfare,
                    distance: distance,
                    direction: direction
                )
            }
            
            completion(places)
        }
    }
    
    func navigateToAddress(_ address: String, completion: @escaping (String) -> Void) {
        geocoder.geocodeAddressString(address) { [weak self] placemarks, error in
            guard let placemark = placemarks?.first,
                  let location = placemark.location else {
                completion("Could not find location for: \(address)")
                return
            }
            
            self?.startNavigation(to: location, destinationName: address, completion: completion)
        }
    }
    
    private func startNavigation(to destination: CLLocation, destinationName: String, completion: @escaping (String) -> Void) {
        guard let currentLocation = currentLocation else {
            completion("Current location not available.")
            return
        }
        
        self.destination = destination
        self.isNavigating = true
        
        let distance = currentLocation.distance(from: destination)
        let direction = getDirectionDescription(
            from: currentLocation.coordinate,
            to: destination.coordinate
        )
        
        let initialInstruction = "Navigation started to \(destinationName). Distance: \(formatDistance(distance)). Direction: \(direction)."
        
        navigationInstructions = [initialInstruction]
        completion(initialInstruction)
        
        // Start continuous navigation updates
        monitorNavigationProgress()
    }
    
    private func monitorNavigationProgress() {
        guard isNavigating, let destination = destination, let currentLocation = currentLocation else {
            return
        }
        
        let distance = currentLocation.distance(from: destination)
        
        // Announce distance milestones
        if shouldAnnounceDistance(distance) {
            let instruction = "You are \(formatDistance(distance)) from your destination."
            navigationInstructions.append(instruction)
            lastAnnouncedDistance = distance
        }
        
        // Arrival detection
        if distance < 10 {
            let instruction = "You have arrived at your destination."
            navigationInstructions.append(instruction)
            stopNavigation()
        }
    }
    
    private func shouldAnnounceDistance(_ distance: Double) -> Bool {
        let announcementThresholds: [Double] = [1000, 500, 200, 100, 50, 20]
        
        for threshold in announcementThresholds {
            if distance <= threshold && lastAnnouncedDistance > threshold {
                return true
            }
        }
        
        return false
    }
    
    func stopNavigation() {
        isNavigating = false
        destination = nil
        lastAnnouncedDistance = 0
        navigationInstructions.removeAll()
    }
    
    private func getHeadingDescription() -> String {
        let directions = [
            "North", "Northeast", "East", "Southeast",
            "South", "Southwest", "West", "Northwest"
        ]
        
        let index = Int((heading + 22.5) / 45.0) % 8
        return directions[index]
    }
    
    private func getDirectionDescription(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> String {
        let deltaLat = to.latitude - from.latitude
        let deltaLon = to.longitude - from.longitude
        
        let bearing = atan2(deltaLon, deltaLat) * 180 / .pi
        let normalizedBearing = bearing < 0 ? bearing + 360 : bearing
        
        let directions = [
            "North", "Northeast", "East", "Southeast",
            "South", "Southwest", "West", "Northwest"
        ]
        
        let index = Int((normalizedBearing + 22.5) / 45.0) % 8
        return directions[index]
    }
    
    private func formatDistance(_ distance: Double) -> String {
        if distance < 1000 {
            return "\(Int(distance)) meters"
        } else {
            let kilometers = distance / 1000
            return String(format: "%.1f kilometers", kilometers)
        }
    }
    
    private func formatTimeAgo(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        
        if interval < 60 {
            return "just now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes) minute\(minutes == 1 ? "" : "s") ago"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours) hour\(hours == 1 ? "" : "s") ago"
        } else {
            let days = Int(interval / 86400)
            return "\(days) day\(days == 1 ? "" : "s") ago"
        }
    }
    
    func getNavigationSummary() -> String {
        guard isNavigating, let destination = destination, let currentLocation = currentLocation else {
            return "No active navigation."
        }
        
        let distance = currentLocation.distance(from: destination)
        let direction = getDirectionDescription(
            from: currentLocation.coordinate,
            to: destination.coordinate
        )
        
        return "Navigating: \(formatDistance(distance)) \(direction.lowercased())"
    }
    
    // MARK: - Data Persistence
    
    private func saveEmergencyContacts() {
        if let data = try? JSONEncoder().encode(emergencyContacts) {
            UserDefaults.standard.set(data, forKey: "EmergencyContacts")
        }
    }
    
    private func loadEmergencyContacts() {
        if let data = UserDefaults.standard.data(forKey: "EmergencyContacts"),
           let contacts = try? JSONDecoder().decode([EmergencyContact].self, from: data) {
            emergencyContacts = contacts
        }
    }
    
    private func saveSavedLocations() {
        if let data = try? JSONEncoder().encode(locationHistory) {
            UserDefaults.standard.set(data, forKey: "SavedLocations")
        }
    }
    
    private func loadSavedLocations() {
        if let data = UserDefaults.standard.data(forKey: "SavedLocations"),
           let locations = try? JSONDecoder().decode([SavedLocation].self, from: data) {
            locationHistory = locations
        }
    }
    
    private func saveHomeLocation() {
        if let homeLocation = homeLocation,
           let data = try? JSONEncoder().encode(homeLocation) {
            UserDefaults.standard.set(data, forKey: "HomeLocation")
        }
    }
    
    private func loadHomeLocation() {
        if let data = UserDefaults.standard.data(forKey: "HomeLocation"),
           let location = try? JSONDecoder().decode(CLLocation.self, from: data) {
            homeLocation = location
        }
    }
}

// MARK: - Codable Extensions

extension NavigationAssistant.EmergencyContact: Codable {}
extension NavigationAssistant.SavedLocation: Codable {}
extension NavigationAssistant.LocationCategory: Codable {}

extension CLLocation: Codable {
    enum CodingKeys: String, CodingKey {
        case latitude, longitude
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(coordinate.latitude, forKey: .latitude)
        try container.encode(coordinate.longitude, forKey: .longitude)
    }
    
    public convenience init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let latitude = try container.decode(Double.self, forKey: .latitude)
        let longitude = try container.decode(Double.self, forKey: .longitude)
        self.init(latitude: latitude, longitude: longitude)
    }
}

extension NavigationAssistant: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        
        currentLocation = location
        
        if isNavigating {
            monitorNavigationProgress()
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        heading = newHeading.magneticHeading
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    }
    
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            locationManager.startUpdatingLocation()
            locationManager.startUpdatingHeading()
        case .denied, .restricted:
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        @unknown default:
            break
        }
    }
} 