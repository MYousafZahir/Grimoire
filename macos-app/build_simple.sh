#!/bin/bash

# Simple build script for Grimoire

set -e

echo "Building Grimoire..."

# Clean
rm -rf Build Grimoire.app 2>/dev/null || true

# Build
xcodebuild \
    -project Grimoire.xcodeproj \
    -scheme Grimoire \
    -configuration Debug \
    -derivedDataPath Build \
    -destination "platform=macOS" \
    -quiet \
    build

# Check result
if [ $? -eq 0 ]; then
    # Find the built app
    if [ -d "Build/Build/Products/Debug/Grimoire.app" ]; then
        cp -R "Build/Build/Products/Debug/Grimoire.app" .
        echo "✅ Build successful! Grimoire.app created."
        echo "🚀 Run: open Grimoire.app"
    else
        echo "❌ Build succeeded but app not found"
        exit 1
    fi
else
    echo "❌ Build failed"
    exit 1
fi
