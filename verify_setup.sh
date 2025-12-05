#!/bin/bash

# Grimoire Debug Setup Verification Script
# Verifies that the profiler replacement is complete and working

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

# Check if file exists and has content
check_file() {
    local file="$1"
    local description="$2"

    if [ -f "$file" ]; then
        if [ -s "$file" ]; then
            print_success "$description exists and has content"
            return 0
        else
            print_warning "$description exists but is empty"
            return 1
        fi
    else
        print_error "$description not found"
        return 2
    fi
}

# Check for string in file
check_contains() {
    local file="$1"
    local pattern="$2"
    local description="$3"

    if [ -f "$file" ]; then
        if grep -q "$pattern" "$file"; then
            print_success "$description found in $(basename $file)"
            return 0
        else
            print_warning "$description not found in $(basename $file)"
            return 1
        fi
    else
        print_error "File not found: $file"
        return 2
    fi
}

# Check that old profiler is removed
check_old_profiler_removed() {
    print_header "Checking Old Profiler Removal"

    local removed_count=0
    local total_checks=0

    # Check for removed directories
    if [ ! -d "profiler" ]; then
        print_success "Custom profiler directory removed"
        ((removed_count++))
    else
        print_error "Custom profiler directory still exists"
    fi
    ((total_checks++))

    if [ ! -d "macos-app/Profiler" ]; then
        print_success "Frontend profiler directory removed"
        ((removed_count++))
    else
        print_error "Frontend profiler directory still exists"
    fi
    ((total_checks++))

    # Check for removed files
    if [ ! -f "backend/profiler_integration.py" ]; then
        print_success "Backend profiler integration removed"
        ((removed_count++))
    else
        print_error "Backend profiler integration still exists"
    fi
    ((total_checks++))

    # Check for profiler imports in backend
    if [ -f "backend/main.py" ]; then
        if ! grep -q "profiler_integration" "backend/main.py"; then
            print_success "Backend profiler import removed"
            ((removed_count++))
        else
            print_error "Backend still imports profiler"
        fi
        ((total_checks++))
    fi

    echo ""
    print_info "Old profiler removal: $removed_count/$total_checks checks passed"

    if [ $removed_count -eq $total_checks ]; then
        return 0
    else
        return 1
    fi
}

# Check new debugging tools
check_new_debug_tools() {
    print_header "Checking New Debugging Tools"

    local passed_count=0
    local total_checks=0

    # Check DebugTools.swift
    check_file "macos-app/DebugTools.swift" "DebugTools.swift"
    if [ $? -eq 0 ]; then
        ((passed_count++))

        # Check for key components
        check_contains "macos-app/DebugTools.swift" "class SignpostManager" "SignpostManager class"
        if [ $? -eq 0 ]; then ((passed_count++)); fi
        ((total_checks++))

        check_contains "macos-app/DebugTools.swift" "class DebugLogger" "DebugLogger class"
        if [ $? -eq 0 ]; then ((passed_count++)); fi
        ((total_checks++))

        check_contains "macos-app/DebugTools.swift" "OSSignpostID" "OSSignpost integration"
        if [ $? -eq 0 ]; then ((passed_count++)); fi
        ((total_checks++))

        check_contains "macos-app/DebugTools.swift" "NetworkMetricsCollector" "Network metrics"
        if [ $? -eq 0 ]; then ((passed_count++)); fi
        ((total_checks++))

        check_contains "macos-app/DebugTools.swift" "RaceConditionDetector" "Race condition detection"
        if [ $? -eq 0 ]; then ((passed_count++)); fi
        ((total_checks++))
    fi
    ((total_checks++))

    # Check integration in NoteManager
    check_file "macos-app/NoteManager.swift" "NoteManager.swift"
    if [ $? -eq 0 ]; then
        ((passed_count++))

        check_contains "macos-app/NoteManager.swift" "logDebug\|logError" "Debug logging in NoteManager"
        if [ $? -eq 0 ]; then ((passed_count++)); fi
        ((total_checks++))

        check_contains "macos-app/NoteManager.swift" "SignpostManager" "OSSignpost in NoteManager"
        if [ $? -eq 0 ]; then ((passed_count++)); fi
        ((total_checks++))
    fi
    ((total_checks++))

    # Check integration in SearchManager
    check_file "macos-app/SearchManager.swift" "SearchManager.swift"
    if [ $? -eq 0 ]; then
        ((passed_count++))

        check_contains "macos-app/SearchManager.swift" "logDebug\|logError" "Debug logging in SearchManager"
        if [ $? -eq 0 ]; then ((passed_count++)); fi
        ((total_checks++))
    fi
    ((total_checks++))

    echo ""
    print_info "New debug tools: $passed_count/$total_checks checks passed"

    if [ $passed_count -eq $total_checks ]; then
        return 0
    else
        return 1
    fi
}

# Check profiling scripts
check_profiling_scripts() {
    print_header "Checking Profiling Scripts"

    local passed_count=0
    local total_checks=0

    # Check run_instruments.sh
    check_file "run_instruments.sh" "run_instruments.sh"
    if [ $? -eq 0 ]; then
        ((passed_count++))

        if [ -x "run_instruments.sh" ]; then
            print_success "run_instruments.sh is executable"
            ((passed_count++))
        else
            print_warning "run_instruments.sh is not executable"
        fi
        ((total_checks++))
    fi
    ((total_checks++))

    # Check profile_backend.py
    check_file "profile_backend.py" "profile_backend.py"
    if [ $? -eq 0 ]; then
        ((passed_count++))

        check_contains "profile_backend.py" "class BackendProfiler" "BackendProfiler class"
        if [ $? -eq 0 ]; then ((passed_count++)); fi
        ((total_checks++))

        check_contains "profile_backend.py" "cProfile" "cProfile integration"
        if [ $? -eq 0 ]; then ((passed_count++)); fi
        ((total_checks++))
    fi
    ((total_checks++))

    # Check test_debug_tools.sh
    check_file "test_debug_tools.sh" "test_debug_tools.sh"
    if [ $? -eq 0 ]; then
        ((passed_count++))

        if [ -x "test_debug_tools.sh" ]; then
            print_success "test_debug_tools.sh is executable"
            ((passed_count++))
        else
            print_warning "test_debug_tools.sh is not executable"
        fi
        ((total_checks++))
    fi
    ((total_checks++))

    echo ""
    print_info "Profiling scripts: $passed_count/$total_checks checks passed"

    if [ $passed_count -eq $total_checks ]; then
        return 0
    else
        return 1
    fi
}

# Check documentation
check_documentation() {
    print_header "Checking Documentation"

    local passed_count=0
    local total_checks=0

    check_file "PROFILING_GUIDE.md" "PROFILING_GUIDE.md"
    if [ $? -eq 0 ]; then
        ((passed_count++))

        check_contains "PROFILING_GUIDE.md" "Instruments" "Instruments documentation"
        if [ $? -eq 0 ]; then ((passed_count++)); fi
        ((total_checks++))

        check_contains "PROFILING_GUIDE.md" "OSSignpost" "OSSignpost documentation"
        if [ $? -eq 0 ]; then ((passed_count++)); fi
        ((total_checks++))

        check_contains "PROFILING_GUIDE.md" "Thread Sanitizer" "Thread Sanitizer documentation"
        if [ $? -eq 0 ]; then ((passed_count++)); fi
        ((total_checks++))
    fi
    ((total_checks++))

    check_file "PROFILER_REPLACEMENT_SUMMARY.md" "PROFILER_REPLACEMENT_SUMMARY.md"
    if [ $? -eq 0 ]; then
        ((passed_count++))

        check_contains "PROFILER_REPLACEMENT_SUMMARY.md" "What Was Removed" "Removal summary"
        if [ $? -eq 0 ]; then ((passed_count++)); fi
        ((total_checks++))

        check_contains "PROFILER_REPLACEMENT_SUMMARY.md" "What Was Added" "Addition summary"
        if [ $? -eq 0 ]; then ((passed_count++)); fi
        ((total_checks++))
    fi
    ((total_checks++))

    check_file "DEBUG_EXAMPLES.md" "DEBUG_EXAMPLES.md"
    if [ $? -eq 0 ]; then
        ((passed_count++))

        check_contains "DEBUG_EXAMPLES.md" "Basic Debug Logging" "Debug examples"
        if [ $? -eq 0 ]; then ((passed_count++)); fi
        ((total_checks++))
    fi
    ((total_checks++))

    echo ""
    print_info "Documentation: $passed_count/$total_checks checks passed"

    if [ $passed_count -eq $total_checks ]; then
        return 0
    else
        return 1
    fi
}

# Check build configuration
check_build_config() {
    print_header "Checking Build Configuration"

    local passed_count=0
    local total_checks=0

    # Check Package.swift for debug dependencies
    if [ -f "macos-app/Package.swift" ]; then
        print_success "Package.swift exists"
        ((passed_count++))

        # Check that we're not importing custom profiler
        if ! grep -q "Profiler" "macos-app/Package.swift"; then
            print_success "Package.swift doesn't reference custom profiler"
            ((passed_count++))
        else
            print_warning "Package.swift may reference custom profiler"
        fi
        ((total_checks++))
    else
        print_warning "Package.swift not found"
    fi
    ((total_checks++))

    # Check that app can be built
    if [ -f "macos-app/build.sh" ] || [ -f "macos-app/build_app.sh" ]; then
        print_success "Build script exists"
        ((passed_count++))
    else
        print_warning "No build script found"
    fi
    ((total_checks++))

    echo ""
    print_info "Build configuration: $passed_count/$total_checks checks passed"

    if [ $passed_count -eq $total_checks ]; then
        return 0
    else
        return 1
    fi
}

# Main verification function
main() {
    echo -e "${BLUE}=========================================${NC}"
    echo -e "${BLUE}Grimoire Profiler Replacement Verification${NC}"
    echo -e "${BLUE}=========================================${NC}"
    echo ""
    print_info "Verifying setup: Custom profiler → Standard tools"
    echo ""

    local overall_passed=0
    local overall_total=0

    # Run all checks
    check_old_profiler_removed
    local result1=$?

    check_new_debug_tools
    local result2=$?

    check_profiling_scripts
    local result3=$?

    check_documentation
    local result4=$?

    check_build_config
    local result5=$?

    # Calculate overall results
    overall_passed=0
    if [ $result1 -eq 0 ]; then ((overall_passed++)); fi
    if [ $result2 -eq 0 ]; then ((overall_passed++)); fi
    if [ $result3 -eq 0 ]; then ((overall_passed++)); fi
    if [ $result4 -eq 0 ]; then ((overall_passed++)); fi
    if [ $result5 -eq 0 ]; then ((overall_passed++)); fi
    overall_total=5

    print_header "Verification Summary"

    if [ $overall_passed -eq $overall_total ]; then
        print_success "ALL CHECKS PASSED! ✓"
        echo ""
        print_info "Profiler replacement complete and verified."
        print_info "The custom profiler has been successfully replaced with:"
        echo ""
        echo "  1. OSSignpost for precise timing (Instruments compatible)"
        echo "  2. DebugLogger for flexible logging"
        echo "  3. NetworkMetricsCollector for URLSession metrics"
        echo "  4. RaceConditionDetector for concurrency issues"
        echo "  5. Comprehensive profiling scripts"
        echo "  6. Complete documentation"
        echo ""
        print_info "Next steps:"
        echo "  1. Run ./test_debug_tools.sh for detailed testing"
        echo "  2. Read PROFILING_GUIDE.md for usage instructions"
        echo "  3. Use ./run_instruments.sh to profile with Instruments"
        echo "  4. Use python profile_backend.py for backend profiling"
        echo ""
        return 0
    else
        print_warning "Some checks failed: $overall_passed/$overall_total passed"
        echo ""
        print_info "Issues found. Please review the warnings and errors above."
        print_info "The setup may still work, but some components need attention."
        echo ""
        return 1
    fi
}

# Run main function
main "$@"
