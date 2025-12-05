#!/bin/bash

# Grimoire Frontend Profiler Integration Script
# Run this script to integrate the profiler into your Xcode project

set -e

echo "========================================="
echo "Grimoire Frontend Profiler Integration"
echo "========================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROFILER_DIR="$PROJECT_DIR/Profiler"
XCODE_PROJECT="$PROJECT_DIR/Grimoire.xcodeproj"

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if Xcode project exists
if [ ! -d "$XCODE_PROJECT" ]; then
    print_error "Xcode project not found at $XCODE_PROJECT"
    print_info "Please run this script from the macos-app directory"
    exit 1
fi

# Check if profiler files exist
if [ ! -f "$PROFILER_DIR/FrontendProfiler.swift" ]; then
    print_error "FrontendProfiler.swift not found at $PROFILER_DIR"
    exit 1
fi

print_info "Project directory: $PROJECT_DIR"
print_info "Profiler directory: $PROFILER_DIR"
print_info "Xcode project: $XCODE_PROJECT"

# Step 1: Add profiler files to Xcode project
print_info "Adding profiler files to Xcode project..."

# Create a temporary Ruby script to modify the Xcode project
RUBY_SCRIPT=$(cat << 'RUBYEOF'
require 'xcodeproj'

project_path = ARGV[0]
profiler_dir = ARGV[1]

# Open the project
project = Xcodeproj::Project.open(project_path)

# Find the main target (assuming it's named "Grimoire")
main_target = project.targets.find { |t| t.name == "Grimoire" }
unless main_target
  puts "❌ Could not find target named 'Grimoire'"
  exit 1
end

# Add profiler files group if it doesn't exist
profiler_group = project.main_group.find_subpath("Profiler", true)
profiler_group.set_source_tree("<group>")

# Add FrontendProfiler.swift to the project
profiler_file = profiler_group.new_file("FrontendProfiler.swift")

# Add the file to the main target
main_target.add_file_references([profiler_file])

# Save the project
project.save

puts "✅ Added profiler files to Xcode project"
RUBYEOF
)

# Check if Ruby and xcodeproj gem are available
if ! command -v ruby &> /dev/null; then
    print_warning "Ruby not found. Please install Ruby to automatically add files to Xcode project."
    print_info "Manual steps:"
    print_info "1. Open $XCODE_PROJECT in Xcode"
    print_info "2. Drag FrontendProfiler.swift from $PROFILER_DIR into your project"
    print_info "3. Ensure 'Copy items if needed' is checked"
    print_info "4. Add to your main target"
else
    # Check if xcodeproj gem is installed
    if ! ruby -e "require 'xcodeproj'" 2>/dev/null; then
        print_info "Installing xcodeproj gem..."
        gem install xcodeproj --user-install
    fi

    # Run the Ruby script
    echo "$RUBY_SCRIPT" | ruby - "$XCODE_PROJECT" "$PROFILER_DIR"
fi

# Step 2: Create integration examples
print_info "Creating integration examples..."

# Create example integration files
EXAMPLE_DIR="$PROFILER_DIR/Examples"
mkdir -p "$EXAMPLE_DIR"

# Example 1: NoteManager with profiler
cat > "$EXAMPLE_DIR/NoteManager+Profiler.swift" << 'SWIFTEOF'
//
//  NoteManager+Profiler.swift
//  Grimoire Profiler Integration Example
//
//  Example of how to integrate profiler with NoteManager
//

import Foundation

extension NoteManager {

    /// Profiled version of deleteNote
    func deleteNoteWithProfiling(noteId: String, completion: @escaping (Bool) -> Void = { _ in }) {
        // Start profiling span
        let spanId = FrontendProfiler.shared.startSpan(
            operation: "deleteNote",
            component: "NoteManager",
            data: ["noteId": noteId]
        )

        // Original delete logic would go here...

        // Profile API call
        FrontendProfiler.shared.profileAPICall(
            method: "POST",
            endpoint: "/delete-note",
            noteId: noteId,
            success: true
        )

        // Send notification (profiled)
        FrontendProfiler.shared.profileNotification(
            notificationName: "NoteDeleted",
            sender: "NoteManager",
            noteId: noteId,
            success: true
        )

        NotificationCenter.default.post(
            name: NSNotification.Name("NoteDeleted"),
            object: nil,
            userInfo: ["noteId": noteId]
        )

        // End profiling span
        FrontendProfiler.shared.endSpan(
            spanId: spanId,
            eventType: .frontendNoteDelete,
            operation: "deleteNote_complete",
            data: ["noteId": noteId, "success": true]
        )

        completion(true)
    }

    /// Profiled version of createFolder
    func createFolderWithProfiling(parentId: String?, completion: @escaping (Bool) -> Void) {
        let folderId = generateFolderId(parentId: parentId)

        // Start profiling
        FrontendProfiler.shared.profileFolderCreation(
            noteId: folderId,
            parentId: parentId
        )

        // Original create folder logic would go here...

        // Simulate API call
        FrontendProfiler.shared.profileAPICall(
            method: "POST",
            endpoint: "/create-folder",
            noteId: folderId,
            success: true,
            durationMs: 150.5
        )

        // After successful creation
        FrontendProfiler.shared.profileFolderCreation(
            noteId: folderId,
            parentId: parentId,
            success: true
        )

        completion(true)
    }
}
SWIFTEOF

# Example 2: SearchManager with profiler
cat > "$EXAMPLE_DIR/SearchManager+Profiler.swift" << 'SWIFTEOF'
//
//  SearchManager+Profiler.swift
//  Grimoire Profiler Integration Example
//
//  Example of how to integrate profiler with SearchManager
//

import Foundation

extension SearchManager {

    /// Profiled version of clearResultsContainingNote
    func clearResultsContainingNoteWithProfiling(_ deletedNoteId: String) {
        DispatchQueue.main.async {
            // Profile cache operation start
            FrontendProfiler.shared.recordEvent(
                eventType: .frontendCacheClear,
                component: "SearchManager",
                operation: "clearResultsContainingNote_start",
                data: [
                    "deletedNoteId": deletedNoteId,
                    "currentCacheKeys": Array(self.searchResults.keys)
                ]
            )

            // Original cache clearing logic...
            var clearedFromNotes: [String] = []
            for (noteId, results) in self.searchResults {
                let originalCount = results.count
                let filteredResults = results.filter { $0.noteId != deletedNoteId }
                let removedCount = originalCount - filteredResults.count

                if removedCount > 0 {
                    self.searchResults[noteId] = filteredResults
                    clearedFromNotes.append("\(noteId): \(removedCount) results")
                }
            }

            // Also clear any cached results for the deleted note itself
            self.searchResults.removeValue(forKey: deletedNoteId)

            // Profile cache operation end
            FrontendProfiler.shared.recordEvent(
                eventType: .frontendCacheClear,
                component: "SearchManager",
                operation: "clearResultsContainingNote_end",
                data: [
                    "deletedNoteId": deletedNoteId,
                    "remainingCacheKeys": Array(self.searchResults.keys),
                    "clearedFromNotes": clearedFromNotes
                ]
            )
        }
    }

    /// Profiled notification setup
    func setupNotificationsWithProfiling() {
        // Listen for note deletions to clear cached search results
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("NoteDeleted"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let noteId = notification.userInfo?["noteId"] as? String {
                // Profile notification reception
                FrontendProfiler.shared.profileNotification(
                    notificationName: "NoteDeleted",
                    sender: "NoteManager",
                    noteId: noteId,
                    success: true
                )

                self?.clearResultsContainingNoteWithProfiling(noteId)
            }
        }
    }
}
SWIFTEOF

print_success "Integration examples created in $EXAMPLE_DIR"

# Step 3: Create profiler activation script
print_info "Creating profiler activation script..."

cat > "$PROJECT_DIR/activate_profiler.sh" << 'EOF'
#!/bin/bash

# Activate Grimoire Profiler
# This script enables the profiler and provides usage instructions

echo "========================================="
echo "Activating Grimoire Profiler"
echo "========================================="

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${GREEN}Profiler Activation Complete!${NC}"
echo ""
echo -e "${BLUE}Usage Instructions:${NC}"
echo ""
echo "1. Backend Profiler:"
echo "   - The profiler is automatically enabled in the backend"
echo "   - Access profiler endpoints at:"
echo "     • GET  /profiler/status      - Get profiler status"
echo "     • GET  /profiler/events      - Get profiler events"
echo "     • POST /profiler/clear       - Clear profiler data"
echo "     • GET  /profiler/export      - Export profiler data"
echo ""
echo "2. Frontend Profiler:"
echo "   - Add FrontendProfiler.swift to your Xcode project"
echo "   - Use the integration examples in Profiler/Examples/"
echo "   - Access profiler UI with ProfilerView()"
echo ""
echo "3. Debugging Folder Management Bugs:"
echo "   - Monitor folder creation events"
echo "   - Track notification flows for deletions"
echo "   - Check cache invalidation timing"
echo "   - Look for sync issues between frontend/backend"
echo ""
echo "4. Exporting Data:"
echo "   - Backend: GET /profiler/export"
echo "   - Frontend: FrontendProfiler.shared.exportToJSON()"
echo ""
echo "For detailed instructions, see:"
echo "  - Profiler/INTEGRATION_GUIDE.md"
echo "  - Profiler/Examples/"

# Check if backend is running
if curl -s http://127.0.0.1:8000/ > /dev/null; then
    echo ""
    echo -e "${GREEN}Backend is running. Profiler endpoints are available.${NC}"
else
    echo ""
    echo -e "${BLUE}Note: Backend is not running. Start it to use profiler endpoints.${NC}"
fi
