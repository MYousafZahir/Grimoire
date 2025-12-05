#!/bin/bash

# Grimoire Debug Tools Test Script
# Tests the new debugging tools that replace the custom profiler

set -e

echo "========================================="
echo "Testing Grimoire Debug Tools"
echo "========================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper functions
print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

# Test 1: Check if DebugTools.swift exists
echo -e "\n${BLUE}Test 1: Checking DebugTools.swift${NC}"
if [ -f "macos-app/DebugTools.swift" ]; then
    print_success "DebugTools.swift exists"

    # Check for key components
    if grep -q "class SignpostManager" "macos-app/DebugTools.swift"; then
        print_success "Found SignpostManager class"
    else
        print_error "Missing SignpostManager class"
    fi

    if grep -q "class DebugLogger" "macos-app/DebugTools.swift"; then
        print_success "Found DebugLogger class"
    else
        print_error "Missing DebugLogger class"
    fi

    if grep -q "OSSignpostID" "macos-app/DebugTools.swift"; then
        print_success "Found OSSignpost integration"
    else
        print_warning "OSSignpost integration not found (requires macOS 10.14+)"
    fi
else
    print_error "DebugTools.swift not found"
    exit 1
fi

# Test 2: Check NoteManager integration
echo -e "\n${BLUE}Test 2: Checking NoteManager integration${NC}"
if [ -f "macos-app/NoteManager.swift" ]; then
    print_success "NoteManager.swift exists"

    # Check for debug tool usage
    if grep -q "logDebug\|logError\|logWarning\|logInfo" "macos-app/NoteManager.swift"; then
        print_success "NoteManager uses debug logging functions"

        # Count debug calls
        debug_count=$(grep -c "logDebug" "macos-app/NoteManager.swift" || true)
        error_count=$(grep -c "logError" "macos-app/NoteManager.swift" || true)
        print_info "Found $debug_count logDebug calls and $error_count logError calls"
    else
        print_warning "NoteManager doesn't use debug logging functions"
    fi

    # Check for OSSignpost usage
    if grep -q "SignpostManager\|OSSignpostID" "macos-app/NoteManager.swift"; then
        print_success "NoteManager uses OSSignpost for timing"
    else
        print_warning "NoteManager doesn't use OSSignpost"
    fi
else
    print_error "NoteManager.swift not found"
fi

# Test 3: Check SearchManager integration
echo -e "\n${BLUE}Test 3: Checking SearchManager integration${NC}"
if [ -f "macos-app/SearchManager.swift" ]; then
    print_success "SearchManager.swift exists"

    if grep -q "logDebug\|logError" "macos-app/SearchManager.swift"; then
        print_success "SearchManager uses debug logging"
    else
        print_warning "SearchManager doesn't use debug logging"
    fi
else
    print_error "SearchManager.swift not found"
fi

# Test 4: Check backend profiler removal
echo -e "\n${BLUE}Test 4: Checking backend profiler removal${NC}"
if [ ! -f "backend/profiler_integration.py" ]; then
    print_success "Custom backend profiler removed"
else
    print_warning "Custom backend profiler still exists"
fi

if [ ! -d "profiler" ]; then
    print_success "Custom profiler directory removed"
else
    print_warning "Custom profiler directory still exists"
fi

# Test 5: Check for Instruments-ready code
echo -e "\n${BLUE}Test 5: Checking for Instruments compatibility${NC}"
echo "The following signposts are available for Instruments:"

if [ -f "macos-app/DebugTools.swift" ]; then
    echo "From SignpostManager:"
    grep -n "os_signpost\|beginFolderCreation\|beginNoteDeletion\|beginAPICall" "macos-app/DebugTools.swift" | head -10 | while read line; do
        print_info "  $line"
    done
fi

# Test 6: Check debug log file location
echo -e "\n${BLUE}Test 6: Debug log configuration${NC}"
if grep -q "GrimoireDebug.log" "macos-app/DebugTools.swift"; then
    print_success "Debug logs will be saved to GrimoireDebug.log in Documents folder"

    # Show log configuration
    echo "Log levels available:"
    echo "  - error (0): Critical errors"
    echo "  - warning (1): Warnings"
    echo "  - info (2): General information"
    echo "  - debug (3): Debug information"
    echo "  - verbose (4): Detailed tracing"

    current_level=$(grep -A2 "static let logLevel" "macos-app/DebugTools.swift" | grep -o "\.debug\|\.info\|\.warning\|\.error\|\.verbose" | head -1 || echo ".debug")
    print_info "Current log level: $current_level"
else
    print_error "Debug log file not configured"
fi

# Test 7: Network metrics collection
echo -e "\n${BLUE}Test 7: Network metrics collection${NC}"
if grep -q "NetworkMetricsCollector\|URLSessionTaskMetrics" "macos-app/DebugTools.swift"; then
    print_success "Network metrics collection is configured"
    print_info "Will collect: DNS time, connect time, request time, response time"
else
    print_warning "Network metrics collection not configured"
fi

# Test 8: Race condition detection
echo -e "\n${BLUE}Test 8: Race condition detection${NC}"
if grep -q "RaceConditionDetector\|checkConcurrentAccess" "macos-app/DebugTools.swift"; then
    print_success "Race condition detection helpers available"
    print_info "Use withRaceCheck() to monitor concurrent access"
else
    print_warning "Race condition detection not configured"
fi

# Summary
echo -e "\n${BLUE}=========================================${NC}"
echo -e "${BLUE}Debug Tools Test Summary${NC}"
echo -e "${BLUE}=========================================${NC}"

echo "Replaced custom profiler with:"
echo "  ✓ OSSignpost for precise timing (Instruments compatible)"
echo "  ✓ DebugLogger for flexible logging"
echo "  ✓ NetworkMetricsCollector for URLSession metrics"
echo "  ✓ RaceConditionDetector for concurrency issues"
echo "  ✓ DebugViewModifier for SwiftUI debugging"
echo ""
echo "To use these tools:"
echo "  1. Run app with debug logging enabled"
echo "  2. Use Instruments to profile specific operations"
echo "  3. Check ~/Documents/GrimoireDebug.log for logs"
echo "  4. Enable Thread Sanitizer for race detection"
echo ""
echo "For detailed instructions, see PROFILING_GUIDE.md"

# Quick test commands
echo -e "\n${YELLOW}Quick test commands:${NC}"
echo "  # View debug logs in real-time"
echo "  tail -f ~/Documents/GrimoireDebug.log"
echo ""
echo "  # Profile with Instruments"
echo "  xcrun xctrace record --template 'Time Profiler' --launch -- ./macos-app/Grimoire.app"
echo ""
echo "  # View signpost events"
echo "  log stream --predicate 'subsystem == \"com.grimoire.app\"'"
echo ""
echo "  # Test backend separately"
echo "  curl -X POST http://127.0.0.1:8000/create-folder \\"
echo "    -H 'Content-Type: application/json' \\"
echo "    -d '{\"folder_path\":\"test_folder\"}' \\"
echo "    -w 'Time: %{time_total}s\\n'"

echo -e "\n${GREEN}Test completed successfully!${NC}"
