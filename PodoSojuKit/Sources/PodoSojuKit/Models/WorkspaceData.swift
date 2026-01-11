//
//  WorkspaceData.swift
//  PodoSojuKit
//
//  Created on 2026-01-07.
//

import Foundation
import SemanticVersion

public struct WorkspaceData: Codable {
    // MARK: - Storage Paths

    public static let containerDir = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: "Library")
        .appending(path: "Containers")
        .appending(path: "com.podosoju.app")  // Bundle ID

    public static let workspaceEntriesFile = containerDir
        .appending(path: "WorkspaceEntries")
        .appendingPathExtension("plist")

    public static let defaultWorkspacesDir = containerDir
        .appending(path: "Workspaces")

    static let currentVersion = SemanticVersion(1, 0, 0)

    // MARK: - Properties

    private var fileVersion: SemanticVersion

    /// Array of workspace directory URLs
    public var workspacePaths: [URL] = [] {
        didSet {
            encode()
        }
    }

    // MARK: - Initialization

    public init() {
        fileVersion = Self.currentVersion

        if !decode() {
            encode()
        }
    }

    // MARK: - Methods

    /// Load all workspaces from stored paths
    public mutating func loadWorkspaces() -> [Workspace] {
        var workspaces: [Workspace] = []

        for path in workspacePaths {
            let metadataPath = path
                .appending(path: "Metadata")
                .appendingPathExtension("plist")
                .path(percentEncoded: false)

            if FileManager.default.fileExists(atPath: metadataPath) {
                workspaces.append(Workspace(workspaceUrl: path, isAvailable: true))
            } else {
                workspaces.append(Workspace(workspaceUrl: path, isAvailable: false))
            }
        }

        return workspaces
    }

    // MARK: - Decoding

    @discardableResult
    private mutating func decode() -> Bool {
        let decoder = PropertyListDecoder()
        do {
            let data = try Data(contentsOf: Self.workspaceEntriesFile)
            self = try decoder.decode(WorkspaceData.self, from: data)
            if self.fileVersion != Self.currentVersion {
                print("Invalid file version \(self.fileVersion)")
                return false
            }
            return true
        } catch {
            return false
        }
    }

    // MARK: - Encoding

    @discardableResult
    private func encode() -> Bool {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml

        do {
            try FileManager.default.createDirectory(
                at: Self.containerDir,
                withIntermediateDirectories: true
            )
            let data = try encoder.encode(self)
            try data.write(to: Self.workspaceEntriesFile)
            return true
        } catch {
            return false
        }
    }
}
