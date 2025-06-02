import Foundation
import CloudKit
import CryptoKit
import Combine

class EnhancedCloudSyncManager: ObservableObject {
    @Published var syncStatus: SyncStatus = .idle
    @Published var lastSyncDate: Date?
    @Published var syncProgress: Double = 0.0
    @Published var conflictCount = 0
    @Published var encryptionEnabled = true
    
    // CloudKit containers
    private let privateContainer: CKContainer
    private let publicContainer: CKContainer
    private let sharedContainer: CKContainer
    
    // Encryption
    private let encryptionManager = DataEncryptionManager()
    private let keychain = KeychainManager()
    
    // Sync coordination
    private let syncQueue = DispatchQueue(label: "sync.queue", qos: .utility)
    private let conflictResolver = ConflictResolver()
    private var syncTimer: Timer?
    private let syncInterval: TimeInterval = 300 // 5 minutes
    
    // Data managers
    private var pendingChanges: [SyncableChange] = []
    private var syncMetadata: [String: SyncMetadata] = [:]
    
    // Offline support
    private let offlineStorage = OfflineStorageManager()
    private var isOffline = false
    
    // Error handling and retry
    private var retryManager = RetryManager()
    
    init() {
        privateContainer = CKContainer.default()
        publicContainer = CKContainer(identifier: "iCloud.com.kaisight.public")
        sharedContainer = CKContainer(identifier: "iCloud.com.kaisight.shared")
        
        setupCloudSync()
    }
    
    // MARK: - Setup
    
    private func setupCloudSync() {
        setupEncryption()
        checkCloudKitAvailability()
        setupSubscriptions()
        loadPendingChanges()
        startPeriodicSync()
        
        Config.debugLog("Enhanced cloud sync manager initialized")
    }
    
    private func setupEncryption() {
        // Generate or load encryption keys
        encryptionManager.initializeKeys { [weak self] success in
            if success {
                self?.encryptionEnabled = true
                Config.debugLog("Encryption initialized successfully")
            } else {
                self?.encryptionEnabled = false
                Config.debugLog("Encryption initialization failed")
            }
        }
    }
    
    private func checkCloudKitAvailability() {
        privateContainer.accountStatus { [weak self] status, error in
            DispatchQueue.main.async {
                switch status {
                case .available:
                    self?.syncStatus = .available
                    self?.performInitialSync()
                case .noAccount:
                    self?.syncStatus = .noAccount
                case .restricted, .temporarilyUnavailable:
                    self?.syncStatus = .unavailable
                case .couldNotDetermine:
                    self?.syncStatus = .error("Could not determine CloudKit status")
                @unknown default:
                    self?.syncStatus = .error("Unknown CloudKit status")
                }
                
                if let error = error {
                    self?.syncStatus = .error(error.localizedDescription)
                }
            }
        }
    }
    
    private func setupSubscriptions() {
        // Create CloudKit subscriptions for real-time updates
        setupPrivateSubscription()
        setupSharedSubscription()
    }
    
    private func setupPrivateSubscription() {
        let subscription = CKQuerySubscription(
            recordType: "UserData",
            predicate: NSPredicate(value: true),
            options: [.firesOnRecordCreation, .firesOnRecordUpdate, .firesOnRecordDeletion]
        )
        
        let notificationInfo = CKSubscription.NotificationInfo()
        notificationInfo.shouldSendContentAvailable = true
        subscription.notificationInfo = notificationInfo
        
        privateContainer.privateCloudDatabase.save(subscription) { _, error in
            if let error = error {
                Config.debugLog("Failed to create private subscription: \(error)")
            } else {
                Config.debugLog("Private subscription created successfully")
            }
        }
    }
    
    private func setupSharedSubscription() {
        let subscription = CKQuerySubscription(
            recordType: "SharedData",
            predicate: NSPredicate(value: true),
            options: [.firesOnRecordCreation, .firesOnRecordUpdate, .firesOnRecordDeletion]
        )
        
        let notificationInfo = CKSubscription.NotificationInfo()
        notificationInfo.shouldSendContentAvailable = true
        subscription.notificationInfo = notificationInfo
        
        sharedContainer.sharedCloudDatabase.save(subscription) { _, error in
            if let error = error {
                Config.debugLog("Failed to create shared subscription: \(error)")
            } else {
                Config.debugLog("Shared subscription created successfully")
            }
        }
    }
    
    private func startPeriodicSync() {
        syncTimer = Timer.scheduledTimer(withTimeInterval: syncInterval, repeats: true) { _ in
            self.performPeriodicSync()
        }
    }
    
    // MARK: - Core Sync Operations
    
    func syncData<T: SyncableData>(_ data: T, to container: SyncContainer = .private) async throws {
        guard syncStatus == .available else {
            throw SyncError.unavailable
        }
        
        syncStatus = .syncing
        
        do {
            // Encrypt data if enabled
            let processedData = try await processDataForSync(data)
            
            // Create CloudKit record
            let record = try createCloudKitRecord(from: processedData, container: container)
            
            // Save to CloudKit
            let savedRecord = try await saveRecord(record, to: container)
            
            // Update metadata
            updateSyncMetadata(for: data.id, record: savedRecord)
            
            syncStatus = .available
            lastSyncDate = Date()
            
        } catch {
            syncStatus = .error(error.localizedDescription)
            
            // Store for offline sync
            await storeForOfflineSync(data, operation: .create)
            throw error
        }
    }
    
    func fetchData<T: SyncableData>(ofType type: T.Type, from container: SyncContainer = .private) async throws -> [T] {
        guard syncStatus == .available else {
            // Return offline data if available
            return await offlineStorage.loadData(ofType: type)
        }
        
        syncStatus = .syncing
        
        do {
            let database = getDatabase(for: container)
            let query = CKQuery(recordType: String(describing: type), predicate: NSPredicate(value: true))
            
            let records = try await database.records(matching: query).matchResults.compactMap { result in
                try? result.1.get()
            }
            
            var decryptedData: [T] = []
            
            for record in records {
                if let data = try await decryptAndParseData(record, as: type) {
                    decryptedData.append(data)
                }
            }
            
            // Cache for offline use
            await offlineStorage.saveData(decryptedData)
            
            syncStatus = .available
            return decryptedData
            
        } catch {
            syncStatus = .error(error.localizedDescription)
            
            // Return offline data as fallback
            return await offlineStorage.loadData(ofType: type)
        }
    }
    
    func deleteData<T: SyncableData>(_ data: T, from container: SyncContainer = .private) async throws {
        guard syncStatus == .available else {
            await storeForOfflineSync(data, operation: .delete)
            return
        }
        
        syncStatus = .syncing
        
        do {
            let database = getDatabase(for: container)
            let recordID = CKRecord.ID(recordName: data.id.uuidString)
            
            try await database.deleteRecord(withID: recordID)
            
            // Remove from metadata
            syncMetadata.removeValue(forKey: data.id.uuidString)
            
            syncStatus = .available
            lastSyncDate = Date()
            
        } catch {
            syncStatus = .error(error.localizedDescription)
            await storeForOfflineSync(data, operation: .delete)
            throw error
        }
    }
    
    // MARK: - Conflict Resolution
    
    private func resolveConflicts() async {
        let conflicts = await detectConflicts()
        
        for conflict in conflicts {
            let resolution = await conflictResolver.resolve(conflict)
            await applyConflictResolution(resolution)
        }
        
        DispatchQueue.main.async {
            self.conflictCount = 0
        }
    }
    
    private func detectConflicts() async -> [DataConflict] {
        var conflicts: [DataConflict] = []
        
        // Check for conflicts in different data types
        conflicts.append(contentsOf: await detectSpatialAnchorConflicts())
        conflicts.append(contentsOf: await detectFaceIdentityConflicts())
        conflicts.append(contentsOf: await detectMemoryConflicts())
        
        return conflicts
    }
    
    private func detectSpatialAnchorConflicts() async -> [DataConflict] {
        // Compare local and remote spatial anchors for conflicts
        return []
    }
    
    private func detectFaceIdentityConflicts() async -> [DataConflict] {
        // Compare local and remote face identities for conflicts
        return []
    }
    
    private func detectMemoryConflicts() async -> [DataConflict] {
        // Compare local and remote memories for conflicts
        return []
    }
    
    private func applyConflictResolution(_ resolution: ConflictResolution) async {
        switch resolution.strategy {
        case .useLocal:
            // Keep local version, sync to cloud
            if let localData = resolution.localData {
                try? await syncData(localData)
            }
            
        case .useRemote:
            // Use remote version, update local
            if let remoteData = resolution.remoteData {
                await offlineStorage.updateLocalData(remoteData)
            }
            
        case .merge:
            // Merge both versions
            if let mergedData = resolution.mergedData {
                try? await syncData(mergedData)
                await offlineStorage.updateLocalData(mergedData)
            }
            
        case .userChoice:
            // Present conflict to user for manual resolution
            await presentConflictToUser(resolution.conflict)
        }
    }
    
    private func presentConflictToUser(_ conflict: DataConflict) async {
        DispatchQueue.main.async {
            self.conflictCount += 1
            // In a real app, this would show a UI for user to resolve conflict
            Config.debugLog("Conflict requires user resolution: \(conflict.description)")
        }
    }
    
    // MARK: - Encryption and Security
    
    private func processDataForSync<T: SyncableData>(_ data: T) async throws -> SyncableData {
        if encryptionEnabled {
            return try await encryptionManager.encrypt(data)
        } else {
            return data
        }
    }
    
    private func decryptAndParseData<T: SyncableData>(_ record: CKRecord, as type: T.Type) async throws -> T? {
        if encryptionEnabled {
            return try await encryptionManager.decrypt(record, as: type)
        } else {
            return try parseRecord(record, as: type)
        }
    }
    
    private func parseRecord<T: SyncableData>(_ record: CKRecord, as type: T.Type) throws -> T? {
        // Parse CloudKit record into SyncableData
        // Implementation depends on specific data types
        return nil
    }
    
    // MARK: - Offline Support
    
    private func storeForOfflineSync<T: SyncableData>(_ data: T, operation: SyncOperation) async {
        let change = SyncableChange(
            id: UUID(),
            dataId: data.id,
            operation: operation,
            data: data,
            timestamp: Date(),
            retryCount: 0
        )
        
        pendingChanges.append(change)
        await offlineStorage.savePendingChange(change)
    }
    
    private func syncPendingChanges() async {
        guard !pendingChanges.isEmpty && syncStatus == .available else { return }
        
        var successfulChanges: [UUID] = []
        
        for change in pendingChanges {
            do {
                switch change.operation {
                case .create, .update:
                    try await syncData(change.data)
                case .delete:
                    try await deleteData(change.data)
                }
                
                successfulChanges.append(change.id)
                
            } catch {
                // Increment retry count
                if let index = pendingChanges.firstIndex(where: { $0.id == change.id }) {
                    pendingChanges[index].retryCount += 1
                    
                    // Remove if exceeded retry limit
                    if pendingChanges[index].retryCount > 5 {
                        successfulChanges.append(change.id)
                        Config.debugLog("Abandoning sync for change \(change.id) after 5 retries")
                    }
                }
            }
        }
        
        // Remove successful changes
        pendingChanges.removeAll { successfulChanges.contains($0.id) }
        await offlineStorage.removePendingChanges(successfulChanges)
    }
    
    // MARK: - Periodic and Background Sync
    
    private func performPeriodicSync() {
        guard syncStatus == .available else { return }
        
        Task {
            await performFullSync()
        }
    }
    
    private func performInitialSync() {
        Task {
            await performFullSync()
        }
    }
    
    private func performFullSync() async {
        syncStatus = .syncing
        syncProgress = 0.0
        
        do {
            // Sync pending changes first
            await syncPendingChanges()
            syncProgress = 0.2
            
            // Sync spatial data
            try await syncSpatialData()
            syncProgress = 0.4
            
            // Sync recognition data
            try await syncRecognitionData()
            syncProgress = 0.6
            
            // Sync memory data
            try await syncMemoryData()
            syncProgress = 0.8
            
            // Resolve any conflicts
            await resolveConflicts()
            syncProgress = 1.0
            
            DispatchQueue.main.async {
                self.syncStatus = .available
                self.lastSyncDate = Date()
                self.syncProgress = 0.0
            }
            
        } catch {
            DispatchQueue.main.async {
                self.syncStatus = .error(error.localizedDescription)
                self.syncProgress = 0.0
            }
        }
    }
    
    private func syncSpatialData() async throws {
        // Sync spatial anchors, room geometry, etc.
        let spatialAnchors: [SpatialAnchor] = try await fetchData(ofType: SpatialAnchor.self)
        await offlineStorage.saveData(spatialAnchors)
    }
    
    private func syncRecognitionData() async throws {
        // Sync face identities and custom objects
        let faceIdentities: [FaceIdentity] = try await fetchData(ofType: FaceIdentity.self)
        let customObjects: [CustomObjectIdentity] = try await fetchData(ofType: CustomObjectIdentity.self)
        
        await offlineStorage.saveData(faceIdentities)
        await offlineStorage.saveData(customObjects)
    }
    
    private func syncMemoryData() async throws {
        // Sync RAG memories
        let episodicMemories: [EpisodicMemory] = try await fetchData(ofType: EpisodicMemory.self)
        let semanticMemories: [SemanticMemory] = try await fetchData(ofType: SemanticMemory.self)
        let locationMemories: [LocationMemory] = try await fetchData(ofType: LocationMemory.self)
        
        await offlineStorage.saveData(episodicMemories)
        await offlineStorage.saveData(semanticMemories)
        await offlineStorage.saveData(locationMemories)
    }
    
    // MARK: - CloudKit Utilities
    
    private func createCloudKitRecord<T: SyncableData>(from data: T, container: SyncContainer) throws -> CKRecord {
        let recordID = CKRecord.ID(recordName: data.id.uuidString)
        let record = CKRecord(recordType: String(describing: type(of: data)), recordID: recordID)
        
        // Encode data to record fields
        let encoder = CloudKitEncoder()
        try encoder.encode(data, to: record)
        
        return record
    }
    
    private func saveRecord(_ record: CKRecord, to container: SyncContainer) async throws -> CKRecord {
        let database = getDatabase(for: container)
        return try await database.save(record)
    }
    
    private func getDatabase(for container: SyncContainer) -> CKDatabase {
        switch container {
        case .private:
            return privateContainer.privateCloudDatabase
        case .public:
            return publicContainer.publicCloudDatabase
        case .shared:
            return sharedContainer.sharedCloudDatabase
        }
    }
    
    private func updateSyncMetadata(for dataId: UUID, record: CKRecord) {
        let metadata = SyncMetadata(
            dataId: dataId,
            recordID: record.recordID,
            lastModified: record.modificationDate ?? Date(),
            etag: record.recordChangeTag
        )
        
        syncMetadata[dataId.uuidString] = metadata
    }
    
    private func loadPendingChanges() {
        Task {
            pendingChanges = await offlineStorage.loadPendingChanges()
        }
    }
    
    // MARK: - Sharing and Collaboration
    
    func shareData<T: SyncableData>(_ data: T, with participants: [String]) async throws -> CKShare {
        let record = try createCloudKitRecord(from: data, container: .private)
        let savedRecord = try await saveRecord(record, to: .private)
        
        let share = CKShare(rootRecord: savedRecord)
        share[CKShare.SystemFieldKey.title] = "KaiSight Data" as CKRecordValue
        
        // Add participants
        for participant in participants {
            let lookupInfo = CKUserIdentity.LookupInfo(emailAddress: participant)
            let userIdentity = try await privateContainer.userIdentity(forUserIdentityLookupInfo: lookupInfo)
            
            let shareParticipant = CKShare.Participant()
            shareParticipant.userIdentity = userIdentity
            shareParticipant.permission = .readWrite
            shareParticipant.role = .privateUser
            
            share.addParticipant(shareParticipant)
        }
        
        let (savedRecord2, savedShare) = try await privateContainer.privateCloudDatabase.modifyRecords(saving: [savedRecord, share], deleting: [])
        
        return savedShare.first as! CKShare
    }
    
    func acceptShare(_ shareURL: URL) async throws {
        let shareMetadata = try await privateContainer.shareMetadata(for: shareURL)
        try await privateContainer.accept(shareMetadata)
        
        // Sync shared data
        try await syncSharedData()
    }
    
    private func syncSharedData() async throws {
        // Fetch and sync shared records
        let sharedDatabase = sharedContainer.sharedCloudDatabase
        let query = CKQuery(recordType: "SharedData", predicate: NSPredicate(value: true))
        
        let records = try await sharedDatabase.records(matching: query).matchResults.compactMap { result in
            try? result.1.get()
        }
        
        // Process shared records
        for record in records {
            // Handle shared data based on record type
            await processSharedRecord(record)
        }
    }
    
    private func processSharedRecord(_ record: CKRecord) async {
        // Process different types of shared records
        switch record.recordType {
        case "SpatialAnchor":
            // Handle shared spatial anchor
            break
        case "FaceIdentity":
            // Handle shared face identity
            break
        default:
            break
        }
    }
    
    // MARK: - Error Handling and Recovery
    
    func handleSyncError(_ error: Error) {
        if let ckError = error as? CKError {
            switch ckError.code {
            case .networkUnavailable, .networkFailure:
                isOffline = true
                syncStatus = .offline
                
            case .quotaExceeded:
                syncStatus = .error("iCloud storage quota exceeded")
                
            case .recordBusy:
                // Retry after delay
                retryManager.scheduleRetry {
                    Task {
                        await self.performFullSync()
                    }
                }
                
            case .serverRecordChanged:
                // Handle server conflicts
                Task {
                    await self.resolveConflicts()
                }
                
            default:
                syncStatus = .error(ckError.localizedDescription)
            }
        } else {
            syncStatus = .error(error.localizedDescription)
        }
    }
    
    func recoverFromError() async {
        switch syncStatus {
        case .offline:
            checkCloudKitAvailability()
            
        case .error(_):
            // Reset and try again
            syncStatus = .idle
            await performFullSync()
            
        default:
            break
        }
    }
    
    // MARK: - Data Export and Import
    
    func exportAllData() async -> CloudSyncExport {
        let spatialData = await offlineStorage.loadData(ofType: SpatialAnchor.self)
        let faceData = await offlineStorage.loadData(ofType: FaceIdentity.self)
        let memoryData = await offlineStorage.loadData(ofType: EpisodicMemory.self)
        
        return CloudSyncExport(
            spatialAnchors: spatialData,
            faceIdentities: faceData,
            episodicMemories: memoryData,
            exportDate: Date(),
            encryptionEnabled: encryptionEnabled
        )
    }
    
    func importData(_ exportData: CloudSyncExport) async throws {
        // Import and sync data
        for anchor in exportData.spatialAnchors {
            try await syncData(anchor)
        }
        
        for face in exportData.faceIdentities {
            try await syncData(face)
        }
        
        for memory in exportData.episodicMemories {
            try await syncData(memory)
        }
    }
    
    // MARK: - Public Interface
    
    func pauseSync() {
        syncTimer?.invalidate()
        syncTimer = nil
        syncStatus = .paused
    }
    
    func resumeSync() {
        startPeriodicSync()
        syncStatus = .available
        
        Task {
            await performFullSync()
        }
    }
    
    func forceSyncNow() {
        Task {
            await performFullSync()
        }
    }
    
    func getSyncSummary() -> String {
        var summary = "Sync status: \(syncStatus.description)"
        
        if let lastSync = lastSyncDate {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            summary += ". Last sync: \(formatter.string(from: lastSync))"
        }
        
        if !pendingChanges.isEmpty {
            summary += ". \(pendingChanges.count) pending changes"
        }
        
        if conflictCount > 0 {
            summary += ". \(conflictCount) conflicts"
        }
        
        return summary
    }
}

// MARK: - Data Models and Protocols

protocol SyncableData: Codable, Identifiable where ID == UUID {
    var id: UUID { get }
    var lastModified: Date { get }
}

struct SyncableChange: Codable {
    let id: UUID
    let dataId: UUID
    let operation: SyncOperation
    let data: any SyncableData
    let timestamp: Date
    var retryCount: Int
    
    private enum CodingKeys: String, CodingKey {
        case id, dataId, operation, timestamp, retryCount
    }
}

struct SyncMetadata {
    let dataId: UUID
    let recordID: CKRecord.ID
    let lastModified: Date
    let etag: String?
}

struct DataConflict {
    let id: UUID
    let dataId: UUID
    let localData: (any SyncableData)?
    let remoteData: (any SyncableData)?
    let description: String
}

struct ConflictResolution {
    let conflict: DataConflict
    let strategy: ConflictStrategy
    let localData: (any SyncableData)?
    let remoteData: (any SyncableData)?
    let mergedData: (any SyncableData)?
}

struct CloudSyncExport: Codable {
    let spatialAnchors: [SpatialAnchor]
    let faceIdentities: [FaceIdentity]
    let episodicMemories: [EpisodicMemory]
    let exportDate: Date
    let encryptionEnabled: Bool
}

// MARK: - Enums

enum SyncStatus: Equatable {
    case idle
    case available
    case syncing
    case paused
    case offline
    case noAccount
    case unavailable
    case error(String)
    
    var description: String {
        switch self {
        case .idle: return "Idle"
        case .available: return "Available"
        case .syncing: return "Syncing"
        case .paused: return "Paused"
        case .offline: return "Offline"
        case .noAccount: return "No iCloud Account"
        case .unavailable: return "Unavailable"
        case .error(let message): return "Error: \(message)"
        }
    }
}

enum SyncContainer {
    case private
    case public
    case shared
}

enum SyncOperation: String, Codable {
    case create = "create"
    case update = "update"
    case delete = "delete"
}

enum ConflictStrategy {
    case useLocal
    case useRemote
    case merge
    case userChoice
}

enum SyncError: Error {
    case unavailable
    case encryptionFailed
    case decryptionFailed
    case networkError
    case quotaExceeded
    case unauthorized
}

// MARK: - Supporting Classes

class DataEncryptionManager {
    private var encryptionKey: SymmetricKey?
    
    func initializeKeys(completion: @escaping (Bool) -> Void) {
        // Generate or load encryption key from keychain
        if let keyData = KeychainManager.shared.getEncryptionKey() {
            encryptionKey = SymmetricKey(data: keyData)
            completion(true)
        } else {
            // Generate new key
            let newKey = SymmetricKey(size: .bits256)
            let keyData = newKey.withUnsafeBytes { Data($0) }
            
            if KeychainManager.shared.saveEncryptionKey(keyData) {
                encryptionKey = newKey
                completion(true)
            } else {
                completion(false)
            }
        }
    }
    
    func encrypt<T: SyncableData>(_ data: T) async throws -> SyncableData {
        guard let key = encryptionKey else {
            throw SyncError.encryptionFailed
        }
        
        let jsonData = try JSONEncoder().encode(data)
        let encryptedData = try AES.GCM.seal(jsonData, using: key)
        
        return EncryptedSyncData(
            id: data.id,
            lastModified: data.lastModified,
            encryptedData: encryptedData.combined!,
            dataType: String(describing: type(of: data))
        )
    }
    
    func decrypt<T: SyncableData>(_ record: CKRecord, as type: T.Type) async throws -> T? {
        guard let key = encryptionKey else {
            throw SyncError.decryptionFailed
        }
        
        // Extract encrypted data from CloudKit record
        guard let encryptedDataField = record["encryptedData"] as? Data else {
            throw SyncError.decryptionFailed
        }
        
        let sealedBox = try AES.GCM.SealedBox(combined: encryptedDataField)
        let decryptedData = try AES.GCM.open(sealedBox, using: key)
        
        return try JSONDecoder().decode(type, from: decryptedData)
    }
}

struct EncryptedSyncData: SyncableData {
    let id: UUID
    let lastModified: Date
    let encryptedData: Data
    let dataType: String
}

class KeychainManager {
    static let shared = KeychainManager()
    
    private let service = "com.kaisight.encryption"
    private let keyAccount = "master-key"
    
    func saveEncryptionKey(_ keyData: Data) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: keyAccount,
            kSecValueData as String: keyData
        ]
        
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        
        return status == errSecSuccess
    }
    
    func getEncryptionKey() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: keyAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        return status == errSecSuccess ? result as? Data : nil
    }
}

class ConflictResolver {
    func resolve(_ conflict: DataConflict) async -> ConflictResolution {
        // Automatic conflict resolution strategies
        
        // Strategy 1: Most recent wins
        if let localData = conflict.localData,
           let remoteData = conflict.remoteData {
            
            if localData.lastModified > remoteData.lastModified {
                return ConflictResolution(
                    conflict: conflict,
                    strategy: .useLocal,
                    localData: localData,
                    remoteData: remoteData,
                    mergedData: nil
                )
            } else {
                return ConflictResolution(
                    conflict: conflict,
                    strategy: .useRemote,
                    localData: localData,
                    remoteData: remoteData,
                    mergedData: nil
                )
            }
        }
        
        // Strategy 2: User choice for complex conflicts
        return ConflictResolution(
            conflict: conflict,
            strategy: .userChoice,
            localData: conflict.localData,
            remoteData: conflict.remoteData,
            mergedData: nil
        )
    }
}

class OfflineStorageManager {
    private let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    
    func saveData<T: SyncableData>(_ data: [T]) async {
        let filename = "\(String(describing: T.self)).json"
        let url = documentsDirectory.appendingPathComponent(filename)
        
        do {
            let jsonData = try JSONEncoder().encode(data)
            try jsonData.write(to: url)
        } catch {
            Config.debugLog("Failed to save offline data: \(error)")
        }
    }
    
    func loadData<T: SyncableData>(ofType type: T.Type) async -> [T] {
        let filename = "\(String(describing: type)).json"
        let url = documentsDirectory.appendingPathComponent(filename)
        
        do {
            let jsonData = try Data(contentsOf: url)
            return try JSONDecoder().decode([T].self, from: jsonData)
        } catch {
            Config.debugLog("Failed to load offline data: \(error)")
            return []
        }
    }
    
    func savePendingChange(_ change: SyncableChange) async {
        // Save pending changes for offline sync
    }
    
    func loadPendingChanges() async -> [SyncableChange] {
        // Load pending changes
        return []
    }
    
    func removePendingChanges(_ changeIds: [UUID]) async {
        // Remove completed changes
    }
    
    func updateLocalData<T: SyncableData>(_ data: T) async {
        // Update local data with remote changes
    }
}

class RetryManager {
    private var retryAttempts: [String: Int] = [:]
    
    func scheduleRetry(operation: @escaping () -> Void) {
        // Exponential backoff retry
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
            operation()
        }
    }
}

class CloudKitEncoder {
    func encode<T: SyncableData>(_ data: T, to record: CKRecord) throws {
        let jsonData = try JSONEncoder().encode(data)
        record["data"] = jsonData as CKRecordValue
        record["lastModified"] = data.lastModified as CKRecordValue
    }
}

// MARK: - Extensions

extension SpatialAnchor: SyncableData {
    var lastModified: Date { timestamp }
}

extension FaceIdentity: SyncableData {
    var lastModified: Date { lastSeen }
}

extension CustomObjectIdentity: SyncableData {
    var lastModified: Date { lastSeen }
}

extension EpisodicMemory: SyncableData {
    var lastModified: Date { timestamp }
}

extension SemanticMemory: SyncableData {
    var lastModified: Date { timestamp }
}

extension LocationMemory: SyncableData {
    var lastModified: Date { timestamp }
} 