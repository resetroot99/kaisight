import Foundation
import Vision
import CoreML
import UIKit
import Combine
import Photos

class EnhancedFamiliarRecognition: ObservableObject {
    @Published var recognizedFaces: [RecognizedFace] = []
    @Published var recognizedObjects: [RecognizedCustomObject] = []
    @Published var isTraining = false
    @Published var trainingProgress: Double = 0.0
    @Published var learningStats = LearningStatistics()
    
    // ML Models
    private var faceRecognitionModel: VNCoreMLModel?
    private var objectRecognitionModel: VNCoreMLModel?
    private var customFaceClassifier: MLModel?
    private var customObjectClassifier: MLModel?
    
    // Recognition data
    private var knownFaces: [FaceIdentity] = []
    private var customObjects: [CustomObjectIdentity] = []
    private var recognitionHistory: [RecognitionEvent] = []
    
    // Learning and training
    private let faceModelTrainer = FaceModelTrainer()
    private let objectModelTrainer = ObjectModelTrainer()
    private let featureExtractor = FeatureExtractor()
    
    // Storage and persistence
    private let dataManager = RecognitionDataManager()
    private let cloudSync = CloudSyncManager()
    
    // Audio feedback
    private let speechOutput = SpeechOutput()
    
    // Processing queue
    private let recognitionQueue = DispatchQueue(label: "recognition.queue", qos: .userInitiated)
    private let trainingQueue = DispatchQueue(label: "training.queue", qos: .background)
    
    init() {
        setupFamiliarRecognition()
    }
    
    // MARK: - Setup
    
    private func setupFamiliarRecognition() {
        loadRecognitionModels()
        loadStoredIdentities()
        setupTrainingComponents()
        
        Config.debugLog("Enhanced familiar recognition initialized")
    }
    
    private func loadRecognitionModels() {
        // Load pre-trained face recognition model
        loadFaceRecognitionModel()
        
        // Load or create custom object recognition model
        loadObjectRecognitionModel()
        
        // Load any previously trained custom models
        loadCustomModels()
    }
    
    private func loadFaceRecognitionModel() {
        guard let modelURL = Bundle.main.url(forResource: "FaceRecognition", withExtension: "mlmodelc"),
              let model = try? MLModel(contentsOf: modelURL),
              let visionModel = try? VNCoreMLModel(for: model) else {
            Config.debugLog("Failed to load face recognition model")
            return
        }
        
        faceRecognitionModel = visionModel
        Config.debugLog("Face recognition model loaded")
    }
    
    private func loadObjectRecognitionModel() {
        guard let modelURL = Bundle.main.url(forResource: "ObjectRecognition", withExtension: "mlmodelc"),
              let model = try? MLModel(contentsOf: modelURL),
              let visionModel = try? VNCoreMLModel(for: model) else {
            Config.debugLog("Failed to load object recognition model")
            return
        }
        
        objectRecognitionModel = visionModel
        Config.debugLog("Object recognition model loaded")
    }
    
    private func loadCustomModels() {
        // Load any custom trained models from storage
        dataManager.loadCustomModels { [weak self] faceModel, objectModel in
            self?.customFaceClassifier = faceModel
            self?.customObjectClassifier = objectModel
        }
    }
    
    private func loadStoredIdentities() {
        dataManager.loadFaceIdentities { [weak self] faces in
            DispatchQueue.main.async {
                self?.knownFaces = faces
                self?.updateLearningStats()
            }
        }
        
        dataManager.loadObjectIdentities { [weak self] objects in
            DispatchQueue.main.async {
                self?.customObjects = objects
                self?.updateLearningStats()
            }
        }
    }
    
    private func setupTrainingComponents() {
        faceModelTrainer.delegate = self
        objectModelTrainer.delegate = self
    }
    
    // MARK: - Face Recognition
    
    func recognizeFaces(in image: UIImage, completion: @escaping ([RecognizedFace]) -> Void) {
        recognitionQueue.async { [weak self] in
            guard let self = self else {
                completion([])
                return
            }
            
            let request = VNDetectFaceRectanglesRequest { request, error in
                guard let observations = request.results as? [VNFaceObservation] else {
                    completion([])
                    return
                }
                
                self.processFaceObservations(observations, in: image, completion: completion)
            }
            
            let handler = VNImageRequestHandler(cgImage: image.cgImage!, options: [:])
            try? handler.perform([request])
        }
    }
    
    private func processFaceObservations(_ observations: [VNFaceObservation], 
                                       in image: UIImage, 
                                       completion: @escaping ([RecognizedFace]) -> Void) {
        var recognizedFaces: [RecognizedFace] = []
        let group = DispatchGroup()
        
        for observation in observations {
            group.enter()
            
            // Extract face region
            let faceImage = extractFaceImage(from: image, observation: observation)
            
            // Get face features
            extractFaceFeatures(from: faceImage) { [weak self] features in
                defer { group.leave() }
                
                guard let features = features else { return }
                
                // Match against known faces
                if let identity = self?.matchFaceFeatures(features) {
                    let recognizedFace = RecognizedFace(
                        identity: identity,
                        boundingBox: observation.boundingBox,
                        confidence: identity.confidence,
                        timestamp: Date()
                    )
                    recognizedFaces.append(recognizedFace)
                    
                    // Update recognition history
                    self?.recordRecognitionEvent(.face, identity: identity.name, confidence: identity.confidence)
                }
            }
        }
        
        group.notify(queue: .main) {
            self.recognizedFaces = recognizedFaces
            completion(recognizedFaces)
            
            // Announce recognized faces
            self.announceFaceRecognition(recognizedFaces)
        }
    }
    
    private func extractFaceImage(from image: UIImage, observation: VNFaceObservation) -> UIImage {
        let rect = VNImageRectForNormalizedRect(observation.boundingBox, 
                                              Int(image.size.width), 
                                              Int(image.size.height))
        
        guard let cgImage = image.cgImage?.cropping(to: rect) else {
            return image
        }
        
        return UIImage(cgImage: cgImage)
    }
    
    private func extractFaceFeatures(from image: UIImage, completion: @escaping ([Float]?) -> Void) {
        guard let model = faceRecognitionModel else {
            completion(nil)
            return
        }
        
        let request = VNCoreMLRequest(model: model) { request, error in
            guard let results = request.results as? [VNCoreMLFeatureValueObservation],
                  let features = results.first?.featureValue.multiArrayValue else {
                completion(nil)
                return
            }
            
            // Convert MLMultiArray to Float array
            let featureArray = self.featureExtractor.convertToFloatArray(features)
            completion(featureArray)
        }
        
        let handler = VNImageRequestHandler(cgImage: image.cgImage!, options: [:])
        try? handler.perform([request])
    }
    
    private func matchFaceFeatures(_ features: [Float]) -> FaceIdentity? {
        var bestMatch: FaceIdentity?
        var bestSimilarity: Float = 0.0
        let threshold: Float = 0.8
        
        for identity in knownFaces {
            let similarity = calculateCosineSimilarity(features, identity.features)
            
            if similarity > threshold && similarity > bestSimilarity {
                bestSimilarity = similarity
                bestMatch = FaceIdentity(
                    id: identity.id,
                    name: identity.name,
                    features: identity.features,
                    confidence: similarity,
                    lastSeen: Date(),
                    timesRecognized: identity.timesRecognized + 1
                )
            }
        }
        
        return bestMatch
    }
    
    // MARK: - Object Recognition
    
    func recognizeCustomObjects(in image: UIImage, completion: @escaping ([RecognizedCustomObject]) -> Void) {
        recognitionQueue.async { [weak self] in
            guard let self = self else {
                completion([])
                return
            }
            
            // First detect general objects
            self.detectGeneralObjects(in: image) { detectedObjects in
                var recognizedObjects: [RecognizedCustomObject] = []
                let group = DispatchGroup()
                
                for object in detectedObjects {
                    group.enter()
                    
                    // Extract object region and get features
                    let objectImage = self.extractObjectImage(from: image, boundingBox: object.boundingBox)
                    
                    self.extractObjectFeatures(from: objectImage) { features in
                        defer { group.leave() }
                        
                        guard let features = features else { return }
                        
                        // Match against custom objects
                        if let identity = self.matchObjectFeatures(features) {
                            let recognizedObject = RecognizedCustomObject(
                                identity: identity,
                                boundingBox: object.boundingBox,
                                confidence: identity.confidence,
                                timestamp: Date()
                            )
                            recognizedObjects.append(recognizedObject)
                            
                            // Update recognition history
                            self.recordRecognitionEvent(.object, identity: identity.name, confidence: identity.confidence)
                        }
                    }
                }
                
                group.notify(queue: .main) {
                    self.recognizedObjects = recognizedObjects
                    completion(recognizedObjects)
                    
                    // Announce recognized objects
                    self.announceObjectRecognition(recognizedObjects)
                }
            }
        }
    }
    
    private func detectGeneralObjects(in image: UIImage, completion: @escaping ([DetectedObject]) -> Void) {
        guard let model = objectRecognitionModel else {
            completion([])
            return
        }
        
        let request = VNCoreMLRequest(model: model) { request, error in
            guard let results = request.results as? [VNRecognizedObjectObservation] else {
                completion([])
                return
            }
            
            let detectedObjects = results.map { observation in
                DetectedObject(
                    label: observation.labels.first?.identifier ?? "unknown",
                    confidence: observation.labels.first?.confidence ?? 0.0,
                    boundingBox: observation.boundingBox
                )
            }
            
            completion(detectedObjects)
        }
        
        let handler = VNImageRequestHandler(cgImage: image.cgImage!, options: [:])
        try? handler.perform([request])
    }
    
    private func extractObjectImage(from image: UIImage, boundingBox: CGRect) -> UIImage {
        let rect = VNImageRectForNormalizedRect(boundingBox, 
                                              Int(image.size.width), 
                                              Int(image.size.height))
        
        guard let cgImage = image.cgImage?.cropping(to: rect) else {
            return image
        }
        
        return UIImage(cgImage: cgImage)
    }
    
    private func extractObjectFeatures(from image: UIImage, completion: @escaping ([Float]?) -> Void) {
        // Use Vision framework to extract features
        featureExtractor.extractFeatures(from: image, completion: completion)
    }
    
    private func matchObjectFeatures(_ features: [Float]) -> CustomObjectIdentity? {
        var bestMatch: CustomObjectIdentity?
        var bestSimilarity: Float = 0.0
        let threshold: Float = 0.75
        
        for identity in customObjects {
            let similarity = calculateCosineSimilarity(features, identity.features)
            
            if similarity > threshold && similarity > bestSimilarity {
                bestSimilarity = similarity
                bestMatch = CustomObjectIdentity(
                    id: identity.id,
                    name: identity.name,
                    category: identity.category,
                    features: identity.features,
                    confidence: similarity,
                    lastSeen: Date(),
                    timesRecognized: identity.timesRecognized + 1
                )
            }
        }
        
        return bestMatch
    }
    
    // MARK: - Training New Faces
    
    func trainNewFace(name: String, images: [UIImage], completion: @escaping (Bool) -> Void) {
        guard images.count >= 3 else {
            speechOutput.speak("Please provide at least 3 images for training")
            completion(false)
            return
        }
        
        isTraining = true
        trainingProgress = 0.0
        
        trainingQueue.async { [weak self] in
            guard let self = self else {
                completion(false)
                return
            }
            
            self.speechOutput.speak("Starting face training for \(name)")
            
            // Extract features from all training images
            var allFeatures: [[Float]] = []
            
            for (index, image) in images.enumerated() {
                self.extractFaceFeatures(from: image) { features in
                    if let features = features {
                        allFeatures.append(features)
                    }
                    
                    DispatchQueue.main.async {
                        self.trainingProgress = Double(index + 1) / Double(images.count) * 0.7
                    }
                }
            }
            
            // Average the features to create a representative embedding
            guard !allFeatures.isEmpty else {
                DispatchQueue.main.async {
                    self.isTraining = false
                    self.speechOutput.speak("Failed to extract features from images")
                    completion(false)
                }
                return
            }
            
            let averagedFeatures = self.averageFeatures(allFeatures)
            
            // Create new face identity
            let faceIdentity = FaceIdentity(
                id: UUID(),
                name: name,
                features: averagedFeatures,
                confidence: 1.0,
                lastSeen: Date(),
                timesRecognized: 0
            )
            
            // Save to storage
            self.dataManager.saveFaceIdentity(faceIdentity) { success in
                DispatchQueue.main.async {
                    if success {
                        self.knownFaces.append(faceIdentity)
                        self.updateLearningStats()
                        self.speechOutput.speak("Successfully trained face recognition for \(name)")
                    } else {
                        self.speechOutput.speak("Failed to save face training data")
                    }
                    
                    self.isTraining = false
                    self.trainingProgress = 0.0
                    completion(success)
                }
            }
            
            // Optionally retrain the model with new data
            if self.knownFaces.count >= 5 {
                self.retrainFaceModel()
            }
        }
    }
    
    // MARK: - Training Custom Objects
    
    func trainCustomObject(name: String, category: String, images: [UIImage], completion: @escaping (Bool) -> Void) {
        guard images.count >= 5 else {
            speechOutput.speak("Please provide at least 5 images for object training")
            completion(false)
            return
        }
        
        isTraining = true
        trainingProgress = 0.0
        
        trainingQueue.async { [weak self] in
            guard let self = self else {
                completion(false)
                return
            }
            
            self.speechOutput.speak("Starting object training for \(name)")
            
            // Extract features from all training images
            var allFeatures: [[Float]] = []
            
            for (index, image) in images.enumerated() {
                self.extractObjectFeatures(from: image) { features in
                    if let features = features {
                        allFeatures.append(features)
                    }
                    
                    DispatchQueue.main.async {
                        self.trainingProgress = Double(index + 1) / Double(images.count) * 0.8
                    }
                }
            }
            
            guard !allFeatures.isEmpty else {
                DispatchQueue.main.async {
                    self.isTraining = false
                    self.speechOutput.speak("Failed to extract features from object images")
                    completion(false)
                }
                return
            }
            
            let averagedFeatures = self.averageFeatures(allFeatures)
            
            // Create new object identity
            let objectIdentity = CustomObjectIdentity(
                id: UUID(),
                name: name,
                category: category,
                features: averagedFeatures,
                confidence: 1.0,
                lastSeen: Date(),
                timesRecognized: 0
            )
            
            // Save to storage
            self.dataManager.saveObjectIdentity(objectIdentity) { success in
                DispatchQueue.main.async {
                    if success {
                        self.customObjects.append(objectIdentity)
                        self.updateLearningStats()
                        self.speechOutput.speak("Successfully trained object recognition for \(name)")
                    } else {
                        self.speechOutput.speak("Failed to save object training data")
                    }
                    
                    self.isTraining = false
                    self.trainingProgress = 0.0
                    completion(success)
                }
            }
        }
    }
    
    // MARK: - Model Retraining
    
    private func retrainFaceModel() {
        guard knownFaces.count >= 5 else { return }
        
        faceModelTrainer.retrain(with: knownFaces) { [weak self] newModel in
            if let newModel = newModel {
                self?.customFaceClassifier = newModel
                self?.dataManager.saveCustomFaceModel(newModel)
                self?.speechOutput.speak("Face recognition model updated with new learning")
            }
        }
    }
    
    private func retrainObjectModel() {
        guard customObjects.count >= 5 else { return }
        
        objectModelTrainer.retrain(with: customObjects) { [weak self] newModel in
            if let newModel = newModel {
                self?.customObjectClassifier = newModel
                self?.dataManager.saveCustomObjectModel(newModel)
                self?.speechOutput.speak("Object recognition model updated with new learning")
            }
        }
    }
    
    // MARK: - Learning Analytics
    
    private func updateLearningStats() {
        learningStats = LearningStatistics(
            totalFacesTrained: knownFaces.count,
            totalObjectsTrained: customObjects.count,
            totalRecognitions: recognitionHistory.count,
            accuracyRate: calculateAccuracyRate(),
            lastTrainingDate: getLastTrainingDate()
        )
    }
    
    private func calculateAccuracyRate() -> Double {
        guard !recognitionHistory.isEmpty else { return 0.0 }
        
        let successfulRecognitions = recognitionHistory.filter { $0.confidence > 0.8 }.count
        return Double(successfulRecognitions) / Double(recognitionHistory.count)
    }
    
    private func getLastTrainingDate() -> Date? {
        let allDates = knownFaces.map { $0.lastSeen } + customObjects.map { $0.lastSeen }
        return allDates.max()
    }
    
    // MARK: - Feedback and Improvement
    
    func provideFeedback(for recognitionID: UUID, isCorrect: Bool) {
        if let index = recognitionHistory.firstIndex(where: { $0.id == recognitionID }) {
            recognitionHistory[index].userFeedback = isCorrect
            
            // Use feedback to improve model
            if !isCorrect {
                adjustModelConfidence(for: recognitionHistory[index])
            }
            
            updateLearningStats()
        }
    }
    
    private func adjustModelConfidence(for event: RecognitionEvent) {
        // Reduce confidence for incorrect recognitions
        switch event.type {
        case .face:
            if let index = knownFaces.firstIndex(where: { $0.name == event.identityName }) {
                // Could implement negative feedback learning here
            }
        case .object:
            if let index = customObjects.firstIndex(where: { $0.name == event.identityName }) {
                // Could implement negative feedback learning here
            }
        }
    }
    
    // MARK: - Utility Methods
    
    private func calculateCosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
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
    
    private func averageFeatures(_ featureArrays: [[Float]]) -> [Float] {
        guard !featureArrays.isEmpty else { return [] }
        
        let featureCount = featureArrays[0].count
        var averagedFeatures = Array(repeating: Float(0.0), count: featureCount)
        
        for features in featureArrays {
            for i in 0..<featureCount {
                averagedFeatures[i] += features[i]
            }
        }
        
        for i in 0..<featureCount {
            averagedFeatures[i] /= Float(featureArrays.count)
        }
        
        return averagedFeatures
    }
    
    private func recordRecognitionEvent(_ type: RecognitionType, identity: String, confidence: Float) {
        let event = RecognitionEvent(
            id: UUID(),
            type: type,
            identityName: identity,
            confidence: confidence,
            timestamp: Date(),
            userFeedback: nil
        )
        
        recognitionHistory.append(event)
        
        // Keep only recent history
        if recognitionHistory.count > 1000 {
            recognitionHistory.removeFirst(recognitionHistory.count - 1000)
        }
    }
    
    // MARK: - Audio Announcements
    
    private func announceFaceRecognition(_ faces: [RecognizedFace]) {
        for face in faces {
            speechOutput.speak("I see \(face.identity.name)", priority: .medium)
        }
    }
    
    private func announceObjectRecognition(_ objects: [RecognizedCustomObject]) {
        for object in objects {
            speechOutput.speak("I found your \(object.identity.name)", priority: .medium)
        }
    }
    
    // MARK: - Public Interface
    
    func removeFaceIdentity(id: UUID) {
        knownFaces.removeAll { $0.id == id }
        dataManager.deleteFaceIdentity(id: id)
        updateLearningStats()
    }
    
    func removeObjectIdentity(id: UUID) {
        customObjects.removeAll { $0.id == id }
        dataManager.deleteObjectIdentity(id: id)
        updateLearningStats()
    }
    
    func getRecognitionSummary() -> String {
        var summary = "Recognition status: "
        summary += "\(knownFaces.count) faces trained, "
        summary += "\(customObjects.count) objects trained. "
        summary += "Accuracy: \(Int(learningStats.accuracyRate * 100))%"
        
        return summary
    }
    
    func speakRecognitionSummary() {
        let summary = getRecognitionSummary()
        speechOutput.speak(summary)
    }
}

// MARK: - Training Delegates

extension EnhancedFamiliarRecognition: FaceModelTrainerDelegate {
    func faceTrainer(_ trainer: FaceModelTrainer, didUpdateProgress progress: Double) {
        DispatchQueue.main.async {
            self.trainingProgress = 0.7 + (progress * 0.3)
        }
    }
    
    func faceTrainer(_ trainer: FaceModelTrainer, didCompleteTraining model: MLModel?) {
        if let model = model {
            customFaceClassifier = model
            speechOutput.speak("Face recognition model updated")
        }
    }
}

extension EnhancedFamiliarRecognition: ObjectModelTrainerDelegate {
    func objectTrainer(_ trainer: ObjectModelTrainer, didUpdateProgress progress: Double) {
        DispatchQueue.main.async {
            self.trainingProgress = 0.8 + (progress * 0.2)
        }
    }
    
    func objectTrainer(_ trainer: ObjectModelTrainer, didCompleteTraining model: MLModel?) {
        if let model = model {
            customObjectClassifier = model
            speechOutput.speak("Object recognition model updated")
        }
    }
}

// MARK: - Data Models

struct FaceIdentity: Identifiable, Codable {
    let id: UUID
    let name: String
    let features: [Float]
    let confidence: Float
    let lastSeen: Date
    let timesRecognized: Int
}

struct CustomObjectIdentity: Identifiable, Codable {
    let id: UUID
    let name: String
    let category: String
    let features: [Float]
    let confidence: Float
    let lastSeen: Date
    let timesRecognized: Int
}

struct RecognizedFace: Identifiable {
    let id = UUID()
    let identity: FaceIdentity
    let boundingBox: CGRect
    let confidence: Float
    let timestamp: Date
}

struct RecognizedCustomObject: Identifiable {
    let id = UUID()
    let identity: CustomObjectIdentity
    let boundingBox: CGRect
    let confidence: Float
    let timestamp: Date
}

struct DetectedObject {
    let label: String
    let confidence: Float
    let boundingBox: CGRect
}

struct RecognitionEvent: Identifiable {
    let id: UUID
    let type: RecognitionType
    let identityName: String
    let confidence: Float
    let timestamp: Date
    var userFeedback: Bool?
}

enum RecognitionType: String, Codable {
    case face = "face"
    case object = "object"
}

struct LearningStatistics {
    let totalFacesTrained: Int
    let totalObjectsTrained: Int
    let totalRecognitions: Int
    let accuracyRate: Double
    let lastTrainingDate: Date?
    
    init(totalFacesTrained: Int = 0, totalObjectsTrained: Int = 0, totalRecognitions: Int = 0, accuracyRate: Double = 0.0, lastTrainingDate: Date? = nil) {
        self.totalFacesTrained = totalFacesTrained
        self.totalObjectsTrained = totalObjectsTrained
        self.totalRecognitions = totalRecognitions
        self.accuracyRate = accuracyRate
        self.lastTrainingDate = lastTrainingDate
    }
}

// MARK: - Supporting Classes

class FaceModelTrainer {
    weak var delegate: FaceModelTrainerDelegate?
    
    func retrain(with faces: [FaceIdentity], completion: @escaping (MLModel?) -> Void) {
        // Implementation for retraining face model
        // This would use CreateML or similar framework
        completion(nil) // Placeholder
    }
}

protocol FaceModelTrainerDelegate: AnyObject {
    func faceTrainer(_ trainer: FaceModelTrainer, didUpdateProgress progress: Double)
    func faceTrainer(_ trainer: FaceModelTrainer, didCompleteTraining model: MLModel?)
}

class ObjectModelTrainer {
    weak var delegate: ObjectModelTrainerDelegate?
    
    func retrain(with objects: [CustomObjectIdentity], completion: @escaping (MLModel?) -> Void) {
        // Implementation for retraining object model
        completion(nil) // Placeholder
    }
}

protocol ObjectModelTrainerDelegate: AnyObject {
    func objectTrainer(_ trainer: ObjectModelTrainer, didUpdateProgress progress: Double)
    func objectTrainer(_ trainer: ObjectModelTrainer, didCompleteTraining model: MLModel?)
}

class FeatureExtractor {
    func extractFeatures(from image: UIImage, completion: @escaping ([Float]?) -> Void) {
        // Extract features using Vision framework
        let request = VNGenerateImageFeaturePrintRequest { request, error in
            guard let observations = request.results as? [VNFeaturePrintObservation],
                  let featurePrint = observations.first else {
                completion(nil)
                return
            }
            
            // Convert feature print to float array
            var features: [Float] = []
            let data = featurePrint.data
            let count = data.count / MemoryLayout<Float>.size
            
            data.withUnsafeBytes { bytes in
                let floatBuffer = bytes.bindMemory(to: Float.self)
                features = Array(floatBuffer.prefix(count))
            }
            
            completion(features)
        }
        
        let handler = VNImageRequestHandler(cgImage: image.cgImage!, options: [:])
        try? handler.perform([request])
    }
    
    func convertToFloatArray(_ multiArray: MLMultiArray) -> [Float] {
        var features: [Float] = []
        
        for i in 0..<multiArray.count {
            features.append(Float(truncating: multiArray[i]))
        }
        
        return features
    }
}

class RecognitionDataManager {
    private let userDefaults = UserDefaults.standard
    private let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    
    func saveFaceIdentity(_ identity: FaceIdentity, completion: @escaping (Bool) -> Void) {
        do {
            let data = try JSONEncoder().encode(identity)
            let url = documentsDirectory.appendingPathComponent("face_\(identity.id.uuidString).json")
            try data.write(to: url)
            completion(true)
        } catch {
            Config.debugLog("Failed to save face identity: \(error)")
            completion(false)
        }
    }
    
    func saveObjectIdentity(_ identity: CustomObjectIdentity, completion: @escaping (Bool) -> Void) {
        do {
            let data = try JSONEncoder().encode(identity)
            let url = documentsDirectory.appendingPathComponent("object_\(identity.id.uuidString).json")
            try data.write(to: url)
            completion(true)
        } catch {
            Config.debugLog("Failed to save object identity: \(error)")
            completion(false)
        }
    }
    
    func loadFaceIdentities(completion: @escaping ([FaceIdentity]) -> Void) {
        var identities: [FaceIdentity] = []
        
        do {
            let urls = try FileManager.default.contentsOfDirectory(at: documentsDirectory, 
                                                                 includingPropertiesForKeys: nil)
            
            for url in urls where url.lastPathComponent.hasPrefix("face_") {
                let data = try Data(contentsOf: url)
                let identity = try JSONDecoder().decode(FaceIdentity.self, from: data)
                identities.append(identity)
            }
        } catch {
            Config.debugLog("Failed to load face identities: \(error)")
        }
        
        completion(identities)
    }
    
    func loadObjectIdentities(completion: @escaping ([CustomObjectIdentity]) -> Void) {
        var identities: [CustomObjectIdentity] = []
        
        do {
            let urls = try FileManager.default.contentsOfDirectory(at: documentsDirectory, 
                                                                 includingPropertiesForKeys: nil)
            
            for url in urls where url.lastPathComponent.hasPrefix("object_") {
                let data = try Data(contentsOf: url)
                let identity = try JSONDecoder().decode(CustomObjectIdentity.self, from: data)
                identities.append(identity)
            }
        } catch {
            Config.debugLog("Failed to load object identities: \(error)")
        }
        
        completion(identities)
    }
    
    func deleteFaceIdentity(id: UUID) {
        let url = documentsDirectory.appendingPathComponent("face_\(id.uuidString).json")
        try? FileManager.default.removeItem(at: url)
    }
    
    func deleteObjectIdentity(id: UUID) {
        let url = documentsDirectory.appendingPathComponent("object_\(id.uuidString).json")
        try? FileManager.default.removeItem(at: url)
    }
    
    func loadCustomModels(completion: @escaping (MLModel?, MLModel?) -> Void) {
        // Load custom trained models from storage
        completion(nil, nil) // Placeholder
    }
    
    func saveCustomFaceModel(_ model: MLModel) {
        // Save custom face model
    }
    
    func saveCustomObjectModel(_ model: MLModel) {
        // Save custom object model
    }
} 