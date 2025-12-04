#!/bin/bash

# Grimoire macOS App Simple Test Script
# Tests basic app functionality and backend integration

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}   Grimoire macOS App Simple Test${NC}"
echo -e "${BLUE}========================================${NC}"

# Check if we're in the right directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR"

if [ ! -d "$PROJECT_ROOT/macos-app" ]; then
    echo -e "${RED}Error: macOS app directory not found${NC}"
    echo -e "${YELLOW}Please run this script from the Grimoire project root${NC}"
    exit 1
fi

cd "$PROJECT_ROOT"

# Initialize test results
total_tests=0
passed_tests=0
failed_tests=0

# Function to run a test
run_test() {
    local test_name="$1"
    local test_command="$2"

    echo -e "\n${BLUE}Test:${NC} $test_name"
    echo -e "${BLUE}Command:${NC} $test_command"

    if eval "$test_command"; then
        echo -e "${GREEN}✓ Test passed${NC}"
        ((passed_tests++))
    else
        echo -e "${RED}✗ Test failed${NC}"
        ((failed_tests++))
    fi

    ((total_tests++))
}

# Test 1: Check if backend is running
run_test "Backend Health Check" \
    "curl -s --max-time 5 http://127.0.0.1:8000 | grep -q 'status'"

# Test 2: Create a test note via API
run_test "Create Note via API" \
    "curl -s -X POST http://127.0.0.1:8000/update-note \
        -H 'Content-Type: application/json' \
        -d '{\"note_id\":\"app-test-note\",\"content\":\"# App Test Note\\n\\nCreated for app testing.\"}' \
        | grep -q 'success'"

# Test 3: Get all notes via API
run_test "Get All Notes via API" \
    "curl -s http://127.0.0.1:8000/all-notes | grep -q 'notes'"

# Test 4: Get specific note content
run_test "Get Note Content via API" \
    "curl -s http://127.0.0.1:8000/note/app-test-note | grep -q 'App Test Note'"

# Test 5: Check Swift syntax
run_test "Swift Syntax Check" \
    "cd macos-app && swiftc -parse GrimoireApp.swift ContentView.swift 2>/dev/null"

# Test 6: Check if .grim files are created
run_test ".grim File Creation" \
    "[ -f 'backend/storage/notes/app-test-note.grim' ]"

# Test 7: Verify .grim file content
run_test ".grim File Content" \
    "grep -q 'App Test Note' 'backend/storage/notes/app-test-note.grim'"

# Test 8: Check build scripts exist and are executable
run_test "Build Scripts Check" \
    "[ -x 'macos-app/build.sh' ] && [ -x 'macos-app/build_app.sh' ]"

# Test 9: Check Xcode project exists
run_test "Xcode Project Check" \
    "[ -d 'macos-app/Grimoire.xcodeproj' ]"

# Test 10: Check app resources exist
run_test "App Resources Check" \
    "[ -f 'macos-app/Resources/Info.plist' ]"

# Clean up test note
echo -e "\n${BLUE}Cleaning up test files...${NC}"
rm -f "backend/storage/notes/app-test-note.grim" 2>/dev/null || true

# Summary
echo -e "\n${BLUE}========================================${NC}"
echo -e "${BLUE}           Test Summary${NC}"
echo -e "${BLUE}========================================${NC}"

echo -e "\n${BLUE}Total Tests:${NC} $total_tests"
echo -e "${GREEN}Passed:${NC} $passed_tests"
echo -e "${RED}Failed:${NC} $failed_tests"

if [ $failed_tests -eq 0 ]; then
    echo -e "\n${GREEN}========================================${NC}"
    echo -e "${GREEN}      All App Tests Passed! 🎉${NC}"
    echo -e "${GREEN}========================================${NC}"

    echo -e "\n${BLUE}Next Steps:${NC}"
    echo -e "1. ${YELLOW}Build the app:${NC} cd macos-app && ./build.sh"
    echo -e "2. ${YELLOW}Run the app:${NC} open macos-app/Grimoire.app"
    echo -e "3. ${YELLOW}Test manually:${NC}"
    echo -e "   - Click the '+' button to create notes"
    echo -e "   - Type in the editor - should auto-save"
    echo -e "   - Check backend status indicator (top-right)"

    echo -e "\n${BLUE}Backend is running at:${NC} http://127.0.0.1:8000"
    echo -e "${BLUE}API Documentation:${NC} http://127.0.0.1:8000/docs"

    exit 0
else
    echo -e "\n${RED}========================================${NC}"
    echo -e "${RED}      $failed_tests Test(s) Failed 😞${NC}"
    echo -e "${RED}========================================${NC}"

    echo -e "\n${YELLOW}Troubleshooting Tips:${NC}"
    echo -e "1. ${BLUE}Start the backend:${NC} ./start_backend.sh"
    echo -e "2. ${BLUE}Check backend status:${NC} curl http://127.0.0.1:8000"
    echo -e "3. ${BLUE}Install dependencies:${NC} cd backend && pip install -r requirements.txt"
    echo -e "4. ${BLUE}Check Swift installation:${NC} swift --version"

    exit 1
fi
