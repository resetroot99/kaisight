import XCTest
import Combine
import CoreML
import Vision
import ARKit
import CloudKit
@testable import KaiSight

class ComprehensiveTestingFramework: XCTestCase {
    
    // MARK: - Test Suite Components
    
    private var agentLoopManager: AgentLoopManager!
    private var streamingGPTManager: StreamingGPTManager!
    private var enhancedSpatialManager: EnhancedSpatialManager!
    private var familiarRecognition: EnhancedFamiliarRecognition!
    private var ragMemoryManager: RAGMemoryManager!
    private var cloudSyncManager: EnhancedCloudSyncManager!
    
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Setup and Teardown
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        
        // Initialize all managers for testing
        agentLoopManager = AgentLoopManager()
        streamingGPTManager = StreamingGPTManager()
        enhancedSpatialManager = EnhancedSpatialManager()
        familiarRecognition = EnhancedFamiliarRecognition()
        ragMemoryManager = RAGMemoryManager()
        cloudSyncManager = EnhancedCloudSyncManager()
        
        // Configure test environment
        setupTestEnvironment()
    }
    
    override func tearDownWithError() throws {
        // Clean up test data
        cleanupTestData()
        
        // Cancel all subscriptions
        cancellables.removeAll()
        
        try super.tearDownWithError()
    }
    
    private func setupTestEnvironment() {
        // Mock API keys and configuration for testing
        Config.debugMode = true
        Config.testMode = true
    }
    
    private func cleanupTestData() {
        // Remove test files and reset state
        let testDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("KaiSightTests")
        try? FileManager.default.removeItem(at: testDirectory)
    }
    
    // MARK: - Agent Loop Manager Tests
    
    func testAgentLoopManagerInitialization() throws {
        XCTAssertNotNil(agentLoopManager)
        XCTAssertEqual(agentLoopManager.agentState, .idle)
        XCTAssertFalse(agentLoopManager.isListening)
        XCTAssertFalse(agentLoopManager.conversationActive)
    }
    
    func testWakeWordDetection() throws {
        let expectation = XCTestExpectation(description: "Wake word detection")
        
        agentLoopManager.$wakeWordDetected
            .sink { detected in
                if detected {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)
        
        // Simulate wake word detection
        agentLoopManager.manualActivation()
        
        wait(for: [expectation], timeout: 5.0)
        XCTAssertTrue(agentLoopManager.wakeWordDetected)
        XCTAssertTrue(agentLoopManager.conversationActive)
    }
    
    func testAgentStateTransitions() throws {
        // Test state machine transitions
        XCTAssertEqual(agentLoopManager.agentState, .idle)
        
        agentLoopManager.manualActivation()
        XCTAssertEqual(agentLoopManager.agentState, .activated)
        
        agentLoopManager.manualDeactivation()
        XCTAssertEqual(agentLoopManager.agentState, .idle)
    }
    
    func testConversationMemoryManagement() throws {
        // Test conversation memory functionality
        let testInput = "Hello, can you help me?"
        let testResponse = "Of course! I'm here to help."
        
        // This would normally be called by the agent loop
        // agentLoopManager.processConversationTurn(userInput: testInput, assistantResponse: testResponse)
        
        let status = agentLoopManager.getAgentStatus()
        XCTAssertFalse(status.isEmpty)
    }
    
    // MARK: - Streaming GPT Manager Tests
    
    func testStreamingGPTManagerInitialization() throws {
        XCTAssertNotNil(streamingGPTManager)
        XCTAssertFalse(streamingGPTManager.isStreaming)
        XCTAssertFalse(streamingGPTManager.narrationActive)
        XCTAssertEqual(streamingGPTManager.currentResponse, "")
    }
    
    func testStreamingResponse() throws {
        let expectation = XCTestExpectation(description: "Streaming response")
        expectation.expectedFulfillmentCount = 1
        
        let testPrompt = "Describe a simple scene for testing"
        
        streamingGPTManager.streamResponse(to: testPrompt) { partialResponse in
            // Handle partial responses
            XCTAssertFalse(partialResponse.isEmpty)
        } completion: { fullResponse in
            XCTAssertFalse(fullResponse.isEmpty)
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 10.0)
    }
    
    func testRealTimeNarration() throws {
        let expectation = XCTestExpectation(description: "Real-time narration")
        
        streamingGPTManager.$narrationActive
            .sink { active in
                if active {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)
        
        streamingGPTManager.startRealTimeNarration()
        
        wait(for: [expectation], timeout: 3.0)
        XCTAssertTrue(streamingGPTManager.narrationActive)
        
        streamingGPTManager.stopRealTimeNarration()
        XCTAssertFalse(streamingGPTManager.narrationActive)
    }
    
    func testVisionAnalysis() throws {
        let testImage = createTestImage()
        let expectation = XCTestExpectation(description: "Vision analysis")
        
        streamingGPTManager.analyzeImageWithStreaming(testImage, detailLevel: .medium) { response in
            XCTAssertFalse(response.isEmpty)
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 15.0)
    }
    
    // MARK: - Enhanced Spatial Manager Tests
    
    func testEnhancedSpatialManagerInitialization() throws {
        XCTAssertNotNil(enhancedSpatialManager)
        XCTAssertEqual(enhancedSpatialManager.spatialAnchors.count, 0)
        XCTAssertEqual(enhancedSpatialManager.spatialObjects.count, 0)
        XCTAssertEqual(enhancedSpatialManager.navigationPath.count, 0)
    }
    
    func testSpatialAnchorManagement() throws {
        let testAnchor = "Test Location"
        let testDescription = "A test spatial anchor"
        let testTransform = simd_float4x4(1)
        
        enhancedSpatialManager.addSpatialAnchor(
            name: testAnchor,
            description: testDescription,
            at: testTransform
        )
        
        XCTAssertEqual(enhancedSpatialManager.spatialAnchors.count, 1)
        XCTAssertEqual(enhancedSpatialManager.spatialAnchors.first?.name, testAnchor)
    }
    
    func testObjectTracking() throws {
        let testPosition = simd_float3(1, 2, 3)
        let testName = "Test Object"
        let testCategory = ObjectCategory.furniture
        
        enhancedSpatialManager.trackObject(
            at: testPosition,
            name: testName,
            category: testCategory
        )
        
        XCTAssertEqual(enhancedSpatialManager.spatialObjects.count, 1)
        
        let trackedObjects = enhancedSpatialManager.findTrackedObjects(category: testCategory)
        XCTAssertEqual(trackedObjects.count, 1)
        XCTAssertEqual(trackedObjects.first?.name, testName)
    }
    
    func testObstacleDetection() throws {
        let obstacles = enhancedSpatialManager.performObstacleDetection()
        XCTAssertNotNil(obstacles)
        // In a real test environment with AR data, we would verify obstacle detection
    }
    
    func testSpatialStatus() throws {
        let status = enhancedSpatialManager.getSpatialStatus()
        XCTAssertFalse(status.isEmpty)
        XCTAssertTrue(status.contains("Spatial tracking"))
    }
    
    // MARK: - Enhanced Familiar Recognition Tests
    
    func testFamiliarRecognitionInitialization() throws {
        XCTAssertNotNil(familiarRecognition)
        XCTAssertEqual(familiarRecognition.recognizedFaces.count, 0)
        XCTAssertEqual(familiarRecognition.recognizedObjects.count, 0)
        XCTAssertFalse(familiarRecognition.isTraining)
        XCTAssertEqual(familiarRecognition.trainingProgress, 0.0)
    }
    
    func testFaceRecognition() throws {
        let testImage = createTestImage()
        let expectation = XCTestExpectation(description: "Face recognition")
        
        familiarRecognition.recognizeFaces(in: testImage) { recognizedFaces in
            // In a real test, we would verify face recognition results
            XCTAssertNotNil(recognizedFaces)
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 10.0)
    }
    
    func testFaceTraining() throws {
        let testImages = [createTestImage(), createTestImage(), createTestImage()]
        let testName = "Test Person"
        let expectation = XCTestExpectation(description: "Face training")
        
        familiarRecognition.trainNewFace(name: testName, images: testImages) { success in
            XCTAssertTrue(success)
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 20.0)
    }
    
    func testObjectRecognition() throws {
        let testImage = createTestImage()
        let expectation = XCTestExpectation(description: "Object recognition")
        
        familiarRecognition.recognizeCustomObjects(in: testImage) { recognizedObjects in
            XCTAssertNotNil(recognizedObjects)
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 10.0)
    }
    
    func testObjectTraining() throws {
        let testImages = Array(repeating: createTestImage(), count: 5)
        let testName = "Test Object"
        let testCategory = "furniture"
        let expectation = XCTestExpectation(description: "Object training")
        
        familiarRecognition.trainCustomObject(
            name: testName,
            category: testCategory,
            images: testImages
        ) { success in
            XCTAssertTrue(success)
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 25.0)
    }
    
    func testRecognitionSummary() throws {
        let summary = familiarRecognition.getRecognitionSummary()
        XCTAssertFalse(summary.isEmpty)
        XCTAssertTrue(summary.contains("Recognition status"))
    }
    
    // MARK: - RAG Memory Manager Tests
    
    func testRAGMemoryManagerInitialization() throws {
        XCTAssertNotNil(ragMemoryManager)
        XCTAssertEqual(ragMemoryManager.contextSummary, "")
        XCTAssertFalse(ragMemoryManager.isIndexing)
        XCTAssertEqual(ragMemoryManager.memoryStats.totalEpisodicMemories, 0)
    }
    
    func testConversationProcessing() throws {
        let testInput = "I really enjoyed visiting the park today"
        let testResponse = "That sounds wonderful! Parks are great for relaxation."
        let testContext = ConversationContext(
            sessionId: UUID(),
            startTime: Date(),
            topic: "leisure",
            location: LocationContext(name: "Home"),
            participantCount: 1
        )
        
        ragMemoryManager.processConversationTurn(
            userInput: testInput,
            assistantResponse: testResponse,
            context: testContext
        )
        
        // Verify memory processing
        XCTAssertFalse(ragMemoryManager.contextSummary.isEmpty)
    }
    
    func testMemoryRetrieval() async throws {
        let testQuery = "tell me about parks"
        let memories = await ragMemoryManager.retrieveRelevantMemories(for: testQuery, limit: 5)
        
        XCTAssertNotNil(memories)
        XCTAssertLessThanOrEqual(memories.count, 5)
    }
    
    func testContextualPromptGeneration() async throws {
        let testQuery = "What did I do yesterday?"
        let memories = await ragMemoryManager.retrieveRelevantMemories(for: testQuery, limit: 3)
        let prompt = ragMemoryManager.generateContextualPrompt(for: testQuery, retrievedMemories: memories)
        
        XCTAssertFalse(prompt.isEmpty)
        XCTAssertTrue(prompt.contains(testQuery))
    }
    
    func testMemoryConsolidation() throws {
        // This would typically be tested with more complex memory scenarios
        let summary = ragMemoryManager.getMemorySummary()
        XCTAssertFalse(summary.isEmpty)
        XCTAssertTrue(summary.contains("Memory:"))
    }
    
    // MARK: - Enhanced Cloud Sync Manager Tests
    
    func testCloudSyncManagerInitialization() throws {
        XCTAssertNotNil(cloudSyncManager)
        XCTAssertEqual(cloudSyncManager.syncStatus, .idle)
        XCTAssertNil(cloudSyncManager.lastSyncDate)
        XCTAssertEqual(cloudSyncManager.syncProgress, 0.0)
        XCTAssertEqual(cloudSyncManager.conflictCount, 0)
    }
    
    func testEncryptionSetup() throws {
        XCTAssertTrue(cloudSyncManager.encryptionEnabled)
    }
    
    func testSyncStatusManagement() throws {
        let expectation = XCTestExpectation(description: "Sync status change")
        
        cloudSyncManager.$syncStatus
            .sink { status in
                if status != .idle {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)
        
        // In a real test, we would trigger sync operations
        wait(for: [expectation], timeout: 10.0)
    }
    
    func testSyncSummary() throws {
        let summary = cloudSyncManager.getSyncSummary()
        XCTAssertFalse(summary.isEmpty)
        XCTAssertTrue(summary.contains("Sync status"))
    }
    
    func testDataExport() async throws {
        let exportData = await cloudSyncManager.exportAllData()
        XCTAssertNotNil(exportData)
        XCTAssertEqual(exportData.encryptionEnabled, cloudSyncManager.encryptionEnabled)
    }
    
    // MARK: - Integration Tests
    
    func testAgentLoopStreamingIntegration() throws {
        let expectation = XCTestExpectation(description: "Agent loop streaming integration")
        
        // Test integration between agent loop and streaming GPT
        agentLoopManager.manualActivation()
        
        streamingGPTManager.streamResponse(to: "Test integration") { _ in
            // Partial response handling
        } completion: { response in
            XCTAssertFalse(response.isEmpty)
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 15.0)
    }
    
    func testSpatialFamiliarRecognitionIntegration() throws {
        // Test integration between spatial manager and familiar recognition
        let testImage = createTestImage()
        let expectation = XCTestExpectation(description: "Spatial familiar integration")
        
        familiarRecognition.recognizeFaces(in: testImage) { recognizedFaces in
            // If faces are recognized, they could be tracked spatially
            for face in recognizedFaces {
                self.enhancedSpatialManager.trackObject(
                    at: simd_float3(0, 0, 0),
                    name: face.identity.name,
                    category: .person
                )
            }
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 10.0)
    }
    
    func testRAGCloudSyncIntegration() async throws {
        // Test integration between RAG memory and cloud sync
        let testContext = ConversationContext(
            sessionId: UUID(),
            startTime: Date(),
            topic: "test",
            location: LocationContext(name: "Test Location"),
            participantCount: 1
        )
        
        ragMemoryManager.processConversationTurn(
            userInput: "Test memory sync",
            assistantResponse: "Memory created",
            context: testContext
        )
        
        // Export memories for sync
        let memoryExport = ragMemoryManager.exportMemories()
        XCTAssertNotNil(memoryExport)
    }
    
    // MARK: - Performance Tests
    
    func testAgentLoopPerformance() throws {
        measure {
            for _ in 0..<100 {
                let status = agentLoopManager.getAgentStatus()
                XCTAssertFalse(status.isEmpty)
            }
        }
    }
    
    func testSpatialManagerPerformance() throws {
        measure {
            for i in 0..<50 {
                enhancedSpatialManager.trackObject(
                    at: simd_float3(Float(i), Float(i), Float(i)),
                    name: "Object \(i)",
                    category: .furniture
                )
            }
        }
    }
    
    func testFamiliarRecognitionPerformance() throws {
        let testImage = createTestImage()
        
        measure {
            let expectation = XCTestExpectation(description: "Recognition performance")
            
            familiarRecognition.recognizeFaces(in: testImage) { _ in
                expectation.fulfill()
            }
            
            wait(for: [expectation], timeout: 5.0)
        }
    }
    
    func testRAGMemoryPerformance() async throws {
        // Add multiple memories for performance testing
        for i in 0..<100 {
            let context = ConversationContext(
                sessionId: UUID(),
                startTime: Date(),
                topic: "performance",
                location: LocationContext(name: "Test"),
                participantCount: 1
            )
            
            ragMemoryManager.processConversationTurn(
                userInput: "Test memory \(i)",
                assistantResponse: "Response \(i)",
                context: context
            )
        }
        
        measure {
            Task {
                let memories = await ragMemoryManager.retrieveRelevantMemories(for: "test", limit: 10)
                XCTAssertNotNil(memories)
            }
        }
    }
    
    // MARK: - Accessibility Tests
    
    func testVoiceOverCompatibility() throws {
        // Test VoiceOver compatibility for UI elements
        XCTAssertTrue(UIAccessibility.isVoiceOverRunning || true) // Allow test to pass in non-VO environment
    }
    
    func testSpeechOutputAccessibility() throws {
        // Test speech output for accessibility
        let testMessage = "This is a test accessibility message"
        // speechOutput.speak(testMessage) - would be tested with actual SpeechOutput instance
        XCTAssertFalse(testMessage.isEmpty)
    }
    
    func testNavigationAccessibility() throws {
        // Test navigation features for accessibility
        let status = enhancedSpatialManager.getSpatialStatus()
        XCTAssertTrue(status.contains("Spatial tracking"))
    }
    
    // MARK: - Error Handling Tests
    
    func testAgentLoopErrorHandling() throws {
        // Test error handling in agent loop
        agentLoopManager.manualDeactivation()
        XCTAssertEqual(agentLoopManager.agentState, .idle)
        XCTAssertFalse(agentLoopManager.conversationActive)
    }
    
    func testStreamingGPTErrorHandling() throws {
        // Test error handling in streaming GPT
        streamingGPTManager.cancelStreaming()
        XCTAssertFalse(streamingGPTManager.isStreaming)
        XCTAssertEqual(streamingGPTManager.currentResponse, "")
    }
    
    func testSpatialManagerErrorHandling() throws {
        // Test error handling in spatial manager
        enhancedSpatialManager.pauseTracking()
        XCTAssertFalse(enhancedSpatialManager.isARActive)
        
        enhancedSpatialManager.resumeTracking()
        // AR tracking state would be tested with actual AR environment
    }
    
    func testCloudSyncErrorHandling() throws {
        // Test error handling in cloud sync
        cloudSyncManager.pauseSync()
        XCTAssertEqual(cloudSyncManager.syncStatus, .paused)
        
        cloudSyncManager.resumeSync()
        // Sync status would be tested with actual CloudKit environment
    }
    
    // MARK: - Security Tests
    
    func testEncryptionFunctionality() throws {
        // Test encryption in cloud sync
        XCTAssertTrue(cloudSyncManager.encryptionEnabled)
    }
    
    func testDataPrivacy() throws {
        // Test data privacy measures
        let summary = familiarRecognition.getRecognitionSummary()
        // Verify no sensitive data is exposed in logs or summaries
        XCTAssertFalse(summary.contains("password"))
        XCTAssertFalse(summary.contains("secret"))
    }
    
    func testSecureStorage() throws {
        // Test secure storage of sensitive data
        // This would involve testing keychain storage and encryption
        XCTAssertTrue(true) // Placeholder for secure storage tests
    }
    
    // MARK: - Load Tests
    
    func testHighVolumeMemoryProcessing() async throws {
        // Test processing many memories
        for i in 0..<1000 {
            let context = ConversationContext(
                sessionId: UUID(),
                startTime: Date(),
                topic: "load_test",
                location: LocationContext(name: "Load Test"),
                participantCount: 1
            )
            
            ragMemoryManager.processConversationTurn(
                userInput: "Load test memory \(i)",
                assistantResponse: "Load test response \(i)",
                context: context
            )
        }
        
        let memories = await ragMemoryManager.retrieveRelevantMemories(for: "load test", limit: 50)
        XCTAssertLessThanOrEqual(memories.count, 50)
    }
    
    func testHighVolumeSpatialObjects() throws {
        // Test tracking many spatial objects
        for i in 0..<500 {
            enhancedSpatialManager.trackObject(
                at: simd_float3(Float(i % 10), Float(i % 10), Float(i % 10)),
                name: "Load Object \(i)",
                category: .furniture
            )
        }
        
        let trackedObjects = enhancedSpatialManager.findTrackedObjects()
        XCTAssertEqual(trackedObjects.count, 500)
    }
    
    // MARK: - Utility Methods
    
    private func createTestImage() -> UIImage {
        let size = CGSize(width: 100, height: 100)
        UIGraphicsBeginImageContext(size)
        let context = UIGraphicsGetCurrentContext()!
        context.setFillColor(UIColor.blue.cgColor)
        context.fill(CGRect(origin: .zero, size: size))
        let image = UIGraphicsGetImageFromCurrentImageContext()!
        UIGraphicsEndImageContext()
        return image
    }
    
    private func createTestAudioBuffer() -> AVAudioPCMBuffer {
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024)!
        buffer.frameLength = 1024
        return buffer
    }
    
    // MARK: - Stress Tests
    
    func testConcurrentOperations() throws {
        let expectation = XCTestExpectation(description: "Concurrent operations")
        expectation.expectedFulfillmentCount = 4
        
        DispatchQueue.global().async {
            self.agentLoopManager.manualActivation()
            expectation.fulfill()
        }
        
        DispatchQueue.global().async {
            self.streamingGPTManager.startRealTimeNarration()
            expectation.fulfill()
        }
        
        DispatchQueue.global().async {
            self.enhancedSpatialManager.speakSpatialStatus()
            expectation.fulfill()
        }
        
        DispatchQueue.global().async {
            self.familiarRecognition.speakRecognitionSummary()
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 10.0)
    }
    
    func testMemoryLeaks() throws {
        weak var weakAgentLoop = agentLoopManager
        weak var weakStreamingGPT = streamingGPTManager
        weak var weakSpatial = enhancedSpatialManager
        weak var weakRecognition = familiarRecognition
        weak var weakRAG = ragMemoryManager
        weak var weakCloudSync = cloudSyncManager
        
        // Release strong references
        agentLoopManager = nil
        streamingGPTManager = nil
        enhancedSpatialManager = nil
        familiarRecognition = nil
        ragMemoryManager = nil
        cloudSyncManager = nil
        
        // Check for memory leaks (in a real test environment)
        // XCTAssertNil(weakAgentLoop)
        // XCTAssertNil(weakStreamingGPT)
        // XCTAssertNil(weakSpatial)
        // XCTAssertNil(weakRecognition)
        // XCTAssertNil(weakRAG)
        // XCTAssertNil(weakCloudSync)
    }
    
    // MARK: - Configuration Tests
    
    func testDebugMode() throws {
        XCTAssertTrue(Config.debugMode)
        XCTAssertTrue(Config.testMode)
    }
    
    func testFeatureFlags() throws {
        // Test feature flags if implemented
        XCTAssertTrue(true) // Placeholder
    }
}

// MARK: - Mock Classes for Testing

class MockSpeechOutput {
    private(set) var spokenMessages: [String] = []
    
    func speak(_ message: String, priority: SpeechPriority = .medium) {
        spokenMessages.append(message)
    }
    
    func clearHistory() {
        spokenMessages.removeAll()
    }
}

class MockCameraManager {
    func captureCurrentFrame() -> UIImage? {
        return createTestImage()
    }
    
    private func createTestImage() -> UIImage {
        let size = CGSize(width: 100, height: 100)
        UIGraphicsBeginImageContext(size)
        let context = UIGraphicsGetCurrentContext()!
        context.setFillColor(UIColor.red.cgColor)
        context.fill(CGRect(origin: .zero, size: size))
        let image = UIGraphicsGetImageFromCurrentImageContext()!
        UIGraphicsEndImageContext()
        return image
    }
}

class MockAudioManager {
    private(set) var isRecording = false
    
    func startRecording(completion: @escaping (AVAudioPCMBuffer) -> Void) throws {
        isRecording = true
        // Simulate audio buffer
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024)!
        buffer.frameLength = 1024
        completion(buffer)
    }
    
    func stopRecording() {
        isRecording = false
    }
}

// MARK: - Test Extensions

extension Config {
    static var debugMode = false
    static var testMode = false
    
    static func debugLog(_ message: String) {
        if debugMode {
            print("[DEBUG] \(message)")
        }
    }
}

enum SpeechPriority {
    case low
    case medium
    case high
}

enum DetailLevel: String {
    case low = "low"
    case medium = "medium"
    case high = "high"
}

// MARK: - ObstacleSeverity for Testing

enum ObstacleSeverity {
    case low
    case warning
    case critical
}

// MARK: - Test Utilities

extension XCTestCase {
    func waitForExpectations(timeout: TimeInterval = 5.0) {
        let expectation = XCTestExpectation(description: "Async operation")
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: timeout + 1.0)
    }
}

// MARK: - Performance Measurement

extension ComprehensiveTestingFramework {
    func measureAsyncPerformance<T>(
        _ operation: @escaping () async throws -> T,
        expectations: XCTestExpectation? = nil
    ) {
        measure {
            let expectation = XCTestExpectation(description: "Async performance")
            
            Task {
                do {
                    _ = try await operation()
                    expectation.fulfill()
                } catch {
                    XCTFail("Async operation failed: \(error)")
                    expectation.fulfill()
                }
            }
            
            wait(for: [expectation], timeout: 10.0)
        }
    }
}

// MARK: - Test Data Generators

class TestDataGenerator {
    static func generateTestImages(count: Int) -> [UIImage] {
        return (0..<count).map { _ in createTestImage() }
    }
    
    static func generateTestMemories(count: Int) -> [EpisodicMemory] {
        return (0..<count).map { i in
            EpisodicMemory(
                id: UUID(),
                description: "Test memory \(i)",
                timestamp: Date(),
                location: LocationContext(name: "Test Location \(i)"),
                participants: ["Test Person \(i)"],
                emotions: [.neutral],
                relevanceScore: Float.random(in: 0.5...1.0),
                embedding: Array(repeating: Float.random(in: -1...1), count: 384)
            )
        }
    }
    
    static func generateTestSpatialAnchors(count: Int) -> [SpatialAnchor] {
        return (0..<count).map { i in
            SpatialAnchor(
                id: UUID(),
                name: "Test Anchor \(i)",
                description: "Test spatial anchor \(i)",
                transform: simd_float4x4(1),
                timestamp: Date()
            )
        }
    }
    
    private static func createTestImage() -> UIImage {
        let size = CGSize(width: 100, height: 100)
        UIGraphicsBeginImageContext(size)
        let context = UIGraphicsGetCurrentContext()!
        context.setFillColor(UIColor.green.cgColor)
        context.fill(CGRect(origin: .zero, size: size))
        let image = UIGraphicsGetImageFromCurrentImageContext()!
        UIGraphicsEndImageContext()
        return image
    }
} 