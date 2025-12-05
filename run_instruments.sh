#!/bin/bash

# Grimoire Instruments Profiling Script
# Uses Apple's Instruments tool to profile the macOS app

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

# Check if Instruments is available
check_instruments() {
    if ! command -v xcrun &> /dev/null; then
        print_error "Xcode command line tools not found"
        print_info "Install with: xcode-select --install"
        exit 1
    fi

    if ! xcrun instruments -s &> /dev/null; then
        print_error "Instruments not available"
        print_info "Make sure Xcode is installed and up to date"
        exit 1
    fi

    print_success "Instruments is available"
}

# Check if app is built
check_app_built() {
    local app_path="macos-app/Grimoire.app"

    if [ ! -d "$app_path" ]; then
        print_warning "Grimoire.app not found at $app_path"
        print_info "Building app first..."

        if [ -f "macos-app/build.sh" ]; then
            cd macos-app && ./build.sh && cd ..
        elif [ -f "macos-app/build_app.sh" ]; then
            cd macos-app && ./build_app.sh && cd ..
        else
            print_error "No build script found"
            print_info "Please build the app in Xcode first"
            exit 1
        fi
    fi

    if [ -d "$app_path" ]; then
        print_success "Grimoire.app found"
    else
        print_error "Failed to build or find Grimoire.app"
        exit 1
    fi
}

# Profile with Time Profiler
profile_time() {
    local output_file="$1"
    local duration="$2"

    print_info "Starting Time Profiler for ${duration}s..."

    xcrun xctrace record \
        --template 'Time Profiler' \
        --output "$output_file" \
        --time-limit "${duration}s" \
        --launch -- ./macos-app/Grimoire.app

    print_success "Time Profiler data saved to $output_file"
}

# Profile with System Trace
profile_system_trace() {
    local output_file="$1"
    local duration="$2"

    print_info "Starting System Trace for ${duration}s..."

    xcrun xctrace record \
        --template 'System Trace' \
        --output "$output_file" \
        --time-limit "${duration}s" \
        --launch -- ./macos-app/Grimoire.app

    print_success "System Trace data saved to $output_file"
}

# Profile with Points of Interest (for OSSignpost)
profile_points_of_interest() {
    local output_file="$1"
    local duration="$2"

    print_info "Starting Points of Interest for ${duration}s..."

    xcrun xctrace record \
        --template 'Points of Interest' \
        --output "$output_file" \
        --time-limit "${duration}s" \
        --launch -- ./macos-app/Grimoire.app

    print_success "Points of Interest data saved to $output_file"
}

# Profile with Network
profile_network() {
    local output_file="$1"
    local duration="$2"

    print_info "Starting Network Profiler for ${duration}s..."

    xcrun xctrace record \
        --template 'Network' \
        --output "$output_file" \
        --time-limit "${duration}s" \
        --launch -- ./macos-app/Grimoire.app

    print_success "Network Profiler data saved to $output_file"
}

# Profile with Allocations
profile_allocations() {
    local output_file="$1"
    local duration="$2"

    print_info "Starting Allocations Profiler for ${duration}s..."

    xcrun xctrace record \
        --template 'Allocations' \
        --output "$output_file" \
        --time-limit "${duration}s" \
        --launch -- ./macos-app/Grimoire.app

    print_success "Allocations data saved to $output_file"
}

# Open trace file in Instruments
open_trace() {
    local trace_file="$1"

    if [ -f "$trace_file" ]; then
        print_info "Opening $trace_file in Instruments..."
        open "$trace_file"
    else
        print_error "Trace file not found: $trace_file"
    fi
}

# Run specific test scenario
run_test_scenario() {
    local scenario="$1"
    local duration="${2:-30}"

    print_info "Running test scenario: $scenario"

    case "$scenario" in
        "folder-creation")
            print_info "Test: Create multiple folders"
            print_info "Instructions:"
            echo "  1. Wait for app to launch"
            echo "  2. Create 3-4 new folders"
            echo "  3. Observe folder icons"
            echo "  4. Wait for profiling to complete"
            ;;
        "note-deletion")
            print_info "Test: Delete notes with backlinks"
            print_info "Instructions:"
            echo "  1. Wait for app to launch"
            echo "  2. Create a note with content"
            echo "  3. Create another note that references it"
            echo "  4. Delete the first note"
            echo "  5. Check if backlinks update"
            ;;
        "mixed-workload")
            print_info "Test: Mixed workload"
            print_info "Instructions:"
            echo "  1. Wait for app to launch"
            echo "  2. Create folders and notes"
            echo "  3. Delete some items"
            echo "  4. Rename items"
            echo "  5. Use search functionality"
            ;;
        *)
            print_warning "Unknown scenario: $scenario"
            print_info "Available scenarios: folder-creation, note-deletion, mixed-workload"
            return 1
            ;;
    esac

    echo -e "\n${YELLOW}Press Enter when ready to start profiling...${NC}"
    read -r

    return 0
}

# Main menu
show_menu() {
    echo -e "\n${BLUE}=========================================${NC}"
    echo -e "${BLUE}Grimoire Instruments Profiler${NC}"
    echo -e "${BLUE}=========================================${NC}"
    echo ""
    echo "Select profiling template:"
    echo "  1. Time Profiler (CPU usage)"
    echo "  2. System Trace (threads, I/O, network)"
    echo "  3. Points of Interest (OSSignpost events)"
    echo "  4. Network Profiler (HTTP requests)"
    echo "  5. Allocations (memory usage)"
    echo "  6. Comprehensive (all templates)"
    echo "  7. Exit"
    echo ""
}

# Create output directory
setup_output_dir() {
    local timestamp=$(date +"%Y%m%d_%H%M%S")
    local output_dir="$HOME/Documents/GrimoireTraces/$timestamp"

    mkdir -p "$output_dir"
    echo "$output_dir"
}

# Run comprehensive profiling
run_comprehensive() {
    local duration="${1:-30}"
    local output_dir=$(setup_output_dir)

    print_info "Running comprehensive profiling for ${duration}s..."
    print_info "Output directory: $output_dir"

    # Run each profiler
    profile_time "$output_dir/TimeProfiler.trace" "$duration" &
    local time_pid=$!

    profile_system_trace "$output_dir/SystemTrace.trace" "$duration" &
    local system_pid=$!

    profile_points_of_interest "$output_dir/PointsOfInterest.trace" "$duration" &
    local points_pid=$!

    profile_network "$output_dir/Network.trace" "$duration" &
    local network_pid=$!

    profile_allocations "$output_dir/Allocations.trace" "$duration" &
    local alloc_pid=$!

    # Wait for all profilers to complete
    print_info "Waiting for profilers to complete..."
    wait $time_pid $system_pid $points_pid $network_pid $alloc_pid

    print_success "Comprehensive profiling complete"
    print_info "Trace files saved to: $output_dir"

    # Ask which trace to open
    echo ""
    echo "Which trace would you like to open?"
    echo "  1. Time Profiler"
    echo "  2. System Trace"
    echo "  3. Points of Interest"
    echo "  4. Network"
    echo "  5. Allocations"
    echo "  6. None"

    read -r -p "Select (1-6): " choice

    case $choice in
        1) open_trace "$output_dir/TimeProfiler.trace" ;;
        2) open_trace "$output_dir/SystemTrace.trace" ;;
        3) open_trace "$output_dir/PointsOfInterest.trace" ;;
        4) open_trace "$output_dir/Network.trace" ;;
        5) open_trace "$output_dir/Allocations.trace" ;;
        6) print_info "Not opening any trace files" ;;
        *) print_warning "Invalid choice" ;;
    esac
}

# Main function
main() {
    echo -e "${BLUE}Grimoire Instruments Profiling Script${NC}"
    echo "========================================="

    # Check prerequisites
    check_instruments
    check_app_built

    while true; do
        show_menu

        read -r -p "Select option (1-7): " choice

        case $choice in
            1|2|3|4|5)
                # Ask for test scenario
                echo ""
                echo "Select test scenario:"
                echo "  1. Folder creation bug"
                echo "  2. Backlinks deletion bug"
                echo "  3. Mixed workload"
                echo "  4. Custom (no specific scenario)"

                read -r -p "Select scenario (1-4): " scenario_choice

                case $scenario_choice in
                    1) scenario="folder-creation" ;;
                    2) scenario="note-deletion" ;;
                    3) scenario="mixed-workload" ;;
                    4) scenario="custom" ;;
                    *)
                        print_warning "Invalid scenario choice, using custom"
                        scenario="custom"
                        ;;
                esac

                # Ask for duration
                read -r -p "Profiling duration in seconds (default 30): " duration_input
                duration=${duration_input:-30}

                # Setup output
                output_dir=$(setup_output_dir)

                # Run test scenario instructions
                if [ "$scenario" != "custom" ]; then
                    run_test_scenario "$scenario" "$duration"
                    if [ $? -ne 0 ]; then
                        continue
                    fi
                else
                    print_info "Custom profiling for ${duration}s"
                    print_info "Interact with the app as needed"
                    echo -e "\n${YELLOW}Press Enter when ready to start profiling...${NC}"
                    read -r
                fi

                # Run selected profiler
                case $choice in
                    1)
                        output_file="$output_dir/TimeProfiler.trace"
                        profile_time "$output_file" "$duration"
                        open_trace "$output_file"
                        ;;
                    2)
                        output_file="$output_dir/SystemTrace.trace"
                        profile_system_trace "$output_file" "$duration"
                        open_trace "$output_file"
                        ;;
                    3)
                        output_file="$output_dir/PointsOfInterest.trace"
                        profile_points_of_interest "$output_file" "$duration"
                        open_trace "$output_file"
                        ;;
                    4)
                        output_file="$output_dir/Network.trace"
                        profile_network "$output_file" "$duration"
                        open_trace "$output_file"
                        ;;
                    5)
                        output_file="$output_dir/Allocations.trace"
                        profile_allocations "$output_file" "$duration"
                        open_trace "$output_file"
                        ;;
                esac
                ;;
            6)
                # Comprehensive profiling
                read -r -p "Profiling duration in seconds (default 30): " duration_input
                duration=${duration_input:-30}

                run_comprehensive "$duration"
                ;;
            7)
                print_info "Exiting..."
                exit 0
                ;;
            *)
                print_warning "Invalid option"
                ;;
        esac

        echo ""
        read -r -p "Run another profile? (y/n): " again
        if [[ ! "$again" =~ ^[Yy]$ ]]; then
            print_info "Exiting..."
            exit 0
        fi
    done
}

# Handle script arguments
if [ $# -eq 0 ]; then
    # Interactive mode
    main
else
    # Command-line mode
    case "$1" in
        "time")
            check_instruments
            check_app_built
            output_dir=$(setup_output_dir)
            profile_time "$output_dir/TimeProfiler.trace" "${2:-30}"
            ;;
        "system")
            check_instruments
            check_app_built
            output_dir=$(setup_output_dir)
            profile_system_trace "$output_dir/SystemTrace.trace" "${2:-30}"
            ;;
        "points")
            check_instruments
            check_app_built
            output_dir=$(setup_output_dir)
            profile_points_of_interest "$output_dir/PointsOfInterest.trace" "${2:-30}"
            ;;
        "network")
            check_instruments
            check_app_built
            output_dir=$(setup_output_dir)
            profile_network "$output_dir/Network.trace" "${2:-30}"
            ;;
        "allocations")
            check_instruments
            check_app_built
            output_dir=$(setup_output_dir)
            profile_allocations "$output_dir/Allocations.trace" "${2:-30}"
            ;;
        "comprehensive")
            check_instruments
            check_app_built
            run_comprehensive "${2:-30}"
            ;;
        "help")
            echo "Usage: $0 [command] [duration]"
            echo ""
            echo "Commands:"
            echo "  time          - Run Time Profiler"
            echo "  system        - Run System Trace"
            echo "  points        - Run Points of Interest"
            echo "  network       - Run Network Profiler"
            echo "  allocations   - Run Allocations Profiler"
            echo "  comprehensive - Run all profilers"
            echo "  help          - Show this help"
            echo ""
            echo "Examples:"
            echo "  $0 time 60      - Profile CPU for 60 seconds"
            echo "  $0 system       - Profile system for 30 seconds (default)"
            echo "  $0 comprehensive 45 - Comprehensive profile for 45 seconds"
            ;;
        *)
            echo "Unknown command: $1"
            echo "Use '$0 help' for usage information"
            exit 1
            ;;
    esac
fi
