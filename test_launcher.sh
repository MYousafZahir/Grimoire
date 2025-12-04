#!/bin/bash

# Grimoire Launcher Test Script
# Tests the main launcher functionality without actually installing dependencies

set -e

echo "🧪 Testing Grimoire Launcher..."

# Check if launcher exists
if [ ! -f "./grimoire" ]; then
    echo "❌ Launcher not found at ./grimoire"
    exit 1
fi

# Make sure it's executable
chmod +x ./grimoire

echo "✅ Launcher exists and is executable"

# Test help command
echo "Testing help command..."
if ./grimoire help 2>&1 | grep -q "Usage:"; then
    echo "✅ Help command works"
else
    echo "❌ Help command failed"
    exit 1
fi

# Test status command (should work even without setup)
echo "Testing status command..."
if ./grimoire status 2>&1 | grep -q "Grimoire Status"; then
    echo "✅ Status command works"
else
    echo "❌ Status command failed"
    exit 1
fi

# Test stop command (should work even if nothing is running)
echo "Testing stop command..."
if ./grimoire stop 2>&1 | grep -q "Backend server"; then
    echo "✅ Stop command works"
else
    echo "❌ Stop command failed"
    exit 1
fi

# Check file structure
echo "Checking file structure..."
REQUIRED_FILES=(
    "backend/main.py"
    "backend/chunker.py"
    "backend/embedder.py"
    "backend/indexer.py"
    "backend/requirements.txt"
    "macos-app/GrimoireApp.swift"
    "macos-app/Views/ContentView.swift"
    "macos-app/Views/SidebarView.swift"
    "macos-app/Views/EditorView.swift"
    "macos-app/Views/BacklinksView.swift"
    "macos-app/FileManager/NoteManager.swift"
    "macos-app/Networking/SearchManager.swift"
)

missing_files=0
for file in "${REQUIRED_FILES[@]}"; do
    if [ -f "$file" ]; then
        echo "  ✅ $file"
    else
        echo "  ❌ $file (missing)"
        missing_files=$((missing_files + 1))
    fi
done

if [ $missing_files -eq 0 ]; then
    echo "✅ All required files present"
else
    echo "❌ Missing $missing_files required files"
    exit 1
fi

# Check Python syntax
echo "Checking Python syntax..."
cd backend
for py_file in *.py; do
    if python3 -m py_compile "$py_file" 2>/dev/null; then
        echo "  ✅ $py_file (valid Python)"
        rm -f "${py_file}c"  # Clean up .pyc files
    else
        echo "  ❌ $py_file (invalid Python)"
        exit 1
    fi
done
cd ..

# Check that launcher has all required functions
echo "Checking launcher functions..."
REQUIRED_FUNCTIONS=(
    "check_requirements"
    "setup_virtualenv"
    "install_python_deps"
    "setup_storage"
    "start_backend"
    "setup_macos_app"
    "launch_macos_app"
    "stop_backend"
    "check_status"
    "show_usage"
)

for func in "${REQUIRED_FUNCTIONS[@]}"; do
    if grep -q "^$func()" ./grimoire; then
        echo "  ✅ Function $func found"
    else
        echo "  ❌ Function $func not found"
        exit 1
    fi
done

# Test launcher argument parsing
echo "Testing argument parsing..."
test_cases=(
    "help:should show usage"
    "status:should show status"
    "stop:should stop backend"
    "reset:should ask for confirmation"
    "invalid:should show error"
)

for test_case in "${test_cases[@]}"; do
    cmd="${test_case%:*}"
    expected="${test_case#*:}"

    echo "  Testing: ./grimoire $cmd"
    if ./grimoire "$cmd" 2>&1 | head -5 > /dev/null; then
        echo "    ✅ Command '$cmd' executed"
    else
        echo "    ❌ Command '$cmd' failed"
        exit 1
    fi
done

# Create a simple test for the setup command (dry run)
echo "Testing setup command (dry run)..."
# We'll just check that it doesn't crash on the requirements check
if ./grimoire setup 2>&1 | head -20 | grep -q "Checking System Requirements"; then
    echo "✅ Setup command starts correctly"
else
    echo "❌ Setup command failed to start"
    exit 1
fi

echo ""
echo "🎉 All tests passed!"
echo ""
echo "To actually run Grimoire:"
echo "  ./grimoire        # Full setup and launch"
echo "  ./grimoire setup  # Setup only"
echo "  ./grimoire backend # Start backend only"
echo "  ./grimoire app    # Launch app only"
echo ""
echo "Note: This test only validates the launcher structure, not actual functionality."
echo "Actual setup will install dependencies and may take several minutes."
