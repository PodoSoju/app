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

        // Ensure CJK fonts are installed for each workspace
        Task {
            for workspace in allWorkspaces {
                await ensureFontsInstalled(workspace: workspace)
            }
        }

        // If only one workspace exists, select it automatically
        if allWorkspaces.count == 1 {
            currentWorkspace = allWorkspaces.first
        }
        // If multiple workspaces exist, currentWorkspace remains nil
        // (user must select from WorkspaceSelectionView)
    }

    /// Ensure CJK fonts are installed in a workspace
    /// - Parameter workspace: Target workspace to check
    private func ensureFontsInstalled(workspace: Workspace) async {
        let fontsDir = workspace.winePrefixURL.appending(path: "windows/Fonts")
        let testFont = fontsDir.appending(path: "AppleGothic.ttf")

        // Skip if already installed
        if FileManager.default.fileExists(atPath: testFont.path) {
            return
        }

        // Install fonts
        do {
            try PodoSojuManager.shared.installCJKFonts(workspace: workspace)
            Logger.sojuKit.info("CJK fonts installed for existing workspace: \(workspace.settings.name)", category: "WorkspaceManager")
        } catch {
            Logger.sojuKit.warning("Failed to install CJK fonts for workspace \(workspace.settings.name): \(error.localizedDescription)", category: "WorkspaceManager")
        }
    }

    // MARK: - Workspace CRUD

    /// Create a new workspace
    public func createWorkspace(
        name: String,
        icon: String = "desktopcomputer",
        windowsVersion: WinVersion = .win10
    ) async throws -> Workspace {
        let startTime = Date()
        Logger.sojuKit.info("🏗️ [1/6] Creating workspace: '\(name)'", category: "WorkspaceManager")
        Logger.sojuKit.debug("    ├─ Icon: '\(icon)'", category: "WorkspaceManager")
        Logger.sojuKit.debug("    ├─ Windows version: '\(windowsVersion)'", category: "WorkspaceManager")
        Logger.sojuKit.debug("    └─ Base directory: \(WorkspaceData.defaultWorkspacesDir.path())", category: "WorkspaceManager")

        // 1. Create workspace directory
        let workspaceURL = WorkspaceData.defaultWorkspacesDir
            .appending(path: UUID().uuidString)

        Logger.sojuKit.info("📁 [2/6] Creating workspace directory...", category: "WorkspaceManager")
        Logger.sojuKit.debug("    └─ Path: \(workspaceURL.path())", category: "WorkspaceManager")

        try FileManager.default.createDirectory(
            at: workspaceURL,
            withIntermediateDirectories: true
        )
        Logger.sojuKit.info("    ✅ Directory created", category: "WorkspaceManager")

        // 2. Initialize Wine prefix
        Logger.sojuKit.info("🍷 [3/6] Initializing Wine prefix with wineboot...", category: "WorkspaceManager")
        Logger.sojuKit.debug("    ├─ WINEPREFIX: \(workspaceURL.path())", category: "WorkspaceManager")
        Logger.sojuKit.debug("    └─ This may take 10-20 seconds", category: "WorkspaceManager")

        let tempWorkspace = Workspace(workspaceUrl: workspaceURL, isAvailable: true)
        do {
            let winebootStart = Date()
            try await PodoSojuManager.shared.runWineboot(workspace: tempWorkspace)
            let winebootDuration = Date().timeIntervalSince(winebootStart)

            // Verify Wine prefix structure
            let driveCPath = workspaceURL.appending(path: "drive_c")
            let dosdevicesPath = workspaceURL.appending(path: "dosdevices")
            let driveCExists = FileManager.default.fileExists(atPath: driveCPath.path())
            let dosdevicesExists = FileManager.default.fileExists(atPath: dosdevicesPath.path())

            Logger.sojuKit.info("    ✅ Wine prefix initialized in \(String(format: "%.1f", winebootDuration))s", category: "WorkspaceManager")
            Logger.sojuKit.debug("    ├─ drive_c: \(driveCExists ? "✓" : "✗")", category: "WorkspaceManager")
            Logger.sojuKit.debug("    └─ dosdevices: \(dosdevicesExists ? "✓" : "✗")", category: "WorkspaceManager")

            if !driveCExists || !dosdevicesExists {
                Logger.sojuKit.warning("    ⚠️  Incomplete Wine prefix structure", category: "WorkspaceManager")
            }

            // Install CJK fonts for Korean/Japanese/Chinese support
            Logger.sojuKit.info("🔤 [3.5/6] Installing CJK fonts...", category: "WorkspaceManager")
            do {
                try PodoSojuManager.shared.installCJKFonts(workspace: tempWorkspace)
                Logger.sojuKit.info("    ✅ CJK fonts installed", category: "WorkspaceManager")
            } catch {
                // Font installation failure is non-fatal - log warning but continue
                Logger.sojuKit.warning("    ⚠️  CJK font installation failed: \(error.localizedDescription)", category: "WorkspaceManager")
            }
        } catch {
            Logger.sojuKit.error("    ❌ Failed to initialize Wine prefix: \(error)", category: "WorkspaceManager")
            Logger.sojuKit.error("    └─ Cleaning up workspace directory", category: "WorkspaceManager")
            try? FileManager.default.removeItem(at: workspaceURL)
            throw error
        }

        // 3. Create metadata
        Logger.sojuKit.info("💾 [4/6] Creating workspace metadata...", category: "WorkspaceManager")
        var settings = WorkspaceSettings()
        settings.name = name
        settings.icon = icon
        settings.windowsVersion = windowsVersion

        let metadataURL = workspaceURL
            .appending(path: "Metadata")
            .appendingPathExtension("plist")

        Logger.sojuKit.debug("    └─ Saving to: \(metadataURL.path())", category: "WorkspaceManager")
        try settings.encode(to: metadataURL)
        Logger.sojuKit.info("    ✅ Metadata saved", category: "WorkspaceManager")

        // 4. Register in WorkspaceData
        Logger.sojuKit.info("📝 [5/6] Registering workspace in WorkspaceData...", category: "WorkspaceManager")
        var data = WorkspaceData()
        data.workspacePaths.append(workspaceURL)
        Logger.sojuKit.info("    ✅ Registered (\(data.workspacePaths.count) total workspaces)", category: "WorkspaceManager")

        // 5. Create and return Workspace object
        let workspace = Workspace(workspaceUrl: workspaceURL, isAvailable: true)

        // 6. Reload workspaces
        Logger.sojuKit.info("🔄 [6/6] Reloading workspace list...", category: "WorkspaceManager")
        await MainActor.run {
            loadWorkspaces()
        }
        Logger.sojuKit.info("    ✅ Workspaces reloaded", category: "WorkspaceManager")

        let totalDuration = Date().timeIntervalSince(startTime)
        Logger.sojuKit.info("🎉 Workspace '\(name)' created successfully in \(String(format: "%.1f", totalDuration))s", category: "WorkspaceManager")
        Logger.sojuKit.debug("    └─ UUID: \(workspace.id)", category: "WorkspaceManager")

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
        Logger.sojuKit.info("🎯 Selecting workspace: '\(workspace.settings.name)'", category: "WorkspaceManager")
        Logger.sojuKit.debug("Workspace URL: \(workspace.url.path(percentEncoded: false))", category: "WorkspaceManager")

        currentWorkspace = workspace
        Logger.sojuKit.debug("✅ currentWorkspace updated", category: "WorkspaceManager")

        // Get Wine environment variables
        let env = workspace.wineEnvironment()
        Logger.sojuKit.debug("🌍 Wine environment variables:", category: "WorkspaceManager")

        // Log Wine-related environment variables
        for (key, value) in env.sorted(by: { $0.key < $1.key }) {
            if key.starts(with: "WINE") || key == "WINEPREFIX" {
                Logger.sojuKit.debug("  \(key)=\(value)", category: "WorkspaceManager")
            }
        }

        Logger.sojuKit.info("🚀 Ready to launch programs in workspace", category: "WorkspaceManager")
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
