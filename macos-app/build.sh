#!/bin/bash

# Grimoire Build Script
# Simple script to build the macOS app

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "🔨 Building Grimoire macOS app..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Check if Xcode is installed
if ! xcode-select -p &> /dev/null; then
    echo -e "${RED}❌ Xcode is not installed. Please install Xcode from the App Store.${NC}"
    exit 1
fi

# Check if project exists
if [ ! -f "Grimoire.xcodeproj/project.pbxproj" ]; then
    echo -e "${YELLOW}⚠ Xcode project not found. Creating project...${NC}"
    ./create_xcode_project.sh
fi

# Clean previous builds (preserve Swift Package checkouts to avoid re-downloading)
echo -e "${BLUE}🧹 Cleaning previous builds...${NC}"
if [ -d "Build/SourcePackages" ]; then
    rm -rf "Build/Build" "Build/Index" "Build/Logs" "Build/Intermediates.noindex" 2>/dev/null || true
else
    rm -rf "Build" 2>/dev/null || true
fi
rm -rf "Grimoire.app" 2>/dev/null || true

# If we already have package checkouts, avoid network package resolution.
PKG_FLAGS=()
if [ -d "Build/SourcePackages/checkouts" ] && [ -n "$(ls -A Build/SourcePackages/checkouts 2>/dev/null)" ]; then
    PKG_FLAGS+=("-disableAutomaticPackageResolution")
elif [ -d "Build/SourcePackages/repositories" ] && [ -n "$(ls -A Build/SourcePackages/repositories 2>/dev/null)" ]; then
    PKG_FLAGS+=("-disableAutomaticPackageResolution")
fi

# Build the project
echo -e "${BLUE}🏗️  Building project...${NC}"
if xcodebuild \
    -project "Grimoire.xcodeproj" \
    -scheme "Grimoire" \
    -configuration "Debug" \
    -derivedDataPath "Build" \
    -destination "platform=macOS" \
    -quiet \
    "${PKG_FLAGS[@]}" \
    build; then

    echo -e "${GREEN}✅ Build successful!${NC}"

    # Find and copy the built app
    APP_PATH=$(find "Build" -name "Grimoire.app" -type d 2>/dev/null | head -1)

    if [ -n "$APP_PATH" ] && [ -d "$APP_PATH" ]; then
        cp -R "$APP_PATH" .
        echo -e "${GREEN}✅ App copied to: $(pwd)/Grimoire.app${NC}"

        # Get app size
        APP_SIZE=$(du -sh "Grimoire.app" | cut -f1)
        echo -e "${BLUE}📦 App size: $APP_SIZE${NC}"

        # Show next steps
        echo -e "\n${GREEN}══════════════════════════════════════════════════════════════${NC}"
        echo -e "${GREEN}🎉 Build complete!${NC}"
        echo -e "${GREEN}══════════════════════════════════════════════════════════════${NC}"
        echo -e "\n${BLUE}Next steps:${NC}"
        echo -e "  1. ${YELLOW}Make sure backend is running:${NC} ../grimoire backend"
        echo -e "  2. ${YELLOW}Launch the app:${NC} open Grimoire.app"
        echo -e "  3. ${YELLOW}Or run full setup:${NC} ../grimoire"
        echo -e ""
        echo -e "${BLUE}Backend URL:${NC} http://127.0.0.1:8000"
        echo -e "${BLUE}API Docs:${NC} http://127.0.0.1:8000/docs"

    else
        echo -e "${YELLOW}⚠ Build succeeded but app not found in Build directory${NC}"
        echo -e "${BLUE}Looking in:${NC} Build/Build/Products/Debug/"
        ls -la "Build/Build/Products/Debug/" 2>/dev/null || echo "Build directory not found"
    fi

else
    echo -e "${RED}❌ Build failed${NC}"
    echo -e "${YELLOW}Try these steps:${NC}"
    echo -e "  1. Open project in Xcode: ${BLUE}open Grimoire.xcodeproj${NC}"
    echo -e "  2. Check for missing files in project navigator"
    echo -e "  3. Build manually with Cmd+R"
    exit 1
fi
