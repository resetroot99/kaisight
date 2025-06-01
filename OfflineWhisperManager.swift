import Foundation
import Speech
import AVFoundation

class OfflineWhisperManager: NSObject, ObservableObject {
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    
    @Published var isAvailable = false
    @Published var isListening = false
    
    override init() {
        super.init()
        checkAvailability()
        requestPermissions()
    }
    
    private func checkAvailability() {
        guard let speechRecognizer = speechRecognizer else {
            isAvailable = false
            return
        }
        
        isAvailable = speechRecognizer.isAvailable
        
        speechRecognizer.delegate = self
    }
    
    private func requestPermissions() {
        SFSpeechRecognizer.requestAuthorization { authStatus in
            DispatchQueue.main.async {
                switch authStatus {
                case .authorized:
                    self.isAvailable = true
                case .denied, .restricted, .notDetermined:
                    self.isAvailable = false
                @unknown default:
                    self.isAvailable = false
                }
            }
        }
    }
    
    func startRecording(completion: @escaping (String?) -> Void) {
        guard isAvailable else {
            completion(nil)
            return
        }
        
        // Cancel any ongoing recognition
        if let recognitionTask = recognitionTask {
            recognitionTask.cancel()
            self.recognitionTask = nil
        }
        
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            completion(nil)
            return
        }
        
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        
        let inputNode = audioEngine.inputNode
        guard let recognitionRequest = recognitionRequest else {
            completion(nil)
            return
        }
        
        recognitionRequest.shouldReportPartialResults = true
        
        var finalResult: String?
        
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { result, error in
            if let result = result {
                finalResult = result.bestTranscription.formattedString
                
                if result.isFinal {
                    completion(finalResult)
                    self.stopRecording()
                }
            }
            
            if error != nil {
                completion(finalResult)
                self.stopRecording()
            }
        }
        
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            self.recognitionRequest?.append(buffer)
        }
        
        audioEngine.prepare()
        do {
            try audioEngine.start()
            isListening = true
            
            // Auto-stop after 10 seconds for offline mode
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                if self.isListening {
                    completion(finalResult)
                    self.stopRecording()
                }
            }
        } catch {
            completion(nil)
        }
    }
    
    func stopRecording() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask = nil
        
        isListening = false
    }
}

extension OfflineWhisperManager: SFSpeechRecognizerDelegate {
    func speechRecognizer(_ speechRecognizer: SFSpeechRecognizer, availabilityDidChange available: Bool) {
        DispatchQueue.main.async {
            self.isAvailable = available
        }
    }
} 