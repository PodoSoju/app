//
//  LogSettingsView.swift
//  PodoSoju
//
//  Created on 2026-01-08.
//

import SwiftUI
import PodoSojuKit
import os.log

struct LogSettingsView: View {
    @ObservedObject private var logConfig = LogConfig.shared

    var body: some View {
        Form {
            Section("Logging Options") {
                Toggle("Enable File Logging", isOn: $logConfig.enableFileLogging)
                    .help("Write logs to a file on disk")

                Toggle("Enable Console Logging", isOn: $logConfig.enableConsoleLogging)
                    .help("Output logs to the system console")

                Picker("Minimum Log Level", selection: $logConfig.minimumLogLevel) {
                    ForEach(LogLevel.allCases, id: \.self) { level in
                        Text(level.rawValue).tag(level)
                    }
                }
                .help("Only log messages at or above this level")
            }

            Section("Log File") {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Log File Location")
                            .font(.headline)
                        Text(Logger.logFileURL.path(percentEncoded: false))
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                            .truncationMode(.middle)
                    }

                    Spacer()

                    Button("Open in Finder") {
                        openLogFile()
                    }
                    .buttonStyle(.borderedProminent)
                }

                Button("Clear Logs") {
                    clearLogs()
                }
                .buttonStyle(.bordered)
                .foregroundColor(.red)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 500, minHeight: 300)
    }

    // MARK: - Actions

    private func openLogFile() {
        let logFile = Logger.logFileURL

        // Create empty log file if it doesn't exist
        if !FileManager.default.fileExists(atPath: logFile.path) {
            try? "".write(to: logFile, atomically: true, encoding: .utf8)
        }

        // Open Finder and select the log file
        NSWorkspace.shared.activateFileViewerSelecting([logFile])
    }

    private func clearLogs() {
        let logFile = Logger.logFileURL

        do {
            // Remove existing log file
            if FileManager.default.fileExists(atPath: logFile.path) {
                try FileManager.default.removeItem(at: logFile)
            }

            // Create new empty log file
            try "".write(to: logFile, atomically: true, encoding: .utf8)

            Logger.podoSojuKit.info("🗑️ Logs cleared", category: "LogSettings")
        } catch {
            Logger.podoSojuKit.error("Failed to clear logs: \(error.localizedDescription)", category: "LogSettings")
        }
    }
}

// MARK: - Preview

#Preview {
    LogSettingsView()
        .frame(width: 600, height: 400)
}
