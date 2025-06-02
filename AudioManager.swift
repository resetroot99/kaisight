import Foundation
import AVFoundation

class AudioManager: NSObject, ObservableObject {
    private let audioEngine = AVAudioEngine()
    private var audioFile: AVAudioFile?
    private var completion: ((String?) -> Void)?
    private let whisperAPI = WhisperAPI()
    
    @Published var isRecording = false
    @Published var recordingDuration: TimeInterval = 5.0 // Configurable duration
    
    private var recordingTimer: Timer?
    
    override init() {
        super.init()
        setupAudioSession()
    }
    
    private func setupAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try audioSession.setActive(true)
        } catch {
        }
    }
    
    func startRecording(completion: @escaping (String?) -> Void) {
        guard !isRecording else { return }
        
        self.completion = completion
        
        do {
            let inputNode = audioEngine.inputNode
            let format = inputNode.outputFormat(forBus: 0)
            
            // Create temporary file
            let tempDir = FileManager.default.temporaryDirectory
            let audioFileURL = tempDir.appendingPathComponent("speech_\(Date().timeIntervalSince1970).m4a")
            
            // Create audio file with better settings
            var settings = format.settings
            settings[AVFormatIDKey] = kAudioFormatMPEG4AAC
            settings[AVSampleRateKey] = 44100
            settings[AVNumberOfChannelsKey] = 1
            settings[AVEncoderAudioQualityKey] = AVAudioQuality.high.rawValue
            
            audioFile = try AVAudioFile(forWriting: audioFileURL, settings: settings)
            
            // Install audio tap
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                try? self?.audioFile?.write(from: buffer)
            }
            
            audioEngine.prepare()
            try audioEngine.start()
            
            isRecording = true
            
            // Auto-stop after configured duration
            recordingTimer = Timer.scheduledTimer(withTimeInterval: recordingDuration, repeats: false) { [weak self] _ in
                self?.stopRecording()
            }
            
        } catch {
            completion(nil)
        }
    }
    
    func stopRecording() {
        guard isRecording else { return }
        
        recordingTimer?.invalidate()
        recordingTimer = nil
        
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        
        isRecording = false
        
        // Send to Whisper API
        guard let audioFile = audioFile else {
            completion?(nil)
            return
        }
        
        whisperAPI.transcribe(audioFileURL: audioFile.url) { [weak self] result in
            DispatchQueue.main.async {
                self?.completion?(result)
                self?.completion = nil
                self?.audioFile = nil
            }
        }
    }
    
    func setRecordingDuration(_ duration: TimeInterval) {
        recordingDuration = max(1.0, min(30.0, duration)) // Limit between 1-30 seconds
    }
} 