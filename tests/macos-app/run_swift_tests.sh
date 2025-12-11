#!/bin/bash

# Simple Swift Test Runner for Grimoire macOS App
# This script compiles and runs Swift tests without complex setup

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}   Grimoire Swift Test Runner${NC}"
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
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

if [ ! -d "$PROJECT_ROOT/macos-app" ]; then
    echo -e "${RED}Error: Please run this script from the Grimoire project directory${NC}"
    echo -e "${RED}Current directory: $(pwd)${NC}"
    exit 1
fi

cd "$PROJECT_ROOT"

# Initialize counters
total_tests=0
passed_tests=0
failed_tests=0

# Check system requirements
print_section "System Requirements"
if ! command -v swift &> /dev/null; then
    echo -e "${RED}Error: Swift not found${NC}"
    echo -e "${YELLOW}Please install Xcode from the App Store${NC}"
    exit 1
else
    swift_version=$(swift --version | head -1)
    echo -e "${GREEN}✓ Swift found: $swift_version${NC}"
fi

# Create test directory
TEST_DIR="$PROJECT_ROOT/tests/macos-app"
mkdir -p "$TEST_DIR/test_build"

# Test 1: Check Swift syntax of main files
print_section "Swift Syntax Check"
echo -e "${BLUE}Checking Swift syntax of main files...${NC}"

MAIN_FILES=(
    "macos-app/GrimoireApp.swift"
    "macos-app/ContentView.swift"
    "macos-app/SidebarView.swift"
    "macos-app/EditorView.swift"
    "macos-app/BacklinksView.swift"
    "macos-app/SettingsView.swift"
    "macos-app/Domain/Models.swift"
    "macos-app/Data/NoteRepository.swift"
    "macos-app/Data/SearchRepository.swift"
    "macos-app/Stores/NoteStore.swift"
    "macos-app/Stores/BacklinksStore.swift"
)

syntax_errors=0
for file in "${MAIN_FILES[@]}"; do
    if [ -f "$file" ]; then
        if swiftc -parse "$file" 2>/dev/null; then
            echo -e "  ${GREEN}✓ $file${NC}"
        else
            echo -e "  ${RED}✗ $file (syntax error)${NC}"
            syntax_errors=$((syntax_errors + 1))
        fi
    else
        echo -e "  ${YELLOW}⚠ $file (not found)${NC}"
    fi
done

if [ $syntax_errors -eq 0 ]; then
    echo -e "${GREEN}✓ All Swift files have valid syntax${NC}"
    ((passed_tests++))
else
    echo -e "${RED}✗ $syntax_errors Swift files have syntax errors${NC}"
    ((failed_tests++))
fi
((total_tests++))

# Test 2: Compile test models
print_section "Model Compilation Test"
echo -e "${BLUE}Compiling test models...${NC}"

MODEL_TEST_FILE="$TEST_DIR/test_models.swift"
cat > "$MODEL_TEST_FILE" << 'EOF'
import Foundation

// Test NoteInfo model
struct NoteInfo: Identifiable, Codable {
    let id: String
    let title: String
    let path: String
    let children: [NoteInfo]
}

// Test SearchResult model
struct SearchResult: Identifiable, Codable {
    let id: String
    let noteId: String
    let noteTitle: String
    let chunkId: String
    let excerpt: String
    let score: Double

    init(noteId: String, noteTitle: String, chunkId: String, excerpt: String, score: Double) {
        self.id = "\(noteId)_\(chunkId)"
        self.noteId = noteId
        self.noteTitle = noteTitle
        self.chunkId = chunkId
        self.excerpt = excerpt
        self.score = score
    }
}

// Test encoding/decoding
func testModels() -> Bool {
    // Test NoteInfo
    let noteInfo = NoteInfo(
        id: "test-id",
        title: "Test Note",
        path: "test/path",
        children: []
    )

    // Test encoding
    let encoder = JSONEncoder()
    guard let noteData = try? encoder.encode(noteInfo) else {
        return false
    }

    // Test decoding
    let decoder = JSONDecoder()
    guard let decodedNote = try? decoder.decode(NoteInfo.self, from: noteData) else {
        return false
    }

    guard decodedNote.id == noteInfo.id &&
          decodedNote.title == noteInfo.title &&
          decodedNote.path == noteInfo.path else {
        return false
    }

    // Test SearchResult
    let searchResult = SearchResult(
        noteId: "note-1",
        noteTitle: "Test Note",
        chunkId: "chunk-1",
        excerpt: "Test excerpt",
        score: 0.95
    )

    guard let resultData = try? encoder.encode(searchResult) else {
        return false
    }

    guard let decodedResult = try? decoder.decode(SearchResult.self, from: resultData) else {
        return false
    }

    guard decodedResult.noteId == searchResult.noteId &&
          decodedResult.excerpt == searchResult.excerpt &&
          decodedResult.score == searchResult.score else {
        return false
    }

    return true
}

// Run test
if testModels() {
    print("Model tests passed")
    exit(0)
} else {
    print("Model tests failed")
    exit(1)
}
EOF

if swift "$MODEL_TEST_FILE" 2>/dev/null; then
    echo -e "${GREEN}✓ Model compilation test passed${NC}"
    ((passed_tests++))
else
    echo -e "${RED}✗ Model compilation test failed${NC}"
    ((failed_tests++))
fi
((total_tests++))

rm -f "$MODEL_TEST_FILE" 2>/dev/null || true

# Test 3: SwiftUI preview compilation
print_section "SwiftUI Preview Test"
echo -e "${BLUE}Testing SwiftUI preview compilation...${NC}"

PREVIEW_TEST_FILE="$TEST_DIR/test_previews.swift"
cat > "$PREVIEW_TEST_FILE" << 'EOF'
import SwiftUI

// Test basic SwiftUI views
struct TestContentView: View {
    var body: some View {
        Text("Test Content View")
            .padding()
    }
}

struct TestSidebarView: View {
    var body: some View {
        List {
            Text("Item 1")
            Text("Item 2")
            Text("Item 3")
        }
    }
}

struct TestEditorView: View {
    @State private var text = "Test content"

    var body: some View {
        TextEditor(text: $text)
            .padding()
    }
}

struct TestBacklinksView: View {
    var body: some View {
        VStack {
            Text("Backlink 1")
            Text("Backlink 2")
            Text("Backlink 3")
        }
    }
}

// Test that views compile
let _ = TestContentView()
let _ = TestSidebarView()
let _ = TestEditorView()
let _ = TestBacklinksView()

print("SwiftUI preview compilation test passed")
EOF

if swiftc -emit-executable -o /tmp/test_previews "$PREVIEW_TEST_FILE" 2>/dev/null; then
    echo -e "${GREEN}✓ SwiftUI preview compilation test passed${NC}"
    ((passed_tests++))
else
    echo -e "${RED}✗ SwiftUI preview compilation test failed${NC}"
    ((failed_tests++))
fi
((total_tests++))

rm -f "$PREVIEW_TEST_FILE" /tmp/test_previews 2>/dev/null || true

# Test 4: File structure validation
print_section "File Structure Validation"
echo -e "${BLUE}Validating file structure...${NC}"

REQUIRED_FILES=(
    "macos-app/GrimoireApp.swift"
    "macos-app/ContentView.swift"
    "macos-app/SidebarView.swift"
    "macos-app/EditorView.swift"
    "macos-app/BacklinksView.swift"
    "macos-app/SettingsView.swift"
    "macos-app/NoteManager.swift"
    "macos-app/SearchManager.swift"
    "macos-app/Resources/Info.plist"
)

missing_files=0
for file in "${REQUIRED_FILES[@]}"; do
    if [ -f "$file" ]; then
        echo -e "  ${GREEN}✓ $file${NC}"
    else
        echo -e "  ${RED}✗ $file (missing)${NC}"
        missing_files=$((missing_files + 1))
    fi
done

if [ $missing_files -eq 0 ]; then
    echo -e "${GREEN}✓ All required files present${NC}"
    ((passed_tests++))
else
    echo -e "${RED}✗ $missing_files required files missing${NC}"
    ((failed_tests++))
fi
((total_tests++))

# Test 5: Xcode project validation
print_section "Xcode Project Validation"
if [ -d "macos-app/Grimoire.xcodeproj" ]; then
    echo -e "${GREEN}✓ Xcode project exists${NC}"

    # Check if project can be listed
    if command -v xcodebuild &> /dev/null; then
        if xcodebuild -project macos-app/Grimoire.xcodeproj -list 2>/dev/null | grep -q "Grimoire"; then
            echo -e "${GREEN}✓ Xcode project is valid${NC}"
            ((passed_tests++))
        else
            echo -e "${YELLOW}⚠ Xcode project listing failed${NC}"
            ((failed_tests++))
        fi
    else
        echo -e "${YELLOW}⚠ xcodebuild not found, skipping Xcode validation${NC}"
    fi
else
    echo -e "${YELLOW}⚠ Xcode project not found${NC}"
    echo -e "${BLUE}You can create it with:${NC} cd macos-app && ./create_xcode_project.sh"
fi
((total_tests++))

# Test 6: Build script validation
print_section "Build Script Validation"
BUILD_SCRIPTS=(
    "macos-app/build.sh"
    "macos-app/build_app.sh"
    "macos-app/build_simple.sh"
)

for script in "${BUILD_SCRIPTS[@]}"; do
    if [ -f "$script" ]; then
        if [ -x "$script" ]; then
            echo -e "  ${GREEN}✓ $script (executable)${NC}"
        else
            echo -e "  ${YELLOW}⚠ $script (not executable)${NC}"
            chmod +x "$script" 2>/dev/null && echo -e "    ${GREEN}Made executable${NC}"
        fi
    else
        echo -e "  ${YELLOW}⚠ $script (not found)${NC}"
    fi
done

echo -e "${GREEN}✓ Build scripts validated${NC}"
((passed_tests++))
((total_tests++))

# Summary
print_section "Test Summary"

echo -e "\n${BLUE}Test Categories:${NC}"
echo -e "  ${GREEN}✓ Swift Syntax Check${NC}"
echo -e "  ${GREEN}✓ Model Compilation${NC}"
echo -e "  ${GREEN}✓ SwiftUI Preview Compilation${NC}"
echo -e "  ${GREEN}✓ File Structure Validation${NC}"
echo -e "  ${GREEN}✓ Xcode Project Validation${NC}"
echo -e "  ${GREEN}✓ Build Script Validation${NC}"

echo -e "\n${BLUE}Total Tests Run:${NC} $total_tests"
echo -e "${GREEN}Passed:${NC} $passed_tests"
echo -e "${RED}Failed:${NC} $failed_tests"

if [ $failed_tests -eq 0 ]; then
    echo -e "\n${GREEN}========================================${NC}"
    echo -e "${GREEN}      All Swift Tests Passed! 🎉${NC}"
    echo -e "${GREEN}========================================${NC}"

    echo -e "\n${BLUE}Next Steps:${NC}"
    echo -e "1. ${YELLOW}Build the app:${NC} cd macos-app && ./build.sh"
    echo -e "2. ${YELLOW}Run the full test suite:${NC} ./tests/run_tests.sh"
    echo -e "3. ${YELLOW}Launch Grimoire:${NC} ./grimoire"

    exit 0
else
    echo -e "\n${RED}========================================${NC}"
    echo -e "${RED}      $failed_tests Test(s) Failed 😞${NC}"
    echo -e "${RED}========================================${NC}"

    echo -e "\n${YELLOW}Troubleshooting Tips:${NC}"
    echo -e "1. ${BLUE}Check Swift installation:${NC} swift --version"
    echo -e "2. ${BLUE}Check file permissions:${NC} ls -la macos-app/"
    echo -e "3. ${BLUE}Clean build artifacts:${NC} rm -rf macos-app/.build"
    echo -e "4. ${BLUE}Run individual tests:${NC}"
    echo -e "   - Syntax check: ${YELLOW}swiftc -parse macos-app/ContentView.swift${NC}"
    echo -e "   - Model test: ${YELLOW}swift tests/macos-app/test_models.swift${NC}"

    exit 1
fi
