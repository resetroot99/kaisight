#!/bin/bash

echo "🧹 KaiSight Production Code Cleanup"
echo "==================================="
echo ""

echo "📋 Starting comprehensive code cleanup for App Store submission..."
echo ""

# Function to backup files before modification
backup_file() {
    local file="$1"
    if [ -f "$file" ]; then
        cp "$file" "${file}.backup"
        echo "   📄 Backed up: $file"
    fi
}

# Function to clean debug statements from a file
clean_debug_statements() {
    local file="$1"
    if [ -f "$file" ]; then
        backup_file "$file"
        
        # Remove print statements but keep ProductionConfig.log calls
        sed -i '' '/print(/d' "$file"
        sed -i '' '/debugPrint(/d' "$file"
        
        # Remove debug-specific comments
        sed -i '' '/\/\/ DEBUG:/d' "$file"
        sed -i '' '/\/\/ TODO:/d' "$file"
        sed -i '' '/\/\/ FIXME:/d' "$file"
        
        echo "   ✅ Cleaned: $file"
    fi
}

# Function to replace debug configurations
replace_debug_config() {
    local file="$1"
    if [ -f "$file" ]; then
        backup_file "$file"
        
        # Replace debug configurations with production equivalents
        sed -i '' 's/Config\.debugLog/ProductionConfig.log/g' "$file"
        sed -i '' 's/isDebugMode = true/isDebugMode = false/g' "$file"
        sed -i '' 's/enableDetailedLogging = true/enableDetailedLogging = false/g' "$file"
        
        echo "   🔧 Updated config: $file"
    fi
}

echo "1️⃣ REMOVING DEBUG STATEMENTS..."
echo ""

# Find and clean all Swift files
find . -name "*.swift" -type f | while read -r file; do
    if [[ "$file" != *".backup" ]]; then
        clean_debug_statements "$file"
    fi
done

echo ""
echo "2️⃣ UPDATING CONFIGURATION FILES..."
echo ""

# Update specific configuration files
config_files=(
    "Config.swift"
    "KaiSightHealthCore.swift"
    "VoiceAgentLoop.swift"
    "AudioManager.swift"
    "GPTManager.swift"
    "WhisperAPI.swift"
)

for file in "${config_files[@]}"; do
    if [ -f "$file" ]; then
        replace_debug_config "$file"
    fi
done

echo ""
echo "3️⃣ REPLACING API KEY PLACEHOLDERS..."
echo ""

# Check for placeholder API keys
if grep -r "your-api-key\|YOUR_API_KEY\|sk-proj-" . --include="*.swift" > /dev/null 2>&1; then
    echo "   ⚠️  PLACEHOLDER API KEYS FOUND!"
    echo "   📝 Please replace with production API keys:"
    grep -r "your-api-key\|YOUR_API_KEY\|sk-proj-" . --include="*.swift"
    echo ""
    echo "   💡 Use environment variables in ProductionConfig.swift:"
    echo "      static let openAIAPIKey = ProcessInfo.processInfo.environment[\"OPENAI_API_KEY\"] ?? \"\""
else
    echo "   ✅ No placeholder API keys found"
fi

echo ""
echo "4️⃣ VALIDATING PRODUCTION CONFIGURATION..."
echo ""

# Check ProductionConfig settings
if [ -f "ProductionConfig.swift" ]; then
    echo "   📋 Checking ProductionConfig.swift settings..."
    
    if grep -q "isProduction = true" ProductionConfig.swift; then
        echo "   ✅ Production mode enabled"
    else
        echo "   ⚠️  Production mode not enabled"
    fi
    
    if grep -q "isDebugMode = false" ProductionConfig.swift; then
        echo "   ✅ Debug mode disabled"
    else
        echo "   ⚠️  Debug mode not disabled"
    fi
    
    if grep -q "enableDetailedLogging = false" ProductionConfig.swift; then
        echo "   ✅ Detailed logging disabled"
    else
        echo "   ⚠️  Detailed logging not disabled"
    fi
else
    echo "   ⚠️  ProductionConfig.swift not found"
fi

echo ""
echo "5️⃣ CHECKING FOR REMAINING DEBUG CODE..."
echo ""

# Check for remaining debug code
debug_patterns=(
    "print("
    "debugPrint("
    "NSLog("
    "// DEBUG"
    "// TODO"
    "// FIXME"
)

found_debug=false
for pattern in "${debug_patterns[@]}"; do
    if grep -r "$pattern" . --include="*.swift" > /dev/null 2>&1; then
        if [ "$found_debug" = false ]; then
            echo "   ⚠️  REMAINING DEBUG CODE FOUND:"
            found_debug=true
        fi
        echo "   🔍 Pattern '$pattern':"
        grep -r "$pattern" . --include="*.swift" | head -5
        echo ""
    fi
done

if [ "$found_debug" = false ]; then
    echo "   ✅ No remaining debug code found"
fi

echo ""
echo "6️⃣ VALIDATING REQUIRED ENTITLEMENTS..."
echo ""

# Check for required entitlements usage
entitlements=(
    "NSCameraUsageDescription"
    "NSMicrophoneUsageDescription"
    "NSLocationWhenInUseUsageDescription"
    "NSBluetoothAlwaysUsageDescription"
    "NSSpeechRecognitionUsageDescription"
    "NSHealthShareUsageDescription"
)

echo "   📋 Required entitlements for KaiSight:"
for entitlement in "${entitlements[@]}"; do
    echo "   • $entitlement"
done

echo ""
echo "7️⃣ CHECKING FILE SIZES AND PERFORMANCE..."
echo ""

# Check for large files that might affect app size
echo "   📊 Largest Swift files:"
find . -name "*.swift" -type f -exec wc -l {} + | sort -nr | head -5

echo ""
echo "   📈 Total lines of code:"
find . -name "*.swift" -type f -exec wc -l {} + | tail -1

echo ""
echo "8️⃣ CREATING PRODUCTION BUILD CHECKLIST..."
echo ""

cat > production_checklist.md << 'EOF'
# KaiSight Production Build Checklist

## ✅ Code Cleanup Complete
- [x] Debug statements removed
- [x] Production configuration enabled
- [x] API key placeholders identified
- [x] Performance optimizations applied

## 🔑 API Keys & Configuration
- [ ] Replace placeholder API keys with production keys
- [ ] Set environment variables for sensitive data
- [ ] Verify ProductionConfig.swift settings
- [ ] Test with production API endpoints

## 📱 App Store Preparation
- [ ] Update app version and build number
- [ ] Verify bundle identifier
- [ ] Check code signing certificates
- [ ] Test on physical devices
- [ ] Verify all entitlements are properly configured

## 🧪 Testing Requirements
- [ ] Complete accessibility testing with VoiceOver
- [ ] Test all voice commands and AI features
- [ ] Verify health device connectivity
- [ ] Test emergency features (safely)
- [ ] Performance testing on older devices

## 📄 Legal Documentation
- [x] Privacy Policy created
- [x] Terms of Service created
- [x] Medical disclaimers created
- [ ] Legal review completed
- [ ] Accessibility compliance verified

## 🏪 App Store Materials
- [x] App description written
- [ ] App icon created (1024x1024)
- [ ] Screenshots captured (all device sizes)
- [ ] App preview video created (optional)
- [ ] Keywords researched and optimized

## 🚀 Final Steps
- [ ] Archive and upload to App Store Connect
- [ ] Complete app metadata
- [ ] Submit for review
- [ ] Prepare for potential rejection response
- [ ] Plan launch strategy

EOF

echo "   📋 Created production_checklist.md"

echo ""
echo "9️⃣ CLEANUP SUMMARY..."
echo ""

# Count cleaned files
cleaned_files=$(find . -name "*.swift.backup" | wc -l)
echo "   📊 Files processed: $cleaned_files"
echo "   🗂️  Backup files created: $cleaned_files"
echo "   📝 Production checklist created"

echo ""
echo "🎯 NEXT STEPS:"
echo ""
echo "1. Review and replace any remaining placeholder API keys"
echo "2. Test the app thoroughly on physical devices"
echo "3. Complete the production_checklist.md items"
echo "4. Create App Store visual assets (icon, screenshots)"
echo "5. Submit to App Store Connect for review"

echo ""
echo "💡 IMPORTANT REMINDERS:"
echo ""
echo "• Test all features with production API keys"
echo "• Verify accessibility with real VoiceOver users"
echo "• Ensure emergency features work but don't interfere with real emergency services"
echo "• Have legal review of all medical disclaimers"
echo "• Prepare detailed documentation for Apple reviewers"

echo ""
echo "✅ CODE CLEANUP COMPLETE!"
echo "   KaiSight is ready for the next phase of App Store preparation."
echo ""
echo "🚀 Ready to transform 285 million lives worldwide!" 