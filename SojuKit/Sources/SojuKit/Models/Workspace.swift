//
//  Workspace.swift
//  SojuKit
//
//  Created on 2026-01-07.
//

import Foundation
import SwiftUI
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

// MARK: - Program (Placeholder)

/// Placeholder for Program model (to be implemented)
public struct Program: Identifiable, Hashable {
    public let id: UUID
    public let name: String
    public let url: URL

    public init(id: UUID = UUID(), name: String, url: URL) {
        self.id = id
        self.name = name
        self.url = url
    }
}
