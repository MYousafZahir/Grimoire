#!/bin/bash

# Simple build script for Grimoire

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "Building Grimoire..."

# Ensure Xcode/SwiftPM caches are writable in sandboxed environments.
LOCAL_HOME="${SCRIPT_DIR}/.home"
mkdir -p "${LOCAL_HOME}/Library/Caches" "${LOCAL_HOME}/Library/Logs" "${LOCAL_HOME}/.cache/clang/ModuleCache"
export HOME="${LOCAL_HOME}"
export CFFIXED_USER_HOME="${LOCAL_HOME}"
export XDG_CACHE_HOME="${LOCAL_HOME}/.cache"
export TMPDIR="${SCRIPT_DIR}/.tmp"
mkdir -p "${TMPDIR}"

CACHE_ROOT="${SCRIPT_DIR}/.cache/xcode"
mkdir -p "${CACHE_ROOT}/clang-module-cache" "${CACHE_ROOT}/swift-module-cache"

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
    CLANG_MODULE_CACHE_PATH="${CACHE_ROOT}/clang-module-cache" \
    SWIFT_MODULE_CACHE_PATH="${CACHE_ROOT}/swift-module-cache" \
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
    echo "If you see 'Operation not permitted' for ~/.cache or ~/Library/Caches, your environment is sandboxed and Xcode can't write its caches."
    exit 1
fi
