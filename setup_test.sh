#!/bin/bash

# BlindAssistant Setup & Test Script
echo "🚀 Setting up BlindAssistant for testing..."

# Check if we're in the right directory
if [ ! -f "ContentView.swift" ]; then
    echo "❌ Error: ContentView.swift not found. Please run this script from the BlindAssistant project directory."
    exit 1
fi

echo "✅ Found BlindAssistant project files"

# Check required files
required_files=(
    "ContentView.swift"
    "NavigationAssistant.swift"
    "QuickActionsView.swift"
    "SettingsView.swift"
    "CameraManager.swift"
    "AudioManager.swift"
    "SpeechOutput.swift"
    "OfflineWhisperManager.swift"
    "ObjectDetectionManager.swift"
    "GPTManager.swift"
    "WhisperAPI.swift"
    "Config.swift"
    "Info.plist"
    "App.swift"
)

missing_files=()
for file in "${required_files[@]}"; do
    if [ ! -f "$file" ]; then
        missing_files+=("$file")
    fi
done

if [ ${#missing_files[@]} -eq 0 ]; then
    echo "✅ All required files found!"
else
    echo "❌ Missing files:"
    for file in "${missing_files[@]}"; do
        echo "   - $file"
    done
    echo "Please add the missing files before testing."
    exit 1
fi

# Check if Xcode is available
if ! command -v xcodebuild &> /dev/null; then
    echo "❌ Xcode not found. Please install Xcode to test the app."
    exit 1
fi

echo "✅ Xcode found"

# Check API key configuration
if grep -q "your-openai-api-key-here" Config.swift; then
    echo "⚠️  Warning: OpenAI API key not configured in Config.swift"
    echo "   Some features will not work without a valid API key."
    echo "   You can still test offline features and UI."
fi

# Create test project structure info
echo ""
echo "📋 Testing Instructions:"
echo "1. Open Xcode"
echo "2. Create new iOS project:"
echo "   - File → New → Project → iOS → App"
echo "   - Name: BlindAssistant"
echo "   - Language: Swift"
echo "   - Interface: SwiftUI"
echo "   - Minimum iOS: 15.0+"
echo ""
echo "3. Add all .swift files to your Xcode project"
echo "4. Replace the default Info.plist with the one provided"
echo "5. Add your OpenAI API key to Config.swift"
echo "6. Build and run on a physical device (recommended)"
echo ""
echo "📱 Testing Priority:"
echo "1. Test on physical iPhone/iPad (camera, GPS, microphone)"
echo "2. Grant all permissions when prompted"
echo "3. Start with offline mode for initial testing"
echo "4. Test basic features before advanced navigation"
echo ""
echo "🔧 Quick Test Commands:"
echo "- 'What do you see?' (basic scene description)"
echo "- 'Take me home' (after setting home address)"
echo "- 'Emergency help' (emergency features)"
echo "- Tap Quick Actions for instant commands"
echo ""
echo "📖 See README_TESTING.md for detailed testing guide"
echo ""
echo "🎉 Setup complete! Ready for testing." 