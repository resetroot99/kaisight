import Foundation

struct Config {
    // MARK: - API Keys (Replace with your actual keys)
    static let openAIAPIKey = "your-openai-api-key-here"
    
    // MARK: - Testing Configuration
    static let isTestMode = true
    static let enableDebugLogging = true
    
    // MARK: - API Endpoints
    static let whisperAPIURL = "https://api.openai.com/v1/audio/transcriptions"
    static let gptAPIURL = "https://api.openai.com/v1/chat/completions"
    
    // MARK: - Default Settings for Testing
    static let defaultSpeechRate: Float = 0.45
    static let defaultSpeechPitch: Float = 1.0
    static let defaultSpeechVolume: Float = 1.0
    static let defaultRecordingDuration: Double = 5.0
    
    // MARK: - Test Data
    static let testHomeAddress = "1 Apple Park Way, Cupertino, CA"
    static let testEmergencyContacts = [
        ("Test Mom", "555-0001", "Mother"),
        ("Test Dad", "555-0002", "Father"),
        ("Test Friend", "555-0003", "Friend")
    ]
    
    // MARK: - Feature Flags
    static let enableOfflineMode = true
    static let enableObjectDetection = true
    static let enableNavigation = true
    static let enableEmergencyFeatures = true
    
    // MARK: - Debug Messages
    static func debugLog(_ message: String) {
        if enableDebugLogging {
            print("🔍 BlindAssistant Debug: \(message)")
        }
    }
}

// MARK: - API Key Validation
extension Config {
    static var hasValidOpenAIKey: Bool {
        return openAIAPIKey != "your-openai-api-key-here" && 
               openAIAPIKey.hasPrefix("sk-") && 
               openAIAPIKey.count > 20
    }
    
    static func validateConfiguration() -> [String] {
        var issues: [String] = []
        
        if !hasValidOpenAIKey {
            issues.append("OpenAI API key not configured")
        }
        
        return issues
    }
} 