//
//  Logger+SojuKit.swift
//  SojuKit
//
//  Created on 2026-01-07.
//

import Foundation
import os.log

// MARK: - Log Level

public enum LogLevel: String, Codable, CaseIterable {
    case debug = "DEBUG"
    case info = "INFO"
    case warning = "WARNING"
    case error = "ERROR"
    case critical = "CRITICAL"

    var osLogType: OSLogType {
        switch self {
        case .debug: return .debug
        case .info: return .info
        case .warning: return .default
        case .error: return .error
        case .critical: return .fault
        }
    }

    var priority: Int {
        switch self {
        case .debug: return 0
        case .info: return 1
        case .warning: return 2
        case .error: return 3
        case .critical: return 4
        }
    }
}

// MARK: - Log Configuration

public class LogConfig: ObservableObject {
    @Published public var enableFileLogging: Bool {
        didSet { save() }
    }
    @Published public var enableConsoleLogging: Bool {
        didSet { save() }
    }
    @Published public var minimumLogLevel: LogLevel {
        didSet { save() }
    }

    nonisolated(unsafe) public static let shared = LogConfig()

    private init() {
        self.enableFileLogging = UserDefaults.standard.object(forKey: "log.enableFile") as? Bool ?? true
        self.enableConsoleLogging = UserDefaults.standard.object(forKey: "log.enableConsole") as? Bool ?? true

        if let levelRaw = UserDefaults.standard.string(forKey: "log.minimumLevel"),
           let level = LogLevel(rawValue: levelRaw) {
            self.minimumLogLevel = level
        } else {
            self.minimumLogLevel = .info
        }
    }

    private func save() {
        UserDefaults.standard.set(enableFileLogging, forKey: "log.enableFile")
        UserDefaults.standard.set(enableConsoleLogging, forKey: "log.enableConsole")
        UserDefaults.standard.set(minimumLogLevel.rawValue, forKey: "log.minimumLevel")
    }
}

// MARK: - Logger Extension

extension Logger {
    /// Logger for SojuKit framework
    public static let sojuKit = Logger(
        subsystem: "com.soju.app",
        category: "SojuKit"
    )

    // MARK: - File Logging

    /// Log file URL in app container
    public static let logFileURL: URL = {
        // Use app container for Sandbox compatibility
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let logsDir = appSupport.appendingPathComponent("Soju").appendingPathComponent("Logs")

        // Create directory if it doesn't exist
        try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)

        return logsDir.appendingPathComponent("soju.log")
    }()

    /// Enhanced logging with category support and level filtering
    public func log(
        _ message: String,
        level: LogLevel = .info,
        category: String? = nil,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        let config = LogConfig.shared

        // Level filtering
        guard level.priority >= config.minimumLogLevel.priority else {
            return
        }

        let fileName = URL(fileURLWithPath: file).lastPathComponent
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let categoryPrefix = category.map { "[\($0)] " } ?? ""

        let logMessage = "[\(level.rawValue)] \(timestamp) \(fileName):\(line) \(function) - \(categoryPrefix)\(message)"

        // Console logging
        if config.enableConsoleLogging {
            self.log(level: level.osLogType, "\(logMessage)")
        }

        // File logging
        if config.enableFileLogging {
            Task {
                await writeToLogFile(logMessage)
            }
        }
    }

    /// Write a message to the log file asynchronously
    private func writeToLogFile(_ message: String) async {
        let logFile = Logger.logFileURL
        let logLine = message + "\n"

        guard let data = logLine.data(using: .utf8) else { return }

        do {
            if FileManager.default.fileExists(atPath: logFile.path) {
                let fileHandle = try FileHandle(forWritingTo: logFile)
                defer { try? fileHandle.close() }
                fileHandle.seekToEndOfFile()
                fileHandle.write(data)
            } else {
                try data.write(to: logFile, options: .atomic)
            }
        } catch {
            // Silently fail - don't crash the app due to logging issues
            NSLog("Failed to write to log file: \(error)")
        }
    }

    // MARK: - Convenience Methods

    public func debug(
        _ message: String,
        category: String? = nil,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(message, level: .debug, category: category, file: file, function: function, line: line)
    }

    public func info(
        _ message: String,
        category: String? = nil,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(message, level: .info, category: category, file: file, function: function, line: line)
    }

    public func warning(
        _ message: String,
        category: String? = nil,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(message, level: .warning, category: category, file: file, function: function, line: line)
    }

    public func error(
        _ message: String,
        category: String? = nil,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(message, level: .error, category: category, file: file, function: function, line: line)
    }

    public func critical(
        _ message: String,
        category: String? = nil,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(message, level: .critical, category: category, file: file, function: function, line: line)
    }

    // MARK: - Legacy Compatibility

    /// Write a message to the log file (legacy method)
    @available(*, deprecated, message: "Use log() with level parameter instead")
    public static func logToFile(_ message: String, level: String = "INFO") {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let logLine = "[\(timestamp)] [\(level)] \(message)\n"

        guard let data = logLine.data(using: .utf8) else { return }

        do {
            if FileManager.default.fileExists(atPath: logFileURL.path) {
                let fileHandle = try FileHandle(forWritingTo: logFileURL)
                fileHandle.seekToEndOfFile()
                fileHandle.write(data)
                try fileHandle.close()
            } else {
                try data.write(to: logFileURL)
            }
        } catch {
            NSLog("Failed to write to log file: \(error)")
        }
    }

    /// Enhanced logging that writes to both console and file (legacy method)
    @available(*, deprecated, message: "Use log() with LogLevel instead")
    public func logWithFile(_ message: String, level: OSLogType = .info) {
        let levelString: String
        switch level {
        case .debug: levelString = "DEBUG"
        case .info: levelString = "INFO"
        case .error: levelString = "ERROR"
        case .fault: levelString = "FAULT"
        default: levelString = "DEFAULT"
        }

        // Console log
        self.log(level: level, "\(message)")

        // File log
        Logger.logToFile(message, level: levelString)
    }
}
