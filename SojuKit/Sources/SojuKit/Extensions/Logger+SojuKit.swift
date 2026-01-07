//
//  Logger+SojuKit.swift
//  SojuKit
//
//  Created on 2026-01-07.
//

import Foundation
import os.log

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

    /// Write a message to the log file
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
            // Silently fail - don't crash the app due to logging issues
            NSLog("Failed to write to log file: \(error)")
        }
    }

    /// Enhanced logging that writes to both console and file
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
