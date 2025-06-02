import Foundation
import AVFoundation
import Vision
import UIKit
import Combine

class RealTimeNarrator: NSObject, ObservableObject {
    private let captureSession = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let processingQueue = DispatchQueue(label: "narrator.processing", qos: .userInitiated)
    
    @Published var isNarrating = false
    @Published var currentNarration = ""
    @Published var detectedObjects: [String] = []
    @Published var detectedText: [String] = []
    
    private let gptManager = GPTManager()
    private let speechOutput = SpeechOutput()
    
    // Narration settings
    private var narrationInterval: TimeInterval = 3.0 // Narrate every 3 seconds
    private var lastNarrationTime: Date = Date.distantPast
    private var isProcessingFrame = false
    
    // Scene context for continuity
    private var previousScene = ""
    private var sceneChangeThreshold = 0.7 // Similarity threshold for scene changes
    
    override init() {
        super.init()
        setupCaptureSession()
    }
    
    private func setupCaptureSession() {
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            print("❌ No camera available")
            return
        }
        
        do {
            let input = try AVCaptureDeviceInput(device: camera)
            
            if captureSession.canAddInput(input) {
                captureSession.addInput(input)
            }
            
            videoOutput.setSampleBufferDelegate(self, queue: processingQueue)
            videoOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
            
            if captureSession.canAddOutput(videoOutput) {
                captureSession.addOutput(videoOutput)
            }
            
            // Configure for real-time processing
            captureSession.sessionPreset = .medium
            
        } catch {
            print("❌ Camera setup error: \(error)")
        }
    }
    
    func startNarration() {
        guard !isNarrating else { return }
        
        isNarrating = true
        captureSession.startRunning()
        speechOutput.speak("Real-time narration started. I'll describe your surroundings as you move.")
        
        Config.debugLog("Started real-time narration")
    }
    
    func stopNarration() {
        guard isNarrating else { return }
        
        isNarrating = false
        captureSession.stopRunning()
        speechOutput.speak("Real-time narration stopped.")
        
        Config.debugLog("Stopped real-time narration")
    }
    
    func adjustNarrationSpeed(_ speed: NarrationSpeed) {
        switch speed {
        case .slow:
            narrationInterval = 5.0
        case .normal:
            narrationInterval = 3.0
        case .fast:
            narrationInterval = 1.5
        case .continuous:
            narrationInterval = 0.5
        }
        
        speechOutput.speak("Narration speed set to \(speed.rawValue)")
    }
    
    private func processFrame(_ image: UIImage) {
        guard !isProcessingFrame else { return }
        
        let now = Date()
        guard now.timeIntervalSince(lastNarrationTime) >= narrationInterval else { return }
        
        isProcessingFrame = true
        lastNarrationTime = now
        
        // Parallel processing of Vision tasks
        let group = DispatchGroup()
        var objects: [String] = []
        var texts: [String] = []
        var landmarks: [String] = []
        
        // Object detection
        group.enter()
        detectObjects(in: image) { detectedObjects in
            objects = detectedObjects
            group.leave()
        }
        
        // Text recognition
        group.enter()
        recognizeText(in: image) { detectedTexts in
            texts = detectedTexts
            group.leave()
        }
        
        // Scene classification
        group.enter()
        classifyScene(in: image) { sceneLandmarks in
            landmarks = sceneLandmarks
            group.leave()
        }
        
        group.notify(queue: .main) {
            self.generateNarration(objects: objects, texts: texts, landmarks: landmarks, image: image)
        }
    }
    
    private func detectObjects(in image: UIImage, completion: @escaping ([String]) -> Void) {
        guard let cgImage = image.cgImage else {
            completion([])
            return
        }
        
        let request = VNRecognizeObjectsRequest { request, error in
            guard let observations = request.results as? [VNRecognizedObjectObservation] else {
                completion([])
                return
            }
            
            let objects = observations.compactMap { observation in
                observation.labels.first?.identifier
            }.prefix(5).map { String($0) }
            
            completion(Array(objects))
        }
        
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? handler.perform([request])
    }
    
    private func recognizeText(in image: UIImage, completion: @escaping ([String]) -> Void) {
        guard let cgImage = image.cgImage else {
            completion([])
            return
        }
        
        let request = VNRecognizeTextRequest { request, error in
            guard let observations = request.results as? [VNRecognizedTextObservation] else {
                completion([])
                return
            }
            
            let texts = observations.compactMap { observation in
                observation.topCandidates(1).first?.string
            }.prefix(3).map { String($0) }
            
            completion(Array(texts))
        }
        
        request.recognitionLevel = .fast
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? handler.perform([request])
    }
    
    private func classifyScene(in image: UIImage, completion: @escaping ([String]) -> Void) {
        guard let cgImage = image.cgImage else {
            completion([])
            return
        }
        
        let request = VNClassifyImageRequest { request, error in
            guard let observations = request.results as? [VNClassificationObservation] else {
                completion([])
                return
            }
            
            let landmarks = observations.prefix(3).map { observation in
                "\(observation.identifier) (\(Int(observation.confidence * 100))%)"
            }
            
            completion(landmarks)
        }
        
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? handler.perform([request])
    }
    
    private func generateNarration(objects: [String], texts: [String], landmarks: [String], image: UIImage) {
        // Update published properties
        DispatchQueue.main.async {
            self.detectedObjects = objects
            self.detectedText = texts
        }
        
        // Create context for GPT
        var context = "Describe the environment briefly and naturally. "
        
        if !objects.isEmpty {
            context += "Objects detected: \(objects.joined(separator: ", ")). "
        }
        
        if !texts.isEmpty {
            context += "Text visible: \(texts.joined(separator: ", ")). "
        }
        
        if !landmarks.isEmpty {
            context += "Scene type: \(landmarks.first ?? "unknown"). "
        }
        
        context += "Focus on what's most important for navigation and awareness. Keep it under 20 words and conversational."
        
        // Add scene continuity
        if !previousScene.isEmpty {
            context += " Previous scene: \(previousScene). Only mention significant changes."
        }
        
        gptManager.ask(prompt: context, image: image) { [weak self] narration in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                // Check if scene has changed significantly
                let similarity = self.calculateSimilarity(self.previousScene, narration)
                
                if similarity < self.sceneChangeThreshold || self.previousScene.isEmpty {
                    self.currentNarration = narration
                    self.speechOutput.speak(narration, priority: .normal)
                    self.previousScene = narration
                    
                    Config.debugLog("Narration: \(narration)")
                } else {
                    Config.debugLog("Scene unchanged, skipping narration")
                }
                
                self.isProcessingFrame = false
            }
        }
    }
    
    private func calculateSimilarity(_ text1: String, _ text2: String) -> Double {
        let words1 = Set(text1.lowercased().components(separatedBy: .whitespacesAndNewlines))
        let words2 = Set(text2.lowercased().components(separatedBy: .whitespacesAndNewlines))
        
        let intersection = words1.intersection(words2)
        let union = words1.union(words2)
        
        return union.isEmpty ? 0 : Double(intersection.count) / Double(union.count)
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension RealTimeNarrator: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()
        
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return }
        
        let image = UIImage(cgImage: cgImage)
        
        DispatchQueue.main.async {
            self.processFrame(image)
        }
    }
}

// MARK: - Supporting Types

enum NarrationSpeed: String, CaseIterable {
    case slow = "slow"
    case normal = "normal"
    case fast = "fast"
    case continuous = "continuous"
    
    var description: String {
        switch self {
        case .slow: return "Every 5 seconds"
        case .normal: return "Every 3 seconds"
        case .fast: return "Every 1.5 seconds"
        case .continuous: return "Continuous"
        }
    }
} 