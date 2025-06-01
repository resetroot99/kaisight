import SwiftUI
import AVFoundation

struct ContentView: View {
    @StateObject var cameraManager = CameraManager()
    @StateObject var audioManager = AudioManager()
    @StateObject var speechOutput = SpeechOutput()
    let gpt = GPTManager()
    
    @State private var isRecording = false
    @State private var isProcessing = false
    @State private var statusMessage = "Ready to help you"
    @State private var showingSettings = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Status indicator
                VStack {
                    Image(systemName: statusIcon)
                        .font(.system(size: 40))
                        .foregroundColor(statusColor)
                        .accessibilityLabel(statusMessage)
                    
                    Text(statusMessage)
                        .font(.headline)
                        .multilineTextAlignment(.center)
                        .accessibilityLiveRegion(.polite)
                }
                .padding()
                
                // Camera preview (hidden but functional)
                CameraPreview(session: cameraManager.getSession())
                    .frame(height: 200)
                    .cornerRadius(12)
                    .accessibilityHidden(true)
                
                // Main action button
                Button(action: handleVoiceQuery) {
                    VStack {
                        Image(systemName: isRecording ? "stop.circle.fill" : "mic.circle.fill")
                            .font(.system(size: 60))
                        Text(isRecording ? "Recording..." : "Start Voice Query")
                            .font(.title2)
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 120)
                    .background(buttonColor)
                    .cornerRadius(20)
                    .scaleEffect(isRecording ? 1.1 : 1.0)
                    .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: isRecording)
                }
                .disabled(isProcessing)
                .accessibilityLabel(isRecording ? "Stop recording" : "Start voice query")
                .accessibilityHint("Double tap to start recording your question")
                
                Spacer()
            }
            .padding()
            .navigationTitle("BlindAssistant")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { showingSettings = true }) {
                        Image(systemName: "gear")
                            .font(.title2)
                    }
                    .accessibilityLabel("Settings")
                    .accessibilityHint("Opens app settings")
                }
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(speechOutput: speechOutput, audioManager: audioManager)
        }
        .onAppear {
            setupAccessibility()
            updateStatus("Ready to help you")
        }
    }
    
    private var statusIcon: String {
        if isRecording { return "waveform" }
        if isProcessing { return "gear" }
        return "eye"
    }
    
    private var statusColor: Color {
        if isRecording { return .red }
        if isProcessing { return .orange }
        return .blue
    }
    
    private var buttonColor: Color {
        if isRecording { return .red }
        if isProcessing { return .gray }
        return .blue
    }
    
    private func handleVoiceQuery() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }
    
    private func startRecording() {
        isRecording = true
        updateStatus("Listening... Speak now")
        
        // Haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
        
        // Capture photo first
        cameraManager.capturePhoto()
        
        // Start recording
        audioManager.startRecording { [self] transcription in
            DispatchQueue.main.async {
                self.isRecording = false
                self.processTranscription(transcription)
            }
        }
    }
    
    private func stopRecording() {
        audioManager.stopRecording()
        isRecording = false
        updateStatus("Processing...")
    }
    
    private func processTranscription(_ transcription: String?) {
        guard let transcription = transcription, !transcription.isEmpty else {
            updateStatus("I couldn't understand. Please try again.")
            speechOutput.speakStatus("I couldn't understand. Please try again.")
            return
        }
        
        isProcessing = true
        updateStatus("Analyzing scene and your question...")
        
        gpt.ask(prompt: transcription, image: cameraManager.capturedImage) { reply in
            DispatchQueue.main.async {
                self.isProcessing = false
                self.updateStatus("Ready to help you")
                self.speechOutput.speak(reply)
                
                // Success haptic
                let notificationFeedback = UINotificationFeedbackGenerator()
                notificationFeedback.notificationOccurred(.success)
            }
        }
    }
    
    private func updateStatus(_ message: String) {
        statusMessage = message
        // Announce status changes to VoiceOver users
        UIAccessibility.post(notification: .announcement, argument: message)
    }
    
    private func setupAccessibility() {
        // Ensure VoiceOver announces important changes
        UIAccessibility.post(notification: .screenChanged, argument: nil)
    }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.frame = CGRect(x: 0, y: 0, width: 300, height: 200)
        preview.videoGravity = .resizeAspectFill
        preview.cornerRadius = 12
        view.layer.addSublayer(preview)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        if let layer = uiView.layer.sublayers?.first as? AVCaptureVideoPreviewLayer {
            layer.frame = uiView.bounds
        }
    }
} 