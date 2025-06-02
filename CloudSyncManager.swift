import Foundation
import CloudKit
import Combine

class CloudSyncManager: ObservableObject {
    @Published var syncStatus: SyncStatus = .idle
    @Published var lastSyncDate: Date?
    @Published var cloudAccountStatus: CloudAccountStatus = .unknown
    @Published var syncProgress: Double = 0.0
    
    private let container: CKContainer
    private let privateDatabase: CKDatabase
    private let publicDatabase: CKDatabase
    private var syncOperations: [CKOperation] = []
    private var cancellables = Set<AnyCancellable>()
    
    // Data managers
    private let familiarRecognition = FamiliarRecognition()
    private let spatialMapping = SpatialMappingManager()
    private let navigationAssistant = NavigationAssistant()
    
    // Sync settings
    private let syncInterval: TimeInterval = 300 // 5 minutes
    private var backgroundSyncTimer: Timer?
    private var isInitialSyncComplete = false
    
    // Record types
    private let recordTypes = [
        "UserSettings",
        "FamiliarFace",
        "FamiliarObject", 
        "SpatialAnchor",
        "SavedLocation",
        "VoiceCommand",
        "UserProfile"
    ]
    
    init() {
        container = CKContainer.default()
        privateDatabase = container.privateCloudDatabase
        publicDatabase = container.publicCloudDatabase
        
        setupCloudSync()
        checkAccountStatus()
    }
    
    deinit {
        stopBackgroundSync()
    }
    
    // MARK: - Setup
    
    private func setupCloudSync() {
        // Check CloudKit availability
        container.accountStatus { [weak self] status, error in
            DispatchQueue.main.async {
                if let error = error {
                    Config.debugLog("CloudKit account error: \(error)")
                    self?.cloudAccountStatus = .error
                } else {
                    switch status {
                    case .available:
                        self?.cloudAccountStatus = .available
                        self?.initializeCloudSync()
                    case .noAccount:
                        self?.cloudAccountStatus = .noAccount
                    case .restricted:
                        self?.cloudAccountStatus = .restricted
                    case .couldNotDetermine:
                        self?.cloudAccountStatus = .unknown
                    @unknown default:
                        self?.cloudAccountStatus = .unknown
                    }
                }
            }
        }
        
        // Setup subscription for remote changes
        setupRemoteChangeNotifications()
    }
    
    private func initializeCloudSync() {
        Config.debugLog("Initializing CloudKit sync")
        
        // Perform initial sync
        performInitialSync()
        
        // Start background sync
        startBackgroundSync()
    }
    
    private func checkAccountStatus() {
        container.accountStatus { [weak self] status, error in
            DispatchQueue.main.async {
                self?.updateAccountStatus(status, error: error)
            }
        }
    }
    
    private func updateAccountStatus(_ status: CKAccountStatus, error: Error?) {
        if let error = error {
            Config.debugLog("CloudKit status error: \(error)")
            cloudAccountStatus = .error
            return
        }
        
        switch status {
        case .available:
            cloudAccountStatus = .available
        case .noAccount:
            cloudAccountStatus = .noAccount
        case .restricted:
            cloudAccountStatus = .restricted
        case .couldNotDetermine:
            cloudAccountStatus = .unknown
        @unknown default:
            cloudAccountStatus = .unknown
        }
    }
    
    // MARK: - Sync Operations
    
    func startManualSync() {
        guard cloudAccountStatus == .available else {
            Config.debugLog("Cannot sync: CloudKit not available")
            return
        }
        
        guard syncStatus != .syncing else {
            Config.debugLog("Sync already in progress")
            return
        }
        
        performFullSync()
    }
    
    private func performInitialSync() {
        guard !isInitialSyncComplete else { return }
        
        syncStatus = .syncing
        syncProgress = 0.0
        
        Config.debugLog("Starting initial CloudKit sync")
        
        // Download existing data first
        downloadAllRecords { [weak self] success in
            if success {
                // Then upload local data
                self?.uploadAllLocalData { uploadSuccess in
                    DispatchQueue.main.async {
                        self?.isInitialSyncComplete = true
                        self?.syncStatus = uploadSuccess ? .completed : .failed
                        self?.lastSyncDate = Date()
                        self?.syncProgress = 1.0
                        Config.debugLog("Initial sync completed: \(uploadSuccess)")
                    }
                }
            } else {
                DispatchQueue.main.async {
                    self?.syncStatus = .failed
                    self?.syncProgress = 0.0
                }
            }
        }
    }
    
    private func performFullSync() {
        syncStatus = .syncing
        syncProgress = 0.0
        
        let syncGroup = DispatchGroup()
        var successCount = 0
        let totalOperations = recordTypes.count * 2 // Upload and download for each type
        
        // Sync each record type
        for recordType in recordTypes {
            // Download changes
            syncGroup.enter()
            downloadRecords(ofType: recordType) { success in
                if success { successCount += 1 }
                DispatchQueue.main.async {
                    self.syncProgress = Double(successCount) / Double(totalOperations)
                }
                syncGroup.leave()
            }
            
            // Upload changes
            syncGroup.enter()
            uploadRecords(ofType: recordType) { success in
                if success { successCount += 1 }
                DispatchQueue.main.async {
                    self.syncProgress = Double(successCount) / Double(totalOperations)
                }
                syncGroup.leave()
            }
        }
        
        syncGroup.notify(queue: .main) {
            self.syncStatus = successCount > totalOperations / 2 ? .completed : .failed
            self.lastSyncDate = Date()
            self.syncProgress = 1.0
            Config.debugLog("Full sync completed. Success rate: \(successCount)/\(totalOperations)")
        }
    }
    
    // MARK: - Upload Operations
    
    private func uploadAllLocalData(completion: @escaping (Bool) -> Void) {
        let uploadGroup = DispatchGroup()
        var uploadResults: [Bool] = []
        
        // Upload user settings
        uploadGroup.enter()
        uploadUserSettings { result in
            uploadResults.append(result)
            uploadGroup.leave()
        }
        
        // Upload familiar faces
        uploadGroup.enter()
        uploadFamiliarFaces { result in
            uploadResults.append(result)
            uploadGroup.leave()
        }
        
        // Upload familiar objects
        uploadGroup.enter()
        uploadFamiliarObjects { result in
            uploadResults.append(result)
            uploadGroup.leave()
        }
        
        // Upload spatial anchors
        uploadGroup.enter()
        uploadSpatialAnchors { result in
            uploadResults.append(result)
            uploadGroup.leave()
        }
        
        // Upload saved locations
        uploadGroup.enter()
        uploadSavedLocations { result in
            uploadResults.append(result)
            uploadGroup.leave()
        }
        
        uploadGroup.notify(queue: .main) {
            let successCount = uploadResults.filter { $0 }.count
            completion(successCount > uploadResults.count / 2)
        }
    }
    
    private func uploadUserSettings(completion: @escaping (Bool) -> Void) {
        let settings = gatherUserSettings()
        let record = createUserSettingsRecord(from: settings)
        
        saveRecord(record) { result in
            completion(result != nil)
        }
    }
    
    private func uploadFamiliarFaces(completion: @escaping (Bool) -> Void) {
        let faces = familiarRecognition.getFamiliarFaces()
        let records = faces.map { createFamiliarFaceRecord(from: $0) }
        
        saveRecords(records) { results in
            let successCount = results.compactMap { $0 }.count
            completion(successCount > 0)
        }
    }
    
    private func uploadFamiliarObjects(completion: @escaping (Bool) -> Void) {
        let objects = familiarRecognition.getFamiliarObjects()
        let records = objects.map { createFamiliarObjectRecord(from: $0) }
        
        saveRecords(records) { results in
            let successCount = results.compactMap { $0 }.count
            completion(successCount > 0)
        }
    }
    
    private func uploadSpatialAnchors(completion: @escaping (Bool) -> Void) {
        let anchors = spatialMapping.spatialAnchors
        let records = anchors.map { createSpatialAnchorRecord(from: $0) }
        
        saveRecords(records) { results in
            let successCount = results.compactMap { $0 }.count
            completion(successCount > 0)
        }
    }
    
    private func uploadSavedLocations(completion: @escaping (Bool) -> Void) {
        let locations = navigationAssistant.getSavedLocations()
        let records = locations.map { createSavedLocationRecord(from: $0) }
        
        saveRecords(records) { results in
            let successCount = results.compactMap { $0 }.count
            completion(successCount > 0)
        }
    }
    
    // MARK: - Download Operations
    
    private func downloadAllRecords(completion: @escaping (Bool) -> Void) {
        let downloadGroup = DispatchGroup()
        var downloadResults: [Bool] = []
        
        for recordType in recordTypes {
            downloadGroup.enter()
            downloadRecords(ofType: recordType) { result in
                downloadResults.append(result)
                downloadGroup.leave()
            }
        }
        
        downloadGroup.notify(queue: .main) {
            let successCount = downloadResults.filter { $0 }.count
            completion(successCount > downloadResults.count / 2)
        }
    }
    
    private func downloadRecords(ofType recordType: String, completion: @escaping (Bool) -> Void) {
        let query = CKQuery(recordType: recordType, predicate: NSPredicate(value: true))
        
        privateDatabase.perform(query, inZoneWith: nil) { [weak self] records, error in
            if let error = error {
                Config.debugLog("Download error for \(recordType): \(error)")
                completion(false)
                return
            }
            
            guard let records = records else {
                completion(true) // No records is success
                return
            }
            
            self?.processDownloadedRecords(records, ofType: recordType)
            completion(true)
        }
    }
    
    private func processDownloadedRecords(_ records: [CKRecord], ofType recordType: String) {
        switch recordType {
        case "UserSettings":
            processUserSettingsRecords(records)
        case "FamiliarFace":
            processFamiliarFaceRecords(records)
        case "FamiliarObject":
            processFamiliarObjectRecords(records)
        case "SpatialAnchor":
            processSpatialAnchorRecords(records)
        case "SavedLocation":
            processSavedLocationRecords(records)
        default:
            Config.debugLog("Unknown record type: \(recordType)")
        }
    }
    
    // MARK: - Record Processing
    
    private func processUserSettingsRecords(_ records: [CKRecord]) {
        for record in records {
            if let settingsData = record["settingsData"] as? Data {
                do {
                    let settings = try JSONDecoder().decode(UserSettingsBackup.self, from: settingsData)
                    applyUserSettings(settings)
                } catch {
                    Config.debugLog("Failed to decode user settings: \(error)")
                }
            }
        }
    }
    
    private func processFamiliarFaceRecords(_ records: [CKRecord]) {
        for record in records {
            if let faceData = record["faceData"] as? Data,
               let name = record["name"] as? String {
                familiarRecognition.addFamiliarFaceFromCloud(data: faceData, name: name)
            }
        }
    }
    
    private func processFamiliarObjectRecords(_ records: [CKRecord]) {
        for record in records {
            if let objectData = record["objectData"] as? Data,
               let name = record["name"] as? String,
               let description = record["description"] as? String {
                familiarRecognition.addFamiliarObjectFromCloud(data: objectData, name: name, description: description)
            }
        }
    }
    
    private func processSpatialAnchorRecords(_ records: [CKRecord]) {
        for record in records {
            if let anchorData = record["anchorData"] as? Data {
                do {
                    let anchor = try JSONDecoder().decode(SpatialAnchor.self, from: anchorData)
                    spatialMapping.addSpatialAnchorFromCloud(anchor)
                } catch {
                    Config.debugLog("Failed to decode spatial anchor: \(error)")
                }
            }
        }
    }
    
    private func processSavedLocationRecords(_ records: [CKRecord]) {
        for record in records {
            if let locationData = record["locationData"] as? Data {
                do {
                    let location = try JSONDecoder().decode(SavedLocation.self, from: locationData)
                    navigationAssistant.addSavedLocationFromCloud(location)
                } catch {
                    Config.debugLog("Failed to decode saved location: \(error)")
                }
            }
        }
    }
    
    // MARK: - Record Creation
    
    private func createUserSettingsRecord(from settings: UserSettingsBackup) -> CKRecord {
        let record = CKRecord(recordType: "UserSettings")
        
        do {
            let settingsData = try JSONEncoder().encode(settings)
            record["settingsData"] = settingsData
            record["lastModified"] = Date()
        } catch {
            Config.debugLog("Failed to encode user settings: \(error)")
        }
        
        return record
    }
    
    private func createFamiliarFaceRecord(from face: FamiliarFace) -> CKRecord {
        let record = CKRecord(recordType: "FamiliarFace")
        record["name"] = face.name
        record["faceData"] = face.encodingData
        record["dateAdded"] = face.dateAdded
        record["lastSeen"] = face.lastSeen
        return record
    }
    
    private func createFamiliarObjectRecord(from object: FamiliarObject) -> CKRecord {
        let record = CKRecord(recordType: "FamiliarObject")
        record["name"] = object.name
        record["description"] = object.description
        record["objectData"] = object.encodingData
        record["dateAdded"] = object.dateAdded
        return record
    }
    
    private func createSpatialAnchorRecord(from anchor: SpatialAnchor) -> CKRecord {
        let record = CKRecord(recordType: "SpatialAnchor")
        
        do {
            let anchorData = try JSONEncoder().encode(anchor)
            record["anchorData"] = anchorData
            record["name"] = anchor.name
            record["timestamp"] = anchor.timestamp
        } catch {
            Config.debugLog("Failed to encode spatial anchor: \(error)")
        }
        
        return record
    }
    
    private func createSavedLocationRecord(from location: SavedLocation) -> CKRecord {
        let record = CKRecord(recordType: "SavedLocation")
        
        do {
            let locationData = try JSONEncoder().encode(location)
            record["locationData"] = locationData
            record["name"] = location.name
            record["dateAdded"] = location.dateAdded
        } catch {
            Config.debugLog("Failed to encode saved location: \(error)")
        }
        
        return record
    }
    
    // MARK: - CloudKit Operations
    
    private func saveRecord(_ record: CKRecord, completion: @escaping (CKRecord?) -> Void) {
        privateDatabase.save(record) { savedRecord, error in
            if let error = error {
                Config.debugLog("Save record error: \(error)")
                completion(nil)
            } else {
                completion(savedRecord)
            }
        }
    }
    
    private func saveRecords(_ records: [CKRecord], completion: @escaping ([CKRecord?]) -> Void) {
        let operation = CKModifyRecordsOperation(recordsToSave: records, recordIDsToDelete: nil)
        
        operation.modifyRecordsCompletionBlock = { savedRecords, deletedRecordIDs, error in
            if let error = error {
                Config.debugLog("Batch save error: \(error)")
                completion(Array(repeating: nil, count: records.count))
            } else {
                completion(savedRecords ?? [])
            }
        }
        
        privateDatabase.add(operation)
    }
    
    private func uploadRecords(ofType recordType: String, completion: @escaping (Bool) -> Void) {
        switch recordType {
        case "UserSettings":
            uploadUserSettings(completion: completion)
        case "FamiliarFace":
            uploadFamiliarFaces(completion: completion)
        case "FamiliarObject":
            uploadFamiliarObjects(completion: completion)
        case "SpatialAnchor":
            uploadSpatialAnchors(completion: completion)
        case "SavedLocation":
            uploadSavedLocations(completion: completion)
        default:
            completion(false)
        }
    }
    
    // MARK: - Background Sync
    
    private func startBackgroundSync() {
        backgroundSyncTimer = Timer.scheduledTimer(withTimeInterval: syncInterval, repeats: true) { _ in
            if self.cloudAccountStatus == .available && self.syncStatus != .syncing {
                self.performIncrementalSync()
            }
        }
    }
    
    private func stopBackgroundSync() {
        backgroundSyncTimer?.invalidate()
        backgroundSyncTimer = nil
    }
    
    private func performIncrementalSync() {
        guard let lastSync = lastSyncDate else {
            performFullSync()
            return
        }
        
        // Only sync changes since last sync
        let changesSince = lastSync.addingTimeInterval(-60) // 1 minute buffer
        syncChangesSince(changesSince)
    }
    
    private func syncChangesSince(_ date: Date) {
        let predicate = NSPredicate(format: "modificationDate > %@", date as NSDate)
        
        for recordType in recordTypes {
            let query = CKQuery(recordType: recordType, predicate: predicate)
            
            privateDatabase.perform(query, inZoneWith: nil) { [weak self] records, error in
                if let records = records, !records.isEmpty {
                    self?.processDownloadedRecords(records, ofType: recordType)
                }
            }
        }
        
        lastSyncDate = Date()
    }
    
    // MARK: - Remote Change Notifications
    
    private func setupRemoteChangeNotifications() {
        let subscription = CKDatabaseSubscription(subscriptionID: "kaisight-changes")
        
        let notificationInfo = CKSubscription.NotificationInfo()
        notificationInfo.shouldSendContentAvailable = true
        subscription.notificationInfo = notificationInfo
        
        privateDatabase.save(subscription) { _, error in
            if let error = error {
                Config.debugLog("Subscription setup error: \(error)")
            } else {
                Config.debugLog("CloudKit subscription created successfully")
            }
        }
    }
    
    // MARK: - Data Gathering
    
    private func gatherUserSettings() -> UserSettingsBackup {
        return UserSettingsBackup(
            speechRate: 0.5, // Get from actual settings
            speechVolume: 1.0,
            recordingDuration: 5.0,
            navigationVoice: true,
            hapticFeedback: true,
            voiceCommands: getCustomVoiceCommands(),
            lastBackup: Date()
        )
    }
    
    private func getCustomVoiceCommands() -> [String] {
        // Return user's custom voice commands
        return []
    }
    
    private func applyUserSettings(_ settings: UserSettingsBackup) {
        // Apply downloaded settings to the app
        Config.debugLog("Applying user settings from cloud")
    }
    
    // MARK: - Public Interface
    
    func getSyncStatusDescription() -> String {
        switch syncStatus {
        case .idle:
            return "Ready to sync"
        case .syncing:
            return "Syncing... \(Int(syncProgress * 100))%"
        case .completed:
            if let lastSync = lastSyncDate {
                return "Last synced: \(formatDate(lastSync))"
            }
            return "Sync completed"
        case .failed:
            return "Sync failed"
        }
    }
    
    func getCloudAccountDescription() -> String {
        switch cloudAccountStatus {
        case .available:
            return "iCloud account active"
        case .noAccount:
            return "No iCloud account"
        case .restricted:
            return "iCloud access restricted"
        case .error:
            return "iCloud error"
        case .unknown:
            return "Checking iCloud status..."
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Data Models

enum SyncStatus {
    case idle
    case syncing
    case completed
    case failed
}

enum CloudAccountStatus {
    case available
    case noAccount
    case restricted
    case error
    case unknown
}

struct UserSettingsBackup: Codable {
    let speechRate: Double
    let speechVolume: Double
    let recordingDuration: Double
    let navigationVoice: Bool
    let hapticFeedback: Bool
    let voiceCommands: [String]
    let lastBackup: Date
}

// MARK: - Extensions

extension FamiliarRecognition {
    func getFamiliarFaces() -> [FamiliarFace] {
        // Return familiar faces for sync
        return []
    }
    
    func getFamiliarObjects() -> [FamiliarObject] {
        // Return familiar objects for sync
        return []
    }
    
    func addFamiliarFaceFromCloud(data: Data, name: String) {
        // Add face from cloud data
    }
    
    func addFamiliarObjectFromCloud(data: Data, name: String, description: String) {
        // Add object from cloud data
    }
}

extension SpatialMappingManager {
    func addSpatialAnchorFromCloud(_ anchor: SpatialAnchor) {
        // Add spatial anchor from cloud
    }
}

extension NavigationAssistant {
    func getSavedLocations() -> [SavedLocation] {
        // Return saved locations for sync
        return []
    }
    
    func addSavedLocationFromCloud(_ location: SavedLocation) {
        // Add saved location from cloud
    }
}

struct FamiliarFace {
    let name: String
    let encodingData: Data
    let dateAdded: Date
    let lastSeen: Date?
}

struct FamiliarObject {
    let name: String
    let description: String
    let encodingData: Data
    let dateAdded: Date
}

struct SavedLocation: Codable {
    let name: String
    let latitude: Double
    let longitude: Double
    let description: String
    let dateAdded: Date
} 