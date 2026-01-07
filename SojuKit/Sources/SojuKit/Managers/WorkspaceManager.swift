//
//  WorkspaceManager.swift
//  SojuKit
//
//  Created on 2026-01-07.
//

import Foundation
import SwiftUI
import os.log

@MainActor
public class WorkspaceManager: ObservableObject {
    // MARK: - Singleton

    public static let shared = WorkspaceManager()

    // MARK: - Published Properties

    /// All available workspaces
    @Published public var allWorkspaces: [Workspace] = []

    /// Currently active workspace
    @Published public var currentWorkspace: Workspace?

    /// Convenience property for accessing workspaces
    public var workspaces: [Workspace] {
        allWorkspaces
    }

    // MARK: - Initialization

    private init() {
        loadWorkspaces()
    }

    // MARK: - Workspace Loading

    /// Load all workspaces from WorkspaceData
    public func loadWorkspaces() {
        var data = WorkspaceData()
        allWorkspaces = data.loadWorkspaces()

        // If only one workspace exists, select it automatically
        if allWorkspaces.count == 1 {
            currentWorkspace = allWorkspaces.first
        }
        // If multiple workspaces exist, currentWorkspace remains nil
        // (user must select from WorkspaceSelectionView)
    }

    // MARK: - Workspace CRUD

    /// Create a new workspace
    public func createWorkspace(
        name: String,
        icon: String = "desktopcomputer",
        windowsVersion: WinVersion = .win10
    ) async throws -> Workspace {
        Logger.sojuKit.logWithFile("Creating workspace: '\(name)' with icon '\(icon)' and Windows version '\(windowsVersion)'", level: .info)

        // 1. Create workspace directory
        let workspaceURL = WorkspaceData.defaultWorkspacesDir
            .appending(path: UUID().uuidString)

        try FileManager.default.createDirectory(
            at: workspaceURL,
            withIntermediateDirectories: true
        )
        Logger.sojuKit.logWithFile("Workspace directory created at: \(workspaceURL.path())", level: .debug)

        // 2. Initialize Wine prefix (placeholder - actual Wine integration needed)
        // This would be:
        // - Wine binary execution
        // - wineboot --init
        // - environment setup
        Logger.sojuKit.logWithFile("Wine prefix initialization would happen here for: \(workspaceURL.path())", level: .info)

        // 3. Create metadata
        var settings = WorkspaceSettings()
        settings.name = name
        settings.icon = icon
        settings.windowsVersion = windowsVersion

        let metadataURL = workspaceURL
            .appending(path: "Metadata")
            .appendingPathExtension("plist")
        try settings.encode(to: metadataURL)
        Logger.sojuKit.logWithFile("Workspace metadata saved to: \(metadataURL.path())", level: .debug)

        // 4. Register in WorkspaceData
        var data = WorkspaceData()
        data.workspacePaths.append(workspaceURL)

        // 5. Create and return Workspace object
        let workspace = Workspace(workspaceUrl: workspaceURL, isAvailable: true)

        // 6. Reload workspaces
        await MainActor.run {
            loadWorkspaces()
        }

        Logger.sojuKit.logWithFile("Workspace '\(name)' created successfully", level: .info)
        return workspace
    }

    /// Delete a workspace
    public func deleteWorkspace(_ workspace: Workspace) throws {
        // 1. Remove from WorkspaceData
        var data = WorkspaceData()
        data.workspacePaths.removeAll { $0 == workspace.url }

        // 2. Delete from filesystem
        try FileManager.default.removeItem(at: workspace.url)

        // 3. Reload workspaces
        loadWorkspaces()
    }

    /// Select a workspace as current
    public func selectWorkspace(_ workspace: Workspace) {
        Logger.sojuKit.logWithFile("Selecting workspace: '\(workspace.settings.name)'", level: .info)
        currentWorkspace = workspace

        // Get Wine environment variables
        let env = workspace.wineEnvironment()

        // Launch Windows Explorer (placeholder - actual Wine integration needed)
        Logger.sojuKit.logWithFile("Would launch Explorer with environment: \(env)", level: .info)
    }

    // MARK: - Program Management

    /// Refresh programs list for a workspace
    public func refreshPrograms(for workspace: Workspace) async {
        // Placeholder for program scanning logic
        Logger.sojuKit.info("Would scan programs for workspace: \(workspace.settings.name)")
    }

    /// Pin a program to workspace
    public func pinProgram(_ program: Program, to workspace: Workspace) {
        let pinnedProgram = PinnedProgram(name: program.name, url: program.url)
        workspace.settings.pinnedPrograms.append(pinnedProgram)
    }

    /// Unpin a program from workspace
    public func unpinProgram(_ program: Program, from workspace: Workspace) {
        workspace.settings.pinnedPrograms.removeAll { $0.url == program.url }
    }
}
