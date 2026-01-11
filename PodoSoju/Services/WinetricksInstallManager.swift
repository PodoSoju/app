//
//  WinetricksInstallManager.swift
//  PodoSoju
//
//  Created on 2026-01-11.
//

import Foundation
import SwiftUI

/// Installation status for individual winetricks component.
enum InstallStatus: Equatable {
    case idle
    case downloading(percent: Int)
    case installing
    case success
    case failed(String)
}

/// Shared manager for winetricks component installation status.
/// Persists installation status across view lifecycle (window close/reopen).
@MainActor
class WinetricksInstallManager: ObservableObject {
    static let shared = WinetricksInstallManager()

    /// Per-workspace component installation statuses.
    /// Structure: [workspaceId: [componentId: InstallStatus]]
    @Published var statuses: [String: [String: InstallStatus]] = [:]

    private init() {}

    /// Get installation status for a specific component in a workspace.
    func getStatus(workspace: String, component: String) -> InstallStatus {
        statuses[workspace]?[component] ?? .idle
    }

    /// Set installation status for a specific component in a workspace.
    func setStatus(workspace: String, component: String, status: InstallStatus) {
        if statuses[workspace] == nil {
            statuses[workspace] = [:]
        }
        statuses[workspace]?[component] = status
    }

    /// Clear all statuses for a workspace (e.g., when workspace is deleted).
    func clearStatuses(workspace: String) {
        statuses.removeValue(forKey: workspace)
    }
}
