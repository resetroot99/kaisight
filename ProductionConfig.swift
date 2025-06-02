import Foundation

/// Production configuration for KaiSight App Store release
struct ProductionConfig {
    
    // MARK: - Build Configuration
    
    static let isProduction = true
    static let isDebugMode = false
    static let enableDetailedLogging = false
    
    // MARK: - App Information
    
    static let appName = "KaiSight"
    static let appVersion = "1.0.0"
    static let buildNumber = "1"
    static let bundleIdentifier = "com.kaisight.app"
    
    // MARK: - API Configuration
    
    struct APIKeys {
        // Replace with actual production API keys before submission
        static let openAIAPIKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"] ?? ""
        static let emergencyServicesAPIKey = ProcessInfo.processInfo.environment["EMERGENCY_API_KEY"] ?? ""
        
        // Validate API keys are present
        static func validateAPIKeys() -> Bool {
            return !openAIAPIKey.isEmpty
        }
    }
    
    // MARK: - Feature Flags
    
    struct Features {
        static let enableHealthMonitoring = true
        static let enableEmergencyServices = true
        static let enableAIFeatures = true
        static let enableSpatialMapping = true
        static let enableCommunityFeatures = true
        static let enableAdvancedAudio = true
        static let enableCloudSync = false // Start with local-only for privacy
    }
    
    // MARK: - Performance Limits
    
    struct Performance {
        static let maxMemoryUsageMB = 200
        static let maxAudioBufferSize = 1024 * 1024 // 1MB
        static let networkTimeoutSeconds = 30.0
        static let maxVoiceRecognitionDuration = 60.0
        static let maxHealthDataRetentionDays = 30
    }
    
    // MARK: - Privacy Settings
    
    struct Privacy {
        static let enableLocalProcessing = true
        static let enableDataEncryption = true
        static let enableBiometricAuth = true
        static let anonymizeAnalytics = true
        static let autoDeleteSensitiveData = true
    }
    
    // MARK: - Accessibility Configuration
    
    struct Accessibility {
        static let enableVoiceOverOptimizations = true
        static let enableHapticFeedback = true
        static let enableHighContrastMode = true
        static let enableLargeTextSupport = true
        static let defaultSpeechRate: Float = 0.5
        static let enableSpatialAudio = true
    }
    
    // MARK: - Health & Medical Settings
    
    struct Health {
        static let enableHealthKitIntegration = true
        static let requireMedicalDisclaimers = true
        static let enableEmergencyDetection = true
        static let maxEmergencyResponseTime = 30.0 // seconds
        static let enableCaregiverNotifications = true
    }
    
    // MARK: - Logging Configuration
    
    struct Logging {
        static let enableCrashReporting = true
        static let enablePerformanceLogging = true
        static let enableUserAnalytics = false // Privacy-first approach
        static let logLevel: LogLevel = .error
        
        enum LogLevel: String {
            case verbose = "VERBOSE"
            case debug = "DEBUG"
            case info = "INFO"
            case warning = "WARNING"
            case error = "ERROR"
        }
    }
    
    // MARK: - Production Logging
    
    static func log(_ message: String, level: Logging.LogLevel = .info, file: String = #file, function: String = #function, line: Int = #line) {
        guard level.rawValue.count >= Logging.logLevel.rawValue.count else { return }
        
        let filename = (file as NSString).lastPathComponent
        let timestamp = DateFormatter.logFormatter.string(from: Date())
        
        if enableDetailedLogging {
            NSLog("[\(timestamp)] [\(level.rawValue)] KaiSight[\(filename):\(line)] \(function): \(message)")
        } else if level == .error {
            NSLog("[ERROR] KaiSight: \(message)")
        }
    }
    
    // MARK: - Validation
    
    static func validateProductionReadiness() -> (isReady: Bool, issues: [String]) {
        var issues: [String] = []
        
        // Check API keys
        if !APIKeys.validateAPIKeys() {
            issues.append("OpenAI API key not configured")
        }
        
        // Check required features
        if !Features.enableHealthMonitoring {
            issues.append("Health monitoring must be enabled for production")
        }
        
        if !Features.enableEmergencyServices {
            issues.append("Emergency services must be enabled for production")
        }
        
        // Check privacy settings
        if !Privacy.enableDataEncryption {
            issues.append("Data encryption must be enabled for production")
        }
        
        // Check accessibility
        if !Accessibility.enableVoiceOverOptimizations {
            issues.append("VoiceOver optimizations must be enabled for production")
        }
        
        return (issues.isEmpty, issues)
    }
}

// MARK: - Extensions

extension DateFormatter {
    static let logFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter
    }()
}

// MARK: - Production Utilities

extension ProductionConfig {
    
    /// Check if running in production environment
    static var isProductionBuild: Bool {
        #if DEBUG
        return false
        #else
        return true
        #endif
    }
    
    /// Secure configuration check
    static func performSecurityCheck() -> Bool {
        // Ensure no debug configurations in production
        guard isProductionBuild else { return false }
        guard !isDebugMode else { return false }
        guard Privacy.enableDataEncryption else { return false }
        
        return true
    }
} 