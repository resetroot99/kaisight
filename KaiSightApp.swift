import SwiftUI
import Combine

@main
struct KaiSightApp: App {
    let healthCore = KaiSightHealthCore.shared
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(healthCore)
                .environmentObject(healthCore.bleHealthMonitor)
                .environmentObject(healthCore.emergencyProtocol)
                .environmentObject(healthCore.healthProfileManager)
                .environmentObject(healthCore.dropDetector)
                .environmentObject(healthCore.airPodsLocator)
                .onTapGesture {
                    // Handle screen taps for drop recovery
                    healthCore.dropDetector.handleScreenTap()
                }
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var healthCore: KaiSightHealthCore
    @EnvironmentObject var bleMonitor: BLEHealthMonitor
    @EnvironmentObject var emergencyProtocol: EmergencyProtocol
    @EnvironmentObject var profileManager: HealthProfileManager
    @EnvironmentObject var dropDetector: DropDetector
    @EnvironmentObject var airPodsLocator: AirPodsLocator
    
    @State private var showHealthProfile = false
    @State private var showEmergencySettings = false
    @State private var testCommand = ""
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // System Status Header
                SystemStatusView()
                
                // Drop Detection Status (if active)
                if dropDetector.isDropDetected || dropDetector.dropRecoveryMode {
                    DropDetectionStatusView()
                }
                
                // AirPods Locator Status (if searching or recent activity)
                if airPodsLocator.isSearching || airPodsLocator.lastKnownLocation != nil {
                    AirPodsLocatorStatusView()
                }
                
                // Health Monitoring Section
                HealthMonitoringSection()
                
                // Emergency Controls Section
                EmergencyControlsSection()
                
                // Voice Command Testing
                VoiceCommandSection(testCommand: $testCommand)
                
                Spacer()
            }
            .padding()
            .navigationTitle("KaiSight Health")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu("Settings") {
                        Button("Health Profile") {
                            showHealthProfile = true
                        }
                        
                        Button("Emergency Settings") {
                            showEmergencySettings = true
                        }
                        
                        Button("System Check") {
                            performSystemHealthCheck()
                        }
                        
                        if Config.debugMode {
                            Button("Simulate Drop") {
                                dropDetector.simulateDropEvent()
                            }
                            
                            Button("Test AirPods Search") {
                                airPodsLocator.findAirPods(triggeredBy: "debug")
                            }
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showHealthProfile) {
            HealthProfileView()
        }
        .sheet(isPresented: $showEmergencySettings) {
            EmergencySettingsView()
        }
        .onAppear {
            healthCore.startHealthMonitoring()
        }
    }
    
    private func performSystemHealthCheck() {
        let status = healthCore.performSystemHealthCheck()
        let message = status.isHealthy ? "All systems healthy" : "Issues detected: \(status.issues.joined(separator: ", "))"
        healthCore.speechOutput.speak(message)
    }
}

struct SystemStatusView: View {
    @EnvironmentObject var healthCore: KaiSightHealthCore
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Circle()
                    .fill(healthCore.isSystemReady ? Color.green : Color.orange)
                    .frame(width: 12, height: 12)
                
                Text(healthCore.systemStatus)
                    .font(.headline)
                    .foregroundColor(healthCore.isSystemReady ? .primary : .orange)
                
                Spacer()
            }
            
            if healthCore.isSystemReady {
                let summary = healthCore.getSystemSummary()
                Text(summary)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.leading)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

struct HealthMonitoringSection: View {
    @EnvironmentObject var bleMonitor: BLEHealthMonitor
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Health Monitoring")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button(bleMonitor.isScanning ? "Stop Scan" : "Scan Devices") {
                    if bleMonitor.isScanning {
                        bleMonitor.stopScanning()
                    } else {
                        bleMonitor.startScanning()
                    }
                }
                .buttonStyle(.bordered)
            }
            
            // Connected Devices
            VStack(alignment: .leading, spacing: 8) {
                Text("Connected Devices: \(bleMonitor.connectedDevices.count)")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                ForEach(bleMonitor.connectedDevices) { device in
                    HStack {
                        Image(systemName: deviceIcon(for: device.type))
                            .foregroundColor(.blue)
                        
                        VStack(alignment: .leading) {
                            Text(device.name)
                                .font(.caption)
                                .fontWeight(.medium)
                            
                            Text(device.type.description)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Circle()
                            .fill(Color.green)
                            .frame(width: 8, height: 8)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                }
            }
            
            // Recent Readings
            VStack(alignment: .leading, spacing: 8) {
                Text("Recent Readings: \(bleMonitor.latestReadings.count)")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                ForEach(Array(bleMonitor.latestReadings.suffix(3)), id: \.id) { reading in
                    HStack {
                        Text(reading.type.rawValue.capitalized)
                            .font(.caption)
                            .fontWeight(.medium)
                        
                        Spacer()
                        
                        Text("\(Int(reading.value)) \(reading.unit)")
                            .font(.caption)
                            .foregroundColor(reading.isCritical ? .red : .primary)
                        
                        Text(timeAgo(reading.timestamp))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(reading.isCritical ? Color.red.opacity(0.1) : Color(.systemGray6))
                    .cornerRadius(8)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 2)
    }
    
    private func deviceIcon(for type: DeviceType) -> String {
        switch type {
        case .glucoseMeter: return "drop.circle"
        case .heartRateMonitor: return "heart.circle"
        case .bloodPressureMonitor: return "staroflife.circle"
        case .thermometer: return "thermometer"
        case .pulseOximeter: return "lungs.circle"
        default: return "sensor.tag.radiowaves.forward"
        }
    }
    
    private func timeAgo(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 {
            return "now"
        } else if interval < 3600 {
            return "\(Int(interval / 60))m"
        } else {
            return "\(Int(interval / 3600))h"
        }
    }
}

struct EmergencyControlsSection: View {
    @EnvironmentObject var emergencyProtocol: EmergencyProtocol
    @EnvironmentObject var healthCore: KaiSightHealthCore
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Emergency Controls")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer()
                
                if emergencyProtocol.isActive {
                    Button("Resolve Emergency") {
                        emergencyProtocol.resolveEmergency(response: .userResponded)
                    }
                    .buttonStyle(.bordered)
                    .foregroundColor(.green)
                }
            }
            
            if emergencyProtocol.isActive {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                        
                        Text("EMERGENCY ACTIVE")
                            .font(.headline)
                            .fontWeight(.bold)
                            .foregroundColor(.red)
                    }
                    
                    if let emergency = emergencyProtocol.currentEmergency {
                        Text(emergency.condition.description)
                            .font(.subheadline)
                        
                        Text("Started: \(emergency.startTime.formatted())")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
                .background(Color.red.opacity(0.1))
                .cornerRadius(8)
            }
            
            HStack(spacing: 12) {
                Button("Test Emergency") {
                    healthCore.simulateEmergency(type: .fall)
                }
                .buttonStyle(.bordered)
                .foregroundColor(.orange)
                
                Button("Wellness Check") {
                    emergencyProtocol.performWellnessCheck()
                }
                .buttonStyle(.bordered)
                
                Button("Emergency Test") {
                    emergencyProtocol.testEmergencySystem()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 2)
    }
}

struct VoiceCommandSection: View {
    @Binding var testCommand: String
    @EnvironmentObject var healthCore: KaiSightHealthCore
    @EnvironmentObject var airPodsLocator: AirPodsLocator
    
    let commonCommands = [
        "What's my glucose?",
        "System status",
        "Health summary",
        "Scan for devices",
        "Emergency contact",
        "I'm okay",
        "Drop status",
        "I'm fine"
    ]
    
    let airPodsCommands = [
        "Find my AirPods",
        "Where are my AirPods?",
        "AirPods status",
        "Found them",
        "Stop searching",
        "Warmer",
        "Colder"
    ]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Voice Commands")
                .font(.title2)
                .fontWeight(.semibold)
            
            TextField("Enter voice command", text: $testCommand)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    healthCore.processVoiceCommand(testCommand)
                    testCommand = ""
                }
            
            VStack(alignment: .leading, spacing: 12) {
                Text("Health Commands:")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 8) {
                    ForEach(commonCommands, id: \.self) { command in
                        Button(command) {
                            healthCore.processVoiceCommand(command)
                        }
                        .buttonStyle(.bordered)
                        .font(.caption)
                    }
                }
            }
            
            VStack(alignment: .leading, spacing: 12) {
                Text("AirPods Commands:")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.blue)
                
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 8) {
                    ForEach(airPodsCommands, id: \.self) { command in
                        Button(command) {
                            healthCore.processVoiceCommand(command)
                        }
                        .buttonStyle(.bordered)
                        .font(.caption)
                        .foregroundColor(.blue)
                        .disabled(command.contains("Warmer") || command.contains("Colder") || command.contains("Found them") ? !airPodsLocator.isSearching : false)
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 2)
    }
}

struct DropDetectionStatusView: View {
    @EnvironmentObject var dropDetector: DropDetector
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "iphone.and.arrow.forward")
                    .foregroundColor(.orange)
                    .font(.title2)
                
                Text("Drop Detection Active")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.orange)
                
                Spacer()
            }
            
            if dropDetector.isDropDetected {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                        
                        Text("DROP DETECTED")
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .foregroundColor(.red)
                    }
                    
                    Text("Please confirm you're okay by saying 'I'm fine' or tapping the screen")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if let lastDrop = dropDetector.lastDropTime {
                        Text("Detected: \(lastDrop.formatted())")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
                .background(Color.red.opacity(0.1))
                .cornerRadius(8)
            }
            
            if dropDetector.dropRecoveryMode {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "arrow.clockwise.circle")
                            .foregroundColor(.blue)
                        
                        Text("SYSTEM RECOVERY")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.blue)
                    }
                    
                    Text("Restoring normal operation after drop detection")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color.blue.opacity(0.1))
                .cornerRadius(8)
            }
            
            // Drop Statistics
            let dropStats = dropDetector.getDropStatistics()
            if dropStats.totalDrops > 0 {
                HStack {
                    Text("Total drops: \(dropStats.totalDrops)")
                        .font(.caption)
                    
                    Spacer()
                    
                    Text("Recent: \(dropStats.recentDrops)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 2)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.orange, lineWidth: 2)
        )
    }
}

struct AirPodsLocatorStatusView: View {
    @EnvironmentObject var airPodsLocator: AirPodsLocator
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "airpods")
                    .foregroundColor(.blue)
                    .font(.title2)
                
                Text("AirPods Locator")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.blue)
                
                Spacer()
                
                if airPodsLocator.isSearching {
                    Button("Stop Search") {
                        airPodsLocator.stopSearch()
                    }
                    .buttonStyle(.bordered)
                    .foregroundColor(.red)
                }
            }
            
            if airPodsLocator.isSearching {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "magnifyingglass.circle")
                            .foregroundColor(.blue)
                        
                        Text("SEARCHING FOR AIRPODS")
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .foregroundColor(.blue)
                    }
                    
                    Text(airPodsLocator.getSearchStatus())
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("Say 'found them' when you locate your AirPods")
                        .font(.caption2)
                        .foregroundColor(.blue)
                }
                .padding()
                .background(Color.blue.opacity(0.1))
                .cornerRadius(8)
            }
            
            if let location = airPodsLocator.lastKnownLocation {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "location.circle")
                            .foregroundColor(.green)
                        
                        Text("LAST KNOWN LOCATION")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.green)
                    }
                    
                    let timeAgo = Date().timeIntervalSince(location.timestamp)
                    let timeDescription = timeAgo < 3600 ? "\(Int(timeAgo/60)) minutes ago" : "\(Int(timeAgo/3600)) hours ago"
                    
                    Text("Last seen: \(timeDescription)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("Room: \(location.roomDescription)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color.green.opacity(0.1))
                .cornerRadius(8)
            }
            
            // Quick Actions
            HStack(spacing: 12) {
                Button("Find AirPods") {
                    airPodsLocator.findAirPods(triggeredBy: "ui")
                }
                .buttonStyle(.bordered)
                .disabled(airPodsLocator.isSearching)
                
                Button("Status") {
                    airPodsLocator.speakSearchStatus()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 2)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.blue, lineWidth: 2)
        )
    }
}

struct HealthProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var profileManager: HealthProfileManager
    
    var body: some View {
        NavigationView {
            VStack {
                Text("Health Profile Configuration")
                    .font(.title2)
                    .padding()
                
                Text("Profile setup would go here")
                    .foregroundColor(.secondary)
                
                Spacer()
            }
            .navigationTitle("Health Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct EmergencySettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var emergencyProtocol: EmergencyProtocol
    
    var body: some View {
        NavigationView {
            VStack {
                Text("Emergency Settings")
                    .font(.title2)
                    .padding()
                
                Text("Emergency configuration would go here")
                    .foregroundColor(.secondary)
                
                Spacer()
            }
            .navigationTitle("Emergency Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Preview

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(KaiSightHealthCore.shared)
            .environmentObject(KaiSightHealthCore.shared.bleHealthMonitor)
            .environmentObject(KaiSightHealthCore.shared.emergencyProtocol)
            .environmentObject(KaiSightHealthCore.shared.healthProfileManager)
            .environmentObject(KaiSightHealthCore.shared.dropDetector)
            .environmentObject(KaiSightHealthCore.shared.airPodsLocator)
    }
} 