#!/bin/bash

# Simple build script for Grimoire

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "Building Grimoire..."

# Clean
if [ -d "Build/SourcePackages" ]; then
    rm -rf "Build/Build" "Build/Index" "Build/Logs" "Build/Intermediates.noindex" 2>/dev/null || true
else
    rm -rf "Build" 2>/dev/null || true
fi
rm -rf "Grimoire.app" 2>/dev/null || true

PKG_FLAGS=()
if [ -d "Build/SourcePackages/checkouts" ] && [ -n "$(ls -A Build/SourcePackages/checkouts 2>/dev/null)" ]; then
    PKG_FLAGS+=("-disableAutomaticPackageResolution")
elif [ -d "Build/SourcePackages/repositories" ] && [ -n "$(ls -A Build/SourcePackages/repositories 2>/dev/null)" ]; then
    PKG_FLAGS+=("-disableAutomaticPackageResolution")
fi

# Build
xcodebuild \
    -project Grimoire.xcodeproj \
    -scheme Grimoire \
    -configuration Debug \
    -derivedDataPath Build \
    -destination "platform=macOS" \
    -quiet \
    "${PKG_FLAGS[@]}" \
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
