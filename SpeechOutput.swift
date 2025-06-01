import AVFoundation
import Foundation

class SpeechOutput: NSObject, ObservableObject {
    private let synthesizer = AVSpeechSynthesizer()
    
    @Published var isSpeaking = false
    @Published var speechRate: Float = 0.45
    @Published var speechPitch: Float = 1.0
    @Published var speechVolume: Float = 1.0
    
    private var currentUtterance: AVSpeechUtterance?
    
    override init() {
        super.init()
        synthesizer.delegate = self
        setupAudioSession()
    }
    
    private func setupAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, options: [.duckOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to setup audio session for speech: \(error)")
        }
    }
    
    func speak(_ text: String, priority: SpeechPriority = .normal) {
        guard !text.isEmpty else { return }
        
        // Handle priority - stop current speech if high priority
        if priority == .high && isSpeaking {
            stop()
        }
        
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = speechRate
        utterance.pitchMultiplier = speechPitch
        utterance.volume = speechVolume
        
        // Add slight pause for natural speech
        utterance.preUtteranceDelay = 0.1
        utterance.postUtteranceDelay = 0.1
        
        currentUtterance = utterance
        synthesizer.speak(utterance)
    }
    
    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        currentUtterance = nil
    }
    
    func pause() {
        synthesizer.pauseSpeaking(at: .word)
    }
    
    func resume() {
        synthesizer.continueSpeaking()
    }
    
    func adjustSpeechRate(_ rate: Float) {
        speechRate = max(0.1, min(1.0, rate))
    }
    
    func adjustPitch(_ pitch: Float) {
        speechPitch = max(0.5, min(2.0, pitch))
    }
    
    func adjustVolume(_ volume: Float) {
        speechVolume = max(0.1, min(1.0, volume))
    }
    
    // Quick speech for status updates
    func speakStatus(_ message: String) {
        speak(message, priority: .high)
    }
    
    // Announce important information with emphasis
    func announce(_ message: String) {
        let emphasizedMessage = message
        speak(emphasizedMessage, priority: .high)
    }
}

extension SpeechOutput: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.isSpeaking = true
        }
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.isSpeaking = false
            self.currentUtterance = nil
        }
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.isSpeaking = false
            self.currentUtterance = nil
        }
    }
}

enum SpeechPriority {
    case low
    case normal
    case high
}

// Global convenience function for backward compatibility
func speak(_ text: String) {
    let speechOutput = SpeechOutput()
    speechOutput.speak(text)
} 