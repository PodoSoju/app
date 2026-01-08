//
//  Workspace.swift
//  SojuKit
//
//  Created on 2026-01-07.
//

import Foundation
import SwiftUI
import AppKit
import os.log

public final class Workspace: ObservableObject, Equatable, Hashable, Identifiable, Comparable {
    // MARK: - Properties

    /// Workspace directory URL
    public let url: URL

    /// Metadata file URL
    public let metadataURL: URL

    /// Workspace settings
    @Published public var settings: WorkspaceSettings {
        didSet { saveSettings() }
    }

    /// Running programs in this workspace
    @Published public var programs: [Program] = []

    /// Whether workspace is currently running
    @Published public var isRunning: Bool = false

    /// Whether workspace is available (metadata exists)
    public var isAvailable: Bool = false

    // MARK: - Computed Properties

    /// Wine prefix URL (drive_c directory)
    public var winePrefixURL: URL {
        return url.appending(path: "drive_c")
    }

    /// Wine prefix path as String
    public var winePrefixPath: String {
        return url.path(percentEncoded: false)
    }

    // MARK: - Initialization

    public init(workspaceUrl: URL, isRunning: Bool = false, isAvailable: Bool = false) {
        let metadataURL = workspaceUrl
            .appending(path: "Metadata")
            .appendingPathExtension("plist")

        self.url = workspaceUrl
        self.isRunning = isRunning
        self.isAvailable = isAvailable
        self.metadataURL = metadataURL

        do {
            self.settings = try WorkspaceSettings.decode(from: metadataURL)
        } catch {
            Logger.sojuKit.error(
                "Failed to load settings for workspace `\(metadataURL.path(percentEncoded: false))`: \(error)"
            )
            self.settings = WorkspaceSettings()
        }
    }

    // MARK: - Methods

    /// Save workspace settings to disk
    private func saveSettings() {
        do {
            try settings.encode(to: self.metadataURL)
        } catch {
            Logger.sojuKit.error(
                "Failed to encode settings for workspace `\(self.metadataURL.path(percentEncoded: false))`: \(error)"
            )
        }
    }

    /// Get Wine environment variables for this workspace
    public func wineEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["WINEPREFIX"] = winePrefixPath

        // Add workspace-specific environment variables
        settings.environmentVariables(wineEnv: &env)

        return env
    }

    // MARK: - Equatable

    public static func == (lhs: Workspace, rhs: Workspace) -> Bool {
        return lhs.url == rhs.url
    }

    // MARK: - Hashable

    public func hash(into hasher: inout Hasher) {
        return hasher.combine(url)
    }

    // MARK: - Identifiable

    public var id: URL {
        self.url
    }

    // MARK: - Comparable

    public static func < (lhs: Workspace, rhs: Workspace) -> Bool {
        lhs.settings.name.lowercased() < rhs.settings.name.lowercased()
    }
}

// MARK: - Program

/// Represents a Windows program that can be executed in a workspace
@MainActor
public class Program: Identifiable, Hashable, ObservableObject {
    public let id: UUID
    public let name: String
    public let url: URL // Path to .exe file
    public let icon: NSImage?

    /// Whether the program is currently running
    @Published public private(set) var isRunning: Bool = false

    /// Process output stream
    @Published public private(set) var output: [String] = []

    /// Process exit code (nil if still running)
    @Published public private(set) var exitCode: Int32?

    public init(id: UUID = UUID(), name: String, url: URL, icon: NSImage? = nil) {
        self.id = id
        self.name = name
        self.url = url
        self.icon = icon
    }

    /// Run this program in the specified workspace
    public func run(in workspace: Workspace) async throws {
        let executionId = UUID().uuidString.prefix(8)
        let category = "Program[\(executionId)]"

        Logger.sojuKit.info("🚀 Program execution started", category: category)
        Logger.sojuKit.debug("Program: \(self.name)", category: category)
        Logger.sojuKit.debug("URL: \(self.url.path(percentEncoded: false))", category: category)
        Logger.sojuKit.debug("Workspace: \(workspace.settings.name)", category: category)

        guard !isRunning else {
            Logger.sojuKit.warning("⚠️ Program already running, ignoring request", category: category)
            return
        }

        await MainActor.run {
            self.isRunning = true
            self.exitCode = nil
            self.output = []
            
            // Add test output to verify the mechanism works
            self.output.append("🧪 Test: Wine execution starting...")
            self.output.append("Program: \(self.name)")
            self.output.append("File: \(self.url.path(percentEncoded: false))")
            
            Logger.sojuKit.debug("✅ Test output added to array, count: \(self.output.count)", category: category)
        }
        Logger.sojuKit.debug("✅ State updated: isRunning=true", category: category)

        do {
            let podoSoju = PodoSojuManager.shared
            Logger.sojuKit.debug("📦 PodoSojuManager acquired", category: category)

            // Direct execution without 'start' - runs in foreground and captures output
            let wineArgs = [self.url.path(percentEncoded: false)]
            Logger.sojuKit.debug("🍷 Wine args: \(wineArgs)", category: category)

            for await processOutput in try podoSoju.runWine(args: wineArgs, workspace: workspace) {
                switch processOutput {
                case .message(let message):
                    Logger.sojuKit.debug("📤 Output: \(message)", category: category)
                    await MainActor.run {
                        self.output.append(message)
                    }
                case .error(let error):
                    Logger.sojuKit.error("❌ Error: \(error)", category: category)
                    await MainActor.run {
                        self.output.append("ERROR: \(error)")
                    }
                case .terminated(let code):
                    Logger.sojuKit.info("🏁 Terminated with code \(code)", category: category)
                    await MainActor.run {
                        self.isRunning = false
                        self.exitCode = code
                    }
                    if code == 0 {
                        Logger.sojuKit.info("✅ Program completed successfully", category: category)
                    } else {
                        Logger.sojuKit.error("⚠️ Program exited with error code \(code)", category: category)
                    }
                case .started:
                    Logger.sojuKit.info("▶️ Process started", category: category)
                }
            }
        } catch {
            Logger.sojuKit.critical("💥 Fatal error: \(error.localizedDescription)", category: category)
            Logger.sojuKit.debug("Error details: \(String(reflecting: error))", category: category)

            await MainActor.run {
                self.isRunning = false
                self.exitCode = 1
            }

            throw error
        }
    }

    // MARK: - Equatable

    nonisolated public static func == (lhs: Program, rhs: Program) -> Bool {
        return lhs.id == rhs.id
    }

    // MARK: - Hashable

    nonisolated public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Preview Support

#if DEBUG
extension Workspace {
    public static var preview: Workspace {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("PreviewWorkspace")
        let workspace = Workspace(workspaceUrl: tempURL, isRunning: false, isAvailable: true)
        workspace.settings.name = "Preview Workspace"
        workspace.settings.icon = "desktopcomputer"
        return workspace
    }
}
#endif
