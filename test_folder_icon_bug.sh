#!/bin/bash

# Grimoire Folder Icon Bug Investigation Script
# Uses the new profiling tools to diagnose why new folders show wrong icons

set -e

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

print_header() {
    echo -e "\n${BLUE}=========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}=========================================${NC}"
}

# Check prerequisites
check_prerequisites() {
    print_header "Checking Prerequisites"

    # Check if backend is running
    if curl -s http://127.0.0.1:8000/ > /dev/null; then
        print_success "Backend is running"
    else
        print_warning "Backend is not running"
        print_info "Starting backend..."
        cd backend && python -m uvicorn main:app --host 127.0.0.1 --port 8000 > backend.log 2>&1 &
        BACKEND_PID=$!
        sleep 3

        if curl -s http://127.0.0.1:8000/ > /dev/null; then
            print_success "Backend started successfully (PID: $BACKEND_PID)"
        else
            print_error "Failed to start backend"
            exit 1
        fi
    fi

    # Check if debug tools are available
    if [ -f "macos-app/DebugTools.swift" ]; then
        print_success "DebugTools.swift found"
    else
        print_error "DebugTools.swift not found"
        exit 1
    fi

    # Check if app is built
    if [ -d "macos-app/Grimoire.app" ]; then
        print_success "Grimoire.app found"
    else
        print_warning "Grimoire.app not found"
        print_info "You may need to build the app first: cd macos-app && ./build_simple.sh"
    fi
}

# Test 1: Backend API response for folder creation
test_backend_folder_creation() {
    print_header "Test 1: Backend Folder Creation API"

    local test_folder="test_folder_$(date +%s)"

    print_info "Creating test folder: $test_folder"

    # Time the API call
    start_time=$(date +%s%N)

    response=$(curl -s -X POST http://127.0.0.1:8000/create-folder \
        -H "Content-Type: application/json" \
        -d "{\"folder_path\":\"$test_folder\"}" \
        -w "\nTime: %{time_total}s")

    end_time=$(date +%s%N)
    duration=$(( (end_time - start_time) / 1000000 ))  # Convert to ms

    echo "Response: $response"
    echo "API call took: ${duration}ms"

    # Parse response
    if echo "$response" | grep -q '"success":true'; then
        print_success "Backend folder creation successful"

        # Extract folder_id
        folder_id=$(echo "$response" | grep -o '"folder_id":"[^"]*"' | cut -d'"' -f4)
        print_info "Created folder ID: $folder_id"

        # Test getting notes to see if folder appears
        print_info "\nChecking notes endpoint for new folder..."
        notes_response=$(curl -s http://127.0.0.1:8000/notes)
        echo "Notes response (first 500 chars):"
        echo "$notes_response" | head -c 500
        echo "..."

        # Check if folder is in response
        if echo "$notes_response" | grep -q "$folder_id"; then
            print_success "Folder found in notes endpoint"

            # Check if type field is present
            if echo "$notes_response" | grep -q "\"type\":\"folder\""; then
                print_success "Folder has correct type field"
            else
                print_warning "Folder may not have type field"
            fi
        else
            print_warning "Folder not found in notes endpoint"
        fi

        # Clean up
        print_info "\nCleaning up test folder..."
        curl -s -X POST http://127.0.0.1:8000/delete-note \
            -H "Content-Type: application/json" \
            -d "{\"note_id\":\"$folder_id\"}"

    else
        print_error "Backend folder creation failed"
    fi
}

# Test 2: Measure timing between optimistic update and backend response
test_timing_analysis() {
    print_header "Test 2: Timing Analysis"

    print_info "This test measures the timing gap that causes the icon bug:"
    echo "1. Frontend optimistic update (sets type='folder')"
    echo "2. Backend API call"
    echo "3. Backend response"
    echo "4. Frontend reloads notes"

    # Create multiple folders to measure average timing
    local num_folders=3
    local total_duration=0
    local successful_creations=0

    for i in $(seq 1 $num_folders); do
        local test_folder="timing_test_${i}_$(date +%s)"

        print_info "\nCreating folder $i/$num_folders: $test_folder"

        # Measure API call time
        start_time=$(date +%s%N)

        response=$(curl -s -X POST http://127.0.0.1:8000/create-folder \
            -H "Content-Type: application/json" \
            -d "{\"folder_path\":\"$test_folder\"}")

        end_time=$(date +%s%N)
        duration=$(( (end_time - start_time) / 1000000 ))

        echo "  API call took: ${duration}ms"

        if echo "$response" | grep -q '"success":true'; then
            successful_creations=$((successful_creations + 1))
            total_duration=$((total_duration + duration))

            # Extract folder_id for cleanup
            folder_id=$(echo "$response" | grep -o '"folder_id":"[^"]*"' | cut -d'"' -f4)

            # Clean up immediately
            curl -s -X POST http://127.0.0.1:8000/delete-note \
                -H "Content-Type: application/json" \
                -d "{\"note_id\":\"$folder_id\"}" > /dev/null
        fi

        sleep 1  # Wait between creations
    done

    if [ $successful_creations -gt 0 ]; then
        local avg_duration=$((total_duration / successful_creations))
        print_info "\nTiming Analysis Results:"
        echo "  Successful creations: $successful_creations/$num_folders"
        echo "  Average API response time: ${avg_duration}ms"
        echo "  Expected UI delay: ~${avg_duration}ms"

        if [ $avg_duration -gt 100 ]; then
            print_warning "API response time >100ms - UI may show loading state"
        else
            print_success "API response time <100ms - should be fast enough"
        fi
    fi
}

# Test 3: Check data model compatibility
test_data_model() {
    print_header "Test 3: Data Model Compatibility Check"

    print_info "Checking if frontend and backend NoteInfo models match..."

    # Get sample notes from backend
    print_info "\nGetting sample notes from backend:"
    notes_response=$(curl -s http://127.0.0.1:8000/notes)

    # Check response structure
    echo "Backend response keys:"
    echo "$notes_response" | python3 -c "
import json, sys
try:
    data = json.loads(sys.stdin.read())
    if 'notes' in data:
        print('  - notes (array)')
        if data['notes']:
            first_note = data['notes'][0]
            print('  First note keys:')
            for key in first_note.keys():
                print(f'    - {key}')
            print(f'  First note type: {first_note.get(\"type\", \"missing\")}')
            print(f'  First note children type: {type(first_note.get(\"children\", [])).__name__}')
    else:
        print('  - No \"notes\" key found')
except Exception as e:
    print(f'  Error parsing JSON: {e}')
"

    # Create a test folder and check its structure
    print_info "\nCreating test folder to check structure..."
    test_folder="model_test_$(date +%s)"

    create_response=$(curl -s -X POST http://127.0.0.1:8000/create-folder \
        -H "Content-Type: application/json" \
        -d "{\"folder_path\":\"$test_folder\"}")

    if echo "$create_response" | grep -q '"success":true'; then
        folder_id=$(echo "$create_response" | grep -o '"folder_id":"[^"]*"' | cut -d'"' -f4)

        # Get notes again to see the new folder
        notes_response=$(curl -s http://127.0.0.1:8000/notes)

        echo "\nLooking for created folder in response:"
        echo "$notes_response" | python3 -c "
import json, sys
try:
    data = json.loads(sys.stdin.read())
    if 'notes' in data:
        for note in data['notes']:
            if note.get('id') == '$folder_id':
                print(f'  Found folder: {note[\"id\"]}')
                print(f'  Type field: {note.get(\"type\", \"missing\")}')
                print(f'  Children: {note.get(\"children\", [])}')
                print(f'  Children type: {type(note.get(\"children\", [])).__name__}')
                break
except Exception as e:
    print(f'  Error: {e}')
"

        # Clean up
        curl -s -X POST http://127.0.0.1:8000/delete-note \
            -H "Content-Type: application/json" \
            -d "{\"note_id\":\"$folder_id\"}" > /dev/null
    fi
}

# Test 4: Debug log analysis
test_debug_logs() {
    print_header "Test 4: Debug Log Analysis"

    local log_file="$HOME/Documents/GrimoireDebug.log"

    if [ -f "$log_file" ]; then
        print_info "Found debug log: $log_file"

        # Check for folder creation logs
        local folder_logs=$(grep -c "folder" "$log_file" 2>/dev/null || echo "0")
        local creation_logs=$(grep -c "Folder creation" "$log_file" 2>/dev/null || echo "0")
        local type_logs=$(grep -c "type:" "$log_file" 2>/dev/null || echo "0")

        echo "  Total folder-related logs: $folder_logs"
        echo "  Folder creation logs: $creation_logs"
        echo "  Type field logs: $type_logs"

        # Show recent folder creation logs
        print_info "\nRecent folder creation logs (last 5):"
        grep -i "folder creation" "$log_file" | tail -5 | while read line; do
            echo "  $line"
        done

        # Show recent type field logs
        print_info "\nRecent type field logs (last 5):"
        grep -i "type:" "$log_file" | tail -5 | while read line; do
            echo "  $line"
        done

    else
        print_warning "Debug log not found: $log_file"
        print_info "Run the app once to generate debug logs"
    fi
}

# Test 5: Using Instruments for profiling
test_instruments_profiling() {
    print_header "Test 5: Instruments Profiling Setup"

    if [ -f "run_instruments.sh" ]; then
        print_success "Instruments profiling script found"

        print_info "\nTo profile folder creation with Instruments:"
        echo "  ./run_instruments.sh points 30"
        echo ""
        echo "Then in the app:"
        echo "  1. Create a new folder"
        echo "  2. Observe the icon behavior"
        echo "  3. Check Points of Interest for timing"
        echo ""
        echo "Look for these signposts:"
        echo "  - 'Folder Creation' timing"
        echo "  - 'API Call' to /create-folder"
        echo "  - 'UI Render' for NoteRow"

    else
        print_warning "run_instruments.sh not found"
    fi
}

# Test 6: Manual bug reproduction steps
test_manual_reproduction() {
    print_header "Test 6: Manual Bug Reproduction Steps"

    print_info "To manually reproduce and debug the folder icon bug:"
    echo ""
    echo "1. Start the app with debug logging:"
    echo "   - Build and run Grimoire.app"
    echo "   - Check ~/Documents/GrimoireDebug.log"
    echo ""
    echo "2. Monitor debug logs in real-time:"
    echo "   tail -f ~/Documents/GrimoireDebug.log | grep -E '(NoteRow|type:|folder)'"
    echo ""
    echo "3. Create a new folder and observe:"
    echo "   - Look for 'Adding optimistic folder to UI' log"
    echo "   - Check if type field is 'folder' in optimistic update"
    echo "   - Note the API response time"
    echo "   - Check if loadNotes() overwrites the optimistic folder"
    echo ""
    echo "4. Check NoteRow rendering logs:"
    echo "   - Look for 'NoteRow rendering:' logs"
    echo "   - Check if type field is nil when showing loading state"
    echo "   - Check if type field becomes 'folder' after backend response"
    echo ""
    echo "5. Expected bug pattern:"
    echo "   - NoteRow renders with type=nil (shows loading)"
    echo "   - Backend responds after 100-200ms"
    echo "   - loadNotes() reloads all notes"
    echo "   - NoteRow re-renders with type='folder' (shows folder icon)"
    echo ""
    print_info "The fix should ensure type='folder' is set optimistically"
}

# Main function
main() {
    echo -e "${BLUE}=========================================${NC}"
    echo -e "${BLUE}Grimoire Folder Icon Bug Investigation${NC}"
    echo -e "${BLUE}=========================================${NC}"
    echo ""
    print_info "Investigating why new folders show note icons (📄) instead of folder icons (📁)"
    echo ""

    # Check prerequisites
    check_prerequisites

    # Run tests
    test_backend_folder_creation
    test_timing_analysis
    test_data_model
    test_debug_logs
    test_instruments_profiling
    test_manual_reproduction

    print_header "Investigation Summary"

    print_info "Based on code analysis, the likely causes are:"
    echo ""
    echo "1. Data model mismatch:"
    echo "   - Backend returns children as array of strings"
    echo "   - Frontend expects children as array of NoteInfo objects"
    echo "   - Backend doesn't provide 'path' field"
    echo ""
    echo "2. Timing issues:"
    echo "   - UI renders before optimistic update completes"
    echo "   - Backend API response takes 100-200ms"
    echo "   - loadNotes() may overwrite optimistic updates"
    echo ""
    echo "3. Debugging approach:"
    echo "   ✓ Use debug logs to track type field changes"
    echo "   ✓ Use Instruments to measure timing gaps"
    echo "   ✓ Test backend API response structure"
    echo "   ✓ Monitor NoteRow rendering with debug view modifier"
    echo ""
    print_info "Next steps:"
    echo "1. Fix data model conversion in NoteManager"
    echo "2. Ensure optimistic updates persist through loadNotes()"
    echo "3. Add more detailed logging for type field changes"
    echo "4. Use OSSignpost to measure critical timing paths"

    # Clean up backend if we started it
    if [ -n "$BACKEND_PID" ]; then
        print_info "\nCleaning up backend process (PID: $BACKEND_PID)"
        kill $BACKEND_PID 2>/dev/null || true
    fi
}

# Run main function
main "$@"
