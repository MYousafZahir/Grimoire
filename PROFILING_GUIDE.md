# Profiling Guide for Grimoire Sidebar Bugs

This guide explains how to use existing Apple and Python profiling tools to diagnose and fix the sidebar bugs in Grimoire, replacing the custom profiler with industry-standard solutions.

## Overview

Instead of maintaining a custom profiler, we now use:
1. **Instruments** (Apple's official profiling tool)
2. **OSSignpost** (for precise timing measurements)
3. **Thread Sanitizer** (for race condition detection)
4. **URLSession metrics** (for network timing)
5. **Python cProfile/py-spy** (for backend profiling)

## 1. Diagnosing the Folder Icon Bug

### Symptoms
- New folders show note icon (📄) instead of folder icon (📁)
- Icon corrects itself after a brief delay

### Using Instruments to Diagnose

#### Step 1: Launch Instruments
```bash
# Open Xcode Instruments
open -a Instruments
```

#### Step 2: Create a Time Profiler Template
1. Select "Time Profiler" template
2. Choose "Grimoire.app" as target
3. Click Record

#### Step 3: Reproduce the Bug
1. Create a new folder in the sidebar
2. Watch for the incorrect icon display
3. Wait for it to correct

#### Step 4: Analyze Results
Look for:
- **UI Rendering delays**: Check `NoteRow.body` computation time
- **Network latency**: Look for `/create-folder` API call duration
- **Thread transitions**: Note any main thread blocking

#### Step 5: Use System Trace for Detailed Analysis
1. Create "System Trace" template in Instruments
2. Record folder creation
3. Analyze:
   - Thread states (running, waiting, blocked)
   - Queue operations (GCD)
   - Network request timing

### Using OSSignpost Integration

Our code now includes OSSignpost markers. To view them:

1. **In Instruments**:
   - Use "Points of Interest" template
   - Or add "os_signpost" instrument to any template

2. **Console.app**:
   ```bash
   # Filter for signposts
   log stream --predicate 'subsystem == "com.grimoire.app"'
   ```

3. **Key signposts to monitor**:
   - `Folder Creation` - Tracks folder creation timing
   - `UI Render` - Tracks NoteRow rendering
   - `API Call` - Tracks network requests

### Debugging Steps

1. **Check timing between events**:
   ```swift
   // Enable detailed logging
   logDebug("NoteRow rendering - type: \(noteInfo.type ?? "nil")")
   ```

2. **Measure API response time**:
   ```bash
   # Check backend response time
   curl -X POST http://127.0.0.1:8000/create-folder \
     -H "Content-Type: application/json" \
     -d '{"folder_path":"test_folder"}' \
     -w "Time: %{time_total}s\n"
   ```

3. **Verify optimistic updates**:
   - The folder should appear immediately with type="folder"
   - Check console for "Adding optimistic folder to UI" log

## 2. Diagnosing Backlinks Bug

### Symptoms
- Deleted notes/folders still appear in semantic backlinks
- Backlinks clear after delay or app restart

### Using Thread Sanitizer for Race Conditions

#### Step 1: Enable Thread Sanitizer
1. Open Grimoire.xcodeproj in Xcode
2. Edit scheme → Run → Diagnostics
3. Enable "Thread Sanitizer"

#### Step 2: Reproduce the Bug
1. Create a note with content
2. Create another note that references it
3. Delete the first note
4. Check if backlinks still show the deleted note

#### Step 3: Analyze Results
Thread Sanitizer will report:
- Data races on shared state (like `searchResults`)
- Race conditions between notification handlers
- Unsafe concurrent cache access

#### Step 4: Fix Identified Issues
Common fixes:
- Use `@MainActor` for UI updates
- Use thread-safe collections
- Add proper synchronization

### Using Instruments System Trace

1. **Record deletion flow**:
   - Start System Trace recording
   - Delete a note with backlinks
   - Stop recording

2. **Analyze the trace**:
   - Look for `NoteDeleted` notification timing
   - Check `clearResultsContainingNote` execution
   - Identify gaps between notification and cache clearing

3. **Key metrics to check**:
   - Time between `deleteNote` API call and response
   - Time between notification and cache clearing
   - Thread switches during the process

### Debugging Steps

1. **Check cache clearing timing**:
   ```swift
   // Add timing logs
   let startTime = Date()
   clearResultsContainingNote(deletedNoteId)
   let duration = Date().timeIntervalSince(startTime)
   logDebug("Cache clearing took \(duration * 1000)ms")
   ```

2. **Verify notification order**:
   ```swift
   // Add notification logging
   NotificationCenter.default.addObserver(
       forName: NSNotification.Name("NoteDeleted"),
       object: nil,
       queue: .main
   ) { notification in
       logDebug("NoteDeleted received: \(notification.userInfo?["noteId"] ?? "unknown")")
   }
   ```

3. **Test with slow network simulation**:
   ```bash
   # Use Network Link Conditioner
   # Available from Apple Developer website
   # Simulate 3G or High Latency DNS
   ```

## 3. Backend Profiling

### Using Python cProfile

```python
# Profile the create-folder endpoint
python -m cProfile -o create_folder.prof backend/main.py

# Analyze with snakeviz
pip install snakeviz
snakeviz create_folder.prof
```

### Using py-spy for Real-time Profiling

```bash
# Install py-spy
pip install py-spy

# Profile the running backend
py-spy top --pid $(pgrep -f "uvicorn main:app")

# Record a profile
py-spy record -o profile.svg --pid $(pgrep -f "uvicorn main:app")
```

### Key Backend Metrics to Monitor

1. **API endpoint response times**:
   ```python
   # Add timing to FastAPI endpoints
   import time
   
   @app.post("/create-folder")
   async def create_folder(request: CreateFolderRequest):
       start_time = time.time()
       # ... endpoint logic ...
       duration = time.time() - start_time
       print(f"create-folder took {duration * 1000:.2f}ms")
   ```

2. **Database/File operations**:
   - File write times for note storage
   - JSON serialization/deserialization
   - Directory traversal for note tree

## 4. Network Profiling

### Using Instruments Network Profiler

1. **Launch Network Profiler**:
   - Open Instruments
   - Choose "Network" template
   - Record network activity

2. **Key metrics to monitor**:
   - Request/response timing
   - Payload sizes
   - Connection establishment time
   - DNS lookup time

### Using URLSession Metrics

Our code now collects URLSession metrics automatically. Check logs for:
```
Network Metrics: [
  "URL": "http://127.0.0.1:8000/create-folder",
  "Method": "POST",
  "Duration": "152.34ms",
  "DNS Lookup": "12.45ms",
  "Connect Time": "45.67ms",
  "Request Time": "23.45ms",
  "Response Time": "70.77ms"
]
```

## 5. Memory and Performance Issues

### Using Instruments Allocations

1. **Check for memory leaks**:
   - Use "Allocations" template
   - Look for persistent `NoteInfo` objects
   - Check for cache bloat

2. **Monitor cache growth**:
   ```swift
   // Log cache size periodically
   func logCacheStats() {
       let totalResults = searchResults.values.reduce(0) { $0 + $1.count }
       logDebug("Cache stats: \(searchResults.count) notes, \(totalResults) total results")
   }
   ```

### Using SwiftUI Preview Debugging

1. **Debug NoteRow rendering**:
   ```swift
   struct NoteRow_Previews: PreviewProvider {
       static var previews: some View {
           NoteRow(
               noteInfo: NoteInfo(
                   id: "test_folder",
                   title: "Test Folder",
                   path: "",
                   children: [],
                   type: nil  // Simulate the bug
               ),
               // ... other parameters ...
           )
           .debugged(viewName: "NoteRowPreview", noteId: "test_folder")
       }
   }
   ```

2. **Use Xcode View Debugger**:
   - Run app in debug mode
   - Click "Debug View Hierarchy" in Xcode
   - Inspect NoteRow view properties

## 6. Automated Testing with Profiling

### Unit Tests with Performance Metrics

```swift
func testFolderCreationPerformance() {
    measure {
        let expectation = self.expectation(description: "Folder created")
        noteManager.createFolder(parentId: nil) { success in
            XCTAssertTrue(success)
            expectation.fulfill()
        }
        waitForExpectations(timeout: 5.0)
    }
}
```

### Integration Test Script

```bash
#!/bin/bash
# test_sidebar_bugs.sh

echo "Testing folder creation..."
# Time folder creation
time curl -X POST http://127.0.0.1:8000/create-folder \
  -H "Content-Type: application/json" \
  -d '{"folder_path":"test_perf"}' \
  -s -o /dev/null

echo -e "\nTesting note deletion with backlinks..."
# Create two linked notes, delete one, check backlinks
python test_backlinks_scenario.py
```

## 7. Common Fixes Based on Profiling Results

### For Folder Icon Bug:

1. **Optimistic UI updates**:
   ```swift
   // Already implemented:
   // - Set type="folder" optimistically
   // - Add to tree immediately
   // - Show loading state if type is nil
   ```

2. **Reduce API latency**:
   - Optimize backend folder creation
   - Use HTTP/2 if available
   - Implement request batching

### For Backlinks Bug:

1. **Immediate cache invalidation**:
   ```swift
   // Clear cache when deletion starts, not when it completes
   func deleteNote(noteId: String) {
       clearSearchCacheForNoteImmediately(noteId)  // Optimistic clearing
       // ... proceed with deletion ...
   }
   ```

2. **Thread-safe cache operations**:
   ```swift
   // Use dispatch queues for thread safety
   private let cacheQueue = DispatchQueue(label: "...", attributes: .concurrent)
   ```

## 8. Continuous Monitoring

### Add Performance Regression Tests

```swift
class PerformanceTests: XCTestCase {
    func testFolderCreationUnder100ms() {
        measureMetrics([.wallClockTime], automaticallyStartMeasuring: false) {
            let expectation = self.expectation(description: "Folder creation")
            
            startMeasuring()
            noteManager.createFolder(parentId: nil) { success in
                self.stopMeasuring()
                XCTAssertTrue(success)
                expectation.fulfill()
            }
            
            waitForExpectations(timeout: 1.0)  // Should complete in under 1 second
        }
    }
}
```

### Monitor in Production

1. **Use MetricKit** (for App Store distribution):
   ```swift
   import MetricKit
   
   class MetricsCollector: MXMetricManagerSubscriber {
       func didReceive(_ payloads: [MXMetricPayload]) {
           // Analyze performance metrics
       }
   }
   ```

2. **Custom metrics endpoint**:
   ```python
   # Backend metrics endpoint
   @app.get("/metrics")
   async def get_metrics():
       return {
           "active_connections": count_connections(),
           "avg_response_time": calculate_avg_response_time(),
           "error_rate": calculate_error_rate()
       }
   ```

## 9. Quick Reference Commands

### Swift/Instruments Commands:
```bash
# Profile with Instruments from command line
xcrun xctrace record --template 'Time Profiler' --launch -- /path/to/Grimoire.app

# Export signpost data
log show --predicate 'subsystem == "com.grimoire.app"' --last 1h --info --debug

# Memory debugging
xcrun xctrace record --template 'Allocations' --launch -- /path/to/Grimoire.app
```

### Python Profiling Commands:
```bash
# CPU profiling
python -m cProfile -s time backend/main.py

# Memory profiling
python -m memory_profiler backend/main.py

# Line-by-line profiling
kernprof -l -v backend/main.py
```

### Network Testing:
```bash
# Test backend response time
ab -n 100 -c 10 -p test_folder.json -T 'application/json' http://127.0.0.1:8000/create-folder

# Monitor network traffic
tcpdump -i lo0 port 8000 -w grimoire_network.pcap
```

## 10. Troubleshooting Checklist

### Folder Icon Issues:
- [ ] Check if `type` field is `nil` in NoteRow
- [ ] Verify optimistic folder creation is working
- [ ] Measure API response time for `/create-folder`
- [ ] Check for main thread blocking during UI render

### Backlinks Issues:
- [ ] Enable Thread Sanitizer to detect races
- [ ] Verify cache is cleared immediately on deletion
- [ ] Check notification timing with System Trace
- [ ] Test with slow network simulation

### General Performance:
- [ ] Profile with Instruments Time Profiler
- [ ] Check memory usage with Allocations
- [ ] Monitor network requests with Network Profiler
- [ ] Review backend response times

## Conclusion

By using these existing profiling tools instead of maintaining a custom profiler, you get:

1. **Industry-standard tools** with extensive documentation
2. **Better performance** (no custom profiler overhead)
3. **Easier collaboration** (standard tools everyone knows)
4. **Future-proofing** (tools maintained by Apple/Python community)

The key is to use the right tool for each job:
- **Instruments** for comprehensive performance analysis
- **OSSignpost** for precise timing of specific operations
- **Thread Sanitizer** for race condition detection
- **Python profilers** for backend optimization

Start with the simplest tool that can answer your question, and only move to more complex tools when needed.