import Foundation
import Vision
import UIKit

class ObjectDetectionManager: ObservableObject {
    @Published var detectedObjects: [DetectedObject] = []
    @Published var isProcessing = false
    
    struct DetectedObject: Identifiable {
        let id = UUID()
        let label: String
        let confidence: Float
        let boundingBox: CGRect
        let position: ObjectPosition
    }
    
    enum ObjectPosition: String {
        case center = "in the center"
        case left = "on the left"
        case right = "on the right"
        case top = "at the top"
        case bottom = "at the bottom"
        case topLeft = "in the top left"
        case topRight = "in the top right"
        case bottomLeft = "in the bottom left"
        case bottomRight = "in the bottom right"
    }
    
    func detectObjects(in image: UIImage, completion: @escaping ([DetectedObject]) -> Void) {
        guard let cgImage = image.cgImage else {
            completion([])
            return
        }
        
        isProcessing = true
        
        // Use Vision framework for object detection
        let request = VNRecognizeObjectsRequest { [weak self] request, error in
            DispatchQueue.main.async {
                self?.isProcessing = false
                if let results = request.results as? [VNRecognizedObjectObservation] {
                    let objects = self?.processObjectResults(results) ?? []
                    self?.detectedObjects = objects
                    completion(objects)
                } else {
                    completion([])
                }
            }
        }
        
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try handler.perform([request])
            } catch {
                DispatchQueue.main.async {
                    self.isProcessing = false
                    completion([])
                }
            }
        }
    }
    
    func classifyImage(_ image: UIImage, completion: @escaping ([DetectedObject]) -> Void) {
        guard let cgImage = image.cgImage else {
            completion([])
            return
        }
        
        isProcessing = true
        
        // Use Vision framework for image classification
        let request = VNClassifyImageRequest { [weak self] request, error in
            DispatchQueue.main.async {
                self?.isProcessing = false
                if let results = request.results as? [VNClassificationObservation] {
                    let objects = self?.processClassificationResults(results) ?? []
                    self?.detectedObjects = objects
                    completion(objects)
                } else {
                    completion([])
                }
            }
        }
        
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try handler.perform([request])
            } catch {
                DispatchQueue.main.async {
                    self.isProcessing = false
                    completion([])
                }
            }
        }
    }
    
    private func processObjectResults(_ results: [VNRecognizedObjectObservation]) -> [DetectedObject] {
        return results.compactMap { observation in
            guard let topLabel = observation.labels.first,
                  topLabel.confidence > 0.5 else { return nil }
            
            let position = determinePosition(for: observation.boundingBox)
            
            return DetectedObject(
                label: cleanLabel(topLabel.identifier),
                confidence: topLabel.confidence,
                boundingBox: observation.boundingBox,
                position: position
            )
        }
    }
    
    private func processClassificationResults(_ results: [VNClassificationObservation]) -> [DetectedObject] {
        return results.prefix(3).compactMap { observation -> DetectedObject? in
            guard observation.confidence > 0.3 else { return nil }
            
            return DetectedObject(
                label: cleanLabel(observation.identifier),
                confidence: observation.confidence,
                boundingBox: CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5), // Center region
                position: .center
            )
        }
    }
    
    private func determinePosition(for boundingBox: CGRect) -> ObjectPosition {
        let centerX = boundingBox.midX
        let centerY = boundingBox.midY
        
        // Note: Vision uses different coordinate system (origin at bottom-left)
        let normalizedY = 1.0 - centerY
        
        if normalizedY < 0.33 {
            if centerX < 0.33 {
                return .topLeft
            } else if centerX > 0.67 {
                return .topRight
            } else {
                return .top
            }
        } else if normalizedY > 0.67 {
            if centerX < 0.33 {
                return .bottomLeft
            } else if centerX > 0.67 {
                return .bottomRight
            } else {
                return .bottom
            }
        } else {
            if centerX < 0.33 {
                return .left
            } else if centerX > 0.67 {
                return .right
            } else {
                return .center
            }
        }
    }
    
    private func cleanLabel(_ label: String) -> String {
        // Clean up labels for better speech output
        return label
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .lowercased()
            .capitalized
    }
    
    func generateObjectDescription() -> String {
        guard !detectedObjects.isEmpty else {
            return "No objects detected in the current view."
        }
        
        let sortedObjects = detectedObjects.sorted { $0.confidence > $1.confidence }
        let topObjects = Array(sortedObjects.prefix(3))
        
        var description = "I can see "
        
        for (index, object) in topObjects.enumerated() {
            let confidence = Int(object.confidence * 100)
            let objectDesc = "\(object.label) \(object.position.rawValue)"
            
            if index == 0 {
                description += objectDesc
            } else if index == topObjects.count - 1 {
                description += " and \(objectDesc)"
            } else {
                description += ", \(objectDesc)"
            }
        }
        
        description += "."
        return description
    }
    
    func quickScan(image: UIImage, completion: @escaping (String) -> Void) {
        // Perform both object detection and classification for comprehensive results
        var objectResults: [DetectedObject] = []
        var classificationResults: [DetectedObject] = []
        let group = DispatchGroup()
        
        group.enter()
        detectObjects(in: image) { objects in
            objectResults = objects
            group.leave()
        }
        
        group.enter()
        classifyImage(image) { classifications in
            classificationResults = classifications
            group.leave()
        }
        
        group.notify(queue: .main) {
            // Combine results, prioritizing object detection over classification
            var combinedResults = objectResults
            
            // Add classification results that aren't already covered
            for classification in classificationResults {
                let alreadyDetected = objectResults.contains { object in
                    object.label.lowercased().contains(classification.label.lowercased()) ||
                    classification.label.lowercased().contains(object.label.lowercased())
                }
                
                if !alreadyDetected {
                    combinedResults.append(classification)
                }
            }
            
            self.detectedObjects = Array(combinedResults.prefix(5))
            completion(self.generateObjectDescription())
        }
    }
} 