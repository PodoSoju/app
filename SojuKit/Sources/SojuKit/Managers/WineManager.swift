//
//  WineManager.swift
//  SojuKit
//
//  Created on 2026-01-07.
//

import Foundation
import os.log

/// Manages Wine executable and process execution
@MainActor
public final class WineManager {
    public static let shared = WineManager()

    // MARK: - Properties

    /// Path to Wine installation directory
    public let wineInstallPath: URL

    /// Path to wine64 binary
    public var wine64Binary: URL {
        wineInstallPath.appending(path: "wine64")
    }

    /// Path to wineserver binary
    public var wineserverBinary: URL {
        wineInstallPath.appending(path: "wineserver")
    }

    // MARK: - Initialization

    private init() {
        // Default Wine installation path (customize as needed)
        // This should point to where Whisky Wine is installed
        let libraryURL = FileManager.default.urls(
            for: .libraryDirectory,
            in: .userDomainMask
        )[0]

        self.wineInstallPath = libraryURL
            .appending(path: "Application Support")
            .appending(path: "com.isaacmarovitz.Whisky")
            .appending(path: "Libraries")
            .appending(path: "Wine")
            .appending(path: "bin")

        Logger.sojuKit.info("Wine binary path: \(self.wine64Binary.path)")
    }

    // MARK: - Execution

    /// Execute a Windows program using Wine
    /// - Parameters:
    ///   - program: URL to the .exe file
    ///   - environment: Environment variables (must include WINEPREFIX)
    ///   - workingDirectory: Working directory for the process
    /// - Returns: AsyncStream of output lines
    public func execute(
        program: URL,
        environment: [String: String],
        workingDirectory: URL
    ) async throws -> AsyncStream<String> {
        guard FileManager.default.fileExists(atPath: wine64Binary.path(percentEncoded: false)) else {
            Logger.sojuKit.error("Wine binary not found at: \(self.wine64Binary.path)")
            throw WineManagerError.wineNotFound
        }

        guard FileManager.default.fileExists(atPath: program.path(percentEncoded: false)) else {
            Logger.sojuKit.error("Program not found: \(program.path)")
            throw WineManagerError.programNotFound
        }

        Logger.sojuKit.info("Executing: \(program.lastPathComponent)")
        Logger.sojuKit.debug("Working directory: \(workingDirectory.path)")
        Logger.sojuKit.debug("WINEPREFIX: \(environment["WINEPREFIX"] ?? "not set")")

        return AsyncStream { continuation in
            Task {
                do {
                    let process = Process()
                    process.executableURL = wine64Binary
                    process.arguments = [
                        "start",
                        "/unix",
                        program.path(percentEncoded: false)
                    ]
                    process.currentDirectoryURL = workingDirectory
                    process.environment = environment
                    process.qualityOfService = .userInitiated

                    // Setup output pipes
                    let outputPipe = Pipe()
                    let errorPipe = Pipe()
                    process.standardOutput = outputPipe
                    process.standardError = errorPipe

                    // Read output asynchronously
                    let outputHandle = outputPipe.fileHandleForReading
                    let errorHandle = errorPipe.fileHandleForReading

                    outputHandle.readabilityHandler = { handle in
                        if let data = handle.availableData as Data?, !data.isEmpty,
                           let line = String(data: data, encoding: .utf8) {
                            continuation.yield(line)
                        }
                    }

                    errorHandle.readabilityHandler = { handle in
                        if let data = handle.availableData as Data?, !data.isEmpty,
                           let line = String(data: data, encoding: .utf8) {
                            continuation.yield("[ERROR] \(line)")
                        }
                    }

                    // Start process
                    try process.run()
                    Logger.sojuKit.info("Process started: PID \(process.processIdentifier)")

                    // Wait for completion
                    process.waitUntilExit()

                    // Clean up handlers
                    outputHandle.readabilityHandler = nil
                    errorHandle.readabilityHandler = nil

                    let exitCode = process.terminationStatus
                    Logger.sojuKit.info("Process terminated with code: \(exitCode)")

                    if exitCode != 0 {
                        continuation.yield("Process exited with code: \(exitCode)")
                    }

                    continuation.finish()
                } catch {
                    Logger.sojuKit.error("Execution failed: \(error.localizedDescription)")
                    continuation.finish()
                }
            }
        }
    }

    /// Kill all Wine processes for a specific WINEPREFIX
    /// - Parameter winePrefix: Path to the wine prefix
    public func killWineServer(winePrefix: String) async throws {
        let process = Process()
        process.executableURL = wineserverBinary
        process.arguments = ["-k"]
        process.environment = ["WINEPREFIX": winePrefix]

        Logger.sojuKit.info("Killing wineserver for: \(winePrefix)")

        try process.run()
        process.waitUntilExit()

        Logger.sojuKit.info("Wineserver killed")
    }

    /// Check if Wine is installed and accessible
    /// - Returns: True if Wine binary exists
    public func isWineInstalled() -> Bool {
        return FileManager.default.fileExists(
            atPath: wine64Binary.path(percentEncoded: false)
        )
    }

    /// Get Wine version
    /// - Returns: Wine version string
    public func wineVersion() async throws -> String {
        let process = Process()
        process.executableURL = wine64Binary
        process.arguments = ["--version"]

        let pipe = Pipe()
        process.standardOutput = pipe

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else {
            throw WineManagerError.invalidOutput
        }

        var version = output.trimmingCharacters(in: .whitespacesAndNewlines)
        version = version.replacingOccurrences(of: "wine-", with: "")

        return version
    }
}

// MARK: - Errors

public enum WineManagerError: LocalizedError {
    case wineNotFound
    case programNotFound
    case invalidOutput
    case executionFailed(String)

    public var errorDescription: String? {
        switch self {
        case .wineNotFound:
            return "Wine binary not found. Please install Whisky Wine first."
        case .programNotFound:
            return "Windows program not found."
        case .invalidOutput:
            return "Invalid Wine output."
        case .executionFailed(let message):
            return "Execution failed: \(message)"
        }
    }
}
