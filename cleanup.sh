#!/bin/bash

# Grimoire Cleanup Script
# Removes old virtual environment and lets you start fresh

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║${NC} ${YELLOW}Grimoire Cleanup Script${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}\n"

echo -e "${YELLOW}This script will remove:${NC}"
echo -e "  • Python virtual environment"
echo -e "  • Backend server PID file"
echo -e "  • Build artifacts"
echo -e "  • Log files"
echo -e ""
echo -e "${YELLOW}It will NOT remove:${NC}"
echo -e "  • Your notes (in backend/storage/notes/)"
echo -e "  • Configuration files"
echo -e "  • Source code"
echo -e ""

read -p "Are you sure you want to continue? [y/N]: " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${BLUE}Cleanup cancelled.${NC}"
    exit 0
fi

echo -e "\n${YELLOW}Starting cleanup...${NC}"

# Remove virtual environment
if [ -d "backend/venv" ]; then
    echo -e "  ${RED}Removing${NC} Python virtual environment..."
    rm -rf backend/venv
    echo -e "  ${GREEN}✓ Virtual environment removed${NC}"
else
    echo -e "  ${BLUE}No virtual environment found${NC}"
fi

# Remove build artifacts
if [ -d "macos-app/Build" ]; then
    echo -e "  ${RED}Removing${NC} build artifacts..."
    rm -rf macos-app/Build
    echo -e "  ${GREEN}✓ Build artifacts removed${NC}"
fi

# Remove Xcode project (optional)
read -p "Remove Xcode project too? [y/N]: " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    if [ -d "macos-app/Grimoire.xcodeproj" ]; then
        echo -e "  ${RED}Removing${NC} Xcode project..."
        rm -rf macos-app/Grimoire.xcodeproj
        echo -e "  ${GREEN}✓ Xcode project removed${NC}"
    fi
    if [ -d "macos-app/Grimoire.app" ]; then
        echo -e "  ${RED}Removing${NC} built app..."
        rm -rf macos-app/Grimoire.app
        echo -e "  ${GREEN}✓ Built app removed${NC}"
    fi
fi

# Clear log files
echo -e "  ${RED}Clearing${NC} log files..."
> grimoire.log 2>/dev/null || true
echo -e "  ${GREEN}✓ Log files cleared${NC}"

# Check for running backend and stop it
if [ -f "backend.pid" ]; then
    BACKEND_PID=$(cat backend.pid 2>/dev/null || true)
    if [ -n "$BACKEND_PID" ] && kill -0 "$BACKEND_PID" 2>/dev/null; then
        echo -e "  ${YELLOW}Stopping${NC} backend server (PID: $BACKEND_PID)..."
        kill "$BACKEND_PID" 2>/dev/null || true
        sleep 1
        kill -9 "$BACKEND_PID" 2>/dev/null || true
        echo -e "  ${GREEN}✓ Backend server stopped${NC}"
    fi
    rm -f backend.pid
    echo -e "  ${GREEN}✓ PID file removed${NC}"
fi

# Fallback to stop any uvicorn/main processes that may not match PID file
if pgrep -f "uvicorn .*main:app" > /dev/null 2>&1 || pgrep -f "python3.*main.py" > /dev/null 2>&1; then
    echo -e "  ${YELLOW}Stopping${NC} running backend server..."
    pkill -f "uvicorn .*main:app" 2>/dev/null || true
    pkill -f "python3.*main.py" 2>/dev/null || true
    echo -e "  ${GREEN}✓ Backend server stopped${NC}"
fi

echo -e "\n${GREEN}══════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}Cleanup complete!${NC}"
echo -e "${GREEN}══════════════════════════════════════════════════════════════${NC}\n"

echo -e "${BLUE}Next steps:${NC}"
echo -e "  1. Run ${YELLOW}./grimoire${NC} to start fresh"
echo -e "  2. Or run ${YELLOW}./grimoire setup${NC} to setup only"
echo -e ""
echo -e "${BLUE}Your notes are safe at:${NC} backend/storage/notes/"
echo -e "${BLUE}Configuration files preserved:${NC}"
echo -e "  • backend/requirements.txt"
echo -e "  • All source code files"
echo -e "  • Sample notes"
echo -e ""
echo -e "${YELLOW}Note:${NC} The first run will re-download dependencies and models."
echo -e "This may take a few minutes."
