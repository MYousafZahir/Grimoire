#!/bin/bash

# Grimoire Build Script
# Builds the macOS app from command line

set -e

echo "🔨 Building Grimoire..."

# Clean up old builds
rm -rf "Build"
rm -rf "Grimoire.app"

# Build the project
xcodebuild \
    -project "Grimoire.xcodeproj" \
    -scheme "Grimoire" \
    -configuration "Debug" \
    -derivedDataPath "Build" \
    -destination "platform=macOS" \
    build

# Check if build succeeded
if [ $? -eq 0 ]; then
    # Copy the built app
    if [ -d "Build/Build/Products/Debug/Grimoire.app" ]; then
        cp -R "Build/Build/Products/Debug/Grimoire.app" .
        echo "✅ Build successful! Grimoire.app created."
        echo "🚀 To run: open Grimoire.app"
    else
        echo "❌ Build succeeded but app not found at expected location"
        echo "📁 Check: Build/Build/Products/Debug/"
    fi
else
    echo "❌ Build failed"
    exit 1
fi
