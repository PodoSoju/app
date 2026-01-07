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
    private let metadataURL: URL

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
        guard !isRunning else {
            Logger.sojuKit.warning("Program \(self.name) is already running")
            return
        }

        await MainActor.run {
            self.isRunning = true
            self.exitCode = nil
            self.output = []
        }

        Logger.sojuKit.info("Starting program: \(self.name) at \(self.url.path)")

        do {
            let podoSoju = PodoSojuManager.shared

            for await processOutput in try podoSoju.runWine(
                args: ["start", "/unix", self.url.path(percentEncoded: false)],
                workspace: workspace
            ) {
                switch processOutput {
                case .message(let message):
                    await MainActor.run {
                        self.output.append(message)
                    }
                case .error(let error):
                    await MainActor.run {
                        self.output.append("ERROR: \(error)")
                    }
                case .terminated(let code):
                    await MainActor.run {
                        self.isRunning = false
                        self.exitCode = code
                    }
                    if code == 0 {
                        Logger.sojuKit.info("Program \(self.name) completed successfully")
                    } else {
                        Logger.sojuKit.error("Program \(self.name) exited with code \(code)")
                    }
                case .started:
                    Logger.sojuKit.info("Program \(self.name) started")
                }
            }
        } catch {
            await MainActor.run {
                self.isRunning = false
                self.exitCode = 1
            }

            Logger.sojuKit.error("Program \(self.name) failed: \(error.localizedDescription)")
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
