import Foundation
import UserNotifications
import HealthKit

class HealthAlertEngine: ObservableObject {
    @Published var activeAlerts: [HealthAlert] = []
    @Published var alertHistory: [HealthAlert] = []
    @Published var isMonitoring = true
    
    weak var delegate: HealthAlertEngineDelegate?
    
    // Alert configuration
    private var currentThresholds: AlertThresholds = AlertThresholds.default
    private var alertRules: [AlertRule] = []
    private var alertSuppressionRules: [AlertSuppressionRule] = []
    
    // Pattern recognition
    private let patternAnalyzer = AlertPatternAnalyzer()
    private var recentReadings: [HealthReading] = []
    private let maxReadingHistory = 100
    
    // Alert timing and suppression
    private var lastAlertTimes: [AlertType: Date] = [:]
    private var suppressedAlerts: Set<AlertType> = []
    
    // Voice and haptic feedback
    private var speechOutput: SpeechOutput?
    private var hapticFeedback: HapticFeedbackManager?
    
    // AI-powered analysis
    private let aiAnalyzer = AIHealthAnalyzer()
    private let contextualEngine = ContextualAlertEngine()
    
    init() {
        setupDefaultAlertRules()
        setupNotifications()
        
        // Use shared speech output by default
        self.speechOutput = SpeechOutput.shared
    }
    
    // MARK: - Configuration
    
    func configure(speechOutput: SpeechOutput, hapticFeedback: HapticFeedbackManager) {
        self.speechOutput = speechOutput
        self.hapticFeedback = hapticFeedback
    }
    
    func updateThresholds(_ profile: HealthProfile) {
        currentThresholds = AlertThresholds.from(profile: profile)
        updateAlertRules(for: profile)
        
        Config.debugLog("Alert thresholds updated for health profile")
    }
    
    private func updateAlertRules(for profile: HealthProfile) {
        alertRules.removeAll()
        
        // Diabetic alert rules
        if let diabeticProfile = profile.diabeticProfile {
            addDiabeticAlertRules(diabeticProfile)
        }
        
        // Cardiovascular alert rules
        if let cardioProfile = profile.cardiovascularProfile {
            addCardiovascularAlertRules(cardioProfile)
        }
        
        // General health alert rules
        addGeneralHealthAlertRules(profile)
        
        Config.debugLog("Updated \(alertRules.count) alert rules")
    }
    
    // MARK: - Core Alert Processing
    
    func processReading(_ reading: HealthReading) {
        // Add to recent readings
        recentReadings.append(reading)
        
        // Maintain reading history limit
        if recentReadings.count > maxReadingHistory {
            recentReadings.removeFirst(recentReadings.count - maxReadingHistory)
        }
        
        // Evaluate all alert rules
        evaluateAlertRules(for: reading)
        
        // Pattern-based analysis
        analyzePatterns(with: reading)
        
        // AI-powered contextual analysis
        performAIAnalysis(with: reading)
        
        // Check for compound alerts (multiple concerning readings)
        checkForCompoundAlerts()
    }
    
    private func evaluateAlertRules(for reading: HealthReading) {
        for rule in alertRules {
            if rule.appliesTo(reading) {
                let evaluation = rule.evaluate(reading, recentReadings: recentReadings, thresholds: currentThresholds)
                
                if let alert = evaluation.alert {
                    processTriggeredAlert(alert, from: rule)
                }
            }
        }
    }
    
    private func processTriggeredAlert(_ alert: HealthAlert, from rule: AlertRule) {
        // Check if alert should be suppressed
        if shouldSuppressAlert(alert) {
            Config.debugLog("Alert suppressed: \(alert.type)")
            return
        }
        
        // Add to active alerts
        activeAlerts.append(alert)
        alertHistory.append(alert)
        
        // Update last alert time
        lastAlertTimes[alert.type] = Date()
        
        // Notify delegate
        delegate?.alertEngine(self, didTriggerAlert: alert)
        
        // Send notification
        sendNotification(for: alert)
        
        // Log alert
        Config.debugLog("Health alert triggered: \(alert.type) - \(alert.severity)")
    }
    
    // MARK: - Alert Suppression Logic
    
    private func shouldSuppressAlert(_ alert: HealthAlert) -> Bool {
        // Check if alert type is currently suppressed
        if suppressedAlerts.contains(alert.type) {
            return true
        }
        
        // Check minimum time between similar alerts
        if let lastAlertTime = lastAlertTimes[alert.type] {
            let timeSinceLastAlert = Date().timeIntervalSince(lastAlertTime)
            let minimumInterval = getMinimumAlertInterval(for: alert.type, severity: alert.severity)
            
            if timeSinceLastAlert < minimumInterval {
                return true
            }
        }
        
        // Check custom suppression rules
        for suppressionRule in alertSuppressionRules {
            if suppressionRule.shouldSuppress(alert, recentAlerts: Array(alertHistory.suffix(10))) {
                return true
            }
        }
        
        return false
    }
    
    private func getMinimumAlertInterval(for alertType: AlertType, severity: AlertSeverity) -> TimeInterval {
        switch severity {
        case .emergency:
            return 60 // 1 minute for emergency alerts
        case .critical:
            return 300 // 5 minutes for critical alerts
        case .warning:
            return 900 // 15 minutes for warning alerts
        case .info:
            return 1800 // 30 minutes for info alerts
        }
    }
    
    // MARK: - Pattern Analysis
    
    private func analyzePatterns(with reading: HealthReading) {
        let analysis = patternAnalyzer.analyze(reading, recentReadings: recentReadings)
        
        for pattern in analysis.detectedPatterns {
            if pattern.isConcerning {
                let patternAlert = createPatternAlert(pattern, reading: reading)
                processTriggeredAlert(patternAlert, from: AlertRule.patternRule)
            }
        }
        
        // Check for trending concerns
        if let trend = analysis.detectTrend(reading.type) {
            if trend.isConcerning {
                let trendAlert = createTrendAlert(trend, reading: reading)
                processTriggeredAlert(trendAlert, from: AlertRule.trendRule)
            }
        }
    }
    
    private func performAIAnalysis(with reading: HealthReading) {
        aiAnalyzer.analyzeReading(reading, context: recentReadings) { [weak self] analysis in
            if let concerningInsight = analysis.insights.first(where: { $0.severity >= .warning }) {
                let aiAlert = self?.createAIAlert(concerningInsight, reading: reading)
                
                if let alert = aiAlert {
                    DispatchQueue.main.async {
                        self?.processTriggeredAlert(alert, from: AlertRule.aiRule)
                    }
                }
            }
        }
    }
    
    private func checkForCompoundAlerts() {
        let compoundAnalyzer = CompoundAlertAnalyzer()
        let compoundAlerts = compoundAnalyzer.analyze(recentReadings: recentReadings, thresholds: currentThresholds)
        
        for compoundAlert in compoundAlerts {
            processTriggeredAlert(compoundAlert, from: AlertRule.compoundRule)
        }
    }
    
    // MARK: - Alert Creation
    
    private func createPatternAlert(_ pattern: DetectedPattern, reading: HealthReading) -> HealthAlert {
        return HealthAlert(
            id: UUID(),
            type: .pattern,
            severity: pattern.severity,
            message: "Health pattern detected: \(pattern.description)",
            reading: reading,
            timestamp: Date(),
            metadata: [
                "pattern_type": pattern.type.rawValue,
                "confidence": String(pattern.confidence)
            ]
        )
    }
    
    private func createTrendAlert(_ trend: HealthTrend, reading: HealthReading) -> HealthAlert {
        return HealthAlert(
            id: UUID(),
            type: .trend,
            severity: trend.severity,
            message: "Health trend alert: \(trend.description)",
            reading: reading,
            timestamp: Date(),
            metadata: [
                "trend_direction": trend.direction.rawValue,
                "duration": String(trend.duration)
            ]
        )
    }
    
    private func createAIAlert(_ insight: AIHealthInsight, reading: HealthReading) -> HealthAlert {
        return HealthAlert(
            id: UUID(),
            type: .aiInsight,
            severity: insight.severity,
            message: insight.description,
            reading: reading,
            timestamp: Date(),
            metadata: [
                "ai_confidence": String(insight.confidence),
                "recommendation": insight.recommendation
            ]
        )
    }
    
    // MARK: - Diabetic Alert Rules
    
    private func addDiabeticAlertRules(_ profile: DiabeticProfile) {
        let thresholds = profile.glucoseThresholds
        
        // Severe hypoglycemia
        alertRules.append(AlertRule(
            type: .severeHypoglycemia,
            condition: { reading, _, _ in
                reading.type == .bloodGlucose && reading.value < Double(thresholds.veryLow)
            },
            severity: .emergency,
            message: "Severe low blood sugar detected: \(Int(thresholds.veryLow)) mg/dL. Take glucose immediately!"
        ))
        
        // Hypoglycemia
        alertRules.append(AlertRule(
            type: .hypoglycemia,
            condition: { reading, _, _ in
                reading.type == .bloodGlucose && reading.value < Double(thresholds.low)
            },
            severity: .critical,
            message: "Low blood sugar: \(Int(thresholds.low)) mg/dL. Consider eating."
        ))
        
        // Severe hyperglycemia
        alertRules.append(AlertRule(
            type: .severeHyperglycemia,
            condition: { reading, _, _ in
                reading.type == .bloodGlucose && reading.value > Double(thresholds.veryHigh)
            },
            severity: .emergency,
            message: "Very high blood sugar: \(Int(thresholds.veryHigh)) mg/dL. Check ketones and consider medical attention."
        ))
        
        // Hyperglycemia
        alertRules.append(AlertRule(
            type: .hyperglycemia,
            condition: { reading, _, _ in
                reading.type == .bloodGlucose && reading.value > Double(thresholds.high)
            },
            severity: .warning,
            message: "High blood sugar: \(Int(thresholds.high)) mg/dL. Consider insulin if needed."
        ))
        
        // Rapid glucose change
        alertRules.append(AlertRule(
            type: .rapidGlucoseChange,
            condition: { reading, recentReadings, _ in
                guard reading.type == .bloodGlucose,
                      let previousReading = recentReadings.last(where: { $0.type == .bloodGlucose && $0.id != reading.id }) else {
                    return false
                }
                
                let change = abs(reading.value - previousReading.value)
                let timeInterval = reading.timestamp.timeIntervalSince(previousReading.timestamp)
                
                // Alert if glucose changes more than 50 mg/dL in 15 minutes
                return change > 50 && timeInterval < 900
            },
            severity: .warning,
            message: "Rapid glucose change detected. Monitor closely."
        ))
    }
    
    // MARK: - Cardiovascular Alert Rules
    
    private func addCardiovascularAlertRules(_ profile: CardiovascularProfile) {
        let targetHR = profile.targetHeartRate
        let targetBP = profile.targetBloodPressure
        
        // Bradycardia
        alertRules.append(AlertRule(
            type: .bradycardia,
            condition: { reading, _, _ in
                reading.type == .heartRate && reading.value < Double(targetHR.lowerBound - 10)
            },
            severity: .warning,
            message: "Heart rate is low: \(Int(reading.value)) BPM."
        ))
        
        // Tachycardia
        alertRules.append(AlertRule(
            type: .tachycardia,
            condition: { reading, _, _ in
                reading.type == .heartRate && reading.value > Double(targetHR.upperBound + 20)
            },
            severity: .warning,
            message: "Heart rate is elevated: \(Int(reading.value)) BPM."
        ))
        
        // Severe tachycardia
        alertRules.append(AlertRule(
            type: .severeTachycardia,
            condition: { reading, _, _ in
                reading.type == .heartRate && reading.value > 150
            },
            severity: .critical,
            message: "Very high heart rate: \(Int(reading.value)) BPM. Consider medical attention."
        ))
        
        // Hypertensive crisis
        alertRules.append(AlertRule(
            type: .hypertensiveCrisis,
            condition: { reading, _, _ in
                guard reading.type == .bloodPressure,
                      let systolic = reading.additionalValues?["systolic"] else {
                    return false
                }
                return systolic > 180
            },
            severity: .emergency,
            message: "Blood pressure critically high. Seek immediate medical attention."
        ))
    }
    
    // MARK: - General Health Alert Rules
    
    private func addGeneralHealthAlertRules(_ profile: HealthProfile) {
        // Low oxygen saturation
        alertRules.append(AlertRule(
            type: .lowOxygenSaturation,
            condition: { reading, _, _ in
                reading.type == .oxygenSaturation && reading.value < 90
            },
            severity: .critical,
            message: "Oxygen saturation low: \(Int(reading.value))%. Check breathing."
        ))
        
        // High body temperature
        alertRules.append(AlertRule(
            type: .fever,
            condition: { reading, _, _ in
                reading.type == .temperature && reading.value > 38.0 // 38°C = 100.4°F
            },
            severity: .warning,
            message: "Elevated body temperature: \(String(format: "%.1f", reading.value))°C."
        ))
        
        // Fall detection
        alertRules.append(AlertRule(
            type: .fallDetected,
            condition: { reading, _, _ in
                reading.type == .movement && reading.isCritical
            },
            severity: .emergency,
            message: "Fall detected. Are you okay?"
        ))
    }
    
    // MARK: - Notification System
    
    private func setupNotifications() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if granted {
                Config.debugLog("Notification permissions granted")
            } else {
                Config.debugLog("Notification permissions denied")
            }
        }
    }
    
    private func sendNotification(for alert: HealthAlert) {
        let content = UNMutableNotificationContent()
        content.title = "Health Alert"
        content.body = alert.message
        content.categoryIdentifier = alert.type.rawValue
        
        // Set priority based on severity
        switch alert.severity {
        case .emergency:
            content.sound = UNNotificationSound.critical
            content.interruptionLevel = .critical
        case .critical:
            content.sound = UNNotificationSound.default
            content.interruptionLevel = .timeSensitive
        case .warning:
            content.sound = UNNotificationSound.default
            content.interruptionLevel = .active
        case .info:
            content.sound = nil
            content.interruptionLevel = .passive
        }
        
        // Add custom data
        content.userInfo = [
            "alert_id": alert.id.uuidString,
            "alert_type": alert.type.rawValue,
            "severity": alert.severity.rawValue,
            "reading_value": alert.reading.value
        ]
        
        let request = UNNotificationRequest(
            identifier: alert.id.uuidString,
            content: content,
            trigger: nil // Immediate delivery
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                Config.debugLog("Failed to send notification: \(error)")
            }
        }
    }
    
    // MARK: - Alert Management
    
    func acknowledgeAlert(_ alertId: UUID) {
        if let index = activeAlerts.firstIndex(where: { $0.id == alertId }) {
            activeAlerts[index].acknowledged = true
            activeAlerts[index].acknowledgedTime = Date()
        }
    }
    
    func dismissAlert(_ alertId: UUID) {
        activeAlerts.removeAll { $0.id == alertId }
    }
    
    func snoozeAlert(_ alertId: UUID, for duration: TimeInterval) {
        if let index = activeAlerts.firstIndex(where: { $0.id == alertId }) {
            let alert = activeAlerts[index]
            suppressedAlerts.insert(alert.type)
            
            // Remove suppression after duration
            DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                self.suppressedAlerts.remove(alert.type)
            }
            
            activeAlerts.remove(at: index)
        }
    }
    
    func suppressAlertType(_ alertType: AlertType, for duration: TimeInterval) {
        suppressedAlerts.insert(alertType)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            self.suppressedAlerts.remove(alertType)
        }
    }
    
    // MARK: - Default Configuration
    
    private func setupDefaultAlertRules() {
        alertRules = [
            AlertRule.defaultGlucoseRules,
            AlertRule.defaultHeartRateRules,
            AlertRule.defaultBloodPressureRules
        ].flatMap { $0 }
        
        alertSuppressionRules = [
            AlertSuppressionRule.duplicateAlertSuppression,
            AlertSuppressionRule.nightTimeSuppression,
            AlertSuppressionRule.exerciseModeSuppression
        ]
    }
    
    // MARK: - Public Interface
    
    func enableMonitoring() {
        isMonitoring = true
        speechOutput?.speak("Health monitoring enabled")
    }
    
    func disableMonitoring() {
        isMonitoring = false
        speechOutput?.speak("Health monitoring disabled")
    }
    
    func getActiveAlertsCount() -> Int {
        return activeAlerts.filter { !$0.acknowledged }.count
    }
    
    func getActiveAlertsSummary() -> String {
        let unacknowledgedAlerts = activeAlerts.filter { !$0.acknowledged }
        
        if unacknowledgedAlerts.isEmpty {
            return "No active alerts"
        }
        
        let criticalCount = unacknowledgedAlerts.filter { $0.severity == .critical || $0.severity == .emergency }.count
        let warningCount = unacknowledgedAlerts.filter { $0.severity == .warning }.count
        
        var summary = ""
        if criticalCount > 0 {
            summary += "\(criticalCount) critical alert\(criticalCount == 1 ? "" : "s")"
        }
        if warningCount > 0 {
            if !summary.isEmpty { summary += ", " }
            summary += "\(warningCount) warning\(warningCount == 1 ? "" : "s")"
        }
        
        return summary
    }
    
    func speakActiveAlerts() {
        let summary = getActiveAlertsSummary()
        speechOutput?.speak(summary)
    }
}

// MARK: - Data Models

struct HealthAlert: Identifiable {
    let id: UUID
    let type: AlertType
    let severity: AlertSeverity
    let message: String
    let reading: HealthReading
    let timestamp: Date
    let metadata: [String: String]
    
    var acknowledged: Bool = false
    var acknowledgedTime: Date?
}

enum AlertType: String, CaseIterable {
    case severeHypoglycemia = "severe_hypoglycemia"
    case hypoglycemia = "hypoglycemia"
    case severeHyperglycemia = "severe_hyperglycemia"
    case hyperglycemia = "hyperglycemia"
    case rapidGlucoseChange = "rapid_glucose_change"
    case bradycardia = "bradycardia"
    case tachycardia = "tachycardia"
    case severeTachycardia = "severe_tachycardia"
    case hypertensiveCrisis = "hypertensive_crisis"
    case lowOxygenSaturation = "low_oxygen_saturation"
    case fever = "fever"
    case fallDetected = "fall_detected"
    case pattern = "pattern"
    case trend = "trend"
    case aiInsight = "ai_insight"
}

enum AlertSeverity: String, Comparable, CaseIterable {
    case info = "info"
    case warning = "warning"
    case critical = "critical"
    case emergency = "emergency"
    
    static func < (lhs: AlertSeverity, rhs: AlertSeverity) -> Bool {
        let order: [AlertSeverity] = [.info, .warning, .critical, .emergency]
        guard let lhsIndex = order.firstIndex(of: lhs),
              let rhsIndex = order.firstIndex(of: rhs) else {
            return false
        }
        return lhsIndex < rhsIndex
    }
}

struct AlertThresholds {
    let glucoseThresholds: GlucoseThresholds
    let heartRateRange: Range<Int>
    let bloodPressureThresholds: BloodPressureThresholds
    let oxygenSaturationThreshold: Double
    let temperatureThreshold: Double
    
    static let `default` = AlertThresholds(
        glucoseThresholds: GlucoseThresholds.standard,
        heartRateRange: 60..<100,
        bloodPressureThresholds: BloodPressureThresholds.normal,
        oxygenSaturationThreshold: 90.0,
        temperatureThreshold: 38.0
    )
    
    static func from(profile: HealthProfile) -> AlertThresholds {
        var thresholds = AlertThresholds.default
        
        // Use diabetic profile thresholds if available
        if let diabeticProfile = profile.diabeticProfile {
            thresholds = AlertThresholds(
                glucoseThresholds: diabeticProfile.glucoseThresholds,
                heartRateRange: thresholds.heartRateRange,
                bloodPressureThresholds: thresholds.bloodPressureThresholds,
                oxygenSaturationThreshold: thresholds.oxygenSaturationThreshold,
                temperatureThreshold: thresholds.temperatureThreshold
            )
        }
        
        // Use cardiovascular profile thresholds if available
        if let cardioProfile = profile.cardiovascularProfile {
            thresholds = AlertThresholds(
                glucoseThresholds: thresholds.glucoseThresholds,
                heartRateRange: cardioProfile.targetHeartRate,
                bloodPressureThresholds: BloodPressureThresholds.from(target: cardioProfile.targetBloodPressure),
                oxygenSaturationThreshold: thresholds.oxygenSaturationThreshold,
                temperatureThreshold: thresholds.temperatureThreshold
            )
        }
        
        return thresholds
    }
}

struct BloodPressureThresholds {
    let normalSystolic: Range<Double>
    let normalDiastolic: Range<Double>
    let hypertensionStage1Systolic: Double
    let hypertensionStage2Systolic: Double
    let hypertensiveCrisisSystolic: Double
    
    static let normal = BloodPressureThresholds(
        normalSystolic: 90.0..<120.0,
        normalDiastolic: 60.0..<80.0,
        hypertensionStage1Systolic: 130.0,
        hypertensionStage2Systolic: 140.0,
        hypertensiveCrisisSystolic: 180.0
    )
    
    static func from(target: BloodPressureTarget) -> BloodPressureThresholds {
        return BloodPressureThresholds(
            normalSystolic: Double(target.systolic - 10)..<Double(target.systolic + 10),
            normalDiastolic: Double(target.diastolic - 10)..<Double(target.diastolic + 10),
            hypertensionStage1Systolic: Double(target.systolic + 20),
            hypertensionStage2Systolic: Double(target.systolic + 30),
            hypertensiveCrisisSystolic: 180.0
        )
    }
}

struct AlertRule {
    let type: AlertType
    let condition: (HealthReading, [HealthReading], AlertThresholds) -> Bool
    let severity: AlertSeverity
    let message: String
    
    func appliesTo(_ reading: HealthReading) -> Bool {
        // Basic check - could be expanded with more sophisticated logic
        return true
    }
    
    func evaluate(_ reading: HealthReading, recentReadings: [HealthReading], thresholds: AlertThresholds) -> AlertEvaluation {
        if condition(reading, recentReadings, thresholds) {
            let alert = HealthAlert(
                id: UUID(),
                type: type,
                severity: severity,
                message: message,
                reading: reading,
                timestamp: Date(),
                metadata: [:]
            )
            return AlertEvaluation(triggered: true, alert: alert)
        } else {
            return AlertEvaluation(triggered: false, alert: nil)
        }
    }
    
    // Default rule sets
    static let defaultGlucoseRules: [AlertRule] = [
        AlertRule(
            type: .severeHypoglycemia,
            condition: { reading, _, thresholds in
                reading.type == .bloodGlucose && reading.value < thresholds.glucoseThresholds.veryLow
            },
            severity: .emergency,
            message: "Severe low blood sugar. Take glucose immediately!"
        )
    ]
    
    static let defaultHeartRateRules: [AlertRule] = [
        AlertRule(
            type: .tachycardia,
            condition: { reading, _, thresholds in
                reading.type == .heartRate && reading.value > Double(thresholds.heartRateRange.upperBound + 20)
            },
            severity: .warning,
            message: "Heart rate elevated. Consider rest."
        )
    ]
    
    static let defaultBloodPressureRules: [AlertRule] = [
        AlertRule(
            type: .hypertensiveCrisis,
            condition: { reading, _, thresholds in
                guard reading.type == .bloodPressure,
                      let systolic = reading.additionalValues?["systolic"] else {
                    return false
                }
                return systolic > thresholds.bloodPressureThresholds.hypertensiveCrisisSystolic
            },
            severity: .emergency,
            message: "Blood pressure critically high. Seek immediate medical attention."
        )
    ]
    
    // Special rule types
    static let patternRule = AlertRule(
        type: .pattern,
        condition: { _, _, _ in false },
        severity: .warning,
        message: "Health pattern detected"
    )
    
    static let trendRule = AlertRule(
        type: .trend,
        condition: { _, _, _ in false },
        severity: .warning,
        message: "Health trend detected"
    )
    
    static let aiRule = AlertRule(
        type: .aiInsight,
        condition: { _, _, _ in false },
        severity: .warning,
        message: "AI health insight"
    )
    
    static let compoundRule = AlertRule(
        type: .aiInsight,
        condition: { _, _, _ in false },
        severity: .critical,
        message: "Multiple health concerns detected"
    )
}

struct AlertEvaluation {
    let triggered: Bool
    let alert: HealthAlert?
}

struct AlertSuppressionRule {
    let name: String
    let shouldSuppress: (HealthAlert, [HealthAlert]) -> Bool
    
    static let duplicateAlertSuppression = AlertSuppressionRule(
        name: "Duplicate Alert Suppression",
        shouldSuppress: { newAlert, recentAlerts in
            // Suppress if same type of alert was triggered in last 10 minutes
            return recentAlerts.contains { alert in
                alert.type == newAlert.type &&
                newAlert.timestamp.timeIntervalSince(alert.timestamp) < 600
            }
        }
    )
    
    static let nightTimeSuppression = AlertSuppressionRule(
        name: "Night Time Suppression",
        shouldSuppress: { alert, _ in
            // Suppress non-critical alerts between 10 PM and 6 AM
            let hour = Calendar.current.component(.hour, from: Date())
            let isNightTime = hour >= 22 || hour < 6
            
            return isNightTime && alert.severity < .critical
        }
    )
    
    static let exerciseModeSuppression = AlertSuppressionRule(
        name: "Exercise Mode Suppression",
        shouldSuppress: { alert, _ in
            // Would integrate with fitness tracking to suppress certain alerts during exercise
            return false // Placeholder
        }
    )
}

// MARK: - Supporting Classes

struct DetectedPattern {
    let type: PatternType
    let description: String
    let severity: AlertSeverity
    let confidence: Double
    let isConcerning: Bool
}

struct HealthTrend {
    let type: ReadingType
    let direction: TrendDirection
    let severity: AlertSeverity
    let description: String
    let duration: TimeInterval
    let isConcerning: Bool
}

enum TrendDirection: String {
    case increasing = "increasing"
    case decreasing = "decreasing"
    case stable = "stable"
    case volatile = "volatile"
}

struct AIHealthInsight {
    let description: String
    let severity: AlertSeverity
    let confidence: Double
    let recommendation: String
}

class AlertPatternAnalyzer {
    func analyze(_ reading: HealthReading, recentReadings: [HealthReading]) -> PatternAnalysisResult {
        var detectedPatterns: [DetectedPattern] = []
        
        // Dawn phenomenon detection for glucose
        if reading.type == .bloodGlucose {
            if let dawnPattern = detectDawnPhenomenon(reading, recentReadings: recentReadings) {
                detectedPatterns.append(dawnPattern)
            }
        }
        
        // Postprandial glucose pattern
        if reading.type == .bloodGlucose {
            if let postPrandialPattern = detectPostPrandialPattern(reading, recentReadings: recentReadings) {
                detectedPatterns.append(postPrandialPattern)
            }
        }
        
        return PatternAnalysisResult(
            detectedPatterns: detectedPatterns,
            trends: analyzeTrends(reading, recentReadings: recentReadings)
        )
    }
    
    func detectTrend(_ readingType: ReadingType) -> HealthTrend? {
        // Implement trend detection logic
        return nil
    }
    
    private func detectDawnPhenomenon(_ reading: HealthReading, recentReadings: [HealthReading]) -> DetectedPattern? {
        // Check if glucose is rising in early morning hours
        let hour = Calendar.current.component(.hour, from: reading.timestamp)
        let isDawnTime = hour >= 4 && hour <= 8
        
        guard isDawnTime else { return nil }
        
        // Look for glucose readings in the past 2 hours
        let twoHoursAgo = reading.timestamp.addingTimeInterval(-7200)
        let recentGlucoseReadings = recentReadings.filter {
            $0.type == .bloodGlucose && $0.timestamp > twoHoursAgo
        }.sorted { $0.timestamp < $1.timestamp }
        
        guard recentGlucoseReadings.count >= 2 else { return nil }
        
        // Check for rising trend
        let firstReading = recentGlucoseReadings.first!
        let lastReading = recentGlucoseReadings.last!
        let change = lastReading.value - firstReading.value
        
        if change > 30 { // More than 30 mg/dL increase
            return DetectedPattern(
                type: .glucoseSpike,
                description: "Dawn phenomenon detected - morning glucose rise",
                severity: .info,
                confidence: 0.8,
                isConcerning: false
            )
        }
        
        return nil
    }
    
    private func detectPostPrandialPattern(_ reading: HealthReading, recentReadings: [HealthReading]) -> DetectedPattern? {
        // Implement post-meal glucose pattern detection
        return nil
    }
    
    private func analyzeTrends(_ reading: HealthReading, recentReadings: [HealthReading]) -> [HealthTrend] {
        // Implement trend analysis
        return []
    }
}

struct PatternAnalysisResult {
    let detectedPatterns: [DetectedPattern]
    let trends: [HealthTrend]
}

class AIHealthAnalyzer {
    func analyzeReading(_ reading: HealthReading, context: [HealthReading], completion: @escaping (AIAnalysisResult) -> Void) {
        // Simulate AI analysis - in production this would call GPT-4 or similar
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
            let insights = self.generateInsights(reading, context: context)
            let result = AIAnalysisResult(insights: insights)
            completion(result)
        }
    }
    
    private func generateInsights(_ reading: HealthReading, context: [HealthReading]) -> [AIHealthInsight] {
        var insights: [AIHealthInsight] = []
        
        // Example: Glucose variability analysis
        if reading.type == .bloodGlucose {
            let glucoseReadings = context.filter { $0.type == .bloodGlucose }
            if glucoseReadings.count >= 5 {
                let values = glucoseReadings.map { $0.value }
                let standardDeviation = calculateStandardDeviation(values)
                
                if standardDeviation > 50 { // High variability
                    insights.append(AIHealthInsight(
                        description: "High glucose variability detected. Consider reviewing meal timing and medication.",
                        severity: .warning,
                        confidence: 0.85,
                        recommendation: "Track meal times and discuss with healthcare provider"
                    ))
                }
            }
        }
        
        return insights
    }
    
    private func calculateStandardDeviation(_ values: [Double]) -> Double {
        let mean = values.reduce(0, +) / Double(values.count)
        let squaredDifferences = values.map { pow($0 - mean, 2) }
        let variance = squaredDifferences.reduce(0, +) / Double(values.count)
        return sqrt(variance)
    }
}

struct AIAnalysisResult {
    let insights: [AIHealthInsight]
}

class ContextualAlertEngine {
    func enhanceAlert(_ alert: HealthAlert, context: [HealthReading]) -> HealthAlert {
        // Add contextual information to alerts
        var enhancedAlert = alert
        
        // Add time-based context
        let hour = Calendar.current.component(.hour, from: alert.timestamp)
        if hour >= 22 || hour < 6 {
            enhancedAlert.metadata["time_context"] = "nighttime"
        } else if hour >= 6 && hour < 12 {
            enhancedAlert.metadata["time_context"] = "morning"
        } else if hour >= 12 && hour < 18 {
            enhancedAlert.metadata["time_context"] = "afternoon"
        } else {
            enhancedAlert.metadata["time_context"] = "evening"
        }
        
        return enhancedAlert
    }
}

class CompoundAlertAnalyzer {
    func analyze(recentReadings: [HealthReading], thresholds: AlertThresholds) -> [HealthAlert] {
        var compoundAlerts: [HealthAlert] = []
        
        // Check for multiple concerning readings within a time window
        let recentWindow = Date().addingTimeInterval(-1800) // Last 30 minutes
        let recentConcerning = recentReadings.filter {
            $0.timestamp > recentWindow && $0.isCritical
        }
        
        if recentConcerning.count >= 2 {
            let alert = HealthAlert(
                id: UUID(),
                type: .aiInsight,
                severity: .critical,
                message: "Multiple health concerns detected in the last 30 minutes. Consider medical evaluation.",
                reading: recentConcerning.last!,
                timestamp: Date(),
                metadata: [
                    "concerning_readings": String(recentConcerning.count),
                    "compound_alert": "true"
                ]
            )
            compoundAlerts.append(alert)
        }
        
        return compoundAlerts
    }
}

// MARK: - Delegate Protocol

protocol HealthAlertEngineDelegate: AnyObject {
    func alertEngine(_ engine: HealthAlertEngine, didTriggerAlert alert: HealthAlert)
} 