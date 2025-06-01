import SwiftUI

struct SettingsView: View {
    @ObservedObject var speechOutput: SpeechOutput
    @ObservedObject var audioManager: AudioManager
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            Form {
                Section("Speech Settings") {
                    VStack(alignment: .leading) {
                        Text("Speech Rate: \(speechOutput.speechRate, specifier: "%.2f")")
                            .accessibilityLabel("Speech rate \(speechOutput.speechRate, specifier: "%.2f")")
                        
                        Slider(value: $speechOutput.speechRate, in: 0.1...1.0, step: 0.05)
                            .accessibilityLabel("Speech rate slider")
                            .accessibilityValue("\(speechOutput.speechRate, specifier: "%.2f")")
                    }
                    
                    VStack(alignment: .leading) {
                        Text("Speech Pitch: \(speechOutput.speechPitch, specifier: "%.2f")")
                            .accessibilityLabel("Speech pitch \(speechOutput.speechPitch, specifier: "%.2f")")
                        
                        Slider(value: $speechOutput.speechPitch, in: 0.5...2.0, step: 0.1)
                            .accessibilityLabel("Speech pitch slider")
                            .accessibilityValue("\(speechOutput.speechPitch, specifier: "%.2f")")
                    }
                    
                    VStack(alignment: .leading) {
                        Text("Speech Volume: \(speechOutput.speechVolume, specifier: "%.2f")")
                            .accessibilityLabel("Speech volume \(speechOutput.speechVolume, specifier: "%.2f")")
                        
                        Slider(value: $speechOutput.speechVolume, in: 0.1...1.0, step: 0.05)
                            .accessibilityLabel("Speech volume slider")
                            .accessibilityValue("\(speechOutput.speechVolume, specifier: "%.2f")")
                    }
                    
                    Button("Test Speech") {
                        speechOutput.speak("This is a test of the current speech settings.")
                    }
                    .accessibilityHint("Plays sample speech with current settings")
                }
                
                Section("Recording Settings") {
                    VStack(alignment: .leading) {
                        Text("Recording Duration: \(audioManager.recordingDuration, specifier: "%.1f") seconds")
                            .accessibilityLabel("Recording duration \(audioManager.recordingDuration, specifier: "%.1f") seconds")
                        
                        Slider(value: $audioManager.recordingDuration, in: 1.0...30.0, step: 0.5)
                            .accessibilityLabel("Recording duration slider")
                            .accessibilityValue("\(audioManager.recordingDuration, specifier: "%.1f") seconds")
                    }
                    
                    Text("Longer recording time allows for more detailed questions but uses more data.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Section("Accessibility") {
                    Button("Reset to Defaults") {
                        resetToDefaults()
                    }
                    .accessibilityHint("Resets all settings to default values")
                    
                    Text("Speech and recording settings are optimized for blind and visually impaired users.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Section("About") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("BlindAssistant v1.0")
                            .font(.headline)
                        
                        Text("A voice-activated camera assistant designed for blind and visually impaired users.")
                            .font(.caption)
                        
                        Text("Uses OpenAI Whisper for speech recognition and GPT-4 Vision for scene analysis.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .accessibilityLabel("Done, close settings")
                }
            }
        }
    }
    
    private func resetToDefaults() {
        speechOutput.speechRate = 0.45
        speechOutput.speechPitch = 1.0
        speechOutput.speechVolume = 1.0
        audioManager.recordingDuration = 5.0
        
        speechOutput.speakStatus("Settings reset to defaults")
    }
} 