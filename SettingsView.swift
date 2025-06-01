import SwiftUI

struct SettingsView: View {
    @ObservedObject var speechOutput: SpeechOutput
    @ObservedObject var audioManager: AudioManager
    @ObservedObject var navigationAssistant = NavigationAssistant()
    
    @Environment(\.dismiss) private var dismiss
    
    @State private var homeAddress = ""
    @State private var newContactName = ""
    @State private var newContactPhone = ""
    @State private var newContactRelationship = ""
    @State private var showingAddContact = false
    
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
                
                Section("Home & Navigation") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Home Address")
                            .font(.headline)
                        
                        TextField("Enter your home address", text: $homeAddress)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .accessibilityLabel("Home address input field")
                        
                        Button("Set Home Location") {
                            setHomeLocation()
                        }
                        .disabled(homeAddress.isEmpty)
                        .accessibilityHint("Sets your home address for quick navigation")
                    }
                    
                    Button("Clear Location History") {
                        clearLocationHistory()
                    }
                    .foregroundColor(.red)
                    .accessibilityHint("Removes all saved locations except home")
                }
                
                Section("Emergency Contacts") {
                    ForEach(navigationAssistant.emergencyContacts, id: \.id) { contact in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(contact.name)
                                        .font(.headline)
                                    Text(contact.relationship)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                                
                                VStack(alignment: .trailing) {
                                    Text(contact.phoneNumber)
                                        .font(.caption)
                                    
                                    if contact.isLocationShared {
                                        HStack {
                                            Image(systemName: "location.fill")
                                                .foregroundColor(.green)
                                            Text("Sharing")
                                                .font(.caption)
                                                .foregroundColor(.green)
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .onDelete(perform: deleteContact)
                    
                    Button("Add Emergency Contact") {
                        showingAddContact = true
                    }
                    .accessibilityHint("Adds a new emergency contact for navigation assistance")
                }
                
                Section("Location History") {
                    if navigationAssistant.locationHistory.isEmpty {
                        Text("No location history")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(Array(navigationAssistant.locationHistory.prefix(5)), id: \.id) { location in
                            HStack {
                                Image(systemName: iconForCategory(location.category))
                                    .foregroundColor(colorForCategory(location.category))
                                
                                VStack(alignment: .leading) {
                                    Text(location.name)
                                        .font(.headline)
                                    Text(formatDate(location.timestamp))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                            }
                        }
                    }
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
                        Text("BlindAssistant v2.0")
                            .font(.headline)
                        
                        Text("Enhanced voice-activated camera assistant with navigation, family/friend location sharing, and emergency features.")
                            .font(.caption)
                        
                        Text("Features: Offline mode, object detection, GPS navigation, emergency contacts, and return home functionality.")
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
        .sheet(isPresented: $showingAddContact) {
            AddContactView(
                name: $newContactName,
                phone: $newContactPhone,
                relationship: $newContactRelationship,
                onSave: { addContact() },
                onCancel: { showingAddContact = false }
            )
        }
        .onAppear {
            loadCurrentHomeAddress()
        }
    }
    
    // MARK: - Helper Methods
    
    private func setHomeLocation() {
        guard !homeAddress.isEmpty else { return }
        
        navigationAssistant.setHomeLocation(homeAddress) { result in
            speechOutput.speak(result)
        }
    }
    
    private func clearLocationHistory() {
        // Keep home location but clear history
        navigationAssistant.locationHistory.removeAll { $0.category != .home }
        speechOutput.speak("Location history cleared")
    }
    
    private func addContact() {
        guard !newContactName.isEmpty && !newContactPhone.isEmpty else { return }
        
        navigationAssistant.addEmergencyContact(
            name: newContactName,
            phoneNumber: newContactPhone,
            relationship: newContactRelationship.isEmpty ? "Contact" : newContactRelationship
        )
        
        speechOutput.speak("Emergency contact \(newContactName) added")
        
        // Clear fields
        newContactName = ""
        newContactPhone = ""
        newContactRelationship = ""
        showingAddContact = false
    }
    
    private func deleteContact(at offsets: IndexSet) {
        for index in offsets {
            let contact = navigationAssistant.emergencyContacts[index]
            speechOutput.speak("Removed \(contact.name) from emergency contacts")
        }
        navigationAssistant.emergencyContacts.remove(atOffsets: offsets)
    }
    
    private func loadCurrentHomeAddress() {
        // Load current home address if available
        if let homeLocation = navigationAssistant.locationHistory.first(where: { $0.category == .home }) {
            homeAddress = homeLocation.name
        }
    }
    
    private func iconForCategory(_ category: NavigationAssistant.LocationCategory) -> String {
        switch category {
        case .home: return "house.fill"
        case .work: return "building.fill"
        case .frequentPlace: return "star.fill"
        case .startingPoint: return "mappin.circle.fill"
        case .emergency: return "exclamationmark.triangle.fill"
        }
    }
    
    private func colorForCategory(_ category: NavigationAssistant.LocationCategory) -> Color {
        switch category {
        case .home: return .blue
        case .work: return .orange
        case .frequentPlace: return .yellow
        case .startingPoint: return .purple
        case .emergency: return .red
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    private func resetToDefaults() {
        speechOutput.speechRate = 0.45
        speechOutput.speechPitch = 1.0
        speechOutput.speechVolume = 1.0
        audioManager.recordingDuration = 5.0
        
        speechOutput.speakStatus("Settings reset to defaults")
    }
}

struct AddContactView: View {
    @Binding var name: String
    @Binding var phone: String
    @Binding var relationship: String
    let onSave: () -> Void
    let onCancel: () -> Void
    
    var body: some View {
        NavigationView {
            Form {
                Section("Contact Information") {
                    TextField("Name", text: $name)
                        .accessibilityLabel("Contact name")
                    
                    TextField("Phone Number", text: $phone)
                        .keyboardType(.phonePad)
                        .accessibilityLabel("Phone number")
                    
                    TextField("Relationship (e.g., Mom, Friend)", text: $relationship)
                        .accessibilityLabel("Relationship to contact")
                }
                
                Section {
                    Text("Emergency contacts can share their location with you for navigation assistance. They will need to enable location sharing separately.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Add Contact")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        onCancel()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        onSave()
                    }
                    .disabled(name.isEmpty || phone.isEmpty)
                }
            }
        }
    }
} 