import Foundation
import Vision
import CoreML
import UIKit
import Accelerate

class FamiliarRecognition: ObservableObject {
    @Published var knownFaces: [KnownPerson] = []
    @Published var knownObjects: [KnownObject] = []
    @Published var recognitionResults: [RecognitionResult] = []
    
    private let faceEmbeddingModel: VNCoreMLModel
    private let objectEmbeddingModel: VNCoreMLModel
    private let facesDatabase = PersonDatabase()
    private let objectsDatabase = ObjectDatabase()
    
    // Recognition settings
    private let faceConfidenceThreshold: Float = 0.7
    private let objectConfidenceThreshold: Float = 0.6
    private let similarityThreshold: Float = 0.8
    
    init() {
        // Initialize CoreML models for face and object embeddings
        // In production, use models like FaceNet or ResNet for embeddings
        guard let faceModel = try? VNCoreMLModel(for: createDummyFaceModel()),
              let objectModel = try? VNCoreMLModel(for: createDummyObjectModel()) else {
            fatalError("❌ Failed to load recognition models")
        }
        
        self.faceEmbeddingModel = faceModel
        self.objectEmbeddingModel = objectModel
        
        loadKnownEntities()
    }
    
    // MARK: - Person Recognition
    
    func addKnownPerson(name: String, relationship: String, image: UIImage, completion: @escaping (Bool) -> Void) {
        generateFaceEmbedding(from: image) { [weak self] embedding in
            guard let self = self, let embedding = embedding else {
                completion(false)
                return
            }
            
            let person = KnownPerson(
                id: UUID(),
                name: name,
                relationship: relationship,
                embedding: embedding,
                addedDate: Date(),
                recognitionCount: 0
            )
            
            self.knownFaces.append(person)
            self.facesDatabase.savePerson(person)
            
            Config.debugLog("Added known person: \(name) (\(relationship))")
            completion(true)
        }
    }
    
    func addKnownObject(name: String, category: String, description: String, image: UIImage, completion: @escaping (Bool) -> Void) {
        generateObjectEmbedding(from: image) { [weak self] embedding in
            guard let self = self, let embedding = embedding else {
                completion(false)
                return
            }
            
            let object = KnownObject(
                id: UUID(),
                name: name,
                category: category,
                description: description,
                embedding: embedding,
                addedDate: Date(),
                recognitionCount: 0
            )
            
            self.knownObjects.append(object)
            self.objectsDatabase.saveObject(object)
            
            Config.debugLog("Added known object: \(name) (\(category))")
            completion(true)
        }
    }
    
    func recognizeFamiliarEntities(in image: UIImage, completion: @escaping ([RecognitionResult]) -> Void) {
        var results: [RecognitionResult] = []
        let group = DispatchGroup()
        
        // Recognize faces
        group.enter()
        recognizeFaces(in: image) { faceResults in
            results.append(contentsOf: faceResults)
            group.leave()
        }
        
        // Recognize objects
        group.enter()
        recognizeObjects(in: image) { objectResults in
            results.append(contentsOf: objectResults)
            group.leave()
        }
        
        group.notify(queue: .main) {
            self.recognitionResults = results
            completion(results)
        }
    }
    
    private func recognizeFaces(in image: UIImage, completion: @escaping ([RecognitionResult]) -> Void) {
        guard let cgImage = image.cgImage else {
            completion([])
            return
        }
        
        let faceRequest = VNDetectFaceRectanglesRequest { [weak self] request, error in
            guard let self = self,
                  let observations = request.results as? [VNFaceObservation] else {
                completion([])
                return
            }
            
            var faceResults: [RecognitionResult] = []
            let group = DispatchGroup()
            
            for faceObservation in observations {
                group.enter()
                
                // Extract face region and generate embedding
                let faceImage = self.extractFaceRegion(from: image, observation: faceObservation)
                
                self.generateFaceEmbedding(from: faceImage) { embedding in
                    defer { group.leave() }
                    
                    guard let embedding = embedding else { return }
                    
                    // Find closest match in known faces
                    if let match = self.findClosestPerson(embedding: embedding) {
                        let result = RecognitionResult(
                            type: .person,
                            name: match.person.name,
                            confidence: match.similarity,
                            boundingBox: faceObservation.boundingBox,
                            details: "Relationship: \(match.person.relationship)",
                            entity: .person(match.person)
                        )
                        faceResults.append(result)
                        
                        // Update recognition count
                        self.updatePersonRecognitionCount(match.person.id)
                    }
                }
            }
            
            group.notify(queue: .main) {
                completion(faceResults)
            }
        }
        
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? handler.perform([faceRequest])
    }
    
    private func recognizeObjects(in image: UIImage, completion: @escaping ([RecognitionResult]) -> Void) {
        guard let cgImage = image.cgImage else {
            completion([])
            return
        }
        
        let objectRequest = VNRecognizeObjectsRequest { [weak self] request, error in
            guard let self = self,
                  let observations = request.results as? [VNRecognizedObjectObservation] else {
                completion([])
                return
            }
            
            var objectResults: [RecognitionResult] = []
            let group = DispatchGroup()
            
            for objectObservation in observations {
                group.enter()
                
                // Extract object region and generate embedding
                let objectImage = self.extractObjectRegion(from: image, observation: objectObservation)
                
                self.generateObjectEmbedding(from: objectImage) { embedding in
                    defer { group.leave() }
                    
                    guard let embedding = embedding else { return }
                    
                    // Find closest match in known objects
                    if let match = self.findClosestObject(embedding: embedding) {
                        let result = RecognitionResult(
                            type: .object,
                            name: match.object.name,
                            confidence: match.similarity,
                            boundingBox: objectObservation.boundingBox,
                            details: match.object.description,
                            entity: .object(match.object)
                        )
                        objectResults.append(result)
                        
                        // Update recognition count
                        self.updateObjectRecognitionCount(match.object.id)
                    }
                }
            }
            
            group.notify(queue: .main) {
                completion(objectResults)
            }
        }
        
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? handler.perform([objectRequest])
    }
    
    // MARK: - Embedding Generation
    
    private func generateFaceEmbedding(from image: UIImage, completion: @escaping ([Float]?) -> Void) {
        guard let cgImage = image.cgImage else {
            completion(nil)
            return
        }
        
        let request = VNCoreMLRequest(model: faceEmbeddingModel) { request, error in
            guard let results = request.results as? [VNCoreMLFeatureValueObservation],
                  let featureValue = results.first?.featureValue,
                  let multiArray = featureValue.multiArrayValue else {
                completion(nil)
                return
            }
            
            let embedding = self.multiArrayToFloatArray(multiArray)
            completion(embedding)
        }
        
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? handler.perform([request])
    }
    
    private func generateObjectEmbedding(from image: UIImage, completion: @escaping ([Float]?) -> Void) {
        guard let cgImage = image.cgImage else {
            completion(nil)
            return
        }
        
        let request = VNCoreMLRequest(model: objectEmbeddingModel) { request, error in
            guard let results = request.results as? [VNCoreMLFeatureValueObservation],
                  let featureValue = results.first?.featureValue,
                  let multiArray = featureValue.multiArrayValue else {
                completion(nil)
                return
            }
            
            let embedding = self.multiArrayToFloatArray(multiArray)
            completion(embedding)
        }
        
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? handler.perform([request])
    }
    
    // MARK: - Similarity Matching
    
    private func findClosestPerson(embedding: [Float]) -> (person: KnownPerson, similarity: Float)? {
        var bestMatch: (person: KnownPerson, similarity: Float)?
        var highestSimilarity: Float = 0
        
        for person in knownFaces {
            let similarity = cosineSimilarity(embedding, person.embedding)
            
            if similarity > highestSimilarity && similarity >= similarityThreshold {
                highestSimilarity = similarity
                bestMatch = (person: person, similarity: similarity)
            }
        }
        
        return bestMatch
    }
    
    private func findClosestObject(embedding: [Float]) -> (object: KnownObject, similarity: Float)? {
        var bestMatch: (object: KnownObject, similarity: Float)?
        var highestSimilarity: Float = 0
        
        for object in knownObjects {
            let similarity = cosineSimilarity(embedding, object.embedding)
            
            if similarity > highestSimilarity && similarity >= similarityThreshold {
                highestSimilarity = similarity
                bestMatch = (object: object, similarity: similarity)
            }
        }
        
        return bestMatch
    }
    
    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count else { return 0 }
        
        var dotProduct: Float = 0
        var normA: Float = 0
        var normB: Float = 0
        
        for i in 0..<a.count {
            dotProduct += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }
        
        let denominator = sqrt(normA) * sqrt(normB)
        return denominator == 0 ? 0 : dotProduct / denominator
    }
    
    // MARK: - Utility Methods
    
    private func extractFaceRegion(from image: UIImage, observation: VNFaceObservation) -> UIImage {
        let imageSize = image.size
        let boundingBox = observation.boundingBox
        
        // Convert Vision coordinates to UIImage coordinates
        let rect = CGRect(
            x: boundingBox.origin.x * imageSize.width,
            y: (1 - boundingBox.origin.y - boundingBox.height) * imageSize.height,
            width: boundingBox.width * imageSize.width,
            height: boundingBox.height * imageSize.height
        )
        
        guard let cgImage = image.cgImage?.cropping(to: rect) else {
            return image
        }
        
        return UIImage(cgImage: cgImage)
    }
    
    private func extractObjectRegion(from image: UIImage, observation: VNRecognizedObjectObservation) -> UIImage {
        let imageSize = image.size
        let boundingBox = observation.boundingBox
        
        let rect = CGRect(
            x: boundingBox.origin.x * imageSize.width,
            y: (1 - boundingBox.origin.y - boundingBox.height) * imageSize.height,
            width: boundingBox.width * imageSize.width,
            height: boundingBox.height * imageSize.height
        )
        
        guard let cgImage = image.cgImage?.cropping(to: rect) else {
            return image
        }
        
        return UIImage(cgImage: cgImage)
    }
    
    private func multiArrayToFloatArray(_ multiArray: MLMultiArray) -> [Float] {
        let count = multiArray.count
        let pointer = UnsafeMutablePointer<Float>.allocate(capacity: count)
        defer { pointer.deallocate() }
        
        multiArray.dataPointer.assumingMemoryBound(to: Float.self).assign(to: pointer, count: count)
        return Array(UnsafeBufferPointer(start: pointer, count: count))
    }
    
    private func updatePersonRecognitionCount(_ personId: UUID) {
        if let index = knownFaces.firstIndex(where: { $0.id == personId }) {
            knownFaces[index].recognitionCount += 1
            facesDatabase.updatePerson(knownFaces[index])
        }
    }
    
    private func updateObjectRecognitionCount(_ objectId: UUID) {
        if let index = knownObjects.firstIndex(where: { $0.id == objectId }) {
            knownObjects[index].recognitionCount += 1
            objectsDatabase.updateObject(knownObjects[index])
        }
    }
    
    private func loadKnownEntities() {
        knownFaces = facesDatabase.loadAllPersons()
        knownObjects = objectsDatabase.loadAllObjects()
        
        Config.debugLog("Loaded \(knownFaces.count) known faces and \(knownObjects.count) known objects")
    }
    
    // MARK: - Public Interface
    
    func generateFamiliarityReport() -> String {
        var report = "Familiar Recognition Summary:\n"
        
        if !knownFaces.isEmpty {
            report += "\nKnown People (\(knownFaces.count)):\n"
            for person in knownFaces.sorted(by: { $0.recognitionCount > $1.recognitionCount }) {
                report += "• \(person.name) (\(person.relationship)) - seen \(person.recognitionCount) times\n"
            }
        }
        
        if !knownObjects.isEmpty {
            report += "\nKnown Objects (\(knownObjects.count)):\n"
            for object in knownObjects.sorted(by: { $0.recognitionCount > $1.recognitionCount }) {
                report += "• \(object.name) (\(object.category)) - seen \(object.recognitionCount) times\n"
            }
        }
        
        return report
    }
    
    func removeKnownPerson(id: UUID) {
        knownFaces.removeAll { $0.id == id }
        facesDatabase.deletePerson(id: id)
    }
    
    func removeKnownObject(id: UUID) {
        knownObjects.removeAll { $0.id == id }
        objectsDatabase.deleteObject(id: id)
    }
    
    // MARK: - Dummy Model Creation (Replace with real models)
    
    private func createDummyFaceModel() -> MLModel {
        // In production, load a pre-trained face recognition model
        // For now, create a simple dummy model
        return try! MLModel(contentsOf: Bundle.main.url(forResource: "FaceEmbedding", withExtension: "mlmodelc")!)
    }
    
    private func createDummyObjectModel() -> MLModel {
        // In production, load a pre-trained object recognition model
        return try! MLModel(contentsOf: Bundle.main.url(forResource: "ObjectEmbedding", withExtension: "mlmodelc")!)
    }
}

// MARK: - Data Models

struct KnownPerson: Codable, Identifiable {
    let id: UUID
    let name: String
    let relationship: String
    let embedding: [Float]
    let addedDate: Date
    var recognitionCount: Int
}

struct KnownObject: Codable, Identifiable {
    let id: UUID
    let name: String
    let category: String
    let description: String
    let embedding: [Float]
    let addedDate: Date
    var recognitionCount: Int
}

struct RecognitionResult {
    let type: RecognitionType
    let name: String
    let confidence: Float
    let boundingBox: CGRect
    let details: String
    let entity: RecognizedEntity
}

enum RecognitionType {
    case person
    case object
}

enum RecognizedEntity {
    case person(KnownPerson)
    case object(KnownObject)
}

// MARK: - Database Classes

class PersonDatabase {
    private let userDefaults = UserDefaults.standard
    private let personsKey = "KnownPersons"
    
    func savePerson(_ person: KnownPerson) {
        var persons = loadAllPersons()
        if let index = persons.firstIndex(where: { $0.id == person.id }) {
            persons[index] = person
        } else {
            persons.append(person)
        }
        savePersons(persons)
    }
    
    func loadAllPersons() -> [KnownPerson] {
        guard let data = userDefaults.data(forKey: personsKey),
              let persons = try? JSONDecoder().decode([KnownPerson].self, from: data) else {
            return []
        }
        return persons
    }
    
    func updatePerson(_ person: KnownPerson) {
        savePerson(person)
    }
    
    func deletePerson(id: UUID) {
        var persons = loadAllPersons()
        persons.removeAll { $0.id == id }
        savePersons(persons)
    }
    
    private func savePersons(_ persons: [KnownPerson]) {
        if let data = try? JSONEncoder().encode(persons) {
            userDefaults.set(data, forKey: personsKey)
        }
    }
}

class ObjectDatabase {
    private let userDefaults = UserDefaults.standard
    private let objectsKey = "KnownObjects"
    
    func saveObject(_ object: KnownObject) {
        var objects = loadAllObjects()
        if let index = objects.firstIndex(where: { $0.id == object.id }) {
            objects[index] = object
        } else {
            objects.append(object)
        }
        saveObjects(objects)
    }
    
    func loadAllObjects() -> [KnownObject] {
        guard let data = userDefaults.data(forKey: objectsKey),
              let objects = try? JSONDecoder().decode([KnownObject].self, from: data) else {
            return []
        }
        return objects
    }
    
    func updateObject(_ object: KnownObject) {
        saveObject(object)
    }
    
    func deleteObject(id: UUID) {
        var objects = loadAllObjects()
        objects.removeAll { $0.id == id }
        saveObjects(objects)
    }
    
    private func saveObjects(_ objects: [KnownObject]) {
        if let data = try? JSONEncoder().encode(objects) {
            userDefaults.set(data, forKey: objectsKey)
        }
    }
} 