#!/bin/bash

echo "🔧 KaiSight Compilation Error Fix Script"
echo "========================================"

# Navigate to project directory
cd /Users/v3ctor/Documents/kaisight

echo "📊 Analyzing project structure..."

# Check for duplicate Info.plist files
echo "🔍 Checking for duplicate Info.plist files..."
find . -name "Info.plist" -type f
echo ""

# Check if Xcode project exists
if [ -f "kaiSight.xcodeproj/project.pbxproj" ]; then
    echo "✅ Xcode project found"
else
    echo "❌ Xcode project not found"
    echo "📝 You need to create the Xcode project as instructed earlier"
fi

# Check Swift file syntax quickly
echo "🔍 Quick syntax check for critical Swift files..."

# Check Config.swift
if grep -q "your-openai-api-key-here" Config.swift; then
    echo "⚠️  Config.swift: API key placeholder found - replace with real key"
else
    echo "✅ Config.swift: API key configured"
fi

# Verify key Swift files exist and have basic structure
echo "📋 Verifying core Swift files..."

CORE_FILES=(
    "AgentLoopManager.swift"
    "Config.swift"
    "KaiSightApp.swift" 
    "ContentView.swift"
    "CameraManager.swift"
    "GPTManager.swift"
    "WhisperAPI.swift"
)

for file in "${CORE_FILES[@]}"; do
    if [ -f "$file" ]; then
        echo "✅ $file exists"
        # Quick check for basic Swift syntax
        if grep -q "import Foundation\|import SwiftUI\|import UIKit" "$file"; then
            echo "   └─ Has proper imports"
        else
            echo "   ⚠️  Missing standard imports"
        fi
    else
        echo "❌ $file missing"
    fi
done

echo ""
echo "🏗️  Project Structure Summary:"
echo "==============================="
echo "Swift files: $(ls *.swift | wc -l)"
echo "Documentation: $(ls docs/ 2>/dev/null | wc -l) files"
echo "Scripts: $(ls scripts/ 2>/dev/null | wc -l) files"

echo ""
echo "📝 Next Steps to Fix Compilation:"
echo "=================================="
echo "1. Open Xcode and create new project (as shown in previous instructions)"
echo "2. Import all Swift files into the project"
echo "3. Add your OpenAI API key to Config.swift"
echo "4. Build and test"

echo ""
echo "✅ Compilation error analysis complete!" 