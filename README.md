# BlindAssistant - Enhanced Voice + Camera Assistant for iOS

A comprehensive Swift-based iOS app that provides advanced voice-activated, camera-aware assistance specifically designed for blind and visually impaired users.

## ✅ Enhanced Features

### Core Functionality
- **Live camera feed** with optimized still frame capture
- **Advanced voice input** using OpenAI Whisper API with retry logic
- **GPT-4 Vision integration** for intelligent scene analysis
- **Natural text-to-speech** with customizable settings
- **Complete accessibility support** with VoiceOver integration

### Accessibility Enhancements
- **Haptic feedback** for button interactions and status changes
- **VoiceOver announcements** for status updates
- **Large, accessible buttons** with clear labels
- **Real-time status indicators** with audio feedback
- **Priority-based speech** system for important announcements

### Advanced Features
- **Configurable recording duration** (1-30 seconds)
- **Customizable speech settings** (rate, pitch, volume)
- **Intelligent error handling** with retry mechanisms
- **Image optimization** for faster processing and lower costs
- **Settings panel** for personalization

## 🧠 Enhanced Architecture

```
User Input → Audio Processing → Whisper API → GPT-4 Vision + Camera → Enhanced TTS
    ↓             ↓                ↓              ↓                      ↓
Haptic        Recording        Retry Logic    Scene Analysis      Priority Speech
Feedback      Duration         Error Handle   Optimization        Custom Settings
```

## 📁 Complete File Structure

```
BlindAssistant/
├── App.swift                 # Main SwiftUI app entry point
├── ContentView.swift          # Enhanced main UI with navigation
├── SettingsView.swift         # Customizable settings panel
├── CameraManager.swift        # Optimized camera handling
├── AudioManager.swift         # Advanced audio recording manager
├── WhisperAPI.swift          # Enhanced Whisper API with retry logic
├── GPTManager.swift          # Improved GPT-4 Vision integration
├── SpeechOutput.swift        # Advanced TTS with customization
├── Info.plist               # App permissions and configuration
└── README.md               # This comprehensive guide
```

## 🛠 Enhanced Setup Instructions

### 1. Create iOS Project in Xcode

1. Open Xcode
2. Create a new iOS project with SwiftUI
3. Set minimum deployment target to iOS 14.0+
4. Add all Swift files from this repository

### 2. Configure Enhanced Permissions

The `Info.plist` includes optimized permissions:
- **Camera access** for real-time environment analysis
- **Microphone access** for high-quality voice commands
- **Speech recognition** for accurate transcription
- **Background audio** for uninterrupted TTS

### 3. Add Your OpenAI API Key

In `Info.plist`, replace the placeholder with your actual key:

```xml
<key>OPENAI_API_KEY</key>
<string>sk-your-actual-openai-api-key-here</string>
```

### 4. Build and Test

1. Connect your iPhone (recommended for full testing)
2. Build and run in Xcode
3. Grant all requested permissions
4. Test voice commands and camera functionality

## 🚀 Enhanced Usage Guide

### Basic Operation
1. **Tap the microphone button** to start recording
2. **Speak your question clearly** (duration customizable in settings)
3. **Wait for processing** - status updates will be announced
4. **Listen to the response** - delivered through optimized TTS

### Advanced Features
- **Access Settings** via the gear icon for customization
- **Adjust speech rate** for comfortable listening
- **Configure recording duration** based on your needs
- **Test speech settings** with sample audio

### Example Voice Commands
- *"What do you see in front of me?"*
- *"Read any text in this image"*
- *"Are there any obstacles ahead?"*
- *"Describe the people in this room"*
- *"What colors are around me?"*

## ⚠️ System Requirements

- **iOS 14.0+** for full SwiftUI support
- **Valid OpenAI API key** with GPT-4 Vision access
- **Camera and microphone permissions**
- **Stable internet connection** for API calls
- **iPhone recommended** for optimal camera and haptic features

## 🎯 Key Improvements Over Basic Version

### User Experience
- ✅ **Visual status indicators** with color coding
- ✅ **Haptic feedback** for all interactions
- ✅ **VoiceOver integration** for complete accessibility
- ✅ **Configurable settings** for personalization
- ✅ **Error recovery** with user-friendly messages

### Technical Enhancements
- ✅ **Retry logic** for network failures
- ✅ **Image optimization** for faster processing
- ✅ **Memory management** improvements
- ✅ **Audio session handling** for better quality
- ✅ **Modular architecture** for easy maintenance

### Accessibility Focus
- ✅ **Priority speech system** for important announcements
- ✅ **Customizable TTS settings** for different users
- ✅ **Large touch targets** for easy interaction
- ✅ **Clear audio feedback** for all actions
- ✅ **Spatial awareness** in scene descriptions

## 🔧 Customization Options

### Speech Settings
- **Rate**: 0.1 to 1.0 (default: 0.45)
- **Pitch**: 0.5 to 2.0 (default: 1.0)
- **Volume**: 0.1 to 1.0 (default: 1.0)

### Recording Settings
- **Duration**: 1 to 30 seconds (default: 5 seconds)
- **Quality**: High-quality AAC encoding
- **Auto-stop**: Configurable timeout

### Accessibility Settings
- **VoiceOver support**: Full integration
- **Haptic patterns**: Success/error feedback
- **Status announcements**: Real-time updates

## 📝 Enhanced Technical Notes

- **GPT-4 Vision model** used for superior scene understanding
- **Images resized to 1024x1024** for optimal processing
- **JPEG compression at 80%** balancing quality and speed
- **Exponential backoff** for API rate limiting
- **Automatic cleanup** of temporary audio files
- **Thread-safe operations** throughout the app

## 🚨 Security & Best Practices

- **Secure API key storage** in app bundle
- **No data persistence** - privacy by design
- **Temporary file cleanup** after processing
- **Network timeout handling** for reliability
- **Error logging** for debugging (no sensitive data)

## 🎨 Future Enhancement Ideas

- **Offline Whisper** using Whisper.cpp for privacy
- **Object detection** with custom trained models
- **Navigation assistance** with CoreLocation
- **Face recognition** with PhotoKit integration
- **Multi-language support** for global accessibility
- **Cloud sync** for personalized settings

## 📞 Support & Accessibility

This app is specifically designed for blind and visually impaired users. All features prioritize:
- **Clear audio feedback**
- **Logical navigation flow**
- **Consistent interaction patterns**
- **Reliable error handling**
- **Customizable experience**

---

**Built with accessibility-first design principles and modern iOS development best practices.** 