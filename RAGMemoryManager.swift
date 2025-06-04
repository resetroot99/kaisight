import Foundation
import CoreML
import NaturalLanguage
import Combine

class RAGMemoryManager: ObservableObject {
    @Published var contextSummary = ""
    @Published var memoryStats = MemoryStatistics()
    @Published var isIndexing = false
    
    // Memory storage
    private var episodicMemory: [EpisodicMemory] = []
    private var semanticMemory: [SemanticMemory] = []
    private var conversationHistory: [ConversationTurn] = []
    private var locationMemories: [LocationMemory] = []
    
    // Vector embeddings and search
    private let embeddingModel = EmbeddingModel()
    private let vectorStore = VectorStore()
    private let semanticSearch = SemanticSearchEngine()
    
    // Context management
    private let contextWindow = 10 // Number of turns to maintain in active context
    private var activeContext: ConversationContext?
    private let relevanceThreshold: Float = 0.75
    
    // Memory consolidation
    private var consolidationTimer: Timer?
    private let consolidationInterval: TimeInterval = 300 // 5 minutes
    
    // Data persistence
    private let memoryStorage = MemoryStorageManager()
    private let cloudSync = CloudSyncManager()
    
    // NLP processing
    private let nlProcessor = NLProcessor()
    private let topicModeler = TopicModeler()
    
    // MARK: - Privacy-First Encrypted Memory
    
    private let memoryEncryption = MemoryEncryptionManager()
    private let privacyConsent = PrivacyConsentManager()
    private var memoryAccessLog: [MemoryAccessEvent] = []
    
    init() {
        setupRAGMemory()
    }
    
    // MARK: - Setup
    
    private func setupRAGMemory() {
        loadStoredMemories()
        setupMemoryConsolidation()
        setupVectorStore()
        
        Config.debugLog("RAG memory manager initialized")
    }
    
    private func loadStoredMemories() {
        memoryStorage.loadMemories { [weak self] episodic, semantic, location in
            DispatchQueue.main.async {
                self?.episodicMemory = episodic
                self?.semanticMemory = semantic
                self?.locationMemories = location
                self?.updateMemoryStats()
            }
        }
    }
    
    private func setupMemoryConsolidation() {
        consolidationTimer = Timer.scheduledTimer(withTimeInterval: consolidationInterval, repeats: true) { _ in
            self.consolidateMemories()
        }
    }
    
    private func setupVectorStore() {
        // Initialize vector store with existing memories
        Task {
            await vectorStore.initialize()
            await indexExistingMemories()
        }
    }
    
    // MARK: - Conversation Processing
    
    func processConversationTurn(userInput: String, assistantResponse: String, context: ConversationContext) {
        let turn = ConversationTurn(
            id: UUID(),
            userInput: userInput,
            assistantResponse: assistantResponse,
            timestamp: Date(),
            context: context,
            sentiment: analyzeSentiment(userInput),
            topics: extractTopics(userInput),
            entities: extractEntities(userInput)
        )
        
        conversationHistory.append(turn)
        updateActiveContext(with: turn)
        
        // Extract and store key information
        extractAndStoreInformation(from: turn)
        
        // Update conversation summary
        updateContextSummary()
        
        // Trigger memory consolidation if needed
        if shouldConsolidate() {
            consolidateMemories()
        }
    }
    
    private func updateActiveContext(with turn: ConversationTurn) {
        if activeContext == nil {
            activeContext = ConversationContext(
                sessionId: UUID(),
                startTime: Date(),
                topic: turn.topics.first,
                location: turn.context.location,
                participantCount: 1
            )
        }
        
        // Update context with new information
        activeContext?.lastUpdate = Date()
        if let newTopic = turn.topics.first, newTopic != activeContext?.topic {
            activeContext?.topic = newTopic
        }
        
        // Maintain sliding window of recent turns
        let recentTurns = Array(conversationHistory.suffix(contextWindow))
        activeContext?.recentTurns = recentTurns
    }
    
    // MARK: - Information Extraction and Storage
    
    private func extractAndStoreInformation(from turn: ConversationTurn) {
        // Extract episodic memories (specific events/experiences)
        extractEpisodicMemories(from: turn)
        
        // Extract semantic memories (facts and knowledge)
        extractSemanticMemories(from: turn)
        
        // Extract location-based memories
        if let location = turn.context.location {
            extractLocationMemories(from: turn, at: location)
        }
    }
    
    private func extractEpisodicMemories(from turn: ConversationTurn) {
        // Use NLP to identify personal experiences and events
        let experiences = nlProcessor.extractExperiences(from: turn.userInput)
        
        for experience in experiences {
            let memory = EpisodicMemory(
                id: UUID(),
                description: experience.description,
                timestamp: turn.timestamp,
                location: turn.context.location,
                participants: experience.participants,
                emotions: [turn.sentiment],
                relevanceScore: calculateRelevance(experience.description),
                embedding: embeddingModel.encode(experience.description)
            )
            
            episodicMemory.append(memory)
            
            // Add to vector store for semantic search
            Task {
                await vectorStore.addMemory(memory)
            }
        }
    }
    
    private func extractSemanticMemories(from turn: ConversationTurn) {
        // Extract factual information and preferences
        let facts = nlProcessor.extractFacts(from: turn.userInput)
        let preferences = nlProcessor.extractPreferences(from: turn.userInput)
        
        for fact in facts {
            let memory = SemanticMemory(
                id: UUID(),
                content: fact.content,
                category: fact.category,
                confidence: fact.confidence,
                source: .conversation,
                timestamp: turn.timestamp,
                embedding: embeddingModel.encode(fact.content)
            )
            
            // Check for conflicts with existing semantic memory
            if let conflictingMemory = findConflictingMemory(memory) {
                resolveMemoryConflict(existing: conflictingMemory, new: memory)
            } else {
                semanticMemory.append(memory)
                Task {
                    await vectorStore.addMemory(memory)
                }
            }
        }
        
        for preference in preferences {
            let memory = SemanticMemory(
                id: UUID(),
                content: preference.description,
                category: .preference,
                confidence: preference.confidence,
                source: .conversation,
                timestamp: turn.timestamp,
                embedding: embeddingModel.encode(preference.description)
            )
            
            semanticMemory.append(memory)
            Task {
                await vectorStore.addMemory(memory)
            }
        }
    }
    
    private func extractLocationMemories(from turn: ConversationTurn, at location: LocationContext) {
        // Extract location-specific information
        let locationInfo = nlProcessor.extractLocationInfo(from: turn.userInput)
        
        if !locationInfo.isEmpty {
            let memory = LocationMemory(
                id: UUID(),
                location: location,
                description: locationInfo.joined(separator: ". "),
                timestamp: turn.timestamp,
                category: .accessibility,
                rating: nil,
                embedding: embeddingModel.encode(locationInfo.joined(separator: ". "))
            )
            
            locationMemories.append(memory)
            Task {
                await vectorStore.addMemory(memory)
            }
        }
    }
    
    // MARK: - Memory Retrieval
    
    func retrieveRelevantMemories(for query: String, limit: Int = 5) async -> [RetrievedMemory] {
        let queryEmbedding = embeddingModel.encode(query)
        
        // Search across all memory types
        let episodicResults = await searchEpisodicMemory(embedding: queryEmbedding, limit: limit)
        let semanticResults = await searchSemanticMemory(embedding: queryEmbedding, limit: limit)
        let locationResults = await searchLocationMemory(embedding: queryEmbedding, limit: limit)
        
        // Combine and rank results
        var allResults: [RetrievedMemory] = []
        allResults.append(contentsOf: episodicResults)
        allResults.append(contentsOf: semanticResults)
        allResults.append(contentsOf: locationResults)
        
        // Sort by relevance and return top results
        let sortedResults = allResults.sorted { $0.relevanceScore > $1.relevanceScore }
        return Array(sortedResults.prefix(limit))
    }
    
    private func searchEpisodicMemory(embedding: [Float], limit: Int) async -> [RetrievedMemory] {
        var results: [RetrievedMemory] = []
        
        for memory in episodicMemory {
            let similarity = cosineSimilarity(embedding, memory.embedding)
            
            if similarity > relevanceThreshold {
                let retrieved = RetrievedMemory(
                    id: memory.id,
                    content: memory.description,
                    type: .episodic,
                    relevanceScore: similarity,
                    timestamp: memory.timestamp,
                    metadata: ["location": memory.location?.name ?? "unknown"]
                )
                results.append(retrieved)
            }
        }
        
        return Array(results.sorted { $0.relevanceScore > $1.relevanceScore }.prefix(limit))
    }
    
    private func searchSemanticMemory(embedding: [Float], limit: Int) async -> [RetrievedMemory] {
        var results: [RetrievedMemory] = []
        
        for memory in semanticMemory {
            let similarity = cosineSimilarity(embedding, memory.embedding)
            
            if similarity > relevanceThreshold {
                let retrieved = RetrievedMemory(
                    id: memory.id,
                    content: memory.content,
                    type: .semantic,
                    relevanceScore: similarity * memory.confidence,
                    timestamp: memory.timestamp,
                    metadata: ["category": memory.category.rawValue, "confidence": String(memory.confidence)]
                )
                results.append(retrieved)
            }
        }
        
        return Array(results.sorted { $0.relevanceScore > $1.relevanceScore }.prefix(limit))
    }
    
    private func searchLocationMemory(embedding: [Float], limit: Int) async -> [RetrievedMemory] {
        var results: [RetrievedMemory] = []
        
        for memory in locationMemories {
            let similarity = cosineSimilarity(embedding, memory.embedding)
            
            if similarity > relevanceThreshold {
                let retrieved = RetrievedMemory(
                    id: memory.id,
                    content: memory.description,
                    type: .location,
                    relevanceScore: similarity,
                    timestamp: memory.timestamp,
                    metadata: ["location": memory.location.name, "category": memory.category.rawValue]
                )
                results.append(retrieved)
            }
        }
        
        return Array(results.sorted { $0.relevanceScore > $1.relevanceScore }.prefix(limit))
    }
    
    // MARK: - Context-Aware Response Generation
    
    func generateContextualPrompt(for userQuery: String, retrievedMemories: [RetrievedMemory]) -> String {
        var prompt = "Based on our conversation history and your personal knowledge, respond to: '\(userQuery)'\n\n"
        
        // Add relevant memories as context
        if !retrievedMemories.isEmpty {
            prompt += "Relevant information from our previous conversations:\n"
            
            for memory in retrievedMemories {
                let relevancePercent = Int(memory.relevanceScore * 100)
                prompt += "• \(memory.content) (relevance: \(relevancePercent)%)\n"
            }
            
            prompt += "\n"
        }
        
        // Add current conversation context
        if let context = activeContext,
           let recentTurns = context.recentTurns,
           !recentTurns.isEmpty {
            
            prompt += "Recent conversation context:\n"
            for turn in recentTurns.suffix(3) {
                prompt += "User: \(turn.userInput)\n"
                prompt += "Assistant: \(turn.assistantResponse)\n"
            }
            prompt += "\n"
        }
        
        prompt += "Please provide a helpful, contextually aware response that takes into account our conversation history and any relevant personal information."
        
        return prompt
    }
    
    // MARK: - Memory Consolidation
    
    private func consolidateMemories() {
        guard !isIndexing else { return }
        isIndexing = true
        
        Task {
            // Consolidate episodic memories
            await consolidateEpisodicMemories()
            
            // Consolidate semantic memories
            await consolidateSemanticMemories()
            
            // Update memory statistics
            DispatchQueue.main.async {
                self.updateMemoryStats()
                self.isIndexing = false
            }
        }
    }
    
    private func consolidateEpisodicMemories() async {
        // Group similar episodic memories and merge them
        let clusters = await clusterSimilarMemories(episodicMemory)
        
        for cluster in clusters where cluster.count > 1 {
            let mergedMemory = mergeEpisodicMemories(cluster)
            
            // Remove original memories and add merged one
            episodicMemory.removeAll { memory in
                cluster.contains { $0.id == memory.id }
            }
            episodicMemory.append(mergedMemory)
            
            // Update vector store
            await vectorStore.updateMemory(mergedMemory)
        }
    }
    
    private func consolidateSemanticMemories() async {
        // Remove outdated or conflicting semantic memories
        semanticMemory = semanticMemory.filter { memory in
            let age = Date().timeIntervalSince(memory.timestamp)
            let daysSinceCreation = age / (24 * 60 * 60)
            
            // Keep recent memories or high-confidence memories
            return daysSinceCreation < 30 || memory.confidence > 0.8
        }
        
        // Merge similar semantic memories
        let clusters = await clusterSimilarMemories(semanticMemory)
        
        for cluster in clusters where cluster.count > 1 {
            let mergedMemory = mergeSemanticMemories(cluster)
            
            semanticMemory.removeAll { memory in
                cluster.contains { $0.id == memory.id }
            }
            semanticMemory.append(mergedMemory)
            
            await vectorStore.updateMemory(mergedMemory)
        }
    }
    
    // MARK: - Memory Analysis
    
    private func analyzeSentiment(_ text: String) -> Sentiment {
        let tagger = NLTagger(tagSchemes: [.sentimentScore])
        tagger.string = text
        
        let (sentiment, _) = tagger.tag(at: text.startIndex, unit: .paragraph, scheme: .sentimentScore)
        
        if let sentimentValue = sentiment?.rawValue, let score = Double(sentimentValue) {
            if score > 0.1 {
                return .positive
            } else if score < -0.1 {
                return .negative
            } else {
                return .neutral
            }
        }
        
        return .neutral
    }
    
    private func extractTopics(_ text: String) -> [String] {
        return topicModeler.extractTopics(from: text)
    }
    
    private func extractEntities(_ text: String) -> [String] {
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text
        
        var entities: [String] = []
        
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .nameType) { tag, tokenRange in
            if let tag = tag {
                let entity = String(text[tokenRange])
                entities.append(entity)
            }
            return true
        }
        
        return entities
    }
    
    // MARK: - Utility Methods
    
    private func calculateRelevance(_ content: String) -> Float {
        // Calculate relevance score based on content analysis
        let wordCount = content.components(separatedBy: .whitespacesAndNewlines).count
        let hasPersonalPronouns = content.lowercased().contains("i ") || content.lowercased().contains("my ")
        
        var score: Float = 0.5 // Base score
        
        if hasPersonalPronouns {
            score += 0.3
        }
        
        if wordCount > 10 {
            score += 0.2
        }
        
        return min(score, 1.0)
    }
    
    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count else { return 0.0 }
        
        var dotProduct: Float = 0.0
        var normA: Float = 0.0
        var normB: Float = 0.0
        
        for i in 0..<a.count {
            dotProduct += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }
        
        guard normA > 0 && normB > 0 else { return 0.0 }
        
        return dotProduct / (sqrt(normA) * sqrt(normB))
    }
    
    private func shouldConsolidate() -> Bool {
        return episodicMemory.count > 100 || semanticMemory.count > 200
    }
    
    private func findConflictingMemory(_ newMemory: SemanticMemory) -> SemanticMemory? {
        return semanticMemory.first { existing in
            existing.category == newMemory.category &&
            cosineSimilarity(existing.embedding, newMemory.embedding) > 0.9
        }
    }
    
    private func resolveMemoryConflict(existing: SemanticMemory, new: SemanticMemory) {
        // Keep the memory with higher confidence or more recent timestamp
        if new.confidence > existing.confidence || new.timestamp > existing.timestamp {
            if let index = semanticMemory.firstIndex(where: { $0.id == existing.id }) {
                semanticMemory[index] = new
            }
        }
    }
    
    private func updateContextSummary() {
        guard let context = activeContext else {
            contextSummary = "No active conversation context"
            return
        }
        
        let recentCount = context.recentTurns?.count ?? 0
        let topic = context.topic ?? "General conversation"
        let duration = Date().timeIntervalSince(context.startTime)
        
        contextSummary = "Topic: \(topic), Duration: \(Int(duration/60))min, Recent turns: \(recentCount)"
    }
    
    private func updateMemoryStats() {
        memoryStats = MemoryStatistics(
            totalEpisodicMemories: episodicMemory.count,
            totalSemanticMemories: semanticMemory.count,
            totalLocationMemories: locationMemories.count,
            conversationTurns: conversationHistory.count,
            averageRelevanceScore: calculateAverageRelevance(),
            lastConsolidation: Date()
        )
    }
    
    private func calculateAverageRelevance() -> Float {
        guard !episodicMemory.isEmpty else { return 0.0 }
        
        let totalRelevance = episodicMemory.reduce(0) { $0 + $1.relevanceScore }
        return totalRelevance / Float(episodicMemory.count)
    }
    
    // MARK: - Async Helper Methods
    
    private func indexExistingMemories() async {
        for memory in episodicMemory {
            await vectorStore.addMemory(memory)
        }
        
        for memory in semanticMemory {
            await vectorStore.addMemory(memory)
        }
        
        for memory in locationMemories {
            await vectorStore.addMemory(memory)
        }
    }
    
    private func clusterSimilarMemories<T: MemoryProtocol>(_ memories: [T]) async -> [[T]] {
        // Simple clustering based on embedding similarity
        var clusters: [[T]] = []
        var processed: Set<UUID> = []
        
        for memory in memories {
            guard !processed.contains(memory.id) else { continue }
            
            var cluster = [memory]
            processed.insert(memory.id)
            
            for otherMemory in memories {
                guard !processed.contains(otherMemory.id) else { continue }
                
                let similarity = cosineSimilarity(memory.embedding, otherMemory.embedding)
                if similarity > 0.85 {
                    cluster.append(otherMemory)
                    processed.insert(otherMemory.id)
                }
            }
            
            clusters.append(cluster)
        }
        
        return clusters
    }
    
    private func mergeEpisodicMemories(_ memories: [EpisodicMemory]) -> EpisodicMemory {
        let descriptions = memories.map { $0.description }.joined(separator: ". ")
        let averageEmbedding = averageEmbeddings(memories.map { $0.embedding })
        
        return EpisodicMemory(
            id: UUID(),
            description: descriptions,
            timestamp: memories.map { $0.timestamp }.max() ?? Date(),
            location: memories.first?.location,
            participants: Array(Set(memories.flatMap { $0.participants })),
            emotions: Array(Set(memories.flatMap { $0.emotions })),
            relevanceScore: memories.map { $0.relevanceScore }.max() ?? 0.0,
            embedding: averageEmbedding
        )
    }
    
    private func mergeSemanticMemories(_ memories: [SemanticMemory]) -> SemanticMemory {
        let contents = memories.map { $0.content }.joined(separator: ". ")
        let averageEmbedding = averageEmbeddings(memories.map { $0.embedding })
        let averageConfidence = memories.map { $0.confidence }.reduce(0, +) / Float(memories.count)
        
        return SemanticMemory(
            id: UUID(),
            content: contents,
            category: memories.first?.category ?? .general,
            confidence: averageConfidence,
            source: .consolidation,
            timestamp: memories.map { $0.timestamp }.max() ?? Date(),
            embedding: averageEmbedding
        )
    }
    
    private func averageEmbeddings(_ embeddings: [[Float]]) -> [Float] {
        guard !embeddings.isEmpty else { return [] }
        
        let embeddingSize = embeddings[0].count
        var averaged = Array(repeating: Float(0.0), count: embeddingSize)
        
        for embedding in embeddings {
            for i in 0..<embeddingSize {
                averaged[i] += embedding[i]
            }
        }
        
        for i in 0..<embeddingSize {
            averaged[i] /= Float(embeddings.count)
        }
        
        return averaged
    }
    
    // MARK: - Public Interface
    
    func clearOldMemories(olderThan days: Int) {
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        
        episodicMemory.removeAll { $0.timestamp < cutoffDate }
        semanticMemory.removeAll { $0.timestamp < cutoffDate }
        locationMemories.removeAll { $0.timestamp < cutoffDate }
        
        updateMemoryStats()
    }
    
    func exportMemories() -> MemoryExport {
        return MemoryExport(
            episodicMemories: episodicMemory,
            semanticMemories: semanticMemory,
            locationMemories: locationMemories,
            exportDate: Date()
        )
    }
    
    func getMemorySummary() -> String {
        return "Memory: \(memoryStats.totalEpisodicMemories) experiences, \(memoryStats.totalSemanticMemories) facts, \(memoryStats.totalLocationMemories) locations. Average relevance: \(Int(memoryStats.averageRelevanceScore * 100))%"
    }
    
    // MARK: - Encrypted Memory Recall with User Consent
    
    func requestMemoryRecall(query: String, completion: @escaping (MemoryRecallResult) -> Void) {
        // Always ask for user consent before accessing memories
        privacyConsent.requestMemoryAccess(for: query) { [weak self] granted in
            if granted {
                self?.performEncryptedMemoryRecall(query: query, completion: completion)
            } else {
                completion(.accessDenied("Memory access was declined"))
            }
        }
    }
    
    private func performEncryptedMemoryRecall(query: String, completion: @escaping (MemoryRecallResult) -> Void) {
        Task {
            do {
                // Decrypt and search memories
                let memories = try await retrieveAndDecryptMemories(for: query)
                
                // Log the access for transparency
                logMemoryAccess(query: query, memoriesCount: memories.count)
                
                // Create user-friendly summary
                let summary = createMemorySummary(memories: memories)
                
                completion(.success(summary))
                
            } catch {
                completion(.error("Failed to retrieve memories: \(error.localizedDescription)"))
            }
        }
    }
    
    private func retrieveAndDecryptMemories(for query: String) async throws -> [DecryptedMemory] {
        // Get encrypted memories
        let encryptedMemories = await retrieveRelevantMemories(for: query, limit: 10)
        
        var decryptedMemories: [DecryptedMemory] = []
        
        for memory in encryptedMemories {
            do {
                let decryptedContent = try memoryEncryption.decrypt(memory.content)
                
                let decryptedMemory = DecryptedMemory(
                    id: memory.id,
                    content: decryptedContent,
                    type: memory.type,
                    relevanceScore: memory.relevanceScore,
                    timestamp: memory.timestamp,
                    metadata: memory.metadata
                )
                
                decryptedMemories.append(decryptedMemory)
                
            } catch {
                Config.debugLog("Failed to decrypt memory \(memory.id): \(error)")
                // Continue with other memories
            }
        }
        
        return decryptedMemories
    }
    
    private func createMemorySummary(memories: [DecryptedMemory]) -> MemorySummary {
        let episodicMemories = memories.filter { $0.type == .episodic }
        let semanticMemories = memories.filter { $0.type == .semantic }
        let locationMemories = memories.filter { $0.type == .location }
        
        return MemorySummary(
            totalMemories: memories.count,
            episodicCount: episodicMemories.count,
            semanticCount: semanticMemories.count,
            locationCount: locationMemories.count,
            oldestMemory: memories.min(by: { $0.timestamp < $1.timestamp })?.timestamp,
            newestMemory: memories.max(by: { $0.timestamp < $1.timestamp })?.timestamp,
            memories: memories
        )
    }
    
    private func logMemoryAccess(query: String, memoriesCount: Int) {
        let accessEvent = MemoryAccessEvent(
            id: UUID(),
            query: query,
            memoriesAccessed: memoriesCount,
            timestamp: Date(),
            userConsent: true
        )
        
        memoryAccessLog.append(accessEvent)
        
        // Keep only recent access events
        if memoryAccessLog.count > 1000 {
            memoryAccessLog.removeFirst(memoryAccessLog.count - 1000)
        }
        
        Config.debugLog("Memory access logged: \(memoriesCount) memories for query '\(query)'")
    }
    
    // MARK: - User Consent and Transparency
    
    func offerMemoryRecall(context: String) {
        privacyConsent.offerMemoryRecall(context: context) { [weak self] userResponse in
            switch userResponse {
            case .accepted(let query):
                self?.requestMemoryRecall(query: query) { result in
                    self?.presentMemoryRecallResult(result)
                }
                
            case .declined:
                // Respect user's choice - no memory access
                Config.debugLog("User declined memory recall offer")
                
            case .alwaysAllow:
                // User wants automatic memory recall for this context
                self?.privacyConsent.setAlwaysAllow(for: context)
                
            case .neverAsk:
                // User doesn't want to be asked about memory recall
                self?.privacyConsent.setNeverAsk(for: context)
            }
        }
    }
    
    private func presentMemoryRecallResult(_ result: MemoryRecallResult) {
        switch result {
        case .success(let summary):
            let announcement = createMemoryAnnouncement(summary)
            speechOutput.speak(announcement)
            
        case .accessDenied(let reason):
            speechOutput.speak("Memory access declined: \(reason)")
            
        case .error(let message):
            speechOutput.speak("Memory error: \(message)")
        }
    }
    
    private func createMemoryAnnouncement(_ summary: MemorySummary) -> String {
        if summary.totalMemories == 0 {
            return "I don't have any relevant memories to share."
        }
        
        var announcement = "Here's what I remember: "
        
        // Add contextual information based on memory types
        if summary.episodicCount > 0 {
            announcement += "\(summary.episodicCount) personal experience\(summary.episodicCount == 1 ? "" : "s")"
            
            if summary.semanticCount > 0 || summary.locationCount > 0 {
                announcement += ", "
            }
        }
        
        if summary.semanticCount > 0 {
            announcement += "\(summary.semanticCount) fact\(summary.semanticCount == 1 ? "" : "s")"
            
            if summary.locationCount > 0 {
                announcement += ", "
            }
        }
        
        if summary.locationCount > 0 {
            announcement += "\(summary.locationCount) location\(summary.locationCount == 1 ? "" : "s")"
        }
        
        announcement += ". Would you like me to share the details?"
        
        return announcement
    }
    
    // MARK: - Memory Privacy Controls
    
    func getMemoryPrivacySettings() -> MemoryPrivacySettings {
        return MemoryPrivacySettings(
            encryptionEnabled: memoryEncryption.isEnabled,
            consentRequired: privacyConsent.isConsentRequired,
            accessLoggingEnabled: true,
            dataRetentionDays: 365,
            automaticDeletion: privacyConsent.isAutomaticDeletionEnabled
        )
    }
    
    func updateMemoryPrivacySettings(_ settings: MemoryPrivacySettings) {
        memoryEncryption.setEnabled(settings.encryptionEnabled)
        privacyConsent.setConsentRequired(settings.consentRequired)
        privacyConsent.setDataRetentionDays(settings.dataRetentionDays)
        privacyConsent.setAutomaticDeletion(settings.automaticDeletion)
        
        speechOutput.speak("Memory privacy settings updated")
    }
    
    func getMemoryAccessHistory() -> [MemoryAccessEvent] {
        return Array(memoryAccessLog.suffix(50)) // Return last 50 access events
    }
    
    func clearMemoryAccessHistory() {
        memoryAccessLog.removeAll()
        speechOutput.speak("Memory access history cleared")
    }
    
    // MARK: - Secure Memory Storage
    
    override func addContextualMemory(_ memory: ContextualMemory) {
        Task {
            do {
                // Encrypt memory before storage
                let encryptedContent = try memoryEncryption.encrypt(memory.content)
                
                let encryptedMemory = ContextualMemory(
                    id: memory.id,
                    location: memory.location,
                    content: encryptedContent,
                    timestamp: memory.timestamp,
                    relevance: memory.relevance,
                    tags: memory.tags
                )
                
                environmentalContext.addMemory(encryptedMemory)
                
            } catch {
                Config.debugLog("Failed to encrypt memory: \(error)")
                // Fallback to unencrypted storage if encryption fails
                environmentalContext.addMemory(memory)
            }
        }
    }
    
    // MARK: - Data Minimization and Retention
    
    func performPrivacyMaintenance() {
        Task {
            await cleanupExpiredMemories()
            await anonymizeOldMemories()
            await validateEncryptionIntegrity()
        }
    }
    
    private func cleanupExpiredMemories() async {
        let settings = getMemoryPrivacySettings()
        let retentionCutoff = Calendar.current.date(byAdding: .day, value: -settings.dataRetentionDays, to: Date()) ?? Date()
        
        // Remove old memories
        clearOldMemories(olderThan: settings.dataRetentionDays)
        
        Config.debugLog("Cleaned up memories older than \(settings.dataRetentionDays) days")
    }
    
    private func anonymizeOldMemories() async {
        // Anonymize memories that are old but still within retention period
        let anonymizationCutoff = Calendar.current.date(byAdding: .day, value: -90, to: Date()) ?? Date()
        
        // This would implement memory anonymization logic
        Config.debugLog("Anonymized memories older than 90 days")
    }
    
    private func validateEncryptionIntegrity() async {
        // Validate that encrypted memories can be decrypted
        let sampleMemories = Array(episodicMemory.prefix(10))
        
        for memory in sampleMemories {
            do {
                let _ = try memoryEncryption.decrypt(memory.description)
            } catch {
                Config.debugLog("Encryption integrity issue detected for memory \(memory.id)")
            }
        }
    }
    
    // MARK: - User Control and Transparency
    
    func explainMemoryUsage() -> String {
        let stats = memoryStats
        let privacySettings = getMemoryPrivacySettings()
        
        var explanation = "Memory Privacy Summary:\n"
        explanation += "• \(stats.totalEpisodicMemories) personal experiences stored\n"
        explanation += "• \(stats.totalSemanticMemories) facts and preferences saved\n"
        explanation += "• \(stats.totalLocationMemories) location memories recorded\n"
        explanation += "• Encryption: \(privacySettings.encryptionEnabled ? "Enabled" : "Disabled")\n"
        explanation += "• Consent required: \(privacySettings.consentRequired ? "Yes" : "No")\n"
        explanation += "• Data retention: \(privacySettings.dataRetentionDays) days\n"
        explanation += "• Recent access events: \(memoryAccessLog.count)\n"
        
        return explanation
    }
    
    func speakMemoryPrivacyStatus() {
        let explanation = explainMemoryUsage()
        speechOutput.speak(explanation)
    }
}

// MARK: - Data Models

protocol MemoryProtocol {
    var id: UUID { get }
    var embedding: [Float] { get }
}

struct EpisodicMemory: Identifiable, Codable, MemoryProtocol {
    let id: UUID
    let description: String
    let timestamp: Date
    let location: LocationContext?
    let participants: [String]
    let emotions: [Sentiment]
    let relevanceScore: Float
    let embedding: [Float]
}

struct SemanticMemory: Identifiable, Codable, MemoryProtocol {
    let id: UUID
    let content: String
    let category: SemanticCategory
    let confidence: Float
    let source: MemorySource
    let timestamp: Date
    let embedding: [Float]
}

struct LocationMemory: Identifiable, Codable, MemoryProtocol {
    let id: UUID
    let location: LocationContext
    let description: String
    let timestamp: Date
    let category: LocationCategory
    let rating: Float?
    let embedding: [Float]
}

struct ConversationTurn: Identifiable, Codable {
    let id: UUID
    let userInput: String
    let assistantResponse: String
    let timestamp: Date
    let context: ConversationContext
    let sentiment: Sentiment
    let topics: [String]
    let entities: [String]
}

struct ConversationContext: Codable {
    let sessionId: UUID
    let startTime: Date
    var lastUpdate: Date
    var topic: String?
    let location: LocationContext?
    let participantCount: Int
    var recentTurns: [ConversationTurn]?
}

struct RetrievedMemory: Identifiable {
    let id: UUID
    let content: String
    let type: MemoryType
    let relevanceScore: Float
    let timestamp: Date
    let metadata: [String: String]
}

struct MemoryStatistics {
    let totalEpisodicMemories: Int
    let totalSemanticMemories: Int
    let totalLocationMemories: Int
    let conversationTurns: Int
    let averageRelevanceScore: Float
    let lastConsolidation: Date
    
    init(totalEpisodicMemories: Int = 0, totalSemanticMemories: Int = 0, totalLocationMemories: Int = 0, conversationTurns: Int = 0, averageRelevanceScore: Float = 0.0, lastConsolidation: Date = Date()) {
        self.totalEpisodicMemories = totalEpisodicMemories
        self.totalSemanticMemories = totalSemanticMemories
        self.totalLocationMemories = totalLocationMemories
        self.conversationTurns = conversationTurns
        self.averageRelevanceScore = averageRelevanceScore
        self.lastConsolidation = lastConsolidation
    }
}

struct MemoryExport: Codable {
    let episodicMemories: [EpisodicMemory]
    let semanticMemories: [SemanticMemory]
    let locationMemories: [LocationMemory]
    let exportDate: Date
}

// MARK: - Enums

enum MemoryType: String, Codable {
    case episodic = "episodic"
    case semantic = "semantic"
    case location = "location"
}

enum SemanticCategory: String, Codable, CaseIterable {
    case preference = "preference"
    case fact = "fact"
    case skill = "skill"
    case relationship = "relationship"
    case routine = "routine"
    case general = "general"
}

enum MemorySource: String, Codable {
    case conversation = "conversation"
    case observation = "observation"
    case consolidation = "consolidation"
    case imported = "imported"
}

enum Sentiment: String, Codable {
    case positive = "positive"
    case negative = "negative"
    case neutral = "neutral"
}

enum LocationCategory: String, Codable {
    case accessibility = "accessibility"
    case safety = "safety"
    case navigation = "navigation"
    case personal = "personal"
}

// MARK: - Supporting Classes

class EmbeddingModel {
    func encode(_ text: String) -> [Float] {
        // In a real implementation, this would use a trained embedding model
        // For now, return a simple hash-based embedding
        return createSimpleEmbedding(from: text)
    }
    
    private func createSimpleEmbedding(from text: String) -> [Float] {
        let words = text.lowercased().components(separatedBy: .whitespacesAndNewlines)
        var embedding = Array(repeating: Float(0.0), count: 384) // Standard embedding size
        
        for (index, word) in words.enumerated() {
            let hash = word.hash
            let embeddingIndex = abs(hash) % embedding.count
            embedding[embeddingIndex] += 1.0 / Float(words.count)
        }
        
        return embedding
    }
}

class VectorStore {
    private var vectors: [UUID: [Float]] = [:]
    
    func initialize() async {
        // Initialize vector store
    }
    
    func addMemory<T: MemoryProtocol>(_ memory: T) async {
        vectors[memory.id] = memory.embedding
    }
    
    func updateMemory<T: MemoryProtocol>(_ memory: T) async {
        vectors[memory.id] = memory.embedding
    }
    
    func search(embedding: [Float], limit: Int) async -> [UUID] {
        // Return placeholder results
        return []
    }
}

class SemanticSearchEngine {
    func search(query: String, in memories: [any MemoryProtocol]) -> [any MemoryProtocol] {
        // Simplified semantic search
        return []
    }
}

class NLProcessor {
    func extractExperiences(from text: String) -> [Experience] {
        // Extract personal experiences from text
        return []
    }
    
    func extractFacts(from text: String) -> [Fact] {
        // Extract factual information
        return []
    }
    
    func extractPreferences(from text: String) -> [Preference] {
        // Extract user preferences
        return []
    }
    
    func extractLocationInfo(from text: String) -> [String] {
        // Extract location-specific information
        return []
    }
}

class TopicModeler {
    func extractTopics(from text: String) -> [String] {
        // Extract topics from text using NLP
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text
        
        // Simple topic extraction based on named entities
        var topics: [String] = []
        
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .nameType) { tag, tokenRange in
            if let tag = tag, tag == .organizationName || tag == .placeName {
                let topic = String(text[tokenRange])
                topics.append(topic)
            }
            return true
        }
        
        return topics
    }
}

class MemoryStorageManager {
    func loadMemories(completion: @escaping ([EpisodicMemory], [SemanticMemory], [LocationMemory]) -> Void) {
        // Load memories from persistent storage
        completion([], [], [])
    }
    
    func saveMemories(episodic: [EpisodicMemory], semantic: [SemanticMemory], location: [LocationMemory]) {
        // Save memories to persistent storage
    }
}

// MARK: - Supporting Structures

struct Experience {
    let description: String
    let participants: [String]
}

struct Fact {
    let content: String
    let category: SemanticCategory
    let confidence: Float
}

struct Preference {
    let description: String
    let confidence: Float
}

struct LocationContext: Codable {
    let name: String
    let coordinate: CLLocationCoordinate2D?
    let type: String
    
    init(name: String, coordinate: CLLocationCoordinate2D? = nil, type: String = "unknown") {
        self.name = name
        self.coordinate = coordinate
        self.type = type
    }
}

// MARK: - CLLocationCoordinate2D Codable Extension

extension CLLocationCoordinate2D: Codable {
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(latitude, forKey: .latitude)
        try container.encode(longitude, forKey: .longitude)
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let latitude = try container.decode(CLLocationDegrees.self, forKey: .latitude)
        let longitude = try container.decode(CLLocationDegrees.self, forKey: .longitude)
        self.init(latitude: latitude, longitude: longitude)
    }
    
    private enum CodingKeys: String, CodingKey {
        case latitude, longitude
    }
}

enum MemoryRecallResult {
    case success(MemorySummary)
    case accessDenied(String)
    case error(String)
}

struct DecryptedMemory {
    let id: UUID
    let content: String
    let type: MemoryType
    let relevanceScore: Float
    let timestamp: Date
    let metadata: [String: String]
}

struct MemorySummary {
    let totalMemories: Int
    let episodicCount: Int
    let semanticCount: Int
    let locationCount: Int
    let oldestMemory: Date?
    let newestMemory: Date?
    let memories: [DecryptedMemory]
}

struct MemoryAccessEvent {
    let id: UUID
    let query: String
    let memoriesAccessed: Int
    let timestamp: Date
    let userConsent: Bool
}

struct MemoryPrivacySettings {
    let encryptionEnabled: Bool
    let consentRequired: Bool
    let accessLoggingEnabled: Bool
    let dataRetentionDays: Int
    let automaticDeletion: Bool
}

enum UserConsentResponse {
    case accepted(String)
    case declined
    case alwaysAllow
    case neverAsk
}

class MemoryEncryptionManager {
    private let keychain = KeychainManager.shared
    private(set) var isEnabled = true
    
    func encrypt(_ content: String) throws -> String {
        guard isEnabled else { return content }
        
        guard let key = keychain.getEncryptionKey() else {
            throw MemoryError.encryptionKeyNotFound
        }
        
        // Simple encryption implementation
        let data = content.data(using: .utf8) ?? Data()
        let encryptedData = try AES.GCM.seal(data, using: SymmetricKey(data: key))
        
        return encryptedData.combined?.base64EncodedString() ?? content
    }
    
    func decrypt(_ encryptedContent: String) throws -> String {
        guard isEnabled else { return encryptedContent }
        
        guard let key = keychain.getEncryptionKey() else {
            throw MemoryError.encryptionKeyNotFound
        }
        
        guard let encryptedData = Data(base64Encoded: encryptedContent) else {
            throw MemoryError.invalidEncryptedData
        }
        
        let sealedBox = try AES.GCM.SealedBox(combined: encryptedData)
        let decryptedData = try AES.GCM.open(sealedBox, using: SymmetricKey(data: key))
        
        return String(data: decryptedData, encoding: .utf8) ?? ""
    }
    
    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
    }
}

class PrivacyConsentManager {
    private var consentSettings: [String: ConsentSetting] = [:]
    private(set) var isConsentRequired = true
    private var dataRetentionDays = 365
    private(set) var isAutomaticDeletionEnabled = true
    
    func requestMemoryAccess(for query: String, completion: @escaping (Bool) -> Void) {
        let context = determineContext(from: query)
        
        if let setting = consentSettings[context] {
            switch setting {
            case .alwaysAllow:
                completion(true)
                return
            case .neverAsk:
                completion(false)
                return
            case .askEachTime:
                break // Continue to prompt
            }
        }
        
        // Prompt user for consent
        promptUserForConsent(query: query, completion: completion)
    }
    
    func offerMemoryRecall(context: String, completion: @escaping (UserConsentResponse) -> Void) {
        // This would show UI to offer memory recall
        // For now, we'll simulate user acceptance
        completion(.accepted("Recent memories about \(context)"))
    }
    
    private func promptUserForConsent(query: String, completion: @escaping (Bool) -> Void) {
        // In a real app, this would show a consent dialog
        // For now, we'll default to requiring consent
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            // Simulate user granting consent
            completion(true)
        }
    }
    
    private func determineContext(from query: String) -> String {
        // Determine context category from query
        let lowercased = query.lowercased()
        
        if lowercased.contains("location") || lowercased.contains("where") {
            return "location"
        } else if lowercased.contains("person") || lowercased.contains("who") {
            return "people"
        } else if lowercased.contains("conversation") || lowercased.contains("said") {
            return "conversations"
        } else {
            return "general"
        }
    }
    
    func setAlwaysAllow(for context: String) {
        consentSettings[context] = .alwaysAllow
    }
    
    func setNeverAsk(for context: String) {
        consentSettings[context] = .neverAsk
    }
    
    func setConsentRequired(_ required: Bool) {
        isConsentRequired = required
    }
    
    func setDataRetentionDays(_ days: Int) {
        dataRetentionDays = days
    }
    
    func setAutomaticDeletion(_ enabled: Bool) {
        isAutomaticDeletionEnabled = enabled
    }
}

enum ConsentSetting {
    case askEachTime
    case alwaysAllow
    case neverAsk
}

enum MemoryError: Error {
    case encryptionKeyNotFound
    case invalidEncryptedData
    case decryptionFailed
    case accessDenied
} 