//
//  PodoSojuKit.swift
//  PodoSojuKit
//
//  Created on 2026-01-07.
//

import Foundation

/// PodoSojuKit - Core framework for Soju macOS app
///
/// # Overview
/// PodoSojuKit provides workspace management for Wine-based Windows environments on macOS.
/// Each workspace represents an independent Windows PC environment.
///
/// # Key Components
/// - `Workspace`: Individual Windows PC environment with Wine prefix
/// - `WorkspaceSettings`: Configuration for Wine, graphics, and programs
/// - `WorkspaceManager`: Singleton for managing multiple workspaces
/// - `WorkspaceData`: Persistent storage of workspace locations
///
/// # Usage
/// ```swift
/// import PodoPodoSojuKit
///
/// let manager = WorkspaceManager.shared
/// manager.loadWorkspaces()
///
/// // Create new workspace
/// let workspace = try await manager.createWorkspace(
///     name: "Gaming PC",
///     icon: "gamecontroller.fill",
///     windowsVersion: .win10
/// )
///
/// // Select workspace
/// manager.selectWorkspace(workspace)
/// ```
public struct PodoSojuKit {
    public static let version = "1.0.0"

    public init() {}
}

// MARK: - Public Exports
// All types are automatically exported from their source files
