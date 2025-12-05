# Debugging Tools Examples

This document provides practical examples of how to use the new debugging tools to investigate the Grimoire sidebar bugs.

## 1. Basic Debug Logging

### Simple Logging Examples:
```swift
// In NoteManager.swift or any Swift file
import Foundation

// Basic logging with different levels
logError("Backend connection failed: \(error.localizedDescription)")
logWarning("Note type is nil for note: \(noteId)")
logInfo("Successfully loaded \(count) notes")
logDebug("Creating folder with parentId: \(parentId ?? "nil")")
logVerbose("NoteRow computed body with type: \(type ?? "nil")")

// Log with file/line information (automatic)
logDebug("Folder creation started")  // Automatically includes file:line:function
```

### Conditional Logging:
```swift
// Only log in debug builds
#if DEBUG
logDebug("Debug build - extra logging enabled")
#endif

// Log based on condition
if noteInfo.type == nil {
    logWarning("Note \(noteInfo.id) has nil type field")
}
```

## 2. OSSignpost for Performance Timing

### Folder Creation Timing:
```swift
func createFolder(parentId: String?, completion: @escaping (Bool) -> Void) {
    // Start timing
    var signpostID: OSSignpostID? = nil
    if #available(macOS 10.14, *) {
        signpostID = SignpostManager.shared.beginFolderCreation("new_folder")
    }
    
    logDebug("Starting folder creation with parentId: \(parentId ?? "nil")")
    
    // ... folder creation logic ...
    
    // End timing with success/failure
    if #available(macOS 10.14, *) {
        SignpostManager.shared.endFolderCreation(signpostID!, success: success)
    }
}
```

### Measuring API Call Duration:
```swift
func callAPI(endpoint: String, completion: @escaping (Result<Data, Error>) -> Void) {
    var signpostID: OSSignpostID? = nil
    if #available(macOS 10.14, *) {
        signpostID = SignpostManager.shared.beginAPICall(endpoint)
    }
    
    let startTime = CFAbsoluteTimeGetCurrent()
    
    URLSession.shared.dataTask(with: request) { data, response, error in
        let duration = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        
        if #available(macOS 10.14, *) {
            SignpostManager.shared.endAPICall(signpostID!, durationMs: duration, success: error == nil)
        }
        
        logDebug("API call to \(endpoint) took \(String(format: "%.2f", duration))ms")
        
        // ... handle response ...
    }.resume()
}
```

### Tracking UI Rendering:
```swift
struct NoteRow: View {
    let noteInfo: NoteInfo
    
    var body: some View {
        VStack {
            // View content
        }
        .debugged(viewName: "NoteRow", noteId: noteInfo.id)
        .onAppear {
            logDebug("NoteRow appeared for note: \(noteInfo.id)")
        }
    }
}
```

## 3. Network Metrics Collection

### Automatic URLSession Metrics:
```swift
// Configure URLSession to collect metrics
let configuration = URLSessionConfiguration.default
if #available(macOS 10.12, *) {
    configuration.urlCache = nil  // Disable cache for accurate timing
}

let session = URLSession(configuration: configuration)

// Metrics are automatically collected and logged
// Check ~/Documents/GrimoireDebug.log for:
// Network Metrics: [
//   "URL": "http://127.0.0.1:8000/create-folder",
//   "Method": "POST",
//   "Duration": "152.34ms",
//   "DNS Lookup": "12.45ms",
//   "Connect Time": "45.67ms",
//   "Request Time": "23.45ms",
//   "Response Time": "70.77ms"
// ]
```

## 4. Race Condition Detection

### Checking for Concurrent Access:
```swift
class SearchManager {
    private var cache: [String: [SearchResult]] = [:]
    
    func updateCache(for noteId: String, results: [SearchResult]) {
        // This will warn if multiple threads try to update cache simultaneously
        withRaceCheck(self, operation: "updateCache") {
            cache[noteId] = results
        }
    }
    
    func clearCache() {
        // Manual race detection
        RaceConditionDetector.shared.beginOperation("clearCache")
        cache.removeAll()
        RaceConditionDetector.shared.endOperation("clearCache")
    }
}
```

## 5. Measuring Execution Time

### Using measureTime Helper:
```swift
func performExpensiveOperation() -> Result {
    return measureTime("Expensive Operation") {
        // Time-consuming operation
        var result = Result()
        for i in 0..<1000000 {
            result.process(item: i)
        }
        return result
    }
}

// Output: "Expensive Operation took 1250.34ms"
```

### Manual Timing with Logging:
```swift
let startTime = Date()
// ... operation ...
let duration = Date().timeIntervalSince(startTime) * 1000
logDebug("Operation took \(String(format: "%.2f", duration))ms")
```

## 6. Debugging Specific Bugs

### Folder Icon Bug Investigation:
```swift
struct NoteRow: View {
    let noteInfo: NoteInfo
    
    var body: some View {
        // Add debug logging for the bug
        let _ = logDebug("""
            NoteRow DEBUG: \(noteInfo.title)
            - type: \(noteInfo.type ?? "nil")
            - children count: \(noteInfo.children.count)
            - isFolder: \(noteInfo.type == "folder" || !noteInfo.children.isEmpty)
            """)
        
        // Rest of view implementation
    }
}
```

### Backlinks Bug Investigation:
```swift
class SearchManager {
    func clearResultsContainingNote(_ deletedNoteId: String) {
        logDebug("Starting cache clear for deleted note: \(deletedNoteId)")
        logDebug("Current cache keys: \(searchResults.keys.sorted())")
        
        let startTime = Date()
        
        // Clear cache logic
        
        let duration = Date().timeIntervalSince(startTime) * 1000
        logDebug("Cache clear completed in \(String(format: "%.2f", duration))ms")
        logDebug("Remaining cache keys: \(searchResults.keys.sorted())")
    }
}
```

## 7. Using Instruments with OSSignpost

### Viewing Signposts in Instruments:
1. **Launch Instruments** and choose "Points of Interest" template
2. **Record** while reproducing the bug
3. **Look for** these signpost intervals:
   - "Folder Creation" - Folder creation timing
   - "Note Deletion" - Note deletion flow
   - "API Call" - Network request timing
   - "UI Render" - View rendering performance
   - "Cache Operation" - Cache clearing timing

### Command Line for Signpost Logs:
```bash
# View real-time signpost events
log stream --predicate 'subsystem == "com.grimoire.app"'

# View historical signpost events
log show --predicate 'subsystem == "com.grimoire.app"' --last 1h --info --debug
```

## 8. Backend Profiling Examples

### Using Python Profiling Script:
```bash
# Profile folder creation endpoint
python profile_backend.py

# Select option 2 for folder creation flow
# This will:
# 1. Create test folders
# 2. Measure API response times
# 3. Generate timing statistics
# 4. Save results to JSON file

# Or use command line:
python profile_backend.py 2  # Profile folder creation
```

### Manual Backend Timing:
```python
# In backend/main.py
import time

@app.post("/create-folder")
async def create_folder(request: CreateFolderRequest):
    start_time = time.time()
    
    # ... folder creation logic ...
    
    duration = (time.time() - start_time) * 1000
    print(f"create-folder took {duration:.2f}ms")
    
    return {"success": True, "folder_id": folder_id}
```

## 9. Debug View in SwiftUI

### Adding Debug Overlay:
```swift
struct ContentView: View {
    @StateObject private var noteManager = NoteManager()
    
    var body: some View {
        SidebarView()
            .environmentObject(noteManager)
            .debugged(viewName: "ContentView")
            .overlay(
                // Optional debug overlay
                DebugOverlayView()
                    .opacity(0.3)
            )
    }
}

struct DebugOverlayView: View {
    var body: some View {
        VStack {
            Text("Debug Mode")
                .font(.caption)
                .foregroundColor(.white)
                .padding(4)
                .background(Color.red.opacity(0.7))
                .cornerRadius(4)
            Spacer()
        }
        .padding()
    }
}
```

## 10. Log File Analysis

### Viewing Logs:
```bash
# Tail logs in real-time
tail -f ~/Documents/GrimoireDebug.log

# Search for specific patterns
grep "ERROR" ~/Documents/GrimoireDebug.log
grep "Folder creation" ~/Documents/GrimoireDebug.log
grep "took.*ms" ~/Documents/GrimoireDebug.log

# Count log entries by level
grep -c "\[ERROR\]" ~/Documents/GrimoireDebug.log
grep -c "\[WARNING\]" ~/Documents/GrimoireDebug.log
grep -c "\[DEBUG\]" ~/Documents/GrimoireDebug.log
```

### Parsing Logs Programmatically:
```swift
func analyzeLogs() {
    let logURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        .first!
        .appendingPathComponent("GrimoireDebug.log")
    
    if let logContent = try? String(contentsOf: logURL) {
        let lines = logContent.components(separatedBy: "\n")
        
        // Find all API call durations
        let apiCalls = lines.filter { $0.contains("API call") }
        let durations = apiCalls.compactMap { line -> Double? in
            if let range = line.range(of: "took (\\d+\\.\\d+)ms", options: .regularExpression) {
                let durationStr = line[range]
                    .replacingOccurrences(of: "took ", with: "")
                    .replacingOccurrences(of: "ms", with: "")
                return Double(durationStr)
            }
            return nil
        }
        
        if !durations.isEmpty {
            let average = durations.reduce(0, +) / Double(durations.count)
            logInfo("Average API call duration: \(String(format: "%.2f", average))ms")
        }
    }
}
```

## 11. Quick Reference Commands

### For Folder Icon Bug:
```bash
# 1. Enable detailed logging
#    (Already done in DebugTools.swift with .debug level)

# 2. Reproduce bug and check logs
tail -f ~/Documents/GrimoireDebug.log | grep -E "(NoteRow|type:|folder)"

# 3. Profile with Instruments
./run_instruments.sh points 30

# 4. Check API response time
curl -X POST http://127.0.0.1:8000/create-folder \
  -H "Content-Type: application/json" \
  -d '{"folder_path":"test"}' \
  -w "Time: %{time_total}s\n"
```

### For Backlinks Bug:
```bash
# 1. Enable Thread Sanitizer in Xcode scheme
#    Edit Scheme → Run → Diagnostics → Thread Sanitizer

# 2. Check cache clearing timing
tail -f ~/Documents/GrimoireDebug.log | grep -E "(cache|Cache|deleted)"

# 3. Profile deletion flow
./run_instruments.sh system 30

# 4. Monitor network during deletion
./run_instruments.sh network 30
```

## 12. Common Debugging Patterns

### Timing Critical Sections:
```swift
func criticalOperation() {
    let signpostID = SignpostManager.shared.beginCacheOperation("critical_section")
    defer {
        SignpostManager.shared.endCacheOperation(signpostID, success: true)
    }
    
    // Critical code here
}
```

### Debugging Async Operations:
```swift
func asyncOperation(completion: @escaping (Result) -> Void) {
    logDebug("Starting async operation")
    
    DispatchQueue.global().async {
        let result = measureTime("Async Work") {
            return performWork()
        }
        
        DispatchQueue.main.async {
            logDebug("Async operation completed")
            completion(result)
        }
    }
}
```

### Memory Debugging:
```swift
func checkMemoryUsage() {
    #if DEBUG
    let memoryUsed = report_memory()
    logDebug("Memory usage: \(memoryUsed) MB")
    
    if memoryUsed > 100 {
        logWarning("High memory usage detected: \(memoryUsed) MB")
    }
    #endif
}

func report_memory() -> UInt64 {
    var taskInfo = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info>.size) / 4
    let result: kern_return_t = withUnsafeMutablePointer(to: &taskInfo) {
        $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
            task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
        }
    }
    
    if result == KERN_SUCCESS {
        return UInt64(taskInfo.phys_footprint) / 1024 / 1024
    }
    return 0
}
```

These examples demonstrate how to use the new debugging tools to investigate the sidebar bugs effectively. The tools provide comprehensive visibility into timing, performance, and concurrency issues without the maintenance burden of a custom profiler.