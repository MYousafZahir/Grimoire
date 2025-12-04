#!/bin/bash

# Grimoire Fixes Test Script
# Tests all the fixes implemented for the macOS app

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}   Grimoire Fixes Test Suite${NC}"
echo -e "${CYAN}========================================${NC}"

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR"
BACKEND_URL="http://127.0.0.1:8000"
LOG_FILE="$PROJECT_ROOT/test_fixes.log"

# Initialize counters
total_tests=0
passed_tests=0
failed_tests=0

# Function to run a test
run_test() {
    local test_name="$1"
    local test_command="$2"
    local description="$3"

    echo -e "\n${BLUE}Test ${total_tests}:${NC} $test_name"
    echo -e "${YELLOW}Description:${NC} $description"
    echo -e "${BLUE}Command:${NC} $test_command"

    if eval "$test_command" 2>> "$LOG_FILE"; then
        echo -e "${GREEN}✓ Test passed${NC}"
        ((passed_tests++))
    else
        echo -e "${RED}✗ Test failed${NC}"
        ((failed_tests++))
    fi

    ((total_tests++))
}

# Clear log file
> "$LOG_FILE"

echo -e "${BLUE}Starting tests at: $(date)${NC}"
echo -e "${BLUE}Log file: $LOG_FILE${NC}"

# ============================================================================
# SECTION 1: BACKEND TESTS
# ============================================================================
echo -e "\n${CYAN}=== SECTION 1: Backend Tests ===${NC}"

# Test 1: Backend health check
run_test "Backend Health" \
    "curl -s --max-time 5 $BACKEND_URL | grep -q 'status'" \
    "Backend server should be running and responding"

# Test 2: API documentation endpoint
run_test "API Documentation" \
    "curl -s --max-time 5 $BACKEND_URL/docs | grep -q 'Swagger UI'" \
    "API documentation should be available"

# Test 3: Create note via API
run_test "Create Note via API" \
    "curl -s -X POST $BACKEND_URL/update-note \
        -H 'Content-Type: application/json' \
        -d '{\"note_id\":\"fix-test-note\",\"content\":\"# Fix Test Note\\n\\nTesting app fixes.\"}' \
        | grep -q 'success'" \
    "Should be able to create a note via API"

# Test 4: Get note content
run_test "Get Note Content" \
    "curl -s $BACKEND_URL/note/fix-test-note | grep -q 'Fix Test Note'" \
    "Should be able to retrieve note content"

# Test 5: List all notes
run_test "List All Notes" \
    "curl -s $BACKEND_URL/all-notes | grep -q 'notes'" \
    "Should be able to list all notes"

# Test 6: Check .grim file creation
run_test ".grim File Creation" \
    "[ -f '$PROJECT_ROOT/backend/storage/notes/fix-test-note.grim' ]" \
    ".grim file should be created for new notes"

# ============================================================================
# SECTION 2: APP BUILD TESTS
# ============================================================================
echo -e "\n${CYAN}=== SECTION 2: App Build Tests ===${NC}"

# Test 7: Check build script exists
run_test "Build Script Exists" \
    "[ -f '$PROJECT_ROOT/macos-app/build.sh' ]" \
    "Build script should exist"

# Test 8: Check build script is executable
run_test "Build Script Executable" \
    "[ -x '$PROJECT_ROOT/macos-app/build.sh' ]" \
    "Build script should be executable"

# Test 9: Check Xcode project exists
run_test "Xcode Project Exists" \
    "[ -d '$PROJECT_ROOT/macos-app/Grimoire.xcodeproj' ]" \
    "Xcode project should exist"

# Test 10: Check app resources
run_test "App Resources Exist" \
    "[ -f '$PROJECT_ROOT/macos-app/Resources/Info.plist' ]" \
    "App resources should exist"

# Test 11: Swift syntax check (key files)
run_test "Swift Syntax Check" \
    "cd '$PROJECT_ROOT/macos-app' && swiftc -parse GrimoireApp.swift ContentView.swift NoteManager.swift EditorView.swift 2>/dev/null" \
    "Key Swift files should have valid syntax"

# ============================================================================
# SECTION 3: FIXES VALIDATION TESTS
# ============================================================================
echo -e "\n${CYAN}=== SECTION 3: Fixes Validation Tests ===${NC}"

# Test 12: Check for duplicate '+' button fix
run_test "Duplicate '+' Button Fix" \
    "! grep -q 'ToolbarItem.*plus.*noteManager.createNewNote' '$PROJECT_ROOT/macos-app/ContentView.swift'" \
    "ContentView should not have duplicate '+' button (should only be in SidebarView)"

# Test 13: Check note creation notification system
run_test "Note Creation Notifications" \
    "grep -q 'NotificationCenter.default.post.*NoteCreated' '$PROJECT_ROOT/macos-app/NoteManager.swift'" \
    "NoteManager should post notifications for note creation"

# Test 14: Check backend connection handling
run_test "Backend Connection Handling" \
    "grep -q 'checkBackendConnection' '$PROJECT_ROOT/macos-app/NoteManager.swift'" \
    "NoteManager should have backend connection checking"

# Test 15: Check save status improvements
run_test "Save Status Improvements" \
    "grep -q 'enum SaveStatus' '$PROJECT_ROOT/macos-app/EditorView.swift'" \
    "EditorView should have improved save status tracking"

# Test 16: Check backend status indicator
run_test "Backend Status Indicator" \
    "grep -q 'BackendStatusIndicator' '$PROJECT_ROOT/macos-app/ContentView.swift'" \
    "ContentView should have backend status indicator"

# Test 17: Check empty state handling
run_test "Empty State Handling" \
    "grep -q 'No Notes Yet' '$PROJECT_ROOT/macos-app/SidebarView.swift'" \
    "SidebarView should have empty state message"

# Test 18: Check error handling improvements
run_test "Error Handling Improvements" \
    "grep -q 'lastError.*Published' '$PROJECT_ROOT/macos-app/NoteManager.swift'" \
    "NoteManager should have published error state"

# ============================================================================
# SECTION 4: INTEGRATION TESTS
# ============================================================================
echo -e "\n${CYAN}=== SECTION 4: Integration Tests ===${NC}"

# Test 19: Test the grimoire launcher script
run_test "Grimoire Launcher Script" \
    "[ -x '$PROJECT_ROOT/grimoire' ]" \
    "Main grimoire launcher should be executable"

# Test 20: Test backend startup script
run_test "Backend Startup Script" \
    "[ -f '$PROJECT_ROOT/start_backend.sh' ]" \
    "Backend startup script should exist"

# Test 21: Test app can be built
run_test "App Build Test" \
    "cd '$PROJECT_ROOT/macos-app' && ./build.sh 2>&1 | tail -5 | grep -q 'Build complete'" \
    "App should build successfully"

# Test 22: Check for existing Grimoire.app
run_test "Grimoire.app Exists" \
    "[ -d '$PROJECT_ROOT/macos-app/Grimoire.app' ]" \
    "Grimoire.app should exist after build"

# ============================================================================
# SECTION 5: CLEANUP AND FINAL CHECKS
# ============================================================================
echo -e "\n${CYAN}=== SECTION 5: Cleanup and Final Checks ===${NC}"

# Test 23: Clean up test note
run_test "Cleanup Test Note" \
    "rm -f '$PROJECT_ROOT/backend/storage/notes/fix-test-note.grim' 2>/dev/null && \
     [ ! -f '$PROJECT_ROOT/backend/storage/notes/fix-test-note.grim' ]" \
    "Should be able to clean up test files"

# Test 24: Check no compilation errors in key files
run_test "No Swift Compilation Errors" \
    "cd '$PROJECT_ROOT/macos-app' && \
     ! swiftc -parse GrimoireApp.swift ContentView.swift SidebarView.swift EditorView.swift BacklinksView.swift SettingsView.swift NoteManager.swift SearchManager.swift 2>&1 | grep -q 'error:'" \
    "All Swift files should compile without errors"

# Test 25: Verify all required files exist
run_test "Required Files Check" \
    "[ -f '$PROJECT_ROOT/macos-app/GrimoireApp.swift' ] && \
     [ -f '$PROJECT_ROOT/macos-app/ContentView.swift' ] && \
     [ -f '$PROJECT_ROOT/macos-app/SidebarView.swift' ] && \
     [ -f '$PROJECT_ROOT/macos-app/EditorView.swift' ] && \
     [ -f '$PROJECT_ROOT/macos-app/NoteManager.swift' ] && \
     [ -f '$PROJECT_ROOT/macos-app/SearchManager.swift' ]" \
    "All required app files should exist"

# ============================================================================
# SUMMARY
# ============================================================================
echo -e "\n${CYAN}========================================${NC}"
echo -e "${CYAN}           Test Summary${NC}"
echo -e "${CYAN}========================================${NC}"

echo -e "\n${BLUE}Test Sections:${NC}"
echo -e "  ${GREEN}✓ Backend Tests${NC} (6 tests)"
echo -e "  ${GREEN}✓ App Build Tests${NC} (5 tests)"
echo -e "  ${GREEN}✓ Fixes Validation Tests${NC} (7 tests)"
echo -e "  ${GREEN}✓ Integration Tests${NC} (4 tests)"
echo -e "  ${GREEN}✓ Cleanup and Final Checks${NC} (3 tests)"

echo -e "\n${BLUE}Total Tests Run:${NC} $total_tests"
echo -e "${GREEN}Passed:${NC} $passed_tests"
echo -e "${RED}Failed:${NC} $failed_tests"

if [ $failed_tests -eq 0 ]; then
    echo -e "\n${GREEN}========================================${NC}"
    echo -e "${GREEN}      ALL FIXES VERIFIED! 🎉${NC}"
    echo -e "${GREEN}========================================${NC}"

    echo -e "\n${BLUE}Summary of Verified Fixes:${NC}"
    echo -e "  ${GREEN}✅ Duplicate '+' button removed${NC}"
    echo -e "  ${GREEN}✅ Note creation with notifications${NC}"
    echo -e "  ${GREEN}✅ Backend connection handling${NC}"
    echo -e "  ${GREEN}✅ Improved save status tracking${NC}"
    echo -e "  ${GREEN}✅ Backend status indicator${NC}"
    echo -e "  ${GREEN}✅ Empty state handling${NC}"
    echo -e "  ${GREEN}✅ Error handling improvements${NC}"
    echo -e "  ${GREEN}✅ App builds successfully${NC}"
    echo -e "  ${GREEN}✅ Backend API working${NC}"
    echo -e "  ${GREEN}✅ .grim file extension working${NC}"

    echo -e "\n${BLUE}Next Steps:${NC}"
    echo -e "1. ${YELLOW}Run the full Grimoire system:${NC} ./grimoire"
    echo -e "2. ${YELLOW}Test the app manually:${NC}"
    echo -e "   - Click '+' button to create notes"
    echo -e "   - Type in editor - should auto-save"
    echo -e "   - Check backend status indicator"
    echo -e "   - Test with backend offline"
    echo -e "3. ${YELLOW}Check backend:${NC} $BACKEND_URL/docs"
    echo -e "4. ${YELLOW}View logs:${NC} $LOG_FILE"

    exit 0
else
    echo -e "\n${RED}========================================${NC}"
    echo -e "${RED}      $failed_tests TEST(S) FAILED 😞${NC}"
    echo -e "${RED}========================================${NC}"

    echo -e "\n${YELLOW}Troubleshooting Tips:${NC}"
    echo -e "1. ${BLUE}Check backend is running:${NC} curl $BACKEND_URL"
    echo -e "2. ${BLUE}Start backend if needed:${NC} ./start_backend.sh"
    echo -e "3. ${BLUE}Build app manually:${NC} cd macos-app && ./build.sh"
    echo -e "4. ${BLUE}Check Swift syntax:${NC} cd macos-app && swiftc -parse *.swift"
    echo -e "5. ${BLUE}View detailed logs:${NC} cat $LOG_FILE"

    exit 1
fi
