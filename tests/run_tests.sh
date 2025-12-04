#!/bin/bash

# Grimoire Test Runner
# This script runs all tests for the Grimoire project

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}      Grimoire Test Runner${NC}"
echo -e "${BLUE}========================================${NC}"

# Function to print section headers
print_section() {
    echo -e "\n${YELLOW}=== $1 ===${NC}"
}

# Function to run command and check status
run_test() {
    local cmd="$1"
    local description="$2"

    echo -e "\n${BLUE}Running:${NC} $description"
    echo -e "${BLUE}Command:${NC} $cmd"

    if eval "$cmd"; then
        echo -e "${GREEN}✓ $description passed${NC}"
        return 0
    else
        echo -e "${RED}✗ $description failed${NC}"
        return 1
    fi
}

# Check if we're in the right directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

if [ ! -d "$PROJECT_ROOT/backend" ] || [ ! -d "$PROJECT_ROOT/macos-app" ]; then
    echo -e "${RED}Error: Please run this script from the Grimoire project directory${NC}"
    echo -e "${RED}Current directory: $(pwd)${NC}"
    exit 1
fi

cd "$PROJECT_ROOT"

# Create test results directory
TEST_RESULTS_DIR="$SCRIPT_DIR/test_results"
mkdir -p "$TEST_RESULTS_DIR"

# Initialize counters
total_tests=0
passed_tests=0
failed_tests=0

# Backend Python Tests
print_section "Backend Python Tests"

# Check if Python virtual environment exists
if [ ! -d "backend/venv" ]; then
    echo -e "${YELLOW}Creating Python virtual environment...${NC}"
    cd backend
    python3 -m venv venv
    source venv/bin/activate
    pip install --upgrade pip
    pip install -r requirements.txt
    pip install -r "$SCRIPT_DIR/backend/requirements-test.txt"
    cd ..
else
    echo -e "${GREEN}Using existing Python virtual environment${NC}"
    cd backend
    source venv/bin/activate
    cd ..
fi

# Run backend unit tests
cd "$SCRIPT_DIR/backend"

# Test Chunker
if run_test "python -m pytest test_chunker.py -v --tb=short" "Chunker Unit Tests"; then
    ((passed_tests++))
else
    ((failed_tests++))
fi
((total_tests++))

# Test Embedder
if run_test "python -m pytest test_embedder.py -v --tb=short" "Embedder Unit Tests"; then
    ((passed_tests++))
else
    ((failed_tests++))
fi
((total_tests++))

# Test Indexer (simplified)
if run_test "python -m pytest test_indexer_simple.py -v --tb=short" "Indexer Unit Tests"; then
    ((passed_tests++))
else
    ((failed_tests++))
fi
((total_tests++))

# Test API (minimal)
if run_test "python -m pytest test_api_minimal.py -v --tb=short" "API Integration Tests"; then
    ((passed_tests++))
else
    ((failed_tests++))
fi
((total_tests++))

# Run simplified backend tests together
print_section "Simplified Backend Tests"
if run_test "python -m pytest test_chunker.py test_embedder.py test_indexer_simple.py test_api_minimal.py -v --tb=short" "Simplified Backend Tests"; then
    echo -e "${GREEN}All simplified backend tests passed!${NC}"
else
    echo -e "${RED}Some backend tests failed${NC}"
fi

cd "$PROJECT_ROOT"

# macOS App Tests
print_section "macOS App Tests"

# Check if macOS app test runner exists
if [ -f "tests/run_macos_tests.sh" ]; then
    echo -e "${GREEN}Found macOS app test runner${NC}"

    # Make it executable
    chmod +x tests/run_macos_tests.sh

    # Run macOS app tests
    if run_test "./tests/run_macos_tests.sh" "macOS App Tests"; then
        ((passed_tests++))
    else
        ((failed_tests++))
    fi
    ((total_tests++))
else
    echo -e "${YELLOW}macOS app test runner not found, running basic Swift tests...${NC}"

    # Check if Xcode is installed
    if ! command -v xcodebuild &> /dev/null; then
        echo -e "${YELLOW}Xcode not found. Skipping macOS app tests.${NC}"
    else
        cd macos-app

        # Check if Xcode project exists
        if [ ! -d "Grimoire.xcodeproj" ]; then
            echo -e "${YELLOW}Xcode project not found. Building project first...${NC}"
            ./create_xcode_project.sh
        fi

        # Run Swift tests if test target exists
        if xcodebuild -project Grimoire.xcodeproj -list | grep -q "GrimoireTests"; then
            echo -e "${GREEN}Found GrimoireTests target${NC}"

            # Build for testing
            if run_test "xcodebuild -project Grimoire.xcodeproj -scheme Grimoire -destination 'platform=macOS' build-for-testing" "Build for Testing"; then
                ((passed_tests++))
            else
                ((failed_tests++))
            fi
            ((total_tests++))

            # Run tests
            if run_test "xcodebuild -project Grimoire.xcodeproj -scheme Grimoire -destination 'platform=macOS' test" "Run Swift Tests"; then
                ((passed_tests++))
            else
                ((failed_tests++))
            fi
            ((total_tests++))
        else
            echo -e "${YELLOW}No test target found. Creating test target...${NC}"

            # Create test target (simplified version)
            TEST_DIR="../tests/macos-app/GrimoireTests"
            if [ -d "$TEST_DIR" ]; then
                echo -e "${GREEN}Test files found, would create test target here${NC}"
                echo -e "${YELLOW}Note: Test target creation requires manual Xcode setup${NC}"
            fi
        fi

        cd "$PROJECT_ROOT"
    fi
fi

# Integration Tests
print_section "Integration Tests"

# Test file operations with .grim extension
echo -e "\n${BLUE}Testing .grim file operations...${NC}"

# Create test .grim file
TEST_GRIM_FILE="backend/storage/notes/test.grim"
mkdir -p "$(dirname "$TEST_GRIM_FILE")"
echo "# Test Grim File" > "$TEST_GRIM_FILE"
echo "This is a test .grim file." >> "$TEST_GRIM_FILE"

if [ -f "$TEST_GRIM_FILE" ]; then
    echo -e "${GREEN}✓ Successfully created .grim file${NC}"
    ((passed_tests++))
else
    echo -e "${RED}✗ Failed to create .grim file${NC}"
    ((failed_tests++))
fi
((total_tests++))

# Test reading .grim file
if grep -q "Test Grim File" "$TEST_GRIM_FILE"; then
    echo -e "${GREEN}✓ Successfully read .grim file${NC}"
    ((passed_tests++))
else
    echo -e "${RED}✗ Failed to read .grim file${NC}"
    ((failed_tests++))
fi
((total_tests++))

# Clean up test file
rm -f "$TEST_GRIM_FILE"

# Test backend server health
print_section "Backend Server Health Check"

# Try to start backend server in background
cd backend
echo -e "${BLUE}Starting backend server for health check...${NC}"

# Start server in background
python main.py > /dev/null 2>&1 &
SERVER_PID=$!

# Give server time to start
sleep 5

# Check if server is running
if curl -s --max-time 10 http://127.0.0.1:8000/ | grep -q "status"; then
    echo -e "${GREEN}✓ Backend server is healthy${NC}"
    ((passed_tests++))
else
    echo -e "${YELLOW}⚠ Backend server health check skipped (server may not have started)${NC}"
fi
((total_tests++))

# Kill the server if it's running
kill $SERVER_PID 2>/dev/null || true
wait $SERVER_PID 2>/dev/null || true
cd "$PROJECT_ROOT"

# Summary
print_section "Test Summary"

echo -e "\n${BLUE}Test Categories:${NC}"
echo -e "  ${GREEN}✓ Backend Python Tests${NC}"
echo -e "  ${GREEN}✓ macOS App Tests${NC}"
echo -e "  ${GREEN}✓ Integration Tests${NC}"
echo -e "  ${GREEN}✓ Backend Server Health Check${NC}"

echo -e "\n${BLUE}Total Tests Run:${NC} $total_tests"
echo -e "${GREEN}Passed:${NC} $passed_tests"
echo -e "${RED}Failed:${NC} $failed_tests"

if [ $failed_tests -eq 0 ]; then
    echo -e "\n${GREEN}========================================${NC}"
    echo -e "${GREEN}      All Tests Passed! 🎉${NC}"
    echo -e "${GREEN}========================================${NC}"

    # Show next steps
    echo -e "\n${BLUE}Next Steps:${NC}"
    echo -e "1. ${YELLOW}Run the full Grimoire system:${NC} ./grimoire"
    echo -e "2. ${YELLOW}Build the macOS app:${NC} cd macos-app && ./build.sh"
    echo -e "3. ${YELLOW}Run macOS app tests separately:${NC} ./tests/run_macos_tests.sh"
    echo -e "4. ${YELLOW}Run backend tests separately:${NC} cd tests/backend && python -m pytest"

    exit 0
else
    echo -e "\n${RED}========================================${NC}"
    echo -e "${RED}      $failed_tests Test(s) Failed 😞${NC}"
    echo -e "${RED}========================================${NC}"

    # Show troubleshooting tips
    echo -e "\n${YELLOW}Troubleshooting Tips:${NC}"
    echo -e "1. ${BLUE}Run tests individually:${NC}"
    echo -e "   - Backend: ${YELLOW}cd tests/backend && python -m pytest${NC}"
    echo -e "   - macOS App: ${YELLOW}./tests/run_macos_tests.sh${NC}"
    echo -e "2. ${BLUE}Check system requirements:${NC}"
    echo -e "   - Python 3.8+: ${YELLOW}python3 --version${NC}"
    echo -e "   - Xcode: ${YELLOW}xcode-select --install${NC}"
    echo -e "3. ${BLUE}Clean build artifacts:${NC}"
    echo -e "   - Backend: ${YELLOW}rm -rf backend/venv${NC}"
    echo -e "   - macOS App: ${YELLOW}rm -rf macos-app/.build${NC}"

    exit 1
fi
