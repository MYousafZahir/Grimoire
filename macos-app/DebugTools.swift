//
//  DebugTools.swift
//  Grimoire
//
//  Debugging tools using existing Apple frameworks instead of custom profiler.
//

import Foundation
import SwiftUI
import os.signpost

// MARK: - Debug Configuration

struct DebugConfig {
    static let isDebugEnabled = true
    static let logLevel: LogLevel = .debug

    enum LogLevel: Int {
        case error = 0
        case warning = 1
        case info = 2
        case debug = 3
        case verbose = 4
    }
}

// MARK: - OSSignpost Manager for Performance Tracing

@available(macOS 10.14, *)
class SignpostManager {
    static let shared = SignpostManager()

    private let log = OSLog(
        subsystem: "com.grimoire.app",
        category: "Performance"
    )

    private let sidebarLog = OSLog(
        subsystem: "com.grimoire.app",
        category: "Sidebar"
    )

    private let networkLog = OSLog(
        subsystem: "com.grimoire.app",
        category: "Network"
    )

    private let cacheLog = OSLog(
        subsystem: "com.grimoire.app",
        category: "Cache"
    )

    // MARK: - Public API

    func beginFolderCreation(_ folderId: String) -> OSSignpostID {
        let signpostID = OSSignpostID(log: sidebarLog, object: folderId as NSString)
        os_signpost(
            .begin, log: sidebarLog, name: "Folder Creation", signpostID: signpostID,
            "Folder ID: %{public}@", folderId)
        return signpostID
    }

    func endFolderCreation(_ signpostID: OSSignpostID, success: Bool) {
        os_signpost(
            .end, log: sidebarLog, name: "Folder Creation", signpostID: signpostID,
            "Success: %{public}@", success ? "true" : "false")
    }

    func beginNoteDeletion(_ noteId: String) -> OSSignpostID {
        let signpostID = OSSignpostID(log: sidebarLog, object: noteId as NSString)
        os_signpost(
            .begin, log: sidebarLog, name: "Note Deletion", signpostID: signpostID,
            "Note ID: %{public}@", noteId)
        return signpostID
    }

    func endNoteDeletion(_ signpostID: OSSignpostID, success: Bool) {
        os_signpost(
            .end, log: sidebarLog, name: "Note Deletion", signpostID: signpostID,
            "Success: %{public}@", success ? "true" : "false")
    }

    func beginAPICall(_ endpoint: String) -> OSSignpostID {
        let signpostID = OSSignpostID(log: networkLog, object: endpoint as NSString)
        os_signpost(
            .begin, log: networkLog, name: "API Call", signpostID: signpostID,
            "Endpoint: %{public}@", endpoint)
        return signpostID
    }

    func endAPICall(_ signpostID: OSSignpostID, durationMs: Double, success: Bool) {
        os_signpost(
            .end, log: networkLog, name: "API Call", signpostID: signpostID,
            "Duration: %.2fms, Success: %{public}@", durationMs, success ? "true" : "false")
    }

    func beginUIRender(_ viewName: String, noteId: String? = nil) -> OSSignpostID {
        let object = noteId ?? viewName
        let signpostID = OSSignpostID(log: sidebarLog, object: object as NSString)
        let noteInfo = noteId != nil ? "Note ID: \(noteId!)" : ""
        os_signpost(
            .begin, log: sidebarLog, name: "UI Render", signpostID: signpostID,
            "View: %{public}@ %{public}@", viewName, noteInfo)
        return signpostID
    }

    func endUIRender(_ signpostID: OSSignpostID) {
        os_signpost(.end, log: sidebarLog, name: "UI Render", signpostID: signpostID)
    }

    func beginCacheOperation(_ operation: String, key: String? = nil) -> OSSignpostID {
        let object = key ?? operation
        let signpostID = OSSignpostID(log: cacheLog, object: object as NSString)
        let keyInfo = key != nil ? "Key: \(key!)" : ""
        os_signpost(
            .begin, log: cacheLog, name: "Cache Operation", signpostID: signpostID,
            "Operation: %{public}@ %{public}@", operation, keyInfo)
        return signpostID
    }

    func endCacheOperation(_ signpostID: OSSignpostID, success: Bool) {
        os_signpost(
            .end, log: cacheLog, name: "Cache Operation", signpostID: signpostID,
            "Success: %{public}@", success ? "true" : "false")
    }

    func event(_ name: String, message: String) {
        os_signpost(.event, log: sidebarLog, name: "Event", "%{public}@: %{public}@", name, message)
    }

    func measureInterval<T>(_ name: String, operation: () throws -> T) rethrows -> T {
        let signpostID = OSSignpostID(log: sidebarLog)
        os_signpost(
            .begin, log: sidebarLog, name: "Interval", signpostID: signpostID,
            "Operation: %{public}@", name)

        let startTime = CFAbsoluteTimeGetCurrent()
        let result = try operation()
        let endTime = CFAbsoluteTimeGetCurrent()

        os_signpost(
            .end, log: sidebarLog, name: "Interval", signpostID: signpostID,
            "Duration: %.2fms", (endTime - startTime) * 1000)

        return result
    }
}

// MARK: - Simple Debug Logger

class DebugLogger {
    static let shared = DebugLogger()

    private let queue = DispatchQueue(label: "com.grimoire.debuglogger", qos: .utility)
    private let logFileURL: URL

    private init() {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
            .first!
        logFileURL = documentsPath.appendingPathComponent("GrimoireDebug.log")
        print("Debug log file: \(logFileURL.path)")
    }

    func log(
        _ message: String, level: DebugConfig.LogLevel = .info, file: String = #file,
        line: Int = #line, function: String = #function
    ) {
        guard DebugConfig.isDebugEnabled && level.rawValue <= DebugConfig.logLevel.rawValue else {
            return
        }

        queue.async {
            let timestamp = DateFormatter.localizedString(
                from: Date(), dateStyle: .medium, timeStyle: .medium)
            let fileName = (file as NSString).lastPathComponent
            let logMessage =
                "[\(timestamp)] [\(level)] [\(fileName):\(line) \(function)] \(message)\n"

            // Print to console
            print(logMessage, terminator: "")

            // Write to file
            if let data = logMessage.data(using: .utf8) {
                if FileManager.default.fileExists(atPath: self.logFileURL.path) {
                    if let fileHandle = try? FileHandle(forWritingTo: self.logFileURL) {
                        fileHandle.seekToEndOfFile()
                        fileHandle.write(data)
                        fileHandle.closeFile()
                    }
                } else {
                    try? data.write(to: self.logFileURL, options: .atomic)
                }
            }
        }
    }

    func error(
        _ message: String, file: String = #file, line: Int = #line, function: String = #function
    ) {
        log(message, level: .error, file: file, line: line, function: function)
    }

    func warning(
        _ message: String, file: String = #file, line: Int = #line, function: String = #function
    ) {
        log(message, level: .warning, file: file, line: line, function: function)
    }

    func info(
        _ message: String, file: String = #file, line: Int = #line, function: String = #function
    ) {
        log(message, level: .info, file: file, line: line, function: function)
    }

    func debug(
        _ message: String, file: String = #file, line: Int = #line, function: String = #function
    ) {
        log(message, level: .debug, file: file, line: line, function: function)
    }

    func verbose(
        _ message: String, file: String = #file, line: Int = #line, function: String = #function
    ) {
        log(message, level: .verbose, file: file, line: line, function: function)
    }
}

// MARK: - Debug View Modifier for SwiftUI

struct DebugViewModifier: ViewModifier {
    let viewName: String
    let noteId: String?

    @State private var renderStartTime: CFAbsoluteTime?

    func body(content: Content) -> some View {
        content
            .onAppear {
                if #available(macOS 10.14, *) {
                    let _ = SignpostManager.shared.beginUIRender(viewName, noteId: noteId)
                }
                renderStartTime = CFAbsoluteTimeGetCurrent()
                DebugLogger.shared.debug(
                    "View appeared: \(viewName)\(noteId != nil ? " (noteId: \(noteId!))" : "")")
            }
            .onDisappear {
                if #available(macOS 10.14, *) {
                    if let renderStartTime = renderStartTime {
                        let duration = (CFAbsoluteTimeGetCurrent() - renderStartTime) * 1000
                        DebugLogger.shared.debug(
                            "View disappeared: \(viewName) - Duration: \(String(format: "%.2f", duration))ms"
                        )
                    }
                    // Note: We can't end the signpost here because we don't have the ID
                    // In practice, use separate begin/end calls for critical paths
                }
            }
    }
}

extension View {
    func debugged(viewName: String, noteId: String? = nil) -> some View {
        modifier(DebugViewModifier(viewName: viewName, noteId: noteId))
    }
}

// MARK: - URLSession Metrics Integration

class NetworkMetricsCollector {
    static let shared = NetworkMetricsCollector()

    private var metrics: [String: URLSessionTaskMetrics] = [:]
    private let queue = DispatchQueue(label: "com.grimoire.networkmetrics")

    func recordMetrics(_ metrics: URLSessionTaskMetrics, for request: URLRequest) {
        queue.async {
            let key = self.requestKey(for: request)
            self.metrics[key] = metrics

            // Log network timing
            self.logMetrics(metrics, request: request)
        }
    }

    private func requestKey(for request: URLRequest) -> String {
        return "\(request.httpMethod ?? "GET")_\(request.url?.absoluteString ?? "unknown")"
    }

    private func logMetrics(_ metrics: URLSessionTaskMetrics, request: URLRequest) {
        let taskInterval = metrics.taskInterval
        let duration = taskInterval.duration * 1000  // Convert to ms

        var metricsInfo = [
            "URL": request.url?.absoluteString ?? "unknown",
            "Method": request.httpMethod ?? "GET",
            "Duration": String(format: "%.2fms", duration),
            "Redirect Count": "\(metrics.redirectCount)",
        ]

        if let transactionMetrics = metrics.transactionMetrics.last {
            metricsInfo["Network Protocol"] = transactionMetrics.networkProtocolName
            metricsInfo["Resource Fetch Type"] = "\(transactionMetrics.resourceFetchType)"

            if let domainLookupStart = transactionMetrics.domainLookupStartDate,
                let domainLookupEnd = transactionMetrics.domainLookupEndDate
            {
                let dnsTime = domainLookupEnd.timeIntervalSince(domainLookupStart) * 1000
                metricsInfo["DNS Lookup"] = String(format: "%.2fms", dnsTime)
            }

            if let connectStart = transactionMetrics.connectStartDate,
                let connectEnd = transactionMetrics.connectEndDate
            {
                let connectTime = connectEnd.timeIntervalSince(connectStart) * 1000
                metricsInfo["Connect Time"] = String(format: "%.2fms", connectTime)
            }

            if let requestStart = transactionMetrics.requestStartDate,
                let requestEnd = transactionMetrics.requestEndDate
            {
                let requestTime = requestEnd.timeIntervalSince(requestStart) * 1000
                metricsInfo["Request Time"] = String(format: "%.2fms", requestTime)
            }

            if let responseStart = transactionMetrics.responseStartDate,
                let responseEnd = transactionMetrics.responseEndDate
            {
                let responseTime = responseEnd.timeIntervalSince(responseStart) * 1000
                metricsInfo["Response Time"] = String(format: "%.2fms", responseTime)
            }
        }

        DebugLogger.shared.debug("Network Metrics: \(metricsInfo)")

        if #available(macOS 10.14, *) {
            SignpostManager.shared.event(
                "Network Request",
                message:
                    "\(request.url?.absoluteString ?? "unknown") - \(String(format: "%.2fms", duration))"
            )
        }
    }

    func getMetrics(for request: URLRequest) -> URLSessionTaskMetrics? {
        return queue.sync {
            let key = requestKey(for: request)
            return metrics[key]
        }
    }

    func clear() {
        queue.async {
            self.metrics.removeAll()
        }
    }
}

// MARK: - Race Condition Detection Helpers

class RaceConditionDetector {
    static let shared = RaceConditionDetector()

    private let queue = DispatchQueue(label: "com.grimoire.racedetector")
    private var operations: [String: (startTime: Date, threadId: UInt64)] = [:]

    func beginOperation(_ operationId: String, file: String = #file, line: Int = #line) {
        queue.async {
            let threadId = pthread_mach_thread_np(pthread_self())

            if let existing = self.operations[operationId] {
                DebugLogger.shared.warning(
                    """
                    Potential race condition detected for operation: \(operationId)
                    - Previous started at: \(existing.startTime) on thread: \(existing.threadId)
                    - New started at: \(Date()) on thread: \(threadId)
                    - File: \(file), Line: \(line)
                    """)
            }

            self.operations[operationId] = (Date(), threadId)
        }
    }

    func endOperation(_ operationId: String) {
        queue.async {
            self.operations.removeValue(forKey: operationId)
        }
    }

    func checkConcurrentAccess<T>(
        to object: T, operation: String, file: String = #file, line: Int = #line
    ) {
        let objectId =
            "\(type(of: object))_\(Unmanaged.passUnretained(object as AnyObject).toOpaque())"
        beginOperation("\(operation)_\(objectId)", file: file, line: line)

        // Use defer to ensure we always end the operation
        defer {
            endOperation("\(operation)_\(objectId)")
        }
    }
}

// MARK: - Convenience Macros

/// Log an error message
func logError(
    _ message: String, file: String = #file, line: Int = #line, function: String = #function
) {
    DebugLogger.shared.error(message, file: file, line: line, function: function)
}

/// Log a warning message
func logWarning(
    _ message: String, file: String = #file, line: Int = #line, function: String = #function
) {
    DebugLogger.shared.warning(message, file: file, line: line, function: function)
}

/// Log an info message
func logInfo(
    _ message: String, file: String = #file, line: Int = #line, function: String = #function
) {
    DebugLogger.shared.info(message, file: file, line: line, function: function)
}

/// Log a debug message
func logDebug(
    _ message: String, file: String = #file, line: Int = #line, function: String = #function
) {
    DebugLogger.shared.debug(message, file: file, line: line, function: function)
}

/// Measure execution time of a block
func measureTime<T>(_ name: String, operation: () throws -> T) rethrows -> T {
    if #available(macOS 10.14, *) {
        return try SignpostManager.shared.measureInterval(name, operation: operation)
    } else {
        let startTime = CFAbsoluteTimeGetCurrent()
        let result = try operation()
        let endTime = CFAbsoluteTimeGetCurrent()
        DebugLogger.shared.debug(
            "\(name) took \(String(format: "%.2f", (endTime - startTime) * 1000))ms")
        return result
    }
}

/// Check for race conditions when accessing an object
func withRaceCheck<T, R>(
    _ object: T, operation: String, file: String = #file, line: Int = #line, block: () throws -> R
) rethrows -> R {
    RaceConditionDetector.shared.checkConcurrentAccess(
        to: object, operation: operation, file: file, line: line)
    return try block()
}
